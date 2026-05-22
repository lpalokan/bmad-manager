use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::models::AppSettings;

#[derive(Debug, Error)]
pub enum SettingsError {
    #[error("io error reading {path:?}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("malformed settings.json at {path:?}: {source}")]
    Parse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("serialize error: {0}")]
    Serialize(#[from] serde_json::Error),
}

/// Load `settings.json` from `path`. Returns `Ok(None)` if the file
/// doesn't exist yet — first-run callers turn that into
/// `AppSettings::defaults()` and persist them.
pub fn load(path: &Path) -> Result<Option<AppSettings>, SettingsError> {
    if !path.exists() {
        return Ok(None);
    }
    let raw = std::fs::read_to_string(path).map_err(|source| SettingsError::Io {
        path: path.to_path_buf(),
        source,
    })?;
    let parsed = serde_json::from_str(&raw).map_err(|source| SettingsError::Parse {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(Some(parsed))
}

/// Write `settings` to `path` pretty-printed with sorted keys, atomically
/// via a temp file + rename. Mirrors the Swift `FileSettingsRepository`
/// so settings.json from either app round-trips.
pub fn save(path: &Path, settings: &AppSettings) -> Result<(), SettingsError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|source| SettingsError::Io {
            path: parent.to_path_buf(),
            source,
        })?;
    }
    let value = serde_json::to_value(settings)?;
    let sorted = sort_keys(value);
    let json = serde_json::to_string_pretty(&sorted)?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, json).map_err(|source| SettingsError::Io {
        path: tmp.clone(),
        source,
    })?;
    std::fs::rename(&tmp, path).map_err(|source| SettingsError::Io {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(())
}

/// Convenience: load the settings or fall back to defaults, persisting
/// the defaults so subsequent reads round-trip without re-deriving them.
pub fn load_or_init(path: &Path) -> Result<AppSettings, SettingsError> {
    if let Some(loaded) = load(path)? {
        Ok(loaded)
    } else {
        let defaults = AppSettings::defaults();
        save(path, &defaults)?;
        Ok(defaults)
    }
}

fn sort_keys(value: serde_json::Value) -> serde_json::Value {
    use serde_json::{Map, Value};
    match value {
        Value::Object(map) => {
            let mut pairs: Vec<(String, Value)> = map.into_iter().collect();
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            let mut sorted = Map::new();
            for (k, v) in pairs {
                sorted.insert(k, sort_keys(v));
            }
            Value::Object(sorted)
        }
        Value::Array(items) => Value::Array(items.into_iter().map(sort_keys).collect()),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn first_load_returns_none() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        assert!(load(&path).unwrap().is_none());
    }

    #[test]
    fn save_then_load_round_trips() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        let mut s = AppSettings::defaults();
        s.projects_root = "/tmp/test-projects".to_string();
        save(&path, &s).unwrap();
        let loaded = load(&path).unwrap().unwrap();
        assert_eq!(loaded, s);
    }

    #[test]
    fn saved_file_is_pretty_printed_with_sorted_keys() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        save(&path, &AppSettings::defaults()).unwrap();
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(raw.contains('\n'), "file should be multi-line");
        // Find the first two top-level keys and confirm they're sorted.
        let key_lines: Vec<&str> = raw
            .lines()
            .filter(|l| l.contains(':') && l.contains('"'))
            .collect();
        if key_lines.len() >= 2 {
            assert!(
                key_lines[0].trim() <= key_lines[1].trim(),
                "keys should be sorted"
            );
        }
    }

    #[test]
    fn load_or_init_creates_defaults_on_first_run() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        let loaded = load_or_init(&path).unwrap();
        assert_eq!(loaded, AppSettings::defaults());
        assert!(path.exists());
    }

    #[test]
    fn load_or_init_returns_existing() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("settings.json");
        let mut custom = AppSettings::defaults();
        custom.claude_command = "custom-claude".to_string();
        save(&path, &custom).unwrap();
        assert_eq!(load_or_init(&path).unwrap(), custom);
    }

    #[test]
    fn load_legacy_settings_without_sort_order() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("legacy.json");
        std::fs::write(
            &path,
            r#"{
                "projectsRoot": "/tmp/legacy",
                "moduleZipPath": "/tmp/m.zip",
                "initCommand": "echo {PROJECT_PATH}",
                "claudeCommand": "claude",
                "opencodeCommand": "opencode"
            }"#,
        )
        .unwrap();
        let loaded = load(&path).unwrap().unwrap();
        assert_eq!(loaded.projects_root, "/tmp/legacy");
    }
}
