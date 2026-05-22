//! macOS arm of the platform layer. Intentionally `unimplemented!()` until
//! the Tauri unification milestone — see the future-proofing table in
//! issue #25. Building the Tauri tree for macOS will fail loudly on these
//! call sites, which is the point: we want to notice every new caller that
//! needs a macOS implementation before it ships.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use super::TerminalKind;

/// Port from `Sources/BmadManager/Services/ShellProcess.swift` —
/// `/bin/zsh -lc '...'` with `cwd` as the working directory.
pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::macos::run_shell — future macOS unification milestone")
}

/// Port from `Sources/BmadManager/Services/TerminalLauncher.swift` —
/// `osascript` driving Terminal.app or iTerm2.
pub fn launch_terminal(
    _path: &Path,
    _command: &str,
    _kind: TerminalKind,
) -> Result<(), String> {
    unimplemented!("platform::macos::launch_terminal — future macOS unification milestone")
}

/// `~/Library/Application Support/bmad-manager`.
pub fn settings_dir() -> PathBuf {
    unimplemented!("platform::macos::settings_dir — future macOS unification milestone")
}

/// macOS uses system `npx` from the user's shell PATH — no bundled Node.
pub fn resolve_npx_path() -> PathBuf {
    unimplemented!("platform::macos::resolve_npx_path — future macOS unification milestone")
}

/// macOS uses system `git` from Xcode Command Line Tools — no bundled Git.
pub fn resolve_git_path() -> PathBuf {
    unimplemented!("platform::macos::resolve_git_path — future macOS unification milestone")
}

/// macOS inherits PATH unchanged from the login shell.
pub fn augmented_path() -> OsString {
    unimplemented!("platform::macos::augmented_path — future macOS unification milestone")
}
