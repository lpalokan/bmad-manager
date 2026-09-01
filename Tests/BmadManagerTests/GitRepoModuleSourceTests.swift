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

    // MARK: - Resolution: does the install record a real version?
    //
    // `bmad-method` records whatever ref it is handed as the module version.
    // A bare URL or a branch ref makes it stamp `main`, which can never
    // compare as current against a real semver — the project is flagged
    // forever and re-running Update rewrites the same value. Resolution has
    // to say so instead of letting it happen silently.

    func testResolutionPinsTheLatestTagAndRecordsAVersion() {
        let resolved = GitRepoModuleSource.describeInstallerSource(
            url: "https://github.com/o/r", ref: "", tagsOutput: lsRemote(["v1.0.0", "v2.5.0"]))
        XCTAssertEqual(resolved.arg, "https://github.com/o/r@v2.5.0")
        XCTAssertEqual(resolved.pinnedRef, "v2.5.0")
        XCTAssertTrue(resolved.note.contains("latest tag v2.5.0"))
    }

    func testResolutionPinsAnExplicitVersionTagFromSettings() {
        let resolved = GitRepoModuleSource.describeInstallerSource(
            url: "https://github.com/o/r", ref: "v2.4.0", tagsOutput: lsRemote(["v2.5.0"]))
        XCTAssertEqual(resolved.arg, "https://github.com/o/r@v2.4.0")
        XCTAssertEqual(resolved.pinnedRef, "v2.4.0")
        XCTAssertTrue(resolved.note.contains("from Settings"))
    }

    func testResolutionWarnsThatABranchRefRecordsNoVersion() {
        let resolved = GitRepoModuleSource.describeInstallerSource(
            url: "https://github.com/o/r", ref: "main", tagsOutput: lsRemote(["v2.5.0"]))
        XCTAssertEqual(resolved.arg, "https://github.com/o/r@main")
        XCTAssertNil(resolved.pinnedRef)
        XCTAssertTrue(resolved.note.contains("not a version tag"))
        XCTAssertTrue(resolved.note.contains("keep showing an update"))
    }

    func testResolutionWarnsWhenTheTagListingCannotBeRead() {
        let resolved = GitRepoModuleSource.describeInstallerSource(
            url: "https://github.com/o/r", ref: "", tagsOutput: nil)
        XCTAssertEqual(resolved.arg, "https://github.com/o/r")
        XCTAssertNil(resolved.pinnedRef)
        XCTAssertTrue(resolved.note.contains("could not list the version tags"))
        XCTAssertTrue(resolved.note.contains("keep showing an update"))
    }

    func testResolutionWarnsWhenTheRepoPublishesNoVersionTags() {
        let resolved = GitRepoModuleSource.describeInstallerSource(
            url: "https://github.com/o/r", ref: "", tagsOutput: lsRemote(["latest", "nightly"]))
        XCTAssertEqual(resolved.arg, "https://github.com/o/r")
        XCTAssertNil(resolved.pinnedRef)
        XCTAssertTrue(resolved.note.contains("no version tags"))
    }

    /// The module read locally and the module the installer records have to be
    /// the same version: a repo whose default branch runs ahead of its newest
    /// tag otherwise reports a version nothing will ever install.
    func testWithModuleRootClonesTheTagItWillPin() async throws {
        let repoURL = try buildLocalRepo(name: "tagged")
        let repoDir = workDir.appendingPathComponent("tagged", isDirectory: true)
        try runGit(["tag", "v1.1.0"], cwd: repoDir)
        try "moved on".write(
            to: repoDir.appendingPathComponent("manifest.yaml"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: repoDir)
        try runGit(["commit", "--quiet", "-m", "after the tag"], cwd: repoDir)

        var captured: String?
        try await GitRepoModuleSource(
            url: repoURL, ref: "", lsRemoteTags: { _ in self.lsRemote(["v1.1.0"]) }
        )
        .withModuleRoot { root, _ in
            captured = try? String(
                contentsOf: root.appendingPathComponent("manifest.yaml"), encoding: .utf8)
        }

        XCTAssertNotEqual(
            captured, "moved on",
            "the clone must be the tag that will be installed, not the default branch")
    }

    func testWithModuleRootYieldsResolvedInstallerSourceNotClonePath() async throws {
        let repoURL = try buildLocalRepo()
        // The resolved tag is also the ref that gets cloned, so it has to
        // exist on the fixture repo — a tag listing and the repo it came from
        // always agree in the real world.
        try runGit(["tag", "v0.9.0"], cwd: workDir.appendingPathComponent("fixture"))
        try runGit(["tag", "v1.1.0"], cwd: workDir.appendingPathComponent("fixture"))
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
