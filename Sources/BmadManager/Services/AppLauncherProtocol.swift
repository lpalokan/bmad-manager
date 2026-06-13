import Foundation

/// Protocol seam for launching a desktop app by bundle identifier, so
/// agent-launch orchestration can be tested without actually opening an
/// app via LaunchServices. Mirrors [[TerminalLauncherProtocol]].
protocol AppLauncherProtocol {
    func open(bundleIdentifier: String) throws
}

/// Production adapter that delegates to the static [[AppLauncher]] helper.
struct DefaultAppLauncher: AppLauncherProtocol {
    func open(bundleIdentifier: String) throws {
        try AppLauncher.open(bundleIdentifier: bundleIdentifier)
    }
}
