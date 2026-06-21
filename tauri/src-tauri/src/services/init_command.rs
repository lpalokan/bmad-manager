/// Substitutes the `{PROJECT_NAME}`, `{PROJECT_PATH}`, `{MODULE_SOURCE}`, and
/// `{MODULE_PATH}` placeholders in an init-command template.
///
/// `{MODULE_SOURCE}` is the value handed to `--custom-source`: the repo URL for
/// a git source (so the installer records `repoUrl` + a real version) or the
/// local module path for a zip source. `{MODULE_PATH}` is always the local
/// module path; it is retained so settings.json files written before
/// `{MODULE_SOURCE}` keep working.
///
/// On Windows, the single-quoted forms `'{MODULE_SOURCE}'` / `'{MODULE_PATH}'` /
/// `'{PROJECT_PATH}'` (which the Swift default writes for POSIX shells) are
/// rewritten to double-quoted forms because `cmd.exe` does not honour single
/// quotes. The rewrite happens at substitution time so the same `settings.json`
/// round-trips across operating systems.
pub fn substitute(
    template: &str,
    project_name: &str,
    project_path: &str,
    module_source: &str,
    module_path: &str,
    windows: bool,
) -> String {
    let mut s = template.to_string();
    if windows {
        s = s.replace("'{MODULE_SOURCE}'", "\"{MODULE_SOURCE}\"");
        s = s.replace("'{MODULE_PATH}'", "\"{MODULE_PATH}\"");
        s = s.replace("'{PROJECT_PATH}'", "\"{PROJECT_PATH}\"");
    }
    s = s.replace("{PROJECT_PATH}", project_path);
    s = s.replace("{MODULE_SOURCE}", module_source);
    s = s.replace("{MODULE_PATH}", module_path);
    s = s.replace("{PROJECT_NAME}", project_name);
    s
}

/// Builds the value for the init command's `--custom-source` argument.
///
/// `bmad-method`'s custom-source parser only recognises a *local* path when it
/// starts with `/`, `./`, `../`, or `~` (see `custom-module-manager.js`). A
/// Windows drive-absolute path like `C:\…\Temp\mod` matches none of those,
/// falls through every branch, and fails with "Not a valid Git URL or local
/// path" — so the module is silently never applied. POSIX absolute paths
/// already start with `/`, so they pass straight through.
///
/// On Windows we therefore express the module directory as a forward-slash
/// path *relative to the project directory* (which is the install's cwd, so
/// `bmad-method`'s `path.resolve` reconstructs the correct absolute path).
/// When the module and project live on different drives no lexical relative
/// path exists, so we fall back to the absolute path — no worse than today.
pub fn custom_source_arg(module_path: &str, project_path: &str, windows: bool) -> String {
    if !windows {
        return module_path.to_string();
    }
    relative_path_windows(project_path, module_path).unwrap_or_else(|| module_path.to_string())
}

/// Lexical (no filesystem access) relative path from `from` to `to`, using
/// forward slashes and a `./`/`../` prefix. Returns `None` when the two paths
/// are on different drives. Case-insensitive segment comparison matches
/// Windows semantics — and survives 8.3 short names (`LAURIP~1`) round-tripping
/// through `path.resolve` because both ends are treated lexically.
fn relative_path_windows(from: &str, to: &str) -> Option<String> {
    let split = |s: &str| -> Vec<String> {
        s.split(['\\', '/'])
            .filter(|p| !p.is_empty())
            .map(str::to_string)
            .collect()
    };
    let from_parts = split(from);
    let to_parts = split(to);
    if !from_parts.first()?.eq_ignore_ascii_case(to_parts.first()?) {
        return None; // different drive — no lexical relative path
    }
    let mut common = 0;
    while common < from_parts.len()
        && common < to_parts.len()
        && from_parts[common].eq_ignore_ascii_case(&to_parts[common])
    {
        common += 1;
    }
    let ups = from_parts.len() - common;
    let mut segments: Vec<String> = vec!["..".to_string(); ups];
    segments.extend(to_parts[common..].iter().cloned());
    if segments.is_empty() {
        return Some("./".to_string());
    }
    let joined = segments.join("/");
    if joined.starts_with("..") {
        Some(joined)
    } else {
        Some(format!("./{joined}"))
    }
}

