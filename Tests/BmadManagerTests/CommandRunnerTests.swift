import XCTest
@testable import BmadManager

final class CommandRunnerTests: XCTestCase {
    func testRunCapturesStdoutAndExitCode() async {
        let runner = CommandRunner()
        let exitCode = await runner.run(command: "echo hello", cwd: URL(fileURLWithPath: "/tmp"))

        // The readability handler hops to the main queue via DispatchQueue.main.async,
        // so the @Published output may not be fully drained the instant `run` returns.
        // Spin the runloop briefly until the chunk lands, with a generous cap.
        let deadline = Date().addingTimeInterval(2)
        while !runner.output.contains("hello") && Date() < deadline {
            await Task.yield()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(runner.output.contains("hello"),
                      "expected output to contain 'hello', got '\(runner.output)'")
        XCTAssertEqual(runner.lastExitCode, 0)
        XCTAssertFalse(runner.isRunning)
    }

    func testRunReportsNonZeroExit() async {
        let runner = CommandRunner()
        let exitCode = await runner.run(command: "exit 3", cwd: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(exitCode, 3)
        XCTAssertEqual(runner.lastExitCode, 3)
        XCTAssertFalse(runner.isRunning)
    }
}
