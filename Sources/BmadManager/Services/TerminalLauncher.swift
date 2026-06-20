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
    static func open(
        projectPath: String,
        command: String,
        kind: TerminalKind = .terminal,
        placement: NewSessionPlacement = .newWindow
    ) throws {
        // Order is load-bearing: shell-quote the path first, then
        // appleScript(for:placement:shellLine:) escapes the whole line for
        // AppleScript. Reversed, the AppleScript backslashes would reach
        // the shell as literal input.
        let shellLine = "cd \(shellQuote(projectPath)) && \(command)"
        let script = appleScript(for: kind, placement: placement, shellLine: shellLine)
        try runOsascript(script)
    }

    // MARK: - Per-terminal AppleScript

    /// Build the AppleScript that runs `shellLine` in `kind`, either in a new
    /// window or a new tab per `placement`. Internal (not private) so tests
    /// can assert the right script flavour is chosen for each combination.
    static func appleScript(
        for kind: TerminalKind,
        placement: NewSessionPlacement = .newWindow,
        shellLine: String
    ) -> String {
        let escaped = appleScriptEscape(shellLine)
        switch (kind, placement) {
        case (.terminal, .newWindow):
            // Terminal.app's `do script` with no target always opens a new
            // window.
            return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        case (.terminal, .newTab):
            // Terminal.app's dictionary has no "new tab" verb, so the
            // standard idiom is to send Cmd-T (needs Terminal frontmost,
            // hence `activate`, and Automation permission for System Events)
            // and then run the line in the now-frontmost window's new tab.
            return """
            tell application "Terminal"
                activate
                tell application "System Events" to keystroke "t" using command down
                delay 0.2
                do script "\(escaped)" in front window
            end tell
            """
        case (.iterm2, .newWindow):
            // iTerm2 ≥ 3.x exposes a Python-style scripting model under
            // the "iTerm" application name; `create window with default
            // profile` opens a new window and `write text` runs the line
            // in its current session.
            return """
            tell application "iTerm"
                activate
                set targetWindow to (create window with default profile)
                tell current session of targetWindow
                    write text "\(escaped)"
                end tell
            end tell
            """
        case (.iterm2, .newTab):
            // Add a tab to the current window (or open a fresh window when
            // none exists yet), then run the line in its session.
            return """
            tell application "iTerm"
                activate
                if (count of windows) is 0 then
                    set targetWindow to (create window with default profile)
                else
                    set targetWindow to current window
                    tell targetWindow to create tab with default profile
                end if
                tell current session of targetWindow
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
