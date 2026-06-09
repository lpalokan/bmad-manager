import XCTest
@testable import BmadManager

/// Scenario-style coverage for scanning projects for company contexts and
/// importing one into a newly created project. The recognized file set and
/// the resolution order (`_bmad-output/company-context` then
/// `company-context`) mirror the bmad-marketing-growth module's
/// company-context-bootstrap workflow.
final class CompanyContextServiceTests: XCTestCase {
    private var projectsRoot: URL!
    private let service = CompanyContextService()

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ctx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    /// Creates `<projectsRoot>/<project>/<subpath>/` containing the given
    /// files, returning the project folder URL.
    @discardableResult
    private func makeProject(
        _ name: String,
        contextAt subpath: String? = "_bmad-output/company-context",
        files: [String] = []
    ) throws -> URL {
        let projectURL = projectsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        if let subpath {
            let contextDir = projectURL.appendingPathComponent(subpath, isDirectory: true)
            try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
            for file in files {
                try "content of \(file) from \(name)".write(
                    to: contextDir.appendingPathComponent(file),
                    atomically: true, encoding: .utf8
                )
            }
        }
        return projectURL
    }

    // MARK: - Scanning

    func testFindsContextUnderBmadOutputCompanyContext() throws {
        try makeProject("acme", files: ["icp.md", "positioning.md"])

        let contexts = service.scanContexts(inProjectsRoot: projectsRoot.path)

        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.projectName, "acme")
        XCTAssertEqual(contexts.first?.files, ["icp.md", "positioning.md"])
    }

    func testFindsContextUnderTopLevelCompanyContextFallback() throws {
        try makeProject("legacy", contextAt: "company-context", files: ["brand-voice.md"])

        let contexts = service.scanContexts(inProjectsRoot: projectsRoot.path)

        XCTAssertEqual(contexts.map(\.projectName), ["legacy"])
        XCTAssertEqual(contexts.first?.files, ["brand-voice.md"])
    }

    func testPrefersBmadOutputLocationOverTopLevelFallback() throws {
        let projectURL = try makeProject("both", files: ["icp.md"])
        let fallbackDir = projectURL.appendingPathComponent("company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        try "fallback".write(to: fallbackDir.appendingPathComponent("kpis.md"),
                             atomically: true, encoding: .utf8)

        let contexts = service.scanContexts(inProjectsRoot: projectsRoot.path)

        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.files, ["icp.md"])
        XCTAssertEqual(
            contexts.first?.directoryURL.path,
            projectURL.appendingPathComponent("_bmad-output/company-context").path
        )
    }

    func testIgnoresProjectsWithoutRecognizedContextFiles() throws {
        try makeProject("empty-context", files: [])
        try makeProject("only-unrecognized", files: [])
        let dir = projectsRoot
            .appendingPathComponent("only-unrecognized/_bmad-output/company-context", isDirectory: true)
        try "summary".write(to: dir.appendingPathComponent("bootstrap-summary.md"),
                            atomically: true, encoding: .utf8)
        try makeProject("no-context-dir", contextAt: nil)

        XCTAssertTrue(service.scanContexts(inProjectsRoot: projectsRoot.path).isEmpty)
    }

    func testListsOnlyRecognizedFilesInCanonicalOrder() throws {
        try makeProject(
            "mixed",
            files: ["tech-stack.md", "bootstrap-summary.md", "icp.md", "notes.txt"]
        )

        let contexts = service.scanContexts(inProjectsRoot: projectsRoot.path)

        XCTAssertEqual(contexts.first?.files, ["icp.md", "tech-stack.md"])
    }

    func testSortsContextsByProjectNameCaseInsensitively() throws {
        try makeProject("zeta", files: ["icp.md"])
        try makeProject("Alpha", files: ["icp.md"])
        try makeProject("beta", files: ["icp.md"])

        let contexts = service.scanContexts(inProjectsRoot: projectsRoot.path)

        XCTAssertEqual(contexts.map(\.projectName), ["Alpha", "beta", "zeta"])
    }

    func testReturnsEmptyWhenProjectsRootMissing() {
        let missing = projectsRoot.appendingPathComponent("does-not-exist").path
        XCTAssertTrue(service.scanContexts(inProjectsRoot: missing).isEmpty)
    }

    func testSkipsPlainFilesAtProjectsRoot() throws {
        try "not a project".write(to: projectsRoot.appendingPathComponent("stray.txt"),
                                  atomically: true, encoding: .utf8)
        XCTAssertTrue(service.scanContexts(inProjectsRoot: projectsRoot.path).isEmpty)
    }

    // MARK: - Import

    func testImportCopiesRecognizedFilesIntoNewProject() throws {
        try makeProject("source", files: ["icp.md", "kpis.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(
            service.scanContexts(inProjectsRoot: projectsRoot.path).first
        )

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "content of icp.md from source")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("kpis.md").path))
    }

    func testImportDoesNotCarryUnrecognizedFilesOver() throws {
        try makeProject("source", files: ["icp.md", "bootstrap-summary.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(
            service.scanContexts(inProjectsRoot: projectsRoot.path).first
        )

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("bootstrap-summary.md").path))
    }

    func testImportLeavesExistingDestinationFilesUntouched() throws {
        // Never overwrite silently — if the init command (or the user)
        // already put a context file in place, the import keeps it.
        try makeProject("source", files: ["icp.md", "positioning.md"])
        let target = try makeProject("the-target", files: ["icp.md"])
        let context = try XCTUnwrap(
            service.scanContexts(inProjectsRoot: projectsRoot.path)
                .first { $0.projectName == "source" }
        )

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "content of icp.md from the-target")
        let positioning = try String(
            contentsOf: destDir.appendingPathComponent("positioning.md"), encoding: .utf8)
        XCTAssertEqual(positioning, "content of positioning.md from source")
    }

    func testImportFailsWithReadableErrorWhenSourceFileVanished() throws {
        try makeProject("source", files: ["icp.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(
            service.scanContexts(inProjectsRoot: projectsRoot.path).first
        )
        try FileManager.default.removeItem(
            at: context.directoryURL.appendingPathComponent("icp.md"))

        XCTAssertThrowsError(try service.importContext(context, into: target)) { error in
            XCTAssertTrue(error.localizedDescription.contains("icp.md"))
        }
    }

    // MARK: - Display

    func testDisplayNameIsJustTheProjectNameWhenContextIsComplete() {
        let context = CompanyContext(
            projectName: "acme",
            directoryURL: URL(fileURLWithPath: "/tmp/acme/_bmad-output/company-context"),
            files: CompanyContext.recognizedFileNames
        )
        XCTAssertEqual(context.displayName, "acme")
    }

    func testDisplayNameFlagsPartialContexts() {
        let context = CompanyContext(
            projectName: "acme",
            directoryURL: URL(fileURLWithPath: "/tmp/acme/_bmad-output/company-context"),
            files: ["icp.md", "kpis.md"]
        )
        XCTAssertEqual(context.displayName, "acme (2 of 5 context files)")
    }
}
