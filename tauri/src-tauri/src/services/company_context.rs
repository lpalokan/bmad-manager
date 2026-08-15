//! Resolves company contexts inside projects and copies one into a new
//! project. Port of the Swift `CompanyContextService`.
//!
//! The resolution order inside each project mirrors the
//! company-context-bootstrap workflow's own rules: prefer
//! `output/company-context` (the canonical marketing-growth layout since
//! v2.4), then the legacy `_bmad-output/company-context`, then a top-level
//! `company-context`. A project counts as having a context when its
//! context folder holds at least one file — every file is part of the
//! context, not just the canonical names, so user-added files seed across
//! too.
//!
//! Reading is deliberately broad and writing is not: a seeded context
//! always lands in `output/company-context` (see [`import_context`]), so
//! new projects start on the canonical name while projects on either older
//! layout keep resolving in place. Nothing is ever moved.
//!
//! Walking the projects folder is deliberately NOT this module's job —
//! `project_service::list_projects` is the one place that knows what
//! counts as a project folder; callers hand the resulting `ProjectItem`s
//! in.

use std::collections::HashMap;
use std::path::Path;

use thiserror::Error;

use crate::models::company_context::RECOGNIZED_FILE_NAMES;
use crate::models::{CompanyContext, ContextSource, ProjectItem};

/// Every layout a context is read from, canonical first. The first entry is
/// also the one [`import_context`] writes to.
const CONTEXT_SUBPATHS: [&str; 3] = [
    "output/company-context",
    "_bmad-output/company-context",
    "company-context",
];

/// Hidden folder inside a context holding copies of files a refresh was about
/// to overwrite, one sub-folder per refresh. Dot-prefixed so `context_files`
/// skips it — backups must never become part of the context they protect.
pub const BACKUP_DIR_NAME: &str = ".bmad-context-backup";

/// Hidden marker recording which skills-repo pack a context was seeded from,
/// so resolution is a lookup rather than an inference. Also dot-prefixed, and
/// for the same reason.
pub const SOURCE_MARKER_NAME: &str = ".bmad-context-source.json";

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
/// `<project_path>/output/company-context/` — the canonical layout,
/// whichever layout the source used. Files already present at the
/// destination are left untouched — the manager never overwrites silently
/// (the bootstrap workflow's behavioural contract); re-running the workflow
/// in the new project handles refreshes interactively.
pub fn import_context(
    context: &CompanyContext,
    project_path: &Path,
) -> Result<(), ContextImportError> {
    let dest_dir = project_path.join("output").join("company-context");
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
    // Record where these files came from, so a later drift check is a lookup
    // instead of a guess at the tags. Only meaningful for a skills-repo pack —
    // seeding from another project carries no upstream to refresh from.
    if context.source == ContextSource::Github {
        write_context_source(&dest_dir, &context.project_name)?;
    }
    Ok(())
}

