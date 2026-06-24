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

    /// Filenames of the desktop app bundle as it lands in the standard
    /// Applications folders. Used as a fallback when LaunchServices can't
    /// resolve `bundleIdentifier` — e.g. a side-loaded Codex GUI whose real
    /// `CFBundleIdentifier` differs from the stable key we hardcode, which
    /// otherwise makes detection report "not installed" while
    /// `/Applications/Codex.app` is sitting right there. See [[AppDetector]].
    var appBundleNames: [String] {
        switch self {
        case .claude: return ["Claude.app"]
        case .codex:  return ["Codex.app"]
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

    /// One-line note for Settings explaining what launching the app does,
    /// since the two apps differ in kind: the Codex app is a coding app
    /// that opens the project, whereas the Claude desktop app is a
    /// multi-surface app where Code is one tab (alongside Chat and
    /// Cowork) and the app opens on whichever tab was last used — there's
    /// no public deep link to force the Code tab.
    var appLaunchNote: String {
        switch self {
        case .claude: return "Opens the Claude desktop app — Code is a tab there, alongside Chat and Cowork."
        case .codex:  return "Opens the project in the Codex app."
        }
    }
}
