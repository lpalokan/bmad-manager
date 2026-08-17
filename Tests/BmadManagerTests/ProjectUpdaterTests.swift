import XCTest
@testable import BmadManager

/// `ProjectUpdater` re-installs the latest module over an *existing* project
/// folder and refreshes the managed AGENTS.md blocks, without touching the
/// user's data. These mirror `ProjectCreatorTests`: a `FakeModuleSource`
/// stands in for a real clone, init is faked via the `runCommand` closure, and
/// partial-state/failure behaviour is pinned.
private struct FakeModuleSource: ModuleSource {
    let moduleRoot: URL
    let installerSource: String
    let errorBeforeBody: Error?

    init(moduleRoot: URL, installerSource: String? = nil, errorBeforeBody: Error? = nil) {
        self.moduleRoot = moduleRoot
        self.installerSource = installerSource ?? moduleRoot.path
        self.errorBeforeBody = errorBeforeBody
    }

    func withModuleRoot<T>(
        _ body: (_ moduleRoot: URL, _ installerSource: String) async throws -> T
    ) async throws -> T {
        if let errorBeforeBody { throw errorBeforeBody }
        return try await body(moduleRoot, installerSource)
    }
}

private enum FakeSourceError: Error { case missingFixture }

final class ProjectUpdaterTests: XCTestCase {
    private var projectsRoot: URL!
    private var moduleRoot: URL!

