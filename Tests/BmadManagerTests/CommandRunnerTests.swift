import XCTest
@testable import BmadManager

final class CommandRunnerTests: XCTestCase {
    @MainActor
    func testRunCapturesStdoutAndExitCode() async {
        let runner = CommandRunner()
        let exitCode = await runner.run(command: "echo hello", cwd: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(runner.output.contains("hello"),
                      "expected output to contain 'hello', got '\(runner.output)'")
        XCTAssertEqual(runner.lastExitCode, 0)
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testRunReportsNonZeroExit() async {
        let runner = CommandRunner()
        let exitCode = await runner.run(command: "exit 3", cwd: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(exitCode, 3)
        XCTAssertEqual(runner.lastExitCode, 3)
        XCTAssertFalse(runner.isRunning)
    }
}

final class ShellProcessTests: XCTestCase {
    func testEchoHello() async {
        let (stream, exitTask) = ShellProcess.run(command: "echo hello", cwd: URL(fileURLWithPath: "/tmp"))

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let output = chunks.joined()
        let exitCode = await exitTask.value

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.contains("hello"),
                      "expected output to contain 'hello', got '\(output)'")
    }

    func testExitCodeThree() async {
        let (stream, exitTask) = ShellProcess.run(command: "exit 3", cwd: URL(fileURLWithPath: "/tmp"))

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let exitCode = await exitTask.value

        XCTAssertEqual(exitCode, 3)
    }

    func testStdinIsNullDevice() async {
        let (stream, exitTask) = ShellProcess.run(command: "cat", cwd: URL(fileURLWithPath: "/tmp"))

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let exitCode = await exitTask.value

        // cat with /dev/null stdin should exit immediately with 0
        XCTAssertEqual(exitCode, 0)
    }

    func testCwdIsHonoured() async {
        let (stream, exitTask) = ShellProcess.run(command: "pwd", cwd: URL(fileURLWithPath: "/tmp"))

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let output = chunks.joined()
        let exitCode = await exitTask.value

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.contains("/tmp"),
                      "expected pwd to contain /tmp, got '\(output)'")
    }
}
