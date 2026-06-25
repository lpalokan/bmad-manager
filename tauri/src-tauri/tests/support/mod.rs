//! Shared cucumber `World` and test fixtures.
//!
//! The world owns the throwaway state each scenario needs: a temp
//! directory acting as the projects root, the currently-loaded
//! settings, the most recent service result/error, captured Tauri
//! events from the command runner, and helpers for building zip
//! fixtures. Step files stay thin by delegating here.

use std::path::{Path, PathBuf};

use bmad_manager_lib::models::{AgentLaunchMethod, AppSettings, CompanyContext, ProjectItem};
use bmad_manager_lib::services::agent_launch::ResolvedAgentLaunch;
use bmad_manager_lib::services::contribution::{ContributableSkill, PreparedFile};
use bmad_manager_lib::services::project_service::InitTargetInfo;
use cucumber::World;
use tempfile::TempDir;

#[derive(Debug, Default, World)]
pub struct TauriWorld {
    pub tmp: Option<TempDir>,
    /// Used by scenarios that want to reference a "nonexistent" root —
    /// we point at a path under `tmp` that we never create.
    pub nonexistent_root: Option<PathBuf>,
    pub projects_root: Option<PathBuf>,
    pub settings: Option<AppSettings>,
    pub decoded_settings: Option<AppSettings>,
    pub raw_json: Option<String>,
    pub last_string: Option<String>,
    pub last_string_error: Option<String>,
    pub listed_projects: Vec<ProjectItem>,
    pub init_template: Option<String>,
    pub last_path_dir: Option<PathBuf>,
    pub last_executable_path: Option<PathBuf>,
    pub last_detection: Option<Option<PathBuf>>,
    pub stub_binary: Option<PathBuf>,
    pub bundled_cache_dir: Option<PathBuf>,
    pub user_cache_dir: Option<PathBuf>,
    pub detected_version: Option<Option<String>>,
    pub seed_outcome: Option<bool>,
    /// `Some(None)` records a resolution attempt that found nothing.
    pub resolved_context: Option<Option<CompanyContext>>,
    pub resolved_contexts: Option<Vec<CompanyContext>>,
    pub last_managed_dir: Option<PathBuf>,
    /// Isolated directory used as the token store's `settings_dir` scope so
    /// secure-token scenarios never touch the real per-user credential store.
    pub token_scope: Option<PathBuf>,
    /// Fake home dir for contribution scenarios (holds `.claude/skills/…`).
    pub contrib_home: Option<PathBuf>,
    pub contributable_skills: Option<Vec<ContributableSkill>>,
    pub prepared_files: Option<Vec<PreparedFile>>,
    pub parsed_owner_repo: Option<Option<(String, String)>>,
    /// Existing-folder init target picked by an init-into-existing scenario.
    pub init_target: Option<PathBuf>,
    pub init_target_info: Option<InitTargetInfo>,
    /// Project folder a version-check / update scenario operates on.
    pub update_target: Option<PathBuf>,
    /// Result of the most recent `is_project_stale` check.
    pub update_available: Option<bool>,
    /// Names of the projects the most recent end-to-end version check
    /// (`read_latest_repo_module` + stale filter) flagged as behind.
    pub stale_projects: Option<Vec<String>>,
    /// Launch-method resolution scenarios (issue #88): the chosen method,
    /// whether the app is "installed", and the resolved concrete launch.
    pub launch_method: Option<AgentLaunchMethod>,
    pub app_installed: Option<bool>,
    pub resolved_launch: Option<ResolvedAgentLaunch>,
}

impl TauriWorld {
    pub fn ensure_tmp(&mut self) -> &Path {
        if self.tmp.is_none() {
            self.tmp = Some(TempDir::new().expect("tempdir"));
        }
        self.tmp.as_ref().unwrap().path()
    }

