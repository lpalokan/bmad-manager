//! Propose additions (personal skills + project contexts) to the shared repo
//! as a pull request.
//!
//! The model is additions-only on branches in the one repo: gather selected
//! files, create a single commit on a fresh branch off the default branch, and
//! open a PR. We never modify `main` directly (the repo's branch ruleset
//! enforces that) and we block additions whose target folder already exists.
//!
//! All GitHub I/O goes through `GitHubClient` so the choreography is testable
//! with a fake. Pure helpers (URL parsing, enumeration, payload assembly, name
//! sanitisation) carry the bulk of the logic and the bulk of the tests.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::services::github_client::{GitHubClient, GitHubError, PullResult, TreeEntry};
use crate::services::skills_sync::{self, base64_encode, SkillTool};

/// Files larger than this are refused — skills/contexts are text-ish; a big
/// blob is almost certainly a mistake (or a secret) we don't want in the repo.
const MAX_FILE_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ContributionError {
    #[error("Set a skills repo URL in Settings first.")]
    NoRepoUrl,
    #[error("The skills repo URL is not a github.com repository: {0}")]
    BadRepoUrl(String),
    #[error("Set a contributor GitHub token in Settings first.")]
    NoToken,
    #[error("Select at least one skill or context to contribute.")]
    NothingSelected,
    #[error("'{0}' is not a valid name for a repo folder.")]
    InvalidName(String),
    #[error("Skill '{0}' has no SKILL.md.")]
    SkillMissingManifest(String),
    #[error("'{name}' has no recognized context files to contribute.")]
    EmptyContext { name: String },
    #[error("'{path}' is {size} bytes, over the {max} byte limit.")]
    FileTooLarge { path: String, size: u64, max: u64 },
    #[error("reading '{path}' failed: {reason}")]
    Read { path: String, reason: String },
    #[error(
        "'{kind}/{name}' already exists in the repo — choose a different name (additions only)."
    )]
    Collision { kind: String, name: String },
    #[error(transparent)]
    GitHub(#[from] GitHubError),
}

/// A personal skill the user can offer (a real skill folder they authored, not
/// a managed/linked one).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributableSkill {
    pub name: String,
    pub directory: PathBuf,
    /// Which tool's folder it was found in (for display: "Claude Code"/"Codex").
    pub tool: String,
}

/// A selected skill to contribute.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillSelection {
    pub name: String,
    pub directory: PathBuf,
}

/// A selected context to contribute, with the (possibly edited) target folder
/// name it should land under in `context/`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextSelection {
    pub target_name: String,
    pub directory: PathBuf,
    pub files: Vec<String>,
}

/// The submission payload from the UI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionRequest {
    #[serde(default)]
    pub skills: Vec<SkillSelection>,
    #[serde(default)]
    pub contexts: Vec<ContextSelection>,
    #[serde(default)]
    pub title: Option<String>,
}

/// Result handed back to the UI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionResult {
    pub url: String,
    pub number: u64,
}

/// A file staged for the commit: its path in the repo and raw bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedFile {
    pub repo_path: String,
    pub content: Vec<u8>,
}

// --- Pure helpers ----------------------------------------------------------

/// Parses `owner`/`repo` from a github.com HTTPS URL, tolerating a trailing
/// `.git` and/or slash. Returns `None` for non-github.com hosts.
pub fn parse_owner_repo(url: &str) -> Option<(String, String)> {
    let trimmed = url.trim().trim_end_matches('/');
    let rest = trimmed
        .strip_prefix("https://github.com/")
        .or_else(|| trimmed.strip_prefix("http://github.com/"))
        .or_else(|| trimmed.strip_prefix("git@github.com:"))?;
    let rest = rest.strip_suffix(".git").unwrap_or(rest);
    let mut parts = rest.splitn(2, '/');
    let owner = parts.next()?.trim();
    let repo = parts.next()?.trim();
    if owner.is_empty() || repo.is_empty() || repo.contains('/') {
        return None;
    }
    Some((owner.to_string(), repo.to_string()))
}

