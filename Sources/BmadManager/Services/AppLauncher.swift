import Foundation

enum AppLauncherError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Failed to open app: \(message)"
        }
    }
}

/// Opens a macOS desktop app via LaunchServices. This is the App half of
/// the launch story; the CLI half stays in [[TerminalLauncher]].
enum AppLauncher {
    /// An ordered set of `/usr/bin/open` invocations for one launch, plus
    /// whether to wait for the app to come up between the first step and the
    /// rest (the cold-start case — see [[AppLauncher]].openPlan).
    struct LaunchPlan: Equatable {
        let steps: [[String]]
        let waitForAppLaunch: Bool
    }

    /// Launches `agent`'s desktop app so it opens *on* `projectPath`.
    ///
    /// Builds a [[LaunchPlan]] and runs it: the first step synchronously (so a
    /// launch failure surfaces), then — for a cold Codex start — waits off the
    /// main thread for the app to come up and delivers the deep link to the
    /// now-live app.
    static func open(agent: AgentApp, projectPath: String) throws {
        let appURL = AppDetector.resolveAppURL(agent)
        let plan = openPlan(
            agent: agent,
            projectPath: projectPath,
            resolvedAppURL: appURL,
            appRunning: AppDetector.isRunning(agent, resolvedAppURL: appURL)
        )
        // First step runs synchronously — it's a fast `open`, no UI freeze —
        // so a real launch failure reaches the caller (and the error alert).
        let outcome = try Subprocess.run("/usr/bin/open", arguments: plan.steps[0])
        if outcome.status != 0 {
            throw AppLauncherError.launchFailed(outcome.failureMessage)
        }

        let rest = Array(plan.steps.dropFirst())
        guard !rest.isEmpty else { return }
        let deliver = {
            for args in rest {
                _ = try? Subprocess.run("/usr/bin/open", arguments: args)
            }
        }
        if plan.waitForAppLaunch {
            // Cold start: don't block the main thread while the app boots. Wait
            // off-thread for it to be live, then deliver the deep link (the app
            // is already launching, so this is best-effort from here).
            AppDetector.whenAppReady(agent, resolvedAppURL: appURL, then: deliver)
        } else {
            deliver()
        }
    }

    /// The launch plan for handing `projectPath` to `agent`'s app.
    ///
    /// The Codex desktop app loses a `codex://…?path=…` deep link fired at it
    /// *cold*: it boots into its last workspace before it can handle the URL
    /// event, so the project doesn't open. A *live* Codex honours the same URL
    /// immediately. So when we have a deep link, a resolvable app, and it isn't
    /// running, we two-phase the launch: step 1 opens the app, then (after it's
    /// up — `waitForAppLaunch`) step 2 delivers the deep link. Everything else
    /// — a warm Codex, an unresolved app we can only scheme-route to, or Claude
    /// (no deep link) — is a single immediate `open`.
    static func openPlan(
        agent: AgentApp,
        projectPath: String,
        resolvedAppURL: URL?,
        appRunning: Bool
    ) -> LaunchPlan {
        let fire = openArguments(
            agent: agent,
            projectPath: projectPath,
            resolvedAppURL: resolvedAppURL
        )
        if agent.projectDeepLink(forProjectPath: projectPath) != nil,
           let appURL = resolvedAppURL,
           !appRunning {
            return LaunchPlan(steps: [["-a", appURL.path], fire], waitForAppLaunch: true)
        }
        return LaunchPlan(steps: [fire], waitForAppLaunch: false)
    }

    /// Pure `/usr/bin/open` argv for *delivering* the launch to `agent`'s app,
    /// given the app [[AppDetector]] resolved (`nil` when it found none).
    /// Factored out so the launch policy is unit-testable without spawning
    /// `open`.
    ///
    /// Order of preference:
    ///
    ///   1. A project deep link (Codex `codex://threads/new?path=…`). This is
    ///      the *only* mechanism that opens the GUI on the project — a bare
    ///      folder argument is ignored. When we resolved the app we target it
    ///      explicitly (`open -a <path> <url>`) so launch and detection can't
    ///      disagree on the bundle; otherwise we fire the deep link bare and
    ///      let LaunchServices route it to whichever install registered the
    ///      `codex://` scheme (covers a side-loaded GUI under a forced "App").
    ///   2. No deep link (Claude): open the resolved app with the project as a
    ///      best-effort document argument (`open -a <path> <project>`).
    ///   3. Nothing resolved and no deep link: fall back to the bundle ID
    ///      (`open -b <id> <project>`), honouring a forced "App" best-effort.
    static func openArguments(
        agent: AgentApp,
        projectPath: String,
        resolvedAppURL: URL?
    ) -> [String] {
        if let deepLink = agent.projectDeepLink(forProjectPath: projectPath) {
            if let appURL = resolvedAppURL {
                return ["-a", appURL.path, deepLink.absoluteString]
            }
            return [deepLink.absoluteString]
        }
        if let appURL = resolvedAppURL {
            return ["-a", appURL.path, projectPath]
        }
        return ["-b", agent.bundleIdentifier, projectPath]
    }
}
