//! Global skill sync: clone/update a private GitHub skills repo into the
//! per-tool `managed/` skills folder so the skills are available across every
//! project the user opens in that tool.
//!
//! The `managed/` subfolder is owned entirely by the sync — it is hard-reset
//! to the remote tip on every run, so any hand edits there are discarded.
//! Personal skills that live directly under `~/.claude/skills` or
//! `~/.codex/skills` (i.e. NOT under `managed/`) are never touched.

use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::services::command_runner::{self, OutputEvent};

/// The coding tools that expose a global skills folder we can sync into.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkillTool {
    ClaudeCode,
    Codex,
}

impl SkillTool {
    /// The dotfolder under the user's home for this tool (`.claude` / `.codex`).
    fn home_subdir(self) -> &'static str {
        match self {
            SkillTool::ClaudeCode => ".claude",
            SkillTool::Codex => ".codex",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            SkillTool::ClaudeCode => "Claude Code",
            SkillTool::Codex => "Codex",
        }
    }
}

#[derive(Debug, Error)]
pub enum SkillsSyncError {
    #[error("Set a skills repo URL in Settings first.")]
    NoRepoUrl,
    #[error("Set a GitHub token in Settings first.")]
    NoToken,
    #[error("Could not determine your home directory.")]
    NoHomeDir,
    #[error("io error preparing {path:?}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("git exited with code {0}.")]
    GitFailed(i32),
}

/// The managed skills directory for `tool` under `home`, e.g.
/// `<home>/.claude/skills/managed`. Pure — no filesystem access.
pub fn managed_dir(home: &Path, tool: SkillTool) -> PathBuf {
    home.join(tool.home_subdir())
        .join("skills")
        .join("managed")
}

/// The `Authorization` header value git should send, carrying `token` as a
/// GitHub Basic-auth credential. Passed via `-c http.extraHeader=...` so the
/// token never lands in `.git/config` or the remote URL. GitHub accepts any
/// username with the PAT as the password; `x-access-token` matches the header
/// GitHub Actions injects, so fine-grained PATs work.
pub fn auth_header(token: &str) -> String {
    let creds = format!("x-access-token:{token}");
    format!("AUTHORIZATION: basic {}", base64_encode(creds.as_bytes()))
}

/// git args to clone the repo fresh into an empty/missing `dest`.
pub fn clone_args(repo_url: &str, branch: &str, dest: &Path, header: &str) -> Vec<String> {
    vec![
        "-c".into(),
        format!("http.extraHeader={header}"),
        "clone".into(),
        "--depth".into(),
        "1".into(),
        "--single-branch".into(),
        "--branch".into(),
        branch.into(),
        repo_url.into(),
        dest.to_string_lossy().into_owned(),
    ]
}

/// git args (run with cwd = managed dir) to fetch the latest tip of `branch`.
pub fn fetch_args(branch: &str, header: &str) -> Vec<String> {
    vec![
        "-c".into(),
        format!("http.extraHeader={header}"),
        "fetch".into(),
        "--depth".into(),
        "1".into(),
        "origin".into(),
        branch.into(),
    ]
}

/// git args (run with cwd = managed dir) to hard-reset the working tree to the
/// just-fetched tip. `FETCH_HEAD` (not `origin/<branch>`) so it still works if
/// the user changed the configured branch since the clone.
pub fn reset_args() -> Vec<String> {
    vec!["reset".into(), "--hard".into(), "FETCH_HEAD".into()]
}

/// A redacted, user-facing description of the git step — never includes the
/// auth header/token. Shown in the output panel so the user can follow along.
pub fn redacted_summary(repo_url: &str, branch: &str, updating: bool) -> String {
    if updating {
        format!("git fetch + reset --hard ({repo_url} @ {branch})")
    } else {
        format!("git clone --depth 1 --branch {branch} {repo_url}")
    }
}

