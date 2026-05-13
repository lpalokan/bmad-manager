import Foundation

enum ProjectSortOrder: String, Codable, CaseIterable {
    case nameAscending
    case dateNewestFirst
    case dateOldestFirst

    var displayName: String {
        switch self {
        case .nameAscending:     return "Name (A→Z)"
        case .dateNewestFirst:   return "Date created (newest first)"
        case .dateOldestFirst:   return "Date created (oldest first)"
        }
    }

    /// Comparator suitable for `Array.sorted(by:)`. Projects without a
    /// known creation date sort last in date-based orderings.
    func areInIncreasingOrder(_ lhs: ProjectItem, _ rhs: ProjectItem) -> Bool {
        switch self {
        case .nameAscending:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .dateNewestFirst:
            let ld = lhs.createdAt ?? .distantPast
            let rd = rhs.createdAt ?? .distantPast
            return ld > rd
        case .dateOldestFirst:
            let ld = lhs.createdAt ?? .distantFuture
            let rd = rhs.createdAt ?? .distantFuture
            return ld < rd
        }
    }
}

struct AppSettings: Codable, Equatable {
    var projectsRoot: String
    var moduleZipPath: String
    var initCommand: String
    var claudeCommand: String
    var opencodeCommand: String
    var projectSortOrder: ProjectSortOrder

    static func defaults() -> AppSettings {
        // Headless BMad install per docs.bmad-method.org/how-to/install-bmad
        // (--yes for non-interactive, --modules for the always-on set,
        // --tools for IDE configuration, --directory for the target).
        // Always installs the BMad Method core (bmm), BMad Builder (bmb),
        // and Creative Intelligence Suite (cis), and registers the unzipped
        // marketing growth bundle via `--custom-source` so its modules show
        // up as proper BMad modules (not just files dropped on the project).
        //
        // If you upgrade an existing install, hit "Reset to defaults" in
        // Settings so the persisted command picks up these flags.
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleZipPath: "",
            initCommand: "npx bmad-method install --yes --modules bmm,bmb,cis --tools claude-code,opencode --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )
    }

    // MARK: - Codable (custom to keep legacy settings.json files readable)

    private enum CodingKeys: String, CodingKey {
        case projectsRoot
        case moduleZipPath
        case initCommand
        case claudeCommand
        case opencodeCommand
        case projectSortOrder
    }

    init(projectsRoot: String,
         moduleZipPath: String,
         initCommand: String,
         claudeCommand: String,
         opencodeCommand: String,
         projectSortOrder: ProjectSortOrder = .nameAscending) {
        self.projectsRoot = projectsRoot
        self.moduleZipPath = moduleZipPath
        self.initCommand = initCommand
        self.claudeCommand = claudeCommand
        self.opencodeCommand = opencodeCommand
        self.projectSortOrder = projectSortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectsRoot     = try c.decode(String.self, forKey: .projectsRoot)
        moduleZipPath    = try c.decode(String.self, forKey: .moduleZipPath)
        initCommand      = try c.decode(String.self, forKey: .initCommand)
        claudeCommand    = try c.decode(String.self, forKey: .claudeCommand)
        opencodeCommand  = try c.decode(String.self, forKey: .opencodeCommand)
        // New in #12 — fall back to the default when reading a legacy file
        // so a freshly upgraded install doesn't fail to load its settings.
        projectSortOrder = try c.decodeIfPresent(ProjectSortOrder.self, forKey: .projectSortOrder) ?? .nameAscending
    }
}
