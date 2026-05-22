use cucumber::{given, then, when};

use bmad_manager_lib::models::ProjectSortOrder;
use bmad_manager_lib::services::project_service::{
    create_project_folder, list_projects, ProjectError,
};

use crate::support::TauriWorld;

#[given("an empty projects root directory")]
async fn empty_projects_root(world: &mut TauriWorld) {
    world.ensure_projects_root();
}

#[given("a nonexistent projects root directory")]
async fn nonexistent_projects_root(world: &mut TauriWorld) {
    let path = world.ensure_tmp().join("does-not-exist-yet");
    world.nonexistent_root = Some(path.clone());
    world.projects_root = Some(path);
}

#[given(regex = r#"^a project named "(.+)" already exists$"#)]
async fn project_already_exists(world: &mut TauriWorld, name: String) {
    let root = world.ensure_projects_root();
    create_project_folder(&name, &root).expect("seed project folder");
}

#[given(regex = r#"^a project named "(.+)" exists$"#)]
async fn project_exists(world: &mut TauriWorld, name: String) {
    let root = world.ensure_projects_root();
    create_project_folder(&name, &root).expect("seed project folder");
}

#[given(regex = r#"^projects named (.+) exist$"#)]
async fn projects_exist(world: &mut TauriWorld, list: String) {
    let root = world.ensure_projects_root();
    for raw in list.split(',') {
        let name = raw.trim().trim_matches('"');
        create_project_folder(name, &root).expect("seed project folder");
    }
}

#[given(regex = r#"^a loose file "(.+)" exists at the projects root$"#)]
async fn loose_file_exists(world: &mut TauriWorld, name: String) {
    let root = world.ensure_projects_root();
    std::fs::write(root.join(&name), "x").expect("write loose file");
}

#[when(regex = r#"^I (?:try to )?create a project named "(.*)"$"#)]
async fn try_create_project(world: &mut TauriWorld, name: String) {
    let root = world.ensure_projects_root();
    match create_project_folder(&name, &root) {
        Ok(_) => {
            world.last_string_error = None;
        }
        Err(err) => {
            world.last_string_error = Some(err.kind_label().to_string());
        }
    }
}

#[then(regex = r#"^it fails with an "invalid name" error$"#)]
async fn fails_invalid_name(world: &mut TauriWorld) {
    assert_eq!(
        world.last_string_error.as_deref(),
        Some(ProjectError::INVALID_NAME)
    );
}

#[then(regex = r#"^it fails with a "project exists" error$"#)]
async fn fails_project_exists(world: &mut TauriWorld) {
    assert_eq!(
        world.last_string_error.as_deref(),
        Some(ProjectError::PROJECT_EXISTS)
    );
}

#[then(regex = r#"^a folder named "(.+)" exists at the projects root$"#)]
async fn folder_exists_at_root(world: &mut TauriWorld, name: String) {
    let root = world.projects_root.as_ref().expect("root set");
    assert!(
        root.join(&name).is_dir(),
        "expected {name} to exist at {root:?}"
    );
}

#[then("the projects root now exists")]
async fn projects_root_now_exists(world: &mut TauriWorld) {
    let root = world.projects_root.as_ref().expect("root set");
    assert!(root.is_dir(), "expected projects root to exist at {root:?}");
}

#[when(regex = r#"^I list projects sorted by "(nameAscending|dateNewestFirst|dateOldestFirst)"$"#)]
async fn list_projects_step(world: &mut TauriWorld, order: String) {
    let root = world
        .projects_root
        .clone()
        .or_else(|| world.nonexistent_root.clone())
        .unwrap_or_else(|| world.ensure_projects_root());
    let order = match order.as_str() {
        "nameAscending" => ProjectSortOrder::NameAscending,
        "dateNewestFirst" => ProjectSortOrder::DateNewestFirst,
        "dateOldestFirst" => ProjectSortOrder::DateOldestFirst,
        _ => unreachable!(),
    };
    world.listed_projects = list_projects(&root, order);
}

#[then(regex = r#"^the listed names are exactly ?(.*)$"#)]
async fn listed_names(world: &mut TauriWorld, list: String) {
    let expected: Vec<&str> = if list.trim().is_empty() {
        Vec::new()
    } else {
        list.split(',')
            .map(|s| s.trim().trim_matches('"'))
            .collect()
    };
    let actual: Vec<&str> = world
        .listed_projects
        .iter()
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(actual, expected);
}
