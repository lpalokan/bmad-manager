use serde::{Deserialize, Serialize};

/// How project entries are ordered in the UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProjectSortOrder {
    #[serde(rename = "nameAscending")]
    NameAscending,
    #[serde(rename = "dateNewestFirst")]
    DateNewestFirst,
    #[serde(rename = "dateOldestFirst")]
    DateOldestFirst,
}

impl ProjectSortOrder {
    pub fn display_name(self) -> &'static str {
        match self {
            ProjectSortOrder::NameAscending => "Name (A→Z)",
            ProjectSortOrder::DateNewestFirst => "Date created (newest first)",
            ProjectSortOrder::DateOldestFirst => "Date created (oldest first)",
        }
    }
}

/// Where the marketing-growth module comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ModuleSourceKind {
    #[serde(rename = "gitRepo")]
    GitRepo,
    #[serde(rename = "localZip")]
    LocalZip,
}

impl ModuleSourceKind {
    pub fn display_name(self) -> &'static str {
        match self {
            ModuleSourceKind::GitRepo => "GitHub repo",
            ModuleSourceKind::LocalZip => "Local zip",
        }
    }
}

/// Curated list of terminal emulators the launcher knows how to drive.
///
/// Adding a kind is intentionally a code change — each kind needs its own
/// launch glue (AppleScript on macOS, `wt.exe` / `cmd /k` on Windows).
/// The settings file is platform-agnostic so a settings.json copied across
/// machines doesn't crash on load; if a kind isn't installable on the
/// current OS, the launcher falls back to the platform default.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TerminalKind {
    #[serde(rename = "terminal")]
    Terminal,
    #[serde(rename = "iterm2")]
    Iterm2,
    #[serde(rename = "windowsTerminal")]
    WindowsTerminal,
    #[serde(rename = "cmd")]
    Cmd,
}

impl TerminalKind {
    pub fn display_name(self) -> &'static str {
        match self {
            TerminalKind::Terminal => "Terminal",
            TerminalKind::Iterm2 => "iTerm2",
            TerminalKind::WindowsTerminal => "Windows Terminal",
            TerminalKind::Cmd => "Command Prompt",
        }
    }

    /// Platform-appropriate default: Windows Terminal on Windows,
    /// Terminal.app on macOS, Windows Terminal everywhere else so unit
    /// tests on Linux have a stable value.
    pub fn default_for_platform() -> Self {
        #[cfg(target_os = "macos")]
        {
            TerminalKind::Terminal
        }
        #[cfg(not(target_os = "macos"))]
        {
            TerminalKind::WindowsTerminal
        }
    }
}

pub const DEFAULT_MODULE_REPO_URL: &str = "https://github.com/lpalokan/bmad-marketing-growth";

/// User-visible app settings. Persisted as JSON under
/// `platform::settings_dir()/settings.json`.
///
/// The on-disk shape mirrors the Swift `AppSettings` exactly so a
/// settings.json from the macOS app loads here without translation. The
/// custom `Deserialize` handles legacy files written before the
/// module-source picker or terminal picker existed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub projects_root: String,
    pub module_source_kind: ModuleSourceKind,
    pub module_repo_url: String,
    pub module_repo_ref: String,
    pub module_zip_path: String,
    pub init_command: String,
    pub claude_command: String,
    pub opencode_command: String,
    pub pi_command: String,
    pub codex_command: String,
    pub project_sort_order: ProjectSortOrder,
    pub terminal_kind: TerminalKind,
}

impl AppSettings {
    pub fn defaults() -> Self {
        // Headless BMad install per docs.bmad-method.org/how-to/install-bmad.
        // The single-quoted placeholders match the Swift app's persisted
        // default — substitution rewrites them to double quotes when
        // executing on Windows so the same settings.json round-trips.
        Self {
            projects_root: default_projects_root(),
            module_source_kind: ModuleSourceKind::GitRepo,
            module_repo_url: DEFAULT_MODULE_REPO_URL.to_string(),
            module_repo_ref: String::new(),
            module_zip_path: String::new(),
            init_command: "npx bmad-method install --yes --modules bmm,bmb,cis --tools claude-code,opencode,pi,codex --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'".to_string(),
            claude_command: "claude".to_string(),
            opencode_command: "opencode".to_string(),
            pi_command: "pi".to_string(),
            codex_command: "codex".to_string(),
            project_sort_order: ProjectSortOrder::NameAscending,
            terminal_kind: TerminalKind::default_for_platform(),
        }
    }
}

fn default_projects_root() -> String {
    if let Some(home) = dirs::home_dir() {
        home.join("Projects").to_string_lossy().into_owned()
    } else {
        // No home dir is exceedingly unusual; fall back to a path that's
        // at least absolute so the UI's "non-empty + absolute" invariant
        // holds. Users will hit "rootNotADirectory" the first time they
        // try to create a project, and Settings can repoint it.
        "/Projects".to_string()
    }
}

// --- Custom Deserialize to tolerate legacy settings.json files -----------

impl<'de> Deserialize<'de> for AppSettings {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Raw {
            projects_root: String,
            #[serde(default)]
            module_source_kind: Option<ModuleSourceKind>,
            #[serde(default)]
            module_repo_url: Option<String>,
            #[serde(default)]
            module_repo_ref: Option<String>,
            module_zip_path: String,
            init_command: String,
            claude_command: String,
            opencode_command: String,
            #[serde(default)]
            pi_command: Option<String>,
            #[serde(default)]
            codex_command: Option<String>,
            #[serde(default)]
            project_sort_order: Option<ProjectSortOrder>,
            #[serde(default)]
            terminal_kind: Option<TerminalKind>,
        }