/// Reads the pack name recorded by [`write_context_source`], or `None` when no
/// marker is present (every project seeded before #103) or it can't be parsed.
pub fn read_context_source(context_dir: &Path) -> Option<String> {
    let text = std::fs::read_to_string(context_dir.join(SOURCE_MARKER_NAME)).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    let name = value.get("name")?.as_str()?.trim().to_string();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

/// Records `name` as the skills-repo pack this context was seeded from.
fn write_context_source(context_dir: &Path, name: &str) -> Result<(), ContextImportError> {
    std::fs::create_dir_all(context_dir).map_err(ContextImportError::CreateDirFailed)?;
    let body = serde_json::json!({ "name": name }).to_string();
    std::fs::write(context_dir.join(SOURCE_MARKER_NAME), body).map_err(|err| {
        ContextImportError::CopyFailed {
            file: SOURCE_MARKER_NAME.to_string(),
            reason: err.to_string(),
        }
    })
}

// --- Context drift vs the skills repo (issue #92) -----------------------
//
// A project's company-context is seeded from a skills-repo context at
// create time (see `import_context`) and drifts behind when the maintainer
// edits that context. Drift is read from the OKF `last_updated` date the
// context files carry (always bumped on edit), falling back to a byte
// comparison for files without a date. A project is linked back to its
// source context by the OKF `tags` slug its own files carry, so no marker
// file is needed and existing projects work.

/// The slice of an OKF context file's YAML frontmatter drift detection
/// needs: the declared edit date and the tags (which carry the
/// source-context slug). Absent fields stay empty.
#[derive(Default)]
struct OkfMeta {
    last_updated: Option<String>,
    tags: Vec<String>,
}

/// Parses the leading `---`-fenced YAML frontmatter for just `last_updated`
/// and `tags`. Only a `---` on the first line opens the block; parsing stops
/// at the closing `---`. `tags` is read as a flow sequence (`[a, b, c]`), the
/// only form OKF uses. A file without frontmatter yields an empty meta.
fn parse_okf_meta(text: &str) -> OkfMeta {
    let mut meta = OkfMeta::default();
    let mut lines = text.lines();
    if lines.next().map(str::trim) != Some("---") {
        return meta;
    }
    for raw in lines {
        let line = raw.trim();
        if line == "---" {
            break;
        }
        if let Some(rest) = line.strip_prefix("last_updated:") {
            let value = unquote(rest.trim());
            if !value.is_empty() {
                meta.last_updated = Some(value);
            }
        } else if let Some(rest) = line.strip_prefix("tags:") {
            meta.tags = parse_flow_list(rest.trim());
        }
    }
    meta
}

/// Splits an inline YAML flow sequence `[a, b, c]` into trimmed, unquoted,
/// non-empty entries. A bare (non-bracketed) value becomes a single entry.
fn parse_flow_list(value: &str) -> Vec<String> {
    let inner = value
        .strip_prefix('[')
        .and_then(|v| v.strip_suffix(']'))
        .unwrap_or(value);
    inner
        .split(',')
        .map(|t| unquote(t.trim()))
        .filter(|t| !t.is_empty())
        .collect()
}

fn unquote(value: &str) -> String {
    let bytes = value.as_bytes();
    if bytes.len() >= 2 {
        let (first, last) = (bytes[0], bytes[bytes.len() - 1]);
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.to_string()
}

/// Parses an ISO `YYYY-MM-DD` date into a comparable tuple, or `None` when it
/// isn't exactly three numeric components.
fn parse_ymd(value: &str) -> Option<(u32, u32, u32)> {
    let mut parts = value.trim().split('-');
    let y = parts.next()?.parse().ok()?;
    let m = parts.next()?.parse().ok()?;
    let d = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((y, m, d))
}

/// Resolves which of `sources` a project's context was seeded from, by
/// matching the OKF `tags` slug embedded in the project's own files against
/// the source context names. Returns `None` when nothing matches or the match
/// is ambiguous — the project then has no upstream to refresh from and is
/// treated as not context-stale (module-only).
pub fn source_context_for<'a>(
    project_ctx: &CompanyContext,
    sources: &'a [CompanyContext],
) -> Option<&'a CompanyContext> {
    if sources.is_empty() {
        return None;
    }
    // A marker written at seed/refresh time settles it outright. A marker
    // naming a pack that is no longer published falls through to the vote
    // rather than giving up — the tags may still resolve it.
    if let Some(name) = read_context_source(&project_ctx.directory) {
        if let Some(found) = sources.iter().find(|s| s.project_name == name) {
            return Some(found);
        }
    }
    // Otherwise vote, top-level files first: a pack bundled in a sub-folder
    // carries its own identity tags and would otherwise outvote the pack the
    // project was actually seeded from. Falling back to every file keeps a
    // context whose files all live in sub-folders resolvable.
    let top_level: Vec<&String> = project_ctx
        .files
        .iter()
        .filter(|f| !f.contains('/'))
        .collect();
    let mut votes = tally(project_ctx, sources, &top_level);
    // Only when the top level named nothing at all — a context whose files
    // all live in sub-folders. A top-level *tie* is a genuine ambiguity and
    // must not be broken by letting sub-folders vote after the fact.
    if votes.is_empty() {
        let all: Vec<&String> = project_ctx.files.iter().collect();
        votes = tally(project_ctx, sources, &all);
    }

    let best = votes.values().copied().max()?;
    let mut leaders = votes.iter().filter(|(_, count)| **count == best);
    let (name, _) = leaders.next()?;
    if leaders.next().is_some() {
        return None; // an even split — don't guess
    }
    sources.iter().find(|s| s.project_name == *name)
}

/// Counts, per published pack, how many of `files` carry that pack's name as
/// an OKF tag. A tag is a vote only when it matches a published pack, so
/// subject keywords naming nothing published are ignored — and one file
/// naming another vertical as its subject cannot outweigh the pack's own
/// identity across the rest of the bundle.
fn tally<'a>(
    project_ctx: &CompanyContext,
    sources: &'a [CompanyContext],
    files: &[&String],
) -> HashMap<&'a str, usize> {
    let mut votes: HashMap<&str, usize> = HashMap::new();
    for file in files {
        let Ok(text) = std::fs::read_to_string(project_ctx.directory.join(file)) else {
            continue;
        };
        let tags = parse_okf_meta(&text).tags;
        for source in sources {
            if tags.contains(&source.project_name) {
                *votes.entry(source.project_name.as_str()).or_default() += 1;
            }
        }
    }
    votes
}

