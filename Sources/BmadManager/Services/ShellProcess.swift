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

                do {
                    try process.run()
                } catch {
                    continuation.yield("Failed to launch shell: \(error.localizedDescription)\n")
                    continuation.finish()
                    resume.resume(returning: -1)
                    return
                }

                // Drain the pipe from a single reader so output ordering is
                // deterministic. Splitting reads across a readabilityHandler and
                // a terminationHandler races on fast runners: the readability
                // handler can yield a chunk *after* the termination handler has
                // already finished the stream, silently dropping the output.
                let readHandle = pipe.fileHandleForReading
                DispatchQueue.global().async {
                    while true {
                        let data = readHandle.availableData
                        if data.isEmpty { break } // EOF: child exited and write end closed
                        if let chunk = String(data: data, encoding: .utf8) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                    process.waitUntilExit()
                    resume.resume(returning: process.terminationStatus)
                }
            }
        }

        return (stream, exitTask)
    }
}
