use std::ffi::OsString;
use std::path::PathBuf;

use cucumber::{given, then, when};

use bmad_manager_lib::services::path_detection;

use crate::support::TauriWorld;

#[given(regex = r#"^a PATH directory containing an executable named "(.+)"$"#)]
async fn path_dir_with_executable(world: &mut TauriWorld, name: String) {
    let dir = world.ensure_tmp().join("path-dir");
    std::fs::create_dir_all(&dir).expect("mkdir path-dir");
    let exe = dir.join(&name);
    write_executable(&exe);
    world.last_path_dir = Some(dir);
    world.last_executable_path = Some(exe);
}

#[given("a PATH directory with no matching executable")]
async fn empty_path_dir(world: &mut TauriWorld) {
    let dir = world.ensure_tmp().join("empty-path-dir");
    std::fs::create_dir_all(&dir).expect("mkdir empty-path-dir");
    world.last_path_dir = Some(dir);
}

#[given("a file that exists on disk")]
async fn file_that_exists(world: &mut TauriWorld) {
    let dir = world.ensure_tmp().join("abs-dir");
    std::fs::create_dir_all(&dir).expect("mkdir abs-dir");
    let file = dir.join("some-binary");
    write_executable(&file);
    world.last_executable_path = Some(file);
}

#[when(regex = r#"^I detect the command "(.+)" against that PATH$"#)]
async fn detect_against_dir(world: &mut TauriWorld, command: String) {
    let dir = world.last_path_dir.clone().expect("PATH directory set");
    let path_env = OsString::from(dir);
    world.last_detection = Some(path_detection::detect_command_in_path(
        &command,
        Some(path_env.as_os_str()),
    ));
}

#[when("I detect that file's absolute path against an empty PATH")]
async fn detect_absolute_against_empty(world: &mut TauriWorld) {
    let abs = world
        .last_executable_path
        .clone()
        .expect("absolute path set");
    let command = abs.to_string_lossy().into_owned();
    let empty = OsString::new();
    world.last_detection = Some(path_detection::detect_command_in_path(
        &command,
        Some(empty.as_os_str()),
    ));
}

#[when(regex = r#"^I detect the command "(.+)" against an empty PATH$"#)]
async fn detect_against_empty(world: &mut TauriWorld, command: String) {
    let empty = OsString::new();
    world.last_detection = Some(path_detection::detect_command_in_path(
        &command,
        Some(empty.as_os_str()),
    ));
}

#[then("the detection returns the absolute path to that executable")]
async fn detection_returns_executable(world: &mut TauriWorld) {
    let expected = world
        .last_executable_path
        .clone()
        .expect("executable path set");
    let got = world
        .last_detection
        .clone()
        .expect("detection ran")
        .expect("detection returned Some(_)");
    assert_eq!(got, expected);
}

#[then("the detection returns nothing")]
async fn detection_returns_nothing(world: &mut TauriWorld) {
    let got = world.last_detection.clone().expect("detection ran");
    assert!(got.is_none(), "expected None, got {got:?}");
}

#[then("the detection returns that same absolute path")]
async fn detection_returns_same_absolute(world: &mut TauriWorld) {
    let expected = world
        .last_executable_path
        .clone()
        .expect("executable path set");
    let got = world
        .last_detection
        .clone()
        .expect("detection ran")
        .expect("detection returned Some(_)");
    assert_eq!(got, expected);
}

#[cfg(unix)]
fn write_executable(path: &PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, "#!/bin/sh\nexit 0\n").expect("write fake exe");
    let mut perms = std::fs::metadata(path).expect("stat fake exe").permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(path, perms).expect("chmod fake exe");
}

#[cfg(windows)]
fn write_executable(path: &PathBuf) {
    // On Windows the detection logic checks for files with executable
    // extensions (.exe / .cmd / .bat); a plain file with no extension
    // is treated as not executable. Write an empty .exe alongside any
    // existing extensionless path so both shapes of test work.
    std::fs::write(path, b"").expect("write fake exe");
    if path.extension().is_none() {
        let with_ext = path.with_extension("exe");
        std::fs::write(&with_ext, b"").expect("write fake .exe");
    }
}
