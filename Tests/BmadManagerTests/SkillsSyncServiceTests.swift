import XCTest
@testable import BmadManager

final class SkillsSyncServiceTests: XCTestCase {

    /// Records the git commands a sync would run, with a configurable exit.
    private final class Recorder {
        var calls: [(command: String, cwd: URL)] = []
        var exitCode: Int32 = 0
        func run(_ command: String, _ cwd: URL) async -> Int32 {
            calls.append((command, cwd))
            return exitCode
        }
    }

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Pure helpers

    func testManagedDirectoryLivesUnderToolSkillsManaged() {
        let base = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(
            SkillsSyncService.managedDirectory(for: .claudeCode, home: base).path,
            "/Users/me/.claude/skills/managed"
        )
        XCTAssertEqual(
            SkillsSyncService.managedDirectory(for: .codex, home: base).path,
            "/Users/me/.codex/skills/managed"
        )
    }

    func testAuthHeaderIsBasicXAccessToken() {
        // base64("x-access-token:ghp_secret")
        XCTAssertEqual(
            SkillsSyncService.authHeader(token: "ghp_secret"),
            "AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46Z2hwX3NlY3JldA=="
        )
    }

    func testAuthHeaderNeverContainsRawToken() {
        let header = SkillsSyncService.authHeader(token: "ghp_supersecretvalue")
        XCTAssertFalse(header.contains("ghp_supersecretvalue"))
    }

    func testCloneCommandIsShallowSingleBranchWithQuotedHeader() {
        let cmd = SkillsSyncService.cloneCommand(
            repoURL: "https://github.com/acme/skills",
            branch: "main",
            dest: URL(fileURLWithPath: "/Users/me/.claude/skills/managed"),
            header: "AUTHORIZATION: basic ABC"
        )
        XCTAssertTrue(cmd.hasPrefix("git -c "))
        XCTAssertTrue(cmd.contains("'http.extraHeader=AUTHORIZATION: basic ABC'"))
        XCTAssertTrue(cmd.contains("clone --depth 1 --single-branch"))
        XCTAssertTrue(cmd.contains("--branch 'main'"))
        XCTAssertTrue(cmd.contains("'https://github.com/acme/skills'"))
        XCTAssertTrue(cmd.contains("'/Users/me/.claude/skills/managed'"))
    }

    func testUpdateCommandFetchesThenHardResetsToFetchHead() {
        let cmd = SkillsSyncService.updateCommand(branch: "release", header: "AUTHORIZATION: basic X")
        XCTAssertTrue(cmd.contains("fetch --depth 1 origin 'release'"))
        XCTAssertTrue(cmd.hasSuffix("&& git reset --hard FETCH_HEAD"))
    }

    // MARK: - Orchestration

    func testSyncClonesWhenManagedDirIsMissing() async throws {
        let rec = Recorder()
        try await SkillsSyncService.sync(
            tool: .claudeCode,
            repoURL: "https://github.com/acme/skills",
            branch: "main",
            token: "ghp_token",
            home: home,
            runCommand: rec.run
        )
        XCTAssertEqual(rec.calls.count, 1)
        XCTAssertTrue(rec.calls[0].command.contains("clone"))
        // Clone runs from the parent of the managed dir, which must exist.
        let managed = SkillsSyncService.managedDirectory(for: .claudeCode, home: home)
        XCTAssertEqual(rec.calls[0].cwd.path, managed.deletingLastPathComponent().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.deletingLastPathComponent().path))
    }

    func testSyncUpdatesWhenManagedDirIsAGitRepo() async throws {
        let managed = SkillsSyncService.managedDirectory(for: .codex, home: home)
        try FileManager.default.createDirectory(
            at: managed.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let rec = Recorder()
        try await SkillsSyncService.sync(
            tool: .codex,
            repoURL: "https://github.com/acme/skills",
            branch: "main",
            token: "ghp_token",
            home: home,
            runCommand: rec.run
        )
        XCTAssertEqual(rec.calls.count, 1)
        XCTAssertTrue(rec.calls[0].command.contains("fetch"))
        XCTAssertTrue(rec.calls[0].command.contains("reset --hard FETCH_HEAD"))
        // Update runs from inside the managed dir.
        XCTAssertEqual(rec.calls[0].cwd.path, managed.path)
    }

    func testSyncThrowsWhenTokenMissingAndRunsNothing() async {
        let rec = Recorder()
        do {
            try await SkillsSyncService.sync(
                tool: .claudeCode,
                repoURL: "https://github.com/acme/skills",
                branch: "main",
                token: "   ",
                home: home,
                runCommand: rec.run
            )
            XCTFail("expected noToken error")
        } catch {
            XCTAssertTrue(error is SkillsSyncError)
            XCTAssertTrue(rec.calls.isEmpty, "no git should run without a token")
        }
    }

    func testSyncThrowsWhenRepoURLMissing() async {
        let rec = Recorder()
        do {
            try await SkillsSyncService.sync(
                tool: .claudeCode,
                repoURL: "",
                branch: "main",
                token: "ghp_token",
                home: home,
                runCommand: rec.run
            )
            XCTFail("expected noRepoURL error")
        } catch {
            XCTAssertTrue(error is SkillsSyncError)
        }
    }

    func testSyncThrowsGitFailedOnNonZeroExit() async {
        let rec = Recorder()
        rec.exitCode = 128
        do {
            try await SkillsSyncService.sync(
                tool: .claudeCode,
                repoURL: "https://github.com/acme/skills",
                branch: "main",
                token: "ghp_token",
                home: home,
                runCommand: rec.run
            )
            XCTFail("expected gitFailed error")
        } catch let SkillsSyncError.gitFailed(code) {
            XCTAssertEqual(code, 128)
        } catch {
            XCTFail("expected gitFailed, got \(error)")
        }
    }
}
