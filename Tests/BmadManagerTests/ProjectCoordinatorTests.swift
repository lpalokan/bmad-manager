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

/// Records desktop-app launches so tests can assert which bundle (and on
/// which project) would be opened without actually launching an app via
/// LaunchServices.
private final class FakeAppLauncher: AppLauncherProtocol {
    private(set) var opens: [(bundleIdentifier: String, projectPath: String)] = []
    var errorToThrow: Error? = nil

    func open(bundleIdentifier: String, projectPath: String) throws {
        if let error = errorToThrow { throw error }
        opens.append((bundleIdentifier, projectPath))
    }
}

private enum FakeError: Error { case terminalFailed, appFailed }

@MainActor
final class ProjectCoordinatorTests: XCTestCase {
    private var projectsRoot: URL!
    private var settings: SettingsStore!
    private var terminal: FakeTerminalLauncher!
    private var appLauncher: FakeAppLauncher!

    override func setUp() {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-coord-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        terminal = FakeTerminalLauncher()
        appLauncher = FakeAppLauncher()
        // Use an in-memory repository so the test never writes to the
        // real ~/Library/Application Support/.../settings.json — otherwise
        // setting `settings.projectsRoot` here would persist this temp
        // path into the user's actual settings file via the @Published
        // didSet on SettingsStore.
        settings = SettingsStore(repository: InMemorySettingsRepository())
        settings.settings = AppSettings.defaults()
        settings.settings.projectsRoot = projectsRoot.path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    private var defaultRunCommand: (String, URL) async -> Int32 = { _, _ in 0 }

    private func makeCoordinator() -> ProjectCoordinator {
        ProjectCoordinator(terminalLauncher: terminal, appLauncher: appLauncher)
    }

    private func createProject(
        _ coordinator: ProjectCoordinator,
        name: String,
        zipPath: URL? = nil,
        runCommand: ((String, URL) async -> Int32)? = nil
    ) async {
        if let zipPath {
            settings.settings.moduleZipPath = zipPath.path
        }
        await coordinator.createProject(
            name: name,
            settings: settings.settings,
            runCommand: runCommand ?? defaultRunCommand
        )
    }

    private func deleteProject(
        _ coordinator: ProjectCoordinator,
        _ project: ProjectItem
    ) async {
        await coordinator.deleteProject(
            project,
            root: settings.settings.projectsRoot,
            sortOrder: settings.settings.projectSortOrder
        )
    }

    // MARK: - Refresh

    private func refresh(_ coordinator: ProjectCoordinator) {
        coordinator.refresh(
            root: settings.settings.projectsRoot,
            sortOrder: settings.settings.projectSortOrder
        )
    }

    func testRefreshReturnsEmptyWhenNoProjects() {
        let coordinator = makeCoordinator()
        refresh(coordinator)
        XCTAssertTrue(coordinator.projects.isEmpty)
    }

    func testRefreshListsCreatedProject() async throws {
        let coordinator = makeCoordinator()

        await createProject(coordinator, name: "my-project")
        refresh(coordinator)

        XCTAssertEqual(coordinator.projects.count, 1)
        XCTAssertEqual(coordinator.projects.first?.name, "my-project")
    }

    func testRefreshHonoursRootFromCaller() throws {
        // Regression: prior to the projectsRoot drift fix, refresh() read
        // `settings.settings.projectsRoot` off the coordinator's captured
        // SettingsStore. Under the App's @StateObject init dance that
        // store can drift from the View's @EnvironmentObject, so updating
        // the projects folder in Settings reindexed the OLD folder until
        // the next launch. Now refresh() takes the root from the caller.
        let other = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-other-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other) }
        try FileManager.default.createDirectory(at: other.appendingPathComponent("only-here"), withIntermediateDirectories: true)

        let coordinator = makeCoordinator()
        coordinator.refresh(root: other.path, sortOrder: .nameAscending)

