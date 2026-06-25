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

/// The `codex://` deep link that opens the Codex GUI on `project_path`.
///
/// A bare folder argument is ignored by Codex, so opening the GUI *on* a
/// project requires this `threads/new?path=…` link. Mirrors the macOS
/// `AgentApp.codex` deep link, including the percent-encoding, so the same
/// path produces the same link on both platforms.
pub fn codex_project_deep_link(project_path: &str) -> String {
    format!(
        "codex://threads/new?path={}",
        percent_encode_unreserved(project_path)
    )
}

/// Percent-encode `input`, keeping only the RFC 3986 unreserved set
/// (`A–Z a–z 0–9 - . _ ~`). Every other byte becomes `%XX` with uppercase
/// hex. Matches the macOS deep-link encoding; on Windows this turns the
/// drive colon, backslashes, and spaces in a project path into `%3A`,
/// `%5C`, and `%20` so the URL stays well-formed.
fn percent_encode_unreserved(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for &byte in input.as_bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            out.push(byte as char);
        } else {
            out.push('%');
            out.push_str(&format!("{byte:02X}"));
        }
    }
    out
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

    #[test]
    fn deep_link_percent_encodes_a_windows_path() {
        assert_eq!(
            codex_project_deep_link(r"C:\Users\Lauri\proj"),
            "codex://threads/new?path=C%3A%5CUsers%5CLauri%5Cproj"
        );
    }

    #[test]
    fn deep_link_encodes_spaces_and_keeps_unreserved() {
        assert_eq!(
            codex_project_deep_link(r"C:\My Apps\bmad-x_1.2~3"),
            "codex://threads/new?path=C%3A%5CMy%20Apps%5Cbmad-x_1.2~3"
        );
    }
}
