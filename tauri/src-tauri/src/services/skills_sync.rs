//! Global skill sync: clone/update a private GitHub skills repo and expose its
//! skills to a coding tool by **linking each skill as a direct child** of the
//! tool's skills folder.
//!
//! Why links: Claude Code and Codex only discover skills one level deep —
//! `~/.claude/skills/<name>/SKILL.md`. A skill buried under a `managed/`
//! subfolder is never found. So we clone the repo into a hidden sibling
//! (`~/.claude/skills-managed/`, which the tools don't scan) and create a
//! junction (Windows) / symlink (macOS) at `~/.claude/skills/<name>` pointing
//! at each skill in the clone.
//!
//! Safety: we only ever create/remove links we own (tracked in a manifest);
//! a name already taken by a **real** personal skill directory is skipped, not
//! overwritten. Personal skills are never touched.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
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
    #[error("io error on {path:?}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("git exited with code {0}.")]
    GitFailed(i32),
}

fn io_err(path: &Path, source: std::io::Error) -> SkillsSyncError {
    SkillsSyncError::Io {
        path: path.to_path_buf(),
        source,
    }
}

// --- Paths -----------------------------------------------------------------

/// The tool's skills folder that it actually scans, e.g.
/// `<home>/.claude/skills`. Pure.
pub fn skills_root(home: &Path, tool: SkillTool) -> PathBuf {
    home.join(tool.home_subdir()).join("skills")
}

/// Hidden sibling holding the cloned repo, e.g. `<home>/.claude/skills-managed`.
/// Not scanned by the tool. Pure.
pub fn managed_repo_dir(home: &Path, tool: SkillTool) -> PathBuf {
    home.join(tool.home_subdir()).join("skills-managed")
}

/// Manifest recording the link names we created (so re-syncs clean up only our
/// own links). Lives outside both `skills/` and the git clone. Pure.
pub fn links_manifest_path(home: &Path, tool: SkillTool) -> PathBuf {
    home.join(tool.home_subdir()).join(".bmad-skill-links.json")
}

/// The pre-link layout this feature shipped with first (a buried clone under
/// `skills/managed`), cleaned up on the next sync. Pure.
fn legacy_managed_dir(home: &Path, tool: SkillTool) -> PathBuf {
    skills_root(home, tool).join("managed")
}

// --- Git arguments (pure) --------------------------------------------------

/// The `Authorization` header git should send, carrying `token` as a GitHub
/// Basic-auth credential. Passed via `-c http.extraHeader=...` so the token
/// never lands in `.git/config` or the remote URL.
pub fn auth_header(token: &str) -> String {
    let creds = format!("x-access-token:{token}");
    format!("AUTHORIZATION: basic {}", base64_encode(creds.as_bytes()))
}

/// git args to clone the repo fresh into `dest`.
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

/// git args (run with cwd = clone dir) to fetch the latest tip of `branch`.
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

/// git args (run with cwd = clone dir) to hard-reset to the just-fetched tip.
pub fn reset_args() -> Vec<String> {
    vec!["reset".into(), "--hard".into(), "FETCH_HEAD".into()]
}

/// A redacted, user-facing description of the git step — never the token.
pub fn redacted_summary(repo_url: &str, branch: &str, updating: bool) -> String {
    if updating {
        format!("git fetch + reset --hard ({repo_url} @ {branch})")
    } else {
        format!("git clone --depth 1 --branch {branch} {repo_url}")
    }
}

// --- Skill discovery & link reconciliation ---------------------------------

/// Where skills live inside the cloned repo: the top-level `skills/` folder
/// when present (the layout shared with the sibling `context/` folder), else
/// the repo root — backward-compatible with repos that keep skills directly
/// at the top level. Pure.
pub fn skills_source_dir(repo: &Path) -> PathBuf {
    let sub = repo.join("skills");
    if sub.is_dir() {
        sub
    } else {
        repo.to_path_buf()
    }
}

/// Immediate child directories of `repo` that contain a `SKILL.md`, sorted.
/// Dotfolders (incl. `.git`) are ignored. Pure (reads the filesystem).
pub fn discover_skills(repo: &Path) -> Vec<String> {
    let mut names = Vec::new();
    if let Ok(entries) = std::fs::read_dir(repo) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let path = entry.path();
            if path.is_dir() && path.join("SKILL.md").is_file() {
                names.push(name);
            }
        }
    }
    names.sort();
    names
}

/// What a reconcile did, for the output panel.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct LinkSummary {
    pub linked: Vec<String>,
    pub removed: Vec<String>,
    pub skipped: Vec<String>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct LinkManifest {
    links: Vec<String>,
}

