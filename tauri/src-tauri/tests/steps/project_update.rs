use std::path::PathBuf;

use cucumber::{given, then, when};

use bmad_manager_lib::models::{AppSettings, ModuleSourceKind, ProjectItem};
use bmad_manager_lib::services::module_manifest::{self, RepoModule};
use bmad_manager_lib::services::{agents_file, project_service, project_updater};

use crate::support::TauriWorld;

// --- Version check ------------------------------------------------------

#[given(regex = r#"^a project "([^"]+)" with installed module version "([^"]+)"$"#)]
async fn project_with_installed_version(world: &mut TauriWorld, name: String, version: String) {
    let project = world.ensure_projects_root().join(&name);
    let config = project.join("_bmad/_config");
    std::fs::create_dir_all(&config).expect("create config dir");
    std::fs::write(
        config.join("manifest.yaml"),
        format!("modules:\n  - name: marketing-growth\n    version: {version}\n"),
    )
    .expect("write manifest");
    world.update_target = Some(project);
}

#[given(regex = r#"^a project "([^"]+)" with no marketing-growth module$"#)]
async fn project_with_no_module(world: &mut TauriWorld, name: String) {
    let project = world.ensure_projects_root().join(&name);
    let config = project.join("_bmad/_config");
    std::fs::create_dir_all(&config).expect("create config dir");
    std::fs::write(
        config.join("manifest.yaml"),
        "modules:\n  - name: core\n    version: 6.8.0\n",
    )
    .expect("write manifest");
    world.update_target = Some(project);
}

#[when(regex = r#"^I check it against repo module version "([^"]+)"$"#)]
async fn check_against_repo_version(world: &mut TauriWorld, version: String) {
    let project = world.update_target.clone().expect("project seeded");
    let repo = RepoModule {
        code: "marketing-growth".to_string(),
        version,
    };
    world.update_available = Some(module_manifest::is_project_stale(&project, &repo));
}

#[then("the project reports an update is available")]
async fn reports_update_available(world: &mut TauriWorld) {
    assert_eq!(world.update_available, Some(true));
}

#[then("the project reports no update available")]
async fn reports_no_update(world: &mut TauriWorld) {
    assert_eq!(world.update_available, Some(false));
}

// --- Version check end-to-end (latest read from the module source) ------
//
// Unlike the steps above, which call `is_project_stale` with a hand-built
// `RepoModule`, these drive the real `read_latest_repo_module` +
// stale-filter pipeline that `commands::check_for_updates` runs — the path a
// behind project actually travels before its Update button lights up.

#[given(regex = r#"^a marketing-growth module source at version "([^"]+)"$"#)]
async fn module_source_at_version(world: &mut TauriWorld, version: String) {
    let zip = world.build_marketing_growth_module_zip(&version);
    let root = world.ensure_projects_root();
    let mut settings = AppSettings::defaults();
    settings.projects_root = root.to_string_lossy().into_owned();
    settings.module_source_kind = ModuleSourceKind::LocalZip;
    settings.module_zip_path = zip.to_string_lossy().into_owned();
    world.settings = Some(settings);
}

#[given(regex = r#"^a marketing-growth git source at version "([^"]+)"$"#)]
async fn git_module_source_at_version(world: &mut TauriWorld, version: String) {
    let url = world.build_marketing_growth_git_repo(&version);
    let root = world.ensure_projects_root();
    let mut settings = AppSettings::defaults();
    settings.projects_root = root.to_string_lossy().into_owned();
    settings.module_source_kind = ModuleSourceKind::GitRepo;
    settings.module_repo_url = url;
    settings.module_repo_ref = String::new();
    world.settings = Some(settings);
}

#[when("I run the version check")]
async fn run_version_check(world: &mut TauriWorld) {
    let settings = world.settings.clone().expect("module source prepared");
    // Mirror `commands::check_for_updates`: read the latest version from the
    // configured source once, then flag every project under the root behind it.
    let stale = match project_updater::read_latest_repo_module(&settings) {
        Some(repo) => {
            let root = PathBuf::from(&settings.projects_root);
            project_service::list_projects(&root, settings.project_sort_order)
                .into_iter()
                .filter(|p| module_manifest::is_project_stale(&p.path, &repo))
                .map(|p| p.name)
                .collect()
        }
        None => Vec::new(),
    };
    world.stale_projects = Some(stale);
}

#[then(regex = r#"^the version check reports "([^"]+)" needs an update$"#)]
async fn version_check_flags(world: &mut TauriWorld, name: String) {
    let stale = world.stale_projects.as_ref().expect("version check ran");
    assert!(
        stale.contains(&name),
        "expected {name:?} to be flagged stale, got {stale:?}"
    );
}

#[then("the version check reports no projects need an update")]
async fn version_check_clears(world: &mut TauriWorld) {
    let stale = world.stale_projects.as_ref().expect("version check ran");
    assert!(
        stale.is_empty(),
        "expected no stale projects, got {stale:?}"
    );
}

// --- Per-project update -------------------------------------------------

#[given(regex = r#"^an existing project "([^"]+)" to update$"#)]
async fn existing_project_to_update(world: &mut TauriWorld, name: String) {
    let project = world.ensure_projects_root().join(&name);
    std::fs::create_dir_all(&project).expect("create project dir");
    world.update_target = Some(project);
}

