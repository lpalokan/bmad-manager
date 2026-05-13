import XCTest
@testable import BmadManager

final class AppSettingsTests: XCTestCase {
    func testDefaultsAreSensible() {
        let defaults = AppSettings.defaults()
        XCTAssertFalse(defaults.projectsRoot.isEmpty)
        XCTAssertTrue(defaults.projectsRoot.hasPrefix("/"),
                      "projectsRoot should be tilde-expanded to an absolute path")
        XCTAssertFalse(defaults.projectsRoot.contains("~"))
        XCTAssertTrue(defaults.initCommand.contains("{PROJECT_PATH}"))
        XCTAssertTrue(defaults.initCommand.contains("{MODULE_PATH}"))
        XCTAssertEqual(defaults.moduleZipPath, "")
        XCTAssertEqual(defaults.claudeCommand, "claude")
        XCTAssertEqual(defaults.opencodeCommand, "opencode")
    }

    func testDefaultsUseHeadlessBmadInstall() {
        // Per issue #6 — always non-interactive, always install bmm/bmb/cis,
        // always configure claude-code and opencode tooling, and register
        // the marketing-growth bundle as a BMad module via --custom-source
        // (not just a cp overlay; see the issue-11 discussion).
        let command = AppSettings.defaults().initCommand
        XCTAssertTrue(command.contains("--yes"),
                      "headless install must pass --yes to skip prompts")
        XCTAssertTrue(command.contains("--modules"),
                      "headless install must specify modules explicitly")
        XCTAssertTrue(command.contains("bmm"))
        XCTAssertTrue(command.contains("bmb"))
        XCTAssertTrue(command.contains("cis"))
        XCTAssertTrue(command.contains("--tools"),
                      "headless install must specify tools explicitly")
        XCTAssertTrue(command.contains("claude-code"))
        XCTAssertTrue(command.contains("opencode"))
        XCTAssertTrue(command.contains("--custom-source"),
                      "marketing-growth module must register via --custom-source")
        XCTAssertTrue(command.contains("--directory"),
                      "headless install must target an explicit directory")
        XCTAssertTrue(command.contains("{PROJECT_PATH}"),
                      "init command must thread the project path through")
        XCTAssertTrue(command.contains("{MODULE_PATH}"),
                      "init command must thread the unzipped module path through")
    }

    func testCodableRoundTrip() throws {
        let original = AppSettings(
            projectsRoot: "/tmp/my-projects",
            moduleZipPath: "/tmp/module.zip",
            initCommand: "echo {PROJECT_PATH} && cp {MODULE_PATH}/* .",
            claudeCommand: "claude --verbose",
            opencodeCommand: "opencode --debug"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testDefaultsRoundTrip() throws {
        let defaults = AppSettings.defaults()
        let encoded = try JSONEncoder().encode(defaults)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(defaults, decoded)
    }
}
