//! Reads the two version sources behind "is this project behind the repo?":
//! the module repo's `skills/module.yaml` (`code` + `module_version`) and an
//! installed project's `_bmad/_config/manifest.yaml` (`modules[].version`),
//! and compares them with a leading-`v`-tolerant semver order.
//!
//! Mirrors the Swift `ModuleManifest`. The project ships no YAML parser and we
//! only need a couple of scalars plus one list scan, so the reads are
//! hand-rolled line scans rather than a dependency. The bias is conservative: a
//! missing module/manifest or a repo version we can't compare is treated as
//! "not stale" so we never show a false update badge. The one deliberate
//! exception is an unverifiable *installed* version against a real repo semver —
//! that's flagged for reinstall (#76).

use std::path::Path;

/// The module's own identity, read from the repo's `skills/module.yaml`.
/// `code` matches the installed manifest's `modules[].name`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepoModule {
    pub code: String,
    pub version: String,
}

/// Reads `<module_root>/skills/module.yaml`. Returns `None` if the file is
/// absent or either top-level scalar (`code`, `module_version`) is missing.
pub fn read_repo_module(module_root: &Path) -> Option<RepoModule> {
    let text = std::fs::read_to_string(module_root.join("skills/module.yaml")).ok()?;

    let mut code: Option<String> = None;
    let mut version: Option<String> = None;
    for raw in text.lines() {
        // Only top-level (column-0) keys count, so a `module_version:` nested
        // under another block can't be mistaken for the real one.
        if raw.starts_with([' ', '\t']) {
            continue;
        }
        let line = raw.trim();
        if line.starts_with('#') {
            continue;
        }
        if code.is_none() {
            if let Some(v) = scalar(line, "code") {
                code = Some(v);
            }
        }
        if version.is_none() {
            if let Some(v) = scalar(line, "module_version") {
                version = Some(v);
            }
        }
        if code.is_some() && version.is_some() {
            break;
        }
    }

    let (code, version) = (code?, version?);
    if code.is_empty() || version.is_empty() {
        return None;
    }
    Some(RepoModule { code, version })
}

/// Reads the installed version of `module_code` from a project's
/// `_bmad/_config/manifest.yaml` — a YAML list of `{name, version, …}`
/// mappings under `modules:`. Returns the raw value (no `v`-strip) or `None`
/// if the manifest is missing/unreadable or lists no such module.
pub fn installed_version(module_code: &str, project_dir: &Path) -> Option<String> {
    let text = std::fs::read_to_string(project_dir.join("_bmad/_config/manifest.yaml")).ok()?;

    let mut in_modules = false;
    let mut current_name: Option<String> = None;
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        let is_top_level = !raw.starts_with([' ', '\t']);
        if is_top_level {
            // A column-0 key — we're inside `modules:` only while it's the
            // active block (so `installation.version` can't leak in).
            in_modules = line.starts_with("modules:");
            current_name = None;
            continue;
        }
        if !in_modules {
            continue;
        }
        if let Some(item) = line.strip_prefix("- ") {
            current_name = scalar(item.trim(), "name");
        } else if current_name.as_deref() == Some(module_code) {
            if let Some(version) = scalar(line, "version") {
                return Some(version);
            }
        }
    }
    None
}

/// True iff `lhs` is a strictly older version than `rhs`. Strips a leading
/// `v`/`V`, splits on `.`, and compares components numerically (missing or
/// non-numeric components count as 0).
pub fn is_older(lhs: &str, rhs: &str) -> bool {
    let l = numeric_components(lhs);
    let r = numeric_components(rhs);
    for i in 0..l.len().max(r.len()) {
        let lv = l.get(i).copied().unwrap_or(0);
        let rv = r.get(i).copied().unwrap_or(0);
        if lv != rv {
            return lv < rv;
        }
    }
    false
}

