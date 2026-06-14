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

enum ModuleSourceKind: String, Codable, CaseIterable {
    case gitRepo
    case localZip

    var displayName: String {
        switch self {
        case .gitRepo:  return "GitHub repo"
        case .localZip: return "Local zip"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var projectsRoot: String
    var moduleSourceKind: ModuleSourceKind
    var moduleRepoURL: String
    var moduleRepoRef: String
    var moduleZipPath: String
    var initCommand: String
    var claudeCommand: String
    var opencodeCommand: String
    var piCommand: String
    var codexCommand: String
    var claudeLaunchMethod: AgentLaunchMethod
    var codexLaunchMethod: AgentLaunchMethod
    var projectSortOrder: ProjectSortOrder
    var terminalKind: TerminalKind
    /// HTTPS URL of the private skills repo synced into the global
    /// `~/.claude/skills/managed` and `~/.codex/skills/managed` folders.
    /// Empty until configured. The read-only token lives in the Keychain,
    /// never here.
    var skillsRepoURL: String
    /// Branch the skills repo is synced from (defaults to `main`).
    var skillsRepoBranch: String

    static let defaultModuleRepoURL = "https://github.com/lpalokan/bmad-marketing-growth"
    static let defaultSkillsRepoBranch = "main"

    static func defaults() -> AppSettings {
        // Headless BMad install per docs.bmad-method.org/how-to/install-bmad
        // (--yes for non-interactive, --modules for the always-on set,
        // --tools for IDE configuration, --directory for the target).
        // Always installs the BMad Method core (bmm), BMad Builder (bmb),
        // and Creative Intelligence Suite (cis), and registers the
        // marketing-growth bundle via `--custom-source` so its modules show
        // up as proper BMad modules (not just files dropped on the project).
        //
        // If you upgrade an existing install, hit "Reset to defaults" in
        // Settings so the persisted command picks up these flags.
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleSourceKind: .gitRepo,
            moduleRepoURL: AppSettings.defaultModuleRepoURL,
            moduleRepoRef: "",
            moduleZipPath: "",
            initCommand: "npx bmad-method install --yes --modules bmm,bmb,cis --tools claude-code,opencode,pi,codex --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            piCommand: "pi",
            codexCommand: "codex",
            claudeLaunchMethod: .default,
            codexLaunchMethod: .default,
            projectSortOrder: .nameAscending,
            terminalKind: .terminal,
            skillsRepoURL: "",
            skillsRepoBranch: AppSettings.defaultSkillsRepoBranch
        )
    }

    // MARK: - Codable (custom to keep legacy settings.json files readable)

    private enum CodingKeys: String, CodingKey {
        case projectsRoot
        case moduleSourceKind
        case moduleRepoURL
        case moduleRepoRef
        case moduleZipPath
        case initCommand
        case claudeCommand
        case opencodeCommand
        case piCommand
        case codexCommand
        case claudeLaunchMethod
        case codexLaunchMethod
        case projectSortOrder
        case terminalKind
        // Explicit raw value so the on-disk key matches the Tauri/Rust side
        // (`skillsRepoUrl`), keeping settings.json portable across platforms.
        case skillsRepoURL = "skillsRepoUrl"
        case skillsRepoBranch
    }

    init(projectsRoot: String,
         moduleSourceKind: ModuleSourceKind = .gitRepo,
         moduleRepoURL: String = AppSettings.defaultModuleRepoURL,
         moduleRepoRef: String = "",
         moduleZipPath: String,
         initCommand: String,
         claudeCommand: String,
         opencodeCommand: String,
         piCommand: String = "pi",
         codexCommand: String = "codex",
         claudeLaunchMethod: AgentLaunchMethod = .default,
         codexLaunchMethod: AgentLaunchMethod = .default,
         projectSortOrder: ProjectSortOrder = .nameAscending,
         terminalKind: TerminalKind = .terminal,
         skillsRepoURL: String = "",
         skillsRepoBranch: String = AppSettings.defaultSkillsRepoBranch) {
        self.projectsRoot = projectsRoot
        self.moduleSourceKind = moduleSourceKind
        self.moduleRepoURL = moduleRepoURL
        self.moduleRepoRef = moduleRepoRef
        self.moduleZipPath = moduleZipPath
        self.initCommand = initCommand
        self.claudeCommand = claudeCommand
        self.opencodeCommand = opencodeCommand
        self.piCommand = piCommand
        self.codexCommand = codexCommand
        self.claudeLaunchMethod = claudeLaunchMethod
        self.codexLaunchMethod = codexLaunchMethod
        self.projectSortOrder = projectSortOrder
        self.terminalKind = terminalKind
        self.skillsRepoURL = skillsRepoURL
        self.skillsRepoBranch = skillsRepoBranch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectsRoot     = try c.decode(String.self, forKey: .projectsRoot)
        moduleZipPath    = try c.decode(String.self, forKey: .moduleZipPath)
        initCommand      = try c.decode(String.self, forKey: .initCommand)
        claudeCommand    = try c.decode(String.self, forKey: .claudeCommand)
        opencodeCommand  = try c.decode(String.self, forKey: .opencodeCommand)
        // Pi and Codex are later additions; legacy settings.json files
        // predate them, so fall back to the bare binary names rather than
        // failing to load.
        piCommand        = try c.decodeIfPresent(String.self, forKey: .piCommand) ?? "pi"
        codexCommand     = try c.decodeIfPresent(String.self, forKey: .codexCommand) ?? "codex"
        // Per-agent App-vs-CLI launch preference. Settings files written
        // before this picker don't carry the fields — default to .auto so
        // upgrading users get the prefer-app behaviour without a load error.
        claudeLaunchMethod = try c.decodeIfPresent(AgentLaunchMethod.self, forKey: .claudeLaunchMethod) ?? .default
        codexLaunchMethod  = try c.decodeIfPresent(AgentLaunchMethod.self, forKey: .codexLaunchMethod) ?? .default
        // New in #12 — fall back to the default when reading a legacy file
        // so a freshly upgraded install doesn't fail to load its settings.
        projectSortOrder = try c.decodeIfPresent(ProjectSortOrder.self, forKey: .projectSortOrder) ?? .nameAscending

        // New module-source fields. Legacy settings.json files don't carry
        // the discriminator — infer it from `moduleZipPath` so existing
        // users keep the local-zip workflow they had configured.
        moduleRepoURL    = try c.decodeIfPresent(String.self, forKey: .moduleRepoURL) ?? AppSettings.defaultModuleRepoURL
        moduleRepoRef    = try c.decodeIfPresent(String.self, forKey: .moduleRepoRef) ?? ""
        if let kind = try c.decodeIfPresent(ModuleSourceKind.self, forKey: .moduleSourceKind) {
            moduleSourceKind = kind
        } else {
            let zipConfigured = !moduleZipPath.trimmingCharacters(in: .whitespaces).isEmpty
            moduleSourceKind = zipConfigured ? .localZip : .gitRepo
        }

        // Legacy settings.json files predate the terminal picker — default
        // to Terminal.app so upgrades keep the previous behaviour.
        terminalKind = try c.decodeIfPresent(TerminalKind.self, forKey: .terminalKind) ?? .terminal

        // Skills sync (#40) — legacy files predate these; default to an
        // unconfigured repo on `main` so loading never fails.
        skillsRepoURL = try c.decodeIfPresent(String.self, forKey: .skillsRepoURL) ?? ""
        skillsRepoBranch = try c.decodeIfPresent(String.self, forKey: .skillsRepoBranch)
            ?? AppSettings.defaultSkillsRepoBranch
    }
}
