use std::path::{Path, PathBuf};
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectItem {
    pub name: String,
    pub path: PathBuf,
    /// Unix epoch seconds; `None` when the filesystem doesn't report a
    /// creation date (rare on Windows/macOS, common on some Linux FSes).
    pub created_at: Option<i64>,
}

impl ProjectItem {
    pub fn new(path: PathBuf, created_at: Option<SystemTime>) -> Self {
        let name = path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        let epoch = created_at.and_then(|t| {
            t.duration_since(SystemTime::UNIX_EPOCH)
                .ok()
                .map(|d| d.as_secs() as i64)
        });
        Self {
            name,
            path,
            created_at: epoch,
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}
