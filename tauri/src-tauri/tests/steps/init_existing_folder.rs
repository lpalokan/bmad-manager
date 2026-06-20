use cucumber::{given, then, when};

use bmad_manager_lib::services::project_service::{inspect_init_target, use_existing_folder};

use crate::support::TauriWorld;

#[given(regex = r#"^an existing folder "(.+)"$"#)]
async fn an_existing_folder(world: &mut TauriWorld, name: String) {
    let path = world.ensure_tmp().join(&name);
    std::fs::create_dir_all(&path).expect("create existing folder");
    world.init_target = Some(path);
}

#[given(regex = r#"^a path "(.+)" that does not exist$"#)]
async fn a_missing_path(world: &mut TauriWorld, name: String) {
    let path = world.ensure_tmp().join(&name);
    world.init_target = Some(path);
}

#[given(regex = r#"^the folder contains a file "(.+)"$"#)]
async fn folder_contains_file(world: &mut TauriWorld, name: String) {
    let folder = world.init_target.clone().expect("init target set");
    std::fs::write(folder.join(&name), "x").expect("write file");
}

#[given(regex = r#"^the folder contains a "(.+)" marker directory$"#)]
async fn folder_contains_marker(world: &mut TauriWorld, marker: String) {
    let folder = world.init_target.clone().expect("init target set");
    std::fs::create_dir_all(folder.join(&marker)).expect("create marker dir");
}

#[when("I prepare to initialize that folder")]
async fn prepare_to_initialize(world: &mut TauriWorld) {
    let folder = world.init_target.clone().expect("init target set");
    match use_existing_folder(&folder) {
        Ok(item) => {
            world.last_string = Some(item.name);
            world.last_string_error = None;
        }
        Err(err) => {
            world.last_string = None;
            world.last_string_error = Some(err.kind_label().to_string());
        }
    }
}

#[when("I inspect that folder as an init target")]
async fn inspect_target(world: &mut TauriWorld) {
    let folder = world.init_target.clone().expect("init target set");
    world.init_target_info = Some(inspect_init_target(&folder));
}

#[then(regex = r#"^the init target is accepted with name "(.+)"$"#)]
async fn accepted_with_name(world: &mut TauriWorld, name: String) {
    assert_eq!(world.last_string_error, None);
    assert_eq!(world.last_string.as_deref(), Some(name.as_str()));
}

#[then("the init target is rejected as not a folder")]
async fn rejected_not_a_folder(world: &mut TauriWorld) {
    assert_eq!(
        world.last_string_error.as_deref(),
        Some(bmad_manager_lib::services::project_service::ProjectError::FOLDER_NOT_A_DIRECTORY)
    );
}

#[then("the init target reports it exists")]
async fn reports_exists(world: &mut TauriWorld) {
    assert!(world.init_target_info.as_ref().expect("inspected").exists);
}

#[then("the init target reports it is empty")]
async fn reports_empty(world: &mut TauriWorld) {
    assert!(world.init_target_info.as_ref().expect("inspected").is_empty);
}

#[then("the init target reports it is not empty")]
async fn reports_not_empty(world: &mut TauriWorld) {
    assert!(!world.init_target_info.as_ref().expect("inspected").is_empty);
}

#[then("the init target reports no BMAD install")]
async fn reports_no_bmad(world: &mut TauriWorld) {
    assert!(!world.init_target_info.as_ref().expect("inspected").has_bmad);
}

#[then("the init target reports a BMAD install")]
async fn reports_bmad(world: &mut TauriWorld) {
    assert!(world.init_target_info.as_ref().expect("inspected").has_bmad);
}
