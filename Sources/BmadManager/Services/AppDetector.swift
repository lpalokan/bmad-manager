import Foundation
import AppKit

/// Detects whether a coding agent's desktop app is installed, so Settings
/// can reflect availability and the launch path can fall back to the CLI
/// when an agent's app is absent.
///
/// Mirrors [[TerminalDetector]] — a LaunchServices lookup keyed on the
/// app's bundle identifier — so we answer the same question `open` would
/// at launch time.
enum AppDetector {
    static func isInstalled(_ agent: AgentApp, workspace: NSWorkspace = .shared) -> Bool {
        workspace.urlForApplication(withBundleIdentifier: agent.bundleIdentifier) != nil
    }
}
