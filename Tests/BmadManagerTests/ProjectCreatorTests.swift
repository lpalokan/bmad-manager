import XCTest
@testable import BmadManager

final class ProjectCreatorTests: XCTestCase {
    private var projectsRoot: URL!
    private let creator = ProjectCreator(projectService: ProjectService())

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ptest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    // MARK: - Helpers

    private func buildFixtureZip(name: String, content: String = "module content") throws -> String {
        let sourceDir = projectsRoot.appendingPathComponent("src-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try content.write(to: sourceDir.appendingPathComponent("manifest.yaml"), atomically: true, encoding: .utf8)

        let zipURL = projectsRoot.appendingPathComponent("\(name).zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "."]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        return zipURL.path
    }

    // MARK: - Tests

    @MainActor
    func testHappyPath() async throws {
        let zipPath = try buildFixtureZip(name: "happy")

        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: zipPath,
            initCommand: "true",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        let project = try await creator.create(name: "happy-project", settings: settings, runner: runner)

        XCTAssertEqual(project.name, "happy-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
    }

    @MainActor
    func testPlaceholderSubstitution() async throws {
        let zipPath = try buildFixtureZip(name: "subst")

        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: zipPath,
            initCommand: "echo '{PROJECT_PATH}' > marker.txt && echo '{PROJECT_NAME}' >> marker.txt",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        let project = try await creator.create(name: "subst-project", settings: settings, runner: runner)

        let markerURL = project.url.appendingPathComponent("marker.txt")
        let contents = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(project.url.path))
        XCTAssertTrue(contents.contains("subst-project"))
    }

    @MainActor
    func testGitHubWrapperDescent() async throws {
        // Build a zip with a wrapper folder (like GitHub downloads)
        let wrapperDir = projectsRoot.appendingPathComponent("wrapper-src", isDirectory: true)
        let inner = wrapperDir.appendingPathComponent("repo-main", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "wrapper content".write(to: inner.appendingPathComponent("manifest.yaml"),
                                    atomically: true, encoding: .utf8)

        let zipURL = projectsRoot.appendingPathComponent("wrapped.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "repo-main"]
        zip.currentDirectoryURL = wrapperDir
        try zip.run()
        zip.waitUntilExit()

        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: zipURL.path,
            initCommand: "echo module root: {MODULE_PATH} > info.txt",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        let project = try await creator.create(name: "wrapper-test", settings: settings, runner: runner)

        let infoURL = project.url.appendingPathComponent("info.txt")
        let contents = try String(contentsOf: infoURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("repo-main"),
                      "expected MODULE_PATH to descend into wrapper, got: \(contents)")
    }

    @MainActor
    func testFailureCleanupOnNonZeroExit() async throws {
        let zipPath = try buildFixtureZip(name: "fail-cleanup")

        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: zipPath,
            initCommand: "exit 42",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        do {
            try await creator.create(name: "fail-project", settings: settings, runner: runner)
            XCTFail("expected throw")
        } catch ProjectCreationError.initCommandFailed(let code) {
            XCTAssertEqual(code, 42)
        }

        // Project folder should still exist (partial-state policy)
        let projectURL = projectsRoot.appendingPathComponent("fail-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    @MainActor
    func testFailureCleanupOnThrow() async throws {
        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: "/tmp/nonexistent-\(UUID().uuidString).zip",
            initCommand: "true",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        do {
            try await creator.create(name: "throw-project", settings: settings, runner: runner)
            XCTFail("expected throw")
        } catch ZipError.zipNotFound {
            // expected
        }

        // Project folder was created before the zip extraction throw,
        // so the partial-state policy applies (same as testFailureCleanupOnNonZeroExit).
        let projectURL = projectsRoot.appendingPathComponent("throw-project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
    }

    @MainActor
    func testEmptyModuleZipThrows() async throws {
        let settings = AppSettings(
            projectsRoot: projectsRoot.path,
            moduleZipPath: "",
            initCommand: "true",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )

        let runner = CommandRunner()
        do {
            try await creator.create(name: "empty-zip", settings: settings, runner: runner)
            XCTFail("expected throw")
        } catch ProjectCreationError.noModuleZipConfigured {
            // expected
        }

        let projectURL = projectsRoot.appendingPathComponent("empty-zip")
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.path))
    }
}
