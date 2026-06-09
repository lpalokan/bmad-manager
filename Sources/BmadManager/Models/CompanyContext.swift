import Foundation

/// A company context discovered inside an existing project.
///
/// The bmad-marketing-growth module's company-context-bootstrap workflow
/// defines the shared context as five recognized files under
/// `_bmad-output/company-context/` (every v2 agent reads them on
/// activation). The manager scans the projects folder for those files so a
/// new project can be seeded from an existing project's context instead of
/// starting from scratch.
struct CompanyContext: Identifiable, Hashable {
    /// The file names the bootstrap workflow recognizes, in canonical
    /// order. Anything else in a context folder (e.g.
    /// `bootstrap-summary.md`) is ignored, matching the workflow's own
    /// import rules.
    static let recognizedFileNames = [
        "icp.md",
        "positioning.md",
        "brand-voice.md",
        "kpis.md",
        "tech-stack.md",
    ]

    let id: URL
    /// Name of the project folder the context was found in.
    let projectName: String
    /// The context folder itself (e.g. `<project>/_bmad-output/company-context`).
    let directoryURL: URL
    /// Recognized files present in the source, in canonical order.
    let files: [String]

    init(projectName: String, directoryURL: URL, files: [String]) {
        self.id = directoryURL
        self.projectName = projectName
        self.directoryURL = directoryURL
        self.files = files
    }

    /// Menu label: the source project name, with a hint appended when the
    /// context is missing some of the recognized files.
    var displayName: String {
        let total = Self.recognizedFileNames.count
        return files.count == total
            ? projectName
            : "\(projectName) (\(files.count) of \(total) context files)"
    }
}