fn read_manifest(path: &Path) -> Vec<String> {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str::<LinkManifest>(&s).ok())
        .map(|m| m.links)
        .unwrap_or_default()
}

fn write_manifest(path: &Path, links: &[String]) -> Result<(), SkillsSyncError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| io_err(parent, e))?;
    }
    let json = serde_json::to_string_pretty(&LinkManifest {
        links: links.to_vec(),
    })
    .map_err(|e| io_err(path, std::io::Error::other(e)))?;
    std::fs::write(path, json).map_err(|e| io_err(path, e))
}

/// True if `p` exists and is a link/junction (reparse point on Windows, symlink
/// on Unix) rather than a real directory. `is_symlink()` misreports Windows
/// junctions, so we test the reparse-point attribute directly. `pub(crate)` so
/// the contribution flow can tell personal skills (real dirs) from managed
/// links.
pub(crate) fn is_link(p: &Path) -> bool {
    match std::fs::symlink_metadata(p) {
        Ok(md) => {
            #[cfg(windows)]
            {
                use std::os::windows::fs::MetadataExt;
                const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
                md.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
            }
            #[cfg(not(windows))]
            {
                md.file_type().is_symlink()
            }
        }
        Err(_) => false,
    }
}

#[cfg(windows)]
fn create_link(link: &Path, target: &Path) -> std::io::Result<()> {
    use std::os::windows::process::CommandExt;
    // Junctions (mklink /J) need no special privilege, unlike symlinks. They're
    // filesystem-transparent, so the tool reads `<link>/SKILL.md` normally.
    let out = std::process::Command::new("cmd")
        .args(["/C", "mklink", "/J"])
        .arg(link)
        .arg(target)
        .creation_flags(0x0800_0000)
        .output()?;
    if out.status.success() {
        Ok(())
    } else {
        Err(std::io::Error::other(
            String::from_utf8_lossy(&out.stderr).trim().to_string(),
        ))
    }
}