    override func setUpWithError() throws {
        projectsRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-utest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        moduleRoot = projectsRoot.appendingPathComponent("module-root", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    // MARK: - Helpers

    private func makeSettings(initCommand: String) -> AppSettings {
        AppSettings(
            projectsRoot: projectsRoot.path,
            moduleSourceKind: .gitRepo,
            moduleRepoURL: "ignored-by-fake",
            moduleRepoRef: "",
            moduleZipPath: "",
            initCommand: initCommand,
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
        )
    }

    private func makeUpdater(source: ModuleSource) -> ProjectUpdater {
        ProjectUpdater(projectService: ProjectService()) { _ in source }
    }

    /// Creates an existing project folder (with a sentinel file proving the
    /// updater reuses it rather than recreating it) and returns its item.
    @discardableResult
    private func makeProject(_ name: String, sentinel: String = "keep me") throws -> ProjectItem {
        let url = projectsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try sentinel.write(to: url.appendingPathComponent("user-data.txt"),
                           atomically: true, encoding: .utf8)
        return ProjectItem(url: url)
    }

    private func seedOkfTemplate(_ body: String) throws {
        let templates = moduleRoot.appendingPathComponent("templates", isDirectory: true)
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        try body.write(to: templates.appendingPathComponent("agents-okf-block.md"),
                       atomically: true, encoding: .utf8)
    }

    private func realRun(_ command: String, _ cwd: URL) async -> Int32 {
        let (_, exitCode) = ShellProcess.run(command: command, cwd: cwd)
        return await exitCode.value
    }

    // MARK: - Re-install over existing folder

    func testUpdateRunsInitInExistingFolder() async throws {
        let project = try makeProject("existing")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        var capturedCwd: URL?
        try await updater.update(project: project, settings: settings) { command, cwd in
            capturedCwd = cwd
            return await self.realRun(command, cwd)
        }

        XCTAssertEqual(capturedCwd?.standardizedFileURL, project.url.standardizedFileURL)
        // User data in the existing folder is untouched.
        let kept = try String(
            contentsOf: project.url.appendingPathComponent("user-data.txt"), encoding: .utf8)
        XCTAssertEqual(kept, "keep me")
    }

    func testUpdateSubstitutesPlaceholders() async throws {
        let project = try makeProject("subst")
        let settings = makeSettings(
            initCommand: "echo '{PROJECT_PATH}' > marker.txt && echo '{PROJECT_NAME}' >> marker.txt && echo '{MODULE_PATH}' >> marker.txt")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { command, cwd in
            await self.realRun(command, cwd)
        }

        let contents = try String(
            contentsOf: project.url.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertTrue(contents.contains(project.url.path))
        XCTAssertTrue(contents.contains("subst"))
        XCTAssertTrue(contents.contains(moduleRoot.path))
    }

    func testUpdateSubstitutesModuleSourcePlaceholder() async throws {
        let project = try makeProject("module-source")
        let installerSource = "https://github.com/o/r@v2.0.2"
        let settings = makeSettings(
            initCommand: "echo '{MODULE_SOURCE}' > marker.txt && echo '{MODULE_PATH}' >> marker.txt")
        let updater = makeUpdater(
            source: FakeModuleSource(moduleRoot: moduleRoot, installerSource: installerSource))

        try await updater.update(project: project, settings: settings) { command, cwd in
            await self.realRun(command, cwd)
        }

        let contents = try String(
            contentsOf: project.url.appendingPathComponent("marker.txt"), encoding: .utf8)
        XCTAssertTrue(contents.contains(installerSource))
        XCTAssertTrue(contents.contains(moduleRoot.path))
    }

    // MARK: - Output folder is a create-path-only flag (#99)

    func testUpdateDoesNotPassTheOutputFolderFlag() async throws {
        // The installer lets a CLI flag override a project's remembered answer,
        // so passing `--output-folder` here would silently flip an existing
        // project's `[core] output_folder` while its files stayed put.
        let project = try makeProject("output-folder-untouched")
        let configured = "npx bmad-method install --yes --directory '{PROJECT_PATH}'"
        let settings = makeSettings(initCommand: configured)
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        var captured: String?
        try await updater.update(project: project, settings: settings) { command, _ in
            captured = command
            return 0
        }

        let command = try XCTUnwrap(captured)
        XCTAssertFalse(command.contains("--output-folder"),
                       "the update must run the configured command as written, got \(command)")
        XCTAssertEqual(
            command,
            "npx bmad-method install --yes --directory '\(project.url.path)'")
    }

    // MARK: - AGENTS.md block refresh

    func testUpdateRefreshesBmadBlockPreservingUserContent() async throws {
        let project = try makeProject("agents-refresh")
        // A stale, hand-edited bmad block wrapped in user prose.
        try """
        # My notes

        \(AgentsFileWriter.startMarker(for: "bmad-manager:bmad"))
        STALE CONTENT
        \(AgentsFileWriter.endMarker(for: "bmad-manager:bmad"))

        More notes.
        """.write(to: project.url.appendingPathComponent("AGENTS.md"),
                  atomically: true, encoding: .utf8)
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertFalse(text.contains("STALE CONTENT"), "the stale block must be refreshed")
        XCTAssertTrue(text.contains(".agents/skills"), "the current bmad block must be written")
        XCTAssertTrue(text.contains("# My notes"), "user prose before the block survives")
        XCTAssertTrue(text.contains("More notes."), "user prose after the block survives")
    }

    func testUpdateInjectsOkfBlockWhenTemplatePresent() async throws {
        let project = try makeProject("with-okf")
        try seedOkfTemplate("# OKF\n\nUse the company-context OKF bundle.")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.startMarker(for: "marketing-growth:okf")))
        XCTAssertTrue(text.contains("Use the company-context OKF bundle."))
        // The bmad block is also present.
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker))
    }

    func testUpdateSkipsOkfBlockWhenTemplateAbsent() async throws {
        // No templates/agents-okf-block.md in the clone (today's reality).
        let project = try makeProject("no-okf")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        try await updater.update(project: project, settings: settings) { _, _ in 0 }

        let text = try String(
            contentsOf: project.url.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker), "bmad block still refreshed")
        XCTAssertFalse(text.contains("marketing-growth:okf"),
                       "okf block stays dormant until the template ships")
    }

    // MARK: - Failure / partial state

    func testUpdateFailsOnNonZeroExitAndLeavesProjectInspectable() async throws {
        let project = try makeProject("fails")
        let settings = makeSettings(initCommand: "exit 42")
        let updater = makeUpdater(source: FakeModuleSource(moduleRoot: moduleRoot))

        do {
            try await updater.update(project: project, settings: settings) { _, _ in 42 }
            XCTFail("expected throw")
        } catch ProjectUpdateError.initCommandFailed(let code) {
            XCTAssertEqual(code, 42)
        }

        // The project folder and the user's data are intact.
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
        let kept = try String(
            contentsOf: project.url.appendingPathComponent("user-data.txt"), encoding: .utf8)
        XCTAssertEqual(kept, "keep me")
    }

    func testUpdatePropagatesSourceError() async throws {
        let project = try makeProject("source-error")
        let settings = makeSettings(initCommand: "true")
        let updater = makeUpdater(
            source: FakeModuleSource(moduleRoot: moduleRoot, errorBeforeBody: FakeSourceError.missingFixture))

        do {
            try await updater.update(project: project, settings: settings) { _, _ in 0 }
            XCTFail("expected throw")
        } catch FakeSourceError.missingFixture {
            // expected — the source's own error propagates unchanged
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.path))
    }

    // MARK: - The check's own diagnostic line (issue #105)
    //
    // The line written per project is the only window the user has into why a
    // project did or didn't get an Update button. It has to name the context
    // state actually reached, or an unresolvable upstream reads as "current"
    // and the wrong answer stays invisible.

    private var skillsRepo: URL {
        projectsRoot.appendingPathComponent("skills-repo", isDirectory: true)
    }

    private func putSkillsOKF(_ name: String, _ file: String, date: String, body: String = "v1")
        throws
    {
        let dir = skillsRepo.appendingPathComponent("context/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "---\ntags: [company-context, \(name)]\nlast_updated: \(date)\n---\n\(body)\n"
        try text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private func installModule(_ project: ProjectItem, version: String) throws {
        let config = project.url.appendingPathComponent("_bmad/_config", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try "modules:\n  - name: marketing-growth\n    version: \(version)\n"
            .write(to: config.appendingPathComponent("manifest.yaml"),
                   atomically: true, encoding: .utf8)
    }

    private func seedContext(_ project: ProjectItem, from name: String) throws {
        let service = CompanyContextService()
        let source = try XCTUnwrap(
            service.githubContexts(inRepoRoot: skillsRepo).first { $0.projectName == name })
        // Copied rather than imported, so no seed marker is written and the
        // resolution itself is under test.
        let dest = project.url.appendingPathComponent("output/company-context", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for file in source.files {
            try FileManager.default.copyItem(
                at: source.directoryURL.appendingPathComponent(file),
                to: dest.appendingPathComponent(file))
        }
    }

    private func evaluate(_ project: ProjectItem, latest: String) -> UpdateVerdict {
        ProjectUpdater.evaluate(
            project: project,
            repoModule: ModuleManifest.RepoModule(code: "marketing-growth", version: latest),
            sources: CompanyContextService().githubContexts(inRepoRoot: skillsRepo))
    }

    func testCheckLineReportsDriftOnTheContextAxis() throws {
        let project = try makeProject("drifted")
        try installModule(project, version: "2.1.0")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try seedContext(project, from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        let verdict = evaluate(project, latest: "2.1.0")

        XCTAssertTrue(verdict.needsUpdate)
        XCTAssertTrue(verdict.line.contains("context=drift"), verdict.line)
        XCTAssertTrue(verdict.line.contains("-> UPDATE"), verdict.line)
    }

    func testCheckLineReportsAnUnresolvableUpstreamAsNoUpstream() throws {
        let project = try makeProject("split")
        try installModule(project, version: "2.1.0")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("healthcare", "positioning.md", date: "2026-06-26")
        try seedContext(project, from: "digital-workforce")
        // A second file naming the other published pack: the vote ties, and
        // both packs carry the same single filename, so overlap ties too.
        try "---\ntags: [company-context, healthcare]\n---\nlocal\n".write(
            to: project.url.appendingPathComponent("output/company-context/vertical.md"),
            atomically: true, encoding: .utf8)
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        let verdict = evaluate(project, latest: "2.1.0")

        XCTAssertFalse(verdict.needsUpdate)
        XCTAssertTrue(verdict.line.contains("context=no-upstream"), verdict.line)
    }

    func testCheckLineReportsAProjectWithNoContextAtAll() throws {
        let project = try makeProject("module-only")
        try installModule(project, version: "2.1.0")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")

        let verdict = evaluate(project, latest: "2.1.0")

        XCTAssertTrue(verdict.line.contains("context=no-context"), verdict.line)
        XCTAssertTrue(verdict.line.contains("installed=2.1.0 latest=2.1.0"), verdict.line)
    }
}
