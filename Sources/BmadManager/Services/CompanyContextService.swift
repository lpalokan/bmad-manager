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
/// `company-context`. A project counts as having a context when at least
/// one of `CompanyContext.recognizedFileNames` is present there.
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
    /// none of the expected locations contains a recognized file.
    func context(inProject projectURL: URL) -> CompanyContext? {
        for subpath in Self.contextSubpaths {
            let dir = projectURL.appendingPathComponent(subpath, isDirectory: true)
            let present = CompanyContext.recognizedFileNames.filter { name in
                FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
            }
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
    /// subdirectory holding at least one recognized file is offered as a
    /// seeding source, tagged `.github`. Sorted by name.
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
                let present = CompanyContext.recognizedFileNames.filter { name in
                    FileManager.default.fileExists(
                        atPath: dir.appendingPathComponent(name).path)
                }
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

    /// Copies the context's recognized files into
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
