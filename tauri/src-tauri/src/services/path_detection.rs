//! Resolves a coding-agent command to an absolute file path by walking
//! the supplied (or process) `PATH`. The Settings dialog calls this for
//! `claude` / `opencode` / `pi` so the user knows whether the bare-name
//! defaults are reachable before they hit "Open in …".
//!
//! Mirrors enough of the standard `which(1)` behaviour to be useful:
//!
//!   * Bare command names are looked up under every PATH entry.
//!   * Absolute or explicitly-relative paths (anything containing a
//!     separator) are checked as-is — no PATH lookup, no extension
//!     guessing — which matches how shells dispatch them.
//!   * On Windows we try the suffixes from `PATHEXT` (defaulting to
//!     `.exe`, `.cmd`, `.bat`) so `claude` finds `claude.exe`.
//!
//! The function takes the PATH explicitly so tests can pin it without
//! mutating process-global state.

use std::ffi::OsStr;
use std::path::{Path, PathBuf};

pub fn detect_command_in_path(command: &str, path_env: Option<&OsStr>) -> Option<PathBuf> {
    let trimmed = command.trim();
    if trimmed.is_empty() {
        return None;
    }

    let as_path = Path::new(trimmed);
    if looks_like_path(trimmed) {
        return as_path.is_file().then(|| as_path.to_path_buf());
    }

    let owned;
    let path = match path_env {
        Some(p) => p,
        None => {
            owned = std::env::var_os("PATH").unwrap_or_default();
            owned.as_os_str()
        }
    };

    for dir in std::env::split_paths(path) {
        if dir.as_os_str().is_empty() {
            continue;
        }
        for candidate in candidates_in(&dir, trimmed) {
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

fn looks_like_path(command: &str) -> bool {
    command.contains('/') || command.contains('\\')
}

#[cfg(windows)]
fn candidates_in(dir: &Path, command: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    // Try the exact name first — if the user typed "claude.exe" we
    // shouldn't tack ".exe.exe" onto it.
    out.push(dir.join(command));
    let has_ext = Path::new(command).extension().is_some();
    if !has_ext {
        for ext in pathext_suffixes() {
            out.push(dir.join(format!("{command}{ext}")));
        }
    }
    out
}

#[cfg(not(windows))]
fn candidates_in(dir: &Path, command: &str) -> Vec<PathBuf> {
    vec![dir.join(command)]
}

#[cfg(windows)]
fn pathext_suffixes() -> Vec<String> {
    std::env::var("PATHEXT")
        .ok()
        .filter(|s| !s.is_empty())
        .map(|raw| {
            raw.split(';')
                .filter(|s| !s.is_empty())
                .map(|s| s.to_ascii_lowercase())
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| {
            vec![
                ".exe".to_string(),
                ".cmd".to_string(),
                ".bat".to_string(),
            ]
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;
    use tempfile::TempDir;

    #[cfg(unix)]
    fn make_exec(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        std::fs::write(path, "#!/bin/sh\nexit 0\n").unwrap();
        let mut perms = std::fs::metadata(path).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(path, perms).unwrap();
    }

    #[cfg(windows)]
    fn make_exec(path: &Path) {
        std::fs::write(path, b"").unwrap();
    }

    #[test]
    fn empty_command_returns_none() {
        assert_eq!(
            detect_command_in_path("", Some(OsStr::new(""))),
            None
        );
        assert_eq!(
            detect_command_in_path("   ", Some(OsStr::new(""))),
            None
        );
    }

    #[test]
    fn missing_command_returns_none() {
        let tmp = TempDir::new().unwrap();
        let path = OsString::from(tmp.path());
        assert_eq!(
            detect_command_in_path("definitely-not-here-xyz", Some(&path)),
            None
        );
    }

    #[test]
    fn finds_executable_on_path() {
        let tmp = TempDir::new().unwrap();
        let exe_name = if cfg!(windows) { "tool.exe" } else { "tool" };
        let exe = tmp.path().join(exe_name);
        make_exec(&exe);
        let path = OsString::from(tmp.path());
        let lookup = if cfg!(windows) { "tool" } else { "tool" };
        assert_eq!(
            detect_command_in_path(lookup, Some(&path)),
            Some(exe)
        );
    }
}
