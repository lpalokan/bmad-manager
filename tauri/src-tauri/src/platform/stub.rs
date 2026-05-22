//! Fallback arm for non-Windows / non-macOS targets (Linux dev containers,
//! CI sanity checks). Every function panics — these stubs exist only so
//! `cargo check` on Linux can verify the rest of the crate compiles without
//! pulling in real OS integrations.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use super::TerminalKind;

pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::stub::run_shell — not implemented on this OS")
}

pub fn launch_terminal(
    _path: &Path,
    _command: &str,
    _kind: TerminalKind,
) -> Result<(), String> {
    unimplemented!("platform::stub::launch_terminal — not implemented on this OS")
}

pub fn settings_dir() -> PathBuf {
    unimplemented!("platform::stub::settings_dir — not implemented on this OS")
}

pub fn resolve_npx_path() -> PathBuf {
    unimplemented!("platform::stub::resolve_npx_path — not implemented on this OS")
}

pub fn resolve_git_path() -> PathBuf {
    unimplemented!("platform::stub::resolve_git_path — not implemented on this OS")
}

pub fn augmented_path() -> OsString {
    unimplemented!("platform::stub::augmented_path — not implemented on this OS")
}
