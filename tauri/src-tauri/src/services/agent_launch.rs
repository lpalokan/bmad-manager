//! Pure preference → concrete-launch policy for agents that ship both a
//! CLI and a desktop app (Claude, Codex).
//!
//! Mirrors the macOS `AgentLaunchResolver`: the decision is deliberately
//! free of any process/registry side effects so the policy is exhaustively
//! unit-testable. Detection ("is the GUI installed?") and the actual launch
//! live elsewhere — a Windows app detector plus a platform GUI-launch
//! primitive, added in later phases of issue #88.

use crate::models::AgentLaunchMethod;

/// The concrete launch the command layer acts on once the user's
/// preference and the app's install state are known.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResolvedAgentLaunch {
    App,
    Cli,
}

/// Map a launch method plus "is the app installed?" to a concrete launch.
///
/// - `Cli` always runs the CLI.
/// - `App` is honoured even when detection says the app is missing — the
///   user opted in, and the launcher surfaces any error rather than
///   silently downgrading to the CLI.
/// - `Auto` prefers the app when it is installed, otherwise the CLI.
pub fn resolve(method: AgentLaunchMethod, app_installed: bool) -> ResolvedAgentLaunch {
    match method {
        AgentLaunchMethod::Cli => ResolvedAgentLaunch::Cli,
        AgentLaunchMethod::App => ResolvedAgentLaunch::App,
        AgentLaunchMethod::Auto => {
            if app_installed {
                ResolvedAgentLaunch::App
            } else {
                ResolvedAgentLaunch::Cli
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_prefers_app_when_installed() {
        assert_eq!(
            resolve(AgentLaunchMethod::Auto, true),
            ResolvedAgentLaunch::App
        );
    }

    #[test]
    fn auto_falls_back_to_cli_when_missing() {
        assert_eq!(
            resolve(AgentLaunchMethod::Auto, false),
            ResolvedAgentLaunch::Cli
        );
    }

    #[test]
    fn app_is_honoured_even_when_missing() {
        assert_eq!(
            resolve(AgentLaunchMethod::App, false),
            ResolvedAgentLaunch::App
        );
    }

    #[test]
    fn cli_always_resolves_to_cli() {
        assert_eq!(
            resolve(AgentLaunchMethod::Cli, true),
            ResolvedAgentLaunch::Cli
        );
    }
}
