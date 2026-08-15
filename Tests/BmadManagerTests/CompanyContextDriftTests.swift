import XCTest
@testable import BmadManager

/// Scenario-style coverage for detecting when a project's company-context has
/// drifted behind the skills-repo context it was seeded from, and for
/// refreshing it (issue #92). Mirrors the Tauri `company_context.feature`
/// drift scenarios: drift is read from the OKF `last_updated` date the context
/// files carry (with a byte fallback for dateless files), and a project is
/// linked to its source context by the OKF `tags` slug its own files carry.
final class CompanyContextDriftTests: XCTestCase {
    private var root: URL!
    private let service = CompanyContextService()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-ctx-drift-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var skillsRepo: URL {
        root.appendingPathComponent("skills-repo", isDirectory: true)
    }

    /// Writes (or overwrites) an OKF file in the skills-repo `context/<name>/`:
    /// frontmatter carrying the source slug as a tag and an optional
    /// `last_updated` date, then `body`. Models both publishing and editing.
    private func putSkillsOKF(_ name: String, _ file: String, date: String?, body: String = "v1") throws {
        let dir = skillsRepo.appendingPathComponent("context/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var text = "---\ntags: [company-context, \(name)]\n"
        if let date { text += "last_updated: \(date)\n" }
        text += "---\n\(body)\n"
        try text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private func sources() -> [CompanyContext] {
        service.githubContexts(inRepoRoot: skillsRepo)
    }

    /// Seeds `<root>/projects/<project>` from the named skills context, the way
    /// create-time import does, so the project's copies carry the source tags.
    @discardableResult
    private func seedProject(_ project: String, from name: String) throws -> URL {
        let url = root.appendingPathComponent("projects/\(project)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let source = try XCTUnwrap(sources().first { $0.projectName == name })
        try service.importContext(source, into: url)
        return url
    }

    /// Same, but copying the files into an explicit layout instead of the one
    /// `importContext` writes to — models a project seeded before `output/`
    /// became the manager's write target (issue #96).
    @discardableResult
    private func seedProject(_ project: String, from name: String, at subpath: String) throws -> URL {
        let url = root.appendingPathComponent("projects/\(project)", isDirectory: true)
        let dest = url.appendingPathComponent(subpath, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let source = try XCTUnwrap(sources().first { $0.projectName == name })
        for file in source.files {
            try FileManager.default.copyItem(
                at: source.directoryURL.appendingPathComponent(file),
                to: dest.appendingPathComponent(file))
        }
        return url
    }

    private func hasContextUpdate(_ projectURL: URL) -> Bool {
        service.isProjectContextStale(projectURL: projectURL, sources: sources())
    }

    private func contextDir(_ projectURL: URL) -> URL {
        projectURL.appendingPathComponent("output/company-context", isDirectory: true)
    }

    // MARK: - Drift detection

    func testProjectInSyncWithItsSourceReportsNoDrift() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        XCTAssertFalse(hasContextUpdate(proj))
    }

    func testAdminEditThatBumpsLastUpdatedFlagsTheProject() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")
        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testOlderOrEqualSourceDateIsNotDrift() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        // A later local snapshot than the source: nothing to pull.
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-01", body: "v2")
        XCTAssertFalse(hasContextUpdate(proj))
    }

    func testChangedDatelessFileIsCaughtByContentFallback() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("digital-workforce", "index.md", date: nil, body: "one link")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "index.md", date: nil, body: "two links")
        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testSourceThatAddedANewFileFlagsTheProject() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "kpis.md", date: "2026-06-26")
        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testProjectWhoseSourceIsNoLongerPublishedIsLeftAlone() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("orphan", from: "digital-workforce")
        try FileManager.default.removeItem(
            at: skillsRepo.appendingPathComponent("context/digital-workforce"))
        XCTAssertFalse(hasContextUpdate(proj))
    }

    // MARK: - Refresh

    @discardableResult
    private func refresh(_ proj: URL) throws -> RefreshSummary {
        let projectContext = try XCTUnwrap(service.context(inProject: proj))
        let source = try XCTUnwrap(service.sourceContext(for: projectContext, in: sources()))
        // A fixed stamp keeps the backup folder deterministic; the app passes
        // a timestamp.
        return try service.refreshContext(
            source, into: projectContext.directoryURL, backupStamp: "20260815-000000")
    }

    func testRefreshingOverwritesDriftedFiles() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        try refresh(proj)

        let text = try String(
            contentsOf: contextDir(proj).appendingPathComponent("positioning.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("last_updated: 2026-07-03"))
    }

    func testRefreshingAddsNewFilesAndKeepsProjectLocalFiles() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try "local".write(
            to: contextDir(proj).appendingPathComponent("notes-local.md"),
            atomically: true, encoding: .utf8)
        try putSkillsOKF("digital-workforce", "kpis.md", date: "2026-07-03")

        try refresh(proj)

        for file in ["positioning.md", "kpis.md", "notes-local.md"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: contextDir(proj).appendingPathComponent(file).path),
                "expected '\(file)' to survive the refresh")
        }
    }

    /// A project still on the legacy layout is refreshed where it already
    /// lives — the manager never relocates an existing bundle (issue #96).
    func testRefreshingALegacyBmadOutputProjectRewritesItInPlace() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("legacy", from: "digital-workforce",
                                   at: "_bmad-output/company-context")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")
        XCTAssertTrue(hasContextUpdate(proj))

        try refresh(proj)

        let text = try String(
            contentsOf: proj.appendingPathComponent("_bmad-output/company-context/positioning.md"),
            encoding: .utf8)
        XCTAssertTrue(text.contains("last_updated: 2026-07-03"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: proj.appendingPathComponent("output").path),
            "a refresh must not relocate the bundle into output/")
    }

    /// The canonical loop (issue #92): seeded in sync, admin bumps the date,
    /// the project shows drift, a refresh brings it current, drift clears.
    func testRefreshingThenReCheckingClearsTheDrift() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")
        XCTAssertTrue(hasContextUpdate(proj))

        try refresh(proj)

        XCTAssertFalse(hasContextUpdate(proj))
    }

    // MARK: - Resolving which context a project was seeded from (issue #103)
    //
    // OKF `tags` carry two different things: the pack's own identity slug and
    // subject keywords. A file naming another vertical as its subject must not
    // cost the project its upstream link, and a pack bundled inside the context
    // folder must not outvote the pack the project was seeded from.

    /// Writes a project-local context file carrying explicit tags — models an
    /// OKF file that names another pack as subject matter, not identity.
    private func putLocalTagged(_ proj: URL, _ file: String, tags: [String]) throws {
        let dir = contextDir(proj)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "---\ntags: [company-context, \(tags.joined(separator: ", "))]\n---\nlocal\n"
        try text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    /// Copies a whole skills-repo pack into a sub-folder of the project's own
    /// context — a project bundling a second pack beside the one it was seeded
    /// from.
    private func bundlePack(_ proj: URL, _ name: String) throws {
        let source = try XCTUnwrap(sources().first { $0.projectName == name })
        let dest = contextDir(proj).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for file in source.files {
            try FileManager.default.copyItem(
                at: source.directoryURL.appendingPathComponent(file),
                to: dest.appendingPathComponent(file))
        }
    }

    func testSubjectMatterTagNamingAnotherPackDoesNotBlockResolution() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("healthcare", "positioning.md", date: "2026-06-26")
        // Seeded the pre-#103 way, so the tag vote itself is under test.
        let proj = try seedProject("investor-day", from: "digital-workforce",
                                   at: "output/company-context")
        try putLocalTagged(proj, "offerings.md", tags: ["digital-workforce", "healthcare"])
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testBundledSubPackDoesNotOutvoteTheSeededPack() throws {
        try putSkillsOKF("enterprise-public-sector", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("agent-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("agent-workforce", "icp.md", date: "2026-06-26")
        try putSkillsOKF("agent-workforce", "kpis.md", date: "2026-06-26")
        let proj = try seedProject("gtm", from: "enterprise-public-sector",
                                   at: "output/company-context")
        try bundlePack(proj, "agent-workforce")
        try putSkillsOKF("enterprise-public-sector", "positioning.md", date: "2026-07-03", body: "v2")

        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testEvenlySplitVoteStaysUnresolved() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("healthcare", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("split", from: "digital-workforce",
                                   at: "output/company-context")
        try putLocalTagged(proj, "vertical.md", tags: ["healthcare"])
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        XCTAssertFalse(hasContextUpdate(proj))
    }

    func testSeedMarkerResolvesTheSourceEvenWhenTheVoteIsTied() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        try putSkillsOKF("healthcare", "positioning.md", date: "2026-06-26")
        // Seeded through importContext, which records the marker.
        let proj = try seedProject("marked", from: "digital-workforce")
        try putLocalTagged(proj, "vertical.md", tags: ["healthcare"])
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        XCTAssertTrue(hasContextUpdate(proj))
    }

    func testSeedingRecordsTheSourceMarker() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("fresh", from: "digital-workforce")

        XCTAssertEqual(
            CompanyContextService.contextSource(in: contextDir(proj)), "digital-workforce")
    }

    func testSeedMarkerIsNotTreatedAsContextContent() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("fresh", from: "digital-workforce")

        let context = try XCTUnwrap(service.context(inProject: proj))
        XCTAssertEqual(context.files, ["positioning.md"])
    }

    // MARK: - Backing up edits a refresh would overwrite (issue #103)

    /// Rewrites the body of a project's copy while leaving its frontmatter (and
    /// so its `last_updated`) intact — a user edit that does not bump the date.
    private func editProjectCopy(_ proj: URL, _ file: String, body: String) throws {
        let url = contextDir(proj).appendingPathComponent(file)
        let text = try String(contentsOf: url, encoding: .utf8)
        var head: [String] = []
        var fences = 0
        for line in text.components(separatedBy: "\n") {
            head.append(line)
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                fences += 1
                if fences == 2 { break }
            }
        }
        let updated = (head + [body, ""]).joined(separator: "\n")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func backupDir(_ proj: URL) -> URL {
        contextDir(proj)
            .appendingPathComponent(CompanyContextService.backupDirName, isDirectory: true)
            .appendingPathComponent("20260815-000000", isDirectory: true)
    }

    func testRefreshBacksUpALocallyEditedFileBeforeOverwritingIt() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try editProjectCopy(proj, "positioning.md", body: "my own wording")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        try refresh(proj)

        let backup = try String(
            contentsOf: backupDir(proj).appendingPathComponent("positioning.md"), encoding: .utf8)
        XCTAssertTrue(backup.contains("my own wording"))
        let current = try String(
            contentsOf: contextDir(proj).appendingPathComponent("positioning.md"), encoding: .utf8)
        XCTAssertTrue(current.contains("last_updated: 2026-07-03"))
    }

    func testRefreshingAnUnchangedProjectBacksNothingUp() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try putSkillsOKF("digital-workforce", "kpis.md", date: "2026-06-26")

        let summary = try refresh(proj)

        XCTAssertEqual(summary.backedUp, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDir(proj).path))
    }

    /// A file the source pack does not carry is outside the refresh entirely:
    /// not overwritten, so nothing to preserve.
    func testProjectOnlyFileIsNeverOverwrittenOrBackedUp() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try "local".write(
            to: contextDir(proj).appendingPathComponent("notes-local.md"),
            atomically: true, encoding: .utf8)
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        let summary = try refresh(proj)

        XCTAssertFalse(summary.backedUp.contains("notes-local.md"))
        XCTAssertEqual(
            try String(
                contentsOf: contextDir(proj).appendingPathComponent("notes-local.md"),
                encoding: .utf8),
            "local")
    }

    func testBackupsAreNotTreatedAsContextContent() throws {
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-06-26")
        let proj = try seedProject("investor-day", from: "digital-workforce")
        try editProjectCopy(proj, "positioning.md", body: "my own wording")
        try putSkillsOKF("digital-workforce", "positioning.md", date: "2026-07-03", body: "v2")

        try refresh(proj)

        let context = try XCTUnwrap(service.context(inProject: proj))
        XCTAssertEqual(context.files, ["positioning.md"])
    }
}
