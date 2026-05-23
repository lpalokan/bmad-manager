use cucumber::{given, then, when};

use bmad_manager_lib::models::{AppSettings, ModuleSourceKind, ProjectSortOrder, TerminalKind};

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

fn settings_for_assertion(world: &TauriWorld) -> &AppSettings {
    world
        .settings
        .as_ref()
        .or(world.decoded_settings.as_ref())
        .expect("settings or decoded_settings loaded")
}
