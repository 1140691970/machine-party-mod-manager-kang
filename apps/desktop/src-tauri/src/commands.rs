use std::{
    fs::{self, File},
    io::Write,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager, ipc::Channel};

use crate::{catalog, game, installer, inventory, preferences};

fn config_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().app_config_dir().map_err(|e| e.to_string())
}

fn is_safe_segment(s: &str) -> bool {
    !s.is_empty() && !s.contains("..") && !s.contains('/') && !s.contains('\\') && !s.contains('\0')
}

async fn download_package_zip(
    config_dir: &Path,
    mod_entry: &catalog::ModEntry,
    progress: &Channel<u64>,
) -> Result<PathBuf, String> {
    let pkg = mod_entry
        .package
        .as_ref()
        .ok_or_else(|| "missingPackage".to_string())?;
    if !is_safe_segment(&mod_entry.id) || !is_safe_segment(&pkg.filename) || pkg.size == 0 {
        return Err("packageCorrupt".into());
    }
    let cache_dir = config_dir.join("packages").join(&mod_entry.id);
    let cache_path = cache_dir.join(&pkg.filename);
    if cache_path.is_file()
        && installer::file_fingerprint(&cache_path)
            .is_ok_and(|fp| fp.size == pkg.size && fp.sha256.eq_ignore_ascii_case(&pkg.sha256))
    {
        let _ = progress.send(80);
        return Ok(cache_path);
    }

    let url = catalog::download_url(mod_entry)?;
    let _ = rustls::crypto::ring::default_provider().install_default();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(180))
        .build()
        .map_err(|_| "downloadFailed".to_string())?;
    let mut response = client
        .get(url)
        .send()
        .await
        .map_err(|_| "downloadFailed".to_string())?;
    if !response.status().is_success() {
        return Err("downloadFailed".into());
    }

    fs::create_dir_all(&cache_dir).map_err(|_| "fileWriteError".to_string())?;
    let temp_path = cache_dir.join(format!("{}.part-{}", pkg.filename, std::process::id()));
    let mut file = File::create(&temp_path).map_err(|_| "fileWriteError".to_string())?;
    let mut hasher = Sha256::new();
    let mut received = 0u64;
    let mut reported = None;

    while let Some(chunk) = response.chunk().await.map_err(|_| {
        let _ = fs::remove_file(&temp_path);
        "downloadFailed".to_string()
    })? {
        received = received.saturating_add(chunk.len() as u64);
        if received > pkg.size {
            let _ = fs::remove_file(&temp_path);
            return Err("packageCorrupt".into());
        }
        if file.write_all(&chunk).is_err() {
            let _ = fs::remove_file(&temp_path);
            return Err("fileWriteError".into());
        }
        hasher.update(&chunk);
        let pct = (received.saturating_mul(80) / pkg.size).min(80);
        if reported != Some(pct) {
            let _ = progress.send(pct);
            reported = Some(pct);
        }
    }

    if file.sync_all().is_err() {
        let _ = fs::remove_file(&temp_path);
        return Err("fileWriteError".into());
    }
    drop(file);

    let digest = hex::encode(hasher.finalize());
    if received != pkg.size || !digest.eq_ignore_ascii_case(&pkg.sha256) {
        let _ = fs::remove_file(&temp_path);
        return Err("packageCorrupt".into());
    }
    fs::rename(&temp_path, &cache_path).map_err(|_| {
        let _ = fs::remove_file(&temp_path);
        "fileWriteError".to_string()
    })?;
    Ok(cache_path)
}

#[tauri::command]
pub fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
pub fn catalog() -> serde_json::Value {
    let mut snapshot = catalog::bundled();
    if cfg!(windows) {
        snapshot["previewMod"] = catalog::preview_entry(env!("CARGO_PKG_VERSION")).into();
    }
    snapshot
}