/// True when the project's context has drifted behind `source`: any file the
/// source carries that the project lacks, or whose source OKF `last_updated`
/// is a strictly later date than the project's copy. Files without a
/// comparable date on either side fall back to a byte comparison, so an edit
/// that didn't bump the date is still caught. Project-only files never count
/// — refresh is overwrite+add, never delete.
pub fn is_context_stale(project_ctx: &CompanyContext, source: &CompanyContext) -> bool {
    for file in &source.files {
        let dest = project_ctx.directory.join(file);
        if !dest.exists() {
            return true;
        }
        let (Ok(src_text), Ok(dst_text)) = (
            std::fs::read_to_string(source.directory.join(file)),
            std::fs::read_to_string(&dest),
        ) else {
            continue;
        };
        let src_date = parse_okf_meta(&src_text)
            .last_updated
            .and_then(|d| parse_ymd(&d));
        let dst_date = parse_okf_meta(&dst_text)
            .last_updated
            .and_then(|d| parse_ymd(&d));
        match (src_date, dst_date) {
            (Some(s), Some(d)) => {
                if s > d {
                    return true;
                }
            }
            // A missing/unparseable date on either side: trust the bytes.
            _ => {
                if src_text != dst_text {
                    return true;
                }
            }
        }
    }
    false
}

/// True when `project_path`'s context should be offered a refresh from the
/// skills-repo `sources`: it resolves to one of them and has drifted behind
/// it. Drives the single Update button alongside module staleness.
pub fn is_project_context_stale(project_path: &Path, sources: &[CompanyContext]) -> bool {
    let Some(project_ctx) = context_in_project(project_path) else {
        return false;
    };
    let Some(source) = source_context_for(&project_ctx, sources) else {
        return false;
    };
    is_context_stale(&project_ctx, source)
}

/// Overwrites `dest_dir`'s context with `source`'s files — copying every
/// source file over the destination's copy and adding any it lacks, but never
/// deleting destination-only files. The refresh counterpart to
/// [`import_context`] (which skips existing files at create time): the "bring
/// an existing project current with the skills repo" path.
///
/// Every file whose content would change is copied into
/// `<dest_dir>/{BACKUP_DIR_NAME}/<backup_stamp>/` first, so a refresh can
/// never destroy a local edit. `backup_stamp` names that run's folder; the app
/// passes a timestamp, tests a fixed string.
pub fn refresh_context(
    source: &CompanyContext,
    dest_dir: &Path,
    backup_stamp: &str,
) -> Result<RefreshSummary, ContextImportError> {
    std::fs::create_dir_all(dest_dir).map_err(ContextImportError::CreateDirFailed)?;
    let backup_root = dest_dir.join(BACKUP_DIR_NAME).join(backup_stamp);
    let mut summary = RefreshSummary::default();

    for file in &source.files {
        let destination = dest_dir.join(file);
        let incoming = read_bytes(&source.directory.join(file), file)?;
        let existing = std::fs::read(&destination).ok();

        // Already identical: nothing to write, and nothing worth preserving.
        // Skipping also keeps mtimes stable for an up-to-date project.
        if existing.as_deref() == Some(incoming.as_slice()) {
            continue;
        }
        // Anything whose bytes are about to change is copied aside first. We
        // cannot tell a user's edit from a merely stale copy without a
        // baseline, so we preserve both — a redundant backup is cheap, a lost
        // edit is not.
        if let Some(current) = existing {
            let backup_path = backup_root.join(file);
            create_parent(&backup_path)?;
            std::fs::write(&backup_path, &current).map_err(|err| {
                ContextImportError::CopyFailed {
                    file: file.clone(),
                    reason: err.to_string(),
                }
            })?;
            summary.backed_up.push(file.clone());
        }
        create_parent(&destination)?;
        std::fs::write(&destination, &incoming).map_err(|err| ContextImportError::CopyFailed {
            file: file.clone(),
            reason: err.to_string(),
        })?;
        summary.written.push(file.clone());
    }

    // Stamp the marker so a project seeded before #103 becomes self-describing
    // the first time it is refreshed.
    write_context_source(dest_dir, &source.project_name)?;
    Ok(summary)
}

/// What a [`refresh_context`] run changed, for the output panel.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct RefreshSummary {
    pub written: Vec<String>,
    pub backed_up: Vec<String>,
}

fn read_bytes(path: &Path, file: &str) -> Result<Vec<u8>, ContextImportError> {
    std::fs::read(path).map_err(|err| ContextImportError::CopyFailed {
        file: file.to_string(),
        reason: err.to_string(),
    })
}

fn create_parent(path: &Path) -> Result<(), ContextImportError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(ContextImportError::CreateDirFailed)?;
    }
    Ok(())
}

// Tests for company_context are scenario-style and live in the BDD
// harness (tests/features/company_context.feature).
