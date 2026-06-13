import XCTest
@testable import BmadManager

/// Covers the pieces that decide *how* a coding agent is launched: the
/// per-agent app descriptor, the launch-method preference, and the pure
/// resolver that turns a preference plus install state into a concrete
/// "open the app" / "run the CLI" decision.
final class AgentLaunchTests: XCTestCase {

    // MARK: - AgentApp descriptor

    func testClaudeAppUsesDesktopBundleIdentifier() {
        XCTAssertEqual(AgentApp.claude.bundleIdentifier, "com.anthropic.claudefordesktop")
    }

    func testCodexAppUsesDesktopBundleIdentifier() {
        XCTAssertEqual(AgentApp.codex.bundleIdentifier, "com.openai.codex")
    }

    // MARK: - Launch method defaults & coding

    func testLaunchMethodDefaultPrefersApp() {
        // The product default is "prefer the app when it's installed",
        // which is exactly what `.auto` encodes.
        XCTAssertEqual(AgentLaunchMethod.default, .auto)
    }

    func testLaunchMethodIsCodableByRawValue() throws {
        for method in AgentLaunchMethod.allCases {
            let encoded = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(AgentLaunchMethod.self, from: encoded)
            XCTAssertEqual(decoded, method)
        }
    }

    // MARK: - Resolver

    func testAutoPrefersAppWhenInstalled() {
        XCTAssertEqual(
            AgentLaunchResolver.resolve(method: .auto, appInstalled: true),
            .app
        )
    }

    func testAutoFallsBackToCliWhenAppMissing() {
        XCTAssertEqual(
            AgentLaunchResolver.resolve(method: .auto, appInstalled: false),
            .cli
        )
    }

    func testCliAlwaysResolvesToCliEvenWhenAppInstalled() {
        XCTAssertEqual(
            AgentLaunchResolver.resolve(method: .cli, appInstalled: true),
            .cli
        )
    }

    func testAppForcedResolvesToAppEvenWhenNotDetected() {
        // An explicit "App" choice is honoured best-effort: if detection is
        // wrong (or the user knows better), we still try to open the app and
        // let `open` surface any error, rather than silently using the CLI.
        XCTAssertEqual(
            AgentLaunchResolver.resolve(method: .app, appInstalled: false),
            .app
        )
    }
}
