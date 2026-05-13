import Foundation

enum TerminalLauncherError: LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): return "Failed to open Terminal: \(message)"
        }
    }
}

enum TerminalLauncher {
    /// Opens Terminal.app, cd's into the project path, and runs the given command.
    /// Triggers a one-time Automation permission prompt for Terminal on first use.
    static func open(projectPath: String, command: String) throws {
        let shellLine = "cd \(shellQuote(projectPath)) && \(command)"
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(shellLine))"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw TerminalLauncherError.scriptFailed(message)
        }
    }

    // Exposed as `internal` (not `private`) so the test target can verify the escaping.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ value: String) -> String {
        // Order matters: escape backslashes first, then double quotes.
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
