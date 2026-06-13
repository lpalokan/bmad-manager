use std::path::{Path, PathBuf};
use std::process::Stdio;

use serde::Serialize;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::platform;

/// Chunk of streamed output from a running command. The Tauri command
/// emits one of these per line so the Svelte UI's CommandOutput panel
/// can keep up without buffering the whole run.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum OutputEvent {
    Stdout { line: String },
    Stderr { line: String },
    Exit { code: i32 },
}

/// Runs `command` under the platform shell (`cmd /C ...` on Windows,
/// `/bin/zsh -lc ...` on macOS) with `cwd` as the working directory and
/// the augmented `PATH` from `platform::augmented_path()`. `on_event` is
/// called once per stdout/stderr line and once with the final exit code.
pub async fn run<F>(command: &str, cwd: &Path, mut on_event: F) -> i32
where
    F: FnMut(OutputEvent) + Send,
{
    let (shell, args) = platform_shell_invocation(command);
    let augmented_path = platform::augmented_path();
    let npm_cache = platform::user_npm_cache_dir();

    // Surface what we're actually about to spawn so the output panel
    // shows the exact shell + cwd + relevant env vars before any user
    // output. Critical for diagnosing "system cannot find the path"
    // style errors on Windows where the failing path is otherwise
    // invisible.
    on_event(OutputEvent::Stderr {
        line: format!("[bmad] shell={shell:?} args={args:?} cwd={}", cwd.display()),
    });
    on_event(OutputEvent::Stderr {
        line: format!("[bmad] PATH={}", augmented_path.to_string_lossy()),
    });
    on_event(OutputEvent::Stderr {
        line: format!("[bmad] NPM_CONFIG_CACHE={}", npm_cache.display()),
    });
    on_event(OutputEvent::Stderr {
        line: format!(
            "[bmad] cwd-exists={} npx={} (exists={}) git={} (exists={})",
            cwd.exists(),
            platform::resolve_npx_path().display(),
            platform::resolve_npx_path().exists(),
            platform::resolve_git_path().display(),
            platform::resolve_git_path().exists(),
        ),
    });

    let mut cmd = Command::new(&shell);
    apply_shell_args(&mut cmd, &args, command);
    cmd.current_dir(cwd)
        .env("PATH", augmented_path)
        // Point npx at the user-writable cache seeded from the bundled
        // pre-warm at first launch (see `bundled_tooling::seed_*`). On the
        // Linux stub arm this is just a per-user fallback path; on Windows
        // it's `%LOCALAPPDATA%\bmad-manager\npm-cache`. Setting it here
        // means every project-create run picks it up without the user
        // having to configure anything.
        .env("NPM_CONFIG_CACHE", npm_cache)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(Stdio::null());

    // CREATE_NO_WINDOW = 0x08000000 — without it, spawning cmd.exe from
    // a Tauri GUI flashes a visible console window for every subprocess
    // (npm/npx/node child processes inherit and stack windows). The
    // stdout/stderr pipes still flow back to the output panel either
    // way; this just keeps the screen quiet. tokio::process::Command
    // exposes `creation_flags` as an inherent method on Windows, so no
    // trait import is needed (and importing std's CommandExt here would
    // trip `unused_imports` under `-D warnings`).
    #[cfg(windows)]
    cmd.creation_flags(0x0800_0000);

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(err) => {
            on_event(OutputEvent::Stderr {
                line: format!("Failed to launch shell ({shell:?}): {err}"),
            });
            on_event(OutputEvent::Exit { code: -1 });
            return -1;
        }
    };

    let stdout = child.stdout.take();
    let stderr = child.stderr.take();

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<OutputEvent>();

    if let Some(stdout) = stdout {
        let tx = tx.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = tx.send(OutputEvent::Stdout {
                    line: sanitize_terminal_line(&line),
                });
            }
        });
    }
    if let Some(stderr) = stderr {
        let tx = tx.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = tx.send(OutputEvent::Stderr {
                    line: sanitize_terminal_line(&line),
                });
            }
        });
    }
    drop(tx);

    while let Some(event) = rx.recv().await {
        on_event(event);
    }

    let exit_code = match child.wait().await {
        Ok(status) => status.code().unwrap_or(-1),
        Err(err) => {
            on_event(OutputEvent::Stderr {
                line: format!("Wait failed: {err}"),
            });
            -1
        }
    };
    on_event(OutputEvent::Exit { code: exit_code });
    exit_code
}

