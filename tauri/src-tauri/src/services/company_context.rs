//! Resolves company contexts inside projects and copies one into a new
//! project. Port of the Swift `CompanyContextService`.
//!
//! The resolution order inside each project mirrors the
//! company-context-bootstrap workflow's own rules: prefer
//! `_bmad-output/company-context`, fall back to a top-level
//! `company-context`. A project counts as having a context when its
//! context folder holds at least one file — every file is part of the
//! context, not just the canonical names, so user-added files seed across
//! too.
//!
//! Walking the projects folder is deliberately NOT this module's job —
//! `project_service::list_projects` is the one place that knows what
//! counts as a project folder; callers hand the resulting `ProjectItem`s
//! in.

use std::path::Path;

use thiserror::Error;

use crate::models::company_context::RECOGNIZED_FILE_NAMES;
use crate::models::{CompanyContext, ContextSource, ProjectItem};

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
/// none of the expected locations holds any context files.
pub fn context_in_project(project_path: &Path) -> Option<CompanyContext> {
    let project_name = project_path.file_name()?.to_string_lossy().into_owned();
    for subpath in CONTEXT_SUBPATHS {
        let dir = project_path.join(subpath);
        let present = context_files(&dir);
        if !present.is_empty() {
            return Some(CompanyContext {
                project_name,
                directory: dir,
                files: present,
                source: ContextSource::Project,
            });
        }
    }
    None
}

/// Resolves the contexts published in the shared skills repo's top-level
/// `context/` folder (a sibling of the `skills/` folder). Each immediate
/// subdirectory holding at least one file is offered as a seeding source,
/// tagged `Github`. Sorted by name (lowercased).
pub fn github_contexts_in(repo_root: &Path) -> Vec<CompanyContext> {
    let context_root = repo_root.join("context");
    let mut contexts = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&context_root) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let dir = entry.path();
            if !dir.is_dir() {
                continue;
            }
            let present = context_files(&dir);
            if present.is_empty() {
                continue;
            }
            contexts.push(CompanyContext {
                project_name: name,
                directory: dir,
                files: present,
                source: ContextSource::Github,
            });
        }
    }
    contexts.sort_by_key(|c| c.project_name.to_lowercase());
    contexts
}

/// Lists every file in a context folder: the recognized names first in
/// canonical order (so the seed picker stays stable and predictable), then
/// any other files alphabetically (case-insensitive). Hidden files and
/// recognized top-level names first in canonical order (so the seed picker
/// stays stable), then any other files — including nested ones — by relative
/// path alphabetically. Paths are relative to `dir` with "/" separators
/// (e.g. "research/notes.md"). Hidden files and hidden directories are
/// skipped and not descended into. Empty when `dir` doesn't exist or holds
/// no files. Mirrors the Swift `contextFiles(in:)`.
fn context_files(dir: &Path) -> Vec<String> {
    let mut rel_paths = Vec::new();
    collect_context_files(dir, dir, &mut rel_paths);

    let recognized: Vec<String> = RECOGNIZED_FILE_NAMES
        .iter()
        .filter(|name| rel_paths.iter().any(|p| p == *name))
        .map(|name| name.to_string())
        .collect();
    let mut extras: Vec<String> = rel_paths
        .into_iter()
        .filter(|p| !RECOGNIZED_FILE_NAMES.contains(&p.as_str()))
        .collect();
    extras.sort_by_key(|p| p.to_lowercase());

    [recognized, extras].concat()
}

/// Recursively collects regular files under `dir` as paths relative to
/// `root`, using "/" separators. Hidden files and directories (dot-prefixed)
/// are skipped and not descended into.
fn collect_context_files(root: &Path, dir: &Path, out: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        let path = entry.path();
        if file_type.is_dir() {
            collect_context_files(root, &path, out);
        } else if file_type.is_file() {
            if let Ok(rel) = path.strip_prefix(root) {
                out.push(rel.to_string_lossy().replace('\\', "/"));
            }
        }
    }
}

/// Copies all of the context's files into
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
        // Recreate the file's subfolder (e.g. "research/") before copying so
        // nested context files land at the same relative path.
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent).map_err(ContextImportError::CreateDirFailed)?;
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
