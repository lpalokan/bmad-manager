//! Re-installs the latest module over an existing project and refreshes the
//! managed AGENTS.md blocks. Sibling of `project_creator`: it shares the same
//! module-materialisation and `on_event` streaming, but targets a folder that
//! already exists and never touches the user's data under `_bmad-output/`.
//!
//! Mirrors the Swift `ProjectUpdater`.

use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::models::{AppSettings, CompanyContext, ModuleSourceKind, ProjectItem};
use crate::platform;
use crate::services::command_runner::OutputEvent;
use crate::services::{
    agents_file, command_runner, company_context, git_source, init_command, module_manifest,
    zip_source,
};

const OKF_NAMESPACE: &str = "marketing-growth:okf";
const OKF_TEMPLATE_REL: &str = "templates/agents-okf-block.md";

#[derive(Debug, Error)]
pub enum ProjectUpdateError {
    #[error(transparent)]
    Zip(#[from] zip_source::ZipError),
    #[error(transparent)]
    Git(#[from] git_source::GitError),
    #[error("Update command exited with code {0}. See the output panel for details.")]
    InitCommandFailed(i32),
}

/// Materialises a fresh module clone, re-runs the init command over the
/// existing project folder, then re-injects both managed AGENTS.md blocks from
/// that clone. The install is idempotent over an existing project (the same
/// path the "initialize existing folder" flow exercises), so user content
/// under `_bmad-output/` is left intact.
pub async fn update<F>(
    project: &ProjectItem,
    settings: &AppSettings,
    sources: &[CompanyContext],
    mut on_event: F,
) -> Result<(), ProjectUpdateError>
where
    F: FnMut(OutputEvent) + Send,
{
    let project_path = project.path.as_path();
    let module_dir = materialise_module(settings)?;
    let module_root_path = module_root_for(settings, &module_dir);

    // `bmad-method`'s `--custom-source` rejects Windows drive-absolute paths;
    // hand it a project-relative path it can resolve instead (no-op on POSIX).
    let module_arg = init_command::custom_source_arg(
        &module_root_path.to_string_lossy(),
        &project_path.to_string_lossy(),
        cfg!(target_os = "windows"),
    );
    // `{MODULE_SOURCE}`: repo URL for a git source (installer records repoUrl +
    // a real version), local module path for a zip source. See project_creator.
    let module_source = crate::services::project_creator::module_source_arg(settings, &module_arg);
    let command = init_command::substitute(
        &settings.init_command,
        &project.name,
        &project_path.to_string_lossy(),
        &module_source,
        &module_arg,
        cfg!(target_os = "windows"),
    );

    let exit_code = command_runner::run(&command, project_path, &mut on_event).await;

    if exit_code == 0 {
        // Refresh both managed AGENTS.md blocks from the fresh clone while it's
        // still on disk, then bring the company-context current with the skills
        // repo so the one Update button clears both module and context drift.
        refresh_agents_sections(project_path, &module_root_path);
        refresh_project_context(project_path, sources, &mut on_event);
    }

    // Clean up the temp module dir whether init succeeded or not.
    zip_source::cleanup(&module_dir);

    if exit_code != 0 {
        return Err(ProjectUpdateError::InitCommandFailed(exit_code));
    }
    Ok(())
}

/// Refreshes the managed AGENTS.md blocks for a just-(re)installed project,
/// reading the okf template from `module_root`. Best-effort: a write hiccup
/// shouldn't fail an otherwise-good re-install. Extracted so the block logic is
/// unit-testable without spawning the (platform-bound) init command.
fn refresh_agents_sections(project_path: &Path, module_root: &Path) {
    let _ = agents_file::ensure_bmad_section(project_path);
    inject_okf_block(module_root, project_path);
}

/// Injects the `marketing-growth:okf` block when the fresh clone ships
/// `templates/agents-okf-block.md`. Dormant until the companion repo adds that
/// template — silently skipped (and not an error) when it's absent.
fn inject_okf_block(module_root: &Path, project_path: &Path) {
    let Ok(body) = std::fs::read_to_string(module_root.join(OKF_TEMPLATE_REL)) else {
        return;
    };
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return;
    }
    let _ = agents_file::ensure_managed_section(project_path, "AGENTS.md", OKF_NAMESPACE, trimmed);
}

/// After a successful re-install, brings the project's company-context current
/// with the skills-repo context it was seeded from: resolves the project's
/// source among `sources` and overwrites the drifted files (overwrite+add,
/// never delete). Best-effort — like the AGENTS.md refresh, a context hiccup
/// shouldn't fail an otherwise-good re-install — and a no-op for projects with
/// no context or no resolved source.
fn refresh_project_context<F: FnMut(OutputEvent)>(
    project_path: &Path,
    sources: &[CompanyContext],
    on_event: &mut F,
) {
    let Some(project_ctx) = company_context::context_in_project(project_path) else {
        return;
    };
    let Some(source) = company_context::source_context_for(&project_ctx, sources) else {
        return;
    };
    match company_context::refresh_context(source, &project_ctx.directory) {
        Ok(()) => emit_diag(
            on_event,
            format!("refreshed company-context from '{}'", source.project_name),
        ),
        Err(err) => emit_diag(on_event, format!("company-context refresh skipped: {err}")),
    }
}

/// True when a project should be offered the single per-project Update button:
/// its installed module is behind `repo_module` (when one could be read), or
/// its company-context has drifted behind the skills-repo `sources`. Unifying
/// both causes here keeps `check_for_updates` a thin loop and lets the union be
/// tested without the platform-bound module fetch.
pub fn needs_update(
    project_path: &Path,
    repo_module: Option<&module_manifest::RepoModule>,
    sources: &[CompanyContext],
) -> bool {
    repo_module.is_some_and(|m| module_manifest::is_project_stale(project_path, m))
        || company_context::is_project_context_stale(project_path, sources)
}

/// Materialises the module repo once and reads its `module_version`, emitting
/// diagnostics through `on_event` (clone/extract outcome, the parsed
/// code/version, or the reason it couldn't be read). Drives the version check.
/// The events let `check_for_updates` stream *why* a check came back empty to
/// the output panel, so a failed check on Windows is diagnosable rather than
/// indistinguishable from "up to date" — the shape the missing-Update-button
/// report took. Best-effort: any failure (offline, git missing, unreadable
/// repo) yields `None`.
pub fn read_latest_repo_module_logged<F: FnMut(OutputEvent)>(
    settings: &AppSettings,
    mut on_event: F,
) -> Option<module_manifest::RepoModule> {
    let module_dir = match materialise_module(settings) {
        Ok(dir) => dir,
        Err(err) => {
            emit_diag(
                &mut on_event,
                format!("update check: module fetch failed: {err}"),
            );
            return None;
        }
    };
    let module_root = module_root_for(settings, &module_dir);
    let repo = module_manifest::read_repo_module(&module_root);
    match &repo {
        Some(m) => emit_diag(
            &mut on_event,
            format!("update check: latest {} = {}", m.code, m.version),
        ),
        None => emit_diag(
            &mut on_event,
            format!(
                "update check: could not read code/module_version from {}/skills/module.yaml",
                module_root.display()
            ),
        ),
    }
    zip_source::cleanup(&module_dir);
    repo
}

/// Non-logging convenience wrapper over [`read_latest_repo_module_logged`].
pub fn read_latest_repo_module(settings: &AppSettings) -> Option<module_manifest::RepoModule> {
    read_latest_repo_module_logged(settings, |_| {})
}

/// Resolves the module root inside a freshly materialised source dir. A git
/// clone's root *is* the module root — the repo content sits at the top level
/// (see `git_source::clone`) — so it's read directly. Only a zip extract
/// carries the GitHub "Download ZIP" wrapper folder that
/// [`zip_source::module_root`] descends into. Applying that descent to a git
/// clone is wrong: a repo whose sole top-level entry is one directory (e.g.
/// just `skills/`) gets mistaken for a wrapper and descended into, hiding
/// `skills/module.yaml` so the version check reads nothing and shows no Update
/// button.
fn module_root_for(settings: &AppSettings, module_dir: &Path) -> PathBuf {
    match settings.module_source_kind {
        ModuleSourceKind::GitRepo => module_dir.to_path_buf(),
        ModuleSourceKind::LocalZip => zip_source::module_root(module_dir),
    }
}

fn emit_diag<F: FnMut(OutputEvent)>(on_event: &mut F, message: String) {
    on_event(OutputEvent::Stderr {
        line: format!("[bmad] {message}"),
    });
}

fn materialise_module(settings: &AppSettings) -> Result<PathBuf, ProjectUpdateError> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn seed_okf_template(module: &Path, body: &str) {
        let templates = module.join("templates");
        std::fs::create_dir_all(&templates).unwrap();
        std::fs::write(templates.join("agents-okf-block.md"), body).unwrap();
    }

