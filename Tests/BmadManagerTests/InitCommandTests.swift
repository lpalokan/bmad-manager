import XCTest
@testable import BmadManager

/// The create-path-only shaping of the init-command template (issue #99).
/// New projects install with `--output-folder output` so core, bmm/bmb/cis and
/// marketing-growth share one folder instead of core keeping its own
/// `_bmad-output/`. The append is a build-time decoration of the command —
/// the stored `initCommand` setting is never rewritten.
final class InitCommandTests: XCTestCase {
    func testAppendsOutputFolderToACreateTimeCommand() {
        let template = "npx bmad-method install --yes --directory '{PROJECT_PATH}'"
        XCTAssertEqual(
            InitCommand.withCreateOutputFolder(template),
            "npx bmad-method install --yes --directory '{PROJECT_PATH}' --output-folder output")
    }

    func testAppendingLeavesPlaceholdersAndQuotingIntact() {
        let template =
            "npx bmad-method install --custom-source '{MODULE_SOURCE}' --directory '{PROJECT_PATH}'"
        let extended = InitCommand.withCreateOutputFolder(template)
        XCTAssertTrue(extended.hasPrefix(template),
                      "the configured command must run as written, with the flag appended")
        XCTAssertTrue(extended.contains("'{MODULE_SOURCE}'"))
        XCTAssertTrue(extended.contains("'{PROJECT_PATH}'"))
    }

    func testKeepsAnExplicitOutputFolderChoice() {
        let template = "npx bmad-method install --output-folder docs"
        XCTAssertEqual(InitCommand.withCreateOutputFolder(template), template)
    }

    func testKeepsAnExplicitSetCoreOutputFolderChoice() {
        let template = "npx bmad-method install --set core.output_folder=docs"
        XCTAssertEqual(InitCommand.withCreateOutputFolder(template), template)
    }
}
