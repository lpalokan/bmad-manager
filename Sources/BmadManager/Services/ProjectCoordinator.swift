import Foundation
import AppKit

/// Owns the state machine for project lifecycle actions (create, delete,
/// launch terminal, open folder). Extracted from `ContentView` so every
/// coordination flow is testable without XCUITest.
///
/// Dependencies are injected — the `runCommand` closure and
/// `TerminalLauncherProtocol` let tests supply fakes instead of spawning
/// real `Process` instances. A single `ProjectService` is shared with
/// `ProjectCreator`, eliminating the duplicate wiring noted in #23.
@MainActor
final class ProjectCoordinator: ObservableObject {
    // MARK: - Published state

    @Published var projects: [ProjectItem] = []
    @Published var availableContexts: [CompanyContext] = []
    @Published var isCreating: Bool = false
    @Published var isUpdating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showOutput: Bool = false
    @Published var projectToDelete: ProjectItem? = nil
    /// URLs of projects whose installed module version is behind the repo's
    /// latest. Populated by `checkForUpdates`; the row shows an Update button
    /// when its URL is in this set. A parallel set (rather than a field on
    /// `ProjectItem`) keeps the model — whose identity is its URL — clean.
    @Published var updateAvailable: Set<URL> = []

    // MARK: - Dependencies

    private let projectService: ProjectService
    private let contextService: CompanyContextService
    private let projectCreator: ProjectCreator
    private let projectUpdater: ProjectUpdater
    private let moduleSourceFor: (AppSettings) -> ModuleSource
    private let terminalLauncher: any TerminalLauncherProtocol
    private let appLauncher: any AppLauncherProtocol

    // MARK: - Init

    /// The coordinator deliberately does NOT capture a `SettingsStore` or
    /// a `runCommand` closure at init. Both flow in per-call from the
    /// `ContentView`, which reads them off its own `@EnvironmentObject`
    /// bindings — the same instances SwiftUI manages and the Picker
    /// writes to. Capturing them here would re-introduce the
    /// `@StateObject` init-dance drift that caused the Terminal-vs-iTerm2,
    /// projects-root-doesn't-reindex, and empty-output-panel bugs.
    ///
    /// `moduleSourceFor` is a pure `(AppSettings) -> ModuleSource` factory,
    /// not a captured store or `runCommand`, so it doesn't reintroduce that
    /// drift — it's the same shape `ProjectCreator` already accepts, and lets
    /// the create/update/check flows share an injected fake in tests.
    init(terminalLauncher: any TerminalLauncherProtocol = DefaultTerminalLauncher(),
         appLauncher: any AppLauncherProtocol = DefaultAppLauncher(),
         moduleSourceFor: @escaping (AppSettings) -> ModuleSource = ModuleSourceFactory.make) {
        self.terminalLauncher = terminalLauncher
        self.appLauncher = appLauncher
        self.moduleSourceFor = moduleSourceFor

        let projectService = ProjectService()
        let contextService = CompanyContextService()
        self.projectService = projectService
        self.contextService = contextService
        self.projectCreator = ProjectCreator(
            projectService: projectService,
            contextService: contextService,
            moduleSourceFor: moduleSourceFor
        )
        self.projectUpdater = ProjectUpdater(
            projectService: projectService,
            moduleSourceFor: moduleSourceFor
        )
    }

    // MARK: - Actions

    /// Refreshes the project list from the on-disk projects folder.
    ///
    /// Both `root` and `sortOrder` are taken from the caller rather than
    /// read off `settings.settings.*` so the coordinator can't drift out
    /// of sync with the View's `SettingsStore`. (See the matching note on
    /// `openInTerminal` — same root cause: the App's @StateObject init
    /// dance can hand us a SettingsStore reference that's a different
    /// instance from the one the View's @EnvironmentObject binds to.)
    func refresh(
        root: String,
        sortOrder: ProjectSortOrder,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        projects = projectService.listProjects(in: root, sortedBy: sortOrder)
        let projectContexts = contextService.contexts(in: projects)
        let githubContexts = discoveredGithubContexts(home: home)
        // Shared repo contexts first, then project-local ones — both groups
        // already sorted by name.
        availableContexts = githubContexts + projectContexts
    }

