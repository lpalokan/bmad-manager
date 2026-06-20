//! Pure builders for the external-terminal launch command line.
//!
//! These produce the argument vectors handed to `wt.exe` (and the
//! standalone-window fallback) when opening an agent session on Windows.
//! They live here — not in the Windows-only `platform::windows` arm — so
//! the launch behaviour is unit-testable on every host, including the
//! macOS/Linux dev and CI machines where `platform::windows` isn't
//! compiled. `platform::windows` is the only caller; it turns these
//! vectors into a spawned `Command`.

use crate::models::{NewSessionPlacement, ShellKind};

/// Name of the dedicated Windows Terminal window the app groups its
/// sessions into when the user picks "New tab". `wt -w <name>` reuses an
/// existing window with this name or creates it on first launch, so
/// repeat launches stack as tabs in one app-owned window rather than
/// scattering across the user's other terminals.
pub const APP_WINDOW_NAME: &str = "bmad-manager";

/// Argument vector that runs `command` in the chosen shell and keeps the
/// shell alive afterwards so the user can keep typing. This is the
/// `<shell> …` tail shared by the Windows Terminal and fallback paths.
///
/// `-NoExit` is PowerShell's equivalent of `cmd`'s `/K`: run the command,
/// then drop to an interactive prompt instead of exiting.
pub fn shell_argv(shell: ShellKind, command: &str) -> Vec<String> {
    match shell {
        ShellKind::Cmd => vec!["cmd".into(), "/K".into(), command.into()],
        ShellKind::PowerShell => vec![
            "powershell.exe".into(),
            "-NoExit".into(),
            "-Command".into(),
            command.into(),
        ],
        ShellKind::Pwsh => vec![
            "pwsh.exe".into(),
            "-NoExit".into(),
            "-Command".into(),
            command.into(),
        ],
    }
}

/// Full `wt.exe` argument vector: window targeting + a new tab started in
/// `cwd` running `shell_argv`.
///
/// - `NewTab` targets the app's dedicated window (`-w <window_name>`), so
///   repeat launches stack as tabs in that one window.
/// - `NewWindow` forces a brand-new window (`-w new`).
pub fn wt_args(
    placement: NewSessionPlacement,
    window_name: &str,
    cwd: &str,
    shell_argv: &[String],
) -> Vec<String> {
    let target = match placement {
        NewSessionPlacement::NewTab => window_name.to_string(),
        NewSessionPlacement::NewWindow => "new".to_string(),
    };
    let mut args = vec![
        "-w".to_string(),
        target,
        "new-tab".to_string(),
        "-d".to_string(),
        cwd.to_string(),
    ];
    args.extend(shell_argv.iter().cloned());
    args
}

/// Argument vector for the no-Windows-Terminal fallback: a detached
/// standalone window via `cmd /C start "" <shell_argv>`. Placement has no
/// meaning here (a standalone window can't be a tab), so it is ignored and
/// every launch opens its own window. The empty `""` is `start`'s title
/// argument — omitting it makes `start` treat the next quoted token as the
/// window title instead of the program to run.
pub fn fallback_cmd_args(shell_argv: &[String]) -> Vec<String> {
    let mut args = vec!["/C".to_string(), "start".to_string(), String::new()];
    args.extend(shell_argv.iter().cloned());
    args
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cmd_shell_keeps_window_open_with_slash_k() {
        assert_eq!(
            shell_argv(ShellKind::Cmd, "claude"),
            vec!["cmd", "/K", "claude"]
        );
    }

    #[test]
    fn powershell_shell_uses_noexit_command() {
        assert_eq!(
            shell_argv(ShellKind::PowerShell, "claude"),
            vec!["powershell.exe", "-NoExit", "-Command", "claude"]
        );
    }

    #[test]
    fn pwsh_shell_targets_the_v7_binary() {
        assert_eq!(
            shell_argv(ShellKind::Pwsh, "claude"),
            vec!["pwsh.exe", "-NoExit", "-Command", "claude"]
        );
    }

    #[test]
    fn new_tab_targets_the_app_window() {
        let inner = shell_argv(ShellKind::Cmd, "claude");
        assert_eq!(
            wt_args(
                NewSessionPlacement::NewTab,
                APP_WINDOW_NAME,
                r"C:\proj",
                &inner
            ),
            vec![
                "-w",
                "bmad-manager",
                "new-tab",
                "-d",
                r"C:\proj",
                "cmd",
                "/K",
                "claude"
            ]
        );
    }

    #[test]
    fn new_window_forces_a_fresh_window() {
        let inner = shell_argv(ShellKind::Cmd, "claude");
        let args = wt_args(
            NewSessionPlacement::NewWindow,
            APP_WINDOW_NAME,
            r"C:\proj",
            &inner,
        );
        assert_eq!(&args[0..2], &["-w", "new"]);
        assert!(!args.contains(&"bmad-manager".to_string()));
    }

    #[test]
    fn new_tab_with_powershell_combines_both_choices() {
        let inner = shell_argv(ShellKind::PowerShell, "codex");
        assert_eq!(
            wt_args(
                NewSessionPlacement::NewTab,
                APP_WINDOW_NAME,
                r"C:\work",
                &inner
            ),
            vec![
                "-w",
                "bmad-manager",
                "new-tab",
                "-d",
                r"C:\work",
                "powershell.exe",
                "-NoExit",
                "-Command",
                "codex"
            ]
        );
    }

    #[test]
    fn fallback_wraps_shell_in_detached_start() {
        let inner = shell_argv(ShellKind::PowerShell, "pi");
        assert_eq!(
            fallback_cmd_args(&inner),
            vec![
                "/C",
                "start",
                "",
                "powershell.exe",
                "-NoExit",
                "-Command",
                "pi"
            ]
        );
    }
}
