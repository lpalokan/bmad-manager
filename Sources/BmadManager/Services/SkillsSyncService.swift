import Foundation

/// The coding tools that expose a global skills folder we can sync into.
enum SkillTool: CaseIterable {
    case claudeCode
    case codex

    /// The dotfolder under the user's home (`.claude` / `.codex`).
    var homeSubdir: String {
        switch self {
        case .claudeCode: return ".claude"
        case .codex:      return ".codex"
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }
}

enum SkillsSyncError: LocalizedError {
    case noRepoURL
    case noToken
    case gitFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noRepoURL: return "Set a skills repo URL in Settings first."
        case .noToken:   return "Set a GitHub token in Settings first."
        case .gitFailed(let code): return "git exited with code \(code). See the output panel."
        }
    }
}

/// What a reconcile did, for the output panel.
struct LinkSummary: Equatable {
    var linked: [String] = []
    var removed: [String] = []
    var skipped: [String] = []
}

/// Clones/updates a private GitHub skills repo into a hidden sibling of the
/// tool's skills folder, then **symlinks each skill as a direct child** of that
/// folder so the tool actually discovers it (Claude Code / Codex only scan one
/// level deep — a skill buried under a subfolder is never found).
///
/// We only ever create/remove links we own (tracked in a manifest); a name
/// already taken by a real personal skill directory is skipped, not
/// overwritten. Personal skills are never touched.
enum SkillsSyncService {
    // MARK: - Paths

    /// The folder the tool scans, e.g. `<home>/.claude/skills`.
    static func skillsRoot(for tool: SkillTool, home: URL) -> URL {
        home.appendingPathComponent(tool.homeSubdir, isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    /// Hidden sibling holding the cloned repo, e.g. `<home>/.claude/skills-managed`.
    static func managedRepoDir(for tool: SkillTool, home: URL) -> URL {
        home.appendingPathComponent(tool.homeSubdir, isDirectory: true)
            .appendingPathComponent("skills-managed", isDirectory: true)
    }

    /// Manifest of the link names we created (so re-syncs clean up only ours).
    static func linksManifestPath(for tool: SkillTool, home: URL) -> URL {
        home.appendingPathComponent(tool.homeSubdir, isDirectory: true)
            .appendingPathComponent(".bmad-skill-links.json")
    }

    /// The pre-link layout this feature shipped with first (a buried clone under
    /// `skills/managed`), cleaned up on the next sync.
    static func legacyManagedDir(for tool: SkillTool, home: URL) -> URL {
        skillsRoot(for: tool, home: home).appendingPathComponent("managed", isDirectory: true)
    }

    // MARK: - Git command builders (pure)

    /// The `Authorization` header git should send for `token`, passed via
    /// `-c http.extraHeader=...` so the token never lands in `.git/config`.
    static func authHeader(token: String) -> String {
        let creds = "x-access-token:\(token)"
        return "AUTHORIZATION: basic \(Data(creds.utf8).base64EncodedString())"
    }

    /// Shell command that clones the repo fresh into `dest`.
    static func cloneCommand(repoURL: String, branch: String, dest: URL, header: String) -> String {
        [
            "git",
            "-c", shellQuote("http.extraHeader=\(header)"),
            "clone", "--depth", "1", "--single-branch",
            "--branch", shellQuote(branch),
            shellQuote(repoURL),
            shellQuote(dest.path),
        ].joined(separator: " ")
    }

    /// Shell command (cwd = clone dir) that hard-updates to the latest tip.
    ///
    /// Repoints `origin` at the configured repo first. The clone is made once
    /// and every sync after that fetches `origin`, so this is the only way a
    /// repo URL changed in Settings reaches an existing clone; without it the
    /// sync reports success while still serving the previous repo's skills and
    /// contexts.
    static func updateCommand(repoURL: String, branch: String, header: String) -> String {
        let repoint = "git remote set-url origin \(shellQuote(repoURL))"
        let fetch = [
            "git",
            "-c", shellQuote("http.extraHeader=\(header)"),
            "fetch", "--depth", "1", "origin", shellQuote(branch),
        ].joined(separator: " ")
        return "\(repoint) && \(fetch) && git reset --hard FETCH_HEAD"
    }

    // MARK: - Which repo a clone points at

    /// The `origin` URL recorded in a clone's `.git/config`, or nil when the
    /// clone, the config, or the remote is missing. Read from the file rather
    /// than `git remote get-url` so choosing a clone (which happens on every
    /// context listing) costs no subprocess.
    static func originURL(ofClone clone: URL) -> String? {
        let config = clone.appendingPathComponent(".git/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        var inOrigin = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin =
                    line.replacingOccurrences(of: " ", with: "")
                    .caseInsensitiveCompare("[remote\"origin\"]") == .orderedSame
                continue
            }
            guard inOrigin, line.hasPrefix("url") else { continue }
            let value = line.dropFirst("url".count).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("=") else { continue }
            let url = value.dropFirst().trimmingCharacters(in: .whitespaces)
            if !url.isEmpty { return url }
        }
        return nil
    }

    /// Whether two remote URLs name the same repository, ignoring what git
    /// itself ignores: surrounding space, a trailing slash, a `.git` suffix,
    /// and case (GitHub owners/repos are case-insensitive).
    static func sameRemote(_ left: String, _ right: String) -> Bool {
        normalizedRemote(left) == normalizedRemote(right)
    }

    private static func normalizedRemote(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespaces)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        while value.hasSuffix("/") { value.removeLast() }
        return value.lowercased()
    }

