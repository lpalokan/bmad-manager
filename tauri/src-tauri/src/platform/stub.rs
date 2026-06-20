//! Fallback arm for non-Windows / non-macOS targets (Linux dev containers,
//! CI sanity checks). Read-only helpers (`settings_dir`, `augmented_path`,
//! `resolve_*_path`) return sensible local-dev values so the Rust unit
//! tests and BDD harness can exercise the cross-platform services without
//! pulling in real OS integrations. `run_shell` / `launch_terminal` still
//! panic — those need a real platform arm.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use super::SecretError;
use crate::models::{NewSessionPlacement, ShellKind, TerminalKind};

pub fn run_shell(_command: &str, _cwd: &Path) -> i32 {
    unimplemented!("platform::stub::run_shell — not implemented on this OS")
}

pub fn launch_terminal(
    _path: &Path,
    _command: &str,
    _kind: TerminalKind,
    _shell: ShellKind,
    _placement: NewSessionPlacement,
) -> Result<(), String> {
    unimplemented!("platform::stub::launch_terminal — not implemented on this OS")
}

pub fn open_folder(_path: &Path) -> Result<(), String> {
    unimplemented!("platform::stub::open_folder — not implemented on this OS")
}

pub fn settings_dir() -> PathBuf {
    dirs::config_dir()
        .map(|d| d.join("bmad-manager"))
        .unwrap_or_else(|| PathBuf::from("bmad-manager"))
}

pub fn resolve_npx_path() -> PathBuf {
    PathBuf::from("npx")
}

pub fn resolve_node_path() -> PathBuf {
    PathBuf::from("node")
}

pub fn resolve_git_path() -> PathBuf {
    PathBuf::from("git")
}

pub fn resolve_bundled_npm_cache_path() -> Option<PathBuf> {
    // No bundled resources on non-target platforms; the seeder treats
    // this as a silent no-op so the unit tests pass on Linux CI.
    None
}

pub fn user_npm_cache_dir() -> PathBuf {
    dirs::data_local_dir()
        .map(|d| d.join("bmad-manager").join("npm-cache"))
        .unwrap_or_else(|| PathBuf::from("bmad-manager").join("npm-cache"))
}

pub fn augmented_path() -> OsString {
    std::env::var_os("PATH").unwrap_or_default()
}

// --- Secure-credential fallback ---------------------------------------------
//
// There is no OS keystore on this arm (Linux dev containers / CI), so the
// secret lives in a per-user file next to `settings.json`. It is created
// owner-only (0600 on unix) so other accounts on the machine can't read it,
// and — as on every arm — it is kept out of `settings.json`.

fn secret_path(scope: &Path, account: &str) -> PathBuf {
    scope.join(account)
}

/// Read the stored secret, or `None` when it was never set / is empty.
pub fn secret_get(scope: &Path, account: &str) -> Result<Option<String>, SecretError> {
    let path = secret_path(scope, account);
    match std::fs::read_to_string(&path) {
        Ok(raw) => {
            let trimmed = raw.trim();
            Ok((!trimmed.is_empty()).then(|| trimmed.to_string()))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(SecretError::Backend(format!("{}: {e}", path.display()))),
    }
}

/// Store `secret` in an owner-only file under `scope`.
pub fn secret_set(scope: &Path, account: &str, secret: &str) -> Result<(), SecretError> {
    std::fs::create_dir_all(scope)
        .map_err(|e| SecretError::Backend(format!("{}: {e}", scope.display())))?;
    let path = secret_path(scope, account);
    write_owner_only(&path, secret)
        .map_err(|e| SecretError::Backend(format!("{}: {e}", path.display())))
}

/// Remove the stored secret if present; a missing file is success.
pub fn secret_delete(scope: &Path, account: &str) -> Result<(), SecretError> {
    let path = secret_path(scope, account);
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(SecretError::Backend(format!("{}: {e}", path.display()))),
    }
}

#[cfg(unix)]
fn write_owner_only(path: &Path, secret: &str) -> std::io::Result<()> {
    use std::io::Write as _;
    use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
    // Create with 0600 so the token is never momentarily world-readable, and
    // re-apply 0600 in case the file already existed with looser bits (an
    // OpenOptions `mode` only takes effect when the file is newly created).
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    file.write_all(secret.as_bytes())
}

#[cfg(not(unix))]
fn write_owner_only(path: &Path, secret: &str) -> std::io::Result<()> {
    std::fs::write(path, secret)
}

#[cfg(test)]
mod secret_tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn round_trips_and_reports_absence() {
        let tmp = TempDir::new().unwrap();
        assert_eq!(secret_get(tmp.path(), "tok").unwrap(), None);
        secret_set(tmp.path(), "tok", "ghp_secret").unwrap();
        assert_eq!(
            secret_get(tmp.path(), "tok").unwrap(),
            Some("ghp_secret".to_string())
        );
    }

    #[test]
    fn delete_removes_and_is_idempotent() {
        let tmp = TempDir::new().unwrap();
        secret_delete(tmp.path(), "tok").unwrap();
        secret_set(tmp.path(), "tok", "ghp_secret").unwrap();
        secret_delete(tmp.path(), "tok").unwrap();
        assert_eq!(secret_get(tmp.path(), "tok").unwrap(), None);
    }

    #[test]
    fn fallback_file_sits_at_scope_account_not_settings_json() {
        let tmp = TempDir::new().unwrap();
        secret_set(tmp.path(), "skills-repo-token", "ghp_secret").unwrap();
        assert!(tmp.path().join("skills-repo-token").exists());
        assert!(!tmp.path().join("settings.json").exists());
    }

    #[cfg(unix)]
    #[test]
    fn fallback_file_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = TempDir::new().unwrap();
        secret_set(tmp.path(), "skills-repo-token", "ghp_secret").unwrap();
        let mode = std::fs::metadata(tmp.path().join("skills-repo-token"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600, "mode was {mode:o}");
    }

    #[cfg(unix)]
    #[test]
    fn overwriting_a_loosely_permissioned_file_tightens_it() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("skills-repo-token");
        std::fs::write(&path, "old").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        secret_set(tmp.path(), "skills-repo-token", "new").unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600, "mode was {mode:o}");
    }
}
