import XCTest
@testable import BmadManager

/// Scenario-style coverage for proposing additions (personal skills + project
/// contexts) to the shared repo as a pull request. Pure helpers (URL parsing,
/// enumeration, payload assembly, name safety) are tested directly; the GitHub
/// choreography is tested with a fake client — no real network.
final class ContributionServiceTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeSkill(in root: URL, _ name: String) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# \(name)".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    // MARK: - Pure helpers

    func testParseOwnerRepoFromAssortedURLs() {
        XCTAssertEqual(ContributionService.parseOwnerRepo("https://github.com/acme/skills").map { "\($0.owner)/\($0.repo)" }, "acme/skills")
        XCTAssertEqual(ContributionService.parseOwnerRepo("https://github.com/acme/skills.git/").map { "\($0.owner)/\($0.repo)" }, "acme/skills")
        XCTAssertEqual(ContributionService.parseOwnerRepo("git@github.com:acme/skills.git").map { "\($0.owner)/\($0.repo)" }, "acme/skills")
        XCTAssertNil(ContributionService.parseOwnerRepo("https://gitlab.com/acme/skills"))
        XCTAssertNil(ContributionService.parseOwnerRepo("https://github.com/acme"))
    }

    func testSanitizeNameRejectsTraversalAndEmpty() throws {
        XCTAssertEqual(try ContributionService.sanitizeName("  my-skill "), "my-skill")
        XCTAssertThrowsError(try ContributionService.sanitizeName("../evil"))
        XCTAssertThrowsError(try ContributionService.sanitizeName("a/b"))
        XCTAssertThrowsError(try ContributionService.sanitizeName(".hidden"))
        XCTAssertThrowsError(try ContributionService.sanitizeName(""))
    }

    func testEnumeratePersonalSkillsExcludesManagedLinks() throws {
        let claude = SkillsSyncService.skillsRoot(for: .claudeCode, home: home)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try makeSkill(in: claude, "mine")
        // A managed skill: real target elsewhere, symlinked into the skills root.
        let target = try makeSkill(in: home.appendingPathComponent("skills-managed"), "managed-skill")
        try FileManager.default.createSymbolicLink(
            at: claude.appendingPathComponent("managed-skill"), withDestinationURL: target)
        // A folder without SKILL.md.
        try FileManager.default.createDirectory(
            at: claude.appendingPathComponent("not-a-skill"), withIntermediateDirectories: true)

        let skills = ContributionService.enumeratePersonalSkills(home: home)
        XCTAssertEqual(skills.map(\.name), ["mine"])
    }

    func testPrepareSkillFilesRecursesUnderSkillsPrefix() throws {
        let dir = home.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "doc".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "code".write(to: dir.appendingPathComponent("sub/helper.py"), atomically: true, encoding: .utf8)

        let files = try ContributionService.prepareSkillFiles(name: "my-skill", dir: dir)
        XCTAssertEqual(files.map(\.repoPath),
                       ["skills/my-skill/SKILL.md", "skills/my-skill/sub/helper.py"])
    }

    func testPrepareContextFilesStagesEverySelectedFile() throws {
        // The context is "all files in the folder", so a user-added file like
        // notes.txt must be contributed too, not silently dropped.
        let dir = home.appendingPathComponent("ctx", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in ["icp.md", "kpis.md", "notes.txt"] {
            try "x".write(to: dir.appendingPathComponent(f), atomically: true, encoding: .utf8)
        }
        let files = try ContributionService.prepareContextFiles(
            name: "acme", dir: dir, selected: ["icp.md", "kpis.md", "notes.txt"])
        XCTAssertEqual(
            files.map(\.repoPath),
            ["context/acme/icp.md", "context/acme/kpis.md", "context/acme/notes.txt"])
    }

    func testPrepareContextFilesSkipsSelectedFilesThatVanished() throws {
        let dir = home.appendingPathComponent("ctx2", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("icp.md"), atomically: true, encoding: .utf8)
        // "gone.md" is selected but not on disk — it should be skipped, not error.
        let files = try ContributionService.prepareContextFiles(
            name: "acme", dir: dir, selected: ["icp.md", "gone.md"])
        XCTAssertEqual(files.map(\.repoPath), ["context/acme/icp.md"])
    }

    func testPrepareSkillFilesRejectsOversized() throws {
        let dir = home.appendingPathComponent("big", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let big = Data(count: ContributionService.maxFileBytes + 1)
        try big.write(to: dir.appendingPathComponent("blob.bin"))
        XCTAssertThrowsError(try ContributionService.prepareSkillFiles(name: "big", dir: dir)) { error in
            guard case ContributionError.fileTooLarge = error else {
                return XCTFail("expected fileTooLarge, got \(error)")
            }
        }
    }

    func testBranchAndPRTextCompose() {
        XCTAssertEqual(ContributionService.buildBranchName(login: "ada", timestamp: "123"), "contrib/ada-123")
        XCTAssertEqual(
            ContributionService.buildPRTitle(skills: ["foo"], contexts: ["acme"]),
            "Add skill(s): foo; context(s): acme")
        XCTAssertTrue(ContributionService.buildPRBody(skills: ["foo"], contexts: [], login: "ada").contains("skills/foo/"))
    }

    // MARK: - Orchestration with a fake client

    func testSubmitRunsFullChoreographyAndReturnsPR() async throws {
        let dir = try makeSkill(in: home, "foo")
        let client = FakeGitHubClient()

        let result = try await ContributionService.submitContribution(
            client: client, owner: "acme", repo: "skills",
            skills: [.init(name: "foo", directory: dir)], contexts: [],
            title: nil, timestamp: "ts")

        XCTAssertEqual(result.number, 7)
        XCTAssertEqual(result.url, "https://github.com/acme/skills/pull/7")
        XCTAssertEqual(client.calls,
                       ["whoami", "defaultBranch", "createBlob", "createTree",
                        "createCommit", "createBranchRef", "createPull"])
    }

    func testSubmitBlocksWhenTargetFolderExists() async throws {
        let dir = try makeSkill(in: home, "foo")
        let client = FakeGitHubClient()
        client.existingPaths = ["skills/foo"]

        do {
            _ = try await ContributionService.submitContribution(
                client: client, owner: "acme", repo: "skills",
                skills: [.init(name: "foo", directory: dir)], contexts: [],
                title: nil, timestamp: "ts")
            XCTFail("expected collision error")
        } catch {
            guard case ContributionError.collision = error else {
                return XCTFail("expected collision, got \(error)")
            }
        }
        XCTAssertFalse(client.calls.contains("createBlob"))
    }

    func testSubmitRequiresASelection() async {
        let client = FakeGitHubClient()
        do {
            _ = try await ContributionService.submitContribution(
                client: client, owner: "acme", repo: "skills",
                skills: [], contexts: [], title: nil, timestamp: "ts")
            XCTFail("expected nothingSelected")
        } catch {
            XCTAssertEqual(error as? ContributionError, .nothingSelected)
        }
    }

    func testSubmitSurfacesAPullFailure() async throws {
        let dir = try makeSkill(in: home, "foo")
        let client = FakeGitHubClient()
        client.failOnPull = true
        do {
            _ = try await ContributionService.submitContribution(
                client: client, owner: "acme", repo: "skills",
                skills: [.init(name: "foo", directory: dir)], contexts: [],
                title: nil, timestamp: "ts")
            XCTFail("expected GitHub error")
        } catch {
            guard case GitHubError.api(let status, _) = error else {
                return XCTFail("expected api error, got \(error)")
            }
            XCTAssertEqual(status, 422)
        }
    }
}

/// Records the operations a submit would issue, with canned responses.
private final class FakeGitHubClient: GitHubClient, @unchecked Sendable {
    var calls: [String] = []
    var existingPaths: [String] = []
    var failOnPull = false

    func whoami() async throws -> String { calls.append("whoami"); return "ada" }
    func repoAccess(owner: String, repo: String) async throws -> GitHubRepoAccess {
        GitHubRepoAccess(login: "ada", repoFullName: "\(owner)/\(repo)", canPush: true)
    }
    func defaultBranch(owner: String, repo: String) async throws -> String {
        calls.append("defaultBranch"); return "main"
    }
    func branchHeadSHA(owner: String, repo: String, branch: String) async throws -> String { "basecommit" }
    func commitTreeSHA(owner: String, repo: String, commitSHA: String) async throws -> String { "basetree" }
    func pathExists(owner: String, repo: String, path: String, branch: String) async throws -> Bool {
        existingPaths.contains(path)
    }
    func createBlob(owner: String, repo: String, contentBase64: String) async throws -> String {
        calls.append("createBlob"); return "blobsha"
    }
    func createTree(owner: String, repo: String, baseTree: String, entries: [GitHubTreeEntry]) async throws -> String {
        calls.append("createTree"); return "newtree"
    }
    func createCommit(owner: String, repo: String, message: String, tree: String, parent: String) async throws -> String {
        calls.append("createCommit"); return "newcommit"
    }
    func createBranchRef(owner: String, repo: String, branch: String, sha: String) async throws {
        calls.append("createBranchRef")
    }
    func createPull(owner: String, repo: String, title: String, head: String, base: String, body: String) async throws -> GitHubPullResult {
        calls.append("createPull")
        if failOnPull { throw GitHubError.api(status: 422, message: "validation failed") }
        return GitHubPullResult(htmlURL: "https://github.com/acme/skills/pull/7", number: 7)
    }
}
