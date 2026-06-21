use cucumber::{given, then, when};

use bmad_manager_lib::services::git_source::{latest_semver_tag, pinned_url};
use bmad_manager_lib::services::init_command::{posix_shell_quote, substitute};

use crate::support::TauriWorld;

#[given(regex = r#"^the init command template "(.+)"$"#)]
async fn set_template(world: &mut TauriWorld, value: String) {
    world.init_template = Some(value);
}

#[when(
    regex = r#"^I substitute with project "(.+)", project path "(.+)", module source "(.+)", module path "(.+)"$"#
)]
async fn substitute_plain(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_source: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
        &module_source,
        &module_path,
        false,
    ));
}

#[when(
    regex = r#"^I substitute for Windows with project "(.+)", project path "(.+)", module source "(.+)", module path "(.+)"$"#
)]
async fn substitute_windows(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_source: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
        &module_source,
        &module_path,
        true,
    ));
}

#[when(
    regex = r#"^I substitute for POSIX with project "(.+)", project path "(.+)", module source "(.+)", module path "(.+)"$"#
)]
async fn substitute_posix(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_source: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
        &module_source,
        &module_path,
        false,
    ));
}

#[then(regex = r#"^the substituted command is "(.*)"$"#)]
async fn substituted_command_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}

#[when(regex = r#"^I POSIX shell-quote "(.+)"$"#)]
async fn posix_shell_quote_step(world: &mut TauriWorld, input: String) {
    world.last_string = Some(posix_shell_quote(&input));
}

// --- Git installer source resolution ------------------------------------

#[when(regex = r#"^I pin url "(.*)" to ref "(.*)"$"#)]
async fn pin_url(world: &mut TauriWorld, url: String, git_ref: String) {
    world.last_string = Some(pinned_url(&url, &git_ref));
}

#[when(regex = r#"^I pick the latest semver tag from "(.*)"$"#)]
async fn pick_latest_tag(world: &mut TauriWorld, tags_csv: String) {
    // Build `git ls-remote --tags --refs`-shaped output from a comma list.
    let output: String = tags_csv
        .split(',')
        .map(|t| t.trim())
        .filter(|t| !t.is_empty())
        .map(|t| format!("{}\trefs/tags/{t}", "a".repeat(40)))
        .collect::<Vec<_>>()
        .join("\n");
    world.last_string = Some(latest_semver_tag(&output).unwrap_or_else(|| "none".to_string()));
}

#[then(regex = r#"^the result is "(.+)"$"#)]
async fn result_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}
