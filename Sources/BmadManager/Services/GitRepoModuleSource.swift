import Foundation

enum GitError: LocalizedError {
    case noRepoURLConfigured
    case gitNotAvailable(String)
    case cloneFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRepoURLConfigured:    return "No GitHub repository URL is configured."
        case .gitNotAvailable(let m): return "git is not available: \(m). Install Xcode Command Line Tools (xcode-select --install) or pick a local zip in Settings."
        case .cloneFailed(let m):     return "git clone failed: \(m)"
        }
    }
}

/// `ModuleSource` adapter that materialises the module by shallow-cloning
/// a git repository into a fresh temp directory. The clone root *is* the
/// module root — no wrapper descent needed (unlike GitHub "Download ZIP"
/// archives, which add a wrapper folder).
///
/// The clone is still produced for post-install steps that read the module
/// tree, but the value handed to `bmad-method --custom-source` is the repo
/// **URL** (not the temp path) so the installer records `repoUrl` + `sha` +
/// a real version rather than a throwaway local path with version `"main"`.
struct GitRepoModuleSource: ModuleSource {
    /// What the installer will be told to install, and whether that will make
    /// it record a real version.
    ///
    /// `bmad-method` records whatever ref it is handed as the module's version
    /// in the project manifest. A bare URL or a branch ref makes it stamp
    /// `main`, which the staleness check can never compare against a real
    /// semver — so the project is flagged as needing an update forever and
    /// re-running Update rewrites the same `main`. `pinnedRef` is nil for
    /// exactly those cases, and `note` says so in the output panel instead of
    /// letting it happen silently.
    struct InstallerSource: Equatable {
        /// The `--custom-source` value.
        let arg: String
        /// The ref the install will record as the module version, or nil when
        /// it will not record a usable one.
        let pinnedRef: String?
        /// User-facing diagnostic for the output panel.
        let note: String
    }

    /// Holds the resolution so reading `resolutionNote` and materialising the
    /// module don't each pay for their own `ls-remote`.
    final class ResolutionCache {
        var value: InstallerSource?
        init() {}
    }

    let url: String
    let ref: String
    /// Runs `git ls-remote --tags --refs <url>` and returns stdout, or nil on
    /// any failure (offline, git missing). Injectable so tests resolve the
    /// installer source without touching the network.
    var lsRemoteTags: (String) -> String? = GitRepoModuleSource.realLsRemoteTags
    let cache = ResolutionCache()