/// Sanitises a user-supplied folder name: a single path segment of safe
/// characters, no traversal, no leading dot.
pub fn sanitize_name(name: &str) -> Result<String, ContributionError> {
    let trimmed = name.trim();
    let valid = !trimmed.is_empty()
        && !trimmed.starts_with('.')
        && !trimmed.contains('/')
        && !trimmed.contains('\\')
        && !trimmed.contains("..")
        && trimmed
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'));
    if valid {
        Ok(trimmed.to_string())
    } else {
        Err(ContributionError::InvalidName(name.to_string()))
    }
}

/// Personal skills across both tools: real skill folders (containing SKILL.md)
/// that are NOT managed links. De-duplicated by name (first tool wins), sorted.
pub fn enumerate_personal_skills(home: &Path) -> Vec<ContributableSkill> {
    let mut seen: std::collections::BTreeMap<String, ContributableSkill> =
        std::collections::BTreeMap::new();
    for tool in [SkillTool::ClaudeCode, SkillTool::Codex] {
        let root = skills_sync::skills_root(home, tool);
        let Ok(entries) = std::fs::read_dir(&root) else {
            continue;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let dir = entry.path();
            // Managed skills are links/junctions — only offer real folders the
            // user authored themselves.
            if skills_sync::is_link(&dir) || !dir.is_dir() {
                continue;
            }
            if !dir.join("SKILL.md").is_file() {
                continue;
            }
            seen.entry(name.clone()).or_insert(ContributableSkill {
                name,
                directory: dir,
                tool: tool.display_name().to_string(),
            });
        }
    }
    seen.into_values().collect()
}

/// Stages every file under a skill folder as `skills/<name>/<relative>`.
pub fn prepare_skill_files(name: &str, dir: &Path) -> Result<Vec<PreparedFile>, ContributionError> {
    if !dir.join("SKILL.md").is_file() {
        return Err(ContributionError::SkillMissingManifest(name.to_string()));
    }
    let mut files = Vec::new();
    collect_files(dir, dir, &format!("skills/{name}"), &mut files)?;
    Ok(files)
}

/// Stages every selected file of a context as `context/<name>/<file>`,
/// preserving the selection order (the picker already lists canonical
/// files first, then extras). Selected files that aren't on disk are
/// skipped — the whole context is "all files in the folder", so a
/// user-added file must contribute too.
pub fn prepare_context_files(
    name: &str,
    dir: &Path,
    selected: &[String],
) -> Result<Vec<PreparedFile>, ContributionError> {
    let mut files = Vec::new();
    for file in selected {
        let path = dir.join(file);
        if !path.is_file() {
            continue;
        }
        files.push(read_prepared(&path, &format!("context/{name}/{file}"))?);
    }
    if files.is_empty() {
        return Err(ContributionError::EmptyContext {
            name: name.to_string(),
        });
    }
    Ok(files)
}

fn collect_files(
    root: &Path,
    dir: &Path,
    repo_prefix: &str,
    out: &mut Vec<PreparedFile>,
) -> Result<(), ContributionError> {
    let entries = std::fs::read_dir(dir).map_err(|e| ContributionError::Read {
        path: dir.display().to_string(),
        reason: e.to_string(),
    })?;
    for entry in entries.flatten() {
        let path = entry.path();
        let rel = path.strip_prefix(root).unwrap_or(&path);
        // Skip VCS noise and hidden files.
        if rel
            .components()
            .any(|c| c.as_os_str().to_string_lossy().starts_with('.'))
        {
            continue;
        }
        if path.is_dir() {
            collect_files(root, &path, repo_prefix, out)?;
        } else if path.is_file() {
            let rel_str = rel.to_string_lossy().replace('\\', "/");
            out.push(read_prepared(&path, &format!("{repo_prefix}/{rel_str}"))?);
        }
    }
    Ok(())
}

