import Foundation

/// Where a discovered company context came from, used to badge the picker.
///
/// Native menus can't embed image assets, so each source gets a trailing
/// emoji marker: a folder (matching the project list's "open folder"
/// button) for project-local contexts, and an octopus standing in for the
/// GitHub octocat for contexts pulled from the shared skills repo's
/// `context/` folder.
enum CompanyContextSource: Hashable {
    case project
    case github

    var marker: String {
        switch self {
        case .project: return "📂"
        case .github:  return "🐙"
        }
    }
}

/// A company context discovered inside an existing project or in the shared
/// skills repo.
///
/// The bmad-marketing-growth module's company-context-bootstrap workflow
/// defines the shared context as five recognized files under
/// `_bmad-output/company-context/` (every v2 agent reads them on
/// activation). The manager scans the projects folder for those files — and
/// the skills repo's top-level `context/` folder — so a new project can be
/// seeded from an existing context instead of starting from scratch.
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
    /// Name of the project folder (or skills-repo `context/` subfolder) the
    /// context was found in.
    let projectName: String
    /// The context folder itself (e.g. `<project>/_bmad-output/company-context`).
    let directoryURL: URL
    /// Recognized files present in the source, in canonical order.
    let files: [String]
    /// Whether the context came from a project on disk or the skills repo.
    let source: CompanyContextSource

    init(
        projectName: String,
        directoryURL: URL,
        files: [String],
        source: CompanyContextSource = .project
    ) {
        self.id = directoryURL
        self.projectName = projectName
        self.directoryURL = directoryURL
        self.files = files
        self.source = source
    }

    /// Menu label: the source name with a trailing source marker, and a hint
    /// appended when the context is missing some of the recognized files.
    var displayName: String {
        let total = Self.recognizedFileNames.count
        let base = files.count == total
            ? projectName
            : "\(projectName) (\(files.count) of \(total) context files)"
        return "\(base) \(source.marker)"
    }
}
