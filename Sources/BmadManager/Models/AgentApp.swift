import Foundation

/// A coding agent that ships both a CLI and a macOS desktop app, so the
/// user can pick how bmad-manager launches it (see [[AgentLaunchMethod]]).
///
/// Only agents with a real desktop app belong here — opencode and Pi are
/// CLI-only and keep the plain command flow. The bundle identifiers are
/// the stable LaunchServices keys we both detect with (mirroring
/// `TerminalKind.bundleIdentifier`) and launch with (`open -b`).
enum AgentApp: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    /// Bundle identifier of the desktop app, used both to detect whether
    /// it's installed and to launch exactly that app.
    var bundleIdentifier: String {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex:  return "com.openai.codex"
        }
    }

    /// Human-facing name of the desktop app — e.g. for Settings captions
    /// ("Claude app detected"). The CLI keeps its own label in the UI.
    var appDisplayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }
}
