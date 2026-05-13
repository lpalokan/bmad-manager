import Foundation
import Combine

final class CommandRunner: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastExitCode: Int32? = nil

    @discardableResult
    func run(command: String, cwd: URL) async -> Int32 {
        await MainActor.run {
            self.output = ""
            self.isRunning = true
            self.lastExitCode = nil
        }

        let exitCode: Int32 = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = cwd

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    self?.output.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { [weak self] in
                    self?.output.append("Failed to launch shell: \(error.localizedDescription)\n")
                }
                continuation.resume(returning: -1)
            }
        }

        await MainActor.run {
            self.isRunning = false
            self.lastExitCode = exitCode
        }
        return exitCode
    }
}
