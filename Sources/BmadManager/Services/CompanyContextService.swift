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
}
