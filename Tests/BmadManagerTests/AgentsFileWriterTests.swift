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
}
