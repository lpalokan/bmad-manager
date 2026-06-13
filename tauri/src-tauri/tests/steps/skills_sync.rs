use std::path::{Path, PathBuf};

use cucumber::{given, then, when};

use bmad_manager_lib::models::AppSettings;
use bmad_manager_lib::services::skills_sync::{auth_header, managed_dir, SkillTool};

use crate::support::TauriWorld;

fn tool_from(name: &str) -> SkillTool {
    match name {
        "claude" => SkillTool::ClaudeCode,
        "codex" => SkillTool::Codex,
        other => panic!("unknown skill tool {other:?}"),
    }
}

#[when(regex = r#"^I compute the managed skills dir for "(.+)" under home "(.+)"$"#)]
async fn compute_managed_dir(world: &mut TauriWorld, tool: String, home: String) {
    world.last_managed_dir = Some(managed_dir(Path::new(&home), tool_from(&tool)));
}

#[then(regex = r#"^the managed skills dir is "(.+)"$"#)]
async fn managed_dir_is(world: &mut TauriWorld, expected: String) {
    let got = world.last_managed_dir.as_ref().expect("managed dir computed");
    // Compare as paths so the assertion is separator-insensitive on Windows.
    assert_eq!(got, &PathBuf::from(expected));
}

#[when(regex = r#"^I build the skills auth header for token "(.+)"$"#)]
async fn build_auth_header(world: &mut TauriWorld, token: String) {
    world.last_string = Some(auth_header(&token));
}

#[then(regex = r#"^the skills auth header starts with "(.+)"$"#)]
async fn header_starts_with(world: &mut TauriWorld, prefix: String) {
    let h = world.last_string.as_ref().expect("header built");
    assert!(h.starts_with(&prefix), "header {h:?} should start with {prefix:?}");
}

#[then(regex = r#"^the skills auth header does not contain "(.+)"$"#)]
async fn header_excludes(world: &mut TauriWorld, needle: String) {
    let h = world.last_string.as_ref().expect("header built");
    assert!(!h.contains(&needle), "header must not leak {needle:?}");
}

#[given(regex = r#"^skills settings with repo "(.+)" and branch "(.+)"$"#)]
async fn skills_settings(world: &mut TauriWorld, repo: String, branch: String) {
    let mut s = AppSettings::defaults();
    s.skills_repo_url = repo;
    s.skills_repo_branch = branch;
    world.settings = Some(s);
}

#[when("I encode and decode the skills settings")]
async fn encode_decode(world: &mut TauriWorld) {
    let s = world.settings.as_ref().expect("settings set");
    let json = serde_json::to_string(s).expect("encode");
    world.decoded_settings = Some(serde_json::from_str(&json).expect("decode"));
}

#[given("a legacy settings JSON without skills fields")]
async fn legacy_settings_json(world: &mut TauriWorld) {
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

#[when("I decode the legacy settings")]
async fn decode_legacy(world: &mut TauriWorld) {
    let json = world.raw_json.as_ref().expect("legacy json set");
    world.decoded_settings = Some(serde_json::from_str(json).expect("decode legacy"));
}

#[then(regex = r#"^the decoded skills repo URL is "(.*)"$"#)]
async fn decoded_url_is(world: &mut TauriWorld, expected: String) {
    let s = world.decoded_settings.as_ref().expect("decoded settings");
    assert_eq!(s.skills_repo_url, expected);
}

#[then(regex = r#"^the decoded skills repo branch is "(.+)"$"#)]
async fn decoded_branch_is(world: &mut TauriWorld, expected: String) {
    let s = world.decoded_settings.as_ref().expect("decoded settings");
    assert_eq!(s.skills_repo_branch, expected);
}
