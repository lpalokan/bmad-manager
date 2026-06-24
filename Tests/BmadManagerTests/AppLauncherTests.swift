import XCTest
@testable import BmadManager

/// Covers how [[AppLauncher]] turns a resolved app + project path into the
/// `/usr/bin/open` argv, without spawning `open`.
///
/// The behaviour these pin down: pointing the Codex *GUI* at a project.
/// A bare folder argument (`open -a Codex.app <dir>`) is ignored by Codex —
/// the only mechanism that actually opens the GUI on a workspace is its
/// `codex://threads/new?path=…` deep link. So for Codex the launcher emits
/// the deep link (targeting the detected app when we have its path, else
/// letting LaunchServices route by scheme registration), while Claude — which
/// has no such deep link — keeps the plain app open.
final class AppLauncherTests: XCTestCase {
    private let codexApp = URL(fileURLWithPath: "/Applications/Codex.app")
    private let claudeApp = URL(fileURLWithPath: "/Applications/Claude.app")

    // MARK: - Codex: deep link opens the project as a workspace

    func testCodexDeepLinkTargetsResolvedAppWhenDetected() {
        // We resolved exactly which Codex to open, so hand the deep link to
        // that app (`open -a <path> <url>`) — launch and detection agree on
        // the bundle even when two installs exist.
        let argv = AppLauncher.openArguments(
            agent: .codex,
            projectPath: "/Users/me/My Project",
            resolvedAppURL: codexApp
        )

        XCTAssertEqual(argv, [
            "-a", "/Applications/Codex.app",
            "codex://threads/new?path=%2FUsers%2Fme%2FMy%20Project",
        ])
    }

    func testCodexDeepLinkRoutesBySchemeWhenAppUnresolved() {
        // Bundle-ID miss *and* name-scan miss but the user forced "App":
        // fire the deep link bare so whichever install registered the
        // `codex://` scheme (e.g. the side-loaded GUI) still handles it.
        let argv = AppLauncher.openArguments(
            agent: .codex,
            projectPath: "/Users/me/Proj",
            resolvedAppURL: nil
        )

        XCTAssertEqual(argv, ["codex://threads/new?path=%2FUsers%2Fme%2FProj"])
    }

    // MARK: - Claude: no deep link, plain app open

    func testClaudeOpensResolvedAppWithProjectArgument() {
        let argv = AppLauncher.openArguments(
            agent: .claude,
            projectPath: "/Users/me/Proj",
            resolvedAppURL: claudeApp
        )

        XCTAssertEqual(argv, ["-a", "/Applications/Claude.app", "/Users/me/Proj"])
    }

    func testClaudeFallsBackToBundleIdWhenUnresolved() {
        let argv = AppLauncher.openArguments(
            agent: .claude,
            projectPath: "/Users/me/Proj",
            resolvedAppURL: nil
        )

        XCTAssertEqual(argv, ["-b", "com.anthropic.claudefordesktop", "/Users/me/Proj"])
    }
}
