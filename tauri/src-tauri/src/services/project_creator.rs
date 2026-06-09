use std::path::PathBuf;

use thiserror::Error;

use crate::models::{AppSettings, CompanyContext, ModuleSourceKind, ProjectItem};
use crate::platform;
use crate::services::command_runner::OutputEvent;
use crate::services::{
    command_runner, company_context, git_source, init_command, project_service, zip_source,
};

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
    #[error("Project created, but importing the context from '{source_project}' failed: {reason}")]
    ContextImportFailed {
        source_project: String,
        reason: String,
    },
}

/// Full project-creation pipeline: validate name, mkdir under
/// `settings.projects_root`, materialise the module (git clone or zip
/// extract), substitute placeholders, run the init command streaming
/// output via `on_event`, clean up temp dirs.
pub async fn create_project<F>(
    name: &str,
    settings: &AppSettings,
    import_context_from: Option<&CompanyContext>,
    mut on_event: F,
) -> Result<ProjectItem, ProjectCreationError>
where
    F: FnMut(OutputEvent) + Send,
{
    emit_diag(
        &mut on_event,
        format!(
            "create_project name={name:?} module_source={:?} repo_url={:?} repo_ref={:?} zip_path={:?}",
            settings.module_source_kind,
            settings.module_repo_url,
            settings.module_repo_ref,
            settings.module_zip_path,
        ),
    );

    let projects_root = expand_tilde(&settings.projects_root);
    emit_diag(
        &mut on_event,
        format!(
            "projects_root={} (exists={})",
            projects_root.display(),
            projects_root.exists()
        ),
    );

    let project_path = project_service::create_project_folder(name, &projects_root)?;
    emit_diag(
        &mut on_event,
        format!(
            "project_path={} (exists={})",
            project_path.display(),
            project_path.exists()
        ),
    );

    let module_dir = materialise_module(settings, &mut on_event).await?;
    let module_root_path = zip_source::module_root(&module_dir);
    emit_diag(
        &mut on_event,
        format!(
            "module_dir={} module_root={} (exists={})",
            module_dir.display(),
            module_root_path.display(),
            module_root_path.exists()
        ),
    );

    let command = init_command::substitute(
        &settings.init_command,
        name,
        &project_path.to_string_lossy(),
        &module_root_path.to_string_lossy(),
        cfg!(target_os = "windows"),
    );
    emit_diag(&mut on_event, format!("init_command={command}"));

    let exit_code = command_runner::run(&command, &project_path, &mut on_event).await;
    emit_diag(&mut on_event, format!("init_command exit_code={exit_code}"));

    // Cleanup the temp module dir whether the init succeeded or not so
    // we don't leak gigabytes of clones across repeated failed runs.
    zip_source::cleanup(&module_dir);

    if exit_code != 0 {
        return Err(ProjectCreationError::InitCommandFailed(exit_code));
    }

    // Seed the company context only after the init command succeeded — a
    // failed init keeps the project folder for inspection (partial-state
    // policy) but should not look half-bootstrapped.
    if let Some(context) = import_context_from {
        emit_diag(
            &mut on_event,
            format!(
                "importing company context from {:?} ({} files)",
                context.project_name,
                context.files.len()
            ),
        );
        company_context::import_context(context, &project_path).map_err(|err| {
            ProjectCreationError::ContextImportFailed {
                source_project: context.project_name.clone(),
                reason: err.to_string(),
            }
        })?;
    }

    let created_at = std::fs::metadata(&project_path)
        .ok()
        .and_then(|m| m.created().ok());
    Ok(ProjectItem::new(project_path, created_at))
}

fn emit_diag<F>(on_event: &mut F, message: String)
where
    F: FnMut(OutputEvent),
{
    on_event(OutputEvent::Stderr {
        line: format!("[bmad] {message}"),
    });
}

async fn materialise_module<F>(
    settings: &AppSettings,
    on_event: &mut F,
) -> Result<PathBuf, ProjectCreationError>
where
    F: FnMut(OutputEvent),
{
    match settings.module_source_kind {
        ModuleSourceKind::GitRepo => {
            let dest = git_source::fresh_tempdir();
            let git_exe = platform::resolve_git_path();
            emit_diag(
                on_event,
                format!(
                    "git clone {url:?} ref={r:?} via {git} (exists={ok}) into {dest}",
                    url = settings.module_repo_url,
                    r = settings.module_repo_ref,
                    git = git_exe.display(),
                    ok = git_exe.exists(),
                    dest = dest.display(),
                ),
            );
            git_source::clone(
                &git_exe,
                &settings.module_repo_url,
                &settings.module_repo_ref,
                &dest,
            )?;
            emit_diag(
                on_event,
                format!(
                    "git clone succeeded — dest exists={} files={}",
                    dest.exists(),
                    dest.read_dir().map(|d| d.count()).unwrap_or(0)
                ),
            );
            Ok(dest)
        }
        ModuleSourceKind::LocalZip => {
            emit_diag(
                on_event,
                format!("extracting zip {}", settings.module_zip_path),
            );
            Ok(zip_source::extract_zip(&settings.module_zip_path)?)
        }
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
