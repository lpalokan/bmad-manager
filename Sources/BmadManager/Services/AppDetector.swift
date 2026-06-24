import Foundation
import AppKit

/// Locates a coding agent's desktop app so Settings can reflect
/// availability and the launch path can open exactly the app the user has.
///
/// Resolution is two-stage, and both detection and launch ([[AppLauncher]])
/// go through it so they can never disagree on which app to open:
///
///   1. Ask LaunchServices for the stable `bundleIdentifier` — the fast,
///      install-location-agnostic path the App Store / notarised build hits.
///   2. Fall back to scanning the standard Applications folders for the
///      app by name. This covers a side-loaded GUI whose real
///      `CFBundleIdentifier` differs from the key we hardcode (the Codex
///      GUI case): the bundle-ID lookup misses, but `/Applications/Codex.app`
///      is found by name and launched via `open -a`.
enum AppDetector {
    /// Default LaunchServices lookup, factored out so tests can inject a
    /// deterministic stand-in instead of querying the real `NSWorkspace`.
    static func launchServicesLookup(_ bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func isInstalled(
        _ agent: AgentApp,
        bundleLookup: (String) -> URL? = AppDetector.launchServicesLookup,
        applicationDirectories: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        resolveAppURL(
            agent,
            bundleLookup: bundleLookup,
            applicationDirectories: applicationDirectories,
            fileManager: fileManager
        ) != nil
    }

    /// Resolves the installed desktop app for `agent` to a file URL, or
    /// `nil` when it can't be found by either bundle ID or name.
    static func resolveAppURL(
        _ agent: AgentApp,
        bundleLookup: (String) -> URL? = AppDetector.launchServicesLookup,
        applicationDirectories: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        if let byBundleID = bundleLookup(agent.bundleIdentifier) {
            return byBundleID
        }
        let dirs = applicationDirectories ?? defaultApplicationDirectories(fileManager)
        for dir in dirs {
            for name in agent.appBundleNames {
                let candidate = dir.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return nil
    }

    /// `/Applications` then `~/Applications` — the two domains a desktop app
    /// normally installs into, in the order LaunchServices itself prefers.
    private static func defaultApplicationDirectories(_ fileManager: FileManager) -> [URL] {
        fileManager.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
    }
}
