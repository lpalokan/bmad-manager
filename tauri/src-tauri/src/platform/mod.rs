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