    /// The managed clones that may be read as `configuredURL`'s content, best
    /// first: clones whose `origin` matches, then clones whose origin can't be
    /// read (made before this check existed). A clone pointing at a *different*
    /// repo is left out — serving its skills and context packs is the bug this
    /// exists to prevent. With no repo configured there is nothing to match
    /// against, so every clone is offered.
    static func clonesForRepo(home: URL, configuredURL: String) -> [URL] {
        let configured = configuredURL.trimmingCharacters(in: .whitespaces)
        var matching: [URL] = []
        var unknown: [URL] = []
        for tool in SkillTool.allCases {
            let repo = managedRepoDir(for: tool, home: home)
            // A tool that has never synced has no clone to read — offering its
            // path would just be a phantom candidate. Existence is the whole
            // test: a directory whose `.git` is missing or unreadable simply
            // reports no origin, and is then treated as an unknown one.
            guard isDirectory(repo, fileManager: .default) else { continue }
            guard !configured.isEmpty else {
                matching.append(repo)
                continue
            }
            switch originURL(ofClone: repo) {
            case .some(let origin) where sameRemote(origin, configured): matching.append(repo)
            case .some: break
            case .none: unknown.append(repo)
            }
        }
        return matching + unknown
    }

    /// POSIX single-quote quoting (end-quote / escape / re-open).
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Skill discovery & link reconciliation

