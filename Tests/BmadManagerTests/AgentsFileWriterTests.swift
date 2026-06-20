import XCTest
@testable import BmadManager

/// Codex auto-discovers the repo-scoped skills under `.agents/skills/`, but
/// it can't infer BMad's *routing* — that short menu codes map to skills via
/// `_bmad/_config/bmad-help.csv` — and bmad-method emits no Codex `AGENTS.md`.
/// `AgentsFileWriter` writes that routing into the project `AGENTS.md`; these
/// scenarios pin down create / append / refresh-in-place behaviour.
final class AgentsFileWriterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-agents-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var agentsURL: URL { dir.appendingPathComponent("AGENTS.md") }

    func testCreatesAgentsFileWhenMissing() throws {
        try AgentsFileWriter.ensureBmadSection(in: dir)

        let text = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker))
        XCTAssertTrue(text.contains(".agents/skills"),
                      "must point Codex at the installed skills")
        XCTAssertTrue(text.contains("bmad-help"),
                      "must name the entry-point skill")
        XCTAssertTrue(text.contains("_bmad/_config/bmad-help.csv"),
                      "must reference the menu-code map")
        XCTAssertTrue(text.lowercased().contains("menu code"),
                      "must explain menu-code routing — the real gap for Codex")
    }

    func testAppendsToExistingAgentsFileWithoutBmadSection() throws {
        try "# My project\n\nHand-written agent notes.\n"
            .write(to: agentsURL, atomically: true, encoding: .utf8)

        try AgentsFileWriter.ensureBmadSection(in: dir)

        let text = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertTrue(text.contains("Hand-written agent notes."),
                      "must preserve the user's existing content")
        XCTAssertTrue(text.contains(AgentsFileWriter.sectionMarker),
                      "must append the BMad section")
    }

    func testIsIdempotentWhenSectionAlreadyPresent() throws {
        try AgentsFileWriter.ensureBmadSection(in: dir)
        let firstPass = try String(contentsOf: agentsURL, encoding: .utf8)

        try AgentsFileWriter.ensureBmadSection(in: dir)
        let secondPass = try String(contentsOf: agentsURL, encoding: .utf8)

        XCTAssertEqual(firstPass, secondPass, "re-running must not change the file")
        let occurrences = secondPass.components(separatedBy: AgentsFileWriter.sectionMarker).count - 1
        XCTAssertEqual(occurrences, 1, "the BMad section must appear exactly once")
    }

    // MARK: - Generalized managed sections (parameterized namespace + body)

    func testConstantsMatchDerivedBmadMarkers() {
        // The public `sectionMarker` (which other tests pin) must stay in lock
        // step with the derived markers, so the wrapper and constant can't drift.
        XCTAssertEqual(AgentsFileWriter.sectionMarker,
                       AgentsFileWriter.startMarker(for: "bmad-manager:bmad"))
    }

    func testEnsureManagedSectionCreatesFileForArbitraryNamespace() throws {
        try AgentsFileWriter.ensureManagedSection(
            in: dir, namespace: "marketing-growth:okf", body: "OKF body line")

        let text = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertTrue(text.contains(AgentsFileWriter.startMarker(for: "marketing-growth:okf")))
        XCTAssertTrue(text.contains(AgentsFileWriter.endMarker(for: "marketing-growth:okf")))
        XCTAssertTrue(text.contains("OKF body line"))
    }

    func testTwoNamespacesCoexistInOneFile() throws {
        try AgentsFileWriter.ensureBmadSection(in: dir)
        try AgentsFileWriter.ensureManagedSection(
            in: dir, namespace: "marketing-growth:okf", body: "OKF body line")

        let text = try String(contentsOf: agentsURL, encoding: .utf8)
        // Both managed blocks present, each exactly once.
        XCTAssertEqual(text.components(separatedBy: AgentsFileWriter.sectionMarker).count - 1, 1)
        XCTAssertEqual(
            text.components(separatedBy: AgentsFileWriter.startMarker(for: "marketing-growth:okf")).count - 1, 1)
        XCTAssertTrue(text.contains(".agents/skills"), "bmad block untouched by the okf write")
        XCTAssertTrue(text.contains("OKF body line"))
    }

    func testEnsureManagedSectionRefreshesOnlyItsOwnBlock() throws {
        try AgentsFileWriter.ensureBmadSection(in: dir)
        try AgentsFileWriter.ensureManagedSection(
            in: dir, namespace: "marketing-growth:okf", body: "first okf body")
        let bmadBlock = AgentsFileWriter.bmadBlock()

        // Refresh only the okf block with new content.
        try AgentsFileWriter.ensureManagedSection(
            in: dir, namespace: "marketing-growth:okf", body: "second okf body")

        let text = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertTrue(text.contains("second okf body"))
        XCTAssertFalse(text.contains("first okf body"), "old okf body must be replaced")
        XCTAssertTrue(text.contains(bmadBlock), "bmad block must be byte-identical")
        XCTAssertEqual(
            text.components(separatedBy: AgentsFileWriter.startMarker(for: "marketing-growth:okf")).count - 1, 1)
    }

    func testEnsureManagedSectionHonoursCustomFileName() throws {
        try AgentsFileWriter.ensureManagedSection(
            in: dir, fileName: "OTHER.md", namespace: "marketing-growth:okf", body: "OKF body line")

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("OTHER.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsURL.path),
                       "AGENTS.md must not be written when a custom file name is given")
    }
}
