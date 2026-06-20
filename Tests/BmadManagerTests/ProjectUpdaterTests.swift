import XCTest
@testable import BmadManager

/// `ProjectUpdater` re-installs the latest module over an *existing* project
/// folder and refreshes the managed AGENTS.md blocks, without touching the
/// user's data. These mirror `ProjectCreatorTests`: a `FakeModuleSource`
/// stands in for a real clone, init is faked via the `runCommand` closure, and
/// partial-state/failure behaviour is pinned.
private struct FakeModuleSource: ModuleSource {
    let moduleRoot: URL
    let errorBeforeBody: Error?

    init(moduleRoot: URL, errorBeforeBody: Error? = nil) {
        self.moduleRoot = moduleRoot
        self.errorBeforeBody = errorBeforeBody
    }

    func withModuleRoot<T>(_ body: (URL) async throws -> T) async throws -> T {
        if let errorBeforeBody { throw errorBeforeBody }
        return try await body(moduleRoot)
    }
}

private enum FakeSourceError: Error { case missingFixture }

final class ProjectUpdaterTests: XCTestCase {
    private var projectsRoot: URL!
    private var moduleRoot: URL!

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-utest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        moduleRoot = projectsRoot.appendingPathComponent("module-root", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    // MARK: - Helpers

    private func makeSettings(initCommand: String) -> AppSettings {
        AppSettings(
            projectsRoot: projectsRoot.path,
            moduleSourceKind: .gitRepo,
            moduleRepoURL: "ignored-by-fake",
            moduleRepoRef: "",
            moduleZipPath: "",
            initCommand: initCommand,
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )
    }

    private func makeUpdater(source: ModuleSource) -> ProjectUpdater {
        ProjectUpdater(projectService: ProjectService()) { _ in source }
    }

    /// Creates an existing project folder (with a sentinel file proving the
    /// updater reuses it rather than recreating it) and returns its item.
    @discardableResult
    private func makeProject(_ name: String, sentinel: String = "keep me") throws -> ProjectItem {
        let url = projectsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try sentinel.write(to: url.appendingPathComponent("user-data.txt"),
                           atomically: true, encoding: .utf8)
        return ProjectItem(url: url)
    }

    private func seedOkfTemplate(_ body: String) throws {
        let templates = moduleRoot.appendingPathComponent("templates", isDirectory: true)
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        try body.write(to: templates.appendingPathComponent("agents-okf-block.md"),
                       atomically: true, encoding: .utf8)
    }

    private func realRun(_ command: String, _ cwd: URL) async -> Int32 {
        let (_, exitCode) = ShellProcess.run(command: command, cwd: cwd)
        return await exitCode.value
    }

    // MARK: - Re-install over existing folder

    func testUpdateRunsInitInExistingFolder() async throws {
        let project = try makeProject("existing")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        var capturedCwd: URL?
        try await updater.update(project: project, settings: settings) { command, cwd in
            capturedCwd = cwd
            return await self.realRun(command, cwd)
        }

        XCTAssertEqual(capturedCwd?.standardizedFileURL, project.url.standardizedFileURL)
        // User data in the existing folder is untouched.
        let kept = try String(
            contentsOf: project.url.appendingPathComponent("user-data.txt"), encoding: .utf8)
        XCTAssertEqual(kept, "keep me")
    }

    func testUpdateSubstitutesPlaceholders() async throws {
        let project = try makeProject("subst")
        let settings = makeSettings(
            initCommand: "echo '{PROJECT_PATH}' > marker.txt && echo '{PROJECT_NAME}' >> marker.txt && echo '{MODULE_PATH}' >> marker.txt")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { command, cwd in
            await self.realRun(command, cwd)
        }

        let contents = try String(
            contentsOf: project.url.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertTrue(contents.contains(project.url.path))
        XCTAssertTrue(contents.contains("subst"))
        XCTAssertTrue(contents.contains(moduleRoot.path))
    }

    // MARK: - AGENTS.md block refresh

    func testUpdateRefreshesBmadBlockPreservingUserContent() async throws {
        let project = try makeProject("agents-refresh")
        // A stale, hand-edited bmad block wrapped in user prose.
        try """
        # My notes

        \(AgentsFileWriter.startMarker(for: "bmad-manager:bmad"))
        STALE CONTENT
        \(AgentsFileWriter.endMarker(for: "bmad-manager:bmad"))

        More notes.
        """.write(to: project.url.appendingPathComponent("AGENTS.md"),
                  atomically: true, encoding: .utf8)
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertFalse(text.contains("STALE CONTENT"), "the stale block must be refreshed")
        XCTAssertTrue(text.contains(".agents/skills"), "the current bmad block must be written")
        XCTAssertTrue(text.contains("# My notes"), "user prose before the block survives")
        XCTAssertTrue(text.contains("More notes."), "user prose after the block survives")
    }

    func testUpdateInjectsOkfBlockWhenTemplatePresent() async throws {
        let project = try makeProject("with-okf")
        try seedOkfTemplate("# OKF\n\nUse the company-context OKF bundle.")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.startMarker(for: "marketing-growth:okf")))
        XCTAssertTrue(text.contains("Use the company-context OKF bundle."))
        // The bmad block is also present.
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker))
    }

    func testUpdateSkipsOkfBlockWhenTemplateAbsent() async throws {
        // No templates/agents-okf-block.md in the clone (today's reality).
        let project = try makeProject("no-okf")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker), "bmad block still refreshed")
        XCTAssertFalse(text.contains("marketing-growth:okf"),
                       "okf block stays dormant until the template ships")
    }

    // MARK: - Failure / partial state

    func testUpdateFailsOnNonZeroExitAndLeavesProjectInspectable() async throws {
        let project = try makeProject("fails")
        let settings = makeSettings(initCommand: "exit 42")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        do {
            try await updater.update(project: project, settings: settings) { _, _ in 42 }
            XCTFail("expected throw")
        } catch ProjectUpdateError.initCommandFailed(let code) {
            XCTAssertEqual(code, 42)
        }

        // The project folder and the user's data are intact.
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
        let kept = try String(
            contentsOf: project.url.appendingPathComponent("user-data.txt"), encoding: .utf8)
        XCTAssertEqual(kept, "keep me")
    }

    func testUpdatePropagatesSourceError() async throws {
        let project = try makeProject("source-error")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(
            source: FakeModuleSource(moduleRoot: moduleRoot, errorBeforeBody: FakeSourceError.missingFixture))

        do {
            try await updater.update(project: project, settings: settings) { _, _ in 0 }
            XCTFail("expected throw")
        } catch FakeSourceError.missingFixture {
            // expected — the source's own error propagates unchanged
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
    }
}