fn read_prepared(path: &Path, repo_path: &str) -> Result<PreparedFile, ContributionError> {
    let meta = std::fs::metadata(path).map_err(|e| ContributionError::Read {
        path: path.display().to_string(),
        reason: e.to_string(),
    })?;
    if meta.len() > MAX_FILE_BYTES {
        return Err(ContributionError::FileTooLarge {
            path: repo_path.to_string(),
            size: meta.len(),
            max: MAX_FILE_BYTES,
        });
    }
    let content = std::fs::read(path).map_err(|e| ContributionError::Read {
        path: path.display().to_string(),
        reason: e.to_string(),
    })?;
    Ok(PreparedFile {
        repo_path: repo_path.to_string(),
        content,
    })
}

/// Branch name like `contrib/<login>-<timestamp>`, both sanitised for refs.
pub fn build_branch_name(login: &str, timestamp: &str) -> String {
    let slug: String = login
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    let slug = if slug.is_empty() { "user".into() } else { slug };
    format!("contrib/{slug}-{timestamp}")
}

/// Default PR title from the contributed item names.
pub fn build_pr_title(skills: &[String], contexts: &[String]) -> String {
    let mut parts = Vec::new();
    if !skills.is_empty() {
        parts.push(format!("skill(s): {}", skills.join(", ")));
    }
    if !contexts.is_empty() {
        parts.push(format!("context(s): {}", contexts.join(", ")));
    }
    format!("Add {}", parts.join("; "))
}

/// PR body listing each addition and the submitter.
pub fn build_pr_body(skills: &[String], contexts: &[String], login: &str) -> String {
    let mut lines = vec![
        "Proposed additions via BMad Manager.".to_string(),
        String::new(),
    ];
    for s in skills {
        lines.push(format!("- skill: `skills/{s}/`"));
    }
    for c in contexts {
        lines.push(format!("- context: `context/{c}/`"));
    }
    lines.push(String::new());
    lines.push(format!("Submitted by @{login}."));
    lines.join("\n")
}

// --- Orchestration ---------------------------------------------------------

