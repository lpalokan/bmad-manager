import XCTest
@testable import BmadManager

/// Test double for the `ModuleSource` seam — yields a pre-built directory
/// without spinning up a real zip extraction or git clone, so orchestration
/// tests stay focused on `ProjectCreator`'s own behaviour.
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

final class ProjectCreatorTests: XCTestCase {
    private var projectsRoot: URL!
    private var moduleRoot: URL!

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ptest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        moduleRoot = projectsRoot.appendingPathComponent("module-root", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleRoot, withIntermediateDirectories: true)
        try "stub".write(to: moduleRoot.appendingPathComponent("manifest.yaml"),
                         atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

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

    private func makeCreator(source: ModuleSource) -> ProjectCreator {
        ProjectCreator(projectService: ProjectService()) { _ in source }
    }

    // MARK: - Tests

    func testHappyPath() async throws {
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))
        let project = try await creator.create(
            name: "happy-project",
            settings: settings
        ) { _, _ in 0 }

        XCTAssertEqual(project.name, "happy-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
    }

    func testPlaceholderSubstitution() async throws {
        let settings = makeSettings(
            initCommand: "echo '{PROJECT_PATH}' > marker.txt && echo '{PROJECT_NAME}' >> marker.txt && echo '{MODULE_PATH}' >> marker.txt"
        )
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))
        let project = try await creator.create(
            name: "subst-project",
            settings: settings
        ) { command, cwd in
            let (_, exitCode) = ShellProcess.run(command: command, cwd: cwd)
            return await exitCode.value
        }

        let markerURL = project.url.appendingPathComponent("marker.txt")
        let contents = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(project.url.path))
        XCTAssertTrue(contents.contains("subst-project"))
        XCTAssertTrue(contents.contains(moduleRoot.path))
    }

    func testFailureCleanupOnNonZeroExit() async throws {
        let settings = makeSettings(initCommand: "exit 42")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))
        do {
            try await creator.create(
                name: "fail-project",
                settings: settings
            ) { _, _ in 42 }
            XCTFail("expected throw")
        } catch ProjectCreationError.initCommandFailed(let code) {
            XCTAssertEqual(code, 42)
        }

        // Partial-state policy: the project folder is kept so the user can
        // inspect what was created before the init command failed.
        let projectURL = projectsRoot.appendingPathComponent("fail-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    func testSourceErrorPropagatesAndProjectFolderRemains() async throws {
        // `ModuleSource` adapters validate their own config and throw before
        // invoking `body`. ProjectCreator should let that error propagate
        // unchanged, and the partial-state policy still applies (project
        // folder is created before the source is materialised).
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(
            source: FakeModuleSource(moduleRoot: moduleRoot,
                                     errorBeforeBody: FakeSourceError.missingFixture)
        )
        do {
            try await creator.create(
                name: "throw-project",
                settings: settings
            ) { _, _ in 0 }
            XCTFail("expected throw")
        } catch FakeSourceError.missingFixture {
            // expected
        }

        let projectURL = projectsRoot.appendingPathComponent("throw-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    // MARK: - Factory wiring

    func testDefaultFactoryDispatchesByKind() {
        // Smoke test that ModuleSourceFactory.make returns the concrete
        // adapter implied by moduleSourceKind. Each adapter has its own
        // tests for materialisation behaviour — here we only verify the
        // dispatch step.
        var settings = AppSettings.defaults()

        settings.moduleSourceKind = .gitRepo
        XCTAssertTrue(ModuleSourceFactory.make(for: settings) is GitRepoModuleSource)

        settings.moduleSourceKind = .localZip
        XCTAssertTrue(ModuleSourceFactory.make(for: settings) is LocalZipModuleSource)
    }
}
