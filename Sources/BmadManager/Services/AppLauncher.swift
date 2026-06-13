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
    /// Launches the app registered under `bundleIdentifier` and hands it
    /// `projectPath`, the way `open -b <id> <path>` would by hand, so
    /// project-aware apps (e.g. Codex) open on the project. Keyed on the
    /// stable bundle ID so we open exactly the app [[AppDetector]] found.
    static func open(bundleIdentifier: String, projectPath: String) throws {
        let outcome = try Subprocess.run(
            "/usr/bin/open",
            arguments: ["-b", bundleIdentifier, projectPath]
        )
        if outcome.status != 0 {
            throw AppLauncherError.launchFailed(outcome.failureMessage)
        }
    }
}