/// Clone or hard-update the skills repo into `managed_path` for one tool,
/// streaming git output through `on_event`. Returns `Ok(())` on success.
///
/// `git_exe` is the resolved git binary; `home`/`managed_path` are computed by
/// the caller so this stays testable. The token is required and never logged.
pub async fn sync<F>(
    git_exe: &Path,
    repo_url: &str,
    branch: &str,
    token: &str,
    managed_path: &Path,
    mut on_event: F,
) -> Result<(), SkillsSyncError>
where
    F: FnMut(OutputEvent) + Send,
{
    if repo_url.trim().is_empty() {
        return Err(SkillsSyncError::NoRepoUrl);
    }
    if token.trim().is_empty() {
        return Err(SkillsSyncError::NoToken);
    }
    let branch = if branch.trim().is_empty() {
        "main"
    } else {
        branch.trim()
    };
    let header = auth_header(token.trim());
    let is_git_repo = managed_path.join(".git").is_dir();

    on_event(OutputEvent::Stderr {
        line: format!(
            "[bmad] skills sync -> {} ({})",
            managed_path.display(),
            redacted_summary(repo_url.trim(), branch, is_git_repo),
        ),
    });

    let code = if is_git_repo {
        // Hard-update an existing managed clone.
        let fetch = command_runner::run_program(
            git_exe,
            &fetch_args(branch, &header),
            managed_path,
            &mut on_event,
        )
        .await;
        if fetch != 0 {
            on_event(OutputEvent::Exit { code: fetch });
            return Err(SkillsSyncError::GitFailed(fetch));
        }
        command_runner::run_program(git_exe, &reset_args(), managed_path, &mut on_event).await
    } else {
        // Fresh clone. The managed dir is sync-owned: if it exists without a
        // `.git` (leftover/corrupt), remove it so the clone has a clean dest.
        if managed_path.exists() {
            std::fs::remove_dir_all(managed_path).map_err(|source| SkillsSyncError::Io {
                path: managed_path.to_path_buf(),
                source,
            })?;
        }
        if let Some(parent) = managed_path.parent() {
            std::fs::create_dir_all(parent).map_err(|source| SkillsSyncError::Io {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        // Clone runs from the parent so a missing managed dir is fine.
        let cwd = managed_path.parent().unwrap_or(managed_path);
        command_runner::run_program(
            git_exe,
            &clone_args(repo_url.trim(), branch, managed_path, &header),
            cwd,
            &mut on_event,
        )
        .await
    };

    on_event(OutputEvent::Exit { code });
    if code == 0 {
        Ok(())
    } else {
        Err(SkillsSyncError::GitFailed(code))
    }
}

/// Minimal standard-base64 encoder (no external crate). Kept private; only
/// `auth_header` needs it.
fn base64_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((n >> 18) & 63) as usize] as char);
        out.push(TABLE[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_dir_is_under_tool_skills_managed() {
        let home = Path::new("/home/me");
        assert_eq!(
            managed_dir(home, SkillTool::ClaudeCode),
            Path::new("/home/me/.claude/skills/managed")
        );
        assert_eq!(
            managed_dir(home, SkillTool::Codex),
            Path::new("/home/me/.codex/skills/managed")
        );
    }

    #[test]
    fn base64_matches_known_vectors() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn auth_header_is_basic_x_access_token() {
        // base64("x-access-token:ghp_secret")
        let h = auth_header("ghp_secret");
        assert!(h.starts_with("AUTHORIZATION: basic "));
        let b64 = h.trim_start_matches("AUTHORIZATION: basic ");
        assert_eq!(b64, "eC1hY2Nlc3MtdG9rZW46Z2hwX3NlY3JldA==");
    }

    #[test]
    fn auth_header_never_contains_the_raw_token() {
        let h = auth_header("ghp_supersecretvalue");
        assert!(!h.contains("ghp_supersecretvalue"));
    }

    #[test]
    fn clone_args_are_shallow_single_branch_with_header() {
        let args = clone_args(
            "https://github.com/acme/skills",
            "main",
            Path::new("/home/me/.claude/skills/managed"),
            "AUTHORIZATION: basic ABC",
        );
        assert_eq!(args[0], "-c");
        assert_eq!(args[1], "http.extraHeader=AUTHORIZATION: basic ABC");
        assert!(args.contains(&"clone".to_string()));
        assert!(args.contains(&"--depth".to_string()));
        assert!(args.contains(&"--single-branch".to_string()));
        // branch follows --branch
        let i = args.iter().position(|a| a == "--branch").unwrap();
        assert_eq!(args[i + 1], "main");
        // url then dest are the final two args
        assert_eq!(args[args.len() - 2], "https://github.com/acme/skills");
        assert_eq!(args[args.len() - 1], "/home/me/.claude/skills/managed");
    }

    #[test]
    fn fetch_then_reset_targets_fetch_head() {
        let fetch = fetch_args("release", "AUTHORIZATION: basic X");
        assert_eq!(fetch[0], "-c");
        assert!(fetch.contains(&"fetch".to_string()));
        assert_eq!(fetch[fetch.len() - 1], "release");
        assert_eq!(reset_args(), vec!["reset", "--hard", "FETCH_HEAD"]);
    }

    #[test]
    fn redacted_summary_never_leaks_tokenish_detail() {
        let clone = redacted_summary("https://github.com/acme/skills", "main", false);
        assert!(clone.contains("clone"));
        assert!(clone.contains("main"));
        let update = redacted_summary("https://github.com/acme/skills", "main", true);
        assert!(update.contains("fetch"));
    }
}
