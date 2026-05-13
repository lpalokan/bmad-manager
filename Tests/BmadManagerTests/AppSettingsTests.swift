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
