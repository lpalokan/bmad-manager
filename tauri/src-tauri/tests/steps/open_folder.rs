use cucumber::{then, when};

use bmad_manager_lib::commands;

use crate::support::TauriWorld;

#[when("I try to open a project folder that does not exist")]
async fn open_missing_folder(world: &mut TauriWorld) {
    let missing = world.ensure_tmp().to_path_buf().join("definitely-not-here");
    let result = commands::open_project_folder(missing.to_string_lossy().into_owned());
    world.last_string_error = result.err().map(|e| e.0);
}

#[then("opening the folder fails because it is missing")]
async fn open_folder_failed_missing(world: &mut TauriWorld) {
    let err = world
        .last_string_error
        .as_deref()
        .expect("expected an error when opening a missing folder");
    assert!(
        err.contains("exist"),
        "error should explain the folder no longer exists, got: {err}"
    );
}
