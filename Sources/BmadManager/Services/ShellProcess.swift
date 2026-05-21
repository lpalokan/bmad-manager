import Foundation

struct ShellProcess {
    static func run(command: String, cwd: URL) -> (output: AsyncStream<String>, exitCode: Task<Int32, Never>) {
        let (stream, continuation) = AsyncStream<String>.makeStream()

        let exitTask = Task {
            await withCheckedContinuation { (resume: CheckedContinuation<Int32, Never>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.currentDirectoryURL = cwd

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    guard let chunk = String(data: data, encoding: .utf8) else { return }
                    continuation.yield(chunk)
                }

                process.terminationHandler = { proc in
                    // Drain any data the readability handler hasn't processed yet.
                    // On fast runners the termination handler can fire before the
                    // readability handler, so clearing it first would lose output.
                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !remaining.isEmpty, let chunk = String(data: remaining, encoding: .utf8) {
                        continuation.yield(chunk)
                    }
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.finish()
                    resume.resume(returning: proc.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.yield("Failed to launch shell: \(error.localizedDescription)\n")
                    continuation.finish()
                    resume.resume(returning: -1)
                }
            }
        }

        return (stream, exitTask)
    }
}