    #[test]
    fn refresh_writes_bmad_block_without_okf() {
        let proj = TempDir::new().unwrap();
        let module = TempDir::new().unwrap();
        refresh_agents_sections(proj.path(), module.path());
        let text = std::fs::read_to_string(proj.path().join("AGENTS.md")).unwrap();
        assert!(text.contains(agents_file::BMAD_SECTION_MARKER));
        assert!(text.contains(".agents/skills"));
        assert!(!text.contains("marketing-growth:okf"));
    }

    #[test]
    fn refresh_injects_okf_when_template_present() {
        let proj = TempDir::new().unwrap();
        let module = TempDir::new().unwrap();
        seed_okf_template(module.path(), "Use the company-context OKF bundle.");
        refresh_agents_sections(proj.path(), module.path());
        let text = std::fs::read_to_string(proj.path().join("AGENTS.md")).unwrap();
        assert!(text.contains(&agents_file::start_marker("marketing-growth:okf")));
        assert!(text.contains("Use the company-context OKF bundle."));
        assert!(text.contains(agents_file::BMAD_SECTION_MARKER));
    }

    #[test]
    fn refresh_skips_blank_okf_template() {
        let proj = TempDir::new().unwrap();
        let module = TempDir::new().unwrap();
        seed_okf_template(module.path(), "   \n");
        refresh_agents_sections(proj.path(), module.path());
        let text = std::fs::read_to_string(proj.path().join("AGENTS.md")).unwrap();
        assert!(!text.contains("marketing-growth:okf"));
    }
}
