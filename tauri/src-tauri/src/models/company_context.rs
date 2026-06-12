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

/// A company context discovered inside an existing project.
///
/// The bmad-marketing-growth module's company-context-bootstrap workflow
/// defines the shared context as five recognized files under
/// `_bmad-output/company-context/` (every v2 agent reads them on
/// activation). The manager scans the projects folder for those files so a
/// new project can be seeded from an existing project's context instead of
/// starting from scratch. Mirrors the Swift `CompanyContext` model.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompanyContext {
    /// Name of the project folder the context was found in.
    pub project_name: String,
    /// The context folder itself (e.g. `<project>/_bmad-output/company-context`).
    pub directory: PathBuf,
    /// Recognized files present in the source, in canonical order.
    pub files: Vec<String>,
}

impl CompanyContext {
    /// Menu label: the source project name, with a hint appended when the
    /// context is missing some of the recognized files. The Svelte side
    /// mirrors this in `companyContextDisplayName` (types.ts).
    pub fn display_name(&self) -> String {
        let total = RECOGNIZED_FILE_NAMES.len();
        if self.files.len() == total {
            self.project_name.clone()
        } else {
            format!(
                "{} ({} of {} context files)",
                self.project_name,
                self.files.len(),
                total
            )
        }
    }
}
