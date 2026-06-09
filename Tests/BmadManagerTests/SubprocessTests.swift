import XCTest
@testable import BmadManager

/// Interface tests for the shared subprocess plumbing. The adapters built
/// on top (git clone, unzip, osascript, shell-PATH capture) each keep
/// their own behavioural tests — these cover only the contract every one
/// of them relies on.
final class SubprocessTests: XCTestCase {
    func testCapturesStdoutAndZeroStatus() throws {
        let outcome = try Subprocess.run("/bin/sh", arguments: ["-c", "echo hello"])
        XCTAssertEqual(outcome.status, 0)
        XCTAssertEqual(outcome.stdout, "hello\n")
        XCTAssertEqual(outcome.stderr, "")
    }

    func testCapturesStderrAndNonZeroStatus() throws {
        let outcome = try Subprocess.run("/bin/sh", arguments: ["-c", "echo oops 1>&2; exit 3"])
        XCTAssertEqual(outcome.status, 3)
        XCTAssertEqual(outcome.stderr, "oops\n")
    }

    func testThrowsWhenExecutableCannotBeLaunched() {
        XCTAssertThrowsError(
            try Subprocess.run("/nonexistent/no-such-binary", arguments: [])
        )
    }

    func testStdinIsNullDeviceSoReadersFinishImmediately() throws {
        // A child that reads stdin must see EOF, not hang the app waiting
        // for input — the guard the copied plumbing only applied to some
        // spawners before consolidation.
        let outcome = try Subprocess.run("/bin/sh", arguments: ["-c", "cat"])
        XCTAssertEqual(outcome.status, 0)
        XCTAssertEqual(outcome.stdout, "")
    }

    func testFailureMessageUsesTrimmedStderr() {
        let outcome = Subprocess.Outcome(status: 1, stdout: "", stderr: "  boom \n")
        XCTAssertEqual(outcome.failureMessage, "boom")
    }

    func testFailureMessageFallsBackWhenStderrIsEmpty() {
        let outcome = Subprocess.Outcome(status: 1, stdout: "", stderr: " \n")
        XCTAssertEqual(outcome.failureMessage, "unknown error")
    }
}
