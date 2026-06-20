import XCTest
@testable import BmadManager

/// Scenario-style coverage for resolving company contexts inside projects
/// and importing one into a newly created project. The recognized file set
/// and the resolution order (`_bmad-output/company-context` then
/// `company-context`) mirror the bmad-marketing-growth module's
/// company-context-bootstrap workflow.
///
/// Walking the projects folder is `ProjectService.listProjects`'
/// responsibility (and tested there) — this suite hands the service
/// `ProjectItem`s directly.
final class CompanyContextServiceTests: XCTestCase {
    private var projectsRoot: URL!
    private let service = CompanyContextService()

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-ctx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    /// Creates `<projectsRoot>/<project>/<subpath>/` containing the given
    /// files, returning the project folder URL.
    @discardableResult
    private func makeProject(
        _ name: String,
        contextAt subpath: String? = "_bmad-output/company-context",
        files: [String] = []
    ) throws -> URL {
        let projectURL = projectsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        if let subpath {
            let contextDir = projectURL.appendingPathComponent(subpath, isDirectory: true)
            try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
            for file in files {
                try "content of \(file) from \(name)".write(
                    to: contextDir.appendingPathComponent(file),
                    atomically: true, encoding: .utf8
                )
            }
        }
        return projectURL
    }

    private func items(_ urls: URL...) -> [ProjectItem] {
        urls.map { ProjectItem(url: $0) }
    }

    // MARK: - Resolution

    func testFindsContextUnderBmadOutputCompanyContext() throws {
        let acme = try makeProject("acme", files: ["icp.md", "positioning.md"])

        let context = try XCTUnwrap(service.context(inProject: acme))

        XCTAssertEqual(context.projectName, "acme")
        XCTAssertEqual(context.files, ["icp.md", "positioning.md"])
    }

    func testFindsContextUnderTopLevelCompanyContextFallback() throws {
        let legacy = try makeProject("legacy", contextAt: "company-context",
                                     files: ["brand-voice.md"])

        let context = try XCTUnwrap(service.context(inProject: legacy))

        XCTAssertEqual(context.projectName, "legacy")
        XCTAssertEqual(context.files, ["brand-voice.md"])
    }

    func testPrefersBmadOutputLocationOverTopLevelFallback() throws {
        let projectURL = try makeProject("both", files: ["icp.md"])
        let fallbackDir = projectURL.appendingPathComponent("company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        try "fallback".write(to: fallbackDir.appendingPathComponent("kpis.md"),
                             atomically: true, encoding: .utf8)

        let context = try XCTUnwrap(service.context(inProject: projectURL))

        XCTAssertEqual(context.files, ["icp.md"])
        // Resolve symlinks on both sides: on macOS file URLs under
        // NSTemporaryDirectory() mix the /var symlink and the real
        // /private/var path.
        XCTAssertEqual(
            context.directoryURL.resolvingSymlinksInPath().path,
            projectURL.appendingPathComponent("_bmad-output/company-context")
                .resolvingSymlinksInPath().path
        )
    }

    func testIgnoresProjectsWithoutAnyContextFiles() throws {
        // A context folder counts only when it actually holds files. An empty
        // folder, or no folder at all, is still "no context".
        let empty = try makeProject("empty-context", files: [])
        let bare = try makeProject("no-context-dir", contextAt: nil)

        XCTAssertNil(service.context(inProject: empty))
        XCTAssertNil(service.context(inProject: bare))
        XCTAssertTrue(service.contexts(in: items(empty, bare)).isEmpty)
    }

    func testFindsContextWhenOnlyUnrecognizedFilesArePresent() throws {
        // Extra files the user dropped into the context folder (beyond the
        // five canonical names) make the folder a valid context too — they
        // must not be silently ignored.
        let custom = try makeProject("only-custom", files: ["bootstrap-summary.md"])

        let context = try XCTUnwrap(service.context(inProject: custom))
        XCTAssertEqual(context.files, ["bootstrap-summary.md"])
    }

    func testListsAllFilesWithRecognizedOnesFirstInCanonicalOrder() throws {
        // Pull *every* file in the folder: recognized names first in canonical
        // order, then the rest alphabetically. Hidden files are skipped.
        let mixed = try makeProject(
            "mixed",
            files: ["tech-stack.md", "bootstrap-summary.md", "icp.md", "notes.txt"]
        )

        let context = try XCTUnwrap(service.context(inProject: mixed))

        XCTAssertEqual(
            context.files,
            ["icp.md", "tech-stack.md", "bootstrap-summary.md", "notes.txt"]
        )
    }

    func testSkipsHiddenFilesAndSubdirectoriesWhenListing() throws {
        let project = try makeProject("with-extras", files: ["icp.md", "extra.md"])
        let contextDir = project
            .appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        try "hidden".write(to: contextDir.appendingPathComponent(".DS_Store"),
                           atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: contextDir.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true)

        let context = try XCTUnwrap(service.context(inProject: project))
        XCTAssertEqual(context.files, ["icp.md", "extra.md"])
    }

    func testContextsSortByProjectNameRegardlessOfInputOrder() throws {
        let zeta = try makeProject("zeta", files: ["icp.md"])
        let alpha = try makeProject("Alpha", files: ["icp.md"])
        let beta = try makeProject("beta", files: ["icp.md"])
        let none = try makeProject("no-context", contextAt: nil)

        let contexts = service.contexts(in: items(zeta, none, alpha, beta))

        XCTAssertEqual(contexts.map(\.projectName), ["Alpha", "beta", "zeta"])
    }

