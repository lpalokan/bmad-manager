//! Windows arm of the platform layer. Stage 2 fills these in.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use super::TerminalKind;

/// Run `command` in `cmd.exe /C` (or `pwsh -NoLogo -Command`) with `cwd` as
/// the working directory and the augmented PATH from [`augmented_path`].
/// Returns the child's exit code.
pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::windows::run_shell — Stage 2")
}

/// Open a new terminal window in `path` and run `command`. Uses Windows
/// Terminal (`wt.exe -d <path> cmd /k <command>`) when available, falls
/// back to a detached `cmd /k`.
pub fn launch_terminal(
    _path: &Path,
    _command: &str,
    _kind: TerminalKind,
) -> Result<(), String> {
    unimplemented!("platform::windows::launch_terminal — Stage 2")
}

/// `%APPDATA%\bmad-manager`.
pub fn settings_dir() -> PathBuf {
    unimplemented!("platform::windows::settings_dir — Stage 2")
}

/// Absolute path to the bundled portable Node's `npx.cmd`.
pub fn resolve_npx_path() -> PathBuf {
    unimplemented!("platform::windows::resolve_npx_path — Stage 2")
}

/// Absolute path to the bundled PortableGit's `cmd/git.exe`.
pub fn resolve_git_path() -> PathBuf {
    unimplemented!("platform::windows::resolve_git_path — Stage 2")
}

/// PATH value to inject into spawned children: bundled-Node-bin,
/// bundled-Git-bin, then the inherited PATH.
pub fn augmented_path() -> OsString {
    unimplemented!("platform::windows::augmented_path — Stage 2")
}
