import XCTest
@testable import BmadManager

final class ZipExtractorTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ziptest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    func testExtractAndCleanupRoundTrip() throws {
        // Build a tiny fixture zip on the fly so the tests stay self-contained.
        let sourceDir = workDir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "hi from a fixture\n".write(
            to: sourceDir.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )

        let zipURL = workDir.appendingPathComponent("fixture.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "hello.txt"]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0, "/usr/bin/zip must succeed building the fixture")

        // Extract.
        let extracted = try ZipExtractor.extract(zipPath: zipURL.path)
        XCTAssertTrue(extracted.lastPathComponent.hasPrefix("bmad-manager-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))

        let extractedFile = extracted.appendingPathComponent("hello.txt")
        XCTAssertEqual(
            try String(contentsOf: extractedFile, encoding: .utf8),
            "hi from a fixture\n"
        )

        // Cleanup.
        ZipExtractor.cleanup(extracted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.path))
    }

    func testExtractThrowsForMissingZip() {
        let missing = "/tmp/bmad-manager-missing-\(UUID().uuidString).zip"
        XCTAssertThrowsError(try ZipExtractor.extract(zipPath: missing)) { error in
            if case ZipError.zipNotFound = error { /* ok */ } else {
                XCTFail("expected zipNotFound, got \(error)")
            }
        }
    }

    // MARK: - moduleRoot(in:)

    func testModuleRootDescendsIntoSingleWrapper() throws {
        // Simulate `unzip` of a GitHub-style archive: one wrapper folder
        // at the top, real contents inside it.
        let outer = workDir.appendingPathComponent("outer", isDirectory: true)
        let wrapper = outer.appendingPathComponent("repo-main", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try "x".write(to: wrapper.appendingPathComponent("manifest.yaml"),
                      atomically: true, encoding: .utf8)

        XCTAssertEqual(ZipExtractor.moduleRoot(in: outer), wrapper)
    }

    func testModuleRootStaysWhenMultipleTopLevelEntries() throws {
        // Flat archive (no wrapper): module files at the top level.
        let dir = workDir.appendingPathComponent("flat", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        try "y".write(to: dir.appendingPathComponent("b.txt"),
                      atomically: true, encoding: .utf8)

        XCTAssertEqual(ZipExtractor.moduleRoot(in: dir), dir)
    }

    func testModuleRootIgnoresMacOSXSibling() throws {
        // macOS-created zips often produce a __MACOSX sibling next to the
        // real wrapper. The wrapper should still be picked up.
        let outer = workDir.appendingPathComponent("outer", isDirectory: true)
        let wrapper = outer.appendingPathComponent("repo-main", isDirectory: true)
        let mac = outer.appendingPathComponent("__MACOSX", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)

        XCTAssertEqual(ZipExtractor.moduleRoot(in: outer), wrapper)
    }

    func testModuleRootStaysWhenSoleEntryIsAFile() throws {
        // If the only top-level entry is a file (not a folder), leave the
        // dir alone — there's no wrapper to descend into.
        let dir = workDir.appendingPathComponent("solefile", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("only.txt"),
                      atomically: true, encoding: .utf8)

        XCTAssertEqual(ZipExtractor.moduleRoot(in: dir), dir)
    }
}
