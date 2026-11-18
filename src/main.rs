#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
mod app_updates;
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};
use tauri::Manager;

fn game_files(dir: &Path) -> bool {
    ["Machine Party.exe", "Machine Party.pck"]
        .iter()
        .all(|name| dir.join(name).is_file())
}

fn game_root(dir: &Path) -> bool {
    game_files(dir)
        || fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .any(|entry| {
                entry.file_type().is_ok_and(|kind| kind.is_dir()) && game_files(&entry.path())
            })
}

fn preference(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_config_dir()
        .map_err(|e| e.to_string())?
        .join("game-path.json"))
}

#[tauri::command]
fn find_games(app: tauri::AppHandle, rescan: bool) -> Result<Vec<PathBuf>, String> {
    if !rescan
        && let Ok(contents) = fs::read(preference(&app)?)
        && let Ok(path) = serde_json::from_slice::<PathBuf>(&contents)
        && game_root(&path)
    {
        return Ok(vec![path]);
    }
    let mut games = vec![];
    for steam in steamlocate::locate_all().unwrap_or_default() {
        for library in steam.libraries().into_iter().flatten().flatten() {
            if let Some(Ok(info)) = library.app(4108000) {
                let path = library.resolve_app_dir(&info);
                if game_root(&path) && !games.contains(&path) {
                    games.push(path);
                }
            }
        }
    }
    Ok(games)
}

#[tauri::command]
async fn choose_game(title: String) -> Option<PathBuf> {
    rfd::AsyncFileDialog::new()
        .set_title(title)
        .pick_folder()
        .await
        .map(|file| file.path().to_owned())
}

#[tauri::command]
fn save_game(app: tauri::AppHandle, path: PathBuf) -> Result<(), String> {
    if !game_root(&path) {
        return Err("invalidGame".into());
    }
    let pref = preference(&app)?;
    fs::create_dir_all(pref.parent().ok_or("配置目录无效")?).map_err(|e| e.to_string())?;
    fs::write(pref, serde_json::to_vec(&path).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn open_project(repo: String) -> Result<(), String> {
    let allowed = [
        "DarkJadeStone/MachineParty-Overtime",
        "Ghostx10742/MachineParty-Plus",
        "Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher",
        "Binary1936/machine-party-8p",
    ];
    if !allowed.contains(&repo.as_str()) {
        return Err("未知项目".into());
    }
    let url = format!("https://github.com/{repo}");
    #[cfg(target_os = "macos")]
    let mut cmd = Command::new("open");
    #[cfg(windows)]
    let mut cmd = Command::new("explorer.exe");
    #[cfg(all(unix, not(target_os = "macos")))]
    let mut cmd = Command::new("xdg-open");
    cmd.arg(url).spawn().map(|_| ()).map_err(|e| e.to_string())
}

// The installer records completed transactions per game copy. Missing records
// mean that this manager has not installed any mods for the selected copy.
type Inventory = std::collections::BTreeMap<PathBuf, std::collections::BTreeMap<String, String>>;

#[tauri::command]
fn installed_versions(
    app: tauri::AppHandle,
    path: PathBuf,
) -> Result<std::collections::BTreeMap<String, String>, String> {
    let file = app
        .path()
        .app_config_dir()
        .map_err(|_| "inventoryError")?
        .join("installations.json");
    let bytes = match fs::read(file) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Default::default()),
        Err(_) => return Err("inventoryError".into()),
    };
    let mut inventory: Inventory = serde_json::from_slice(&bytes).map_err(|_| "inventoryError")?;
    Ok(inventory.remove(&path).unwrap_or_default())
}

#[tauri::command]
fn set_app_title(window: tauri::Window, title: String) -> Result<(), String> {
    window.set_title(&title).map_err(|e| e.to_string())
}

#[tauri::command]
fn app_version(app: tauri::AppHandle) -> String {
    app.package_info().version.to_string()
}

fn main() {
    let builder = tauri::Builder::default();
    #[cfg(any(windows, target_os = "macos"))]
    let builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    builder
        .invoke_handler(tauri::generate_handler![
            app_version,
            app_updates::check_app_update,
            app_updates::install_app_update,
            installed_versions,
            set_app_title,
            find_games,
            choose_game,
            save_game,
            open_project
        ])
        .run(tauri::generate_context!())
        .expect("无法启动桌面客户端");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recognizes_complete_copy_in_root_or_version_folder() {
        let root = std::env::temp_dir().join(format!("mpm-test-{}", std::process::id()));
        let child = root.join("v2.1.2");
        fs::create_dir_all(&child).unwrap();
        fs::write(child.join("Machine Party.exe"), []).unwrap();
        assert!(!game_root(&root));
        fs::write(child.join("Machine Party.pck"), []).unwrap();
        assert!(game_root(&root) && game_root(&child));
        fs::remove_dir_all(root).unwrap();
    }
}
