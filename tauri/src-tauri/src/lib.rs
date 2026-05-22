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
            commands::list_projects,
            commands::create_project,
            commands::delete_project,
            commands::get_bundled_tooling,
            commands::open_in_claude,
            commands::open_in_opencode,
            commands::open_in_pi,
            commands::detect_command_in_path,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
