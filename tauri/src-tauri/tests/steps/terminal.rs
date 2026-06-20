use cucumber::{then, when};

use bmad_manager_lib::models::{NewSessionPlacement, ShellKind};
use bmad_manager_lib::services::terminal::{
    fallback_cmd_args, shell_argv, wt_args, APP_WINDOW_NAME,
};

use crate::support::TauriWorld;

fn parse_shell(kind: &str) -> ShellKind {
    match kind {
        "cmd" => ShellKind::Cmd,
        "powershell" => ShellKind::PowerShell,
        "pwsh" => ShellKind::Pwsh,
        _ => unreachable!("unknown shell kind {kind}"),
    }
}

fn parse_placement(placement: &str) -> NewSessionPlacement {
    match placement {
        "newWindow" => NewSessionPlacement::NewWindow,
        "newTab" => NewSessionPlacement::NewTab,
        _ => unreachable!("unknown placement {placement}"),
    }
}

#[when(regex = r#"^I build the shell invocation for "(cmd|powershell|pwsh)" running "(.+)"$"#)]
async fn build_shell_invocation(world: &mut TauriWorld, kind: String, command: String) {
    world.last_string = Some(shell_argv(parse_shell(&kind), &command).join(" "));
}

#[then(regex = r#"^the shell invocation is "(.+)"$"#)]
async fn shell_invocation_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}

#[when(
    regex = r#"^I build the Windows Terminal args for placement "(newWindow|newTab)" shell "(cmd|powershell|pwsh)" running "(.+)" in "(.+)"$"#
)]
async fn build_wt_args(
    world: &mut TauriWorld,
    placement: String,
    kind: String,
    command: String,
    cwd: String,
) {
    let inner = shell_argv(parse_shell(&kind), &command);
    let args = wt_args(parse_placement(&placement), APP_WINDOW_NAME, &cwd, &inner);
    world.last_string = Some(args.join(" "));
}

#[then(regex = r#"^the Windows Terminal args are "(.+)"$"#)]
async fn wt_args_are(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}

#[when(regex = r#"^I build the fallback args for shell "(cmd|powershell|pwsh)" running "(.+)"$"#)]
async fn build_fallback_args(world: &mut TauriWorld, kind: String, command: String) {
    let inner = shell_argv(parse_shell(&kind), &command);
    world.last_string = Some(fallback_cmd_args(&inner).join(" "));
}

#[then(regex = r#"^the fallback args are "(.+)"$"#)]
async fn fallback_args_are(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}
