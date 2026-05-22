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
    let mut cmd = Command::new(&shell);
    cmd.args(&args)
        .current_dir(cwd)
        .env("PATH", platform::augmented_path())
        // Point npx at the user-writable cache seeded from the bundled
        // pre-warm at first launch (see `bundled_tooling::seed_*`). On the
        // Linux stub arm this is just a per-user fallback path; on Windows
        // it's `%LOCALAPPDATA%\bmad-manager\npm-cache`. Setting it here
        // means every project-create run picks it up without the user
        // having to configure anything.
        .env("NPM_CONFIG_CACHE", platform::user_npm_cache_dir())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(Stdio::null());

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
                let _ = tx.send(OutputEvent::Stdout { line });
            }
        });
    }
    if let Some(stderr) = stderr {
        let tx = tx.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = tx.send(OutputEvent::Stderr { line });
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
}