    /// What this source will install, resolved once per instance.
    var resolution: InstallerSource {
        if let cached = cache.value { return cached }
        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)
        let tags = trimmedRef.isEmpty ? lsRemoteTags(url) : nil
        let resolved = Self.describeInstallerSource(url: url, ref: ref, tagsOutput: tags)
        cache.value = resolved
        return resolved
    }

    var resolutionNote: String? { resolution.note }

    func withModuleRoot<T>(
        _ body: (_ moduleRoot: URL, _ installerSource: String) async throws -> T
    ) async throws -> T {
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else {
            throw GitError.noRepoURLConfigured
        }

        let resolved = resolution
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-\(UUID().uuidString)", isDirectory: true)
        // Clone the ref the install will pin, so the module read here and the
        // version the installer records are the same one. Cloning the default
        // branch instead reports a version nothing will ever install as soon as
        // the repo's `main` runs ahead of its newest tag.
        try GitRepoModuleSource.clone(url: trimmedURL, ref: resolved.pinnedRef ?? ref, into: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        return try await body(tmpDir, resolved.arg)
    }

    // MARK: - Installer source resolution

    /// The `--custom-source` value for this repo. With an explicit `ref` it is
    /// `<url>@<ref>` (the installer pins that branch/tag and records it as the
    /// module version). With no ref the configured URL carries no version, so
    /// we resolve the repo's **latest semver tag** and pin to it — the
    /// installer otherwise stamps the literal `"main"` for a bare URL. Falls
    /// back to the bare URL when no semver tag can be discovered.
    static func installerSource(
        url: String, ref: String, lsRemoteTags: (String) -> String?
    ) -> String {
        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)
        let tags = trimmedRef.isEmpty ? lsRemoteTags(url) : nil
        return describeInstallerSource(url: url, ref: ref, tagsOutput: tags).arg
    }

    /// Resolves what to install from the configured URL and ref, given the
    /// repo's `git ls-remote --tags --refs` output (nil when it could not be
    /// read). Pure — the network call lives in `resolution`.
    static func describeInstallerSource(
        url: String, ref: String, tagsOutput: String?
    ) -> InstallerSource {
        let base = baseURL(url)
        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)

        // An explicit ref is always honoured — it is a deliberate choice in
        // Settings — but a branch name is still reported, because that is what
        // it will land in the manifest as.
        if !trimmedRef.isEmpty {
            let arg = pinnedURL(base, ref: trimmedRef)
            if isSemverShaped(trimmedRef) {
                return InstallerSource(
                    arg: arg,
                    pinnedRef: trimmedRef,
                    note: "module source: \(base) pinned to \(trimmedRef) (from Settings)")
            }
            return InstallerSource(
                arg: arg,
                pinnedRef: nil,
                note: """
                    module source: \(base) pinned to \(trimmedRef) (from Settings), which is \
                    not a version tag — the install records it as the module version, so this \
                    project will keep showing an update. Clear the module repo ref in Settings \
                    to install the latest tag instead.
                    """)
        }

        guard let output = tagsOutput else {
            return InstallerSource(
                arg: base,
                pinnedRef: nil,
                note: """
                    module source: could not list the version tags of \(base) (offline, git \
                    missing, or no stored credentials for a private repo) — installing from \
                    the default branch, which the install records as version 'main', so the \
                    project will keep showing an update.
                    """)
        }

        guard let tag = latestSemverTag(inLsRemote: output) else {
            return InstallerSource(
                arg: base,
                pinnedRef: nil,
                note: """
                    module source: \(base) publishes no version tags — installing from the \
                    default branch, which the install records as version 'main', so the \
                    project will keep showing an update.
                    """)
        }
        return InstallerSource(
            arg: pinnedURL(base, ref: tag),
            pinnedRef: tag,
            note: "module source: \(base) pinned to latest tag \(tag)")
    }

    /// `<url>@<ref>` with any trailing slash on the URL stripped first.
    /// `bmad-method` parses the `@<ref>` suffix as the version to pin.
    static func pinnedURL(_ url: String, ref: String) -> String {
        return "\(baseURL(url))@\(ref)"
    }

    /// Highest semver-shaped tag name (original form, e.g. `v2.0.2`) parsed
    /// from `git ls-remote --tags --refs` output, or nil when none qualify.
    static func latestSemverTag(inLsRemote output: String) -> String? {
        var best: String?
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            // Each line is "<sha>\trefs/tags/<name>" (--refs drops peeled tags).
            guard let tabIndex = rawLine.firstIndex(of: "\t") else { continue }
            let refPart = rawLine[rawLine.index(after: tabIndex)...]
            let prefix = "refs/tags/"
            guard refPart.hasPrefix(prefix) else { continue }
            let tag = String(refPart.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard isSemverShaped(tag) else { continue }
            if let current = best {
                if ModuleManifest.isOlder(current, than: tag) { best = tag }
            } else {
                best = tag
            }
        }
        return best
    }

    private static func baseURL(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespaces)
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    /// A tag counts as a version only if, after dropping a leading `v`/`V`, it
    /// has at least one dot-separated numeric component (so `latest`, `nightly`
    /// and similar non-version tags are ignored).
    private static func isSemverShaped(_ tag: String) -> Bool {
        var v = tag
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        guard !v.isEmpty else { return false }
        return v.split(separator: ".").contains { Int($0) != nil }
    }

    static func realLsRemoteTags(_ url: String) -> String? {
        guard let outcome = try? Subprocess.run(
            "/usr/bin/env", arguments: ["git", "ls-remote", "--tags", "--refs", url]
        ), outcome.status == 0 else {
            return nil
        }
        return outcome.stdout
    }

    // MARK: - Internals

    static func clone(url: String, ref: String, into dir: URL) throws {
        // Empty ref → follow the repo's default branch.
        var args = ["clone", "--depth", "1"]
        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)
        if !trimmedRef.isEmpty {
            args.append(contentsOf: ["--branch", trimmedRef])
        }
        args.append(url)
        args.append(dir.path)

        let outcome: Subprocess.Outcome
        do {
            outcome = try Subprocess.run("/usr/bin/env", arguments: ["git"] + args)
        } catch {
            throw GitError.gitNotAvailable(error.localizedDescription)
        }

        if outcome.status != 0 {
            try? FileManager.default.removeItem(at: dir)
            throw GitError.cloneFailed(outcome.failureMessage)
        }
    }
}