    // MARK: - Import

    func testImportCopiesRecognizedFilesIntoNewProject() throws {
        let source = try makeProject("source", files: ["icp.md", "kpis.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(service.context(inProject: source))

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "content of icp.md from source")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("kpis.md").path))
    }

    func testImportCarriesAllContextFilesOver() throws {
        // Every file in the source context folder is copied — including ones
        // beyond the five canonical names the user added themselves.
        let source = try makeProject(
            "source", files: ["icp.md", "bootstrap-summary.md", "extra-notes.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(service.context(inProject: source))

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        for file in ["icp.md", "bootstrap-summary.md", "extra-notes.md"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: destDir.appendingPathComponent(file).path),
                "expected '\(file)' to be imported")
        }
    }

    func testImportLeavesExistingDestinationFilesUntouched() throws {
        // Never overwrite silently — if the init command (or the user)
        // already put a context file in place, the import keeps it.
        let source = try makeProject("source", files: ["icp.md", "positioning.md"])
        let target = try makeProject("the-target", files: ["icp.md"])
        let context = try XCTUnwrap(service.context(inProject: source))

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        let icp = try String(
            contentsOf: destDir.appendingPathComponent("icp.md"), encoding: .utf8)
        XCTAssertEqual(icp, "content of icp.md from the-target")
        let positioning = try String(
            contentsOf: destDir.appendingPathComponent("positioning.md"), encoding: .utf8)
        XCTAssertEqual(positioning, "content of positioning.md from source")
    }

    func testImportFailsWithReadableErrorWhenSourceFileVanished() throws {
        let source = try makeProject("source", files: ["icp.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(service.context(inProject: source))
        try FileManager.default.removeItem(
            at: context.directoryURL.appendingPathComponent("icp.md"))

        XCTAssertThrowsError(try service.importContext(context, into: target)) { error in
            XCTAssertTrue(error.localizedDescription.contains("icp.md"))
        }
    }

    // MARK: - Display

    func testDisplayNameIsProjectNameWithFolderMarker() {
        // The context is now "all files in the folder", so there's no fixed
        // denominator to flag a partial context against — just name + marker.
        let context = CompanyContext(
            projectName: "acme",
            directoryURL: URL(fileURLWithPath: "/tmp/acme/_bmad-output/company-context"),
            files: ["icp.md", "kpis.md", "custom.md"]
        )
        XCTAssertEqual(context.displayName, "acme 📂")
    }

    func testGithubContextDisplayNameCarriesTheGithubMarker() {
        let context = CompanyContext(
            projectName: "acme",
            directoryURL: URL(fileURLWithPath: "/tmp/repo/context/acme"),
            files: ["icp.md"],
            source: .github
        )
        XCTAssertEqual(context.displayName, "acme 🐙")
    }

    // MARK: - GitHub repo contexts

    /// Seeds `<repo>/context/<name>/` with the given files.
    @discardableResult
    private func makeGithubContext(
        inRepo repo: URL,
        _ name: String,
        files: [String]
    ) throws -> URL {
        let dir = repo
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files {
            try "content of \(file)".write(
                to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testGithubContextsDiscoversContextFoldersTaggedAsGithub() throws {
        let repo = projectsRoot.appendingPathComponent("skills-repo", isDirectory: true)
        try makeGithubContext(inRepo: repo, "globex", files: ["positioning.md"])
        try makeGithubContext(inRepo: repo, "acme", files: ["icp.md", "kpis.md"])

        let contexts = service.githubContexts(inRepoRoot: repo)

        XCTAssertEqual(contexts.map(\.projectName), ["acme", "globex"])
        XCTAssertTrue(contexts.allSatisfy { $0.source == .github })
        XCTAssertEqual(contexts.first?.files, ["icp.md", "kpis.md"])
    }

    func testGithubContextsIgnoreEmptyFolders() throws {
        let repo = projectsRoot.appendingPathComponent("skills-repo", isDirectory: true)
        let dir = repo
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        XCTAssertTrue(service.githubContexts(inRepoRoot: repo).isEmpty)
    }

    func testGithubContextsIncludeFoldersWithOnlyCustomFiles() throws {
        // A skills-repo context folder with non-canonical files is still a
        // valid seeding source — all its files get pulled.
        let repo = projectsRoot.appendingPathComponent("skills-repo", isDirectory: true)
        try makeGithubContext(inRepo: repo, "notes", files: ["README.md", "playbook.md"])

        let contexts = service.githubContexts(inRepoRoot: repo)
        XCTAssertEqual(contexts.map(\.projectName), ["notes"])
        // Non-canonical files come back alphabetically (case-insensitive).
        XCTAssertEqual(contexts.first?.files, ["playbook.md", "README.md"])
    }

    func testGithubContextsAreEmptyWhenContextFolderMissing() {
        let repo = projectsRoot.appendingPathComponent("no-such-repo", isDirectory: true)
        XCTAssertTrue(service.githubContexts(inRepoRoot: repo).isEmpty)
    }

    func testGithubContextCanBeImportedIntoANewProject() throws {
        let repo = projectsRoot.appendingPathComponent("skills-repo", isDirectory: true)
        try makeGithubContext(inRepo: repo, "acme", files: ["icp.md"])
        let target = try makeProject("target", contextAt: nil)
        let context = try XCTUnwrap(service.githubContexts(inRepoRoot: repo).first)

        try service.importContext(context, into: target)

        let destDir = target.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("icp.md").path))
    }
}
