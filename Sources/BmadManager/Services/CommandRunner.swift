import Foundation
import Combine

@MainActor
final class CommandRunner: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastExitCode: Int32? = nil

    /// Adds one line to the panel without disturbing a run in progress. Used by
    /// checks that produce diagnostics but spawn no process of their own — the
    /// update check's per-project verdict (issue #105), which otherwise had
    /// nowhere to surface and left "no Update button" unexplainable.
    func append(_ line: String) {
        output.append(line.hasSuffix("\n") ? line : line + "\n")
    }

    @discardableResult
    func run(command: String, cwd: URL) async -> Int32 {
        output = ""
        isRunning = true
        lastExitCode = nil

        let (stream, exitTask) = ShellProcess.run(command: command, cwd: cwd)

        let consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await chunk in stream {
                self.output.append(chunk)
            }
        }

        let exitCode = await exitTask.value
        await consumeTask.value

        isRunning = false
        lastExitCode = exitCode
        return exitCode
    }
}