    /// Reads contexts from the skills repo clone (the `context/` folder
    /// alongside `skills/`). Both tools clone the same repo into their own
    /// hidden dir, so we use whichever clone is present.
    private func discoveredGithubContexts(home: URL) -> [CompanyContext] {
        for tool in SkillTool.allCases {
            let repo = SkillsSyncService.managedRepoDir(for: tool, home: home)
            let contexts = contextService.githubContexts(inRepoRoot: repo)
            if !contexts.isEmpty { return contexts }
        }
        return []
    }

    /// Creates a new project using the supplied settings snapshot and
    /// `runCommand`. The caller is responsible for prompting the user
    /// for a missing module zip path and persisting any update back into
    /// the SettingsStore before calling — that prompt is pure UI
    /// concern, and centralising it in the View also avoids the
    /// stale-store hazard the App's @StateObject init dance used to
    /// trigger.
    func createProject(
        name: String,
        settings: AppSettings,
        importContextFrom context: CompanyContext? = nil,
        destination: URL? = nil,
        runCommand: @escaping (String, URL) async -> Int32
    ) async {
        isCreating = true
        showOutput = true
        defer { isCreating = false }

        do {
            try await projectCreator.create(
                name: name,
                settings: settings,
                importingContextFrom: context,
                destination: destination,
                runCommand: runCommand
            )
            errorMessage = nil
            refresh(root: settings.projectsRoot, sortOrder: settings.projectSortOrder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-installs the latest module over an existing project and refreshes
    /// its managed AGENTS.md blocks. Mirrors `createProject`'s shape (flags,
    /// error surfacing, refresh) but uses a distinct `isUpdating` flag so the
    /// per-row Update spinner doesn't tangle with the create button's state.
    /// After a successful update the stale set is recomputed so the project's
    /// badge clears.
    func updateProject(
        _ project: ProjectItem,
        settings: AppSettings,
        runCommand: @escaping (String, URL) async -> Int32
    ) async {
        isUpdating = true
        showOutput = true
        defer { isUpdating = false }

        do {
            try await projectUpdater.update(
                project: project,
                settings: settings,
                runCommand: runCommand
            )
            errorMessage = nil
            refresh(root: settings.projectsRoot, sortOrder: settings.projectSortOrder)
            await checkForUpdates(settings: settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Recomputes which projects are behind the module repo. Materialises the
    /// configured repo once (one network op, source-agnostic), reads its
    /// `module_version`, then flags each project whose installed manifest
    /// version is older. Best-effort: any failure (offline, git missing,
    /// unreadable repo) clears the set rather than surfacing an error — a
    /// version check shouldn't nag. Reads `projects`, so call after `refresh`.
    func checkForUpdates(settings: AppSettings) async {
        let source = moduleSourceFor(settings)
        let repoModule = try? await source.withModuleRoot { moduleRoot, _ in
            ModuleManifest.readRepoModule(atModuleRoot: moduleRoot)
        }
        guard let repoModule = repoModule.flatMap({ $0 }) else {
            updateAvailable = []
            return
        }
        let stale = projects.filter {
            ModuleManifest.isProjectStale(projectURL: $0.url, repoModule: repoModule)
        }
        updateAvailable = Set(stale.map(\.url))
    }

    func deleteProject(
        _ project: ProjectItem,
        root: String,
        sortOrder: ProjectSortOrder
    ) async {
        do {
            try await projectService.trash(project)
            refresh(root: root, sortOrder: sortOrder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openProjectFolder(_ project: ProjectItem) {
        NSWorkspace.shared.open(project.url)
    }

    /// Opens `command` in a new terminal session at the project's path.
    ///
    /// `kind` is taken from the caller rather than read off
    /// `settings.settings.terminalKind` so the coordinator can't drift out
    /// of sync with the View's `SettingsStore`. The View already binds to
    /// the `@EnvironmentObject` instance SwiftUI manages, and that
    /// instance is the one the Picker writes to — passing the kind through
    /// at call time guarantees we honour what the user just chose, even on
    /// the very first click after a change.
    func openInTerminal(
        project: ProjectItem,
        command: String,
        kind: TerminalKind,
        placement: NewSessionPlacement = .newWindow
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Command is empty. Set it in Settings."
            return
        }
        do {
            try terminalLauncher.open(
                projectPath: project.url.path,
                command: trimmed,
                kind: kind,
                placement: placement
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Launches `agent` for `project`, honouring the user's per-agent
    /// [[AgentLaunchMethod]]: open the desktop app or run the CLI in the
    /// terminal.
    ///
    /// `appInstalled` is supplied by the caller (the View queries
    /// [[AppDetector]] at click time) rather than read here, so the
    /// coordinator stays free of `NSWorkspace` and the resolution policy
    /// is unit-testable. `command` and `kind` are threaded through for the
    /// CLI path for the same no-stale-store reason as `openInTerminal`.
    func openAgent(
        project: ProjectItem,
        agent: AgentApp,
        method: AgentLaunchMethod,
        appInstalled: Bool,
        command: String,
        kind: TerminalKind,
        placement: NewSessionPlacement = .newWindow
    ) {
        switch AgentLaunchResolver.resolve(method: method, appInstalled: appInstalled) {
        case .app:
            do {
                try appLauncher.open(
                    bundleIdentifier: agent.bundleIdentifier,
                    projectPath: project.url.path
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        case .cli:
            openInTerminal(project: project, command: command, kind: kind, placement: placement)
        }
    }

    /// Syncs the configured skills repo into `tool`'s global `managed/`
    /// folder. `token` comes from the Keychain (read by the View at click
    /// time) and `runCommand` streams git output into the command panel —
    /// both passed in so the coordinator stays free of Keychain/Process and
    /// the policy is testable. Errors (no token/URL, git failure) surface via
    /// `errorMessage`; git's own output appears in the panel.
    func syncSkills(
        tool: SkillTool,
        settings: AppSettings,
        token: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runCommand: @escaping (String, URL) async -> Int32
    ) async {
        showOutput = true
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = SkillsSyncError.noToken.localizedDescription
            return
        }
        do {
            try await SkillsSyncService.sync(
                tool: tool,
                repoURL: settings.skillsRepoURL,
                branch: settings.skillsRepoBranch,
                token: token,
                home: home,
                runCommand: runCommand
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Auto-syncs the shared skills repo for every tool, then re-discovers
    /// contexts so the picker reflects the repo's `context/` folder. Driven
    /// by app startup and the Refresh button.
    ///
    /// Silent when the repo URL or token isn't configured — a fresh install
    /// shouldn't nag — but a real git failure surfaces via `errorMessage`.
    /// The local project list and any already-cloned contexts still refresh
    /// either way. Unlike the manual sync buttons this does NOT force the
    /// output panel open; git output still streams there if the user opens it.
    func syncSkillsRepo(
        settings: AppSettings,
        token: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runCommand: @escaping (String, URL) async -> Int32
    ) async {
        let url = settings.skillsRepoURL.trimmingCharacters(in: .whitespaces)
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !trimmedToken.isEmpty else {
            refresh(
                root: settings.projectsRoot,
                sortOrder: settings.projectSortOrder,
                home: home
            )
            return
        }

        var failure: String? = nil
        for tool in SkillTool.allCases {
            do {
                try await SkillsSyncService.sync(
                    tool: tool,
                    repoURL: url,
                    branch: settings.skillsRepoBranch,
                    token: trimmedToken,
                    home: home,
                    runCommand: runCommand
                )
            } catch {
                failure = error.localizedDescription
            }
        }
        errorMessage = failure
        refresh(
            root: settings.projectsRoot,
            sortOrder: settings.projectSortOrder,
            home: home
        )
    }
}
