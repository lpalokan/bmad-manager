import Foundation

/// Protocol seam for launching a coding agent's desktop app, so
/// agent-launch orchestration can be tested without actually opening an
/// app via LaunchServices. Mirrors [[TerminalLauncherProtocol]].
///
/// Takes the whole [[AgentApp]] rather than a bare bundle identifier so the
/// launcher can resolve the app the same two-stage way [[AppDetector]] does
/// (bundle ID, then Applications-folder scan) and open exactly what was
/// detected — including a side-loaded GUI whose bundle ID we can't predict.
protocol AppLauncherProtocol {
    func open(agent: AgentApp, projectPath: String) throws
}

/// Production adapter that delegates to the static [[AppLauncher]] helper.
struct DefaultAppLauncher: AppLauncherProtocol {
    func open(agent: AgentApp, projectPath: String) throws {
        try AppLauncher.open(agent: agent, projectPath: projectPath)
    }
}
