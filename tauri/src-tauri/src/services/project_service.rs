use std::path::{Path, PathBuf};

use serde::Serialize;
use thiserror::Error;

use crate::models::{ProjectItem, ProjectSortOrder};

/// Marker directories that signal a folder already holds a BMAD install —
/// a stronger "init could clobber this" warning than mere non-emptiness.
const BMAD_MARKERS: [&str; 3] = ["bmad", ".bmad", "_cfg"];

#[derive(Debug, Error)]
pub enum ProjectError {
    #[error("{0}")]
    InvalidName(String),
    #[error("A folder named '{0}' already exists at the projects root.")]
    ProjectExists(String),
    #[error("Projects root '{0}' exists but is not a directory.")]
    RootNotADirectory(PathBuf),
    #[error("'{0}' is not an existing folder.")]
    FolderNotADirectory(PathBuf),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

impl ProjectError {
    pub const INVALID_NAME: &'static str = "invalid name";
    pub const PROJECT_EXISTS: &'static str = "project exists";
    pub const ROOT_NOT_A_DIRECTORY: &'static str = "root not a directory";
    pub const FOLDER_NOT_A_DIRECTORY: &'static str = "folder not a directory";
    pub const IO: &'static str = "io";

    pub fn kind_label(&self) -> &'static str {
        match self {
            ProjectError::InvalidName(_) => Self::INVALID_NAME,
            ProjectError::ProjectExists(_) => Self::PROJECT_EXISTS,
            ProjectError::RootNotADirectory(_) => Self::ROOT_NOT_A_DIRECTORY,
            ProjectError::FolderNotADirectory(_) => Self::FOLDER_NOT_A_DIRECTORY,
            ProjectError::Io(_) => Self::IO,
        }
    }
}

/// What the UI needs to decide whether initialising into an existing folder
/// warrants a destructive-overwrite confirmation. Serialised to the frontend
/// by the `inspect_init_target` command.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InitTargetInfo {
    /// The folder exists on disk.
    pub exists: bool,
    /// The folder is empty (or missing) — init can run without a prompt.
    pub is_empty: bool,
    /// The folder already looks like a BMAD install (a marker dir present).
    pub has_bmad: bool,
}

/// Validates that `folder` is an existing directory and returns the matching
/// [`ProjectItem`]. The "initialize into an existing folder" path: the folder
/// is used as-is (it must already exist and may be non-empty), so this skips
/// the must-not-exist guard `create_project_folder` applies.
pub fn use_existing_folder(folder: &Path) -> Result<ProjectItem, ProjectError> {
    if !folder.is_dir() {
        return Err(ProjectError::FolderNotADirectory(folder.to_path_buf()));
    }
    let created_at = std::fs::metadata(folder).ok().and_then(|m| m.created().ok());
    Ok(ProjectItem::new(folder.to_path_buf(), created_at))
}

/// Inspects a candidate existing-folder init target so the UI can decide
/// whether to confirm a potentially destructive overwrite. A missing folder
/// is reported as empty (nothing to overwrite yet).
pub fn inspect_init_target(folder: &Path) -> InitTargetInfo {
    let exists = folder.is_dir();
    if !exists {
        return InitTargetInfo {
            exists: false,
            is_empty: true,
            has_bmad: false,
        };
    }
    let is_empty = std::fs::read_dir(folder)
        .map(|mut entries| entries.next().is_none())
        .unwrap_or(true);
    let has_bmad = BMAD_MARKERS
        .iter()
        .any(|marker| folder.join(marker).is_dir());
    InitTargetInfo {
        exists,
        is_empty,
        has_bmad,
    }
}

/// Validates `name` and creates `<root>/<trimmed-name>` as a fresh
/// directory. Creates the root itself if it is missing (matching the
/// Swift app), which keeps first-run from failing on a freshly-installed
/// machine that has never had a Projects folder.
pub fn create_project_folder(name: &str, root: &Path) -> Result<PathBuf, ProjectError> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(ProjectError::InvalidName(
            "Project name cannot be empty.".to_string(),
        ));
    }
    if trimmed.contains('/') || trimmed.contains(':') || trimmed.contains('\\') {
        return Err(ProjectError::InvalidName(
            "Project name cannot contain '/', '\\', or ':'.".to_string(),
        ));
    }
    if trimmed.starts_with('.') {
        return Err(ProjectError::InvalidName(
            "Project name cannot start with '.'.".to_string(),
        ));
    }

    if root.exists() {
        if !root.is_dir() {
            return Err(ProjectError::RootNotADirectory(root.to_path_buf()));
        }
    } else {
        std::fs::create_dir_all(root)?;
    }

    let project = root.join(trimmed);
    if project.exists() {
        return Err(ProjectError::ProjectExists(trimmed.to_string()));
    }
    std::fs::create_dir(&project)?;
    Ok(project)
}

