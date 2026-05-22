use cucumber::{given, then, when};

use bmad_manager_lib::services::init_command::{posix_shell_quote, substitute};

use crate::support::TauriWorld;

#[given(regex = r#"^the init command template "(.+)"$"#)]
async fn set_template(world: &mut TauriWorld, value: String) {
    world.init_template = Some(value);
}

#[when(regex = r#"^I substitute with project "(.+)", project path "(.+)", module path "(.+)"$"#)]
async fn substitute_plain(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
        &module_path,
        false,
    ));
}

#[when(
    regex = r#"^I substitute for Windows with project "(.+)", project path "(.+)", module path "(.+)"$"#
)]
async fn substitute_windows(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
        &module_path,
        true,
    ));
}

#[when(
    regex = r#"^I substitute for POSIX with project "(.+)", project path "(.+)", module path "(.+)"$"#
)]
async fn substitute_posix(
    world: &mut TauriWorld,
    name: String,
    project_path: String,
    module_path: String,
) {
    let template = world.init_template.as_ref().expect("template set");
    world.last_string = Some(substitute(
        template,
        &name,
        &project_path,
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

#[then(regex = r#"^the result is "(.+)"$"#)]
async fn result_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}
