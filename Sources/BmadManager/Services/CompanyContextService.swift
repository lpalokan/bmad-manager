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

/// Scans projects for company contexts and copies one into a new project.
///
/// The resolution order inside each project mirrors the
/// company-context-bootstrap workflow's own rules: prefer
/// `_bmad-output/company-context`, fall back to a top-level
/// `company-context`. A project counts as having a context when at least
/// one of `CompanyContext.recognizedFileNames` is present there.
struct CompanyContextService {
    private static let contextSubpaths = [
        "_bmad-output/company-context",
        "company-context",
    ]

    /// Lists every context found in the immediate subfolders of the
    /// projects root, sorted by project name. Missing or unreadable roots
    /// yield an empty list.
    func scanContexts(inProjectsRoot rootPath: String) -> [CompanyContext] {
        let expanded = (rootPath as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let contexts: [CompanyContext] = entries.compactMap { projectURL in
            let values = try? projectURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory ?? false else { return nil }
            return context(inProject: projectURL)
        }
        return contexts.sorted {
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
                    files: present
                )
            }
        }
        return nil
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
