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

    // MARK: - Running state (for the cold-start launch workaround)

    /// The running instance of `agent`'s app, matched by the stable bundle ID
    /// or by the resolved bundle path (so a side-loaded GUI whose real ID
    /// differs still matches). `nil` when the app isn't running.
    static func runningApplication(_ agent: AgentApp, resolvedAppURL: URL?) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if app.bundleIdentifier == agent.bundleIdentifier { return true }
            if let want = resolvedAppURL?.standardizedFileURL.path,
               let have = app.bundleURL?.standardizedFileURL.path,
               want == have { return true }
            return false
        }
    }

    /// Whether `agent`'s app is currently running. Drives the two-phase launch
    /// in [[AppLauncher]] (cold start launches first, then delivers the deep
    /// link; a warm app gets the link immediately).
    static func isRunning(_ agent: AgentApp, resolvedAppURL: URL?) -> Bool {
        runningApplication(agent, resolvedAppURL: resolvedAppURL) != nil
    }

    /// Runs `then` once `agent`'s app has finished launching (or after
    /// `timeout`), plus a short `settle` so a cold-started app has restored its
    /// session and is ready to handle a deep link. Always off the main thread,
    /// so the caller's UI never blocks while the app boots.
    static func whenAppReady(
        _ agent: AgentApp,
        resolvedAppURL: URL?,
        timeout: TimeInterval = 15,
        settle: TimeInterval = 2.0,
        pollInterval: TimeInterval = 0.25,
        then: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let app = runningApplication(agent, resolvedAppURL: resolvedAppURL),
                   app.isFinishedLaunching {
                    break
                }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            Thread.sleep(forTimeInterval: settle)
            then()
        }
    }
}
