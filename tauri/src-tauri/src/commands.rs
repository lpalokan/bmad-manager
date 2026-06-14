//! Tauri command handlers exposed to the Svelte frontend.
//!
//! Each handler is a thin wrapper over a service function. Errors are
//! mapped to plain strings here so the IPC layer marshals them as bare
//! JSON strings — the simplest contract the frontend can render in an
//! alert.

use std::path::PathBuf;

use serde::{Serialize, Serializer};
use tauri::{AppHandle, Emitter, State};
use tokio::sync::Mutex;

use crate::models::{AppSettings, CompanyContext, ProjectItem};
use crate::platform;
use crate::services::bundled_tooling::{self, BundledTooling};
use crate::services::command_runner::OutputEvent;
use crate::services::skills_sync::{self, SkillTool};
use crate::services::{
    company_context, path_detection, project_creator, project_service, settings_store, token_store,
};

pub struct AppState {
    pub settings_path: PathBuf,
    /// Serialises project-creation runs so two simultaneous "create"
    /// clicks don't race on the same projects-root and tempdir.
    pub create_lock: Mutex<()>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            settings_path: platform::settings_dir().join("settings.json"),
            create_lock: Mutex::new(()),
        }
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

/// IPC-friendly error: always serialises as a bare JSON string.
pub struct IpcError(pub String);

impl<E: std::fmt::Display> From<E> for IpcError {
    fn from(err: E) -> Self {
        Self(err.to_string())
    }
}

impl Serialize for IpcError {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.0)
    }
}

type CmdResult<T> = Result<T, IpcError>;

#[tauri::command]
pub fn load_settings(state: State<'_, AppState>) -> CmdResult<AppSettings> {
    Ok(settings_store::load_or_init(&state.settings_path)?)
}

#[tauri::command]
pub fn save_settings(settings: AppSettings, state: State<'_, AppState>) -> CmdResult<()> {
    settings_store::save(&state.settings_path, &settings)?;
    Ok(())
}

/// Returns the built-in defaults without touching the persisted file. The
/// Settings dialog's "Reset to defaults" loads these into its draft so the
/// user can review (and then Save) a clean configuration — picking up, for
/// example, agents added to the install `--tools` list since their
/// settings.json was first written.
#[tauri::command]
pub fn default_settings() -> AppSettings {
    AppSettings::defaults()
}

#[tauri::command]
pub fn list_projects(state: State<'_, AppState>) -> CmdResult<Vec<ProjectItem>> {
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let root = expand_tilde(&settings.projects_root);
    Ok(project_service::list_projects(
        &root,
        settings.project_sort_order,
    ))
}

