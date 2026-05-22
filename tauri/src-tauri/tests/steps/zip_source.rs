use std::path::PathBuf;

use cucumber::{given, then, when};

use bmad_manager_lib::services::zip_source::{extract_zip, module_root, ZipError};

use crate::support::TauriWorld;

#[given(regex = r#"^a directory containing exactly one subdirectory "(.+)"$"#)]
async fn dir_with_one_subdir(world: &mut TauriWorld, name: String) {
    let dir = world.ensure_tmp().join("zip-fixture");
    let sub = dir.join(&name);
    std::fs::create_dir_all(&sub).expect("mkdir subdir");
    std::fs::write(sub.join("manifest.yaml"), "x").expect("write manifest");
    world.projects_root = Some(dir);
}

#[given(regex = r#"^a directory containing files "(.+)" and "(.+)"$"#)]
async fn dir_with_two_files(world: &mut TauriWorld, a: String, b: String) {
    let dir = world.ensure_tmp().join("zip-fixture-flat");
    std::fs::create_dir_all(&dir).expect("mkdir flat");
    std::fs::write(dir.join(&a), "x").expect("write a");
    std::fs::write(dir.join(&b), "y").expect("write b");
    world.projects_root = Some(dir);
}

#[given(
    regex = r#"^a directory containing exactly one subdirectory "(.+)" plus a __MACOSX sibling$"#
)]
async fn dir_with_subdir_and_macosx(world: &mut TauriWorld, name: String) {
    let dir = world.ensure_tmp().join("zip-fixture-mac");
    let sub = dir.join(&name);
    let mac = dir.join("__MACOSX");
    std::fs::create_dir_all(&sub).expect("mkdir sub");
    std::fs::create_dir_all(&mac).expect("mkdir mac");
    world.projects_root = Some(dir);
}

#[given(regex = r#"^a directory containing exactly one file "(.+)"$"#)]
async fn dir_with_one_file(world: &mut TauriWorld, name: String) {
    let dir = world.ensure_tmp().join("zip-fixture-solefile");
    std::fs::create_dir_all(&dir).expect("mkdir");
    std::fs::write(dir.join(&name), "x").expect("write");
    world.projects_root = Some(dir);
}

#[when("I ask for its module root")]
async fn ask_module_root(world: &mut TauriWorld) {
    let dir = world.projects_root.as_ref().expect("dir set");
    let root = module_root(dir);
    world.last_string = Some(root.to_string_lossy().into_owned());
}

#[then(regex = r#"^the module root is the "(.+)" subdirectory$"#)]
async fn module_root_is_subdir(world: &mut TauriWorld, name: String) {
    let dir = world.projects_root.as_ref().expect("dir set");
    let expected: PathBuf = dir.join(&name);
    let actual = world.last_string.as_ref().expect("module root captured");
    assert_eq!(actual, &expected.to_string_lossy().into_owned());
}

#[then("the module root is the directory itself")]
async fn module_root_is_directory(world: &mut TauriWorld) {
    let dir = world.projects_root.as_ref().expect("dir set");
    let actual = world.last_string.as_ref().expect("module root captured");
    assert_eq!(actual, &dir.to_string_lossy().into_owned());
}

#[given("an empty zip path")]
async fn empty_zip_path(world: &mut TauriWorld) {
    world.last_string = Some("   ".to_string());
}

#[given("a zip path that does not exist")]
async fn nonexistent_zip_path(world: &mut TauriWorld) {
    let path = world.ensure_tmp().join("does-not-exist.zip");
    world.last_string = Some(path.to_string_lossy().into_owned());
}

#[when("I extract the zip")]
async fn extract_zip_step(world: &mut TauriWorld) {
    let path = world.last_string.clone().unwrap_or_default();
    match extract_zip(&path) {
        Ok(_) => world.last_string_error = None,
        Err(err) => {
            world.last_string_error = Some(match err {
                ZipError::NotConfigured => "not configured".to_string(),
                ZipError::ZipNotFound(_) => "zip not found".to_string(),
                ZipError::ExtractionFailed(_) => "extraction failed".to_string(),
            });
        }
    }
}

#[then(regex = r#"^it fails with a "(not configured|zip not found)" error$"#)]
async fn fails_with_zip_error(world: &mut TauriWorld, kind: String) {
    assert_eq!(world.last_string_error.as_deref(), Some(kind.as_str()));
}
