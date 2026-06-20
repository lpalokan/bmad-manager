//! Writes the project `AGENTS.md` that wires the BMad install up for Codex.
//!
//! Codex auto-discovers repo-scoped skills under `.agents/skills/`, but it
//! can't infer BMad's *routing* — that short menu codes map to skills via
//! `_bmad/_config/bmad-help.csv` — and bmad-method emits no Codex `AGENTS.md`.
//! So bmad-manager writes that routing here.
//!
//! Each managed block is delimited by namespace-derived start/end markers, so
//! a block can be created fresh, appended to a user's existing `AGENTS.md`, or
//! refreshed in place on a later re-install — without disturbing user content
//! or another namespace's block. The Rust port mirrors the Swift
//! `AgentsFileWriter`, generalised to a parameterised namespace + body.

use std::io;
use std::path::Path;

const BMAD_NAMESPACE: &str = "bmad-manager:bmad";

/// The bmad block's start marker — the public constant other code/tests pin.
pub const BMAD_SECTION_MARKER: &str = "<!-- bmad-manager:bmad start -->";

/// The start marker for a namespace token (e.g. `bmad-manager:bmad`,
/// `marketing-growth:okf`). HTML comments, invisible in rendered Markdown.
pub fn start_marker(namespace: &str) -> String {
    format!("<!-- {namespace} start -->")
}

pub fn end_marker(namespace: &str) -> String {
    format!("<!-- {namespace} end -->")
}

/// The BMad body, without markers — the core wraps it.
fn bmad_body() -> &'static str {
    "# BMad\n\n\
- BMad skills are installed in `.agents/skills`.\n\
- Use `bmad-help` when the user asks for BMad help, workflow routing, next steps, or menu options.\n\
- BMad menu codes are defined in `_bmad/_config/bmad-help.csv`.\n\
- When the user enters a BMad menu code, look it up in `_bmad/_config/bmad-help.csv`, identify the `skill`, then use that skill.\n\
- When using a BMad skill, read its `SKILL.md` completely before acting."
}

fn wrap(namespace: &str, body: &str) -> String {
    format!(
        "{}\n{}\n{}",
        start_marker(namespace),
        body,
        end_marker(namespace)
    )
}

/// The managed BMad block, start/end markers included.
pub fn bmad_block() -> String {
    wrap(BMAD_NAMESPACE, bmad_body())
}

/// Ensures the managed BMad block is present and current in
/// `<project_dir>/AGENTS.md`. Thin wrapper over [`ensure_managed_section`].
pub fn ensure_bmad_section(project_dir: &Path) -> io::Result<()> {
    ensure_managed_section(project_dir, "AGENTS.md", BMAD_NAMESPACE, bmad_body())
}

