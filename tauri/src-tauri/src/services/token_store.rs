//! Storage for the skills-repo GitHub token.
//!
//! The token is held in the OS secure credential store via the platform
//! layer — **Windows Credential Manager** on Windows (the macOS app uses the
//! Keychain). On dev/CI builds with no OS keystore wired up, the platform
//! stub falls back to a per-user, owner-only file. In every case the token is
//! kept **out** of `settings.json`, so it is never serialized into a file
//! users routinely copy between machines or paste into bug reports.
//!
//! This module is a thin, platform-agnostic facade: it owns the trim/empty
//! conventions and the credential's logical name, and delegates the actual
//! storage to `platform::secret_*`.

use std::path::Path;

use crate::platform;

/// Errors bubble up from the platform credential store unchanged.
pub use crate::platform::SecretError as TokenError;

/// Logical credential name for the single skills-repo token. On the stub
/// fallback this doubles as the file name next to `settings.json`, preserving
/// the legacy on-disk location.
const ACCOUNT: &str = "skills-repo-token";

/// Logical credential name for the optional contributor (read-write) token,
/// kept separate from the read-only sync token so syncing can stay
/// least-privilege while contributing uses a higher-scope token.
const CONTRIBUTOR_ACCOUNT: &str = "skills-repo-contributor-token";

/// Reads the stored sync token, or `None` if unset/empty.
pub fn load(settings_dir: &Path) -> Result<Option<String>, TokenError> {
    load_account(settings_dir, ACCOUNT)
}

/// True if a non-empty sync token is stored. The raw value is never returned to
/// the frontend — only whether one exists.
pub fn is_set(settings_dir: &Path) -> bool {
    matches!(load(settings_dir), Ok(Some(_)))
}

/// Stores the sync `token`. An empty/whitespace token clears any stored value.
pub fn save(settings_dir: &Path, token: &str) -> Result<(), TokenError> {
    save_account(settings_dir, ACCOUNT, token)
}

/// Removes the stored sync token if present.
pub fn clear(settings_dir: &Path) -> Result<(), TokenError> {
    platform::secret_delete(settings_dir, ACCOUNT)
}

/// Reads the contributor token, or `None` if unset/empty.
pub fn load_contributor(settings_dir: &Path) -> Result<Option<String>, TokenError> {
    load_account(settings_dir, CONTRIBUTOR_ACCOUNT)
}

/// True if a non-empty contributor token is stored.
pub fn is_contributor_set(settings_dir: &Path) -> bool {
    matches!(load_contributor(settings_dir), Ok(Some(_)))
}

/// Stores the contributor `token`. An empty/whitespace token clears it.
pub fn save_contributor(settings_dir: &Path, token: &str) -> Result<(), TokenError> {
    save_account(settings_dir, CONTRIBUTOR_ACCOUNT, token)
}

/// The token the contribution flow should use: the contributor token when set,
/// otherwise the read-only sync token (which won't have write scope, surfacing
/// a clear permission error rather than a silent failure).
pub fn load_for_contribution(settings_dir: &Path) -> Result<Option<String>, TokenError> {
    match load_contributor(settings_dir)? {
        Some(token) => Ok(Some(token)),
        None => load(settings_dir),
    }
}

fn load_account(settings_dir: &Path, account: &str) -> Result<Option<String>, TokenError> {
    let value = platform::secret_get(settings_dir, account)?;
    Ok(value
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty()))
}

fn save_account(settings_dir: &Path, account: &str, token: &str) -> Result<(), TokenError> {
    let trimmed = token.trim();
    if trimmed.is_empty() {
        return platform::secret_delete(settings_dir, account);
    }
    platform::secret_set(settings_dir, account, trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    // These exercise whichever credential backend is compiled in (the file
    // stub on Linux/CI). The temp `settings_dir` keeps each test isolated; on
    // an OS-keystore arm it also keeps them clear of the real credential.

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
        clear(tmp.path()).unwrap();
    }

    #[test]
    fn saving_empty_clears_the_token() {
        let tmp = TempDir::new().unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        save(tmp.path(), "   ").unwrap();
        assert_eq!(load(tmp.path()).unwrap(), None);
        assert!(!is_set(tmp.path()));
    }

    #[test]
    fn clear_is_idempotent() {
        let tmp = TempDir::new().unwrap();
        clear(tmp.path()).unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        clear(tmp.path()).unwrap();
        assert!(!is_set(tmp.path()));
    }

    #[test]
    fn token_is_kept_out_of_settings_json() {
        let tmp = TempDir::new().unwrap();
        save(tmp.path(), "ghp_secret").unwrap();
        assert!(!tmp.path().join("settings.json").exists());
        clear(tmp.path()).unwrap();
    }
}
