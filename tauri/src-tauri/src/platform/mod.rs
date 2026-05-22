//! Platform abstraction layer.
//!
//! Every OS-touching operation goes through this module so the macOS and
//! Windows arms can evolve independently without leaking `#[cfg(...)]`
//! checks into the rest of the crate. Stage 1 stubs every function with
//! `unimplemented!()`; Stage 2 fills in the Windows arm, and a later
//! milestone ports the Swift implementations to `platform::macos`.

/// Terminal the user wants `launch_terminal` to drive. Stage 2 moves this
/// into `models::settings` once the rest of the settings model lands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalKind {
    /// Default native terminal: Windows Terminal on Windows, Terminal.app on macOS.
    System,
    /// Alternate: cmd.exe / PowerShell on Windows, iTerm2 on macOS.
    Alternate,
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
