import Foundation

/// Protocol seam for launching a shell command in a terminal emulator.
///
/// Callers inject a concrete implementation (production, test spy, etc.)
/// so terminal-launch orchestration can be tested without spawning a real
/// terminal. Follows the same pattern as `ModuleSource`.
protocol TerminalLauncherProtocol {
    func open(projectPath: String, command: String, kind: TerminalKind) throws
}

/// Production adapter that delegates to the static `TerminalLauncher` helpers.
struct DefaultTerminalLauncher: TerminalLauncherProtocol {
    func open(projectPath: String, command: String, kind: TerminalKind) throws {
        try TerminalLauncher.open(projectPath: projectPath, command: command, kind: kind)
    }
}