    /// A dedicated, isolated directory acting as the token store's
    /// `settings_dir` scope for the secure-token scenarios. Created once per
    /// scenario so assertions about on-disk fallback files are deterministic.
    pub fn ensure_token_scope(&mut self) -> PathBuf {
        if let Some(scope) = &self.token_scope {
            return scope.clone();
        }
        let scope = self.ensure_tmp().to_path_buf().join("token-store");
        std::fs::create_dir_all(&scope).expect("create token scope");
        self.token_scope = Some(scope.clone());
        scope
    }

    pub fn ensure_projects_root(&mut self) -> PathBuf {
        if let Some(root) = &self.projects_root {
            return root.clone();
        }
        let root = self.ensure_tmp().join("projects-root");
        std::fs::create_dir_all(&root).expect("create projects root");
        self.projects_root = Some(root.clone());
        root
    }

    /// Writes the named context files (with the file name as content so
    /// copies are verifiable) into `<root>/<project>/<subpath>/`. A file name
    /// may itself contain a relative subpath (e.g. "research/notes.md") to
    /// seed nested context files; intermediate folders are created.
    pub fn seed_context_files(&mut self, project: &str, subpath: &str, files: &[&str]) {
        let dir = self.ensure_projects_root().join(project).join(subpath);
        std::fs::create_dir_all(&dir).expect("create context dir");
        for file in files {
            let path = dir.join(file);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).expect("create nested context dir");
            }
            std::fs::write(path, format!("content of {file}")).expect("write context file");
        }
    }

    /// Root of a fake skills-repo clone under the scenario's tempdir.
    pub fn skills_repo_root(&mut self) -> PathBuf {
        self.ensure_tmp().to_path_buf().join("skills-repo")
    }

    /// Seeds `<skills-repo>/context/<name>/` with the named files (file name
    /// as content) so skills-repo context discovery has something to find.
    pub fn seed_skills_repo_context(&mut self, name: &str, files: &[&str]) {
        let dir = self.skills_repo_root().join("context").join(name);
        std::fs::create_dir_all(&dir).expect("create skills repo context dir");
        for file in files {
            std::fs::write(dir.join(file), format!("content of {file}"))
                .expect("write skills repo context file");
        }
    }

    /// Fake home directory for contribution scenarios.
    pub fn ensure_contrib_home(&mut self) -> PathBuf {
        if let Some(home) = &self.contrib_home {
            return home.clone();
        }
        let home = self.ensure_tmp().to_path_buf().join("contrib-home");
        std::fs::create_dir_all(&home).expect("create contrib home");
        self.contrib_home = Some(home.clone());
        home
    }

    /// Builds a minimal module zip fixture (one wrapper folder holding a
    /// manifest) for scenarios that run the full project-creation pipeline.
    pub fn build_module_zip(&mut self) -> PathBuf {
        use std::io::Write as _;
        let path = self.ensure_tmp().join("module-fixture.zip");
        let file = std::fs::File::create(&path).expect("create zip fixture");
        let mut writer = zip::ZipWriter::new(file);
        writer
            .start_file(
                "module/manifest.yaml",
                zip::write::SimpleFileOptions::default(),
            )
            .expect("start zip entry");
        writer.write_all(b"name: fixture").expect("write zip entry");
        writer.finish().expect("finish zip");
        path
    }

    /// Builds a module zip whose `skills/module.yaml` carries the
    /// marketing-growth `code` and the given `module_version`, wrapped in a
    /// single top-level folder (the GitHub "Download ZIP" layout that
    /// `zip_source::module_root` descends into). Lets version-check scenarios
    /// drive `read_latest_repo_module` against a real local source the same way
    /// `check_for_updates` does in production.
    pub fn build_marketing_growth_module_zip(&mut self, version: &str) -> PathBuf {
        use std::io::Write as _;
        let path = self
            .ensure_tmp()
            .join(format!("marketing-growth-{version}.zip"));
        let file = std::fs::File::create(&path).expect("create zip fixture");
        let mut writer = zip::ZipWriter::new(file);
        writer
            .start_file(
                "module/skills/module.yaml",
                zip::write::SimpleFileOptions::default(),
            )
            .expect("start zip entry");
        writer
            .write_all(format!("code: marketing-growth\nmodule_version: {version}\n").as_bytes())
            .expect("write zip entry");
        writer.finish().expect("finish zip");
        path
    }

    /// Like [`build_module_zip`], but also writes a
    /// `module/templates/agents-okf-block.md` so update scenarios can exercise
    /// the conditional okf-block injection.
    pub fn build_module_zip_with_okf(&mut self, okf_body: &str) -> PathBuf {
        use std::io::Write as _;
        let path = self.ensure_tmp().join("module-fixture-okf.zip");
        let file = std::fs::File::create(&path).expect("create zip fixture");
        let mut writer = zip::ZipWriter::new(file);
        let opts = zip::write::SimpleFileOptions::default();
        writer
            .start_file("module/manifest.yaml", opts)
            .expect("start zip entry");
        writer.write_all(b"name: fixture").expect("write zip entry");
        writer
            .start_file("module/templates/agents-okf-block.md", opts)
            .expect("start okf entry");
        writer
            .write_all(okf_body.as_bytes())
            .expect("write okf entry");
        writer.finish().expect("finish zip");
        path
    }

    /// Builds a local git repository (with `skills/module.yaml` and a single
    /// tag) and returns a `file://` URL. Lets git-source scenarios run fully
    /// offline: both the clone and the `git ls-remote --tags` latest-tag
    /// resolution work against a local file repo.
    pub fn build_module_git_repo(&mut self, tag: &str) -> String {
        use std::process::Command;
        let repo = self.ensure_tmp().to_path_buf().join("module-git-repo");
        let skills = repo.join("skills");
        std::fs::create_dir_all(&skills).expect("create git repo skills dir");
        std::fs::write(
            skills.join("module.yaml"),
            "code: marketing-growth\nmodule_version: 2.0.2\n",
        )
        .expect("write module.yaml");

        let git = |args: &[&str]| {
            let out = Command::new("git")
                .args(args)
                .current_dir(&repo)
                .env("GIT_TERMINAL_PROMPT", "0")
                .output()
                .expect("run git");
            assert!(
                out.status.success(),
                "git {args:?} failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        };
        git(&["init", "--quiet", "--initial-branch=main"]);
        git(&["config", "user.email", "test@example.com"]);
        git(&["config", "user.name", "Test"]);
        git(&["config", "commit.gpgsign", "false"]);
        git(&["add", "."]);
        git(&["commit", "--quiet", "-m", "initial"]);
        git(&["tag", tag]);
        format!("file://{}", repo.display())
    }

    /// Builds a local git repo whose `skills/module.yaml` carries the
    /// marketing-growth `code` and the given `module_version`, returning a
    /// `file://` URL for it. Unlike a "Download ZIP" archive, a git clone's
    /// content sits at the clone *root* (here: only `skills/` at the top
    /// level), so this drives the exact clone + `read_repo_module` path
    /// `check_for_updates` runs for a GitHub source — the path PR #83's zip
    /// fixture never exercised.
    pub fn build_marketing_growth_git_repo(&mut self, version: &str) -> String {
        use std::process::Command;
        let repo = self
            .ensure_tmp()
            .to_path_buf()
            .join(format!("marketing-growth-git-{version}"));
        let skills = repo.join("skills");
        std::fs::create_dir_all(&skills).expect("create git repo skills dir");
        std::fs::write(
            skills.join("module.yaml"),
            format!("code: marketing-growth\nmodule_version: {version}\n"),
        )
        .expect("write module.yaml");

        let git = |args: &[&str]| {
            let out = Command::new("git")
                .args(args)
                .current_dir(&repo)
                .env("GIT_TERMINAL_PROMPT", "0")
                .output()
                .expect("run git");
            assert!(
                out.status.success(),
                "git {args:?} failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        };
        git(&["init", "--quiet", "--initial-branch=main"]);
        git(&["config", "user.email", "test@example.com"]);
        git(&["config", "user.name", "Test"]);
        git(&["config", "commit.gpgsign", "false"]);
        git(&["add", "."]);
        git(&["commit", "--quiet", "-m", "initial"]);
        format!("file://{}", repo.display())
    }
}