#[tauri::command]
pub async fn create_project(
    name: String,
    context: Option<CompanyContext>,
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<ProjectItem> {
    let _guard = state.create_lock.lock().await;
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let emit = move |event: OutputEvent| {
        let _ = app.emit("project-create-output", event);
    };
    project_creator::create_project(&name, &settings, context.as_ref(), emit)
        .await
        .map_err(|e| IpcError(e.to_string()))
}

/// Scans the projects root for existing company contexts the new-project
/// "Context" picker can offer as seeding sources.
#[tauri::command]
pub fn list_company_contexts(state: State<'_, AppState>) -> CmdResult<Vec<CompanyContext>> {
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let root = expand_tilde(&settings.projects_root);
    let projects = project_service::list_projects(&root, settings.project_sort_order);
    Ok(company_context::contexts_in(&projects))
}

#[tauri::command]
pub fn delete_project(path: String) -> CmdResult<()> {
    let p = PathBuf::from(&path);
    project_service::trash_project(&p).map_err(IpcError)?;
    Ok(())
}

#[tauri::command]
pub fn get_bundled_tooling() -> BundledTooling {
    bundled_tooling::detect()
}

#[tauri::command]
pub fn open_in_claude(project_path: String, state: State<'_, AppState>) -> CmdResult<()> {
    open_in_terminal(&project_path, "claude", state)
}

#[tauri::command]
pub fn open_in_opencode(project_path: String, state: State<'_, AppState>) -> CmdResult<()> {
    open_in_terminal(&project_path, "opencode", state)
}

#[tauri::command]
pub fn open_in_pi(project_path: String, state: State<'_, AppState>) -> CmdResult<()> {
    open_in_terminal(&project_path, "pi", state)
}

#[tauri::command]
pub fn open_in_codex(project_path: String, state: State<'_, AppState>) -> CmdResult<()> {
    open_in_terminal(&project_path, "codex", state)
}

/// Reveal a project's folder in the OS file manager (Explorer on Windows).
/// Guards against a path that's been moved or deleted since the list was
/// rendered, so the user gets a clear error rather than an empty window.
#[tauri::command]
pub fn open_project_folder(project_path: String) -> CmdResult<()> {
    let path = PathBuf::from(&project_path);
    if !path.is_dir() {
        return Err(IpcError(format!("Folder no longer exists: {project_path}")));
    }
    platform::open_folder(&path).map_err(IpcError)?;
    Ok(())
}

/// Returns the absolute path the supplied command resolves to on the
/// current `PATH`, or `None` if it's not found. The Settings dialog
/// calls this per coding-agent command so the user knows whether the
/// bare-name defaults work before they need to browse for a binary.
#[tauri::command]
pub fn detect_command_in_path(command: String) -> Option<String> {
    path_detection::detect_command_in_path(&command, None).map(|p| p.to_string_lossy().into_owned())
}

/// Stores the skills-repo GitHub token in the OS secure credential store
/// (Windows Credential Manager; a protected per-user file on the dev/CI
/// fallback) — never in settings.json. An empty string clears it.
#[tauri::command]
pub fn set_github_token(token: String, state: State<'_, AppState>) -> CmdResult<()> {
    token_store::save(&settings_dir(&state), &token)?;
    Ok(())
}

/// Whether a skills-repo token is currently stored. The raw token is never
/// returned to the frontend — only its presence, so the Settings UI can show
/// a "token stored" affordance.
#[tauri::command]
pub fn has_github_token(state: State<'_, AppState>) -> bool {
    token_store::is_set(&settings_dir(&state))
}

/// Sync the configured skills repo into `~/.claude/skills/managed`.
#[tauri::command]
pub async fn sync_skills_claude(app: AppHandle, state: State<'_, AppState>) -> CmdResult<()> {
    let (settings, token) = load_skills_inputs(&state)?;
    run_skills_sync(app, settings, token, SkillTool::ClaudeCode).await
}

/// Sync the configured skills repo into `~/.codex/skills/managed`.
#[tauri::command]
pub async fn sync_skills_codex(app: AppHandle, state: State<'_, AppState>) -> CmdResult<()> {
    let (settings, token) = load_skills_inputs(&state)?;
    run_skills_sync(app, settings, token, SkillTool::Codex).await
}

/// Loads the settings + token a sync needs, synchronously (touches `State`,
/// so it must finish before any `.await` — `State` references aren't held
/// across await points).
fn load_skills_inputs(state: &State<'_, AppState>) -> CmdResult<(AppSettings, String)> {
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let token = token_store::load(&settings_dir(state))?
        .ok_or_else(|| IpcError("Set a GitHub token in Settings first.".to_string()))?;
    Ok((settings, token))
}

async fn run_skills_sync(
    app: AppHandle,
    settings: AppSettings,
    token: String,
    tool: SkillTool,
) -> CmdResult<()> {
    let home = dirs::home_dir()
        .ok_or_else(|| IpcError("Could not determine your home directory.".to_string()))?;
    let git_exe = platform::resolve_git_path();

    let emit = move |event: OutputEvent| {
        let _ = app.emit("skills-sync-output", event);
    };
    skills_sync::sync(
        &git_exe,
        &settings.skills_repo_url,
        &settings.skills_repo_branch,
        &token,
        &home,
        tool,
        emit,
    )
    .await
    .map_err(|e| IpcError(e.to_string()))
}

fn settings_dir(state: &State<'_, AppState>) -> PathBuf {
    state
        .settings_path
        .parent()
        .map(std::path::Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn open_in_terminal(project_path: &str, which: &str, state: State<'_, AppState>) -> CmdResult<()> {
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let command = match which {
        "claude" => settings.claude_command.trim().to_string(),
        "opencode" => settings.opencode_command.trim().to_string(),
        "pi" => settings.pi_command.trim().to_string(),
        "codex" => settings.codex_command.trim().to_string(),
        _ => unreachable!(),
    };
    if command.is_empty() {
        return Err(IpcError(format!(
            "{which} command is empty. Set it in Settings."
        )));
    }
    let path = PathBuf::from(project_path);
    platform::launch_terminal(&path, &command, settings.terminal_kind).map_err(IpcError)?;
    Ok(())
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest);
        }
    }
    PathBuf::from(path)
}
