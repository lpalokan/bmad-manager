use cucumber::{given, then, when};

use bmad_manager_lib::services::contribution::{
    enumerate_personal_skills, parse_owner_repo, prepare_context_files, prepare_skill_files,
    sanitize_name,
};
use bmad_manager_lib::services::skills_sync::{skills_root, SkillTool};

use crate::support::TauriWorld;

fn split_list(list: &str) -> Vec<String> {
    list.split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

// --- Repo URL parsing ---

#[when(regex = r#"^I parse the contribution repo URL "([^"]*)"$"#)]
async fn parse_repo_url(world: &mut TauriWorld, url: String) {
    world.parsed_owner_repo = Some(parse_owner_repo(&url));
}

#[then(regex = r#"^the parsed owner is "([^"]+)" and repo is "([^"]+)"$"#)]
async fn parsed_owner_repo(world: &mut TauriWorld, owner: String, repo: String) {
    let parsed = world
        .parsed_owner_repo
        .clone()
        .expect("parse ran")
        .expect("URL parsed");
    assert_eq!(parsed, (owner, repo));
}

#[then("the repo URL is not parseable")]
async fn repo_url_not_parseable(world: &mut TauriWorld) {
    let parsed = world.parsed_owner_repo.clone().expect("parse ran");
    assert!(parsed.is_none(), "expected None, got {parsed:?}");
}

// --- Skills enumeration ---

#[given(regex = r#"^a personal skill "([^"]+)" in the skills folder$"#)]
async fn personal_skill(world: &mut TauriWorld, name: String) {
    let home = world.ensure_contrib_home();
    let dir = skills_root(&home, SkillTool::ClaudeCode).join(&name);
    std::fs::create_dir_all(&dir).expect("create skill dir");
    std::fs::write(dir.join("SKILL.md"), format!("# {name}")).expect("write SKILL.md");
}

#[given(regex = r#"^a managed linked skill "([^"]+)" in the skills folder$"#)]
async fn managed_linked_skill(world: &mut TauriWorld, name: String) {
    let home = world.ensure_contrib_home();
    let target = home.join("skills-managed").join(&name);
    std::fs::create_dir_all(&target).expect("create managed target");
    std::fs::write(target.join("SKILL.md"), "managed").expect("write managed SKILL.md");
    let link = skills_root(&home, SkillTool::ClaudeCode).join(&name);
    std::fs::create_dir_all(link.parent().unwrap()).expect("create skills root");
    #[cfg(unix)]
    std::os::unix::fs::symlink(&target, &link).expect("symlink managed skill");
    #[cfg(not(unix))]
    {
        // On non-unix the BDD suite runs on the file backend; emulate a link
        // by leaving it absent so the scenario still asserts "only personal".
        let _ = (&target, &link);
    }
}

#[when("I list contributable skills")]
async fn list_contributable(world: &mut TauriWorld) {
    let home = world.ensure_contrib_home();
    world.contributable_skills = Some(enumerate_personal_skills(&home));
}

#[then(regex = r#"^the contributable skills are exactly "([^"]*)"$"#)]
async fn contributable_skills_exactly(world: &mut TauriWorld, list: String) {
    let skills = world
        .contributable_skills
        .as_ref()
        .expect("enumeration ran");
    let names: Vec<String> = skills.iter().map(|s| s.name.clone()).collect();
    assert_eq!(names, split_list(&list));
}

// --- Staging files ---

#[when(regex = r#"^I stage the contribution files for skill "([^"]+)"$"#)]
async fn stage_skill(world: &mut TauriWorld, name: String) {
    let home = world.ensure_contrib_home();
    let dir = skills_root(&home, SkillTool::ClaudeCode).join(&name);
    world.prepared_files = Some(prepare_skill_files(&name, &dir).expect("stage skill"));
}

#[given(regex = r#"^a contributable context "([^"]+)" with files "([^"]*)"$"#)]
async fn contributable_context(world: &mut TauriWorld, name: String, files: String) {
    let home = world.ensure_contrib_home();
    let dir = home.join("contexts").join(&name);
    std::fs::create_dir_all(&dir).expect("create context dir");
    for file in split_list(&files) {
        std::fs::write(dir.join(&file), format!("content of {file}")).expect("write context file");
    }
}

#[when(regex = r#"^I stage the contribution files for context "([^"]+)"$"#)]
async fn stage_context(world: &mut TauriWorld, name: String) {
    let home = world.ensure_contrib_home();
    let dir = home.join("contexts").join(&name);
    // Offer every recognized name; prepare keeps only those present.
    let selected: Vec<String> = bmad_manager_lib::models::company_context::RECOGNIZED_FILE_NAMES
        .iter()
        .map(|s| s.to_string())
        .collect();
    world.prepared_files =
        Some(prepare_context_files(&name, &dir, &selected).expect("stage context"));
}

#[then(regex = r#"^a staged file path is "([^"]+)"$"#)]
async fn staged_file_path_is(world: &mut TauriWorld, path: String) {
    let files = world.prepared_files.as_ref().expect("files staged");
    assert!(
        files.iter().any(|f| f.repo_path == path),
        "expected a staged file {path:?}, got {:?}",
        files.iter().map(|f| &f.repo_path).collect::<Vec<_>>()
    );
}

#[then(regex = r#"^no staged file path is "([^"]+)"$"#)]
async fn no_staged_file_path(world: &mut TauriWorld, path: String) {
    let files = world.prepared_files.as_ref().expect("files staged");
    assert!(
        !files.iter().any(|f| f.repo_path == path),
        "did not expect a staged file {path:?}"
    );
}

// --- Name safety ---

#[when(regex = r#"^I sanitize the contribution name "([^"]*)"$"#)]
async fn sanitize_contribution_name(world: &mut TauriWorld, name: String) {
    match sanitize_name(&name) {
        Ok(safe) => {
            world.last_string = Some(safe);
            world.last_string_error = None;
        }
        Err(e) => {
            world.last_string = None;
            world.last_string_error = Some(e.to_string());
        }
    }
}

#[then("the contribution name is rejected")]
async fn name_rejected(world: &mut TauriWorld) {
    assert!(
        world.last_string_error.is_some(),
        "expected the name to be rejected"
    );
}

#[then(regex = r#"^the sanitized contribution name is "([^"]+)"$"#)]
async fn sanitized_name_is(world: &mut TauriWorld, expected: String) {
    assert_eq!(world.last_string.as_deref(), Some(expected.as_str()));
}
