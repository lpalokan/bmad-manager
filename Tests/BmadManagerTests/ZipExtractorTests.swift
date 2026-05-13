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
}
