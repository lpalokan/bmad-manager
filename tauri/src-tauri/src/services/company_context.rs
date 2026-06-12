//! Resolves company contexts inside projects and copies one into a new
//! project. Port of the Swift `CompanyContextService`.
//!
//! The resolution order inside each project mirrors the
//! company-context-bootstrap workflow's own rules: prefer
//! `_bmad-output/company-context`, fall back to a top-level
//! `company-context`. A project counts as having a context when at least
//! one of `RECOGNIZED_FILE_NAMES` is present there.
//!
//! Walking the projects folder is deliberately NOT this module's job —
//! `project_service::list_projects` is the one place that knows what
//! counts as a project folder; callers hand the resulting `ProjectItem`s
//! in.

use std::path::Path;

use thiserror::Error;

use crate::models::company_context::RECOGNIZED_FILE_NAMES;
use crate::models::{CompanyContext, ProjectItem};

const CONTEXT_SUBPATHS: [&str; 2] = ["_bmad-output/company-context", "company-context"];

#[derive(Debug, Error)]
pub enum ContextImportError {
    #[error("Creating the context folder failed: {0}")]
    CreateDirFailed(std::io::Error),
    #[error("Copying '{file}' failed: {reason}")]
    CopyFailed { file: String, reason: String },
}

/// Resolves the context of each given project, sorted by project name
/// (the picker's order, independent of the caller's project sort).
pub fn contexts_in(projects: &[ProjectItem]) -> Vec<CompanyContext> {
    let mut contexts: Vec<CompanyContext> = projects
        .iter()
        .filter_map(|p| context_in_project(p.path()))
        .collect();
    contexts.sort_by_key(|c| c.project_name.to_lowercase());
    contexts
}

/// Returns the context found in a single project folder, or `None` when
/// none of the expected locations contains a recognized file.
pub fn context_in_project(project_path: &Path) -> Option<CompanyContext> {
    let project_name = project_path.file_name()?.to_string_lossy().into_owned();
    for subpath in CONTEXT_SUBPATHS {
        let dir = project_path.join(subpath);
        let present: Vec<String> = RECOGNIZED_FILE_NAMES
            .iter()
            .filter(|name| dir.join(name).is_file())
            .map(|name| name.to_string())
            .collect();
        if !present.is_empty() {
            return Some(CompanyContext {
                project_name,
                directory: dir,
                files: present,
            });
        }
    }
    None
}

/// Copies the context's recognized files into
/// `<project_path>/_bmad-output/company-context/`. Files already present
/// at the destination are left untouched — the manager never overwrites
/// silently (the bootstrap workflow's behavioural contract); re-running
/// the workflow in the new project handles refreshes interactively.
pub fn import_context(
    context: &CompanyContext,
    project_path: &Path,
) -> Result<(), ContextImportError> {
    let dest_dir = project_path.join("_bmad-output").join("company-context");
    std::fs::create_dir_all(&dest_dir).map_err(ContextImportError::CreateDirFailed)?;

    for file in &context.files {
        let destination = dest_dir.join(file);
        if destination.exists() {
            continue;
        }
        std::fs::copy(context.directory.join(file), &destination).map_err(|err| {
            ContextImportError::CopyFailed {
                file: file.clone(),
                reason: err.to_string(),
            }
        })?;
    }
    Ok(())
}

// Tests for company_context are scenario-style and live in the BDD
// harness (tests/features/company_context.feature).