/// Attaches the shell arguments to `cmd`. On Windows the command string is
/// handed to `cmd.exe` via `raw_arg` rather than the normal `.args()` path.
///
/// `std`/`tokio` escape `.arg()`/`.args()` values using the MSVCRT C-runtime
/// rules (wrap-in-quotes, escape embedded `"` as `\"`). `cmd.exe` does **not**
/// understand `\"` — it treats the backslash as literal and the quote as a
/// toggle — so a substituted `--directory "C:\…\proj"` argument arrives at
/// `npx` → `node` with the surrounding double-quotes leaked into `argv`. `node`
/// then resolves the quoted, no-longer-absolute path relative to the cwd,
/// producing the `…\proj\"C:\…\proj"` ENOENT seen in the install log. Passing
/// the command verbatim with `raw_arg` lets `cmd.exe` parse the clean embedded
/// quotes itself, so the path reaches `node` intact. (`_args` already holds
/// `["/C", command]`; we keep it only for the diagnostic line.)
#[cfg(target_os = "windows")]
fn apply_shell_args(cmd: &mut Command, _args: &[String], command: &str) {
    // `raw_arg` is an inherent method on tokio's `Command` on Windows (no
    // `CommandExt` import — importing it would trip `unused_imports` under
    // `-D warnings`, same as the `creation_flags` call above). std inserts a
    // separating space before each appended arg, so this yields the verbatim
    // command line `cmd.exe /C <command>`.
    cmd.raw_arg("/C");
    cmd.raw_arg(command);
}

#[cfg(not(target_os = "windows"))]
fn apply_shell_args(cmd: &mut Command, args: &[String], _command: &str) {
    cmd.args(args);
}

/// Strips ANSI/VT escape sequences from a line of subprocess output so the
/// plain-text output panel shows readable text instead of raw control codes.
///
/// `npx bmad-method` paints its UI with SGR colour codes and drives a spinner
/// that rewrites a single logical line in place via `ESC[1G` (cursor to
/// column 1) + `ESC[J` (clear) *without* emitting a newline between frames.
/// `BufReader::lines()` only breaks on `\n`, so every spinner frame arrives
/// concatenated into one giant line. We therefore keep only the final frame
/// (everything after the last column-1 reset / carriage return) and then drop
/// the remaining escape sequences and stray C0 control bytes.
pub fn sanitize_terminal_line(raw: &str) -> String {
    // Drop any line terminator first so a trailing CR isn't mistaken for a
    // spinner frame boundary (which would blank the line).
    let raw = raw.trim_end_matches(['\r', '\n']);
    // Treat the spinner's "cursor to column 1" sequence like a carriage
    // return so overwritten frames collapse uniformly.
    let normalised = raw.replace("\u{1b}[1G", "\r");
    let last_frame = match normalised.rfind('\r') {
        Some(i) => &normalised[i + 1..],
        None => normalised.as_str(),
    };
    strip_escape_sequences(last_frame)
}

/// Removes CSI (`ESC[…`) and OSC (`ESC]…`) escape sequences plus leftover C0
/// control bytes (except tab) from `s`, returning the visible text.
fn strip_escape_sequences(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\u{1b}' => match chars.peek() {
                // CSI: ESC [ <0x20-0x3f params/intermediates> <0x40-0x7e final>
                Some(&'[') => {
                    chars.next();
                    while matches!(chars.peek(), Some(&p) if ('\u{20}'..='\u{3f}').contains(&p)) {
                        chars.next();
                    }
                    if matches!(chars.peek(), Some(&p) if ('\u{40}'..='\u{7e}').contains(&p)) {
                        chars.next();
                    }
                }
                // OSC: ESC ] … terminated by BEL or ESC\.
                Some(&']') => {
                    chars.next();
                    while let Some(&p) = chars.peek() {
                        chars.next();
                        if p == '\u{7}' {
                            break;
                        }
                    }
                }
                // Lone ESC or other two-char escape — drop the next byte.
                _ => {
                    chars.next();
                }
            },
            '\u{7f}' => {}
            c if (c as u32) < 0x20 && c != '\t' => {}
            c => out.push(c),
        }
    }
    out.trim_end().to_string()
}