/// Stage the selected files, create a branch + single commit off the default
/// branch, and open a PR. `timestamp` is injected so branch names are
/// deterministic in tests.
pub async fn submit_contribution<C: GitHubClient>(
    client: &C,
    owner: &str,
    repo: &str,
    request: &ContributionRequest,
    timestamp: &str,
) -> Result<ContributionResult, ContributionError> {
    if request.skills.is_empty() && request.contexts.is_empty() {
        return Err(ContributionError::NothingSelected);
    }

    // Stage files + collect sanitised names.
    let mut files: Vec<PreparedFile> = Vec::new();
    let mut skill_names: Vec<String> = Vec::new();
    for sel in &request.skills {
        let name = sanitize_name(&sel.name)?;
        files.extend(prepare_skill_files(&name, &sel.directory)?);
        skill_names.push(name);
    }
    let mut context_names: Vec<String> = Vec::new();
    for sel in &request.contexts {
        let name = sanitize_name(&sel.target_name)?;
        files.extend(prepare_context_files(&name, &sel.directory, &sel.files)?);
        context_names.push(name);
    }

    let login = client.whoami().await?;
    let base = client.default_branch(owner, repo).await?;

    // Additions only: refuse to touch an existing folder.
    for name in &skill_names {
        if client
            .path_exists(owner, repo, &format!("skills/{name}"), &base)
            .await?
        {
            return Err(ContributionError::Collision {
                kind: "skills".into(),
                name: name.clone(),
            });
        }
    }
    for name in &context_names {
        if client
            .path_exists(owner, repo, &format!("context/{name}"), &base)
            .await?
        {
            return Err(ContributionError::Collision {
                kind: "context".into(),
                name: name.clone(),
            });
        }
    }

    let base_sha = client.branch_head_sha(owner, repo, &base).await?;
    let base_tree = client.commit_tree_sha(owner, repo, &base_sha).await?;

    let mut entries = Vec::with_capacity(files.len());
    for file in &files {
        let blob_sha = client
            .create_blob(owner, repo, &base64_encode(&file.content))
            .await?;
        entries.push(TreeEntry {
            path: file.repo_path.clone(),
            blob_sha,
        });
    }
    let tree = client
        .create_tree(owner, repo, &base_tree, &entries)
        .await?;

    let title = request
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| build_pr_title(&skill_names, &context_names));
    let commit = client
        .create_commit(owner, repo, &title, &tree, &base_sha)
        .await?;

    let branch = build_branch_name(&login, timestamp);
    client
        .create_branch_ref(owner, repo, &branch, &commit)
        .await?;

    let body = build_pr_body(&skill_names, &context_names, &login);
    let PullResult { html_url, number } = client
        .create_pull(owner, repo, &title, &branch, &base, &body)
        .await?;
    Ok(ContributionResult {
        url: html_url,
        number,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::github_client::{PullResult, RepoAccess};
    use std::cell::RefCell;
    use tempfile::TempDir;

    fn make_skill(root: &Path, name: &str) {
        let dir = root.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), format!("# {name}")).unwrap();
    }

    // --- Pure helpers ---

    #[test]
    fn parses_owner_repo_from_assorted_urls() {
        assert_eq!(
            parse_owner_repo("https://github.com/acme/skills"),
            Some(("acme".into(), "skills".into()))
        );
        assert_eq!(
            parse_owner_repo("https://github.com/acme/skills.git/"),
            Some(("acme".into(), "skills".into()))
        );
        assert_eq!(
            parse_owner_repo("git@github.com:acme/skills.git"),
            Some(("acme".into(), "skills".into()))
        );
        assert_eq!(parse_owner_repo("https://gitlab.com/acme/skills"), None);
        assert_eq!(parse_owner_repo("https://github.com/acme"), None);
    }

    #[test]
    fn sanitize_name_rejects_traversal_and_empty() {
        assert_eq!(sanitize_name(" my-skill ").unwrap(), "my-skill");
        assert!(sanitize_name("../evil").is_err());
        assert!(sanitize_name("a/b").is_err());
        assert!(sanitize_name(".hidden").is_err());
        assert!(sanitize_name("").is_err());
    }

    #[test]
    fn enumerate_personal_skills_excludes_managed_links() {
        let tmp = TempDir::new().unwrap();
        let home = tmp.path();
        let claude = skills_sync::skills_root(home, SkillTool::ClaudeCode);
        std::fs::create_dir_all(&claude).unwrap();
        make_skill(&claude, "mine");
        // A managed skill: real target elsewhere, symlinked into skills root.
        let managed_target = home.join("skills-managed/managed-skill");
        std::fs::create_dir_all(&managed_target).unwrap();
        std::fs::write(managed_target.join("SKILL.md"), "x").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(&managed_target, claude.join("managed-skill")).unwrap();
        // A folder without SKILL.md.
        std::fs::create_dir_all(claude.join("not-a-skill")).unwrap();

        let skills = enumerate_personal_skills(home);
        let names: Vec<&str> = skills.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, vec!["mine"]);
    }

    #[test]
    fn prepare_skill_files_recurses_under_skills_prefix() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("my-skill");
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::write(dir.join("SKILL.md"), "doc").unwrap();
        std::fs::write(dir.join("sub/helper.py"), "code").unwrap();
        std::fs::write(dir.join(".hidden"), "ignored").unwrap();

        let mut files = prepare_skill_files("my-skill", &dir).unwrap();
        files.sort_by(|a, b| a.repo_path.cmp(&b.repo_path));
        let paths: Vec<&str> = files.iter().map(|f| f.repo_path.as_str()).collect();
        assert_eq!(
            paths,
            vec!["skills/my-skill/SKILL.md", "skills/my-skill/sub/helper.py"]
        );
    }

    #[test]
    fn prepare_context_files_stages_every_selected_file() {
        // The context is "all files in the folder", so a user-added file
        // like notes.txt must be contributed too, not silently dropped.
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("ctx");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("icp.md"), "a").unwrap();
        std::fs::write(dir.join("kpis.md"), "b").unwrap();
        std::fs::write(dir.join("notes.txt"), "c").unwrap();

        let files = prepare_context_files(
            "acme",
            &dir,
            &["icp.md".into(), "kpis.md".into(), "notes.txt".into()],
        )
        .unwrap();
        let paths: Vec<&str> = files.iter().map(|f| f.repo_path.as_str()).collect();
        assert_eq!(
            paths,
            vec![
                "context/acme/icp.md",
                "context/acme/kpis.md",
                "context/acme/notes.txt"
            ]
        );
    }

    #[test]
    fn prepare_context_files_skips_selected_files_that_vanished() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("ctx2");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("icp.md"), "x").unwrap();
        // "gone.md" is selected but not on disk — skip it, don't error.
        let files =
            prepare_context_files("acme", &dir, &["icp.md".into(), "gone.md".into()]).unwrap();
        let paths: Vec<&str> = files.iter().map(|f| f.repo_path.as_str()).collect();
        assert_eq!(paths, vec!["context/acme/icp.md"]);
    }

    #[test]
    fn prepare_skill_files_rejects_oversized() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("big");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), "x").unwrap();
        std::fs::write(
            dir.join("blob.bin"),
            vec![0u8; (MAX_FILE_BYTES + 1) as usize],
        )
        .unwrap();
        assert!(matches!(
            prepare_skill_files("big", &dir),
            Err(ContributionError::FileTooLarge { .. })
        ));
    }

    #[test]
    fn branch_and_pr_text_compose() {
        assert_eq!(
            build_branch_name("ada", "20260614-120000"),
            "contrib/ada-20260614-120000"
        );
        assert_eq!(
            build_pr_title(&["foo".into()], &["acme".into()]),
            "Add skill(s): foo; context(s): acme"
        );
        assert!(build_pr_body(&["foo".into()], &[], "ada").contains("skills/foo/"));
    }

    // --- Orchestration with a fake client ---

    #[derive(Default)]
    struct FakeClient {
        calls: RefCell<Vec<String>>,
        existing_paths: Vec<String>,
        fail_on_pull: bool,
    }

    impl GitHubClient for FakeClient {
        async fn whoami(&self) -> Result<String, GitHubError> {
            self.calls.borrow_mut().push("whoami".into());
            Ok("ada".into())
        }
        async fn repo_access(&self, _o: &str, _r: &str) -> Result<RepoAccess, GitHubError> {
            Ok(RepoAccess {
                login: "ada".into(),
                repo_full_name: "acme/skills".into(),
                can_push: true,
            })
        }
        async fn default_branch(&self, _o: &str, _r: &str) -> Result<String, GitHubError> {
            self.calls.borrow_mut().push("default_branch".into());
            Ok("main".into())
        }
        async fn branch_head_sha(
            &self,
            _o: &str,
            _r: &str,
            _b: &str,
        ) -> Result<String, GitHubError> {
            Ok("basecommit".into())
        }
        async fn commit_tree_sha(
            &self,
            _o: &str,
            _r: &str,
            _c: &str,
        ) -> Result<String, GitHubError> {
            Ok("basetree".into())
        }
        async fn path_exists(
            &self,
            _o: &str,
            _r: &str,
            path: &str,
            _b: &str,
        ) -> Result<bool, GitHubError> {
            Ok(self.existing_paths.iter().any(|p| p == path))
        }
        async fn create_blob(&self, _o: &str, _r: &str, _c: &str) -> Result<String, GitHubError> {
            self.calls.borrow_mut().push("create_blob".into());
            Ok("blobsha".into())
        }
        async fn create_tree(
            &self,
            _o: &str,
            _r: &str,
            _b: &str,
            _e: &[TreeEntry],
        ) -> Result<String, GitHubError> {
            self.calls.borrow_mut().push("create_tree".into());
            Ok("newtree".into())
        }
        async fn create_commit(
            &self,
            _o: &str,
            _r: &str,
            _m: &str,
            _t: &str,
            _p: &str,
        ) -> Result<String, GitHubError> {
            self.calls.borrow_mut().push("create_commit".into());
            Ok("newcommit".into())
        }
        async fn create_branch_ref(
            &self,
            _o: &str,
            _r: &str,
            _b: &str,
            _s: &str,
        ) -> Result<(), GitHubError> {
            self.calls.borrow_mut().push("create_branch_ref".into());
            Ok(())
        }
        async fn create_pull(
            &self,
            _o: &str,
            _r: &str,
            _t: &str,
            _h: &str,
            _b: &str,
            _body: &str,
        ) -> Result<PullResult, GitHubError> {
            self.calls.borrow_mut().push("create_pull".into());
            if self.fail_on_pull {
                return Err(GitHubError::Api {
                    status: 422,
                    message: "validation failed".into(),
                });
            }
            Ok(PullResult {
                html_url: "https://github.com/acme/skills/pull/7".into(),
                number: 7,
            })
        }
    }

    fn skill_request(dir: &Path) -> ContributionRequest {
        ContributionRequest {
            skills: vec![SkillSelection {
                name: "foo".into(),
                directory: dir.to_path_buf(),
            }],
            contexts: vec![],
            title: None,
        }
    }

    #[tokio::test]
    async fn submit_runs_the_full_choreography_and_returns_pr() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("foo");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), "doc").unwrap();

        let client = FakeClient::default();
        let result = submit_contribution(&client, "acme", "skills", &skill_request(&dir), "ts")
            .await
            .unwrap();

        assert_eq!(result.number, 7);
        assert_eq!(result.url, "https://github.com/acme/skills/pull/7");
        let calls = client.calls.borrow().clone();
        assert_eq!(
            calls,
            vec![
                "whoami",
                "default_branch",
                "create_blob",
                "create_tree",
                "create_commit",
                "create_branch_ref",
                "create_pull",
            ]
        );
    }

    #[tokio::test]
    async fn submit_blocks_when_target_folder_exists() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("foo");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), "doc").unwrap();

        let client = FakeClient {
            existing_paths: vec!["skills/foo".into()],
            ..Default::default()
        };
        let err = submit_contribution(&client, "acme", "skills", &skill_request(&dir), "ts")
            .await
            .unwrap_err();
        assert!(matches!(err, ContributionError::Collision { .. }));
        assert!(!client.calls.borrow().contains(&"create_blob".to_string()));
    }

    #[tokio::test]
    async fn submit_requires_a_selection() {
        let client = FakeClient::default();
        let empty = ContributionRequest {
            skills: vec![],
            contexts: vec![],
            title: None,
        };
        assert_eq!(
            submit_contribution(&client, "acme", "skills", &empty, "ts")
                .await
                .unwrap_err(),
            ContributionError::NothingSelected
        );
    }

    #[tokio::test]
    async fn submit_surfaces_a_pull_failure() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("foo");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("SKILL.md"), "doc").unwrap();

        let client = FakeClient {
            fail_on_pull: true,
            ..Default::default()
        };
        let err = submit_contribution(&client, "acme", "skills", &skill_request(&dir), "ts")
            .await
            .unwrap_err();
        assert!(matches!(
            err,
            ContributionError::GitHub(GitHubError::Api { status: 422, .. })
        ));
    }
}