/// Returns every directory entry under `root` as a [`ProjectItem`],
/// sorted by `order`. Returns an empty `Vec` if `root` doesn't exist or
/// isn't readable — matching the Swift app's "silently empty list"
/// behaviour so first-run never explodes.
pub fn list_projects(root: &Path, order: ProjectSortOrder) -> Vec<ProjectItem> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    let mut items: Vec<ProjectItem> = entries
        .filter_map(|e| e.ok())
        .filter_map(|entry| {
            let metadata = entry.metadata().ok()?;
            if !metadata.is_dir() {
                return None;
            }
            let created_at = metadata.created().ok();
            Some(ProjectItem::new(entry.path(), created_at))
        })
        .collect();

    sort_projects(&mut items, order);
    items
}

pub fn sort_projects(items: &mut [ProjectItem], order: ProjectSortOrder) {
    match order {
        ProjectSortOrder::NameAscending => {
            items.sort_by_key(|p| p.name.to_lowercase());
        }
        ProjectSortOrder::DateNewestFirst => {
            items.sort_by_key(|p| std::cmp::Reverse(p.created_at));
        }
        ProjectSortOrder::DateOldestFirst => {
            items.sort_by(|a, b| match (a.created_at, b.created_at) {
                (Some(x), Some(y)) => x.cmp(&y),
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, None) => std::cmp::Ordering::Equal,
            });
        }
    }
}

/// Moves the project folder to the system trash / recycle bin. Mirrors
/// the macOS app's `NSWorkspace.shared.recycle` semantics. A failure is mapped
/// to an actionable message — the Windows shell's opaque "Some operations were
/// aborted" almost always means the folder is open somewhere.
pub fn trash_project(path: &Path) -> Result<(), String> {
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    trash::delete(path).map_err(|e| describe_trash_failure(&name, &e.to_string()))
}

