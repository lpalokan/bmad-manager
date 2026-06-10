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

use crate::models::{AppSettings, ProjectItem};
use crate::platform;
use crate::services::command_runner::OutputEvent;
use crate::services::{path_detection, project_creator, project_service, settings_store};

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
    app: AppHandle,
    state: State<'_, AppState>,
) -> CmdResult<ProjectItem> {
    let _guard = state.create_lock.lock().await;
    let settings = settings_store::load_or_init(&state.settings_path)?;
    let emit = move |event: OutputEvent| {
        let _ = app.emit("project-create-output", event);
    };
    project_creator::create_project(&name, &settings, emit)
        .await
        .map_err(|e| IpcError(e.to_string()))
}

#[tauri::command]
pub fn delete_project(path: String) -> CmdResult<()> {
    let p = PathBuf::from(&path);
    project_service::trash_project(&p).map_err(IpcError)?;
    Ok(())
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

/// Returns the absolute path the supplied command resolves to on the
/// current `PATH`, or `None` if it's not found. The Settings dialog
/// calls this per coding-agent command so the user knows whether the
/// bare-name defaults work before they need to browse for a binary.
#[tauri::command]
pub fn detect_command_in_path(command: String) -> Option<String> {
    path_detection::detect_command_in_path(&command, None).map(|p| p.to_string_lossy().into_owned())
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
