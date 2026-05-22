//! Windows arm of the platform layer.
//!
//! All shell invocations route through `cmd.exe /C` with an augmented
//! `PATH` that puts the bundled portable Node and PortableGit first.
//! `wt.exe` (Windows Terminal) is the default external terminal, with a
//! fallback to a detached `cmd /K`. Stage 3 wires the bundled binaries
//! in via `tauri.conf.json`'s `bundle.resources`; until then the resolve
//! helpers locate the resources via `AppHandle::path()` and fall back to
//! whatever's on `PATH` when running under `cargo tauri dev` from a
//! source checkout.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use tauri::path::BaseDirectory;
use tauri::Manager;

use crate::models::TerminalKind;

/// Run `command` under `cmd /C` with the augmented PATH. Synchronous;
/// streaming callers go through `services::command_runner` instead.
pub fn run_shell(command: &str, cwd: &Path) -> i32 {
    Command::new("cmd.exe")
        .args(["/C", command])
        .current_dir(cwd)
        .env("PATH", augmented_path())
        .stdin(Stdio::null())
        .status()
        .map(|s| s.code().unwrap_or(-1))
        .unwrap_or(-1)
}

/// Open a new terminal window in `path` and run `command`. Uses Windows
/// Terminal when available and the kind asks for it (or when nothing is
/// configured), falling back to a detached `cmd /K`.
pub fn launch_terminal(path: &Path, command: &str, kind: TerminalKind) -> Result<(), String> {
    let want_wt = matches!(
        kind,
        TerminalKind::WindowsTerminal | TerminalKind::Terminal | TerminalKind::Iterm2
    );
    if want_wt && wt_available() {
        spawn_wt(path, command).map_err(|e| e.to_string())
    } else {
        spawn_cmd(path, command).map_err(|e| e.to_string())
    }
}

fn wt_available() -> bool {
    Command::new("where")
        .arg("wt.exe")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn spawn_wt(path: &Path, command: &str) -> std::io::Result<()> {
    // `wt.exe -d <cwd> cmd /K <command>` opens a new Windows Terminal
    // tab/window in `cwd`, launching `cmd` configured to leave the
    // shell alive after `command` finishes so the user can keep typing.
    Command::new("wt.exe")
        .arg("-d")
        .arg(path)
        .arg("cmd")
        .arg("/K")
        .arg(command)
        .env("PATH", augmented_path())
        .spawn()
        .map(|_| ())
}

fn spawn_cmd(path: &Path, command: &str) -> std::io::Result<()> {
    // `start "" cmd /K` opens a detached cmd window with the same /K
    // semantics as the wt path. The empty `""` is `start`'s title arg —
    // omitting it makes `start` treat the next quoted token as the title.
    Command::new("cmd.exe")
        .args(["/C", "start", "", "cmd", "/K", command])
        .current_dir(path)
        .env("PATH", augmented_path())
        .spawn()
        .map(|_| ())
}

/// `%APPDATA%\bmad-manager` — the user's roaming config directory.
pub fn settings_dir() -> PathBuf {
    dirs::config_dir()
        .map(|d| d.join("bmad-manager"))
        .unwrap_or_else(|| PathBuf::from("bmad-manager"))
}

/// Absolute path to the bundled portable Node's `npx.cmd`, or the
/// `npx.cmd` on `PATH` if no `AppHandle` is registered yet (e.g. unit
/// tests). When `AppHandle` is set but the bundled resource is missing
/// (dev builds before Stage 3 lands the bundled tarball), we fall back
/// to whatever `PATH` has so the dev loop still works.
pub fn resolve_npx_path() -> PathBuf {
    bundled_resource("node-portable/npx.cmd").unwrap_or_else(|| PathBuf::from("npx.cmd"))
}

/// Absolute path to the bundled portable Node's `node.exe`, with the
/// same dev-friendly fallback to whatever's on `PATH`. Used by the
/// bundled-tooling version probe in the Settings dialog.
pub fn resolve_node_path() -> PathBuf {
    bundled_resource("node-portable/node.exe").unwrap_or_else(|| PathBuf::from("node.exe"))
}

/// Absolute path to bundled PortableGit's `cmd/git.exe`, with the same
/// dev-friendly fallback to `git.exe` on `PATH`.
pub fn resolve_git_path() -> PathBuf {
    bundled_resource("portable-git/cmd/git.exe").unwrap_or_else(|| PathBuf::from("git.exe"))
}

/// Absolute path to the pre-warmed npm cache shipped inside the
/// installer's `resources/npm-cache/`. Returns `None` when no handle is
/// registered yet or when the resource is missing in a dev build —
/// callers (the startup seeder) treat that as a silent no-op.
pub fn resolve_bundled_npm_cache_path() -> Option<PathBuf> {
    bundled_resource("npm-cache")
}

/// User-writable npm cache location seeded from the bundled cache on
/// first launch and used as `NPM_CONFIG_CACHE` for every spawned `npx`.
/// `%LOCALAPPDATA%\bmad-manager\npm-cache` on Windows; a sensible
/// per-user fallback elsewhere so the unit tests still work.
pub fn user_npm_cache_dir() -> PathBuf {
    dirs::data_local_dir()
        .map(|d| d.join("bmad-manager").join("npm-cache"))
        .unwrap_or_else(|| PathBuf::from("bmad-manager").join("npm-cache"))
}

fn bundled_resource(relative: &str) -> Option<PathBuf> {
    let handle = super::app_handle()?;
    let resolved = handle
        .path()
        .resolve(relative, BaseDirectory::Resource)
        .ok()?;
    resolved.exists().then_some(resolved)
}

/// PATH value injected into spawned children: bundled-Node-bin first,
/// bundled-Git-bin second, then the inherited `PATH`. The Windows arm
/// of `services::command_runner` sets this on every `cmd /C` invocation.
pub fn augmented_path() -> OsString {
    let inherited = std::env::var_os("PATH").unwrap_or_default();
    let node_dir = resolve_npx_path().parent().map(|p| p.to_path_buf());
    let git_exe = resolve_git_path();
    let git_dir = git_exe.parent().map(|p| p.to_path_buf());

    let mut paths: Vec<PathBuf> = Vec::new();
    if let Some(d) = node_dir {
        if d.is_dir() {
            paths.push(d);
        }
    }
    if let Some(d) = git_dir {
        if d.is_dir() {
            paths.push(d);
        }
    }
    let mut combined = std::env::join_paths(paths).unwrap_or_default();
    if !inherited.is_empty() {
        if !combined.is_empty() {
            combined.push(";");
        }
        combined.push(&inherited);
    }
    combined
}
