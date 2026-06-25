use cucumber::{given, then, when};

use bmad_manager_lib::models::{
    AgentLaunchMethod, AppSettings, ModuleSourceKind, NewSessionPlacement, ProjectSortOrder,
    ShellKind, TerminalKind,
};

use crate::steps::agent_launch::parse_launch_method;
use crate::support::TauriWorld;

#[when("I read the default settings")]
async fn read_defaults(world: &mut TauriWorld) {
    world.settings = Some(AppSettings::defaults());
}

#[then("the projects root is non-empty and absolute")]
async fn projects_root_absolute(world: &mut TauriWorld) {
    let s = world.settings.as_ref().expect("settings loaded");
    assert!(!s.projects_root.is_empty(), "projects root should be set");
    let p = std::path::Path::new(&s.projects_root);
    assert!(
        p.is_absolute(),
        "projects root should be absolute, got {:?}",
        s.projects_root
    );
    assert!(
        !s.projects_root.contains('~'),
        "projects root should be tilde-expanded"
    );
}

#[then(regex = r#"^the init command contains "(.+)"$"#)]
async fn init_command_contains(world: &mut TauriWorld, needle: String) {
    let s = world.settings.as_ref().expect("settings loaded");
    assert!(
        s.init_command.contains(&needle),
        "init command should contain {needle:?}, got {:?}",
        s.init_command
    );
}

#[then(regex = r#"^the module source kind is "(gitRepo|localZip)"$"#)]
async fn module_source_kind(world: &mut TauriWorld, kind: String) {
    let s = settings_for_assertion(world);
    let expected = match kind.as_str() {
        "gitRepo" => ModuleSourceKind::GitRepo,
        "localZip" => ModuleSourceKind::LocalZip,
        _ => unreachable!(),
    };
    assert_eq!(s.module_source_kind, expected);
}

#[then(regex = r#"^the project sort order is "(nameAscending|dateNewestFirst|dateOldestFirst)"$"#)]
async fn project_sort_order(world: &mut TauriWorld, order: String) {
    let s = settings_for_assertion(world);
    let expected = match order.as_str() {
        "nameAscending" => ProjectSortOrder::NameAscending,
        "dateNewestFirst" => ProjectSortOrder::DateNewestFirst,
        "dateOldestFirst" => ProjectSortOrder::DateOldestFirst,
        _ => unreachable!(),
    };
    assert_eq!(s.project_sort_order, expected);
}

#[when("I encode the default settings and decode them again")]
async fn encode_decode_defaults(world: &mut TauriWorld) {
    let originals = AppSettings::defaults();
    let json = serde_json::to_string(&originals).expect("encode");
    let decoded: AppSettings = serde_json::from_str(&json).expect("decode");
    world.settings = Some(originals);
    world.decoded_settings = Some(decoded);
}

#[then("the decoded settings equal the originals")]
async fn decoded_equals_original(world: &mut TauriWorld) {
    let originals = world.settings.as_ref().expect("originals");
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(originals, decoded);
}

#[given("a legacy settings JSON without projectSortOrder")]
async fn legacy_without_sort_order(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#
        .to_string(),
    );
}

#[given("a legacy settings JSON without moduleSourceKind but with a non-empty moduleZipPath")]
async fn legacy_with_zip(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#
        .to_string(),
    );
}

#[given("a legacy settings JSON without moduleSourceKind and with an empty moduleZipPath")]
async fn legacy_without_zip(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#
        .to_string(),
    );
}

#[given("a legacy settings JSON without terminalKind")]
async fn legacy_without_terminal_kind(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#
        .to_string(),
    );
}

#[given("a legacy settings JSON without piCommand")]
async fn legacy_without_pi_command(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }"#
        .to_string(),
    );
}

#[given("a legacy settings JSON without codexCommand")]
async fn legacy_without_codex_command(world: &mut TauriWorld) {
    world.raw_json = Some(
        r#"{
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode",
            "piCommand": "pi"
        }"#
        .to_string(),
    );
}

#[then(regex = r#"^the claude command is "(.+)"$"#)]
async fn claude_command_is(world: &mut TauriWorld, expected: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.claude_command, expected);
}

