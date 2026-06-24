import XCTest
@testable import BmadManager

/// When Codex is launched cold (not already running) it boots into its last
/// workspace before it can handle our `codex://…?path=…` deep link, so it
/// briefly shows the wrong project before [[AppLauncher]]'s two-phase launch
/// switches it over. We give the user a one-time heads-up on that cold start.
/// A *warm* launch (Codex already running) honours the deep link immediately
/// with no flicker, so it gets no notice. These pin that gating and that the
/// note names the project.
final class CodexWorkspaceNoticeTests: XCTestCase {
    func testPresentsForCodexColdAppLaunchWhenNotSuppressed() {
        XCTAssertTrue(CodexWorkspaceNotice.shouldPresent(
            agent: .codex, resolved: .app, suppressed: false, appRunning: false))
    }

    func testNoNoticeWhenCodexAlreadyRunning() {
        // Warm launch: the live app switches workspace instantly, no flicker.
        XCTAssertFalse(CodexWorkspaceNotice.shouldPresent(
            agent: .codex, resolved: .app, suppressed: false, appRunning: true))
    }

    func testSuppressedSilencesTheNotice() {
        XCTAssertFalse(CodexWorkspaceNotice.shouldPresent(
            agent: .codex, resolved: .app, suppressed: true, appRunning: false))
    }

    func testNoNoticeForCliLaunch() {
        // The CLI opens the project directly in the terminal — nothing to warn about.
        XCTAssertFalse(CodexWorkspaceNotice.shouldPresent(
            agent: .codex, resolved: .cli, suppressed: false, appRunning: false))
    }

    func testNoNoticeForClaude() {
        // Only Codex has the cold-start workspace flicker; Claude's app launch
        // has no project deep link to begin with.
        XCTAssertFalse(CodexWorkspaceNotice.shouldPresent(
            agent: .claude, resolved: .app, suppressed: false, appRunning: false))
    }

    func testMessageNamesTheProjectPath() {
        let message = CodexWorkspaceNotice.message(forProjectPath: "/Users/me/My Project")
        XCTAssertTrue(message.contains("/Users/me/My Project"),
                      "the note must name the project Codex is switching to: \(message)")
    }
}
