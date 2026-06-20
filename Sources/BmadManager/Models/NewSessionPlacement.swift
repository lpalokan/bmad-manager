import Foundation

/// Where a newly launched terminal session opens: a brand-new window, or a
/// tab in the frontmost window of the chosen terminal.
///
/// Mirrors the Tauri/Rust `NewSessionPlacement` and shares its on-disk raw
/// values ("newWindow"/"newTab"), so a settings.json stays portable across
/// the macOS app and the Windows port. `.newWindow` is the default so
/// upgrades keep the previous behaviour. Both Terminal.app and iTerm2 can
/// tab, so the choice is honoured for either.
enum NewSessionPlacement: String, Codable, CaseIterable, Identifiable {
    case newWindow
    case newTab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newWindow: return "New window"
        case .newTab:    return "New tab"
        }
    }

    /// The default to fall back to when nothing is configured.
    static let fallback: NewSessionPlacement = .newWindow
}