#[then(regex = r#"^the opencode command is "(.+)"$"#)]
async fn opencode_command_is(world: &mut TauriWorld, expected: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.opencode_command, expected);
}

#[then(regex = r#"^the pi command is "(.+)"$"#)]
async fn pi_command_is(world: &mut TauriWorld, expected: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.pi_command, expected);
}

#[then(regex = r#"^the codex command is "(.+)"$"#)]
async fn codex_command_is(world: &mut TauriWorld, expected: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.codex_command, expected);
}

#[when(regex = r#"^I round-trip the default settings with pi command "(.+)"$"#)]
async fn round_trip_with_pi_command(world: &mut TauriWorld, pi_command: String) {
    let mut original = AppSettings::defaults();
    original.pi_command = pi_command;
    let json = serde_json::to_string(&original).expect("encode");
    let decoded: AppSettings = serde_json::from_str(&json).expect("decode");
    world.settings = Some(original);
    world.decoded_settings = Some(decoded);
}

#[then(regex = r#"^the decoded pi command is "(.+)"$"#)]
async fn decoded_pi_command_is(world: &mut TauriWorld, expected: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.pi_command, expected);
}

#[when(regex = r#"^I round-trip the default settings with codex command "(.+)"$"#)]
async fn round_trip_with_codex_command(world: &mut TauriWorld, codex_command: String) {
    let mut original = AppSettings::defaults();
    original.codex_command = codex_command;
    let json = serde_json::to_string(&original).expect("encode");
    let decoded: AppSettings = serde_json::from_str(&json).expect("decode");
    world.settings = Some(original);
    world.decoded_settings = Some(decoded);
}

#[then(regex = r#"^the decoded codex command is "(.+)"$"#)]
async fn decoded_codex_command_is(world: &mut TauriWorld, expected: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.codex_command, expected);
}

#[given("a legacy settings JSON without codexLaunchMethod")]
async fn legacy_without_codex_launch_method(world: &mut TauriWorld) {
    world.raw_json = Some(legacy_settings_json());
}

#[given("a legacy settings JSON without claudeLaunchMethod")]
async fn legacy_without_claude_launch_method(world: &mut TauriWorld) {
    world.raw_json = Some(legacy_settings_json());
}

#[then(regex = r#"^the codex launch method is "(auto|app|cli)"$"#)]
async fn codex_launch_method_is(world: &mut TauriWorld, method: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.codex_launch_method, parse_launch_method(&method));
}

#[then(regex = r#"^the claude launch method is "(auto|app|cli)"$"#)]
async fn claude_launch_method_is(world: &mut TauriWorld, method: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.claude_launch_method, parse_launch_method(&method));
}

#[when(regex = r#"^I round-trip the default settings with codex launch method "(auto|app|cli)"$"#)]
async fn round_trip_with_codex_launch_method(world: &mut TauriWorld, method: String) {
    let mut original = AppSettings::defaults();
    original.codex_launch_method = parse_launch_method(&method);
    round_trip(world, original);
}

#[then(regex = r#"^the decoded codex launch method is "(auto|app|cli)"$"#)]
async fn decoded_codex_launch_method_is(world: &mut TauriWorld, method: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.codex_launch_method, parse_launch_method(&method));
}

#[when(regex = r#"^I round-trip the default settings with claude launch method "(auto|app|cli)"$"#)]
async fn round_trip_with_claude_launch_method(world: &mut TauriWorld, method: String) {
    let mut original = AppSettings::defaults();
    original.claude_launch_method = parse_launch_method(&method);
    round_trip(world, original);
}

#[then(regex = r#"^the decoded claude launch method is "(auto|app|cli)"$"#)]
async fn decoded_claude_launch_method_is(world: &mut TauriWorld, method: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.claude_launch_method, parse_launch_method(&method));
}

#[then(regex = r#"^the encoded settings JSON has "([a-zA-Z]+)" set to "([a-z]+)"$"#)]
async fn encoded_settings_json_has_key_value(world: &mut TauriWorld, key: String, value: String) {
    let s = world.settings.as_ref().expect("settings loaded");
    let json = serde_json::to_string(s).expect("encode");
    let needle = format!("\"{key}\":\"{value}\"");
    assert!(
        json.contains(&needle),
        "encoded JSON should contain {needle:?}, got {json}"
    );
}

