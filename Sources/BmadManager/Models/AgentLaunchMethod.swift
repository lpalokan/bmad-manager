import Foundation

/// How bmad-manager should launch a coding agent that has both a CLI and
/// a desktop app (see [[AgentApp]]).
///
/// `.auto` is the product default: prefer the desktop app when it's
/// installed, and fall back to running the CLI in the configured terminal
/// when it isn't. `.app` and `.cli` are explicit overrides for users who
/// want one or the other regardless of what's detected.
///
/// The pure preference → concrete-decision mapping lives in
/// [[AgentLaunchResolver]]; detection and launching are
/// [[AppDetector]] / [[AppLauncher]].
enum AgentLaunchMethod: String, Codable, CaseIterable, Identifiable {
    case auto
    case app
    case cli

    var id: String { rawValue }

    /// Product default — prefer the app, fall back to the CLI.
    static let `default`: AgentLaunchMethod = .auto

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .app:  return "App"
        case .cli:  return "CLI"
        }
    }
}