        XCTAssertEqual(coordinator.projects.map(\.name), ["only-here"])
    }

    // MARK: - Create

    func testCreateProjectHappyPath() async throws {
        let coordinator = makeCoordinator()

        await createProject(coordinator, name: "test-proj")

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

        await createProject(coordinator, name: "output-test")

        XCTAssertTrue(coordinator.showOutput)
    }

    func testCreateProjectNonZeroExitCapturesError() async {
        let coordinator = makeCoordinator()

        await createProject(coordinator, name: "fail-proj", runCommand: { _, _ in 42 })

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertTrue(coordinator.errorMessage?.contains("42") ?? false)
        XCTAssertFalse(coordinator.isCreating)
    }

    func testCreateProjectResetsErrorOnSuccess() async {
        let coordinator = makeCoordinator()
        coordinator.errorMessage = "previous error"

        await createProject(coordinator, name: "good")

        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - Zip prompt

    func testCreateProjectSucceedsWhenViewProvidesZipPath() async {
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

        // The View handles prompting; here we simulate the View persisting
        // the picked zip path before calling the coordinator.
        await createProject(coordinator, name: "zippy", zipPath: zipURL)

        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(coordinator.projects.count, 1)
        XCTAssertFalse(settings.settings.moduleZipPath.isEmpty)
    }

    // MARK: - Company contexts

    /// Drops a company context with the given files into an existing or new
    /// project folder under the projects root.
    private func seedContext(project: String, files: [String]) throws {
        let contextDir = projectsRoot
            .appendingPathComponent("\(project)/_bmad-output/company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
        for file in files {
            try "from \(project)".write(to: contextDir.appendingPathComponent(file),
                                        atomically: true, encoding: .utf8)
        }
    }

    func testRefreshDiscoversContextsFromExistingProjects() throws {
        try seedContext(project: "campaign-a", files: ["icp.md", "positioning.md"])
        try seedContext(project: "campaign-b", files: ["kpis.md"])
        try FileManager.default.createDirectory(
            at: projectsRoot.appendingPathComponent("no-context"),
            withIntermediateDirectories: true)

        let coordinator = makeCoordinator()
        refresh(coordinator)

        XCTAssertEqual(coordinator.availableContexts.map(\.projectName),
                       ["campaign-a", "campaign-b"])
    }

    func testRefreshReturnsNoContextsWhenProjectsHaveNone() async {
        let coordinator = makeCoordinator()
        await createProject(coordinator, name: "plain")
        refresh(coordinator)

        XCTAssertTrue(coordinator.availableContexts.isEmpty)
    }

    func testCreateProjectImportsSelectedContext() async throws {
        try seedContext(project: "donor", files: ["icp.md", "brand-voice.md"])
        let coordinator = makeCoordinator()
        refresh(coordinator)
        let context = try XCTUnwrap(coordinator.availableContexts.first)

        await coordinator.createProject(
            name: "recipient",
            settings: settings.settings,
            importContextFrom: context,
            runCommand: defaultRunCommand
        )

        XCTAssertNil(coordinator.errorMessage)
        let destDir = projectsRoot
            .appendingPathComponent("recipient/_bmad-output/company-context")
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "from donor")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("brand-voice.md").path))
        // The freshly created project now carries a context of its own and
        // should be offered as a source on the next refresh.
        XCTAssertTrue(coordinator.availableContexts.contains { $0.projectName == "recipient" })
    }

    func testCreateProjectWithoutContextStartsFromScratch() async {
        let coordinator = makeCoordinator()

        await coordinator.createProject(
            name: "scratch",
            settings: settings.settings,
            runCommand: defaultRunCommand
        )

        XCTAssertNil(coordinator.errorMessage)
        let destDir = projectsRoot
            .appendingPathComponent("scratch/_bmad-output/company-context")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.path))
    }

    // MARK: - GitHub repo contexts & auto-sync

    /// A throwaway home dir whose `.claude/skills-managed` clone we can seed.
    private func makeHome() -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-coord-home-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    /// Seeds `<home>/.claude/skills-managed/{.git, context/<name>/<files>}`,
    /// simulating a clone the auto-sync's git "update" path can no-op over.
    private func seedManagedRepo(home: URL, context name: String, files: [String]) throws {
        let repo = SkillsSyncService.managedRepoDir(for: .claudeCode, home: home)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let dir = repo.appendingPathComponent("context/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files {
            try "from \(name)".write(to: dir.appendingPathComponent(file),
                                     atomically: true, encoding: .utf8)
        }
    }

    func testRefreshMergesGithubContextsBeforeProjectContexts() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try seedManagedRepo(home: home, context: "shared-acme", files: ["icp.md"])
        try seedContext(project: "campaign-a", files: ["icp.md"])

        let coordinator = makeCoordinator()
        coordinator.refresh(
            root: settings.settings.projectsRoot,
            sortOrder: .nameAscending,
            home: home
        )

        XCTAssertEqual(coordinator.availableContexts.map(\.projectName),
                       ["shared-acme", "campaign-a"])
        XCTAssertEqual(coordinator.availableContexts.first?.source, .github)
        XCTAssertEqual(coordinator.availableContexts.last?.source, .project)
    }

    func testSyncSkillsRepoIsSilentNoOpWhenUnconfigured() async {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        settings.settings.skillsRepoURL = ""

        var ran = false
        let coordinator = makeCoordinator()
        await coordinator.syncSkillsRepo(
            settings: settings.settings,
            token: nil,
            home: home,
            runCommand: { _, _ in ran = true; return 0 }
        )

        XCTAssertFalse(ran, "no git should run without a repo URL/token")
        XCTAssertNil(coordinator.errorMessage)
    }

    func testSyncSkillsRepoSyncsBothToolsThenDiscoversGithubContexts() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        settings.settings.skillsRepoURL = "https://github.com/acme/skills"
        // Pre-seed both tools' clones with a .git so sync takes the
        // fetch/reset path and our fake runCommand can just succeed.
        try seedManagedRepo(home: home, context: "shared-acme", files: ["icp.md", "kpis.md"])
        let codexRepo = SkillsSyncService.managedRepoDir(for: .codex, home: home)
        try FileManager.default.createDirectory(
            at: codexRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        var calls = 0
        let coordinator = makeCoordinator()
        await coordinator.syncSkillsRepo(
            settings: settings.settings,
            token: "ghp_token",
            home: home,
            runCommand: { _, _ in calls += 1; return 0 }
        )

        XCTAssertGreaterThanOrEqual(calls, 2, "git should run for both tools")
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(coordinator.availableContexts.map(\.projectName), ["shared-acme"])
        XCTAssertEqual(coordinator.availableContexts.first?.source, .github)
    }

    func testSyncSkillsRepoSurfacesGitFailure() async {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        settings.settings.skillsRepoURL = "https://github.com/acme/skills"

        let coordinator = makeCoordinator()
        await coordinator.syncSkillsRepo(
            settings: settings.settings,
            token: "ghp_token",
            home: home,
            runCommand: { _, _ in 128 }
        )

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertTrue(coordinator.errorMessage?.contains("128") ?? false)
    }

    // MARK: - Delete

    func testDeleteProjectRemovesIt() async throws {
        let coordinator = makeCoordinator()

        // First create a project
        await createProject(coordinator, name: "to-delete")
        XCTAssertEqual(coordinator.projects.count, 1)

        guard let project = coordinator.projects.first else {
            XCTFail("Project should exist")
            return
        }

        await deleteProject(coordinator, project)

        XCTAssertEqual(coordinator.projects.count, 0)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.url.path))
    }

    func testDeleteProjectResetsErrorOnSuccess() async throws {
        let coordinator = makeCoordinator()
        await createProject(coordinator, name: "del-reset")
        coordinator.errorMessage = "old error"

        guard let project = coordinator.projects.first else {
            XCTFail("Project should exist")
            return
        }

        await deleteProject(coordinator, project)
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

    // MARK: - Agent launch (App vs CLI)

    func testOpenAgentAutoLaunchesAppWhenInstalled() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("auto-app"))

        coordinator.openAgent(
            project: project,
            agent: .claude,
            method: .auto,
            appInstalled: true,
            command: "claude",
            kind: .terminal
        )

        XCTAssertEqual(appLauncher.opens.count, 1)
        XCTAssertEqual(appLauncher.opens.first?.bundleIdentifier, "com.anthropic.claudefordesktop")
        XCTAssertEqual(appLauncher.opens.first?.projectPath, project.url.path)
        XCTAssertEqual(terminal.opens.count, 0)
    }

    func testOpenAgentAutoFallsBackToCliWhenAppMissing() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("auto-cli"))

        coordinator.openAgent(
            project: project,
            agent: .claude,
            method: .auto,
            appInstalled: false,
            command: "claude",
            kind: .iterm2
        )

        XCTAssertEqual(appLauncher.opens.count, 0)
        XCTAssertEqual(terminal.opens.count, 1)
        XCTAssertEqual(terminal.opens.first?.command, "claude")
        XCTAssertEqual(terminal.opens.first?.kind, .iterm2)
    }

    func testOpenAgentCliAlwaysUsesTerminalEvenWhenAppInstalled() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("forced-cli"))

        coordinator.openAgent(
            project: project,
            agent: .codex,
            method: .cli,
            appInstalled: true,
            command: "codex",
            kind: .terminal
        )

        XCTAssertEqual(appLauncher.opens.count, 0)
        XCTAssertEqual(terminal.opens.first?.command, "codex")
    }

    func testOpenAgentAppForcedLaunchesAppEvenWhenNotDetected() {
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("forced-app"))

        coordinator.openAgent(
            project: project,
            agent: .codex,
            method: .app,
            appInstalled: false,
            command: "codex",
            kind: .terminal
        )

        XCTAssertEqual(appLauncher.opens.count, 1)
        XCTAssertEqual(appLauncher.opens.first?.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(appLauncher.opens.first?.projectPath, project.url.path)
        XCTAssertEqual(terminal.opens.count, 0)
    }

    func testOpenAgentSurfacesAppLaunchError() {
        appLauncher.errorToThrow = FakeError.appFailed
        let coordinator = makeCoordinator()
        let project = ProjectItem(url: projectsRoot.appendingPathComponent("app-err"))

        coordinator.openAgent(
            project: project,
            agent: .claude,
            method: .app,
            appInstalled: true,
            command: "claude",
            kind: .terminal
        )

        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertEqual(terminal.opens.count, 0)
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