#[when("I decode it")]
async fn decode_raw_json(world: &mut TauriWorld) {
    let raw = world.raw_json.as_ref().expect("raw json loaded");
    let decoded: AppSettings = serde_json::from_str(raw).expect("legacy decode");
    world.settings = Some(decoded);
}

#[then("the terminal kind matches the platform default")]
async fn terminal_kind_platform_default(world: &mut TauriWorld) {
    let s = settings_for_assertion(world);
    assert_eq!(s.terminal_kind, TerminalKind::default_for_platform());
}

#[given("a legacy settings JSON without shellKind")]
async fn legacy_without_shell_kind(world: &mut TauriWorld) {
    world.raw_json = Some(legacy_settings_json());
}

#[given("a legacy settings JSON without newSessionPlacement")]
async fn legacy_without_new_session_placement(world: &mut TauriWorld) {
    world.raw_json = Some(legacy_settings_json());
}

#[then(regex = r#"^the shell kind is "(cmd|powershell|pwsh)"$"#)]
async fn shell_kind_is(world: &mut TauriWorld, kind: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.shell_kind, parse_shell_kind(&kind));
}

#[then(regex = r#"^the new session placement is "(newWindow|newTab)"$"#)]
async fn new_session_placement_is(world: &mut TauriWorld, placement: String) {
    let s = settings_for_assertion(world);
    assert_eq!(s.new_session_placement, parse_placement(&placement));
}

#[when(regex = r#"^I round-trip the default settings with shell kind "(cmd|powershell|pwsh)"$"#)]
async fn round_trip_with_shell_kind(world: &mut TauriWorld, kind: String) {
    let mut original = AppSettings::defaults();
    original.shell_kind = parse_shell_kind(&kind);
    round_trip(world, original);
}

#[then(regex = r#"^the decoded shell kind is "(cmd|powershell|pwsh)"$"#)]
async fn decoded_shell_kind_is(world: &mut TauriWorld, kind: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.shell_kind, parse_shell_kind(&kind));
}

#[when(
    regex = r#"^I round-trip the default settings with new session placement "(newWindow|newTab)"$"#
)]
async fn round_trip_with_placement(world: &mut TauriWorld, placement: String) {
    let mut original = AppSettings::defaults();
    original.new_session_placement = parse_placement(&placement);
    round_trip(world, original);
}

#[then(regex = r#"^the decoded new session placement is "(newWindow|newTab)"$"#)]
async fn decoded_placement_is(world: &mut TauriWorld, placement: String) {
    let decoded = world.decoded_settings.as_ref().expect("decoded");
    assert_eq!(decoded.new_session_placement, parse_placement(&placement));
}

fn parse_shell_kind(kind: &str) -> ShellKind {
    match kind {
        "cmd" => ShellKind::Cmd,
        "powershell" => ShellKind::PowerShell,
        "pwsh" => ShellKind::Pwsh,
        _ => unreachable!(),
    }
}

fn parse_placement(placement: &str) -> NewSessionPlacement {
    match placement {
        "newWindow" => NewSessionPlacement::NewWindow,
        "newTab" => NewSessionPlacement::NewTab,
        _ => unreachable!(),
    }
}

fn round_trip(world: &mut TauriWorld, original: AppSettings) {
    let json = serde_json::to_string(&original).expect("encode");
    let decoded: AppSettings = serde_json::from_str(&json).expect("decode");
    world.settings = Some(original);
    world.decoded_settings = Some(decoded);
}

/// A settings.json shaped like the oldest releases: only the always-present
/// fields, so every later-added field must fall back to its default.
fn legacy_settings_json() -> String {
    r#"{
        "projectsRoot": "/tmp/legacy",
        "moduleZipPath": "",
        "initCommand": "echo {PROJECT_PATH}",
        "claudeCommand": "claude",
        "opencodeCommand": "opencode"
    }"#
    .to_string()
}

fn settings_for_assertion(world: &TauriWorld) -> &AppSettings {
    world
        .settings
        .as_ref()
        .or(world.decoded_settings.as_ref())
        .expect("settings or decoded_settings loaded")
}
