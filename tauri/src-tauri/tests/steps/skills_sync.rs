use std::path::{Path, PathBuf};

use cucumber::{given, then, when};

use bmad_manager_lib::models::AppSettings;
use bmad_manager_lib::services::company_context::github_contexts_in;
use bmad_manager_lib::services::skills_sync::{
    auth_header, clone_origin_url, clones_for_repo, managed_repo_dir, same_remote,
    set_remote_url_args, skills_root, SkillTool,
};

use crate::support::TauriWorld;

fn tool_from(name: &str) -> SkillTool {
    match name {
        "claude" => SkillTool::ClaudeCode,
        "codex" => SkillTool::Codex,
        other => panic!("unknown skill tool {other:?}"),
    }
}

#[when(regex = r#"^I compute the skills root for "(.+)" under home "(.+)"$"#)]
async fn compute_skills_root(world: &mut TauriWorld, tool: String, home: String) {
    world.last_managed_dir = Some(skills_root(Path::new(&home), tool_from(&tool)));
}

#[when(regex = r#"^I compute the managed repo dir for "(.+)" under home "(.+)"$"#)]
async fn compute_managed_repo(world: &mut TauriWorld, tool: String, home: String) {
    world.last_managed_dir = Some(managed_repo_dir(Path::new(&home), tool_from(&tool)));
}

#[then(regex = r#"^the skills path is "(.+)"$"#)]
async fn skills_path_is(world: &mut TauriWorld, expected: String) {
    let got = world.last_managed_dir.as_ref().expect("path computed");
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
    assert!(
        h.starts_with(&prefix),
        "header {h:?} should start with {prefix:?}"
    );
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

// --- Repointing an existing clone (the configured repo changed) ----------

#[given(regex = r#"^a skills clone whose origin is "([^"]+)"$"#)]
async fn clone_with_origin(world: &mut TauriWorld, url: String) {
    let dir = world.ensure_fake_home().join("clone");
    std::fs::create_dir_all(&dir).expect("create clone dir");
    TauriWorld::write_clone_config(&dir, Some(&url));
    world.clone_dir = Some(dir);
}

#[given("a skills clone with no git config")]
async fn clone_without_config(world: &mut TauriWorld) {
    let dir = world.ensure_fake_home().join("bare-clone");
    std::fs::create_dir_all(&dir).expect("create clone dir");
    world.clone_dir = Some(dir);
}

#[when("I read the clone's origin URL")]
async fn read_clone_origin(world: &mut TauriWorld) {
    let dir = world.clone_dir.clone().expect("clone seeded");
    world.clone_origin = Some(clone_origin_url(&dir));
}

#[then(regex = r#"^the clone origin URL is "([^"]+)"$"#)]
async fn clone_origin_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.clone_origin.clone().flatten(), Some(expected));
}

#[then("the clone has no origin URL")]
async fn clone_origin_missing(world: &mut TauriWorld) {
    assert_eq!(world.clone_origin.clone().flatten(), None);
}

#[when(regex = r#"^I compare remote "([^"]*)" with "([^"]*)"$"#)]
async fn compare_remotes(world: &mut TauriWorld, left: String, right: String) {
    world.remotes_same = Some(same_remote(&left, &right));
}

#[then("the remotes are the same")]
async fn remotes_same(world: &mut TauriWorld) {
    assert_eq!(world.remotes_same, Some(true));
}

#[then("the remotes are not the same")]
async fn remotes_differ(world: &mut TauriWorld) {
    assert_eq!(world.remotes_same, Some(false));
}

#[when(regex = r#"^I build the repoint args for "([^"]+)"$"#)]
async fn build_repoint_args(world: &mut TauriWorld, url: String) {
    world.git_args = Some(set_remote_url_args(&url));
}

#[then(regex = r#"^the git args are "([^"]+)"$"#)]
async fn git_args_are(world: &mut TauriWorld, expected: String) {
    let args = world.git_args.as_ref().expect("args built");
    assert_eq!(args.join(" "), expected);
}

// --- Which clone the shared contexts come from ---------------------------

#[given(regex = r#"^a "(claude|codex)" clone of "([^"]+)" holding context "([^"]+)"$"#)]
async fn clone_of_repo_with_context(
    world: &mut TauriWorld,
    tool: String,
    url: String,
    context: String,
) {
    world.seed_managed_clone(tool_from(&tool), Some(&url), &context);
}

#[given(
    regex = r#"^a "(claude|codex)" clone with an unreadable origin holding context "([^"]+)"$"#
)]
async fn clone_without_origin_with_context(world: &mut TauriWorld, tool: String, context: String) {
    world.seed_managed_clone(tool_from(&tool), None, &context);
}

/// Mirrors `commands::github_contexts_from_repo`: walk the clones that belong
/// to the configured repo, newest-matching first, and take the first that
/// actually holds context packs.
#[when(regex = r#"^I list the shared contexts for repo "([^"]*)"$"#)]
async fn list_shared_contexts(world: &mut TauriWorld, url: String) {
    let home = world.ensure_fake_home();
    let mut found = Vec::new();
    for repo in clones_for_repo(&home, &url) {
        let contexts = github_contexts_in(&repo);
        if !contexts.is_empty() {
            found = contexts;
            break;
        }
    }
    world.shared_contexts = Some(found);
}

#[then(regex = r#"^the shared context names are "([^"]+)"$"#)]
async fn shared_context_names_are(world: &mut TauriWorld, expected: String) {
    let names: Vec<String> = world
        .shared_contexts
        .as_ref()
        .expect("contexts listed")
        .iter()
        .map(|c| c.project_name.clone())
        .collect();
    assert_eq!(names.join(", "), expected);
}

#[then("there are no shared contexts")]
async fn no_shared_contexts(world: &mut TauriWorld) {
    let contexts = world.shared_contexts.as_ref().expect("contexts listed");
    assert!(contexts.is_empty(), "expected none, got {contexts:?}");
}

// --- Overlapping syncs ---------------------------------------------------

#[given("a skills sync gate")]
async fn a_sync_gate(_world: &mut TauriWorld) {}

#[when("two syncs run through the gate at the same time")]
async fn two_syncs_at_once(world: &mut TauriWorld) {
    world.run_two_through_gate().await;
}

#[then("the syncs did not overlap")]
async fn syncs_did_not_overlap(world: &mut TauriWorld) {
    assert_eq!(world.syncs_overlapped, Some(false));
}

#[when(regex = r#"^I list the clones for repo "([^"]*)"$"#)]
async fn list_clones(world: &mut TauriWorld, url: String) {
    let home = world.ensure_fake_home();
    world.offered_clones = Some(clones_for_repo(&home, &url));
}

#[then("one clone is offered")]
async fn one_clone_offered(world: &mut TauriWorld) {
    let clones = world.offered_clones.as_ref().expect("clones listed");
    assert_eq!(
        clones.len(),
        1,
        "expected exactly one clone, got {clones:?}"
    );
}