    /// Where skills live inside the cloned repo: the top-level `skills/`
    /// folder when present (the layout shared with the sibling `context/`
    /// folder), else the repo root — backward-compatible with repos that
    /// keep skills directly at the top level.
    static func skillsSourceDir(in repo: URL, fileManager: FileManager = .default) -> URL {
        let sub = repo.appendingPathComponent("skills", isDirectory: true)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
            return sub
        }
        return repo
    }

    /// Immediate child directories of `repo` containing a `SKILL.md`, sorted.
    /// Hidden entries (incl. `.git`) are skipped.
    static func discoverSkills(in repo: URL, fileManager: FileManager = .default) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: repo,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var names: [String] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let hasSkill = fileManager.fileExists(
                atPath: entry.appendingPathComponent("SKILL.md").path
            )
            if isDir && hasSkill { names.append(entry.lastPathComponent) }
        }
        return names.sorted()
    }

    /// Brings `skillsRoot` in sync with the skills in `managedRepo`: removes the
    /// links we made last time, then links every current skill — skipping any
    /// name occupied by a real personal skill. Records what we own in `manifest`.
    @discardableResult
    static func reconcileLinks(
        skillsRoot: URL,
        managedRepo: URL,
        manifestPath: URL,
        fileManager: FileManager = .default
    ) throws -> LinkSummary {
        try fileManager.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        let source = skillsSourceDir(in: managedRepo, fileManager: fileManager)
        let previous = readManifest(manifestPath)
        let repoSkills = discoverSkills(in: source, fileManager: fileManager)

        // Remove every link we created last sync (clean slate). Only touch
        // entries that are actually symlinks — never a real dir.
        for name in previous {
            let link = skillsRoot.appendingPathComponent(name)
            if isSymlink(link, fileManager: fileManager) {
                try? fileManager.removeItem(at: link)
            }
        }
        let removed = previous.filter { !repoSkills.contains($0) }

        var linked: [String] = []
        var skipped: [String] = []
        for name in repoSkills {
            let link = skillsRoot.appendingPathComponent(name)
            if entryExists(link, fileManager: fileManager) {
                // Occupied after clearing our own links. Reclaim a dangling
                // leftover link (no real skill behind it); otherwise it's a
                // personal skill — leave it untouched.
                let hasSkill = fileManager.fileExists(
                    atPath: link.appendingPathComponent("SKILL.md").path
                )
                if isSymlink(link, fileManager: fileManager) && !hasSkill {
                    try? fileManager.removeItem(at: link)
                } else {
                    skipped.append(name)
                    continue
                }
            }
            try fileManager.createSymbolicLink(
                at: link,
                withDestinationURL: source.appendingPathComponent(name)
            )
            linked.append(name)
        }

        try writeManifest(manifestPath, linked)
        return LinkSummary(linked: linked, removed: removed, skipped: skipped)
    }

    // MARK: - Orchestration

    /// Clone or hard-update the skills repo for `tool`, then link its skills
    /// into the tool's skills folder. Throws on missing config or a non-zero
    /// git exit. `runCommand` streams git output into the command panel.
    static func sync(
        tool: SkillTool,
        repoURL: String,
        branch: String,
        token: String,
        home: URL,
        fileManager: FileManager = .default,
        runCommand: (String, URL) async -> Int32
    ) async throws {
        let trimmedURL = repoURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { throw SkillsSyncError.noRepoURL }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SkillsSyncError.noToken }

        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        let resolvedBranch = trimmedBranch.isEmpty ? "main" : trimmedBranch
        let header = authHeader(token: trimmedToken)
        let managedRepo = managedRepoDir(for: tool, home: home)
        let skillsRoot = skillsRoot(for: tool, home: home)
        let manifest = linksManifestPath(for: tool, home: home)

        let isRepo = isDirectory(managedRepo.appendingPathComponent(".git"), fileManager: fileManager)
        let exit: Int32
        if isRepo {
            exit = await runCommand(
                updateCommand(repoURL: trimmedURL, branch: resolvedBranch, header: header),
                managedRepo)
        } else {
            if entryExists(managedRepo, fileManager: fileManager) {
                try fileManager.removeItem(at: managedRepo)
            }
            try fileManager.createDirectory(
                at: managedRepo.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let command = cloneCommand(
                repoURL: trimmedURL,
                branch: resolvedBranch,
                dest: managedRepo,
                header: header
            )
            exit = await runCommand(command, managedRepo.deletingLastPathComponent())
        }
        if exit != 0 { throw SkillsSyncError.gitFailed(exit) }

        // Clean up the old buried-clone layout if present (links into it become
        // dangling and are reclaimed by reconcileLinks).
        let legacy = legacyManagedDir(for: tool, home: home)
        if isDirectory(legacy, fileManager: fileManager) {
            try? fileManager.removeItem(at: legacy)
        }

        try reconcileLinks(
            skillsRoot: skillsRoot,
            managedRepo: managedRepo,
            manifestPath: manifest,
            fileManager: fileManager
        )
    }

    // MARK: - Filesystem helpers

    /// True if `url` is a symlink (lstat — does not follow). Real dirs are false.
    static func isSymlink(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// True if anything exists at `url` (lstat — a dangling symlink counts).
    static func entryExists(_ url: URL, fileManager: FileManager = .default) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private struct LinkManifest: Codable {
        var links: [String]
    }

    static func readManifest(_ url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LinkManifest.self, from: data)
        else { return [] }
        return manifest.links
    }

    private static func writeManifest(_ url: URL, _ links: [String]) throws {
        let data = try JSONEncoder().encode(LinkManifest(links: links))
        try data.write(to: url)
    }
}
