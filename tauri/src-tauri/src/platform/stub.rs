//! Fallback arm for non-Windows / non-macOS targets (Linux dev containers,
//! CI sanity checks). Read-only helpers (`settings_dir`, `augmented_path`,
//! `resolve_*_path`) return sensible local-dev values so the Rust unit
//! tests and BDD harness can exercise the cross-platform services without
//! pulling in real OS integrations. `run_shell` / `launch_terminal` still
//! panic — those need a real platform arm.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use crate::models::TerminalKind;

pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::stub::run_shell — not implemented on this OS")
}

pub fn launch_terminal(_path: &Path, _command: &str, _kind: TerminalKind) -> Result<(), String> {
    unimplemented!("platform::stub::launch_terminal — not implemented on this OS")
}

pub fn settings_dir() -> PathBuf {
    dirs::config_dir()
        .map(|d| d.join("bmad-manager"))
        .unwrap_or_else(|| PathBuf::from("bmad-manager"))
}

pub fn resolve_npx_path() -> PathBuf {
    PathBuf::from("npx")
}

pub fn resolve_git_path() -> PathBuf {
    PathBuf::from("git")
}

pub fn augmented_path() -> OsString {
    std::env::var_os("PATH").unwrap_or_default()
}
