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
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_settings,
            commands::save_settings,
            commands::list_projects,
            commands::create_project,
            commands::delete_project,
            commands::open_in_claude,
            commands::open_in_opencode,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