/// Turns a raw trash error into something a user can act on. The Windows shell
/// reports an in-use folder as a generic "Some operations were aborted", which
/// tells the user nothing — so we explain the usual cause.
pub fn describe_trash_failure(name: &str, raw: &str) -> String {
    let base = format!("Couldn't move '{name}' to the Recycle Bin");
    if raw.contains("aborted") || raw.contains("in use") || raw.contains("being used") {
        format!(
            "{base}: the folder or a file inside it is in use. Close any terminal, \
             editor, or Explorer windows open in this project, then try again. \
             (details: {raw})"
        )
    } else {
        format!("{base}: {raw}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn trash_failure_explains_an_in_use_folder() {
        let msg = describe_trash_failure(
            "acme",
            "Unknown { description: \"Some operations were aborted\" }",
        );
        assert!(msg.contains("acme"));
        assert!(msg.contains("in use"));
        assert!(msg.contains("Close any terminal"));
    }

    #[test]
    fn trash_failure_passes_other_errors_through() {
        let msg = describe_trash_failure("acme", "permission denied");
        assert!(msg.contains("acme"));
        assert!(msg.contains("permission denied"));
        assert!(!msg.contains("Close any terminal"));
    }

    #[test]
    fn rejects_empty_and_whitespace_names() {
        let tmp = TempDir::new().unwrap();
        for candidate in ["", "   "] {
            let err = create_project_folder(candidate, tmp.path()).unwrap_err();
            assert!(matches!(err, ProjectError::InvalidName(_)));
        }
    }

    #[test]
    fn rejects_slash() {
        let tmp = TempDir::new().unwrap();
        let err = create_project_folder("a/b", tmp.path()).unwrap_err();
        assert!(matches!(err, ProjectError::InvalidName(_)));
    }

    #[test]
    fn rejects_backslash() {
        let tmp = TempDir::new().unwrap();
        let err = create_project_folder("a\\b", tmp.path()).unwrap_err();
        assert!(matches!(err, ProjectError::InvalidName(_)));
    }

    #[test]
    fn rejects_leading_dot() {
        let tmp = TempDir::new().unwrap();
        let err = create_project_folder(".hidden", tmp.path()).unwrap_err();
        assert!(matches!(err, ProjectError::InvalidName(_)));
    }

    #[test]
    fn trims_surrounding_whitespace() {
        let tmp = TempDir::new().unwrap();
        let path = create_project_folder("  spaced  ", tmp.path()).unwrap();
        assert_eq!(path.file_name().unwrap(), "spaced");
    }

    #[test]
    fn rejects_duplicate_project() {
        let tmp = TempDir::new().unwrap();
        create_project_folder("dup", tmp.path()).unwrap();
        let err = create_project_folder("dup", tmp.path()).unwrap_err();
        assert!(matches!(err, ProjectError::ProjectExists(_)));
    }

    // --- Existing-folder init (#64) ---

    #[test]
    fn accepts_existing_folder_when_target_given() {
        let tmp = TempDir::new().unwrap();
        let folder = tmp.path().join("legacy");
        std::fs::create_dir(&folder).unwrap();
        let item = use_existing_folder(&folder).unwrap();
        assert_eq!(item.path, folder);
        assert_eq!(item.name, "legacy");
    }

    #[test]
    fn rejects_existing_folder_that_is_missing() {
        let tmp = TempDir::new().unwrap();
        let err = use_existing_folder(&tmp.path().join("nope")).unwrap_err();
        assert!(matches!(err, ProjectError::FolderNotADirectory(_)));
    }

    #[test]
    fn rejects_existing_folder_that_is_a_file() {
        let tmp = TempDir::new().unwrap();
        let file = tmp.path().join("loose.txt");
        std::fs::write(&file, "x").unwrap();
        let err = use_existing_folder(&file).unwrap_err();
        assert!(matches!(err, ProjectError::FolderNotADirectory(_)));
    }

    #[test]
    fn init_target_inspection_reports_empty_folder() {
        let tmp = TempDir::new().unwrap();
        let info = inspect_init_target(tmp.path());
        assert!(info.exists);
        assert!(info.is_empty);
        assert!(!info.has_bmad);
    }

    #[test]
    fn init_target_inspection_reports_non_empty() {
        let tmp = TempDir::new().unwrap();
        std::fs::write(tmp.path().join("README.md"), "x").unwrap();
        let info = inspect_init_target(tmp.path());
        assert!(info.exists);
        assert!(!info.is_empty);
        assert!(!info.has_bmad);
    }

    #[test]
    fn init_target_inspection_detects_a_bmad_install() {
        for marker in ["bmad", ".bmad", "_cfg"] {
            let tmp = TempDir::new().unwrap();
            std::fs::create_dir(tmp.path().join(marker)).unwrap();
            let info = inspect_init_target(tmp.path());
            assert!(info.has_bmad, "expected '{marker}' to be detected");
            assert!(!info.is_empty);
        }
    }

    #[test]
    fn init_target_inspection_reports_missing_path() {
        let tmp = TempDir::new().unwrap();
        let info = inspect_init_target(&tmp.path().join("does-not-exist"));
        assert!(!info.exists);
        // A missing folder is reported empty (nothing to overwrite).
        assert!(info.is_empty);
        assert!(!info.has_bmad);
    }

    #[test]
    fn creates_root_if_missing() {
        let tmp = TempDir::new().unwrap();
        let nested = tmp.path().join("does-not-exist");
        let path = create_project_folder("p1", &nested).unwrap();
        assert!(nested.is_dir());
        assert!(path.is_dir());
    }

    #[test]
    fn list_sorts_by_name_ascending() {
        let tmp = TempDir::new().unwrap();
        for n in ["beta", "alpha", "Charlie"] {
            create_project_folder(n, tmp.path()).unwrap();
        }
        let names: Vec<String> = list_projects(tmp.path(), ProjectSortOrder::NameAscending)
            .into_iter()
            .map(|p| p.name)
            .collect();
        assert_eq!(names, ["alpha", "beta", "Charlie"]);
    }

    #[test]
    fn list_skips_files() {
        let tmp = TempDir::new().unwrap();
        create_project_folder("alpha", tmp.path()).unwrap();
        std::fs::write(tmp.path().join("loose.txt"), "x").unwrap();
        let names: Vec<String> = list_projects(tmp.path(), ProjectSortOrder::NameAscending)
            .into_iter()
            .map(|p| p.name)
            .collect();
        assert_eq!(names, ["alpha"]);
    }

    #[test]
    fn list_missing_root_returns_empty() {
        let path = std::env::temp_dir().join("bmad-manager-does-not-exist-xyzzy");
        let _ = std::fs::remove_dir_all(&path);
        assert!(list_projects(&path, ProjectSortOrder::NameAscending).is_empty());
    }

    #[test]
    fn sort_by_date_newest_first() {
        use std::time::{Duration, SystemTime};
        let mut items = vec![
            ProjectItem::new(
                "a".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(100)),
            ),
            ProjectItem::new(
                "b".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(300)),
            ),
            ProjectItem::new(
                "c".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(200)),
            ),
        ];
        sort_projects(&mut items, ProjectSortOrder::DateNewestFirst);
        let names: Vec<&str> = items.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["b", "c", "a"]);
    }

    #[test]
    fn sort_by_date_oldest_first() {
        use std::time::{Duration, SystemTime};
        let mut items = vec![
            ProjectItem::new(
                "a".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(100)),
            ),
            ProjectItem::new(
                "b".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(300)),
            ),
            ProjectItem::new(
                "c".into(),
                Some(SystemTime::UNIX_EPOCH + Duration::from_secs(200)),
            ),
        ];
        sort_projects(&mut items, ProjectSortOrder::DateOldestFirst);
        let names: Vec<&str> = items.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["a", "c", "b"]);
    }
}
