use std::fs;
use std::path::PathBuf;

use cucumber::{given, then, when};

use bmad_manager_lib::services::bundled_tooling;

use crate::support::TauriWorld;

#[given("a path that points at no file")]
async fn nonexistent_binary(world: &mut TauriWorld) {
    let tmp = world.ensure_tmp().to_path_buf();
    world.stub_binary = Some(tmp.join("definitely-not-here"));
}

#[given(regex = r#"^a stub binary that prints "(.+)" then "(.+)"$"#)]
async fn stub_two_line_binary(world: &mut TauriWorld, first: String, second: String) {
    let tmp = world.ensure_tmp().to_path_buf();
    let path = make_stub_binary(&tmp, "stub", &[&first, &second]);
    world.stub_binary = Some(path);
}

#[when(regex = r#"^I detect the version with "(.+)"$"#)]
async fn detect_version(world: &mut TauriWorld, arg: String) {
    let binary = world.stub_binary.as_ref().expect("stub binary set").clone();
    let result = bundled_tooling::detect_version(&binary, &[&arg]);
    world.detected_version = Some(result);
}

#[then("the detected version is unavailable")]
async fn detected_version_none(world: &mut TauriWorld) {
    let detected = world
        .detected_version
        .as_ref()
        .expect("version detection ran");
    assert!(
        detected.is_none(),
        "expected detection to return None, got {detected:?}"
    );
}

#[then(regex = r#"^the detected version is "(.+)"$"#)]
async fn detected_version_equals(world: &mut TauriWorld, expected: String) {
    let detected = world
        .detected_version
        .as_ref()
        .expect("version detection ran");
    assert_eq!(detected.as_deref(), Some(expected.as_str()));
}

#[given("a bundled npm cache containing a marker package")]
async fn bundled_cache_with_marker(world: &mut TauriWorld) {
    let tmp = world.ensure_tmp().to_path_buf();
    let bundled = tmp.join("resources").join("npm-cache");
    fs::create_dir_all(bundled.join("_cacache").join("content-v2")).unwrap();
    fs::write(
        bundled
            .join("_cacache")
            .join("content-v2")
            .join("marker.txt"),
        "bundled-marker",
    )
    .unwrap();
    world.bundled_cache_dir = Some(bundled);
}

#[given("no bundled npm cache directory exists")]
async fn no_bundled_cache(world: &mut TauriWorld) {
    let tmp = world.ensure_tmp().to_path_buf();
    world.bundled_cache_dir = Some(tmp.join("missing-bundled-cache"));
}

#[given("no user npm cache directory exists yet")]
async fn no_user_cache(world: &mut TauriWorld) {
    let tmp = world.ensure_tmp().to_path_buf();
    world.user_cache_dir = Some(tmp.join("user").join("npm-cache"));
}

#[given("the user npm cache already contains a different package")]
async fn user_cache_already_present(world: &mut TauriWorld) {
    let tmp = world.ensure_tmp().to_path_buf();
    let user = tmp.join("user").join("npm-cache");
    fs::create_dir_all(&user).unwrap();
    fs::write(user.join("existing.txt"), "existing-package").unwrap();
    world.user_cache_dir = Some(user);
}

#[when("I seed the user npm cache from the bundled cache")]
async fn run_seed(world: &mut TauriWorld) {
    let bundled = world
        .bundled_cache_dir
        .as_ref()
        .expect("bundled cache path set");
    let user = world.user_cache_dir.as_ref().expect("user cache path set");
    let copied = bundled_tooling::seed_user_npm_cache(bundled, user).expect("seed succeeded");
    world.seed_outcome = Some(copied);
}

#[then("the seed reports it copied the cache")]
async fn seed_copied(world: &mut TauriWorld) {
    assert_eq!(world.seed_outcome, Some(true));
}

#[then("the seed reports it left the existing cache alone")]
async fn seed_noop(world: &mut TauriWorld) {
    assert_eq!(world.seed_outcome, Some(false));
}

#[then("the user npm cache contains the marker package")]
async fn user_has_marker(world: &mut TauriWorld) {
    let user = world.user_cache_dir.as_ref().expect("user cache path set");
    let marker = user.join("_cacache").join("content-v2").join("marker.txt");
    assert!(
        marker.exists(),
        "expected {marker:?} to exist after seeding"
    );
}

#[then("the user npm cache still contains the original package")]
async fn user_keeps_original(world: &mut TauriWorld) {
    let user = world.user_cache_dir.as_ref().expect("user cache path set");
    assert!(user.join("existing.txt").exists());
}

#[then("the user npm cache does not contain the marker package")]
async fn user_no_marker(world: &mut TauriWorld) {
    let user = world.user_cache_dir.as_ref().expect("user cache path set");
    let marker = user.join("_cacache").join("content-v2").join("marker.txt");
    assert!(
        !marker.exists(),
        "expected {marker:?} to be absent — seed should have left the cache alone"
    );
}

// Cross-platform stub: on Unix writes a shell script with the given
// echo lines; on Windows writes a .cmd that does the same. Returns the
// absolute path callers should hand to `detect_version`.
fn make_stub_binary(dir: &std::path::Path, name: &str, lines: &[&str]) -> PathBuf {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let path = dir.join(name);
        let mut body = String::from("#!/bin/sh\n");
        for line in lines {
            body.push_str(&format!("echo \"{line}\"\n"));
        }
        fs::write(&path, body).unwrap();
        let mut perms = fs::metadata(&path).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&path, perms).unwrap();
        path
    }
    #[cfg(windows)]
    {
        let path = dir.join(format!("{name}.cmd"));
        let mut body = String::from("@echo off\r\n");
        for line in lines {
            body.push_str(&format!("echo {line}\r\n"));
        }
        fs::write(&path, body).unwrap();
        path
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (dir, name, lines);
        unimplemented!("stub binary helper not implemented for this OS")
    }
}
