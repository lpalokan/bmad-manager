use std::path::{Path, PathBuf};
use std::process::Command;

use thiserror::Error;

use crate::services::module_manifest;

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
///
/// On failure, the captured stdout + stderr from the git process are
/// inlined into the returned error so the caller can surface them in
/// the output panel — otherwise a clone failure looks like an opaque
/// "git clone failed" line in the UI.
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

    let mut cmd = Command::new(git_exe);
    cmd.args(&args);

    // Match command_runner: suppress the console window flash on
    // Windows when the parent is a Tauri GUI app. See command_runner.rs
    // for the rationale.
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }

    let output = cmd
        .output()
        .map_err(|e| GitError::GitNotAvailable(e.to_string()))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let code = output.status.code().unwrap_or(-1);
        let _ = std::fs::remove_dir_all(dest);
        let mut message = format!("exit {code}");
        if !stderr.is_empty() {
            message.push_str("\nstderr: ");
            message.push_str(&stderr);
        }
        if !stdout.is_empty() {
            message.push_str("\nstdout: ");
            message.push_str(&stdout);
        }
        return Err(GitError::CloneFailed(message));
    }
    Ok(())
}

/// The value to hand `bmad-method --custom-source` for a GitHub-repo source.
///
/// With an explicit `git_ref` it is `<url>@<ref>` (the installer pins that
/// branch/tag and records it as the module version). With no ref the configured
/// URL carries no version, so we resolve the repo's **latest semver tag** and
/// pin to it — a bare URL otherwise makes the installer stamp the literal
/// `"main"`. Falls back to the bare URL when no semver tag can be discovered
/// (offline, git missing, or a repo without version tags).
///
/// Mirrors the Swift `GitRepoModuleSource.installerSource`.
pub fn git_installer_source(git_exe: &Path, url: &str, git_ref: &str) -> String {
    let trimmed_ref = git_ref.trim();
    if !trimmed_ref.is_empty() {
        return pinned_url(url, trimmed_ref);
    }
    if let Some(output) = ls_remote_tags(git_exe, url) {
        if let Some(tag) = latest_semver_tag(&output) {
            return pinned_url(url, &tag);
        }
    }
    base_url(url).to_string()
}

/// `<url>@<ref>` with any trailing slash on the URL stripped first. The
/// `bmad-method` source parser reads the `@<ref>` suffix as the version to pin.
pub fn pinned_url(url: &str, git_ref: &str) -> String {
    format!("{}@{}", base_url(url), git_ref.trim())
}

/// Highest semver-shaped tag name (original form, e.g. `v2.0.2`) parsed from
/// `git ls-remote --tags --refs` output, or `None` when none qualify.
pub fn latest_semver_tag(ls_remote_output: &str) -> Option<String> {
    let mut best: Option<String> = None;
    for line in ls_remote_output.lines() {
        // Each line is "<sha>\trefs/tags/<name>" (--refs drops peeled tags).
        let Some((_, refname)) = line.split_once('\t') else {
            continue;
        };
        let Some(tag) = refname.strip_prefix("refs/tags/") else {
            continue;
        };
        let tag = tag.trim();
        if !is_semver_shaped(tag) {
            continue;
        }
        match &best {
            Some(current) if !module_manifest::is_older(current, tag) => {}
            _ => best = Some(tag.to_string()),
        }
    }
    best
}

fn base_url(url: &str) -> &str {
    url.trim().trim_end_matches('/')
}

/// A tag counts as a version only if, after dropping a leading `v`/`V`, it has
/// at least one dot-separated numeric component (so `latest`, `nightly` and
/// similar non-version tags are ignored).
fn is_semver_shaped(tag: &str) -> bool {
    let stripped = tag
        .strip_prefix('v')
        .or_else(|| tag.strip_prefix('V'))
        .unwrap_or(tag);
    !stripped.is_empty() && stripped.split('.').any(|c| c.parse::<u64>().is_ok())
}

/// Runs `git ls-remote --tags --refs <url>` and returns stdout, or `None` on
/// any failure (offline, git missing, non-zero exit).
fn ls_remote_tags(git_exe: &Path, url: &str) -> Option<String> {
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut cmd = Command::new(git_exe);
    cmd.args(["ls-remote", "--tags", "--refs", trimmed]);
    cmd.env("GIT_TERMINAL_PROMPT", "0");

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }

    let output = cmd.output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).into_owned())
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

    fn ls_remote(tags: &[&str]) -> String {
        tags.iter()
            .map(|t| format!("{}\trefs/tags/{t}", "a".repeat(40)))
            .collect::<Vec<_>>()
            .join("\n")
            + "\n"
    }

    #[test]
    fn pinned_url_appends_ref() {
        assert_eq!(
            pinned_url("https://github.com/o/r", "v1.2.3"),
            "https://github.com/o/r@v1.2.3"
        );
    }

    #[test]
    fn pinned_url_strips_trailing_slash() {
        assert_eq!(
            pinned_url("https://github.com/o/r/", " main "),
            "https://github.com/o/r@main"
        );
    }

    #[test]
    fn latest_semver_tag_picks_highest() {
        let out = ls_remote(&["v1.0.1", "v1.0.2", "v1.0.3", "v2.0.2"]);
        assert_eq!(latest_semver_tag(&out), Some("v2.0.2".to_string()));
    }

    #[test]
    fn latest_semver_tag_ignores_non_semver() {
        let out = ls_remote(&["latest", "nightly", "v1.4.0", "release"]);
        assert_eq!(latest_semver_tag(&out), Some("v1.4.0".to_string()));
    }

    #[test]
    fn latest_semver_tag_none_when_no_versions() {
        let out = ls_remote(&["latest", "nightly"]);
        assert_eq!(latest_semver_tag(&out), None);
    }
}
