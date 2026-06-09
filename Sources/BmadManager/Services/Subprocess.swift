import Foundation

/// One home for the synchronous run-to-completion Process plumbing that
/// the git, unzip, osascript, and shell-PATH adapters used to copy: wire
/// the pipes, null stdin so a child that reads it sees EOF instead of
/// hanging the app, wait, decode. Callers keep their own error vocabulary
/// and cleanup policy — only the plumbing lives here.
///
/// `ShellProcess` is the deliberate sibling for the streaming case (live
/// output into the UI); don't fold the two together.
enum Subprocess {
    struct Outcome {
        let status: Int32
        let stdout: String
        let stderr: String

        /// Trimmed stderr, or a stable placeholder when the child produced
        /// none — suitable for feeding straight into an error message.
        var failureMessage: String {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "unknown error" : trimmed
        }
    }

    /// Runs `executable` with `arguments` to completion. Throws only when
    /// the process cannot be launched at all; a non-zero exit is reported
    /// through `Outcome.status` with stderr captured for the caller's
    /// error message.
    static func run(_ executable: String, arguments: [String]) throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return Outcome(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
