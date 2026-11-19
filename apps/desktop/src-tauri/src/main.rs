#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
mod app_updates;
mod catalog;
mod commands;
mod game;
mod installer;
mod inventory;
mod packages;
mod pck_loader;
mod preferences;

fn main() {
    let builder = tauri::Builder::default();
    #[cfg(any(windows, target_os = "macos"))]
    let builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    builder
        .manage(commands::Downloads::default())
        .manage(commands::UpdateCatalog::default())
        .invoke_handler(tauri::generate_handler![
            commands::app_version,
            commands::catalog,
            app_updates::check_app_update,
            app_updates::install_app_update,
            commands::installed_versions,
            commands::validate_game_mods,
            commands::game_copies,
            commands::download_mod,
            commands::cancel_download,
            commands::verify_package,
            commands::cached_packages,
            commands::clear_package,
            commands::install_mod,
            commands::authorize_mod_updates,
            commands::update_mod,
            commands::uninstall_mod,
            commands::set_app_title,
            commands::find_games,
            commands::choose_game,
            commands::save_game,
            commands::open_project
        ])
        .run(tauri::generate_context!())
        .expect("无法启动桌面客户端");
}
