import XCTest
@testable import BmadManager

// MARK: - Test doubles

/// Records terminal-open calls so tests can assert the right arguments
/// were passed without launching a real terminal.
private final class FakeTerminalLauncher: TerminalLauncherProtocol {
    private(set) var opens: [(projectPath: String, command: String, kind: TerminalKind)] = []
    var errorToThrow: Error? = nil

    func open(projectPath: String, command: String, kind: TerminalKind) throws {
        if let error = errorToThrow { throw error }
        opens.append((projectPath, command, kind))
    }
}

private enum FakeError: Error { case terminalFailed }

@MainActor
final class ProjectCoordinatorTests: XCTestCase {
    private var projectsRoot: URL!
    private var settings: SettingsStore!
    private var terminal: FakeTerminalLauncher!

    override func setUp() {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-coord-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        terminal = FakeTerminalLauncher()
        settings = SettingsStore()
        settings.settings = AppSettings.defaults()
        settings.settings.projectsRoot = projectsRoot.path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    private func makeCoordinator(
        runCommand: @escaping (String, URL) async -> Int32 = { _, _ in 0 }
    ) -> ProjectCoordinator {
        ProjectCoordinator(
            settings: settings,
            terminalLauncher: terminal,
            runCommand: runCommand
        )
    }

    // MARK: - Refresh

    func testRefreshReturnsEmptyWhenNoProjects() {
        let coordinator = makeCoordinator()
        coordinator.refresh()
        XCTAssertTrue(coordinator.projects.isEmpty)
    }

    func testRefreshListsCreatedProject() async throws {
        let coordinator = makeCoordinator()

        await coordinator.createProject(name: "my-project")
        coordinator.refresh()

        XCTAssertEqual(coordinator.projects.count, 1)
        XCTAssertEqual(coordinator.projects.first?.name, "my-project")
    }

    // MARK: - Create

    func testCreateProjectHappyPath() async throws {
        let coordinator = makeCoordinator()

        await coordinator.createProject(name: "test-proj")

        XCTAssertEqual(coordinator.projects.count, 1)
        XCTAssertEqual(coordinator.projects.first?.name, "test-proj")
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertFalse(coordinator.isCreating)
        XCTAssertTrue(coordinator.showOutput)

        let projectURL = projectsRoot.appendingPathComponent("test-proj")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testCreateProjectSetsShowOutput() async {
        let coordinator = makeCoordinator()
        coordinator.showOutput = false

        await coordinator.createProject(name: "output-test")

        XCTAssertTrue(coordinator.showOutput)
    }

    func testCreateProjectNonZeroExitCapturesError() async {
        let coordinator = makeCoordinator(runCommand: { _, _ in 42 })

        await coordinator.createProject(name: "fail-proj")

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertTrue(coordinator.errorMessage?.contains("42") ?? false)
        XCTAssertFalse(coordinator.isCreating)
    }

    func testCreateProjectResetsErrorOnSuccess() async {
        let coordinator = makeCoordinator()
        coordinator.errorMessage = "previous error"

        await coordinator.createProject(name: "good")

        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - Zip prompt

    func testCreateProjectWithoutZipPathFailsWhenLocalZip() async {
        settings.settings.moduleSourceKind = .localZip
        settings.settings.moduleZipPath = ""

        let coordinator = makeCoordinator()

        // promptForModuleZip returns nil → creation should fail
        await coordinator.createProject(name: "nozip", promptForModuleZip: { nil })

        XCTAssertEqual(coordinator.errorMessage, "A marketing growth module .zip is required to create a project.")
        XCTAssertEqual(coordinator.projects.count, 0)
    }

    func testCreateProjectSucceedsWhenZipPromptProvidesPath() async {
        settings.settings.moduleSourceKind = .localZip
        settings.settings.moduleZipPath = ""

        let coordinator = makeCoordinator()

        // Create a real zip fixture so unzip succeeds.
        // (Don't put the payload inside projectsRoot — listProjects would pick it up.)
        let payloadDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-zip-payload-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        try? "hi".write(to: payloadDir.appendingPathComponent("dummy.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: payloadDir) }
        let zipURL = projectsRoot.appendingPathComponent("fake.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "."]
        zip.currentDirectoryURL = payloadDir
        try? zip.run()
        zip.waitUntilExit()

        await coordinator.createProject(name: "zippy", promptForModuleZip: { zipURL })

        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(coordinator.projects.count, 1)
        XCTAssertFalse(settings.settings.moduleZipPath.isEmpty)
    }

    // MARK: - Delete

    func testDeleteProjectRemovesIt() async throws {
        let coordinator = makeCoordinator()

        // First create a project
        await coordinator.createProject(name: "to-delete")
        XCTAssertEqual(coordinator.projects.count, 1)

        guard let project = coordinator.projects.first else {
            XCTFail("Project should exist")
            return
        }

        await coordinator.deleteProject(project)

        XCTAssertEqual(coordinator.projects.count, 0)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.url.path))
    }

    func testDeleteProjectResetsErrorOnSuccess() async throws {
        let coordinator = makeCoordinator()
        await coordinator.createProject(name: "del-reset")
        coordinator.errorMessage = "old error"

        guard let project = coordinator.projects.first else {
            XCTFail("Project should exist")
            return
        }

        await coordinator.deleteProject(project)
        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - Terminal

    func testOpenInTerminalDelegatesToLauncher() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("terminal-proj"))

        coordinator.openInTerminal(project: project, command: "claude", kind: .terminal)

        XCTAssertEqual(terminal.opens.count, 1)
        XCTAssertEqual(terminal.opens.first?.command, "claude")
        XCTAssertEqual(terminal.opens.first?.projectPath, project.url.path)
    }

    func testOpenInTerminalTrimsWhitespaceFromCommand() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("trim-proj"))

        coordinator.openInTerminal(project: project, command: "  claude  ", kind: .terminal)

        XCTAssertEqual(terminal.opens.count, 1)
        XCTAssertEqual(terminal.opens.first?.command, "claude")
    }

    func testOpenInTerminalEmptyCommandShowsError() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("empty-cmd"))

