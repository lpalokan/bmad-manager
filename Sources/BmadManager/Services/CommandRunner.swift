import Foundation
import Combine

@MainActor
final class CommandRunner: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastExitCode: Int32? = nil

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