fn platform_shell_invocation(command: &str) -> (PathBuf, Vec<String>) {
    #[cfg(target_os = "windows")]
    {
        (
            PathBuf::from("cmd.exe"),
            vec!["/C".to_string(), command.to_string()],
        )
    }
    #[cfg(target_os = "macos")]
    {
        (
            PathBuf::from("/bin/zsh"),
            vec!["-lc".to_string(), command.to_string()],
        )
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        (
            PathBuf::from("/bin/sh"),
            vec!["-c".to_string(), command.to_string()],
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn runs_a_simple_echo() {
        let mut lines: Vec<String> = Vec::new();
        let mut exit_code: Option<i32> = None;
        let code = run(
            "echo hello-from-test",
            std::env::temp_dir().as_path(),
            |event| match event {
                OutputEvent::Stdout { line } => lines.push(line),
                OutputEvent::Stderr { line } => lines.push(format!("[err] {line}")),
                OutputEvent::Exit { code } => exit_code = Some(code),
            },
        )
        .await;
        assert_eq!(code, 0);
        assert_eq!(exit_code, Some(0));
        assert!(
            lines.iter().any(|l| l.contains("hello-from-test")),
            "expected echo output, got {lines:?}"
        );
    }

    #[test]
    fn sanitize_strips_sgr_colour_codes() {
        assert_eq!(
            sanitize_terminal_line("\u{1b}[34mhello\u{1b}[39m world"),
            "hello world"
        );
    }

    #[test]
    fn sanitize_leaves_plain_diagnostic_lines_untouched() {
        let line = "[bmad] init_command exit_code=0";
        assert_eq!(sanitize_terminal_line(line), line);
    }

    #[test]
    fn sanitize_drops_cursor_hide_show_and_clear() {
        assert_eq!(sanitize_terminal_line("\u{1b}[?25l|\u{1b}[?25h"), "|");
    }

    #[test]
    fn sanitize_collapses_spinner_frames_to_final() {
        // ESC[?25l hides cursor; each frame ends ESC[1G ESC[J then redraws.
        let raw = "\u{1b}[?25l\u{1b}[34m•\u{1b}[39m  Installing core\
                   \u{1b}[1G\u{1b}[Jo  Installing core\
                   \u{1b}[1G\u{1b}[J0  4 module(s) installed";
        assert_eq!(sanitize_terminal_line(raw), "0  4 module(s) installed");
    }

    // Regression for the install failure where a quoted `--directory
    // "C:\…\proj"` reached `npx`/`node` with the surrounding double-quotes
    // leaked into argv (node then resolved the quoted path relative to the
    // cwd → `…\proj\"C:\…\proj"` ENOENT). We can't spawn npx here, but the
    // leak is purely a `cmd.exe` quoting problem: a `for %I in ("<path>")`
    // command exercises the exact same embedded-quote parsing. `%~I` strips
    // the quotes cmd.exe sees, so a clean round-trip prints the bare path;
    // a leaked `\"` would split the path or keep the quotes, failing here.
    #[cfg(windows)]
    #[tokio::test]
    async fn windows_passes_embedded_quotes_to_cmd_verbatim() {
        let mut lines: Vec<String> = Vec::new();
        let mut exit_code: Option<i32> = None;
        let code = run(
            r#"for %I in ("C:\Users\Me\My Project\proj") do @echo GOT:[%~I]"#,
            std::env::temp_dir().as_path(),
            |event| match event {
                OutputEvent::Stdout { line } => lines.push(line),
                OutputEvent::Stderr { line } => lines.push(format!("[err] {line}")),
                OutputEvent::Exit { code } => exit_code = Some(code),
            },
        )
        .await;
        assert_eq!(code, 0, "lines={lines:?}");
        assert_eq!(exit_code, Some(0));
        assert!(
            lines
                .iter()
                .any(|l| l == r#"GOT:[C:\Users\Me\My Project\proj]"#),
            "embedded quotes leaked into the path — expected a clean GOT:[…] line, got {lines:?}"
        );
    }
}
