import XCTest
@testable import BmadManager

/// XCTest specs for `PathDetector`. These play the same role as the
/// Gherkin scenarios in the Tauri tree's `path_detection.feature`: the
/// Settings dialog uses this to tell the user whether `claude`,
/// `opencode`, and `pi` are reachable, so users either trust the
/// defaults or browse for a binary.
final class PathDetectorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PathDetectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testBlankCommandReturnsNil() {
        XCTAssertNil(PathDetector.detect("", path: ""))
        XCTAssertNil(PathDetector.detect("   ", path: ""))
    }

    func testBareCommandOnPathResolvesToAbsolutePath() throws {
        let exe = tmp.appendingPathComponent("ficticious-agent")
        try makeExecutable(at: exe)
        let resolved = PathDetector.detect("ficticious-agent", path: tmp.path)
        XCTAssertEqual(resolved, exe.path)
    }

    func testBareCommandMissingFromPathReturnsNil() {
        XCTAssertNil(
            PathDetector.detect("definitely-not-installed-9999", path: tmp.path)
        )
    }

    func testAbsolutePathThatExistsReturnsItself() throws {
        let exe = tmp.appendingPathComponent("some-binary")
        try makeExecutable(at: exe)
        let resolved = PathDetector.detect(exe.path, path: "")
        XCTAssertEqual(resolved, exe.path)
    }

    func testAbsolutePathThatDoesNotExistReturnsNil() {
        XCTAssertNil(PathDetector.detect("/no/such/binary/anywhere", path: ""))
    }

    func testWalksMultiplePathEntriesInOrder() throws {
        let first = tmp.appendingPathComponent("first")
        let second = tmp.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let inSecond = second.appendingPathComponent("only-in-second")
        try makeExecutable(at: inSecond)
        let combined = "\(first.path):\(second.path)"
        XCTAssertEqual(
            PathDetector.detect("only-in-second", path: combined),
            inSecond.path
        )
    }

    func testSkipsEmptyPathEntries() throws {
        let exe = tmp.appendingPathComponent("with-empty-segment")
        try makeExecutable(at: exe)
        let combined = "::\(tmp.path)::"
        XCTAssertEqual(
            PathDetector.detect("with-empty-segment", path: combined),
            exe.path
        )
    }

    func testNonExecutableFileIsNotReturned() throws {
        let file = tmp.appendingPathComponent("not-executable")
        try Data().write(to: file)
        // Default file mode is 0644 — readable but not executable, so
        // PATH lookup should pretend it isn't there. (An absolute-path
        // lookup is more permissive: it only checks that the file exists,
        // because the user explicitly pointed at it.)
        XCTAssertNil(PathDetector.detect("not-executable", path: tmp.path))
    }

    // MARK: - helpers

    private func makeExecutable(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
