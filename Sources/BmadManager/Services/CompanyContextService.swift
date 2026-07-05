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
/// `_bmad-output/company-context`, fall back to a top-level
/// `company-context`. A project counts as having a context when its context
/// folder holds at least one file — every file is part of the context, not
/// just the five canonical names, so user-added files seed across too.
///
/// Walking the projects folder is deliberately NOT this module's job —
/// `ProjectService.listProjects` is the one place that knows what counts
/// as a project folder; callers hand the resulting `ProjectItem`s in.
struct CompanyContextService {
    private static let contextSubpaths = [
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
    /// `<projectURL>/_bmad-output/company-context/`. Files already present
    /// at the destination are left untouched — the manager never
    /// overwrites silently (the bootstrap workflow's behavioural
    /// contract); re-running the workflow in the new project handles
    /// refreshes interactively.
    func importContext(_ context: CompanyContext, into projectURL: URL) throws {
        let destDir = projectURL
            .appendingPathComponent("_bmad-output", isDirectory: true)
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

    /// Resolves which of `sources` a project's context was seeded from, by
    /// matching the OKF `tags` slug embedded in the project's own files against
    /// the source context names. Returns nil when nothing matches or the match
    /// is ambiguous — the project then has no upstream to refresh from and is
    /// treated as not context-stale (module-only).
    func sourceContext(
        for projectContext: CompanyContext,
        in sources: [CompanyContext]
    ) -> CompanyContext? {
        guard !sources.isEmpty else { return nil }
        var tags = Set<String>()
        for file in projectContext.files {
            let url = projectContext.directoryURL.appendingPathComponent(file)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                tags.formUnion(Self.parseOkfMeta(text).tags)
            }
        }
        let matches = sources.filter { tags.contains($0.projectName) }
        return matches.count == 1 ? matches.first : nil
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

    /// True when `projectURL`'s context should be offered a refresh from the
    /// skills-repo `sources`: it resolves to one of them and has drifted behind
    /// it. Drives the single Update button alongside module staleness.
    func isProjectContextStale(projectURL: URL, sources: [CompanyContext]) -> Bool {
        guard let projectContext = context(inProject: projectURL) else { return false }
        guard let source = sourceContext(for: projectContext, in: sources) else { return false }
        return isContextStale(projectContext, against: source)
    }

    /// Overwrites `destDir`'s context with `source`'s files — copying every
    /// source file over the destination's copy and adding any it lacks, but
    /// never deleting destination-only files. The refresh counterpart to
    /// `importContext` (which skips existing files at create time): the "bring
    /// an existing project current with the skills repo" path.
    func refreshContext(_ source: CompanyContext, into destDir: URL) throws {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        for file in source.files {
            let destination = destDir.appendingPathComponent(file)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // copyItem refuses to overwrite, so clear an existing copy first.
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(
                    at: source.directoryURL.appendingPathComponent(file),
                    to: destination
                )
            } catch {
                throw ContextImportError.copyFailed(file: file, underlying: error)
            }
        }
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
