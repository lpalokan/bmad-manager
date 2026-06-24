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
    /// Launches `agent`'s desktop app so it opens *on* `projectPath`.
    ///
    /// The argv is built by `openArguments` (the testable policy); this just
    /// runs `/usr/bin/open` and surfaces a non-zero exit as an error rather
    /// than silently downgrading.
    static func open(agent: AgentApp, projectPath: String) throws {
        let arguments = openArguments(
            agent: agent,
            projectPath: projectPath,
            resolvedAppURL: AppDetector.resolveAppURL(agent)
        )
        let outcome = try Subprocess.run("/usr/bin/open", arguments: arguments)
        if outcome.status != 0 {
            throw AppLauncherError.launchFailed(outcome.failureMessage)
        }
    }

    /// Pure `/usr/bin/open` argv for handing `projectPath` to `agent`'s app,
    /// given the app [[AppDetector]] resolved (`nil` when it found none).
    /// Factored out so the launch policy is unit-testable without spawning
    /// `open`.
    ///
    /// Order of preference:
    ///
    ///   1. A project deep link (Codex `codex://threads/new?path=…`). This is
    ///      the *only* mechanism that opens the GUI on the project — a bare
    ///      folder argument is ignored. When we resolved the app we target it
    ///      explicitly (`open -a <path> <url>`) so launch and detection can't
    ///      disagree on the bundle; otherwise we fire the deep link bare and
    ///      let LaunchServices route it to whichever install registered the
    ///      `codex://` scheme (covers a side-loaded GUI under a forced "App").
    ///   2. No deep link (Claude): open the resolved app with the project as a
    ///      best-effort document argument (`open -a <path> <project>`).
    ///   3. Nothing resolved and no deep link: fall back to the bundle ID
    ///      (`open -b <id> <project>`), honouring a forced "App" best-effort.
    static func openArguments(
        agent: AgentApp,
        projectPath: String,
        resolvedAppURL: URL?
    ) -> [String] {
        if let deepLink = agent.projectDeepLink(forProjectPath: projectPath) {
            if let appURL = resolvedAppURL {
                return ["-a", appURL.path, deepLink.absoluteString]
            }
            return [deepLink.absoluteString]
        }
        if let appURL = resolvedAppURL {
            return ["-a", appURL.path, projectPath]
        }
        return ["-b", agent.bundleIdentifier, projectPath]
    }
}
