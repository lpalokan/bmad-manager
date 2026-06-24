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

    func testCodexAppBundleNameDrivesApplicationsFolderFallback() {
        // When LaunchServices can't resolve the bundle ID (a side-loaded
        // GUI), detection scans the Applications folders for this name.
        XCTAssertEqual(AgentApp.codex.appBundleNames, ["Codex.app"])
    }

    // MARK: - Project deep link

    func testCodexProjectDeepLinkOpensFolderAsActiveWorkspace() {
        // Codex's GUI opens on a project only via the `codex://threads/new`
        // deep link with an absolute `path` — a bare folder argument is
        // ignored. The query value is percent-encoded down to the unreserved
        // set, so path separators and spaces survive as `%2F` / `%20` — the
        // form OpenAI's own `codex app PATH` launcher uses.
        let link = AgentApp.codex.projectDeepLink(forProjectPath: "/Users/me/My Project")
        XCTAssertEqual(
            link?.absoluteString,
            "codex://threads/new?path=%2FUsers%2Fme%2FMy%20Project"
        )
    }

    func testClaudeHasNoProjectDeepLink() {
        // The Claude desktop app exposes no public deep link to force a
        // target tab/workspace, so there's nothing to point at a project.
        XCTAssertNil(AgentApp.claude.projectDeepLink(forProjectPath: "/Users/me/Proj"))
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
