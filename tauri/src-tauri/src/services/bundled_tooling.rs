//! Bundled tooling discovery and one-time npm-cache seeding.
//!
//! Stage 3 of issue #25 bakes a portable Node.js and PortableGit into the
//! NSIS installer, plus a pre-warmed `bmad-method` npm cache. This module
//! is the runtime side of that work:
//!
//! - `detect()` runs `--version` against the bundled binaries so the
//!   Settings dialog can show the user what they're actually running.
//! - `seed_user_npm_cache()` copies the bundled npm cache into the user's
//!   writable `%LOCALAPPDATA%` location on first launch, so the first
//!   `npx bmad-method install` works even on a flaky network.
//!
//! The detection helpers are written against a `Path`, so the BDD harness
//! can exercise them with stub binaries without needing a real Node/Git
//! install on the build machine.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;

use crate::platform;

/// Per-binary view of what Stage 3 bundles. `None` for a version means
/// the bundled binary either isn't present (dev builds before CI populates
/// `resources/`) or failed to report a version — in either case the UI
/// renders it as "not bundled" so the user knows they're falling back to
/// whatever's on PATH.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundledTooling {
    pub node_version: Option<String>,
    pub git_version: Option<String>,
}

/// Resolve the bundled Node and Git binaries via the platform module,
/// run `--version` on each, and return the trimmed first line of stdout.
pub fn detect() -> BundledTooling {
    let node_path = platform::resolve_node_path();
    let git_path = platform::resolve_git_path();
    BundledTooling {
        node_version: detect_version(&node_path, &["--version"]),
        git_version: detect_version(&git_path, &["--version"]),
    }
}

/// Run `binary args...` and return the first non-empty line of stdout,
/// or `None` if the binary doesn't exist, fails to spawn, exits with a
/// non-zero code, or prints nothing. Trims whitespace and CR off the
/// returned line so a Windows `\r\n` stub doesn't leak into the UI.
pub fn detect_version(binary: &Path, args: &[&str]) -> Option<String> {
    if !binary.exists() {
        return None;
    }
    let mut cmd = Command::new(binary);
    cmd.args(args);
    // Suppress the console-window flash on Windows when the parent is a
    // Tauri GUI app (the Settings dialog runs these `--version` probes on
    // mount). See command_runner.rs for the rationale.
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }
    let output = cmd.output().ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    stdout
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(str::to_owned)
}

/// One-time copy of the bundled npm cache into the user-writable cache
/// directory. Returns `Ok(true)` if the seed happened, `Ok(false)` if the
/// user cache already had content or the bundled cache was missing.
/// Errors only on I/O failures during the copy itself.
pub fn seed_user_npm_cache(bundled: &Path, user: &Path) -> io::Result<bool> {
    if user_cache_already_populated(user)? {
        return Ok(false);
    }
    if !bundled.exists() {
        return Ok(false);
    }
    fs::create_dir_all(user)?;
    copy_dir_recursive(bundled, user)?;
    Ok(true)
}

/// Best-effort variant used by the Tauri `.setup()` hook so a failed seed
/// doesn't keep the app from launching. The detailed result is logged to
/// stderr so a developer running `cargo tauri dev` can still see what
/// went wrong.
pub fn seed_user_npm_cache_best_effort() {
    let bundled = match platform::resolve_bundled_npm_cache_path() {
        Some(p) => p,
        None => return,
    };
    let user = platform::user_npm_cache_dir();
    match seed_user_npm_cache(&bundled, &user) {
        Ok(true) => eprintln!(
            "[bmad-manager] seeded npm cache from {} into {}",
            bundled.display(),
            user.display()
        ),
        Ok(false) => {}
        Err(err) => eprintln!(
            "[bmad-manager] npm cache seed failed ({}): {err}",
            user.display()
        ),
    }
}

/// Dump the resolved bundled-tool paths and whether each one exists.
/// Called once at startup so a misconfigured `bundle.resources` shows
/// up in the app's stderr stream (visible in Event Viewer / a console
/// when launched from the terminal) without a debugger.
pub fn log_resolved_paths() {
    let node = platform::resolve_node_path();
    let npx = platform::resolve_npx_path();
    let git = platform::resolve_git_path();
    let cache = platform::resolve_bundled_npm_cache_path();
    eprintln!(
        "[bmad-manager] resolved node={} (exists={}), npx={} (exists={}), git={} (exists={}), bundled-npm-cache={}",
        node.display(),
        node.exists(),
        npx.display(),
        npx.exists(),
        git.display(),
        git.exists(),
        cache
            .map(|p| format!("{} (exists={})", p.display(), p.exists()))
            .unwrap_or_else(|| "<unresolved>".to_string()),
    );
}

fn user_cache_already_populated(user: &Path) -> io::Result<bool> {
    if !user.exists() {
        return Ok(false);
    }
    let mut entries = fs::read_dir(user)?;
    Ok(entries.next().is_some())
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_recursive(&from, &to)?;
        } else {
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

// Re-export the helper users of this module commonly need.
pub fn user_npm_cache_dir() -> PathBuf {
    platform::user_npm_cache_dir()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn detect_version_returns_none_for_missing_binary() {
        let tmp = TempDir::new().unwrap();
        let phantom = tmp.path().join("nope");
        assert!(detect_version(&phantom, &["--version"]).is_none());
    }

    #[test]
    fn seed_copies_when_user_cache_empty() {
        let tmp = TempDir::new().unwrap();
        let bundled = tmp.path().join("bundled");
        let user = tmp.path().join("user");
        fs::create_dir_all(bundled.join("sub")).unwrap();
        fs::write(bundled.join("sub").join("a.txt"), b"hello").unwrap();
        let copied = seed_user_npm_cache(&bundled, &user).unwrap();
        assert!(copied);
        assert!(user.join("sub").join("a.txt").exists());
    }

    #[test]
    fn seed_skips_when_user_cache_already_populated() {
        let tmp = TempDir::new().unwrap();
        let bundled = tmp.path().join("bundled");
        let user = tmp.path().join("user");
        fs::create_dir_all(&bundled).unwrap();
        fs::write(bundled.join("from-bundled.txt"), b"new").unwrap();
        fs::create_dir_all(&user).unwrap();
        fs::write(user.join("from-user.txt"), b"old").unwrap();
        let copied = seed_user_npm_cache(&bundled, &user).unwrap();
        assert!(!copied);
        assert!(user.join("from-user.txt").exists());
        assert!(!user.join("from-bundled.txt").exists());
    }

    #[test]
    fn seed_is_noop_when_bundled_cache_missing() {
        let tmp = TempDir::new().unwrap();
        let bundled = tmp.path().join("missing");
        let user = tmp.path().join("user");
        let copied = seed_user_npm_cache(&bundled, &user).unwrap();
        assert!(!copied);
    }
}
