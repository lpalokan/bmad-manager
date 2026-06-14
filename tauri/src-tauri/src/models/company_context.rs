use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// The file names the bmad-marketing-growth module's
/// company-context-bootstrap workflow recognizes, in canonical order.
/// Anything else in a context folder (e.g. `bootstrap-summary.md`) is
/// ignored, matching the workflow's own import rules.
pub const RECOGNIZED_FILE_NAMES: [&str; 5] = [
    "icp.md",
    "positioning.md",
    "brand-voice.md",
    "kpis.md",
    "tech-stack.md",
];

/// Where a discovered company context came from, used to badge the picker.
///
/// Native menus can't embed image assets, so each source gets a trailing
/// emoji marker: a folder (matching the project list's "open folder"
/// button) for project-local contexts, and an octopus standing in for the
/// GitHub octocat for contexts pulled from the shared skills repo's
/// `context/` folder. Mirrors the Swift `CompanyContextSource`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum ContextSource {
    #[default]
    Project,
    Github,
}

impl ContextSource {
    pub fn marker(self) -> &'static str {
        match self {
            ContextSource::Project => "📂",
            ContextSource::Github => "🐙",
        }
    }
}

/// A company context discovered inside an existing project or the skills repo.
///
/// The bmad-marketing-growth module's company-context-bootstrap workflow
/// defines the shared context as five recognized files under
/// `_bmad-output/company-context/` (every v2 agent reads them on
/// activation). The manager scans the projects folder for those files — and
/// the skills repo's top-level `context/` folder — so a new project can be
/// seeded from an existing context instead of starting from scratch. Mirrors
/// the Swift `CompanyContext` model.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompanyContext {
    /// Name of the project folder (or skills-repo `context/` subfolder) the
    /// context was found in.
    pub project_name: String,
    /// The context folder itself (e.g. `<project>/_bmad-output/company-context`).
    pub directory: PathBuf,
    /// Recognized files present in the source, in canonical order.
    pub files: Vec<String>,
    /// Whether the context came from a project on disk or the skills repo.
    /// Defaults to `Project` so older IPC payloads still deserialize.
    #[serde(default)]
    pub source: ContextSource,
}

impl CompanyContext {
    /// Menu label: the source name with a trailing source marker, and a hint
    /// appended when the context is missing some of the recognized files. The
    /// Svelte side mirrors this in `companyContextDisplayName` (types.ts).
    pub fn display_name(&self) -> String {
        let total = RECOGNIZED_FILE_NAMES.len();
        let base = if self.files.len() == total {
            self.project_name.clone()
        } else {
            format!(
                "{} ({} of {} context files)",
                self.project_name,
                self.files.len(),
                total
            )
        };
        format!("{} {}", base, self.source.marker())
    }
}
