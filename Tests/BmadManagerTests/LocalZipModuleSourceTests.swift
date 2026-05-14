import XCTest
@testable import BmadManager

final class LocalZipModuleSourceTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ziptest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - extract / cleanup

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

        let extracted = try LocalZipModuleSource.extract(zipPath: zipURL.path)
        XCTAssertTrue(extracted.lastPathComponent.hasPrefix("bmad-manager-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))

        let extractedFile = extracted.appendingPathComponent("hello.txt")
        XCTAssertEqual(
            try String(contentsOf: extractedFile, encoding: .utf8),
            "hi from a fixture\n"
        )

        LocalZipModuleSource.cleanup(extracted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.path))
    }

    func testExtractThrowsForMissingZip() {
        let missing = "/tmp/bmad-manager-missing-\(UUID().uuidString).zip"
        XCTAssertThrowsError(try LocalZipModuleSource.extract(zipPath: missing)) { error in
            if case ZipError.zipNotFound = error { /* ok */ } else {
                XCTFail("expected zipNotFound, got \(error)")
            }
        }
    }

    // MARK: - moduleRoot(in:)

    func testModuleRootDescendsIntoSingleWrapper() throws {
        let outer = workDir.appendingPathComponent("outer", isDirectory: true)
        let wrapper = outer.appendingPathComponent("repo-main", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try "x".write(to: wrapper.appendingPathComponent("manifest.yaml"),
                      atomically: true, encoding: .utf8)

        // FileManager returns URLs with the /private/var prefix on macOS
        // (real path), but our constructed `wrapper` URL has /var (the
        // symlink). Resolve both sides before comparing.
        XCTAssertEqual(LocalZipModuleSource.moduleRoot(in: outer).resolvingSymlinksInPath(),
                       wrapper.resolvingSymlinksInPath())
    }

    func testModuleRootStaysWhenMultipleTopLevelEntries() throws {
        let dir = workDir.appendingPathComponent("flat", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        try "y".write(to: dir.appendingPathComponent("b.txt"),
                      atomically: true, encoding: .utf8)

        XCTAssertEqual(LocalZipModuleSource.moduleRoot(in: dir), dir)
    }

    func testModuleRootIgnoresMacOSXSibling() throws {
        let outer = workDir.appendingPathComponent("outer", isDirectory: true)
        let wrapper = outer.appendingPathComponent("repo-main", isDirectory: true)
        let mac = outer.appendingPathComponent("__MACOSX", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)

        XCTAssertEqual(LocalZipModuleSource.moduleRoot(in: outer).resolvingSymlinksInPath(),
                       wrapper.resolvingSymlinksInPath())
    }

    func testModuleRootStaysWhenSoleEntryIsAFile() throws {
        let dir = workDir.appendingPathComponent("solefile", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("only.txt"),
                      atomically: true, encoding: .utf8)

        XCTAssertEqual(LocalZipModuleSource.moduleRoot(in: dir), dir)
    }

    // MARK: - withModuleRoot

    func testWithModuleRootDescendsWrapper() async throws {
        let sourceDir = workDir.appendingPathComponent("payload", isDirectory: true)
        let wrapper = sourceDir.appendingPathComponent("repo-main", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        try "hi".write(to: wrapper.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

        let zipURL = workDir.appendingPathComponent("wrapped.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "repo-main"]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        var captured: URL?
        try await LocalZipModuleSource(zipPath: zipURL.path).withModuleRoot { root in
            captured = root
            XCTAssertEqual(root.lastPathComponent, "repo-main")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
        }
        if let captured {
            XCTAssertFalse(FileManager.default.fileExists(atPath: captured.deletingLastPathComponent().path),
                          "temp dir should be cleaned up")
        }
    }

    func testWithModuleRootFlatZip() async throws {
        let sourceDir = workDir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "flat content".write(to: sourceDir.appendingPathComponent("flat.txt"), atomically: true, encoding: .utf8)

        let zipURL = workDir.appendingPathComponent("flat.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "."]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        var captured: URL?
        try await LocalZipModuleSource(zipPath: zipURL.path).withModuleRoot { root in
            captured = root
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("flat.txt").path))
        }
        if let captured {
            XCTAssertFalse(FileManager.default.fileExists(atPath: captured.path),
                          "temp dir should be cleaned up")
        }
    }

    func testWithModuleRootCleanupOnThrow() async throws {
        let sourceDir = workDir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "x".write(to: sourceDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let zipURL = workDir.appendingPathComponent("throwable.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "."]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        enum TestError: Error { case intentional }
        var tempDirExistsAfterThrow = false
        do {
            try await LocalZipModuleSource(zipPath: zipURL.path).withModuleRoot { root in
                tempDirExistsAfterThrow = FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path)
                throw TestError.intentional
            }
            XCTFail("expected throw")
        } catch TestError.intentional {
            XCTAssertTrue(tempDirExistsAfterThrow, "temp dir should exist inside closure")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testWithModuleRootCleanupOnNormalReturn() async throws {
        let sourceDir = workDir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "x".write(to: sourceDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let zipURL = workDir.appendingPathComponent("normal.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "."]
        zip.currentDirectoryURL = sourceDir
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        var captured: URL?
        try await LocalZipModuleSource(zipPath: zipURL.path).withModuleRoot { root in
            captured = root
        }
        if let captured {
            XCTAssertFalse(FileManager.default.fileExists(atPath: captured.path),
                          "temp dir should be cleaned up after normal return")
        }
    }

    func testWithModuleRootMissingZip() async throws {
        let missing = "/tmp/bmad-manager-missing-\(UUID().uuidString).zip"
        var closureCalled = false
        do {
            try await LocalZipModuleSource(zipPath: missing).withModuleRoot { _ in
                closureCalled = true
            }
            XCTFail("expected throw")
        } catch ZipError.zipNotFound {
            XCTAssertFalse(closureCalled, "closure should not be called for missing zip")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testWithModuleRootEmptyZipPath() async throws {
        var closureCalled = false
        do {
            try await LocalZipModuleSource(zipPath: "   ").withModuleRoot { _ in
                closureCalled = true
            }
            XCTFail("expected throw")
        } catch ZipError.notConfigured {
            XCTAssertFalse(closureCalled, "closure should not be called when zipPath is blank")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
