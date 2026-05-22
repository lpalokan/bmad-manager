use std::fs::{self, File};
use std::path::{Path, PathBuf};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ZipError {
    #[error("No marketing growth module .zip is configured.")]
    NotConfigured,
    #[error("Zip file not found: {0}")]
    ZipNotFound(PathBuf),
    #[error("Zip extraction failed: {0}")]
    ExtractionFailed(String),
}

/// Materialises the module by extracting `zip_path` into a fresh temp
/// directory. Returns the temp dir path on success; the caller is
/// responsible for cleaning it up (use [`cleanup`]).
pub fn extract_zip(zip_path: &str) -> Result<PathBuf, ZipError> {
    let trimmed = zip_path.trim();
    if trimmed.is_empty() {
        return Err(ZipError::NotConfigured);
    }
    let expanded = expand_tilde(trimmed);
    if !expanded.exists() {
        return Err(ZipError::ZipNotFound(expanded));
    }

    let tmp_dir = std::env::temp_dir().join(format!("bmad-manager-{}", uuid_like()));
    fs::create_dir_all(&tmp_dir).map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;

    let file = File::open(&expanded).map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
    let mut archive =
        zip::ZipArchive::new(file).map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;

    for i in 0..archive.len() {
        let mut entry = archive
            .by_index(i)
            .map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
        let Some(out_path) = entry.enclosed_name() else {
            // Skip entries with absolute paths or `..` segments; matches
            // `unzip -o`'s "trust the archive contents but stay in the
            // target dir" behaviour.
            continue;
        };
        let dest = tmp_dir.join(out_path);
        if entry.is_dir() {
            fs::create_dir_all(&dest).map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
        } else {
            if let Some(parent) = dest.parent() {
                fs::create_dir_all(parent)
                    .map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
            }
            let mut out =
                File::create(&dest).map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
            std::io::copy(&mut entry, &mut out)
                .map_err(|e| ZipError::ExtractionFailed(e.to_string()))?;
        }
    }
    Ok(tmp_dir)
}

pub fn cleanup(dir: &Path) {
    let _ = fs::remove_dir_all(dir);
}

/// If `dir` contains exactly one non-junk subdirectory (the GitHub
/// "Download ZIP" wrapper pattern, where the archive wraps everything in
/// a single top-level folder named after the repo), returns that
/// subdirectory so callers can pass the module root directly to
/// `bmad-method install --custom-source`. Otherwise returns `dir`.
pub fn module_root(dir: &Path) -> PathBuf {
    let Ok(entries) = fs::read_dir(dir) else {
        return dir.to_path_buf();
    };
    let meaningful: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name = name.to_string_lossy();
            !name.starts_with('.') && name != "__MACOSX"
        })
        .collect();
    if meaningful.len() != 1 {
        return dir.to_path_buf();
    }
    let only = &meaningful[0];
    let is_dir = only.metadata().map(|m| m.is_dir()).unwrap_or(false);
    if is_dir {
        only.path()
    } else {
        dir.to_path_buf()
    }
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest);
        }
    }
    PathBuf::from(path)
}

/// Cheap, dependency-free unique-ish suffix for temp dir names. Using a
/// full UUID would require a new dep; the tempfile crate's `TempDir`
/// would be overkill since we hand the path to the init command which
/// expects a stable, predictable lifetime.
fn uuid_like() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{nanos:032x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::TempDir;
    use zip::write::SimpleFileOptions;
    use zip::ZipWriter;

    fn make_fixture_zip(dir: &Path, name: &str, entries: &[(&str, &[u8])]) -> PathBuf {
        let zip_path = dir.join(name);
        let file = File::create(&zip_path).unwrap();
        let mut zw = ZipWriter::new(file);
        let opts = SimpleFileOptions::default();
        for (path, content) in entries {
            zw.start_file(*path, opts).unwrap();
            zw.write_all(content).unwrap();
        }
        zw.finish().unwrap();
        zip_path
    }

    #[test]
    fn extract_and_cleanup_round_trip() {
        let work = TempDir::new().unwrap();
        let zip = make_fixture_zip(work.path(), "fixture.zip", &[("hello.txt", b"hi\n")]);
        let extracted = extract_zip(zip.to_str().unwrap()).unwrap();
        assert!(extracted.exists());
        let content = std::fs::read_to_string(extracted.join("hello.txt")).unwrap();
        assert_eq!(content, "hi\n");
        cleanup(&extracted);
        assert!(!extracted.exists());
    }

    #[test]
    fn extract_rejects_missing_zip() {
        let path = std::env::temp_dir().join("bmad-manager-missing-xyz.zip");
        let _ = std::fs::remove_file(&path);
        let err = extract_zip(path.to_str().unwrap()).unwrap_err();
        assert!(matches!(err, ZipError::ZipNotFound(_)));
    }

    #[test]
    fn extract_rejects_empty_path() {
        let err = extract_zip("   ").unwrap_err();
        assert!(matches!(err, ZipError::NotConfigured));
    }

    #[test]
    fn module_root_descends_into_single_wrapper() {
        let tmp = TempDir::new().unwrap();
        let outer = tmp.path().join("outer");
        let wrapper = outer.join("repo-main");
        std::fs::create_dir_all(&wrapper).unwrap();
        std::fs::write(wrapper.join("manifest.yaml"), "x").unwrap();
        assert_eq!(module_root(&outer), wrapper);
    }

    #[test]
    fn module_root_stays_when_multiple_top_level_entries() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("flat");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("a.txt"), "x").unwrap();
        std::fs::write(dir.join("b.txt"), "y").unwrap();
        assert_eq!(module_root(&dir), dir);
    }

    #[test]
    fn module_root_ignores_macosx_sibling() {
        let tmp = TempDir::new().unwrap();
        let outer = tmp.path().join("outer");
        let wrapper = outer.join("repo-main");
        let mac = outer.join("__MACOSX");
        std::fs::create_dir_all(&wrapper).unwrap();
        std::fs::create_dir_all(&mac).unwrap();
        assert_eq!(module_root(&outer), wrapper);
    }

    #[test]
    fn module_root_stays_when_sole_entry_is_file() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("solefile");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("only.txt"), "x").unwrap();
        assert_eq!(module_root(&dir), dir);
    }
}