/// True iff the project should be offered an update for `repo_module`.
///
/// A missing module/manifest, or a repo version we can't read as a semver,
/// stays "not stale" (nothing to compare against). But when the repo *is* a
/// real semver and the installed version isn't comparable — a branch ref like
/// `main`, `unknown`, or empty (legacy installs, see #76) — the project can't be
/// verified current and needs a reinstall to pin a real version, so it's
/// flagged. Otherwise compare normally and flag a strictly older one.
pub fn is_project_stale(project_dir: &Path, repo_module: &RepoModule) -> bool {
    let Some(installed) = installed_version(&repo_module.code, project_dir) else {
        return false;
    };
    if !has_numeric_component(&repo_module.version) {
        return false;
    }
    if !has_numeric_component(&installed) {
        return true;
    }
    is_older(&installed, &repo_module.version)
}

// --- Parsing helpers --------------------------------------------------------

/// Returns the value of a `key: value` scalar on a single trimmed line, or
/// `None` if the line isn't that key. Surrounding quotes are stripped.
fn scalar(line: &str, key: &str) -> Option<String> {
    let rest = line.strip_prefix(key)?;
    let rest = rest.strip_prefix(':')?;
    Some(unquote(rest.trim()))
}

fn unquote(value: &str) -> String {
    let bytes = value.as_bytes();
    if bytes.len() >= 2 {
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.to_string()
}

fn numeric_components(version: &str) -> Vec<u64> {
    stripped(version)
        .split('.')
        .map(|c| c.trim().parse::<u64>().unwrap_or(0))
        .collect()
}

fn has_numeric_component(version: &str) -> bool {
    stripped(version)
        .split('.')
        .any(|c| c.trim().parse::<u64>().is_ok())
}

fn stripped(version: &str) -> &str {
    let v = version.trim();
    v.strip_prefix('v')
        .or_else(|| v.strip_prefix('V'))
        .unwrap_or(v)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn module_root(yaml: &str) -> TempDir {
        let tmp = TempDir::new().unwrap();
        let skills = tmp.path().join("skills");
        std::fs::create_dir_all(&skills).unwrap();
        std::fs::write(skills.join("module.yaml"), yaml).unwrap();
        tmp
    }

    fn project(manifest: &str) -> TempDir {
        let tmp = TempDir::new().unwrap();
        let config = tmp.path().join("_bmad/_config");
        std::fs::create_dir_all(&config).unwrap();
        std::fs::write(config.join("manifest.yaml"), manifest).unwrap();
        tmp
    }

    fn installed_manifest(mg_version: &str) -> String {
        format!(
            "installation:\n  version: 6.8.0\nmodules:\n  - name: core\n    version: 6.8.0\n  - name: bmb\n    version: v2.0.0\n  - name: marketing-growth\n    version: {mg_version}\n    source: custom\nides:\n  - claude-code\n"
        )
    }

    #[test]
    fn reads_repo_module_scalars() {
        let tmp = module_root("code: marketing-growth\nname: \"Suite\"\nmodule_version: 2.0.0\n");
        assert_eq!(
            read_repo_module(tmp.path()),
            Some(RepoModule {
                code: "marketing-growth".into(),
                version: "2.0.0".into()
            })
        );
    }

    #[test]
    fn reads_repo_module_quoted_and_commented() {
        let tmp =
            module_root("# c\nname: x\ncode: \"marketing-growth\"\nmodule_version: \"2.1.3\"\n");
        let m = read_repo_module(tmp.path()).unwrap();
        assert_eq!(m.code, "marketing-growth");
        assert_eq!(m.version, "2.1.3");
    }

    #[test]
    fn read_repo_module_missing_file_is_none() {
        let tmp = TempDir::new().unwrap();
        assert!(read_repo_module(tmp.path()).is_none());
    }

    #[test]
    fn read_repo_module_missing_scalar_is_none() {
        let tmp = module_root("code: marketing-growth\nname: x\n");
        assert!(read_repo_module(tmp.path()).is_none());
    }

    #[test]
    fn read_repo_module_ignores_nested_keys() {
        let tmp = module_root(
            "code: marketing-growth\nquestions:\n  module_version: 9.9.9\nmodule_version: 2.0.0\n",
        );
        assert_eq!(read_repo_module(tmp.path()).unwrap().version, "2.0.0");
    }

    #[test]
    fn installed_version_from_list() {
        let tmp = project(&installed_manifest("2.0.0"));
        assert_eq!(
            installed_version("marketing-growth", tmp.path()),
            Some("2.0.0".into())
        );
        assert_eq!(installed_version("core", tmp.path()), Some("6.8.0".into()));
    }

    #[test]
    fn installed_version_preserves_v_prefix() {
        let tmp = project(&installed_manifest("2.0.0"));
        assert_eq!(installed_version("bmb", tmp.path()), Some("v2.0.0".into()));
    }

    #[test]
    fn installed_version_ignores_installation_block() {
        let tmp = project(
            "installation:\n  version: 6.8.0\nmodules:\n  - name: core\n    version: 6.8.0\n",
        );
        assert!(installed_version("marketing-growth", tmp.path()).is_none());
    }

    #[test]
    fn installed_version_missing_manifest_is_none() {
        let tmp = TempDir::new().unwrap();
        assert!(installed_version("marketing-growth", tmp.path()).is_none());
    }

    #[test]
    fn installed_version_malformed_is_none() {
        let tmp = project("this is not a modules list at all\n");
        assert!(installed_version("marketing-growth", tmp.path()).is_none());
    }

    #[test]
    fn is_older_basic() {
        assert!(is_older("2.0.0", "2.1.0"));
        assert!(is_older("1.9.0", "2.0.0"));
        assert!(!is_older("2.1.0", "2.0.0"));
    }

    #[test]
    fn is_older_strips_v_prefix() {
        assert!(is_older("v2.0.0", "2.1.0"));
        assert!(!is_older("2.1.0", "v2.0.0"));
        assert!(!is_older("v2.0.0", "2.0.0"));
    }

    #[test]
    fn is_older_equal_is_not_older() {
        assert!(!is_older("2.0.0", "2.0.0"));
    }

    #[test]
    fn is_older_different_component_counts() {
        assert!(is_older("2.0", "2.0.1"));
        assert!(!is_older("2.0.0", "2.0"));
    }

    #[test]
    fn project_stale_when_behind() {
        let tmp = project(&installed_manifest("2.0.0"));
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_not_stale_when_current() {
        let tmp = project(&installed_manifest("2.1.0"));
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(!is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_not_stale_when_module_absent() {
        let tmp = project("modules:\n  - name: core\n    version: 6.8.0\n");
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(!is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_not_stale_when_manifest_missing() {
        let tmp = TempDir::new().unwrap();
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(!is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_stale_when_installed_non_comparable() {
        // A non-comparable installed version (e.g. `garbage`) against a real
        // repo semver can't be verified current → needs a reinstall (#76).
        let tmp = project("modules:\n  - name: marketing-growth\n    version: garbage\n");
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_stale_when_installed_is_branch_ref() {
        // The canonical #76 case: legacy installs stamped the branch name
        // `main` instead of a semver, so the project must offer an update.
        let tmp = project("modules:\n  - name: marketing-growth\n    version: main\n");
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_stale_when_installed_is_empty() {
        let tmp = project("modules:\n  - name: marketing-growth\n    version: \"\"\n");
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "2.1.0".into(),
        };
        assert!(is_project_stale(tmp.path(), &repo));
    }

    #[test]
    fn project_not_stale_when_repo_version_non_comparable() {
        // If the repo version isn't itself comparable there's nothing to
        // compare against — stay conservative and don't badge.
        let tmp = project("modules:\n  - name: marketing-growth\n    version: main\n");
        let repo = RepoModule {
            code: "marketing-growth".into(),
            version: "main".into(),
        };
        assert!(!is_project_stale(tmp.path(), &repo));
    }
}
