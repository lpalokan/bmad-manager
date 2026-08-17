import Foundation

enum ContextImportError: LocalizedError {
    case copyFailed(file: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let file, let underlying):
            return "Copying '\(file)' failed: \(underlying.localizedDescription)"
        }
    }
}

/// Resolves company contexts inside projects and copies one into a new
/// project.
///
/// The resolution order inside each project mirrors the
/// company-context-bootstrap workflow's own rules: prefer
/// `output/company-context` (the canonical marketing-growth layout since
/// v2.4), then the legacy `_bmad-output/company-context`, then a top-level
/// `company-context`. A project counts as having a context when its context
/// folder holds at least one file — every file is part of the context, not
/// just the five canonical names, so user-added files seed across too.
///
/// Reading is deliberately broad and writing is not: a seeded context always
/// lands in `output/company-context` (see `importContext`), so new projects
/// start on the canonical name while projects on either older layout keep
/// resolving in place. Nothing is ever moved.
///
/// Walking the projects folder is deliberately NOT this module's job —
/// `ProjectService.listProjects` is the one place that knows what counts
/// as a project folder; callers hand the resulting `ProjectItem`s in.
/// What a `refreshContext` run changed, for the output panel.
struct RefreshSummary: Equatable {
    var written: [String] = []
    var backedUp: [String] = []
}

/// Where a project's company-context stands against the skills repo. A
/// four-state answer rather than a boolean, because "resolved and matching"
/// and "I cannot tell which pack this came from" are different facts that used
/// to be reported identically as `context=current` — the silent wrong answer
/// that hid a real drift for a whole release (issue #105).
enum ContextStatus: Equatable {
    /// The project carries no company-context at all.
    case noContext
    /// It has one, but no published pack could be identified as its upstream,
    /// so there is nothing to compare it against.
    case noUpstream
    /// Resolved to a pack and matching it.
    case current
    /// Resolved to a pack and behind it.
    case drift

    /// The word the update-check line prints.
    var label: String {
        switch self {
        case .noContext: return "no-context"
        case .noUpstream: return "no-upstream"
        case .current: return "current"
        case .drift: return "drift"
        }
    }

    /// Only actual drift lights the Update button. An unresolved upstream is
    /// visible in the log instead — there is nothing a refresh could do with it.
    var needsUpdate: Bool { self == .drift }
}

struct CompanyContextService {
    /// Every layout a context is read from, canonical first. The first entry
    /// is also the one `importContext` writes to.
    private static let contextSubpaths = [
        "output/company-context",
        "_bmad-output/company-context",
        "company-context",
    ]

    /// Resolves the context of each given project, sorted by project name
    /// (the picker's order, independent of the caller's project sort).
    func contexts(in projects: [ProjectItem]) -> [CompanyContext] {
        projects
            .compactMap { context(inProject: $0.url) }
            .sorted {
                $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
            }
    }

    /// Returns the context found in a single project folder, or nil when
    /// none of the expected locations holds any context files.
    func context(inProject projectURL: URL) -> CompanyContext? {
        for subpath in Self.contextSubpaths {
            let dir = projectURL.appendingPathComponent(subpath, isDirectory: true)
            let present = contextFiles(in: dir)
            if !present.isEmpty {
                return CompanyContext(
                    projectName: projectURL.lastPathComponent,
                    directoryURL: dir,
                    files: present,
                    source: .project
                )
            }
        }
        return nil
    }

