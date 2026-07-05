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

    private func hasContextUpdate(_ projectURL: URL) -> Bool {
        service.isProjectContextStale(projectURL: projectURL, sources: sources())
    }

    private func contextDir(_ projectURL: URL) -> URL {
        projectURL.appendingPathComponent("_bmad-output/company-context", isDirectory: true)
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

    private func refresh(_ proj: URL) throws {
        let projectContext = try XCTUnwrap(service.context(inProject: proj))
        let source = try XCTUnwrap(service.sourceContext(for: projectContext, in: sources()))
        try service.refreshContext(source, into: projectContext.directoryURL)
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
}
