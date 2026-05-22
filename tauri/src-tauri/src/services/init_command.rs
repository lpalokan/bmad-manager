/// Substitutes the `{PROJECT_NAME}`, `{PROJECT_PATH}`, and `{MODULE_PATH}`
/// placeholders in an init-command template.
///
/// On Windows, the single-quoted forms `'{MODULE_PATH}'` /
/// `'{PROJECT_PATH}'` (which the Swift default writes for POSIX shells)
/// are rewritten to double-quoted forms because `cmd.exe` does not honour
/// single quotes. The rewrite happens at substitution time so the same
/// `settings.json` round-trips across operating systems.
pub fn substitute(
    template: &str,
    project_name: &str,
    project_path: &str,
    module_path: &str,
    windows: bool,
) -> String {
    let mut s = template.to_string();
    if windows {
        s = s.replace("'{MODULE_PATH}'", "\"{MODULE_PATH}\"");
        s = s.replace("'{PROJECT_PATH}'", "\"{PROJECT_PATH}\"");
    }
    s = s.replace("{PROJECT_PATH}", project_path);
    s = s.replace("{MODULE_PATH}", module_path);
    s = s.replace("{PROJECT_NAME}", project_name);
    s
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
    fn substitutes_all_three_placeholders() {
        let out = substitute(
            "init {PROJECT_NAME} at {PROJECT_PATH} from {MODULE_PATH}",
            "demo",
            "/p/demo",
            "/m",
            false,
        );
        assert_eq!(out, "init demo at /p/demo from /m");
    }

    #[test]
    fn rewrites_single_quotes_to_double_on_windows() {
        let out = substitute(
            "npx bmad install --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            "demo",
            "C:\\p\\demo",
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
}
