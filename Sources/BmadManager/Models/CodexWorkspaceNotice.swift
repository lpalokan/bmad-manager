import Foundation

/// A one-time heads-up for launching Codex *cold* (not already running) as
/// the *app*.
///
/// DORMANT: not currently wired into the launch path. [[AppLauncher]]'s
/// two-phase cold start (launch the app, wait for it to come up, then deliver
/// the deep link) switches Codex to the right project reliably enough that the
/// flicker no longer warrants a notice. Kept — with its tests — in case the
/// heads-up is wanted again; to re-enable, have [[ProjectCoordinator]] set a
/// pending-notice path off `shouldPresent` and present it from the view.
///
/// The rationale it was built for: a cold Codex boots into its last workspace
/// before it can handle the `codex://threads/new?path=…` deep link, so for a
/// few seconds it shows the wrong project before the two-phase launch switches
/// it over; a *warm* launch lands instantly with no flicker.
enum CodexWorkspaceNotice {
    /// Whether to surface the notice for this launch. True only for a *cold*
    /// Codex *app* launch the user hasn't silenced: a warm launch lands
    /// instantly (no flicker), Claude has no project deep link, and a CLI
    /// launch opens the project directly in the terminal.
    static func shouldPresent(
        agent: AgentApp,
        resolved: ResolvedAgentLaunch,
        suppressed: Bool,
        appRunning: Bool
    ) -> Bool {
        agent == .codex && resolved == .app && !suppressed && !appRunning
    }

    /// Alert title.
    static let title = "Codex is opening your project"

    /// One-sentence heads-up, naming the project Codex is switching to and how
    /// to recover if the cold start was too slow to catch the deep link.
    static func message(forProjectPath path: String) -> String {
        "Codex wasn't running — it may show its previous workspace for a moment before switching to \(path). If it doesn't switch, click Codex again."
    }
}
