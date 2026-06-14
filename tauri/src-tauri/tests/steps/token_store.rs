use std::path::PathBuf;

use cucumber::{given, then, when};

use bmad_manager_lib::services::token_store;

use crate::support::TauriWorld;

#[when(regex = r#"^I store the github token "(.*)"$"#)]
async fn store_token(world: &mut TauriWorld, token: String) {
    let scope = world.ensure_token_scope();
    token_store::save(&scope, &token).expect("store token");
}

#[given(regex = r#"^I have stored the github token "(.*)"$"#)]
async fn have_stored_token(world: &mut TauriWorld, token: String) {
    let scope = world.ensure_token_scope();
    token_store::save(&scope, &token).expect("store token");
}

#[when("I clear the github token")]
async fn clear_token(world: &mut TauriWorld) {
    let scope = world.ensure_token_scope();
    token_store::clear(&scope).expect("clear token");
}

#[then("a github token is reported as stored")]
async fn token_is_stored(world: &mut TauriWorld) {
    let scope = world.ensure_token_scope();
    assert!(token_store::is_set(&scope), "expected a token to be stored");
}

#[then("no github token is reported as stored")]
async fn token_is_not_stored(world: &mut TauriWorld) {
    let scope = world.ensure_token_scope();
    assert!(
        !token_store::is_set(&scope),
        "expected no token to be stored"
    );
}

#[then(regex = r#"^reading the github token returns "(.*)"$"#)]
async fn reading_returns(world: &mut TauriWorld, expected: String) {
    let scope = world.ensure_token_scope();
    let got = token_store::load(&scope).expect("load token");
    assert_eq!(got.as_deref(), Some(expected.as_str()));
}

#[then("no settings.json file is created in the token store location")]
async fn no_settings_json(world: &mut TauriWorld) {
    let scope = world.ensure_token_scope();
    assert!(
        !scope.join("settings.json").exists(),
        "token storage must not create settings.json"
    );
}

#[then("the token is not stored in a world-readable plaintext file")]
async fn not_world_readable(world: &mut TauriWorld) {
    let scope = world.ensure_token_scope();
    let files: Vec<PathBuf> = std::fs::read_dir(&scope)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .collect();

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // The dev/CI stub keeps the token in a fallback file; it must exist and
        // be owner-only (no group/other bits) so other OS users can't read it.
        assert!(
            !files.is_empty(),
            "stub fallback should have written a token file"
        );
        for path in &files {
            let mode = std::fs::metadata(path)
                .expect("metadata")
                .permissions()
                .mode();
            assert_eq!(
                mode & 0o077,
                0,
                "token file {path:?} must not be group/other accessible (mode {mode:o})"
            );
        }
    }
    #[cfg(not(unix))]
    {
        // On platforms with an OS credential store (Windows Credential Manager),
        // no plaintext token file is written to disk at all.
        assert!(
            files.is_empty(),
            "no plaintext token file should exist when an OS credential store is used: {files:?}"
        );
    }
}