/// Ensures a managed block for `namespace` with the supplied marker-free
/// `body` is present and current in `<project_dir>/<file_name>`: creates the
/// file if absent, appends the block if the file exists without it, or
/// refreshes the block in place if it's already there — leaving surrounding
/// user content (and other namespaces' blocks) intact.
pub fn ensure_managed_section(
    project_dir: &Path,
    file_name: &str,
    namespace: &str,
    body: &str,
) -> io::Result<()> {
    let path = project_dir.join(file_name);
    let start = start_marker(namespace);
    let end = end_marker(namespace);
    let block = wrap(namespace, body);

    let Ok(existing) = std::fs::read_to_string(&path) else {
        // File absent (or unreadable) → create it with the block.
        return std::fs::write(&path, format!("{block}\n"));
    };

    if let Some(start_idx) = existing.find(&start) {
        if let Some(rel_end) = existing[start_idx..].find(&end) {
            // Refresh this namespace's block in place; leave everything else.
            let end_idx = start_idx + rel_end + end.len();
            let mut updated = String::with_capacity(existing.len());
            updated.push_str(&existing[..start_idx]);
            updated.push_str(&block);
            updated.push_str(&existing[end_idx..]);
            if updated != existing {
                std::fs::write(&path, updated)?;
            }
            return Ok(());
        }
    }

    // Append, preserving the user's existing content.
    let separator = if existing.ends_with('\n') {
        "\n"
    } else {
        "\n\n"
    };
    std::fs::write(&path, format!("{existing}{separator}{block}\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn agents(dir: &Path) -> String {
        std::fs::read_to_string(dir.join("AGENTS.md")).unwrap()
    }

    #[test]
    fn constants_match_derived_bmad_markers() {
        assert_eq!(BMAD_SECTION_MARKER, start_marker("bmad-manager:bmad"));
    }

    #[test]
    fn creates_agents_file_when_missing() {
        let tmp = TempDir::new().unwrap();
        ensure_bmad_section(tmp.path()).unwrap();
        let text = agents(tmp.path());
        assert!(text.contains(BMAD_SECTION_MARKER));
        assert!(text.contains(".agents/skills"));
        assert!(text.contains("bmad-help"));
        assert!(text.contains("_bmad/_config/bmad-help.csv"));
        assert!(text.to_lowercase().contains("menu code"));
    }

    #[test]
    fn appends_preserving_user_content() {
        let tmp = TempDir::new().unwrap();
        std::fs::write(
            tmp.path().join("AGENTS.md"),
            "# My project\n\nHand-written agent notes.\n",
        )
        .unwrap();
        ensure_bmad_section(tmp.path()).unwrap();
        let text = agents(tmp.path());
        assert!(text.contains("Hand-written agent notes."));
        assert!(text.contains(BMAD_SECTION_MARKER));
    }

    #[test]
    fn is_idempotent_when_section_present() {
        let tmp = TempDir::new().unwrap();
        ensure_bmad_section(tmp.path()).unwrap();
        let first = agents(tmp.path());
        ensure_bmad_section(tmp.path()).unwrap();
        let second = agents(tmp.path());
        assert_eq!(first, second);
        assert_eq!(second.matches(BMAD_SECTION_MARKER).count(), 1);
    }

    #[test]
    fn creates_block_for_arbitrary_namespace() {
        let tmp = TempDir::new().unwrap();
        ensure_managed_section(
            tmp.path(),
            "AGENTS.md",
            "marketing-growth:okf",
            "OKF body line",
        )
        .unwrap();
        let text = agents(tmp.path());
        assert!(text.contains(&start_marker("marketing-growth:okf")));
        assert!(text.contains(&end_marker("marketing-growth:okf")));
        assert!(text.contains("OKF body line"));
    }

    #[test]
    fn two_namespaces_coexist_in_one_file() {
        let tmp = TempDir::new().unwrap();
        ensure_bmad_section(tmp.path()).unwrap();
        ensure_managed_section(
            tmp.path(),
            "AGENTS.md",
            "marketing-growth:okf",
            "OKF body line",
        )
        .unwrap();
        let text = agents(tmp.path());
        assert_eq!(text.matches(BMAD_SECTION_MARKER).count(), 1);
        assert_eq!(
            text.matches(&start_marker("marketing-growth:okf")).count(),
            1
        );
        assert!(text.contains(".agents/skills"));
        assert!(text.contains("OKF body line"));
    }

    #[test]
    fn refreshes_only_its_own_block() {
        let tmp = TempDir::new().unwrap();
        ensure_bmad_section(tmp.path()).unwrap();
        ensure_managed_section(
            tmp.path(),
            "AGENTS.md",
            "marketing-growth:okf",
            "first okf body",
        )
        .unwrap();
        let bmad = bmad_block();

        ensure_managed_section(
            tmp.path(),
            "AGENTS.md",
            "marketing-growth:okf",
            "second okf body",
        )
        .unwrap();
        let text = agents(tmp.path());
        assert!(text.contains("second okf body"));
        assert!(!text.contains("first okf body"));
        assert!(text.contains(&bmad), "bmad block must be byte-identical");
        assert_eq!(
            text.matches(&start_marker("marketing-growth:okf")).count(),
            1
        );
    }

    #[test]
    fn honours_custom_file_name() {
        let tmp = TempDir::new().unwrap();
        ensure_managed_section(
            tmp.path(),
            "OTHER.md",
            "marketing-growth:okf",
            "OKF body line",
        )
        .unwrap();
        assert!(tmp.path().join("OTHER.md").is_file());
        assert!(!tmp.path().join("AGENTS.md").exists());
    }
}
