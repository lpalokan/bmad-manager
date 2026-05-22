use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::models::{ProjectItem, ProjectSortOrder};

#[derive(Debug, Error)]
pub enum ProjectError {
    #[error("{0}")]
    InvalidName(String),
    #[error("A folder named '{0}' already exists at the projects root.")]
    ProjectExists(String),
    #[error("Projects root '{0}' exists but is not a directory.")]
    RootNotADirectory(PathBuf),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

impl ProjectError {
    pub const INVALID_NAME: &'static str = "invalid name";
    pub const PROJECT_EXISTS: &'static str = "project exists";
    pub const ROOT_NOT_A_DIRECTORY: &'static str = "root not a directory";
    pub const IO: &'static str = "io";

    pub fn kind_label(&self) -> &'static str {
        match self {
            ProjectError::InvalidName(_) => Self::INVALID_NAME,
            ProjectError::ProjectExists(_) => Self::PROJECT_EXISTS,
            ProjectError::RootNotADirectory(_) => Self::ROOT_NOT_A_DIRECTORY,
            ProjectError::Io(_) => Self::IO,
        }
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
            items.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        }
        ProjectSortOrder::DateNewestFirst => {
            items.sort_by(|a, b| b.created_at.cmp(&a.created_at));
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
/// the macOS app's `NSWorkspace.shared.recycle` semantics.
pub fn trash_project(path: &Path) -> Result<(), String> {
    trash::delete(path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

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
