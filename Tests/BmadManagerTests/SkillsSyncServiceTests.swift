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

    /// Writes the `.git/config` a clone of `origin` would have.
    private func seedCloneConfig(at clone: URL, origin: String) throws {
        let git = clone.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let body = """
            [core]
            \trepositoryformatversion = 0
            [remote "origin"]
            \turl = \(origin)
            \tfetch = +refs/heads/*:refs/remotes/origin/*

            """
        try body.write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    private func makeSkill(in repo: URL, _ name: String) throws {
        let dir = repo.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# \(name)".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - Paths & pure helpers

    func testPathsResolveUnderTheRightDotfolders() {
        let base = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(
            SkillsSyncService.skillsRoot(for: .claudeCode, home: base).path,
            "/Users/me/.claude/skills"
        )
        XCTAssertEqual(
            SkillsSyncService.managedRepoDir(for: .codex, home: base).path,
            "/Users/me/.codex/skills-managed"
        )
    }

    func testAuthHeaderIsBasicXAccessTokenWithoutRawToken() {
        XCTAssertEqual(
            SkillsSyncService.authHeader(token: "ghp_secret"),
            "AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46Z2hwX3NlY3JldA=="
        )
        XCTAssertFalse(SkillsSyncService.authHeader(token: "ghp_supersecret").contains("ghp_supersecret"))
    }

    func testCloneCommandIsShallowSingleBranchWithQuotedHeader() {
        let cmd = SkillsSyncService.cloneCommand(
            repoURL: "https://github.com/acme/skills",
            branch: "main",
            dest: URL(fileURLWithPath: "/Users/me/.claude/skills-managed"),
            header: "AUTHORIZATION: basic ABC"
        )
        XCTAssertTrue(cmd.hasPrefix("git -c "))
        XCTAssertTrue(cmd.contains("'http.extraHeader=AUTHORIZATION: basic ABC'"))
        XCTAssertTrue(cmd.contains("clone --depth 1 --single-branch"))
        XCTAssertTrue(cmd.contains("--branch 'main'"))
        XCTAssertTrue(cmd.contains("'/Users/me/.claude/skills-managed'"))
    }

    func testUpdateCommandRepointsOriginThenFetchesAndHardResets() {
        let cmd = SkillsSyncService.updateCommand(
            repoURL: "https://github.com/acme/skills",
            branch: "release",
            header: "AUTHORIZATION: basic X")
        XCTAssertTrue(cmd.hasPrefix("git remote set-url origin 'https://github.com/acme/skills'"))
        XCTAssertTrue(cmd.contains("fetch --depth 1 origin 'release'"))
        XCTAssertTrue(cmd.hasSuffix("&& git reset --hard FETCH_HEAD"))
    }

    // MARK: - discoverSkills

    func testDiscoverSkillsFindsOnlySkillDirs() throws {
        let repo = home.appendingPathComponent("repo")
        try makeSkill(in: repo, "alpha")
        try makeSkill(in: repo, "beta")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git/objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("not-a-skill"), withIntermediateDirectories: true)
        XCTAssertEqual(SkillsSyncService.discoverSkills(in: repo), ["alpha", "beta"])
    }

    // MARK: - skills source folder

    func testSkillsSourceDirPrefersSkillsSubfolderWhenPresent() throws {
        let repo = home.appendingPathComponent("repo")
        try makeSkill(in: repo.appendingPathComponent("skills"), "alpha")
        XCTAssertEqual(
            SkillsSyncService.skillsSourceDir(in: repo).lastPathComponent, "skills")
    }

    func testSkillsSourceDirFallsBackToRepoRootWhenNoSubfolder() throws {
        let repo = home.appendingPathComponent("repo")
        try makeSkill(in: repo, "alpha")
        XCTAssertEqual(SkillsSyncService.skillsSourceDir(in: repo).path, repo.path)
    }

    func testReconcileLinksDiscoversSkillsUnderTheSkillsSubfolder() throws {
        let skills = home.appendingPathComponent("skills")
        let repo = home.appendingPathComponent("skills-managed")
        let manifest = home.appendingPathComponent("links.json")
        // New layout: skills live under <repo>/skills, contexts under <repo>/context.
        try makeSkill(in: repo.appendingPathComponent("skills"), "alpha")
        try makeSkill(in: repo.appendingPathComponent("skills"), "beta")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("context/acme"), withIntermediateDirectories: true)

        let summary = try SkillsSyncService.reconcileLinks(
            skillsRoot: skills, managedRepo: repo, manifestPath: manifest)

        XCTAssertEqual(summary.linked, ["alpha", "beta"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skills.appendingPathComponent("alpha/SKILL.md").path))
    }

    // MARK: - reconcileLinks

    func testReconcileLinksCreatesSymlinksForEachSkill() throws {
        let skills = home.appendingPathComponent("skills")
        let repo = home.appendingPathComponent("skills-managed")
        let manifest = home.appendingPathComponent("links.json")
        try makeSkill(in: repo, "alpha")
        try makeSkill(in: repo, "beta")

        let summary = try SkillsSyncService.reconcileLinks(
            skillsRoot: skills, managedRepo: repo, manifestPath: manifest)
        XCTAssertEqual(summary.linked, ["alpha", "beta"])
        XCTAssertTrue(SkillsSyncService.isSymlink(skills.appendingPathComponent("alpha")))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skills.appendingPathComponent("alpha/SKILL.md").path))
        XCTAssertEqual(SkillsSyncService.readManifest(manifest), ["alpha", "beta"])
    }

    func testReconcileLinksSkipsPersonalSkillWithSameName() throws {
        let skills = home.appendingPathComponent("skills")
        let repo = home.appendingPathComponent("skills-managed")
        let manifest = home.appendingPathComponent("links.json")
        // A real personal skill named "alpha".
        try makeSkill(in: skills, "alpha")
        try "personal".write(
            to: skills.appendingPathComponent("alpha/SKILL.md"), atomically: true, encoding: .utf8)
        try makeSkill(in: repo, "alpha")
        try makeSkill(in: repo, "beta")

        let summary = try SkillsSyncService.reconcileLinks(
            skillsRoot: skills, managedRepo: repo, manifestPath: manifest)
        XCTAssertEqual(summary.skipped, ["alpha"])
        XCTAssertEqual(summary.linked, ["beta"])
        // Personal alpha untouched (still a real dir, not a symlink).
        XCTAssertFalse(SkillsSyncService.isSymlink(skills.appendingPathComponent("alpha")))
        XCTAssertEqual(
            try String(contentsOf: skills.appendingPathComponent("alpha/SKILL.md"), encoding: .utf8),
            "personal")
    }

    func testReconcileLinksRemovesStaleManagedLinks() throws {
        let skills = home.appendingPathComponent("skills")
        let repo = home.appendingPathComponent("skills-managed")
        let manifest = home.appendingPathComponent("links.json")
        try makeSkill(in: repo, "alpha")
        try makeSkill(in: repo, "beta")
        try SkillsSyncService.reconcileLinks(skillsRoot: skills, managedRepo: repo, manifestPath: manifest)
        XCTAssertTrue(SkillsSyncService.entryExists(skills.appendingPathComponent("beta")))

        try FileManager.default.removeItem(at: repo.appendingPathComponent("beta"))
        let summary = try SkillsSyncService.reconcileLinks(
            skillsRoot: skills, managedRepo: repo, manifestPath: manifest)
        XCTAssertEqual(summary.linked, ["alpha"])
        XCTAssertTrue(summary.removed.contains("beta"))
        XCTAssertFalse(SkillsSyncService.entryExists(skills.appendingPathComponent("beta")))
    }

    // MARK: - Orchestration

    func testSyncClonesWhenRepoIsMissing() async throws {
        let rec = Recorder()
        try await SkillsSyncService.sync(
            tool: .claudeCode, repoURL: "https://github.com/acme/skills", branch: "main",
            token: "ghp_token", home: home, runCommand: rec.run)
        XCTAssertEqual(rec.calls.count, 1)
        XCTAssertTrue(rec.calls[0].command.contains("clone"))
        // Clone runs from the parent of the hidden repo dir.
        let repo = SkillsSyncService.managedRepoDir(for: .claudeCode, home: home)
        XCTAssertEqual(rec.calls[0].cwd.path, repo.deletingLastPathComponent().path)
    }

    func testSyncUpdatesWhenRepoExists() async throws {
        let repo = SkillsSyncService.managedRepoDir(for: .codex, home: home)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let rec = Recorder()
        try await SkillsSyncService.sync(
            tool: .codex, repoURL: "https://github.com/acme/skills", branch: "main",
            token: "ghp_token", home: home, runCommand: rec.run)
        XCTAssertEqual(rec.calls.count, 1)
        XCTAssertTrue(rec.calls[0].command.contains("fetch"))
        XCTAssertTrue(rec.calls[0].command.contains("reset --hard FETCH_HEAD"))
        XCTAssertEqual(rec.calls[0].cwd.path, repo.path)
    }

    /// The clone is made once; every later sync fetches `origin`. Without
    /// repointing it first, a repo URL changed in Settings never reaches an
    /// existing clone — the sync reports success while serving the old repo's
    /// skills and contexts.
    func testSyncRepointsOriginAtTheConfiguredRepoBeforeFetching() async throws {
        let repo = SkillsSyncService.managedRepoDir(for: .codex, home: home)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let rec = Recorder()
        try await SkillsSyncService.sync(
            tool: .codex, repoURL: "https://github.com/acme/new-skills", branch: "main",
            token: "ghp_token", home: home, runCommand: rec.run)
        let command = rec.calls[0].command
        XCTAssertTrue(
            command.contains("remote set-url origin 'https://github.com/acme/new-skills'"),
            "expected the update to repoint origin, got \(command)")
        // …and to do it before fetching, or the fetch still hits the old repo.
        let repoint = command.range(of: "remote set-url")
        let fetch = command.range(of: "fetch")
        XCTAssertNotNil(repoint)
        XCTAssertNotNil(fetch)
        if let repoint, let fetch {
            XCTAssertTrue(repoint.lowerBound < fetch.lowerBound)
        }
    }

    // MARK: - Which repo a clone points at

    func testOriginURLIsReadFromTheCloneConfig() throws {
        let clone = home.appendingPathComponent("clone", isDirectory: true)
        try seedCloneConfig(at: clone, origin: "https://github.com/acme/old-skills")
        XCTAssertEqual(
            SkillsSyncService.originURL(ofClone: clone), "https://github.com/acme/old-skills")
    }

    func testCloneWithoutConfigHasNoOriginURL() throws {
        let clone = home.appendingPathComponent("bare-clone", isDirectory: true)
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        XCTAssertNil(SkillsSyncService.originURL(ofClone: clone))
    }

    func testSameRemoteIgnoresDotGitTrailingSlashAndCase() {
        XCTAssertTrue(
            SkillsSyncService.sameRemote(
                "https://github.com/acme/skills", "https://github.com/Acme/skills.git/"))
        XCTAssertFalse(
            SkillsSyncService.sameRemote(
                "https://github.com/acme/skills", "https://github.com/acme/other"))
    }

    func testClonesForRepoPrefersTheMatchingCloneAndSkipsAnotherRepo() throws {
        let claude = SkillsSyncService.managedRepoDir(for: .claudeCode, home: home)
        let codex = SkillsSyncService.managedRepoDir(for: .codex, home: home)
        try seedCloneConfig(at: claude, origin: "https://github.com/acme/old-skills")
        try seedCloneConfig(at: codex, origin: "https://github.com/acme/new-skills")

        let clones = SkillsSyncService.clonesForRepo(
            home: home, configuredURL: "https://github.com/acme/new-skills")

        XCTAssertEqual(clones.map(\.path), [codex.path])
    }

    func testClonesForRepoKeepsCloneWithUnreadableOriginAndAllWhenUnconfigured() throws {
        let claude = SkillsSyncService.managedRepoDir(for: .claudeCode, home: home)
        try FileManager.default.createDirectory(
            at: claude.appendingPathComponent(".git"), withIntermediateDirectories: true)

        // A clone made before this check existed still has to work: its origin
        // can't be read, so it is offered rather than discarded. The codex
        // tool has never synced, so it contributes nothing.
        XCTAssertEqual(
            SkillsSyncService.clonesForRepo(
                home: home, configuredURL: "https://github.com/acme/new-skills"
            ).map(\.path),
            [claude.path])
        // Nothing configured — nothing to match against, so offer every clone
        // that actually exists.
        let codex = SkillsSyncService.managedRepoDir(for: .codex, home: home)
        try FileManager.default.createDirectory(
            at: codex.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertEqual(
            Set(SkillsSyncService.clonesForRepo(home: home, configuredURL: "").map(\.path)),
            Set([claude.path, codex.path]))
    }

    func testClonesForRepoSkipsAToolThatHasNeverSynced() throws {
        let claude = SkillsSyncService.managedRepoDir(for: .claudeCode, home: home)
        try seedCloneConfig(at: claude, origin: "https://github.com/acme/skills")

        let clones = SkillsSyncService.clonesForRepo(
            home: home, configuredURL: "https://github.com/acme/skills")

        XCTAssertEqual(clones.map(\.path), [claude.path])
    }

    func testSyncThrowsWhenTokenMissingAndRunsNothing() async {
        let rec = Recorder()
        do {
            try await SkillsSyncService.sync(
                tool: .claudeCode, repoURL: "https://github.com/acme/skills", branch: "main",
                token: "   ", home: home, runCommand: rec.run)
            XCTFail("expected noToken error")
        } catch {
            XCTAssertTrue(error is SkillsSyncError)
            XCTAssertTrue(rec.calls.isEmpty)
        }
    }

    func testSyncThrowsWhenRepoURLMissing() async {
        let rec = Recorder()
        do {
            try await SkillsSyncService.sync(
                tool: .claudeCode, repoURL: "", branch: "main",
                token: "ghp_token", home: home, runCommand: rec.run)
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
                tool: .claudeCode, repoURL: "https://github.com/acme/skills", branch: "main",
                token: "ghp_token", home: home, runCommand: rec.run)
            XCTFail("expected gitFailed error")
        } catch let SkillsSyncError.gitFailed(code) {
            XCTAssertEqual(code, 128)
        } catch {
            XCTFail("expected gitFailed, got \(error)")
        }
    }
}
