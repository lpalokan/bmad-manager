import XCTest
@testable import BmadManager

final class GitRepoModuleSourceTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-gittest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Helpers

    /// Build a local repository on disk with a single commit containing a
    /// `manifest.yaml` file. Returns a `file://` URL suitable for `git clone`.
    private func buildLocalRepo(name: String = "fixture") throws -> String {
        let repoDir = workDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try runGit(["init", "--quiet", "--initial-branch=main"], cwd: repoDir)
        try runGit(["config", "user.email", "test@example.com"], cwd: repoDir)
        try runGit(["config", "user.name", "Test"], cwd: repoDir)
        try runGit(["config", "commit.gpgsign", "false"], cwd: repoDir)
        try "module: fixture\n".write(
            to: repoDir.appendingPathComponent("manifest.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "manifest.yaml"], cwd: repoDir)
        try runGit(["commit", "--quiet", "-m", "initial"], cwd: repoDir)
        return "file://" + repoDir.path
    }

    private func runGit(_ args: [String], cwd: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = cwd
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "git \(args.joined(separator: " ")) failed")
    }

    // MARK: - Tests

    func testWithModuleRootClonesAndCleansUp() async throws {
        let repoURL = try buildLocalRepo()
        var capturedRoot: URL?

        try await GitRepoModuleSource(url: repoURL, ref: "").withModuleRoot { root, _ in
            capturedRoot = root
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.yaml").path),
                "manifest.yaml should be present at the clone root"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path),
                ".git dir should be present in the clone"
            )
        }

        guard let root = capturedRoot else {
            XCTFail("body never invoked")
            return
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path),
            "temp clone dir should be cleaned up after normal return"
        )
    }

    func testWithModuleRootHonoursExplicitRef() async throws {
        let repoURL = try buildLocalRepo()
        var capturedRoot: URL?

        try await GitRepoModuleSource(url: repoURL, ref: "main").withModuleRoot { root, _ in
            capturedRoot = root
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.yaml").path))
        }
        XCTAssertNotNil(capturedRoot)
    }

    func testWithModuleRootCleanupOnThrow() async throws {
        let repoURL = try buildLocalRepo()
        enum TestError: Error { case intentional }
        var capturedRoot: URL?

        do {
            try await GitRepoModuleSource(url: repoURL, ref: "").withModuleRoot { root, _ in
                capturedRoot = root
                throw TestError.intentional
            }
            XCTFail("expected throw")
        } catch TestError.intentional {
            // expected
        }

        if let root = capturedRoot {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.path),
                "temp clone dir should be cleaned up even when body throws"
            )
        }
    }

    func testEmptyURLThrows() async throws {
        var closureCalled = false
        do {
            try await GitRepoModuleSource(url: "  ", ref: "").withModuleRoot { _, _ in
                closureCalled = true
            }
            XCTFail("expected throw")
        } catch GitError.noRepoURLConfigured {
            XCTAssertFalse(closureCalled, "closure should not be called when URL is blank")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInvalidRefThrowsCloneFailed() async throws {
        let repoURL = try buildLocalRepo()
        do {
            try await GitRepoModuleSource(url: repoURL, ref: "no-such-branch").withModuleRoot { _, _ in }
            XCTFail("expected throw")
        } catch GitError.cloneFailed {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Installer source resolution

    /// `git ls-remote --tags --refs` output for the fixtures below.
    private func lsRemote(_ tags: [String]) -> String {
        tags.enumerated()
            .map { "\(String(repeating: "a", count: 40))\trefs/tags/\($1)" }
            .joined(separator: "\n") + "\n"
    }

    func testInstallerSourcePinsExplicitRef() {
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r", ref: "v1.2.3", lsRemoteTags: { _ in nil })
        XCTAssertEqual(result, "https://github.com/o/r@v1.2.3")
    }

    func testInstallerSourceStripsTrailingSlashBeforePinning() {
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r/", ref: " main ", lsRemoteTags: { _ in nil })
        XCTAssertEqual(result, "https://github.com/o/r@main")
    }

    func testInstallerSourceResolvesLatestSemverTagWhenNoRef() {
        let output = lsRemote(["v1.0.1", "v1.0.2", "v1.0.3", "v2.0.2"])
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r", ref: "", lsRemoteTags: { _ in output })
        XCTAssertEqual(result, "https://github.com/o/r@v2.0.2",
                       "no ref → pin the highest semver tag so the manifest records a real version")
    }

    func testInstallerSourceIgnoresNonSemverTags() {
        let output = lsRemote(["latest", "nightly", "v1.4.0", "release-candidate"])
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r", ref: "", lsRemoteTags: { _ in output })
        XCTAssertEqual(result, "https://github.com/o/r@v1.4.0")
    }

    func testInstallerSourceFallsBackToBareURLWhenNoSemverTags() {
        let output = lsRemote(["latest", "nightly"])
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r", ref: "", lsRemoteTags: { _ in output })
        XCTAssertEqual(result, "https://github.com/o/r")
    }

    func testInstallerSourceFallsBackToBareURLWhenLsRemoteFails() {
        let result = GitRepoModuleSource.installerSource(
            url: "https://github.com/o/r", ref: "", lsRemoteTags: { _ in nil })
        XCTAssertEqual(result, "https://github.com/o/r")
    }

    func testWithModuleRootYieldsResolvedInstallerSourceNotClonePath() async throws {
        let repoURL = try buildLocalRepo()
        let output = lsRemote(["v0.9.0", "v1.1.0"])
        var captured: (root: URL, installer: String)?

        try await GitRepoModuleSource(url: repoURL, ref: "", lsRemoteTags: { _ in output })
            .withModuleRoot { root, installer in
                captured = (root, installer)
            }

        XCTAssertEqual(captured?.installer, "\(repoURL)@v1.1.0",
                       "the installer source is the URL+tag, not the temp clone path")
        XCTAssertNotEqual(captured?.installer, captured?.root.path)
    }
}
