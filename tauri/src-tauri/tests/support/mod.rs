//! Shared cucumber `World` and test fixtures.
//!
//! The world owns the throwaway state each scenario needs: a temp
//! directory acting as the projects root, the currently-loaded
//! settings, the most recent service result/error, captured Tauri
//! events from the command runner, and helpers for building zip
//! fixtures. Step files stay thin by delegating here.

use std::path::{Path, PathBuf};

use bmad_manager_lib::models::{AppSettings, ProjectItem};
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
}

impl TauriWorld {
    pub fn ensure_tmp(&mut self) -> &Path {
        if self.tmp.is_none() {
            self.tmp = Some(TempDir::new().expect("tempdir"));
        }
        self.tmp.as_ref().unwrap().path()
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
}
