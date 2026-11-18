use std::{path::PathBuf, process::Command};

use tauri::{AppHandle, Manager};

use crate::{catalog, game, inventory, preferences};

fn config_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().app_config_dir().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
pub fn catalog() -> serde_json::Value {
    catalog::bundled()
}

#[tauri::command]
pub fn find_games(app: AppHandle, rescan: bool) -> Result<Vec<PathBuf>, String> {
    if !rescan
        && let Some(path) = preferences::saved_game(&config_dir(&app)?)
        && game::is_game_root(&path)
    {
        return Ok(vec![path]);
    }
    Ok(game::steam_installations())
}

#[tauri::command]
pub async fn choose_game(title: String) -> Option<PathBuf> {
    rfd::AsyncFileDialog::new()
        .set_title(title)
        .pick_folder()
        .await
        .map(|file| file.path().to_owned())
}

#[tauri::command]
pub fn save_game(app: AppHandle, path: PathBuf) -> Result<(), String> {
    if !game::is_game_root(&path) {
        return Err("invalidGame".into());
    }
    preferences::save_game(&config_dir(&app)?, &path)
}

#[tauri::command]
pub fn installed_versions(app: AppHandle, path: PathBuf) -> Result<inventory::Installed, String> {
    let dir = app.path().app_config_dir().map_err(|_| "inventoryError")?;
    inventory::installed_versions(&dir, &path)
}

#[tauri::command]
pub fn open_project(repo: String) -> Result<(), String> {
    let url = catalog::project_url(&repo).ok_or("未知项目")?;
    #[cfg(target_os = "macos")]
    let mut cmd = Command::new("open");
    #[cfg(windows)]
    let mut cmd = Command::new("explorer.exe");
    #[cfg(all(unix, not(target_os = "macos")))]
    let mut cmd = Command::new("xdg-open");
    cmd.arg(url).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_app_title(window: tauri::Window, title: String) -> Result<(), String> {
    window.set_title(&title).map_err(|e| e.to_string())
}
