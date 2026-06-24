import Foundation

enum AppLauncherError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Failed to open app: \(message)"
        }
    }
}

/// Opens a macOS desktop app via LaunchServices. This is the App half of
/// the launch story; the CLI half stays in [[TerminalLauncher]].
enum AppLauncher {
    /// Launches `agent`'s desktop app and hands it `projectPath`, so
    /// project-aware apps (e.g. Codex) open on the project.
    ///
    /// Prefers the app [[AppDetector]] resolved — `open -a <path> <project>`
    /// — which works for a side-loaded GUI whose bundle ID we can't predict.
    /// Falls back to `open -b <id> <project>` when resolution finds nothing,
    /// so an explicit "App" launch method is still honoured best-effort and
    /// `open` surfaces any error rather than silently downgrading.
    static func open(agent: AgentApp, projectPath: String) throws {
        let arguments: [String]
        if let appURL = AppDetector.resolveAppURL(agent) {
            arguments = ["-a", appURL.path, projectPath]
        } else {
            arguments = ["-b", agent.bundleIdentifier, projectPath]
        }
        let outcome = try Subprocess.run("/usr/bin/open", arguments: arguments)
        if outcome.status != 0 {
            throw AppLauncherError.launchFailed(outcome.failureMessage)
        }
    }
}
