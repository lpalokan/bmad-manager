//! A thin GitHub REST client for the contribution flow.
//!
//! The trait is the seam the contribution orchestrator talks to, so the
//! choreography (ref → base tree → blobs → tree → commit → branch → pull) can
//! be unit-tested with a fake and no network. The real implementation is a
//! small async `reqwest` wrapper over the Git Data API.
//!
//! Auth uses a `Bearer` token (the REST convention) — distinct from the
//! Basic-auth header `skills_sync` builds for git-over-HTTPS.

use serde::Deserialize;
use thiserror::Error;

const API_BASE: &str = "https://api.github.com";
const USER_AGENT: &str = "bmad-manager";
const API_VERSION: &str = "2022-11-28";

#[derive(Debug, Error, PartialEq, Eq)]
pub enum GitHubError {
    #[error("network error talking to GitHub: {0}")]
    Network(String),
    #[error("GitHub API error {status}: {message}")]
    Api { status: u16, message: String },
    #[error("unexpected GitHub response: {0}")]
    Decode(String),
}

/// One entry in a created tree (always a regular file blob).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeEntry {
    pub path: String,
    pub blob_sha: String,
}

/// The opened pull request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PullResult {
    pub html_url: String,
    pub number: u64,
}

/// Read-side report for the Settings "Test access" button.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepoAccess {
    pub login: String,
    pub repo_full_name: String,
    /// Whether the token's effective access includes push (best-effort — GitHub
    /// only returns this when the caller has at least read on the repo).
    pub can_push: bool,
}

/// The operations the contribution orchestrator needs. Used via generics
/// (static dispatch) only, so async fns in the trait are fine.
#[allow(async_fn_in_trait)]
pub trait GitHubClient {
    async fn whoami(&self) -> Result<String, GitHubError>;
    async fn repo_access(&self, owner: &str, repo: &str) -> Result<RepoAccess, GitHubError>;
    async fn default_branch(&self, owner: &str, repo: &str) -> Result<String, GitHubError>;
    async fn branch_head_sha(
        &self,
        owner: &str,
        repo: &str,
        branch: &str,
    ) -> Result<String, GitHubError>;
    async fn commit_tree_sha(
        &self,
        owner: &str,
        repo: &str,
        commit_sha: &str,
    ) -> Result<String, GitHubError>;
    /// True if `path` already exists on `branch` (used to block additions that
    /// would overwrite existing repo content).
    async fn path_exists(
        &self,
        owner: &str,
        repo: &str,
        path: &str,
        branch: &str,
    ) -> Result<bool, GitHubError>;
    async fn create_blob(
        &self,
        owner: &str,
        repo: &str,
        content_base64: &str,
    ) -> Result<String, GitHubError>;
    async fn create_tree(
        &self,
        owner: &str,
        repo: &str,
        base_tree: &str,
        entries: &[TreeEntry],
    ) -> Result<String, GitHubError>;
    async fn create_commit(
        &self,
        owner: &str,
        repo: &str,
        message: &str,
        tree: &str,
        parent: &str,
    ) -> Result<String, GitHubError>;
    async fn create_branch_ref(
        &self,
        owner: &str,
        repo: &str,
        branch: &str,
        sha: &str,
    ) -> Result<(), GitHubError>;
    async fn create_pull(
        &self,
        owner: &str,
        repo: &str,
        title: &str,
        head: &str,
        base: &str,
        body: &str,
    ) -> Result<PullResult, GitHubError>;
}

/// `reqwest`-backed implementation against api.github.com.
pub struct ReqwestGitHubClient {
    client: reqwest::Client,
    token: String,
}

impl ReqwestGitHubClient {
    pub fn new(token: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            token,
        }
    }

    fn request(&self, method: reqwest::Method, path: &str) -> reqwest::RequestBuilder {
        self.client
            .request(method, format!("{API_BASE}{path}"))
            .header(reqwest::header::USER_AGENT, USER_AGENT)
            .header(reqwest::header::ACCEPT, "application/vnd.github+json")
            .header("X-GitHub-Api-Version", API_VERSION)
            .bearer_auth(&self.token)
    }

    /// Sends a request and parses the JSON body on success, mapping non-2xx
    /// responses to `GitHubError::Api` with GitHub's own `message`.
    async fn send_json(builder: reqwest::RequestBuilder) -> Result<serde_json::Value, GitHubError> {
        let resp = builder
            .send()
            .await
            .map_err(|e| GitHubError::Network(e.to_string()))?;
        let status = resp.status();
        let value: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| GitHubError::Decode(e.to_string()))?;
        if status.is_success() {
            Ok(value)
        } else {
            let message = value
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("unknown error")
                .to_string();
            Err(GitHubError::Api {
                status: status.as_u16(),
                message,
            })
        }
    }

    fn str_field(value: &serde_json::Value, field: &str) -> Result<String, GitHubError> {
        value
            .get(field)
            .and_then(|v| v.as_str())
            .map(str::to_string)
            .ok_or_else(|| GitHubError::Decode(format!("missing `{field}` in response")))
    }
}

impl GitHubClient for ReqwestGitHubClient {
    async fn whoami(&self) -> Result<String, GitHubError> {
        let v = Self::send_json(self.request(reqwest::Method::GET, "/user")).await?;
        Self::str_field(&v, "login")
    }

    async fn repo_access(&self, owner: &str, repo: &str) -> Result<RepoAccess, GitHubError> {
        let login = self.whoami().await?;
        let v =
            Self::send_json(self.request(reqwest::Method::GET, &format!("/repos/{owner}/{repo}")))
                .await?;
        let repo_full_name = Self::str_field(&v, "full_name")?;
        let can_push = v
            .get("permissions")
            .and_then(|p| p.get("push"))
            .and_then(|p| p.as_bool())
            .unwrap_or(false);
        Ok(RepoAccess {
            login,
            repo_full_name,
            can_push,
        })
    }

