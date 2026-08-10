use std::path::Path;

use cucumber::{given, then, when};

use bmad_manager_lib::models::{
    AppSettings, CompanyContext, ContextSource, ModuleSourceKind, ProjectItem,
};
use bmad_manager_lib::services::company_context::{
    context_in_project, contexts_in, github_contexts_in, import_context, is_project_context_stale,
    refresh_context, source_context_for,
};
use bmad_manager_lib::services::project_creator;

use crate::support::TauriWorld;

/// Where the manager writes a seeded context — the canonical
/// marketing-growth layout (issue #96). Reading also accepts the legacy
/// `_bmad-output/company-context` and a bare top-level `company-context`.
const PREFERRED_CONTEXT_SUBPATH: &str = "output/company-context";

/// Every layout a context can be read from, canonical first.
const ALL_CONTEXT_SUBPATHS: [&str; 3] = [
    "output/company-context",
    "_bmad-output/company-context",
    "company-context",
];

fn split_list(list: &str) -> Vec<String> {
    if list.trim().is_empty() {
        return Vec::new();
    }
    list.split(',')
        .map(|s| s.trim().trim_matches('"').to_string())
        .collect()
}

// --- Givens -------------------------------------------------------------

#[given(regex = r#"^a project "([^"]+)" with context files "([^"]*)" under "([^"]+)"$"#)]
async fn project_with_context_files(
    world: &mut TauriWorld,
    project: String,
    files: String,
    subpath: String,
) {
    let files = split_list(&files);
    let refs: Vec<&str> = files.iter().map(String::as_str).collect();
    world.seed_context_files(&project, &subpath, &refs);
}

#[given(regex = r#"^the project "([^"]+)" also has context files "([^"]*)" under "([^"]+)"$"#)]
async fn project_also_has_context_files(
    world: &mut TauriWorld,
    project: String,
    files: String,
    subpath: String,
) {
    let files = split_list(&files);
    let refs: Vec<&str> = files.iter().map(String::as_str).collect();
    world.seed_context_files(&project, &subpath, &refs);
}

#[given(regex = r#"^a project "([^"]+)" with no context files$"#)]
async fn project_with_no_context(world: &mut TauriWorld, project: String) {
    let dir = world.ensure_projects_root().join(&project);
    std::fs::create_dir_all(&dir).expect("create project dir");
}

#[given(regex = r#"^an empty project "([^"]+)"$"#)]
async fn empty_project(world: &mut TauriWorld, project: String) {
    let dir = world.ensure_projects_root().join(&project);
    std::fs::create_dir_all(&dir).expect("create project dir");
}

#[given(
    regex = r#"^project "([^"]+)" already has a context file "([^"]+)" with content "([^"]+)"$"#
)]
async fn project_has_existing_context_file(
    world: &mut TauriWorld,
    project: String,
    file: String,
    content: String,
) {
    let dir = world
        .ensure_projects_root()
        .join(&project)
        .join(PREFERRED_CONTEXT_SUBPATH);
    std::fs::create_dir_all(&dir).expect("create context dir");
    std::fs::write(dir.join(&file), content).expect("write existing context file");
}

/// Resolves (and caches) the source context BEFORE deleting the file, so
/// the import step works from a stale snapshot — mirroring the Swift
/// "source file vanished between scan and import" test. The file is removed
/// from wherever the context actually resolved, so this works for a source
/// in any of the supported layouts.
#[given(regex = r#"^the context file "([^"]+)" of project "([^"]+)" has vanished$"#)]
async fn context_file_vanished(world: &mut TauriWorld, file: String, project: String) {
    let project_dir = world.ensure_projects_root().join(&project);
    if world.resolved_context.is_none() {
        world.resolved_context = Some(context_in_project(&project_dir));
    }
    let dir = world
        .resolved_context
        .clone()
        .flatten()
        .map(|c| c.directory)
        .expect("source context resolves before the file vanishes");
    std::fs::remove_file(dir.join(&file)).expect("remove source context file");
}

#[given(regex = r#"^a skills repo context "([^"]+)" with files "([^"]*)"$"#)]
async fn skills_repo_context(world: &mut TauriWorld, name: String, files: String) {
    let files = split_list(&files);
    let refs: Vec<&str> = files.iter().map(String::as_str).collect();
    world.seed_skills_repo_context(&name, &refs);
}

#[given(regex = r#"^creation settings whose init command (succeeds|fails)$"#)]
async fn creation_settings(world: &mut TauriWorld, outcome: String) {
    let root = world.ensure_projects_root();
    let zip_path = world.build_module_zip();
    let mut settings = AppSettings::defaults();
    settings.projects_root = root.to_string_lossy().into_owned();
    settings.module_source_kind = ModuleSourceKind::LocalZip;
    settings.module_zip_path = zip_path.to_string_lossy().into_owned();
    settings.init_command = if outcome == "succeeds" {
        "exit 0"
    } else {
        "exit 1"
    }
    .to_string();
    world.settings = Some(settings);
}