        let raw = Raw::deserialize(deserializer)?;
        // Infer module source from the zip path when the discriminator is
        // missing — mirrors the Swift custom decoder so legacy files keep
        // the workflow the user had configured.
        let module_source_kind = raw.module_source_kind.unwrap_or_else(|| {
            let zip_configured = !raw.module_zip_path.trim().is_empty();
            if zip_configured {
                ModuleSourceKind::LocalZip
            } else {
                ModuleSourceKind::GitRepo
            }
        });

        Ok(AppSettings {
            projects_root: raw.projects_root,
            module_source_kind,
            module_repo_url: raw
                .module_repo_url
                .unwrap_or_else(|| DEFAULT_MODULE_REPO_URL.to_string()),
            module_repo_ref: raw.module_repo_ref.unwrap_or_default(),
            module_zip_path: raw.module_zip_path,
            init_command: raw.init_command,
            claude_command: raw.claude_command,
            opencode_command: raw.opencode_command,
            pi_command: raw.pi_command.unwrap_or_else(|| "pi".to_string()),
            codex_command: raw.codex_command.unwrap_or_else(|| "codex".to_string()),
            project_sort_order: raw
                .project_sort_order
                .unwrap_or(ProjectSortOrder::NameAscending),
            terminal_kind: raw
                .terminal_kind
                .unwrap_or_else(TerminalKind::default_for_platform),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_sensible() {
        let d = AppSettings::defaults();
        assert!(!d.projects_root.is_empty());
        assert!(std::path::Path::new(&d.projects_root).is_absolute());
        assert!(d.init_command.contains("{PROJECT_PATH}"));
        assert!(d.init_command.contains("{MODULE_PATH}"));
        assert_eq!(d.module_source_kind, ModuleSourceKind::GitRepo);
        assert_eq!(d.module_repo_url, DEFAULT_MODULE_REPO_URL);
        assert_eq!(d.module_repo_ref, "");
        assert_eq!(d.module_zip_path, "");
        assert_eq!(d.claude_command, "claude");
        assert_eq!(d.opencode_command, "opencode");
        assert_eq!(d.pi_command, "pi");
        assert_eq!(d.codex_command, "codex");
        assert_eq!(d.project_sort_order, ProjectSortOrder::NameAscending);
    }

    #[test]
    fn defaults_use_headless_bmad_install() {
        let cmd = AppSettings::defaults().init_command;
        for needle in [
            "--yes",
            "--modules",
            "bmm",
            "bmb",
            "cis",
            "--tools",
            "claude-code",
            "opencode",
            "pi",
            "codex",
            "--custom-source",
            "--directory",
            "{PROJECT_PATH}",
            "{MODULE_PATH}",
        ] {
            assert!(
                cmd.contains(needle),
                "default init command should contain {needle:?}, got {cmd:?}"
            );
        }
    }

    #[test]
    fn defaults_round_trip() {
        let original = AppSettings::defaults();
        let json = serde_json::to_string(&original).unwrap();
        let decoded: AppSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(original, decoded);
    }

    #[test]
    fn legacy_without_sort_order_defaults_to_name_ascending() {
        let legacy = r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#;
        let decoded: AppSettings = serde_json::from_str(legacy).unwrap();
        assert_eq!(decoded.project_sort_order, ProjectSortOrder::NameAscending);
        assert_eq!(decoded.projects_root, "/tmp/legacy");
    }

    #[test]
    fn legacy_with_configured_zip_infers_local_zip_kind() {
        let legacy = r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#;
        let decoded: AppSettings = serde_json::from_str(legacy).unwrap();
        assert_eq!(decoded.module_source_kind, ModuleSourceKind::LocalZip);
        assert_eq!(decoded.module_zip_path, "/tmp/m.zip");
        assert_eq!(decoded.module_repo_url, DEFAULT_MODULE_REPO_URL);
    }

    #[test]
    fn legacy_without_configured_zip_defaults_to_git_repo() {
        let legacy = r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#;
        let decoded: AppSettings = serde_json::from_str(legacy).unwrap();
        assert_eq!(decoded.module_source_kind, ModuleSourceKind::GitRepo);
        assert_eq!(decoded.module_repo_url, DEFAULT_MODULE_REPO_URL);
        assert_eq!(decoded.module_repo_ref, "");
    }

    #[test]
    fn legacy_without_terminal_kind_defaults_to_platform_default() {
        let legacy = r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#;
        let decoded: AppSettings = serde_json::from_str(legacy).unwrap();
        assert_eq!(decoded.terminal_kind, TerminalKind::default_for_platform());
    }

    #[test]
    fn round_trip_preserves_terminal_kind() {
        let mut original = AppSettings::defaults();
        original.terminal_kind = TerminalKind::Iterm2;
        let json = serde_json::to_string(&original).unwrap();
        let decoded: AppSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.terminal_kind, TerminalKind::Iterm2);
        assert_eq!(decoded, original);
    }

    #[test]
    fn round_trip_local_zip() {
        let original = AppSettings {
            projects_root: "/tmp/p".to_string(),
            module_source_kind: ModuleSourceKind::LocalZip,
            module_repo_url: "https://github.com/example/repo".to_string(),
            module_repo_ref: "v1.0".to_string(),
            module_zip_path: "/tmp/m.zip".to_string(),
            init_command: "echo {PROJECT_PATH}".to_string(),
            claude_command: "claude".to_string(),
            opencode_command: "opencode".to_string(),
            pi_command: "pi".to_string(),
            codex_command: "codex".to_string(),
            project_sort_order: ProjectSortOrder::DateNewestFirst,
            terminal_kind: TerminalKind::WindowsTerminal,
        };
        let json = serde_json::to_string(&original).unwrap();
        let decoded: AppSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded, original);
    }
}
