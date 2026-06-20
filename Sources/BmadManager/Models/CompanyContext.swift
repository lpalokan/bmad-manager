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
/// seeds a set of canonical files under `_bmad-output/company-context/`
/// (every v2 agent reads them on activation), but a user is free to drop
/// additional files into that folder. The manager scans the projects folder
/// — and the skills repo's top-level `context/` folder — and treats *every*
/// file there as part of the context, so a new project can be seeded with
/// the complete folder instead of starting from scratch.
struct CompanyContext: Identifiable, Hashable {
    /// The canonical file names the bootstrap workflow seeds, in display
    /// order. These are sorted to the front of a context's file list for a
    /// stable picker; any extra files the user added follow alphabetically.
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
    /// All files present in the source: canonical names first, then extras.
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

    /// Menu label: the source name with a trailing source marker.
    var displayName: String {
        "\(projectName) \(source.marker)"
    }
}