// --- Whens --------------------------------------------------------------

#[when(regex = r#"^I resolve the context of project "([^"]+)"$"#)]
async fn resolve_context(world: &mut TauriWorld, project: String) {
    let project_dir = world.ensure_projects_root().join(&project);
    world.resolved_context = Some(context_in_project(&project_dir));
}

#[when(regex = r#"^I resolve the contexts of projects "([^"]+)"$"#)]
async fn resolve_contexts(world: &mut TauriWorld, projects: String) {
    let root = world.ensure_projects_root();
    let items: Vec<ProjectItem> = split_list(&projects)
        .into_iter()
        .map(|name| ProjectItem::new(root.join(name), None))
        .collect();
    world.resolved_contexts = Some(contexts_in(&items));
}

#[when("I resolve the skills repo contexts")]
async fn resolve_skills_repo_contexts(world: &mut TauriWorld) {
    let repo = world.skills_repo_root();
    world.resolved_contexts = Some(github_contexts_in(&repo));
}

#[when(regex = r#"^I import the context of "([^"]+)" into project "([^"]+)"$"#)]
async fn import_context_step(world: &mut TauriWorld, source: String, dest: String) {
    let context = source_context(world, &source);
    let dest_dir = world.ensure_projects_root().join(&dest);
    match import_context(&context, &dest_dir) {
        Ok(()) => world.last_string_error = None,
        Err(err) => world.last_string_error = Some(err.to_string()),
    }
}

#[when(regex = r#"^I create a project "([^"]+)" importing the context of "([^"]+)"$"#)]
async fn create_importing_context(world: &mut TauriWorld, name: String, source: String) {
    let context = source_context(world, &source);
    run_create(world, &name, Some(context)).await;
}

#[when(regex = r#"^I create a project "([^"]+)" without importing a context$"#)]
async fn create_without_context(world: &mut TauriWorld, name: String) {
    run_create(world, &name, None).await;
}

/// Returns the cached pre-vanish snapshot when it matches the requested
/// source project, otherwise resolves fresh from disk.
fn source_context(world: &mut TauriWorld, source: &str) -> CompanyContext {
    let cached = world
        .resolved_context
        .clone()
        .flatten()
        .filter(|c| c.project_name == source);
    cached
        .or_else(|| {
            let dir = world.ensure_projects_root().join(source);
            context_in_project(&dir)
        })
        .expect("source context resolves")
}

async fn run_create(world: &mut TauriWorld, name: &str, context: Option<CompanyContext>) {
    let settings = world.settings.clone().expect("creation settings prepared");
    let result =
        project_creator::create_project(name, &settings, context.as_ref(), None, |_event| {}).await;
    world.last_string_error = result.err().map(|e| e.to_string());
}

// --- Thens --------------------------------------------------------------

#[then(regex = r#"^a context from project "([^"]+)" is found$"#)]
async fn context_found(world: &mut TauriWorld, project: String) {
    let context = expect_context(world);
    assert_eq!(context.project_name, project);
}

#[then("no context is found")]
async fn no_context_found(world: &mut TauriWorld) {
    let resolved = world.resolved_context.as_ref().expect("resolution ran");
    assert!(resolved.is_none(), "expected no context, got {resolved:?}");
}

#[then(regex = r#"^the context directory ends with "([^"]+)"$"#)]
async fn context_directory_ends_with(world: &mut TauriWorld, suffix: String) {
    let context = expect_context(world);
    assert!(
        context.directory.ends_with(Path::new(&suffix)),
        "expected {:?} to end with {suffix:?}",
        context.directory
    );
}

#[then(regex = r#"^the context files are exactly "([^"]*)"$"#)]
async fn context_files_exactly(world: &mut TauriWorld, list: String) {
    let context = expect_context(world);
    assert_eq!(context.files, split_list(&list));
}

#[then(regex = r#"^the resolved context project names are exactly "([^"]*)"$"#)]
async fn resolved_context_names(world: &mut TauriWorld, list: String) {
    let contexts = world.resolved_contexts.as_ref().expect("resolution ran");
    let names: Vec<&str> = contexts.iter().map(|c| c.project_name.as_str()).collect();
    assert_eq!(names, split_list(&list));
}

#[then("the resolved contexts all come from the skills repo")]
async fn resolved_contexts_all_github(world: &mut TauriWorld) {
    let contexts = world.resolved_contexts.as_ref().expect("resolution ran");
    assert!(
        contexts.iter().all(|c| c.source == ContextSource::Github),
        "expected every context tagged Github, got {contexts:?}"
    );
}

