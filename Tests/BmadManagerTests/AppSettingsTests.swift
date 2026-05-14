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
        XCTAssertEqual(defaults.moduleSourceKind, .gitRepo)
        XCTAssertEqual(defaults.moduleRepoURL, "https://github.com/lpalokan/bmad-marketing-growth")
        XCTAssertEqual(defaults.moduleRepoRef, "")
        XCTAssertEqual(defaults.moduleZipPath, "")
        XCTAssertEqual(defaults.claudeCommand, "claude")
        XCTAssertEqual(defaults.opencodeCommand, "opencode")
        XCTAssertEqual(defaults.projectSortOrder, .nameAscending)
    }

    func testDecodesLegacySettingsWithoutSortOrder() throws {
        // Settings files written before #12 don't carry projectSortOrder.
        // The custom decoder should fall back to .nameAscending so users
        // who upgrade don't fail to load their persisted settings.
        let legacy = """
        {
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded.projectsRoot, "/tmp/legacy")
        XCTAssertEqual(decoded.projectSortOrder, .nameAscending)
    }

    func testLegacyWithConfiguredZipInfersLocalZipKind() throws {
        // Pre-source-picker settings.json files don't carry moduleSourceKind.
        // If the user had already configured a zip path, preserve their
        // workflow on upgrade rather than silently switching them to git.
        let legacy = """
        {
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded.moduleSourceKind, .localZip)
        XCTAssertEqual(decoded.moduleZipPath, "/tmp/m.zip")
        XCTAssertEqual(decoded.moduleRepoURL, "https://github.com/lpalokan/bmad-marketing-growth")
    }

    func testLegacyWithoutConfiguredZipDefaultsToGitRepo() throws {
        // Fresh upgrade with no zip ever picked → land on the new default
        // source (GitHub repo) instead of a non-functional .localZip + "".
        let legacy = """
        {
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded.moduleSourceKind, .gitRepo)
        XCTAssertEqual(decoded.moduleRepoURL, "https://github.com/lpalokan/bmad-marketing-growth")
        XCTAssertEqual(decoded.moduleRepoRef, "")
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

    func testCodableRoundTripLocalZip() throws {
        let original = AppSettings(
            projectsRoot: "/tmp/my-projects",
            moduleSourceKind: .localZip,
            moduleRepoURL: "https://github.com/example/repo",
            moduleRepoRef: "v1.0",
            moduleZipPath: "/tmp/module.zip",
            initCommand: "echo {PROJECT_PATH} && cp {MODULE_PATH}/* .",
            claudeCommand: "claude --verbose",
            opencodeCommand: "opencode --debug",
            projectSortOrder: .dateNewestFirst
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripGitRepo() throws {
        let original = AppSettings(
            projectsRoot: "/tmp/my-projects",
            moduleSourceKind: .gitRepo,
            moduleRepoURL: "https://github.com/example/repo",
            moduleRepoRef: "main",
            moduleZipPath: "",
            initCommand: "echo {PROJECT_PATH}",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .nameAscending
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
