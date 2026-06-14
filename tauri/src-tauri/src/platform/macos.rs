//! macOS arm of the platform layer. Intentionally `unimplemented!()` until
//! the Tauri unification milestone — see the future-proofing table in
//! issue #25. Building the Tauri tree for macOS will fail loudly on these
//! call sites, which is the point: we want to notice every new caller that
//! needs a macOS implementation before it ships.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use crate::models::TerminalKind;

pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::macos::run_shell — future macOS unification milestone")
}

pub fn launch_terminal(_path: &Path, _command: &str, _kind: TerminalKind) -> Result<(), String> {
    unimplemented!("platform::macos::launch_terminal — future macOS unification milestone")
}

pub fn open_folder(_path: &Path) -> Result<(), String> {
    unimplemented!("platform::macos::open_folder — future macOS unification milestone")
}

pub fn settings_dir() -> PathBuf {
    unimplemented!("platform::macos::settings_dir — future macOS unification milestone")
}

pub fn resolve_npx_path() -> PathBuf {
    unimplemented!("platform::macos::resolve_npx_path — future macOS unification milestone")
}

pub fn resolve_node_path() -> PathBuf {
    unimplemented!("platform::macos::resolve_node_path — future macOS unification milestone")
}

pub fn resolve_git_path() -> PathBuf {
    unimplemented!("platform::macos::resolve_git_path — future macOS unification milestone")
}

pub fn resolve_bundled_npm_cache_path() -> Option<PathBuf> {
    unimplemented!(
        "platform::macos::resolve_bundled_npm_cache_path — future macOS unification milestone"
    )
}

pub fn user_npm_cache_dir() -> PathBuf {
    unimplemented!("platform::macos::user_npm_cache_dir — future macOS unification milestone")
}

pub fn augmented_path() -> OsString {
    unimplemented!("platform::macos::augmented_path — future macOS unification milestone")
}

pub fn secret_get(_scope: &Path, _account: &str) -> Result<Option<String>, super::SecretError> {
    unimplemented!("platform::macos::secret_get — future macOS unification milestone")
}

pub fn secret_set(_scope: &Path, _account: &str, _secret: &str) -> Result<(), super::SecretError> {
    unimplemented!("platform::macos::secret_set — future macOS unification milestone")
}

pub fn secret_delete(_scope: &Path, _account: &str) -> Result<(), super::SecretError> {
    unimplemented!("platform::macos::secret_delete — future macOS unification milestone")
}