#[then(regex = r#"^the github context "([^"]+)" display name is "([^"]+)"$"#)]
async fn github_context_display_name(world: &mut TauriWorld, name: String, expected: String) {
    let contexts = world.resolved_contexts.as_ref().expect("resolution ran");
    let context = contexts
        .iter()
        .find(|c| c.project_name == name)
        .unwrap_or_else(|| panic!("no skills repo context named {name:?}"));
    assert_eq!(context.display_name(), expected);
}

#[then("no skills repo contexts are found")]
async fn no_skills_repo_contexts(world: &mut TauriWorld) {
    let contexts = world.resolved_contexts.as_ref().expect("resolution ran");
    assert!(contexts.is_empty(), "expected none, got {contexts:?}");
}

#[then(regex = r#"^the context display name is "([^"]+)"$"#)]
async fn context_display_name(world: &mut TauriWorld, expected: String) {
    let context = expect_context(world);
    assert_eq!(context.display_name(), expected);
}

#[then(regex = r#"^project "([^"]+)" contains context files "([^"]*)"$"#)]
async fn project_contains_context_files(world: &mut TauriWorld, project: String, list: String) {
    let dir = world
        .ensure_projects_root()
        .join(&project)
        .join(PREFERRED_CONTEXT_SUBPATH);
    for file in split_list(&list) {
        assert!(
            dir.join(&file).is_file(),
            "expected {file} to exist under {dir:?}"
        );
    }
}

/// Same assertion, but naming the layout explicitly — used where the point
/// of the scenario is *which* folder the files landed in (issue #96).
#[then(regex = r#"^project "([^"]+)" contains context files "([^"]*)" under "([^"]+)"$"#)]
async fn project_contains_context_files_under(
    world: &mut TauriWorld,
    project: String,
    list: String,
    subpath: String,
) {
    let dir = world.ensure_projects_root().join(&project).join(&subpath);
    for file in split_list(&list) {
        assert!(
            dir.join(&file).is_file(),
            "expected {file} to exist under {dir:?}"
        );
    }
}

#[then(regex = r#"^project "([^"]+)" has no "([^"]+)" folder$"#)]
async fn project_has_no_folder(world: &mut TauriWorld, project: String, folder: String) {
    let path = world.ensure_projects_root().join(&project).join(&folder);
    assert!(!path.exists(), "expected {path:?} not to exist");
}

#[then(regex = r#"^project "([^"]+)" does not contain context file "([^"]+)"$"#)]
async fn project_lacks_context_file(world: &mut TauriWorld, project: String, file: String) {
    let path = world
        .ensure_projects_root()
        .join(&project)
        .join(PREFERRED_CONTEXT_SUBPATH)
        .join(&file);
    assert!(!path.exists(), "expected {path:?} not to exist");
}

#[then(regex = r#"^the context file "([^"]+)" in project "([^"]+)" still has content "([^"]+)"$"#)]
async fn context_file_still_has_content(
    world: &mut TauriWorld,
    file: String,
    project: String,
    expected: String,
) {
    let path = world
        .ensure_projects_root()
        .join(&project)
        .join(PREFERRED_CONTEXT_SUBPATH)
        .join(&file);
    let content = std::fs::read_to_string(&path).expect("read context file");
    assert_eq!(content, expected);
}

#[then(regex = r#"^the import fails mentioning "([^"]+)"$"#)]
async fn import_fails_mentioning(world: &mut TauriWorld, fragment: String) {
    let error = world.last_string_error.as_deref().expect("an import error");
    assert!(
        error.contains(&fragment),
        "expected error {error:?} to mention {fragment:?}"
    );
}

#[then("the creation succeeds")]
async fn creation_succeeds(world: &mut TauriWorld) {
    assert_eq!(world.last_string_error, None);
}

#[then(regex = r#"^the creation fails mentioning "([^"]+)"$"#)]
async fn creation_fails_mentioning(world: &mut TauriWorld, fragment: String) {
    let error = world
        .last_string_error
        .as_deref()
        .expect("a creation error");
    assert!(
        error.contains(&fragment),
        "expected error {error:?} to mention {fragment:?}"
    );
}

#[then(regex = r#"^project "([^"]+)" has no context folder$"#)]
async fn project_has_no_context_folder(world: &mut TauriWorld, project: String) {
    let project_dir = world.ensure_projects_root().join(&project);
    for subpath in ALL_CONTEXT_SUBPATHS {
        let dir = project_dir.join(subpath);
        assert!(!dir.exists(), "expected {dir:?} not to exist");
    }
}

fn expect_context(world: &TauriWorld) -> &CompanyContext {
    world
        .resolved_context
        .as_ref()
        .expect("resolution ran")
        .as_ref()
        .expect("a context was found")
}

// --- Context drift vs the skills repo (issue #92) -----------------------

