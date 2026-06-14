//! Platform abstraction layer.
//!
//! Every OS-touching operation goes through this module so the macOS and
//! Windows arms can evolve independently without leaking `#[cfg(...)]`
//! checks into the rest of the crate. Stage 2 fills in the Windows arm;
//! a later milestone ports the Swift implementations to `platform::macos`.

use std::sync::OnceLock;

use tauri::AppHandle;

/// Initialised at app startup by [`set_app_handle`] so `resolve_npx_path`
/// and `resolve_git_path` can find the bundled resources without each
/// caller threading the `AppHandle` through manually.
static APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();

pub fn set_app_handle(handle: AppHandle) {
    let _ = APP_HANDLE.set(handle);
}

pub fn app_handle() -> Option<&'static AppHandle> {
    APP_HANDLE.get()
}

/// Error from the OS secure-credential store that backs the skills-repo
/// token. Each arm maps its backend's failures into this single opaque
/// variant; callers only ever surface the message to the user.
#[derive(Debug, thiserror::Error)]
pub enum SecretError {
    #[error("secure credential store: {0}")]
    Backend(String),
}

// Secure-credential contract implemented by every platform arm and re-exported
// below. The token store calls these; it never touches a backend directly.
//
//   secret_get(scope, account)    -> Ok(Some(value)) | Ok(None) when unset
//   secret_set(scope, account, v) -> stores `v`
//   secret_delete(scope, account) -> removes it; absent is not an error
//
// `account` is the logical credential name (a single skills-repo token today).
// `scope` is the per-user `settings_dir`: production passes one stable dir, so
// there is exactly one credential per user; tests pass a temp dir so they never
// touch the real store. The Windows arm keys Credential Manager off both; the
// stub arm uses `scope/<account>` as an owner-only file.

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::*;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod stub;
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
pub use stub::*;
