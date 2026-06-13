import Foundation

/// The concrete launch the coordinator acts on once the user's preference
/// and the app's install state are known.
enum ResolvedAgentLaunch: Equatable {
    case app
    case cli
}

/// Pure decision logic mapping an [[AgentLaunchMethod]] plus "is the app
/// installed?" to a concrete [[ResolvedAgentLaunch]]. Deliberately free of
/// `NSWorkspace`/`Process` so the policy is exhaustively unit-testable;
/// the side-effecting halves live in [[AppDetector]] / [[AppLauncher]].
enum AgentLaunchResolver {
    static func resolve(method: AgentLaunchMethod, appInstalled: Bool) -> ResolvedAgentLaunch {
        switch method {
        case .cli:
            return .cli
        case .app:
            // Honour an explicit App choice even when detection says the
            // app is missing — the user opted in, and `open` surfaces any
            // error rather than silently downgrading to the CLI.
            return .app
        case .auto:
            return appInstalled ? .app : .cli
        }
    }
}
