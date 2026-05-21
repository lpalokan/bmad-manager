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
    @Published var isCreating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showOutput: Bool = false
    @Published var projectToDelete: ProjectItem? = nil

    // MARK: - Dependencies

    private let projectService: ProjectService
    private let projectCreator: ProjectCreator
    private let terminalLauncher: any TerminalLauncherProtocol
    private let settings: SettingsStore
    private let runCommand: (String, URL) async -> Int32

    // MARK: - Init

    init(
        settings: SettingsStore,
        terminalLauncher: any TerminalLauncherProtocol = DefaultTerminalLauncher(),
        runCommand: @escaping (String, URL) async -> Int32
    ) {
        self.settings = settings
        self.terminalLauncher = terminalLauncher
        self.runCommand = runCommand

        let projectService = ProjectService()
        self.projectService = projectService
        self.projectCreator = ProjectCreator(projectService: projectService)
    }

    // MARK: - Actions

    func refresh() {
        projects = projectService.listProjects(
            in: settings.settings.projectsRoot,
            sortedBy: settings.settings.projectSortOrder
        )
    }

    /// Creates a new project. The `promptForModuleZip` closure is called only
    /// when the local-zip source is configured but no path has been chosen yet.
    /// Pass `{ nil }` to skip the prompt (the caller will see an error message).
    func createProject(name: String, promptForModuleZip: () -> URL? = { nil }) async {
        let s = settings.settings

        if s.moduleSourceKind == .localZip,
           s.moduleZipPath.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let picked = promptForModuleZip() else {
                errorMessage = "A marketing growth module .zip is required to create a project."
                return
            }
            settings.settings.moduleZipPath = picked.path
        }

        isCreating = true
        showOutput = true
        defer { isCreating = false }

        do {
            try await projectCreator.create(
                name: name,
                settings: settings.settings,
                runCommand: runCommand
            )
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: ProjectItem) async {
        do {
            try await projectService.trash(project)
            refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openProjectFolder(_ project: ProjectItem) {
        NSWorkspace.shared.open(project.url)
    }

    func openInTerminal(project: ProjectItem, command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Command is empty. Set it in Settings."
            return
        }
        do {
            try terminalLauncher.open(
                projectPath: project.url.path,
                command: trimmed,
                kind: settings.settings.terminalKind
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