#[cfg(not(windows))]
fn create_link(link: &Path, target: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

/// Removes a link/junction without touching its target. Tries `remove_file`
/// (Unix symlink) then `remove_dir` (Windows junction / dir symlink).
fn remove_link(link: &Path) -> std::io::Result<()> {
    match std::fs::remove_file(link) {
        Ok(()) => Ok(()),
        Err(_) => std::fs::remove_dir(link),
    }
}

/// Brings `skills_root` in sync with the skills in `managed_repo`: removes the
/// links we made last time, then links every current skill — skipping any name
/// occupied by a real personal skill. Records what we own in `manifest_path`.
pub fn reconcile_links(
    skills_root: &Path,
    managed_repo: &Path,
    manifest_path: &Path,
) -> Result<LinkSummary, SkillsSyncError> {
    std::fs::create_dir_all(skills_root).map_err(|e| io_err(skills_root, e))?;

    let source = skills_source_dir(managed_repo);
    let previous = read_manifest(manifest_path);
    let repo_skills = discover_skills(&source);

    // Remove every link we created on the last sync (clean slate). Only touch
    // entries that are actually links — never a real dir the user may have put
    // in our link's place.
    for name in &previous {
        let link = skills_root.join(name);
        if is_link(&link) {
            let _ = remove_link(&link);
        }
    }
    let removed: Vec<String> = previous
        .iter()
        .filter(|n| !repo_skills.contains(*n))
        .cloned()
        .collect();

    let mut linked = Vec::new();
    let mut skipped = Vec::new();
    for name in &repo_skills {
        let link = skills_root.join(name);
        if std::fs::symlink_metadata(&link).is_ok() {
            // Still occupied after clearing our own links. If it's a dangling
            // link with no real skill behind it (e.g. a leftover from the old
            // buried layout), reclaim it; otherwise it's a personal skill —
            // leave it untouched.
            if is_link(&link) && !link.join("SKILL.md").is_file() {
                let _ = remove_link(&link);
            } else {
                skipped.push(name.clone());
                continue;
            }
        }
        create_link(&link, &source.join(name)).map_err(|e| io_err(&link, e))?;
        linked.push(name.clone());
    }

    write_manifest(manifest_path, &linked)?;
    Ok(LinkSummary {
        linked,
        removed,
        skipped,
    })
}

// --- Orchestration ---------------------------------------------------------

/// Clone or hard-update the skills repo for one tool, then link its skills into
/// the tool's skills folder. Streams git output through `on_event`.
pub async fn sync<F>(
    git_exe: &Path,
    repo_url: &str,
    branch: &str,
    token: &str,
    home: &Path,
    tool: SkillTool,
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
    let repo_url = repo_url.trim();
    let header = auth_header(token.trim());

    let managed_repo = managed_repo_dir(home, tool);
    let skills = skills_root(home, tool);
    let manifest = links_manifest_path(home, tool);
    let is_repo = managed_repo.join(".git").is_dir();

    on_event(OutputEvent::Stderr {
        line: format!(
            "[bmad] skills sync ({}) -> {} ({})",
            tool.display_name(),
            managed_repo.display(),
            redacted_summary(repo_url, branch, is_repo),
        ),
    });

    // 1. Clone or hard-update the hidden repo.
    let code = if is_repo {
        let fetch = command_runner::run_program(
            git_exe,
            &fetch_args(branch, &header),
            &managed_repo,
            &mut on_event,
        )
        .await;
        if fetch != 0 {
            on_event(OutputEvent::Exit { code: fetch });
            return Err(SkillsSyncError::GitFailed(fetch));
        }
        command_runner::run_program(git_exe, &reset_args(), &managed_repo, &mut on_event).await
    } else {
        if managed_repo.exists() {
            std::fs::remove_dir_all(&managed_repo).map_err(|e| io_err(&managed_repo, e))?;
        }
        if let Some(parent) = managed_repo.parent() {
            std::fs::create_dir_all(parent).map_err(|e| io_err(parent, e))?;
        }
        let cwd = managed_repo.parent().unwrap_or(&managed_repo);
        command_runner::run_program(
            git_exe,
            &clone_args(repo_url, branch, &managed_repo, &header),
            cwd,
            &mut on_event,
        )
        .await
    };
    if code != 0 {
        on_event(OutputEvent::Exit { code });
        return Err(SkillsSyncError::GitFailed(code));
    }

    // 2. Clean up the old buried-clone layout if present (links into it become
    //    dangling and are reclaimed by reconcile_links).
    let legacy = legacy_managed_dir(home, tool);
    if legacy.exists() {
        let _ = std::fs::remove_dir_all(&legacy);
    }

    // 3. Link the skills into the tool's skills folder.
    let summary = reconcile_links(&skills, &managed_repo, &manifest)?;
    on_event(OutputEvent::Stderr {
        line: format!(
            "[bmad] linked {} skill(s){}{}",
            summary.linked.len(),
            if summary.removed.is_empty() {
                String::new()
            } else {
                format!(", removed {} stale", summary.removed.len())
            },
            if summary.skipped.is_empty() {
                String::new()
            } else {
                format!(
                    ", skipped {} (a personal skill of that name exists): {}",
                    summary.skipped.len(),
                    summary.skipped.join(", ")
                )
            },
        ),
    });

    on_event(OutputEvent::Exit { code: 0 });
    Ok(())
}

/// Minimal standard-base64 encoder (no external crate). Used by `auth_header`
/// and the contribution flow (encoding blob contents for the GitHub API).
pub(crate) fn base64_encode(input: &[u8]) -> String {
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
    use tempfile::TempDir;

    fn make_skill(repo: &Path, name: &str) {
        let dir = repo.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), format!("# {name}")).unwrap();
    }

    #[test]
    fn paths_resolve_under_the_right_dotfolders() {
        let home = Path::new("/home/me");
        assert_eq!(
            skills_root(home, SkillTool::ClaudeCode),
            Path::new("/home/me/.claude/skills")
        );
        assert_eq!(
            managed_repo_dir(home, SkillTool::Codex),
            Path::new("/home/me/.codex/skills-managed")
        );
    }

    #[test]
    fn base64_matches_known_vectors() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn auth_header_is_basic_x_access_token_without_raw_token() {
        let h = auth_header("ghp_secret");
        assert_eq!(
            h,
            "AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46Z2hwX3NlY3JldA=="
        );
        assert!(!auth_header("ghp_supersecret").contains("ghp_supersecret"));
    }

    #[test]
    fn clone_args_are_shallow_single_branch_with_header() {
        let args = clone_args(
            "https://github.com/acme/skills",
            "main",
            Path::new("/home/me/.claude/skills-managed"),
            "AUTHORIZATION: basic ABC",
        );
        assert_eq!(args[0], "-c");
        assert_eq!(args[1], "http.extraHeader=AUTHORIZATION: basic ABC");
        assert!(args.contains(&"--single-branch".to_string()));
        assert_eq!(args[args.len() - 2], "https://github.com/acme/skills");
        assert_eq!(args[args.len() - 1], "/home/me/.claude/skills-managed");
    }

    #[test]
    fn fetch_then_reset_targets_fetch_head() {
        assert_eq!(fetch_args("release", "h")[0], "-c");
        assert_eq!(reset_args(), vec!["reset", "--hard", "FETCH_HEAD"]);
    }

    #[test]
    fn discover_skills_finds_only_skill_dirs() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        make_skill(repo, "alpha");
        make_skill(repo, "beta");
        std::fs::create_dir_all(repo.join(".git/objects")).unwrap();
        std::fs::create_dir_all(repo.join("not-a-skill")).unwrap(); // no SKILL.md
        std::fs::write(repo.join("README.md"), "x").unwrap();
        assert_eq!(discover_skills(repo), vec!["alpha", "beta"]);
    }

    #[test]
    fn skills_source_dir_prefers_the_skills_subfolder() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        make_skill(&repo.join("skills"), "alpha");
        assert_eq!(skills_source_dir(repo), repo.join("skills"));
    }

    #[test]
    fn skills_source_dir_falls_back_to_repo_root() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        make_skill(repo, "alpha");
        assert_eq!(skills_source_dir(repo), repo);
    }

    #[test]
    fn reconcile_links_discovers_skills_under_the_skills_subfolder() {
        let tmp = TempDir::new().unwrap();
        let skills = tmp.path().join("skills");
        let repo = tmp.path().join("skills-managed");
        let manifest = tmp.path().join("links.json");
        // New layout: skills under <repo>/skills, contexts under <repo>/context.
        make_skill(&repo.join("skills"), "alpha");
        make_skill(&repo.join("skills"), "beta");
        std::fs::create_dir_all(repo.join("context/acme")).unwrap();

        let summary = reconcile_links(&skills, &repo, &manifest).unwrap();
        assert_eq!(summary.linked, vec!["alpha", "beta"]);
        assert!(skills.join("alpha/SKILL.md").is_file());
    }

    #[test]
    fn reconcile_links_creates_links_for_each_skill() {
        let tmp = TempDir::new().unwrap();
        let skills = tmp.path().join("skills");
        let repo = tmp.path().join("skills-managed");
        let manifest = tmp.path().join("links.json");
        make_skill(&repo, "alpha");
        make_skill(&repo, "beta");

        let summary = reconcile_links(&skills, &repo, &manifest).unwrap();
        assert_eq!(summary.linked, vec!["alpha", "beta"]);
        // Each link resolves to the skill's SKILL.md.
        assert!(skills.join("alpha/SKILL.md").is_file());
        assert!(skills.join("beta/SKILL.md").is_file());
        assert!(is_link(&skills.join("alpha")));
        // Manifest persisted.
        assert_eq!(read_manifest(&manifest), vec!["alpha", "beta"]);
    }

    #[test]
    fn reconcile_links_skips_personal_skill_with_same_name() {
        let tmp = TempDir::new().unwrap();
        let skills = tmp.path().join("skills");
        let repo = tmp.path().join("skills-managed");
        let manifest = tmp.path().join("links.json");
        // A real personal skill named "alpha".
        std::fs::create_dir_all(skills.join("alpha")).unwrap();
        std::fs::write(skills.join("alpha/SKILL.md"), "personal").unwrap();
        make_skill(&repo, "alpha");
        make_skill(&repo, "beta");

        let summary = reconcile_links(&skills, &repo, &manifest).unwrap();
        assert_eq!(summary.skipped, vec!["alpha"]);
        assert_eq!(summary.linked, vec!["beta"]);
        // Personal alpha untouched (still a real dir, not a link).
        assert!(!is_link(&skills.join("alpha")));
        assert_eq!(
            std::fs::read_to_string(skills.join("alpha/SKILL.md")).unwrap(),
            "personal"
        );
    }

    #[test]
    fn reconcile_links_removes_stale_managed_links() {
        let tmp = TempDir::new().unwrap();
        let skills = tmp.path().join("skills");
        let repo = tmp.path().join("skills-managed");
        let manifest = tmp.path().join("links.json");

        // First sync: alpha + beta.
        make_skill(&repo, "alpha");
        make_skill(&repo, "beta");
        reconcile_links(&skills, &repo, &manifest).unwrap();
        assert!(skills.join("beta").exists());

        // beta removed from the repo; second sync should unlink it.
        std::fs::remove_dir_all(repo.join("beta")).unwrap();
        let summary = reconcile_links(&skills, &repo, &manifest).unwrap();
        assert_eq!(summary.linked, vec!["alpha"]);
        assert!(summary.removed.contains(&"beta".to_string()));
        assert!(std::fs::symlink_metadata(skills.join("beta")).is_err());
    }
}
