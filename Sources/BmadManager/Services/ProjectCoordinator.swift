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
    @Published var errorMessage: String? = nil
    @Published var showOutput: Bool = false
    @Published var projectToDelete: ProjectItem? = nil

    // MARK: - Dependencies

    private let projectService: ProjectService
    private let contextService: CompanyContextService
    private let projectCreator: ProjectCreator
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
    init(terminalLauncher: any TerminalLauncherProtocol = DefaultTerminalLauncher(),
         appLauncher: any AppLauncherProtocol = DefaultAppLauncher()) {
        self.terminalLauncher = terminalLauncher
        self.appLauncher = appLauncher

        let projectService = ProjectService()
        let contextService = CompanyContextService()
        self.projectService = projectService
        self.contextService = contextService
        self.projectCreator = ProjectCreator(
            projectService: projectService,
            contextService: contextService
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
    func refresh(root: String, sortOrder: ProjectSortOrder) {
        projects = projectService.listProjects(in: root, sortedBy: sortOrder)
        availableContexts = contextService.contexts(in: projects)
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
                runCommand: runCommand
            )
            errorMessage = nil
            refresh(root: settings.projectsRoot, sortOrder: settings.projectSortOrder)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    func openInTerminal(project: ProjectItem, command: String, kind: TerminalKind) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Command is empty. Set it in Settings."
            return
        }
        do {
            try terminalLauncher.open(
                projectPath: project.url.path,
                command: trimmed,
                kind: kind
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
        kind: TerminalKind
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
            openInTerminal(project: project, command: command, kind: kind)
        }
    }
}
