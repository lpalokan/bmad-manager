import Foundation

enum TerminalLauncherError: LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): return "Failed to open terminal: \(message)"
        }
    }
}

enum TerminalLauncher {
    /// Opens the configured terminal, cd's into the project path, and runs
    /// the given command. Triggers a one-time Automation permission prompt
    /// (per target app) on first use.
    static func open(projectPath: String, command: String, kind: TerminalKind = .terminal) throws {
        // Order is load-bearing: shell-quote the path first, then
        // appleScript(for:shellLine:) escapes the whole line for
        // AppleScript. Reversed, the AppleScript backslashes would reach
        // the shell as literal input.
        let shellLine = "cd \(shellQuote(projectPath)) && \(command)"
        let script = appleScript(for: kind, shellLine: shellLine)
        try runOsascript(script)
    }

    // MARK: - Per-terminal AppleScript

    /// Build the AppleScript that runs `shellLine` in a fresh window of `kind`.
    /// Internal (not private) so tests can assert the right script flavour is
    /// chosen for each terminal.
    static func appleScript(for kind: TerminalKind, shellLine: String) -> String {
        let escaped = appleScriptEscape(shellLine)
        switch kind {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        case .iterm2:
            // iTerm2 ≥ 3.x exposes a Python-style scripting model under
            // the "iTerm" application name; `create window with default
            // profile` opens a new window and `write text` runs the line
            // in its current session.
            return """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(escaped)"
                end tell
            end tell
            """
        }
    }

    // MARK: - Process plumbing

    private static func runOsascript(_ script: String) throws {
        let outcome = try Subprocess.run("/usr/bin/osascript", arguments: ["-e", script])
        if outcome.status != 0 {
            throw TerminalLauncherError.scriptFailed(outcome.failureMessage)
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