    /// Resolves the contexts published in the shared skills repo's top-level
    /// `context/` folder (a sibling of the `skills/` folder). Each immediate
    /// subdirectory holding at least one file is offered as a seeding source,
    /// tagged `.github`. Sorted by name.
    func githubContexts(inRepoRoot repoRoot: URL) -> [CompanyContext] {
        let contextRoot = repoRoot.appendingPathComponent("context", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: contextRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .compactMap { dir -> CompanyContext? in
                let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                guard isDir else { return nil }
                let present = contextFiles(in: dir)
                guard !present.isEmpty else { return nil }
                return CompanyContext(
                    projectName: dir.lastPathComponent,
                    directoryURL: dir,
                    files: present,
                    source: .github
                )
            }
            .sorted {
                $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
            }
    }

    /// Lists every file in a context folder, recursing into subfolders: the
    /// recognized top-level names first in canonical order (so the seed
    /// picker stays stable and predictable), then any other files — including
    /// nested ones — by relative path alphabetically. Paths are relative to
    /// `dir` with "/" separators (e.g. "research/notes.md"). Hidden files and
    /// hidden directories are skipped. Returns an empty array when `dir`
    /// doesn't exist or holds no files.
    private func contextFiles(in dir: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Resolve symlinks on both the base and each entry so the prefix
        // matches: the enumerator canonicalises paths (e.g. /var →
        // /private/var) while `dir` may not, which would otherwise break the
        // relative-path computation.
        let basePath = dir.resolvingSymlinksInPath().path
        var relPaths: [String] = []
        for case let url as URL in enumerator {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile ?? false
            guard isRegular else { continue }
            let fullPath = url.resolvingSymlinksInPath().path
            guard fullPath.hasPrefix(basePath + "/") else { continue }
            relPaths.append(String(fullPath.dropFirst(basePath.count + 1)))
        }

        let recognized = CompanyContext.recognizedFileNames.filter(relPaths.contains)
        let extras = relPaths
            .filter { !CompanyContext.recognizedFileNames.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return recognized + extras
    }

    /// Copies all of the context's files into
    /// `<projectURL>/output/company-context/` — the canonical layout,
    /// whichever layout the source used. Files already present at the
    /// destination are left untouched — the manager never overwrites
    /// silently (the bootstrap workflow's behavioural contract);
    /// re-running the workflow in the new project handles refreshes
    /// interactively.
    func importContext(_ context: CompanyContext, into projectURL: URL) throws {
        let destDir = projectURL
            .appendingPathComponent("output", isDirectory: true)
            .appendingPathComponent("company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        for file in context.files {
            let destination = destDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            do {
                // Recreate the file's subfolder (e.g. "research/") before
                // copying, so nested context files land at the same relative
                // path in the new project.
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(
                    at: context.directoryURL.appendingPathComponent(file),
                    to: destination
                )
            } catch {
                throw ContextImportError.copyFailed(file: file, underlying: error)
            }
        }
        // Record where these files came from, so a later drift check is a
        // lookup instead of a guess at the tags. Only meaningful for a
        // skills-repo pack — seeding from another project has no upstream.
        if context.source == .github {
            try Self.writeContextSource(context.projectName, in: destDir)
        }
    }

    // MARK: - Source marker

    /// Hidden folder inside a context holding copies of files a refresh was
    /// about to overwrite, one sub-folder per refresh. Dot-prefixed so
    /// `contextFiles` skips it — backups must never become part of the context
    /// they protect.
    static let backupDirName = ".bmad-context-backup"

    /// Hidden marker recording which skills-repo pack a context was seeded
    /// from, so resolution is a lookup rather than an inference. Also
    /// dot-prefixed, and for the same reason.
    static let sourceMarkerName = ".bmad-context-source.json"

    /// Reads the pack name recorded by `writeContextSource`, or nil when no
    /// marker is present (every project seeded before #103) or it won't parse.
    static func contextSource(in contextDir: URL) -> String? {
        guard
            let data = try? Data(contentsOf: contextDir.appendingPathComponent(sourceMarkerName)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = object["name"] as? String
        else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Records `name` as the skills-repo pack this context was seeded from.
    private static func writeContextSource(_ name: String, in contextDir: URL) throws {
        try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["name": name])
        do {
            try data.write(to: contextDir.appendingPathComponent(sourceMarkerName))
        } catch {
            throw ContextImportError.copyFailed(file: sourceMarkerName, underlying: error)
        }
    }

    // MARK: - Context drift vs the skills repo (issue #92)
    //
    // A project's company-context is seeded from a skills-repo context at
    // create time (see `importContext`) and drifts behind when the maintainer
    // edits that context. Drift is read from the OKF `last_updated` date the
    // context files carry (always bumped on edit), with a byte fallback for
    // files without a date. A project is linked back to its source context by
    // the OKF `tags` slug its own files carry, so no marker file is needed and
    // existing projects work.

    /// Resolves which of `sources` a project's context was seeded from: the
    /// marker recorded at seed/refresh time when present, otherwise a plurality
    /// vote over the OKF `tags` its own files carry, and finally — when the tags
    /// decide nothing — how much of each pack's filename set the project holds.
    /// Returns nil when every route comes back ambiguous; the project then has
    /// no upstream to refresh from (reported as `.noUpstream`, never
    /// as "current").
    func sourceContext(
        for projectContext: CompanyContext,
        in sources: [CompanyContext]
    ) -> CompanyContext? {
        guard !sources.isEmpty else { return nil }
        // A marker settles it outright. A marker naming a pack that is no
        // longer published falls through to the vote rather than giving up.
        if let name = Self.contextSource(in: projectContext.directoryURL),
            let found = sources.first(where: { $0.projectName == name })
        {
            return found
        }
        // Otherwise vote, top-level files first: a pack bundled in a sub-folder
        // carries its own identity tags and would otherwise outvote the pack
        // the project was actually seeded from.
        let topLevel = projectContext.files.filter { !$0.contains("/") }
        var votes = tally(projectContext, sources, topLevel)
        // Only when the top level named nothing at all — a context whose files
        // all live in sub-folders. A top-level *tie* is a genuine ambiguity and
        // must not be broken by letting sub-folders vote after the fact.
        if votes.isEmpty {
            votes = tally(projectContext, sources, projectContext.files)
        }
        if let best = votes.values.max() {
            let leaders = votes.filter { $0.value == best }
            // An even split is a genuine ambiguity, not a coin toss — fall
            // through to the files rather than picking one.
            if leaders.count == 1, let name = leaders.keys.first,
                let found = sources.first(where: { $0.projectName == name })
            {
                return found
            }
        }
        // The tags decided nothing — either nobody voted (a pack whose author
        // never tagged its files with its own name) or the vote split evenly.
        // The files themselves still carry the answer: a seeded project holds
        // that pack's whole filename set, and nobody else's.
        return bestByFileOverlap(projectContext, sources)
    }

    /// The share of a pack's files a project carries — the tag-independent
    /// evidence that a bundle came from that pack. A pack the project shares a
    /// single common filename (`index.md`) with scores low; the pack it was
    /// seeded from scores every one of that pack's files.
    private struct Overlap {
        let source: CompanyContext
        let matched: Int
        let total: Int

        /// Strictly larger share, compared by cross-multiplication so two packs
        /// of different sizes are ranked exactly, with no float rounding
        /// deciding an upstream.
        func beats(_ other: Overlap) -> Bool {
            matched * other.total > other.matched * total
        }

        /// Carrying more than half of a pack's files. Below that the evidence
        /// is too thin to name an upstream a refresh would then overwrite from.
        var isMajority: Bool { matched * 2 > total }
    }

    /// Resolves the source by file overlap: the pack whose filename set the
    /// project covers best, provided it covers a majority of that pack and no
    /// other pack matches it exactly. Ignores tags entirely, so a tag collision
    /// cannot break it.
    private func bestByFileOverlap(
        _ projectContext: CompanyContext,
        _ sources: [CompanyContext]
    ) -> CompanyContext? {
        let carried = Set(projectContext.files)
        let scored =
            sources
            .filter { !$0.files.isEmpty }
            .map {
                Overlap(
                    source: $0,
                    matched: $0.files.filter(carried.contains).count,
                    total: $0.files.count)
            }
            .sorted { $0.beats($1) }
        guard let best = scored.first, best.isMajority else { return nil }
        // A runner-up on the same share is the same ambiguity the tag vote hit.
        if let next = scored.dropFirst().first, !best.beats(next) { return nil }
        return best.source
    }

    /// Counts, per published pack, how many of `files` carry that pack's name
    /// as an OKF tag. A tag is a vote only when it matches a published pack, so
    /// subject keywords naming nothing published are ignored — and one file
    /// naming another vertical as its subject cannot outweigh the pack's own
    /// identity across the rest of the bundle.
    private func tally(
        _ projectContext: CompanyContext,
        _ sources: [CompanyContext],
        _ files: [String]
    ) -> [String: Int] {
        var votes: [String: Int] = [:]
        for file in files {
            let url = projectContext.directoryURL.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let tags = Set(Self.parseOkfMeta(text).tags)
            for source in sources where tags.contains(source.projectName) {
                votes[source.projectName, default: 0] += 1
            }
        }
        return votes
    }

    /// True when the project's context has drifted behind `source`: any file
    /// the source carries that the project lacks, or whose source OKF
    /// `last_updated` is a strictly later date than the project's copy. Files
    /// without a comparable date on either side fall back to a byte comparison,
    /// so an edit that didn't bump the date is still caught. Project-only files
    /// never count — refresh is overwrite+add, never delete.
    func isContextStale(_ projectContext: CompanyContext, against source: CompanyContext) -> Bool {
        for file in source.files {
            let dest = projectContext.directoryURL.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: dest.path) else { return true }
            guard
                let srcText = try? String(
                    contentsOf: source.directoryURL.appendingPathComponent(file), encoding: .utf8),
                let dstText = try? String(contentsOf: dest, encoding: .utf8)
            else { continue }
            let srcDate = Self.parseYMD(Self.parseOkfMeta(srcText).lastUpdated)
            let dstDate = Self.parseYMD(Self.parseOkfMeta(dstText).lastUpdated)
            if let srcDate, let dstDate {
                if srcDate > dstDate { return true }
            } else if srcText != dstText {
                return true
            }
        }
        return false
    }

    /// Where `projectURL`'s context stands against the skills-repo `sources`.
    /// Drives the single Update button alongside module staleness, and the
    /// diagnostic line that says why.
    ///
    /// Resolving the upstream also stamps it into the context's marker file, so
    /// a project seeded before the marker existed becomes self-describing after
    /// one successful check and never depends on the inference again.
    /// Best-effort: a read-only or otherwise unwritable context still checks
    /// normally.
    func projectContextStatus(projectURL: URL, sources: [CompanyContext]) -> ContextStatus {
        guard let projectContext = context(inProject: projectURL) else { return .noContext }
        guard let source = sourceContext(for: projectContext, in: sources) else { return .noUpstream }
        if Self.contextSource(in: projectContext.directoryURL) != source.projectName {
            try? Self.writeContextSource(source.projectName, in: projectContext.directoryURL)
        }
        return isContextStale(projectContext, against: source) ? .drift : .current
    }

    /// Overwrites `destDir`'s context with `source`'s files — copying every
    /// source file over the destination's copy and adding any it lacks, but
    /// never deleting destination-only files. The refresh counterpart to
    /// `importContext` (which skips existing files at create time): the "bring
    /// an existing project current with the skills repo" path.
    ///
    /// Every file whose content would change is copied into
    /// `<destDir>/<backupDirName>/<backupStamp>/` first, so a refresh can never
    /// destroy a local edit. `backupStamp` names that run's folder; the app
    /// passes a timestamp, tests a fixed string.
    @discardableResult
    func refreshContext(
        _ source: CompanyContext,
        into destDir: URL,
        backupStamp: String
    ) throws -> RefreshSummary {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let backupRoot = destDir
            .appendingPathComponent(Self.backupDirName, isDirectory: true)
            .appendingPathComponent(backupStamp, isDirectory: true)
        var summary = RefreshSummary()

        for file in source.files {
            let destination = destDir.appendingPathComponent(file)
            do {
                let incoming = try Data(contentsOf: source.directoryURL.appendingPathComponent(file))
                let existing = try? Data(contentsOf: destination)

                // Already identical: nothing to write, and nothing worth
                // preserving. Skipping keeps mtimes stable for a current project.
                if existing == incoming { continue }

                // Anything whose bytes are about to change is copied aside
                // first. We cannot tell a user's edit from a merely stale copy
                // without a baseline, so we preserve both — a redundant backup
                // is cheap, a lost edit is not.
                if let existing {
                    let backupPath = backupRoot.appendingPathComponent(file)
                    try FileManager.default.createDirectory(
                        at: backupPath.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try existing.write(to: backupPath)
                    summary.backedUp.append(file)
                }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try incoming.write(to: destination)
                summary.written.append(file)
            } catch {
                throw ContextImportError.copyFailed(file: file, underlying: error)
            }
        }

        // Stamp the marker so a project seeded before #103 becomes
        // self-describing the first time it is refreshed.
        try Self.writeContextSource(source.projectName, in: destDir)
        return summary
    }

    // MARK: - OKF frontmatter parsing

    private struct OkfMeta {
        var lastUpdated: String?
        var tags: [String]
    }

    /// Parses the leading `---`-fenced YAML frontmatter for just `last_updated`
    /// and `tags`. Only a `---` on the first line opens the block; parsing stops
    /// at the closing `---`. `tags` is read as a flow sequence (`[a, b, c]`), the
    /// only form OKF uses. A file without frontmatter yields empty fields.
    private static func parseOkfMeta(_ text: String) -> OkfMeta {
        var meta = OkfMeta(lastUpdated: nil, tags: [])
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return meta }
        for rawLine in lines.dropFirst() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "---" { break }
            if line.hasPrefix("last_updated:") {
                let value = unquote(String(line.dropFirst("last_updated:".count))
                    .trimmingCharacters(in: .whitespaces))
                if !value.isEmpty { meta.lastUpdated = value }
            } else if line.hasPrefix("tags:") {
                meta.tags = parseFlowList(String(line.dropFirst("tags:".count))
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        return meta
    }

    /// Splits an inline YAML flow sequence `[a, b, c]` into trimmed, unquoted,
    /// non-empty entries. A bare (non-bracketed) value becomes a single entry.
    private static func parseFlowList(_ value: String) -> [String] {
        var inner = value
        if inner.hasPrefix("["), inner.hasSuffix("]") {
            inner = String(inner.dropFirst().dropLast())
        }
        return inner
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// Parses an ISO `YYYY-MM-DD` date into a comparable tuple, or nil when it
    /// isn't exactly three numeric components.
    private static func parseYMD(_ value: String?) -> (Int, Int, Int)? {
        guard let value else { return nil }
        let parts = value.trimmingCharacters(in: .whitespaces)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return (y, m, d)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else { return value }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