/// POSIX shell quoting using the standard end-quote / escape / re-open
/// trick for embedded single quotes. Mirrors `TerminalLauncher.shellQuote`
/// in the Swift app so `cd <quoted>` reaches the same shell verbatim.
pub fn posix_shell_quote(value: &str) -> String {
    let escaped = value.replace('\'', "'\\''");
    format!("'{escaped}'")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn substitutes_all_placeholders() {
        let out = substitute(
            "init {PROJECT_NAME} at {PROJECT_PATH} from {MODULE_SOURCE} ({MODULE_PATH})",
            "demo",
            "/p/demo",
            "https://github.com/o/r@v1",
            "/m",
            false,
        );
        assert_eq!(
            out,
            "init demo at /p/demo from https://github.com/o/r@v1 (/m)"
        );
    }

    #[test]
    fn substitutes_module_source_placeholder_on_posix() {
        let out = substitute(
            "npx bmad install --custom-source '{MODULE_SOURCE}' --directory '{PROJECT_PATH}'",
            "demo",
            "/p/demo",
            "https://github.com/o/r@v2.0.2",
            "/m",
            false,
        );
        assert_eq!(
            out,
            "npx bmad install --custom-source 'https://github.com/o/r@v2.0.2' --directory '/p/demo'"
        );
    }

    #[test]
    fn rewrites_module_source_single_quotes_to_double_on_windows() {
        // The URL form carries no spaces, but the quote rewrite still applies
        // (keyed on the literal token) so the command is valid under cmd.exe.
        let out = substitute(
            "npx bmad install --custom-source '{MODULE_SOURCE}' --directory '{PROJECT_PATH}'",
            "demo",
            "C:\\p\\demo",
            "https://github.com/o/r",
            "C:\\m",
            true,
        );
        assert_eq!(
            out,
            "npx bmad install --custom-source \"https://github.com/o/r\" --directory \"C:\\p\\demo\""
        );
    }

    #[test]
    fn rewrites_single_quotes_to_double_on_windows() {
        let out = substitute(
            "npx bmad install --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            "demo",
            "C:\\p\\demo",
            "ignored",
            "C:\\m",
            true,
        );
        assert_eq!(
            out,
            "npx bmad install --custom-source \"C:\\m\" --directory \"C:\\p\\demo\""
        );
    }

    #[test]
    fn leaves_quotes_alone_on_posix() {
        let out = substitute(
            "npx bmad install --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            "demo",
            "/p/demo",
            "ignored",
            "/m",
            false,
        );
        assert_eq!(
            out,
            "npx bmad install --custom-source '/m' --directory '/p/demo'"
        );
    }

    #[test]
    fn posix_shell_quote_plain() {
        assert_eq!(
            posix_shell_quote("/Users/me/Projects/foo"),
            "'/Users/me/Projects/foo'"
        );
    }

    #[test]
    fn posix_shell_quote_spaces() {
        assert_eq!(
            posix_shell_quote("/Users/me/My Project"),
            "'/Users/me/My Project'"
        );
    }

    #[test]
    fn posix_shell_quote_embedded_single_quote() {
        assert_eq!(posix_shell_quote("foo'bar"), "'foo'\\''bar'");
    }

    #[test]
    fn custom_source_posix_passes_absolute_path_through() {
        assert_eq!(
            custom_source_arg("/var/folders/x/bmad-mod", "/Users/me/Projects/demo", false),
            "/var/folders/x/bmad-mod"
        );
    }

    #[test]
    fn custom_source_windows_same_drive_becomes_forward_slash_relative() {
        // Mirrors the real failure: 8.3 temp dir vs long-named project dir.
        let arg = custom_source_arg(
            r"C:\Users\LAURIP~1\AppData\Local\Temp\bmad-mod",
            r"C:\Users\LauriPalokangas\Projects\demo",
            true,
        );
        assert_eq!(arg, "../../../LAURIP~1/AppData/Local/Temp/bmad-mod");
    }

    #[test]
    fn custom_source_windows_module_under_project_is_dot_relative() {
        let arg = custom_source_arg(
            r"C:\Users\me\Projects\demo\.bmad-src",
            r"C:\Users\me\Projects\demo",
            true,
        );
        assert_eq!(arg, "./.bmad-src");
    }

    #[test]
    fn custom_source_windows_different_drive_falls_back_to_absolute() {
        let abs = r"D:\Temp\bmad-mod";
        assert_eq!(
            custom_source_arg(abs, r"C:\Users\me\Projects\demo", true),
            abs
        );
    }
}
