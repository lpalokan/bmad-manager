pub mod commands;
pub mod models;
pub mod platform;
pub mod services;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(commands::AppState::new())
        .setup(|app| {
            platform::set_app_handle(app.handle().clone());
            // Surface what the bundled-resource resolver returned so a
            // misconfigured `bundle.resources` (path drift between the
            // glob target and the runtime resolver) shows up in stderr
            // without a debugger.
            services::bundled_tooling::log_resolved_paths();
            // Best-effort one-time copy of the bundled npm cache into the
            // user's writable %LOCALAPPDATA%. Failures are logged and
            // ignored — `npx bmad-method install` will still work, just
            // potentially with a network round-trip on the first run.
            services::bundled_tooling::seed_user_npm_cache_best_effort();
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_settings,
            commands::save_settings,
            commands::default_settings,
            commands::list_projects,
            commands::list_company_contexts,
            commands::create_project,
            commands::delete_project,
            commands::get_bundled_tooling,
            commands::open_in_claude,
            commands::open_in_opencode,
            commands::open_in_pi,
            commands::open_in_codex,
            commands::open_project_folder,
            commands::detect_command_in_path,
            commands::set_github_token,
            commands::has_github_token,
            commands::sync_skills_claude,
            commands::sync_skills_codex,
            commands::sync_skills_repo,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
