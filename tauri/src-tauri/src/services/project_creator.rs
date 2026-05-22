use std::path::PathBuf;

use thiserror::Error;

use crate::models::{AppSettings, ModuleSourceKind, ProjectItem};
use crate::platform;
use crate::services::command_runner::OutputEvent;
use crate::services::{command_runner, git_source, init_command, project_service, zip_source};

#[derive(Debug, Error)]
pub enum ProjectCreationError {
    #[error(transparent)]
    Project(#[from] project_service::ProjectError),
    #[error(transparent)]
    Zip(#[from] zip_source::ZipError),
    #[error(transparent)]
    Git(#[from] git_source::GitError),
    #[error("Init command exited with code {0}. See the output panel for details.")]
    InitCommandFailed(i32),
}

/// Full project-creation pipeline: validate name, mkdir under
/// `settings.projects_root`, materialise the module (git clone or zip
/// extract), substitute placeholders, run the init command streaming
/// output via `on_event`, clean up temp dirs.
pub async fn create_project<F>(
    name: &str,
    settings: &AppSettings,
    mut on_event: F,
) -> Result<ProjectItem, ProjectCreationError>
where
    F: FnMut(OutputEvent) + Send,
{
    let projects_root = expand_tilde(&settings.projects_root);
    let project_path = project_service::create_project_folder(name, &projects_root)?;

    let module_dir = materialise_module(settings).await?;
    let module_root_path = zip_source::module_root(&module_dir);

    let command = init_command::substitute(
        &settings.init_command,
        name,
        &project_path.to_string_lossy(),
        &module_root_path.to_string_lossy(),
        cfg!(target_os = "windows"),
    );

    let exit_code = command_runner::run(&command, &project_path, &mut on_event).await;

    // Cleanup the temp module dir whether the init succeeded or not so
    // we don't leak gigabytes of clones across repeated failed runs.
    zip_source::cleanup(&module_dir);

    if exit_code != 0 {
        return Err(ProjectCreationError::InitCommandFailed(exit_code));
    }

    let created_at = std::fs::metadata(&project_path)
        .ok()
        .and_then(|m| m.created().ok());
    Ok(ProjectItem::new(project_path, created_at))
}

async fn materialise_module(settings: &AppSettings) -> Result<PathBuf, ProjectCreationError> {
    match settings.module_source_kind {
        ModuleSourceKind::GitRepo => {
            let dest = git_source::fresh_tempdir();
            let git_exe = platform::resolve_git_path();
            git_source::clone(
                &git_exe,
                &settings.module_repo_url,
                &settings.module_repo_ref,
                &dest,
            )?;
            Ok(dest)
        }
        ModuleSourceKind::LocalZip => Ok(zip_source::extract_zip(&settings.module_zip_path)?),
    }
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest);
        }
    }
    PathBuf::from(path)
}

// Tests for project_creator are scenario-style and live in the BDD
// harness (they require spawning processes and would be flaky here).
