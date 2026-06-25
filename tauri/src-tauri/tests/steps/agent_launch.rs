use cucumber::{given, then, when};

use bmad_manager_lib::models::AgentLaunchMethod;
use bmad_manager_lib::services::agent_launch::{resolve, ResolvedAgentLaunch};

use crate::support::TauriWorld;

#[given(regex = r#"^the launch method "(auto|app|cli)"$"#)]
async fn the_launch_method(world: &mut TauriWorld, method: String) {
    world.launch_method = Some(parse_launch_method(&method));
}

#[given("the agent app is installed")]
async fn agent_app_installed(world: &mut TauriWorld) {
    world.app_installed = Some(true);
}

#[given("the agent app is not installed")]
async fn agent_app_not_installed(world: &mut TauriWorld) {
    world.app_installed = Some(false);
}

#[when("I resolve the launch")]
async fn resolve_the_launch(world: &mut TauriWorld) {
    let method = world.launch_method.expect("launch method set");
    let installed = world.app_installed.expect("install state set");
    world.resolved_launch = Some(resolve(method, installed));
}

#[then(regex = r#"^the resolved launch is "(app|cli)"$"#)]
async fn resolved_launch_is(world: &mut TauriWorld, expected: String) {
    let resolved = world.resolved_launch.expect("launch resolved");
    let want = match expected.as_str() {
        "app" => ResolvedAgentLaunch::App,
        "cli" => ResolvedAgentLaunch::Cli,
        _ => unreachable!(),
    };
    assert_eq!(resolved, want);
}

pub fn parse_launch_method(method: &str) -> AgentLaunchMethod {
    match method {
        "auto" => AgentLaunchMethod::Auto,
        "app" => AgentLaunchMethod::App,
        "cli" => AgentLaunchMethod::Cli,
        _ => unreachable!(),
    }
}
