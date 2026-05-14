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
}
