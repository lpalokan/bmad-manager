use std::path::{Path, PathBuf};
use std::process::Command;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum GitError {
    #[error("No GitHub repository URL is configured.")]
    NoRepoUrlConfigured,
    #[error("git is not available: {0}")]
    GitNotAvailable(String),
    #[error("git clone failed: {0}")]
    CloneFailed(String),
}

/// Materialises the module by shallow-cloning `url` (optionally pinning
/// to `git_ref`) into a fresh temp directory. The clone root *is* the
/// module root — no wrapper descent needed (unlike GitHub "Download ZIP"
/// archives). `git_exe` is the absolute path to the git binary to invoke;
/// Windows passes the bundled PortableGit's `cmd/git.exe`, macOS will
/// pass the system git when the unification milestone lands.
pub fn clone(git_exe: &Path, url: &str, git_ref: &str, dest: &Path) -> Result<(), GitError> {
    let trimmed_url = url.trim();
    if trimmed_url.is_empty() {
        return Err(GitError::NoRepoUrlConfigured);
    }
    let trimmed_ref = git_ref.trim();

    let mut args: Vec<String> = vec!["clone".to_string(), "--depth".to_string(), "1".to_string()];
    if !trimmed_ref.is_empty() {
        args.push("--branch".to_string());
        args.push(trimmed_ref.to_string());
    }
    args.push(trimmed_url.to_string());
    args.push(dest.to_string_lossy().into_owned());

    let output = Command::new(git_exe)
        .args(&args)
        .output()
        .map_err(|e| GitError::GitNotAvailable(e.to_string()))?;

    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let _ = std::fs::remove_dir_all(dest);
        return Err(GitError::CloneFailed(if message.is_empty() {
            "unknown error".to_string()
        } else {
            message
        }));
    }
    Ok(())
}

/// Convenience: produce a fresh temp-dir path the caller can pass to
/// [`clone`]. Mirrors the Swift `GitRepoModuleSource.withModuleRoot`
/// helper's path layout so test fixtures and log snippets are familiar.
pub fn fresh_tempdir() -> PathBuf {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("bmad-manager-{nanos:032x}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_url() {
        let tmp = std::env::temp_dir().join("bmad-manager-git-test");
        let err = clone(Path::new("/usr/bin/git"), "  ", "", &tmp).unwrap_err();
        assert!(matches!(err, GitError::NoRepoUrlConfigured));
    }

    #[test]
    fn surfaces_git_not_available() {
        let tmp = std::env::temp_dir().join("bmad-manager-git-test-missing");
        let err = clone(
            Path::new("/does/not/exist/git-binary"),
            "https://example.invalid/repo.git",
            "",
            &tmp,
        )
        .unwrap_err();
        assert!(matches!(err, GitError::GitNotAvailable(_)));
    }
}
