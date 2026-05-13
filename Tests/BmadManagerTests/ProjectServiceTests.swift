import XCTest
@testable import BmadManager

final class ProjectServiceTests: XCTestCase {
    private var tempRoot: URL!
    private let service = ProjectService()

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRejectsEmptyName() {
        for candidate in ["", "   "] {
            XCTAssertThrowsError(try service.createProjectFolder(name: candidate, in: tempRoot.path)) { error in
                XCTAssertTrue(error is ProjectError, "expected ProjectError, got \(error)")
                if case ProjectError.invalidName = error { /* ok */ } else {
                    XCTFail("expected invalidName, got \(error)")
                }
            }
        }
    }

    func testRejectsSlashInName() {
        XCTAssertThrowsError(try service.createProjectFolder(name: "a/b", in: tempRoot.path)) { error in
            if case ProjectError.invalidName = error { /* ok */ } else {
                XCTFail("expected invalidName, got \(error)")
            }
        }
    }

    func testRejectsLeadingDot() {
        XCTAssertThrowsError(try service.createProjectFolder(name: ".hidden", in: tempRoot.path)) { error in
            if case ProjectError.invalidName = error { /* ok */ } else {
                XCTFail("expected invalidName, got \(error)")
            }
        }
    }

    func testCreatesFolderForValidName() throws {
        let url = try service.createProjectFolder(name: "valid-project", in: tempRoot.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "valid-project")
    }

    func testTrimsSurroundingWhitespace() throws {
        let url = try service.createProjectFolder(name: "  spaced  ", in: tempRoot.path)
        XCTAssertEqual(url.lastPathComponent, "spaced")
    }

    func testRejectsDuplicateProject() throws {
        _ = try service.createProjectFolder(name: "dup", in: tempRoot.path)
        XCTAssertThrowsError(try service.createProjectFolder(name: "dup", in: tempRoot.path)) { error in
            if case ProjectError.projectExists = error { /* ok */ } else {
                XCTFail("expected projectExists, got \(error)")
            }
        }
    }

    func testCreatesRootIfMissing() throws {
        let nested = tempRoot.appendingPathComponent("does-not-exist-yet")
        let url = try service.createProjectFolder(name: "p1", in: nested.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testListProjectsReturnsDirectoriesAlphabetically() throws {
        _ = try service.createProjectFolder(name: "beta", in: tempRoot.path)
        _ = try service.createProjectFolder(name: "alpha", in: tempRoot.path)
        let listed = service.listProjects(in: tempRoot.path)
        XCTAssertEqual(listed.map(\.name), ["alpha", "beta"])
    }

    func testListProjectsSkipsFiles() throws {
        _ = try service.createProjectFolder(name: "alpha", in: tempRoot.path)
        let fileURL = tempRoot.appendingPathComponent("loose.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let listed = service.listProjects(in: tempRoot.path)
        XCTAssertEqual(listed.map(\.name), ["alpha"])
    }

    func testListProjectsForMissingRootReturnsEmpty() {
        let missing = "/tmp/bmad-manager-does-not-exist-\(UUID().uuidString)"
        XCTAssertEqual(service.listProjects(in: missing), [])
    }

    // MARK: - createdAt + sort orders (#12)

    func testListProjectsPopulatesCreationDate() throws {
        _ = try service.createProjectFolder(name: "with-date", in: tempRoot.path)
        let listed = service.listProjects(in: tempRoot.path)
        XCTAssertNotNil(listed.first?.createdAt,
                        "freshly created folders should expose a creation date")
    }

    func testListProjectsSortedByNameAscending() throws {
        _ = try service.createProjectFolder(name: "beta", in: tempRoot.path)
        _ = try service.createProjectFolder(name: "alpha", in: tempRoot.path)
        _ = try service.createProjectFolder(name: "Charlie", in: tempRoot.path)
        let listed = service.listProjects(in: tempRoot.path, sortedBy: .nameAscending)
        XCTAssertEqual(listed.map(\.name), ["alpha", "beta", "Charlie"])
    }

    func testListProjectsSortedByDateNewestFirst() throws {
        try makeTimestampedFixtures()
        let listed = service.listProjects(in: tempRoot.path, sortedBy: .dateNewestFirst)
        XCTAssertEqual(listed.map(\.name), ["newest", "middle", "oldest"])
    }

    func testListProjectsSortedByDateOldestFirst() throws {
        try makeTimestampedFixtures()
        let listed = service.listProjects(in: tempRoot.path, sortedBy: .dateOldestFirst)
        XCTAssertEqual(listed.map(\.name), ["oldest", "middle", "newest"])
    }

    /// Builds three folders ("oldest", "middle", "newest") with explicit
    /// creation dates so date-based sort tests aren't subject to
    /// filesystem timestamp resolution.
    private func makeTimestampedFixtures() throws {
        let oldest = try service.createProjectFolder(name: "oldest", in: tempRoot.path)
        let middle = try service.createProjectFolder(name: "middle", in: tempRoot.path)
        let newest = try service.createProjectFolder(name: "newest", in: tempRoot.path)

        let now = Date()
        try FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-3600)], ofItemAtPath: oldest.path)
        try FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-1800)], ofItemAtPath: middle.path)
        try FileManager.default.setAttributes(
            [.creationDate: now], ofItemAtPath: newest.path)
    }
}
