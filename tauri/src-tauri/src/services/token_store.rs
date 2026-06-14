//! Storage for the skills-repo GitHub token.
//!
//! The token is kept in a dedicated file next to `settings.json` (under the
//! per-user app data dir), **never** inside `settings.json` itself, so it is
//! not serialized into a file users routinely copy between machines or paste
//! into bug reports. The file lives under the user's roaming app data, which
//! is already protected by per-user NTFS ACLs.
//!
//! NOTE: this is intentionally a simple protected-file store. A future
//! enhancement is the Windows Credential Manager (the macOS app uses the
//! Keychain); that needs the `keyring` crate, deferred to keep the locked
//! dependency set unchanged for now.

use std::path::{Path, PathBuf};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum TokenError {
    #[error("io error on {path:?}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

/// Path of the token file given the directory that holds `settings.json`.
pub fn token_path(settings_dir: &Path) -> PathBuf {
    settings_dir.join("skills-repo-token")
}

/// Reads the stored token, or `None` if unset/empty.
pub fn load(settings_dir: &Path) -> Result<Option<String>, TokenError> {
    let path = token_path(settings_dir);
    if !path.exists() {
        return Ok(None);
    }
    let raw = std::fs::read_to_string(&path).map_err(|source| TokenError::Io {
        path: path.clone(),
        source,
    })?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        Ok(None)
    } else {
        Ok(Some(trimmed.to_string()))
    }
}

/// True if a non-empty token is stored. The raw value is never returned to the
/// frontend — only whether one exists.
pub fn is_set(settings_dir: &Path) -> bool {
    matches!(load(settings_dir), Ok(Some(_)))
}

/// Stores `token`. An empty/whitespace token clears any stored value.
pub fn save(settings_dir: &Path, token: &str) -> Result<(), TokenError> {
    let path = token_path(settings_dir);
    if token.trim().is_empty() {
        return clear(settings_dir);
    }
    std::fs::create_dir_all(settings_dir).map_err(|source| TokenError::Io {
        path: settings_dir.to_path_buf(),
        source,
    })?;
    std::fs::write(&path, token.trim()).map_err(|source| TokenError::Io {
        path: path.clone(),
        source,
    })
}

/// Removes the stored token if present.
pub fn clear(settings_dir: &Path) -> Result<(), TokenError> {
    let path = token_path(settings_dir);
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(source) => Err(TokenError::Io { path, source }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn unset_token_loads_as_none_and_is_not_set() {
        let tmp = TempDir::new().unwrap();
        assert_eq!(load(tmp.path()).unwrap(), None);
        assert!(!is_set(tmp.path()));
    }

    #[test]
    fn save_then_load_round_trips_and_trims() {
        let tmp = TempDir::new().unwrap();
        save(tmp.path(), "  ghp_token123  ").unwrap();
        assert_eq!(load(tmp.path()).unwrap(), Some("ghp_token123".to_string()));
        assert!(is_set(tmp.path()));
    }

    #[test]
    fn token_is_stored_outside_settings_json() {
        let tmp = TempDir::new().unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        let file = token_path(tmp.path());
        assert_eq!(file.file_name().unwrap(), "skills-repo-token");
        assert_ne!(file.file_name().unwrap(), "settings.json");
    }

    #[test]
    fn saving_empty_clears_the_token() {
        let tmp = TempDir::new().unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        save(tmp.path(), "   ").unwrap();
        assert_eq!(load(tmp.path()).unwrap(), None);
        assert!(!token_path(tmp.path()).exists());
    }

    #[test]
    fn clear_is_idempotent() {
        let tmp = TempDir::new().unwrap();
        clear(tmp.path()).unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        clear(tmp.path()).unwrap();
        assert!(!is_set(tmp.path()));
    }
}
