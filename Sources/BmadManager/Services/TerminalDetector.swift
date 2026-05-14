import Foundation
import AppKit

/// Discovers which of the curated [[TerminalKind]] options are actually
/// installed on this machine, so we only ever offer the user a working
/// choice in Settings.
enum TerminalDetector {
    /// Returns every known kind whose `.app` bundle resolves via
    /// LaunchServices. Order matches `TerminalKind.allCases` so the UI
    /// stays stable across launches.
    static func installedKinds(workspace: NSWorkspace = .shared) -> [TerminalKind] {
        TerminalKind.allCases.filter { isInstalled($0, workspace: workspace) }
    }

    static func isInstalled(_ kind: TerminalKind, workspace: NSWorkspace = .shared) -> Bool {
        workspace.urlForApplication(withBundleIdentifier: kind.bundleIdentifier) != nil
    }
}