#[given(regex = r#"^a skills repo context "([^"]+)" with OKF file "([^"]+)" dated "([^"]+)"$"#)]
async fn skills_okf_dated(world: &mut TauriWorld, name: String, file: String, date: String) {
    world.put_skills_okf(&name, &file, Some(&date), "v1");
}

#[given(
    regex = r#"^the skills repo context "([^"]+)" also has dateless OKF file "([^"]+)" containing "([^"]+)"$"#
)]
async fn skills_okf_dateless(world: &mut TauriWorld, name: String, file: String, body: String) {
    world.put_skills_okf(&name, &file, None, &body);
}

#[given(regex = r#"^(?:a )?project "([^"]+)" seeded from the "([^"]+)" skills repo context$"#)]
async fn project_seeded_from_context(world: &mut TauriWorld, project: String, name: String) {
    world.seed_project_from_skills_context(&name, &project);
}

/// Seeds a project whose bundle sits in a named layout — models a project
/// created before the manager defaulted to `output/` (issue #96).
#[given(
    regex = r#"^(?:a )?project "([^"]+)" seeded from the "([^"]+)" skills repo context under "([^"]+)"$"#
)]
async fn project_seeded_from_context_under(
    world: &mut TauriWorld,
    project: String,
    name: String,
    subpath: String,
) {
    world.seed_project_from_skills_context_at(&name, &project, &subpath);
}

#[given(
    regex = r#"^the skills repo context "([^"]+)" file "([^"]+)" is edited and dated "([^"]+)"$"#
)]
async fn skills_okf_edited_dated(world: &mut TauriWorld, name: String, file: String, date: String) {
    world.put_skills_okf(&name, &file, Some(&date), "v2 edited");
}

#[given(
    regex = r#"^the skills repo context "([^"]+)" dateless file "([^"]+)" is edited to contain "([^"]+)"$"#
)]
async fn skills_okf_dateless_edited(
    world: &mut TauriWorld,
    name: String,
    file: String,
    body: String,
) {
    world.put_skills_okf(&name, &file, None, &body);
}

#[given(regex = r#"^the skills repo context "([^"]+)" gains OKF file "([^"]+)" dated "([^"]+)"$"#)]
async fn skills_okf_gains(world: &mut TauriWorld, name: String, file: String, date: String) {
    world.put_skills_okf(&name, &file, Some(&date), "added file");
}

#[given(regex = r#"^the skills repo context "([^"]+)" is removed$"#)]
async fn skills_context_removed(world: &mut TauriWorld, name: String) {
    world.remove_skills_context(&name);
}

#[given(regex = r#"^project "([^"]+)" has a local context file "([^"]+)"$"#)]
async fn project_local_context_file(world: &mut TauriWorld, project: String, file: String) {
    world.add_local_context_file(&project, &file);
}

#[when(regex = r#"^I check whether project "([^"]+)" has a context update$"#)]
async fn check_context_update(world: &mut TauriWorld, project: String) {
    let dir = world.ensure_projects_root().join(&project);
    let sources = world.skills_repo_sources();
    world.context_update_available = Some(is_project_context_stale(&dir, &sources));
}

#[when(regex = r#"^I refresh project "([^"]+)" from the skills repo$"#)]
async fn refresh_project_from_skills(world: &mut TauriWorld, project: String) {
    let dir = world.ensure_projects_root().join(&project);
    let sources = world.skills_repo_sources();
    let project_ctx = context_in_project(&dir).expect("project has a context to refresh");
    let source =
        source_context_for(&project_ctx, &sources).expect("project resolves to a source context");
    match refresh_context(source, &project_ctx.directory) {
        Ok(()) => world.last_string_error = None,
        Err(err) => world.last_string_error = Some(err.to_string()),
    }
}

#[then(regex = r#"^project "([^"]+)" reports a context update is available$"#)]
async fn reports_context_update(world: &mut TauriWorld, _project: String) {
    assert_eq!(world.context_update_available, Some(true));
}

#[then(regex = r#"^project "([^"]+)" reports no context update$"#)]
async fn reports_no_context_update(world: &mut TauriWorld, _project: String) {
    assert_eq!(world.context_update_available, Some(false));
}

#[then(regex = r#"^project "([^"]+)" context file "([^"]+)" is dated "([^"]+)"$"#)]
async fn context_file_dated(world: &mut TauriWorld, project: String, file: String, date: String) {
    let path = world
        .ensure_projects_root()
        .join(&project)
        .join(PREFERRED_CONTEXT_SUBPATH)
        .join(&file);
    let text = std::fs::read_to_string(&path).expect("read refreshed context file");
    let found = text.lines().find_map(|l| {
        l.trim()
            .strip_prefix("last_updated:")
            .map(|v| v.trim().to_string())
    });
    assert_eq!(
        found.as_deref(),
        Some(date.as_str()),
        "expected {path:?} to carry last_updated {date:?}"
    );
}
