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

use super::SecretError;
use crate::models::{NewSessionPlacement, ShellKind, TerminalKind};
use crate::services::terminal::{fallback_cmd_args, shell_argv, wt_args, APP_WINDOW_NAME};

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

/// Open a new session in `path` running `command`. `shell` picks the
/// interpreter (cmd / PowerShell); `placement` picks new window vs. a tab
/// in the app's dedicated Windows Terminal window. Uses Windows Terminal
/// when available and the kind asks for it (or when nothing is
/// configured), falling back to a detached standalone window — in which
/// case `placement` is ignored (a standalone window can't be tabbed).
pub fn launch_terminal(
    path: &Path,
    command: &str,
    kind: TerminalKind,
    shell: ShellKind,
    placement: NewSessionPlacement,
) -> Result<(), String> {
    let want_wt = matches!(
        kind,
        TerminalKind::WindowsTerminal | TerminalKind::Terminal | TerminalKind::Iterm2
    );
    if want_wt && wt_available() {
        spawn_wt(path, command, shell, placement).map_err(|e| e.to_string())
    } else {
        spawn_cmd(path, command, shell).map_err(|e| e.to_string())
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

fn spawn_wt(
    path: &Path,
    command: &str,
    shell: ShellKind,
    placement: NewSessionPlacement,
) -> std::io::Result<()> {
    // e.g. `wt.exe -w bmad-manager new-tab -d <cwd> powershell.exe -NoExit
    // -Command <command>` opens (or reuses) the app's Windows Terminal
    // window and adds a tab in `cwd` running the chosen shell, left alive
    // after `command` finishes so the user can keep typing. The arg vector
    // is built by the platform-agnostic `services::terminal` so it can be
    // unit-tested off-Windows.
    let inner = shell_argv(shell, command);
    Command::new("wt.exe")
        .args(wt_args(
            placement,
            APP_WINDOW_NAME,
            &path.to_string_lossy(),
            &inner,
        ))
        .env("PATH", augmented_path())
        .spawn()
        .map(|_| ())
}

fn spawn_cmd(path: &Path, command: &str, shell: ShellKind) -> std::io::Result<()> {
    // `start "" <shell …>` opens a detached standalone window with the
    // same keep-alive semantics as the wt path. Placement is irrelevant
    // here — a standalone window can't be a tab — so this always opens a
    // new window.
    let inner = shell_argv(shell, command);
    Command::new("cmd.exe")
        .args(fallback_cmd_args(&inner))
        .current_dir(path)
        .env("PATH", augmented_path())
        .spawn()
        .map(|_| ())
}

/// Reveal `path` in Windows Explorer. Explorer's exit code is unreliable
/// (it often returns 1 even on success), so — like the terminal launchers —
/// we only surface failures to *spawn* the process, not its exit status.
pub fn open_folder(path: &Path) -> Result<(), String> {
    Command::new("explorer.exe")
        .arg(path)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Whether the Codex desktop GUI is installed, detected by the presence of
/// its `codex://` URL-scheme registration. `HKEY_CLASSES_ROOT` merges the
/// per-machine and per-user class roots, so this catches either install.
/// Mirrors `wt_available`'s "ask the OS, don't guess an install path"
/// approach — the scheme is exactly what we need to fire the deep link.
pub fn codex_app_installed() -> bool {
    Command::new("reg")
        .args(["query", r"HKCR\codex\shell\open\command"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Open `url` with its registered protocol handler — e.g. `codex://…`
/// launches the Codex GUI. Routed through `cmd /C start "" "<url>"` so the
/// URL goes to **ShellExecute**, the same dispatch the Run dialog uses;
/// `explorer.exe <url>` does NOT do this — it treats the string as a shell
/// location and fails. The empty `""` is `start`'s window-title argument
/// (so a quoted URL isn't taken as the title). cmd leaves the
/// percent-encoded URL untouched — no defined `%VAR%` matches — so the deep
/// link arrives intact. Exit status is unobservable through `start`, so we
/// surface only failures to spawn the launcher.
pub fn open_app_url(url: &str) -> Result<(), String> {
    Command::new("cmd")
        .args(["/C", "start", "", url])
        .stdin(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
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
    // Tauri's path resolver runs the result through canonicalization,
    // which on Windows tags the path with the `\\?\` verbatim prefix.
    // That prefix is valid for raw Win32 file APIs but breaks when the
    // path is used as a PATH entry, a command name, or inside a batch
    // file (npx.cmd's `%~dp0` expansion + cmd.exe's `cd /D`). Strip it
    // before handing the path to anything that goes through cmd.exe.
    let normalized = strip_verbatim_prefix(&resolved);
    normalized.exists().then_some(normalized)
}

/// Strip the Windows verbatim path prefix (`\\?\`) if present, mapping
/// `\\?\UNC\server\share` back to its native `\\server\share` form
/// along the way. Returns the input untouched when no prefix is found.
fn strip_verbatim_prefix(path: &Path) -> PathBuf {
    let as_str = path.as_os_str().to_string_lossy();
    if let Some(rest) = as_str.strip_prefix(r"\\?\") {
        if let Some(unc) = rest.strip_prefix("UNC\\") {
            return PathBuf::from(format!(r"\\{unc}"));
        }
        return PathBuf::from(rest);
    }
    path.to_path_buf()
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

// --- Secure-credential store (Windows Credential Manager) -------------------
//
// The skills-repo token is stored as a Generic credential via `keyring`,
// keyed by an app/account service name plus the per-user `scope` (settings
// dir). Production passes one stable scope, so there is a single credential
// per user; tests pass a temp scope so they never touch the real one. No
// plaintext token file is ever written on Windows.

fn entry(scope: &Path, account: &str) -> Result<keyring::Entry, SecretError> {
    let service = format!("BMad Manager ({account})");
    keyring::Entry::new(&service, &scope.to_string_lossy())
        .map_err(|e| SecretError::Backend(e.to_string()))
}

/// Read the stored secret, or `None` when no credential exists.
pub fn secret_get(scope: &Path, account: &str) -> Result<Option<String>, SecretError> {
    match entry(scope, account)?.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(SecretError::Backend(e.to_string())),
    }
}

/// Store `secret`, replacing any existing credential.
pub fn secret_set(scope: &Path, account: &str, secret: &str) -> Result<(), SecretError> {
    entry(scope, account)?
        .set_password(secret)
        .map_err(|e| SecretError::Backend(e.to_string()))
}

/// Remove the credential if present; a missing credential is success.
pub fn secret_delete(scope: &Path, account: &str) -> Result<(), SecretError> {
    match entry(scope, account)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(SecretError::Backend(e.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::strip_verbatim_prefix;
    use std::path::{Path, PathBuf};

    #[test]
    fn strips_drive_letter_verbatim_prefix() {
        assert_eq!(
            strip_verbatim_prefix(Path::new(r"\\?\C:\Users\Lauri\app\node.exe")),
            PathBuf::from(r"C:\Users\Lauri\app\node.exe")
        );
    }

    #[test]
    fn is_identity_when_no_verbatim_prefix() {
        let p = Path::new(r"C:\Users\Lauri\app\node.exe");
        assert_eq!(strip_verbatim_prefix(p), p.to_path_buf());
    }

    #[test]
    fn maps_unc_verbatim_back_to_native_unc() {
        assert_eq!(
            strip_verbatim_prefix(Path::new(r"\\?\UNC\server\share\file.exe")),
            PathBuf::from(r"\\server\share\file.exe")
        );
    }

    #[test]
    fn handles_path_with_spaces_intact() {
        assert_eq!(
            strip_verbatim_prefix(Path::new(r"\\?\C:\Program Files\App\bin.exe")),
            PathBuf::from(r"C:\Program Files\App\bin.exe")
        );
    }
}

// Exercises the real Windows Credential Manager, so it only runs on a Windows
// host (this whole module is `#[cfg(target_os = "windows")]`). Uses a unique
// per-run scope + a dedicated test account so it never touches the real
// skills-repo credential, and cleans up after itself.
#[cfg(test)]
mod secret_tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn token_round_trips_through_credential_manager_without_writing_a_file() {
        let tmp = TempDir::new().unwrap();
        let scope = tmp.path();
        let account = "skills-repo-token-test";

        secret_delete(scope, account).unwrap();
        assert_eq!(secret_get(scope, account).unwrap(), None);

        secret_set(scope, account, "ghp_secret").unwrap();
        assert_eq!(
            secret_get(scope, account).unwrap(),
            Some("ghp_secret".to_string())
        );
        // The Windows arm keeps the token in Credential Manager, never on disk.
        assert!(!scope.join(account).exists());

        secret_delete(scope, account).unwrap();
        assert_eq!(secret_get(scope, account).unwrap(), None);
    }
}