    async fn default_branch(&self, owner: &str, repo: &str) -> Result<String, GitHubError> {
        let v =
            Self::send_json(self.request(reqwest::Method::GET, &format!("/repos/{owner}/{repo}")))
                .await?;
        Self::str_field(&v, "default_branch")
    }

    async fn branch_head_sha(
        &self,
        owner: &str,
        repo: &str,
        branch: &str,
    ) -> Result<String, GitHubError> {
        let v = Self::send_json(self.request(
            reqwest::Method::GET,
            &format!("/repos/{owner}/{repo}/git/ref/heads/{branch}"),
        ))
        .await?;
        v.get("object")
            .and_then(|o| o.get("sha"))
            .and_then(|s| s.as_str())
            .map(str::to_string)
            .ok_or_else(|| GitHubError::Decode("missing object.sha in ref response".into()))
    }

    async fn commit_tree_sha(
        &self,
        owner: &str,
        repo: &str,
        commit_sha: &str,
    ) -> Result<String, GitHubError> {
        let v = Self::send_json(self.request(
            reqwest::Method::GET,
            &format!("/repos/{owner}/{repo}/git/commits/{commit_sha}"),
        ))
        .await?;
        v.get("tree")
            .and_then(|t| t.get("sha"))
            .and_then(|s| s.as_str())
            .map(str::to_string)
            .ok_or_else(|| GitHubError::Decode("missing tree.sha in commit response".into()))
    }

    async fn path_exists(
        &self,
        owner: &str,
        repo: &str,
        path: &str,
        branch: &str,
    ) -> Result<bool, GitHubError> {
        let resp = self
            .request(
                reqwest::Method::GET,
                &format!("/repos/{owner}/{repo}/contents/{path}?ref={branch}"),
            )
            .send()
            .await
            .map_err(|e| GitHubError::Network(e.to_string()))?;
        match resp.status().as_u16() {
            200 => Ok(true),
            404 => Ok(false),
            status => {
                let message = resp
                    .json::<serde_json::Value>()
                    .await
                    .ok()
                    .and_then(|v| {
                        v.get("message")
                            .and_then(|m| m.as_str())
                            .map(str::to_string)
                    })
                    .unwrap_or_else(|| "unknown error".into());
                Err(GitHubError::Api { status, message })
            }
        }
    }

    async fn create_blob(
        &self,
        owner: &str,
        repo: &str,
        content_base64: &str,
    ) -> Result<String, GitHubError> {
        let body = serde_json::json!({ "content": content_base64, "encoding": "base64" });
        let v = Self::send_json(
            self.request(
                reqwest::Method::POST,
                &format!("/repos/{owner}/{repo}/git/blobs"),
            )
            .json(&body),
        )
        .await?;
        Self::str_field(&v, "sha")
    }

    async fn create_tree(
        &self,
        owner: &str,
        repo: &str,
        base_tree: &str,
        entries: &[TreeEntry],
    ) -> Result<String, GitHubError> {
        let tree: Vec<_> = entries
            .iter()
            .map(|e| {
                serde_json::json!({
                    "path": e.path,
                    "mode": "100644",
                    "type": "blob",
                    "sha": e.blob_sha,
                })
            })
            .collect();
        let body = serde_json::json!({ "base_tree": base_tree, "tree": tree });
        let v = Self::send_json(
            self.request(
                reqwest::Method::POST,
                &format!("/repos/{owner}/{repo}/git/trees"),
            )
            .json(&body),
        )
        .await?;
        Self::str_field(&v, "sha")
    }

    async fn create_commit(
        &self,
        owner: &str,
        repo: &str,
        message: &str,
        tree: &str,
        parent: &str,
    ) -> Result<String, GitHubError> {
        let body = serde_json::json!({ "message": message, "tree": tree, "parents": [parent] });
        let v = Self::send_json(
            self.request(
                reqwest::Method::POST,
                &format!("/repos/{owner}/{repo}/git/commits"),
            )
            .json(&body),
        )
        .await?;
        Self::str_field(&v, "sha")
    }

    async fn create_branch_ref(
        &self,
        owner: &str,
        repo: &str,
        branch: &str,
        sha: &str,
    ) -> Result<(), GitHubError> {
        let body = serde_json::json!({ "ref": format!("refs/heads/{branch}"), "sha": sha });
        Self::send_json(
            self.request(
                reqwest::Method::POST,
                &format!("/repos/{owner}/{repo}/git/refs"),
            )
            .json(&body),
        )
        .await?;
        Ok(())
    }

    async fn create_pull(
        &self,
        owner: &str,
        repo: &str,
        title: &str,
        head: &str,
        base: &str,
        body: &str,
    ) -> Result<PullResult, GitHubError> {
        let payload = serde_json::json!({
            "title": title, "head": head, "base": base, "body": body,
        });
        let v = Self::send_json(
            self.request(
                reqwest::Method::POST,
                &format!("/repos/{owner}/{repo}/pulls"),
            )
            .json(&payload),
        )
        .await?;
        #[derive(Deserialize)]
        struct Pull {
            html_url: String,
            number: u64,
        }
        let pull: Pull =
            serde_json::from_value(v).map_err(|e| GitHubError::Decode(e.to_string()))?;
        Ok(PullResult {
            html_url: pull.html_url,
            number: pull.number,
        })
    }
}