#[given("update settings whose init command succeeds")]
async fn update_settings_succeeds(world: &mut TauriWorld) {
    let zip = world.build_module_zip();
    set_update_settings(world, zip, "exit 0");
}

#[given(regex = r#"^update settings whose init command succeeds, with okf template "([^"]+)"$"#)]
async fn update_settings_with_okf(world: &mut TauriWorld, okf: String) {
    let zip = world.build_module_zip_with_okf(&okf);
    set_update_settings(world, zip, "exit 0");
}

#[given("update settings whose init command fails")]
async fn update_settings_fails(world: &mut TauriWorld) {
    let zip = world.build_module_zip();
    set_update_settings(world, zip, "exit 1");
}

#[given(regex = r#"^git update settings with a module repo tagged "([^"]+)"$"#)]
async fn git_update_settings(world: &mut TauriWorld, tag: String) {
    let url = world.build_module_git_repo(&tag);
    let root = world.ensure_projects_root();
    let mut settings = AppSettings::defaults();
    settings.projects_root = root.to_string_lossy().into_owned();
    settings.module_source_kind = ModuleSourceKind::GitRepo;
    settings.module_repo_url = url;
    settings.module_repo_ref = String::new();
    // Echo the resolved {MODULE_SOURCE} so the test can assert what reaches
    // `--custom-source` (the repo URL + tag, not a temp clone path).
    settings.init_command = "echo '{MODULE_SOURCE}' > module-source.txt".to_string();
    world.settings = Some(settings);
}

fn set_update_settings(world: &mut TauriWorld, zip: PathBuf, init: &str) {
    let root = world.ensure_projects_root();
    let mut settings = AppSettings::defaults();
    settings.projects_root = root.to_string_lossy().into_owned();
    settings.module_source_kind = ModuleSourceKind::LocalZip;
    settings.module_zip_path = zip.to_string_lossy().into_owned();
    settings.init_command = init.to_string();
    world.settings = Some(settings);
}

#[given(regex = r#"^the project has a user file "([^"]+)" with content "([^"]+)"$"#)]
async fn project_has_user_file(world: &mut TauriWorld, rel: String, content: String) {
    let project = world.update_target.clone().expect("project seeded");
    let path = project.join(&rel);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("create user file dir");
    }
    std::fs::write(path, content).expect("write user file");
}

#[when("I update the project")]
async fn update_the_project(world: &mut TauriWorld) {
    let project = world.update_target.clone().expect("project seeded");
    let settings = world.settings.clone().expect("update settings prepared");
    let item = ProjectItem::new(project, None);
    let result = project_updater::update(&item, &settings, |_event| {}).await;
    world.last_string_error = result.err().map(|e| e.to_string());
}

#[then("the update succeeds")]
async fn update_succeeds(world: &mut TauriWorld) {
    assert_eq!(world.last_string_error, None);
}

#[then("the update fails")]
async fn update_fails(world: &mut TauriWorld) {
    assert!(
        world.last_string_error.is_some(),
        "expected an update error"
    );
}

#[then("the project AGENTS.md contains the bmad block")]
async fn agents_contains_bmad(world: &mut TauriWorld) {
    let text = read_agents(world);
    assert!(text.contains(agents_file::BMAD_SECTION_MARKER));
    assert!(text.contains(".agents/skills"));
}

#[then(regex = r#"^the project AGENTS.md contains the okf block "([^"]+)"$"#)]
async fn agents_contains_okf(world: &mut TauriWorld, body: String) {
    let text = read_agents(world);
    assert!(text.contains(&agents_file::start_marker("marketing-growth:okf")));
    assert!(text.contains(&body));
}

#[then("the project AGENTS.md has no okf block")]
async fn agents_no_okf(world: &mut TauriWorld) {
    let text = read_agents(world);
    assert!(!text.contains("marketing-growth:okf"));
}

#[then(regex = r#"^the project file "([^"]+)" still has content "([^"]+)"$"#)]
async fn project_file_still_has(world: &mut TauriWorld, rel: String, content: String) {
    let project = world.update_target.as_ref().expect("project seeded");
    let got = std::fs::read_to_string(project.join(&rel)).expect("user file present");
    assert_eq!(got, content);
}

#[then(regex = r#"^the project file "([^"]+)" contains "([^"]+)"$"#)]
async fn project_file_contains(world: &mut TauriWorld, rel: String, needle: String) {
    let project = world.update_target.as_ref().expect("project seeded");
    let got = std::fs::read_to_string(project.join(&rel)).expect("file present");
    assert!(
        got.contains(&needle),
        "expected {rel} to contain {needle:?}, got {got:?}"
    );
}

#[then("the project folder still exists")]
async fn project_folder_exists(world: &mut TauriWorld) {
    let project = world.update_target.as_ref().expect("project seeded");
    assert!(project.is_dir());
}

fn read_agents(world: &TauriWorld) -> String {
    let project = world.update_target.as_ref().expect("project seeded");
    std::fs::read_to_string(project.join("AGENTS.md")).expect("AGENTS.md written")
}