        coordinator.openInTerminal(project: project, command: "", kind: .terminal)

        XCTAssertEqual(terminal.opens.count, 0)
        XCTAssertEqual(coordinator.errorMessage, "Command is empty. Set it in Settings.")
    }

    func testOpenInTerminalWhitespaceOnlyCommandShowsError() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("ws-only"))

        coordinator.openInTerminal(project: project, command: "   ", kind: .terminal)

        XCTAssertEqual(terminal.opens.count, 0)
        XCTAssertEqual(coordinator.errorMessage, "Command is empty. Set it in Settings.")
    }

    func testOpenInTerminalPropagatesLauncherError() {
        terminal.errorToThrow = FakeError.terminalFailed
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("err-proj"))

        coordinator.openInTerminal(project: project, command: "claude", kind: .terminal)

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertEqual(terminal.opens.count, 0)
    }

    func testOpenInTerminalForwardsKindFromCaller() {
        // Regression: previously the coordinator read
        // `settings.settings.terminalKind` from its captured SettingsStore.
        // Under the App's @StateObject init dance, that reference can drift
        // out of sync with the View's @EnvironmentObject binding — Picker
        // writes hit the View's store while the coordinator keeps reading
        // a stale copy, so iTerm2 selections were ignored until the next
        // launch. Now the View passes the live kind directly so there's
        // no captured copy to go stale.
        settings.settings.terminalKind = .terminal // coordinator-captured value
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("kind-proj"))

        coordinator.openInTerminal(project: project, command: "pi", kind: .iterm2)

        XCTAssertEqual(terminal.opens.first?.kind, .iterm2)
    }

    // MARK: - Project to delete state

    func testProjectToDeleteIsInitiallyNil() {
        let coordinator = makeCoordinator()
        XCTAssertNil(coordinator.projectToDelete)
    }

    func testSettingProjectToDeletePersists() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("mark-del"))
        coordinator.projectToDelete = project
        XCTAssertEqual(coordinator.projectToDelete?.name, "mark-del")
    }
}
