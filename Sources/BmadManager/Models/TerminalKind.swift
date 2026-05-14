import Foundation

/// Curated, build-time list of terminal emulators we know how to drive.
///
/// Adding a new case is intentionally a code change rather than user
/// configuration: each terminal needs its own launch glue (AppleScript,
/// CLI args, etc.), and we only want to expose terminals we can actually
/// run a command in.
enum TerminalKind: String, Codable, CaseIterable, Identifiable {
    case terminal
    case iterm2

    // Future work (issue #TBD): warp, ghostty, alacritty, kitty, wezterm, hyper.

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2:   return "iTerm2"
        }
    }

    /// Bundle identifier used to detect whether the app is installed.
    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2:   return "com.googlecode.iterm2"
        }
    }

    /// The default to fall back to when nothing is configured. Terminal.app
    /// ships with macOS, so it's the only kind we can assume is present.
    static let fallback: TerminalKind = .terminal
}
