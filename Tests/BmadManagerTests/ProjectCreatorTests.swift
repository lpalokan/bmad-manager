import XCTest
@testable import BmadManager

/// Test double for the `ModuleSource` seam — yields a pre-built directory
/// without spinning up a real zip extraction or git clone, so orchestration
/// tests stay focused on `ProjectCreator`'s own behaviour.
private struct FakeModuleSource: ModuleSource {
    let moduleRoot: URL
    let installerSource: String
    let errorBeforeBody: Error?

    init(moduleRoot: URL, installerSource: String? = nil, errorBeforeBody: Error? = nil) {
        self.moduleRoot = moduleRoot
        self.installerSource = installerSource ?? moduleRoot.path
        self.errorBeforeBody = errorBeforeBody
    }

    func withModuleRoot<T>(
        _ body: (_ moduleRoot: URL, _ installerSource: String) async throws -> T
    ) async throws -> T {
        if let errorBeforeBody { throw errorBeforeBody }
        return try await body(moduleRoot, installerSource)
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

    // MARK: - Existing-folder init (#64)

    func testInitializesIntoExistingFolder() async throws {
        // A pre-existing folder outside the projects root — init should use
        // it as-is rather than minting a fresh folder under projectsRoot.
        let existing = projectsRoot.appendingPathComponent("already-here", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        let project = try await creator.create(
            name: "already-here",
            settings: settings,
            destination: existing
        ) { _, _ in 0 }

        XCTAssertEqual(project.url.standardizedFileURL, existing.standardizedFileURL)
    }

    func testInitIntoNonEmptyFolderIsAllowed() async throws {
        let existing = projectsRoot.appendingPathComponent("non-empty", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try "keep me".write(to: existing.appendingPathComponent("existing.txt"),
                            atomically: true, encoding: .utf8)
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        let project = try await creator.create(
            name: "non-empty",
            settings: settings,
            destination: existing
        ) { _, _ in 0 }

        XCTAssertEqual(project.url.standardizedFileURL, existing.standardizedFileURL)
        // The pre-existing file must be untouched — init runs *in* the folder.
        let kept = try String(
            contentsOf: existing.appendingPathComponent("existing.txt"), encoding: .utf8)
        XCTAssertEqual(kept, "keep me")
    }

    func testExistingFolderPathUsedAsWorkingDirectory() async throws {
        let existing = projectsRoot.appendingPathComponent("as-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let settings = makeSettings(
            initCommand: "echo '{PROJECT_PATH}' > marker.txt"
        )
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        var capturedCwd: URL?
        let project = try await creator.create(
            name: "as-cwd",
            settings: settings,
            destination: existing
        ) { command, cwd in
            capturedCwd = cwd
            let (_, exitCode) = ShellProcess.run(command: command, cwd: cwd)
            return await exitCode.value
        }

        XCTAssertEqual(capturedCwd?.standardizedFileURL, existing.standardizedFileURL)
        let marker = try String(
            contentsOf: existing.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertTrue(marker.contains(existing.path))
        XCTAssertEqual(project.url.standardizedFileURL, existing.standardizedFileURL)
    }

    func testWritesCodexAgentsFileAfterSuccessfulInit() async throws {
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))
        let project = try await creator.create(
            name: "codex-project",
            settings: settings
        ) { _, _ in 0 }

        let agents = project.url.appendingPathComponent("AGENTS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agents.path),
                      "project creation should leave a Codex AGENTS.md behind")
        let text = try String(contentsOf: agents, encoding: .utf8)
        XCTAssertTrue(text.contains(".agents/skills"))
        XCTAssertTrue(text.contains("_bmad/_config/bmad-help.csv"))
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

    func testModuleSourcePlaceholderSubstitutesInstallerSource() async throws {
        // `{MODULE_SOURCE}` carries the installer-source string (a GitHub URL
        // for the git source), distinct from the local `{MODULE_PATH}`.
        let installerSource = "https://github.com/o/r@v2.0.2"
        let settings = makeSettings(
            initCommand: "echo '{MODULE_SOURCE}' > marker.txt && echo '{MODULE_PATH}' >> marker.txt"
        )
        let creator = makeCreator(
            source: FakeModuleSource(moduleRoot: moduleRoot, installerSource: installerSource))
        let project = try await creator.create(
            name: "module-source-project",
            settings: settings
        ) { command, cwd in
            let (_, exitCode) = ShellProcess.run(command: command, cwd: cwd)
            return await exitCode.value
        }

        let contents = try String(
            contentsOf: project.url.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertTrue(contents.contains(installerSource),
                      "{MODULE_SOURCE} should expand to the installer-source URL")
        XCTAssertTrue(contents.contains(moduleRoot.path),
                      "{MODULE_PATH} should still expand to the local module root")
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

    // MARK: - Context import

    /// Builds a source project with a company context under `projectsRoot`
    /// and returns the resolved `CompanyContext` for it.
    private func makeSourceContext(files: [String]) throws -> CompanyContext {
        let sourceProject = projectsRoot
            .appendingPathComponent("source-project", isDirectory: true)
        let contextDir = sourceProject
            .appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
        for file in files {
            try "imported \(file)".write(to: contextDir.appendingPathComponent(file),
                                         atomically: true, encoding: .utf8)
        }
        return try XCTUnwrap(
            CompanyContextService().context(inProject: sourceProject)
        )
    }

    func testCreateImportsSelectedContextAfterInitSucceeds() async throws {
        let context = try makeSourceContext(files: ["icp.md", "kpis.md"])
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        let project = try await creator.create(
            name: "seeded-project",
            settings: settings,
            importingContextFrom: context
        ) { _, _ in 0 }

        let destDir = project.url.appendingPathComponent("_bmad-output/company-context")
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "imported icp.md")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("kpis.md").path))
    }

    func testCreateWithoutContextSelectionDoesNotCreateContextFolder() async throws {
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        let project = try await creator.create(
            name: "scratch-project",
            settings: settings
        ) { _, _ in 0 }

        let destDir = project.url.appendingPathComponent("_bmad-output/company-context")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.path))
    }

    func testCreateDoesNotImportContextWhenInitFails() async throws {
        let context = try makeSourceContext(files: ["icp.md"])
        let settings = makeSettings(initCommand: "exit 7")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        do {
            try await creator.create(
                name: "failed-seed",
                settings: settings,
                importingContextFrom: context
            ) { _, _ in 7 }
            XCTFail("expected throw")
        } catch ProjectCreationError.initCommandFailed {
            // expected
        }

        let destDir = projectsRoot
            .appendingPathComponent("failed-seed/_bmad-output/company-context")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.path))
    }

    func testCreateSurfacesContextImportFailureWithSourceProjectName() async throws {
        let context = try makeSourceContext(files: ["icp.md"])
        try FileManager.default.removeItem(
            at: context.directoryURL.appendingPathComponent("icp.md"))
        let settings = makeSettings(initCommand: "true")
        let creator = makeCreator(source: FakeModuleSource(moduleRoot: moduleRoot))

        do {
            try await creator.create(
                name: "import-fails",
                settings: settings,
                importingContextFrom: context
            ) { _, _ in 0 }
            XCTFail("expected throw")
        } catch let error as ProjectCreationError {
            XCTAssertTrue(error.localizedDescription.contains("source-project"))
        }

        // Partial-state policy: the project folder is kept so the user can
        // inspect it (consistent with init-command failures).
        let projectURL = projectsRoot.appendingPathComponent("import-fails")
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
