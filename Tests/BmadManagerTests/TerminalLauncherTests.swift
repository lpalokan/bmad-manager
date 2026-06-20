import XCTest
@testable import BmadManager

final class TerminalLauncherTests: XCTestCase {
    func testShellQuoteWrapsPlainPath() {
        XCTAssertEqual(
            TerminalLauncher.shellQuote("/Users/me/Projects/foo"),
            "'/Users/me/Projects/foo'"
        )
    }

    func testShellQuoteHandlesSpaces() {
        XCTAssertEqual(
            TerminalLauncher.shellQuote("/Users/me/My Project"),
            "'/Users/me/My Project'"
        )
    }

    func testShellQuoteEscapesEmbeddedSingleQuote() {
        // Standard POSIX trick: end the quoted string, insert an escaped
        // single quote, start a new quoted string. "foo'bar" → 'foo'\''bar'
        XCTAssertEqual(
            TerminalLauncher.shellQuote("foo'bar"),
            "'foo'\\''bar'"
        )
    }

    func testAppleScriptEscapePlainString() {
        XCTAssertEqual(TerminalLauncher.appleScriptEscape("hello world"), "hello world")
    }

    func testAppleScriptEscapeBackslash() {
        XCTAssertEqual(TerminalLauncher.appleScriptEscape(#"\"#), #"\\"#)
    }

    func testAppleScriptEscapeDoubleQuote() {
        XCTAssertEqual(TerminalLauncher.appleScriptEscape(#"""#), #"\""#)
    }

    func testAppleScriptEscapeOrderingHandlesBackslashThenQuote() {
        // If we escaped quotes first and backslashes second, the result for
        // `\"` would balloon to `\\\\"` (4 backslashes + quote). The
        // backslash-first ordering produces `\\\"` (2 backslashes + escaped
        // quote), which is what AppleScript expects.
        XCTAssertEqual(TerminalLauncher.appleScriptEscape(#"\""#), #"\\\""#)
    }

    // MARK: - Per-terminal AppleScript dispatch

    func testAppleScriptForTerminalDrivesTerminalApp() {
        let script = TerminalLauncher.appleScript(for: .terminal, shellLine: "cd '/tmp' && ls")
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("do script \"cd '/tmp' && ls\""))
    }

    func testAppleScriptForITerm2DrivesITerm() {
        let script = TerminalLauncher.appleScript(for: .iterm2, shellLine: "cd '/tmp' && ls")
        XCTAssertTrue(script.contains("tell application \"iTerm\""))
        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertTrue(script.contains("write text \"cd '/tmp' && ls\""))
    }

    // MARK: - New-window vs. new-tab placement

    func testAppleScriptDefaultsToNewWindowForTerminal() {
        // Omitting placement keeps the historical new-window behaviour.
        let script = TerminalLauncher.appleScript(for: .terminal, shellLine: "cd '/tmp' && ls")
        XCTAssertFalse(script.contains("keystroke \"t\""))
        XCTAssertTrue(script.contains("do script \"cd '/tmp' && ls\""))
    }

    func testAppleScriptForTerminalNewTabSendsCommandT() {
        let script = TerminalLauncher.appleScript(
            for: .terminal, placement: .newTab, shellLine: "cd '/tmp' && ls")
        XCTAssertTrue(script.contains("keystroke \"t\" using command down"))
        XCTAssertTrue(script.contains("do script \"cd '/tmp' && ls\" in front window"))
    }

    func testAppleScriptForITerm2NewTabCreatesTab() {
        let script = TerminalLauncher.appleScript(
            for: .iterm2, placement: .newTab, shellLine: "cd '/tmp' && ls")
        XCTAssertTrue(script.contains("create tab with default profile"))
        XCTAssertTrue(script.contains("write text \"cd '/tmp' && ls\""))
    }

    func testAppleScriptForITerm2NewWindowDoesNotCreateTab() {
        let script = TerminalLauncher.appleScript(
            for: .iterm2, placement: .newWindow, shellLine: "cd '/tmp' && ls")
        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertFalse(script.contains("create tab with default profile"))
    }
}