#[tauri::command]
pub fn find_games(app: AppHandle, rescan: bool) -> Result<Vec<PathBuf>, String> {
    Ok(preferences::resolve_cached_or_detect(
        &config_dir(&app)?,
        rescan,
        game::steam_installations,
    ))
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
pub fn validate_game_mods(
    app: AppHandle,
    path: PathBuf,
    mods: Option<Vec<catalog::ModEntry>>,
) -> Result<installer::CopyValidation, String> {
    let list = mods.unwrap_or_else(catalog::all_entries);
    installer::validate_game_mods(&config_dir(&app)?, &path, &list)
}

fn authorized_mod(item: &catalog::ModEntry) -> bool {
    if cfg!(windows) && catalog::preview_entry(env!("CARGO_PKG_VERSION")).is_some() {
        return catalog::matches_preview(item, env!("CARGO_PKG_VERSION"));
    }
    item.verified
}

#[tauri::command]
pub async fn install_mod(
    app: AppHandle,
    path: PathBuf,
    mod_entry: catalog::ModEntry,
    mods: Option<Vec<catalog::ModEntry>>,
    progress: Channel<u64>,
) -> Result<installer::CopyValidation, String> {
    if !authorized_mod(&mod_entry) {
        return Err("installPending".into());
    }
    if catalog::project_url(&mod_entry.repo).is_none() {
        return Err("unknownMod".into());
    }
    let adapter = mod_entry
        .adapter
        .clone()
        .ok_or_else(|| "unsupportedAdapter".to_string())?;
    installer::check_platform_supported(&adapter)?;

    let dir = config_dir(&app)?;
    let zip_path = download_package_zip(&dir, &mod_entry, &progress).await?;
    let list = mods.unwrap_or_else(catalog::all_entries);

    tauri::async_runtime::spawn_blocking(move || {
        let validation = installer::validate_game_mods(&dir, &path, &list)?;
        let is_manual = validation
            .mod_states
            .get(&mod_entry.id)
            .is_some_and(|s| s == "manualInstall");
        let staging_dir = dir.join("staging").join(&mod_entry.id);
        let pkg = mod_entry
            .package
            .as_ref()
            .ok_or_else(|| "missingPackage".to_string())?;
        let pck_dir = game::resolve_pck_dir(&path).ok_or_else(|| "invalidGame".to_string())?;

        if is_manual {
            installer::stage_package(
                &zip_path,
                &staging_dir,
                pkg,
                &adapter,
                &pck_dir,
                &installer::SystemRunner,
            )?;
            installer::adopt_manual_install(
                &dir,
                &path,
                &staging_dir,
                &mod_entry,
                &installer::SystemRunner,
            )?;
        } else {
            installer::install_from_zip(
                &dir,
                &path,
                &zip_path,
                &staging_dir,
                &mod_entry,
                &list,
                &installer::SystemRunner,
                &installer::SystemGameLockCheck,
            )?;
        }
        let _ = fs::remove_dir_all(&staging_dir);
        let _ = progress.send(100);
        installer::validate_game_mods(&dir, &path, &list)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn uninstall_mod(
    app: AppHandle,
    path: PathBuf,
    mod_entry: catalog::ModEntry,
    mods: Option<Vec<catalog::ModEntry>>,
) -> Result<installer::CopyValidation, String> {
    if cfg!(windows)
        && catalog::preview_entry(env!("CARGO_PKG_VERSION")).is_some()
        && !authorized_mod(&mod_entry)
    {
        return Err("installPending".into());
    }
    let adapter = mod_entry
        .adapter
        .as_ref()
        .ok_or_else(|| "unsupportedAdapter".to_string())?;
    installer::check_platform_supported(adapter)?;
    let dir = config_dir(&app)?;
    let list = mods.unwrap_or_else(catalog::all_entries);

    tauri::async_runtime::spawn_blocking(move || {
        installer::uninstall_mod(
            &dir,
            &path,
            &mod_entry,
            &installer::SystemRunner,
            &installer::SystemGameLockCheck,
        )?;
        installer::validate_game_mods(&dir, &path, &list)
    })
    .await
    .map_err(|e| e.to_string())?
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
