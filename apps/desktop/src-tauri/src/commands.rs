use std::{
    fs::{self, File},
    io::Write,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use futures_util::future::{AbortHandle, Abortable};
use sha2::{Digest, Sha256};
use std::{collections::HashMap, sync::Mutex};
use tauri::{AppHandle, Manager, ipc::Channel};

use crate::{catalog, game, installer, inventory, packages, preferences};

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
    if let Ok(path) = packages::verified(config_dir, mod_entry) {
        let _ = progress.send(100);
        return Ok(path);
    }
    let cache_path = packages::destination(config_dir, mod_entry)?;
    let cache_dir = cache_path.parent().ok_or("fileWriteError")?;

    let url = catalog::download_url(mod_entry)?;
    let _ = rustls::crypto::ring::default_provider().install_default();
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(12))
        .read_timeout(Duration::from_secs(20))
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

    fs::create_dir_all(cache_dir).map_err(|_| "fileWriteError".to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(cache_dir).map_err(|_| "fileWriteError")?;
    let mut hasher = Sha256::new();
    let mut received = 0u64;
    let mut reported = None;

    while let Some(chunk) = response.chunk().await.map_err(|_| "downloadFailed")? {
        received = received.saturating_add(chunk.len() as u64);
        if received > pkg.size {
            return Err("packageCorrupt".into());
        }
        file.write_all(&chunk).map_err(|_| "fileWriteError")?;
        hasher.update(&chunk);
        let pct = received.saturating_mul(100) / pkg.size;
        if reported != Some(pct) {
            let _ = progress.send(pct);
            reported = Some(pct);
        }
    }
    if received != pkg.size || !hex::encode(hasher.finalize()).eq_ignore_ascii_case(&pkg.sha256) {
        return Err("packageCorrupt".into());
    }
    file.as_file().sync_all().map_err(|_| "fileWriteError")?;
    file.persist(&cache_path).map_err(|_| "fileWriteError")?;
    Ok(cache_path)
}

#[tauri::command]
pub fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
pub fn catalog(app: AppHandle) -> Result<serde_json::Value, String> {
    let mut snapshot = catalog::bundled();
    if cfg!(windows) {
        snapshot["previewMod"] = catalog::preview_entry(env!("CARGO_PKG_VERSION")).into();
        snapshot["previewMods"] = catalog::preview_entries(env!("CARGO_PKG_VERSION")).into();
    }
    let retained = catalog::receipts::load(&config_dir(&app)?, catalog_key()?)?;
    let entries = retained
        .iter()
        .map(|raw| serde_json::from_value(raw.clone()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| "catalogInvalid")?;
    *app.state::<UpdateCatalog>()
        .retained
        .lock()
        .map_err(|_| "catalogUnavailable")? = entries;
    snapshot["removalMods"] = retained.into();
    Ok(snapshot)
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

// Both inventory files contain all copies. Keep read/modify/write transactions serialized
// across app instances, including scans that publish a snapshot of the two files.
fn lock_file(dir: &Path, name: &str) -> Result<File, String> {
    let locks = dir.join("locks");
    fs::create_dir_all(&locks).map_err(|_| "fileWriteError")?;
    let file = File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(locks.join(name))
        .map_err(|_| "fileWriteError")?;
    fs2::FileExt::lock_exclusive(&file).map_err(|_| "fileWriteError")?;
    Ok(file)
}

fn trusted(id: &str, version: &str) -> Result<catalog::ModEntry, String> {
    catalog::entry(id)
        .filter(|m| m.version.as_deref() == Some(version))
        .ok_or_else(|| "unknownMod".into())
}

#[derive(Default)]
pub struct UpdateCatalog {
    active: Mutex<Vec<catalog::ModEntry>>,
    retained: Mutex<Vec<catalog::ModEntry>>,
}

fn catalog_key() -> Result<&'static str, String> {
    static CONFIG: std::sync::LazyLock<serde_json::Value> = std::sync::LazyLock::new(|| {
        serde_json::from_str(include_str!("../tauri.conf.json")).expect("valid app config")
    });
    CONFIG["plugins"]["updater"]["pubkey"]
        .as_str()
        .ok_or("catalogInvalid".into())
}

#[tauri::command]
pub fn authorize_mod_updates(
    app: AppHandle,
    document: String,
    signature: String,
) -> Result<Vec<catalog::ModEntry>, String> {
    let state = app.state::<UpdateCatalog>();
    let mut entries = state.active.lock().map_err(|_| "catalogUnavailable")?;
    if signature.is_empty() {
        entries.clear();
        return Ok(Vec::new());
    }
    let mut approved = catalog::signed_updates(
        &document,
        &signature,
        catalog_key()?,
        cfg!(windows) && env!("CARGO_PKG_VERSION").contains('-'),
    )?;
    approved.retain(|item| {
        item.adapter
            .as_ref()
            .is_some_and(|a| installer::check_platform_supported(a).is_ok())
    });
    let mut retained = state.retained.lock().map_err(|_| "catalogUnavailable")?;
    for item in &approved {
        if catalog::entry(&item.id).is_none() && !retained.iter().any(|old| old.id == item.id) {
            catalog::receipts::save(&config_dir(&app)?, &item.id, &document, &signature)?;
            retained.push(item.clone());
        }
    }
    *entries = approved;
    Ok(entries.clone())
}

fn active_entries(app: &AppHandle) -> Result<Vec<catalog::ModEntry>, String> {
    let mut list = catalog::all_entries();
    let state = app.state::<UpdateCatalog>();
    let active = state.active.lock().map_err(|_| "catalogUnavailable")?;
    let retained = state.retained.lock().map_err(|_| "catalogUnavailable")?;
    for item in retained.iter().chain(active.iter()) {
        if let Some(old) = list.iter_mut().find(|old| old.id == item.id) {
            *old = item.clone();
        } else {
            list.push(item.clone());
        }
    }
    Ok(list)
}

fn package_entry(
    app: &AppHandle,
    id: &str,
    version: &str,
    sha256: Option<&str>,
) -> Result<catalog::ModEntry, String> {
    let state = app.state::<UpdateCatalog>();
    let active = state.active.lock().map_err(|_| "catalogUnavailable")?;
    if let Some(item) = active.iter().find(|item| {
        item.id == id
            && item.version.as_deref() == Some(version)
            && item
                .package
                .as_ref()
                .is_some_and(|pkg| Some(pkg.sha256.as_str()) == sha256)
    }) {
        return Ok(item.clone());
    }
    let item = trusted(id, version).map_err(|_| "releaseChanged")?;
    if sha256.is_some_and(|hash| !item.package.as_ref().is_some_and(|pkg| pkg.sha256 == hash)) {
        return Err("releaseChanged".into());
    }
    Ok(item)
}

#[tauri::command]
pub async fn update_mod(
    app: AppHandle,
    path: PathBuf,
    id: String,
    version: String,
    sha256: String,
    from: String,
    expected_dir: PathBuf,
) -> Result<installer::CopyValidation, String> {
    let item = package_entry(&app, &id, &version, Some(&sha256))?;
    if !authorized_mod(&item)
        && !app
            .state::<UpdateCatalog>()
            .active
            .lock()
            .map_err(|_| "catalogUnavailable")?
            .contains(&item)
    {
        return Err("installPending".into());
    }
    installer::check_platform_supported(item.adapter.as_ref().ok_or("unsupportedAdapter")?)?;
    let dir = config_dir(&app)?;
    let list = active_entries(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, "inventory")?;
        let _pkg = lock_file(&dir, &format!("package-{}", item.id))?;
        let zip = packages::verified(&dir, &item)?;
        installer::update::apply(
            &dir,
            &path,
            &expected_dir,
            &zip,
            &item,
            &from,
            &list,
            &installer::SystemGameLockCheck,
        )?;
        installer::scan_copy(&dir, &path, &list, true)
            .map_err(|reason| format!("modUpdatedRescan: {reason}"))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn game_copies(path: PathBuf) -> Vec<PathBuf> {
    game::copy_directories(&path)
}

#[derive(Default)]
pub struct Downloads(Mutex<HashMap<u32, AbortHandle>>);

#[tauri::command]
pub fn cancel_download(downloads: tauri::State<'_, Downloads>, channel: u32) {
    if let Some(handle) = downloads.0.lock().unwrap().get(&channel) {
        handle.abort();
    }
}

#[tauri::command]
pub async fn download_mod(
    app: AppHandle,
    id: String,
    version: String,
    sha256: Option<String>,
    progress: Channel<u64>,
) -> Result<(), String> {
    let item = package_entry(&app, &id, &version, sha256.as_deref())?;
    let dir = config_dir(&app)?;
    let name = format!("package-{}", item.id);
    let downloads = app.state::<Downloads>();
    let channel = progress.id();
    let (handle, registration) = AbortHandle::new_pair();
    downloads.0.lock().unwrap().insert(channel, handle);
    // Acknowledge registration before waiting for a package lock or network response.
    let _ = progress.send(0);
    let result = Abortable::new(
        async {
            let lock_dir = dir.clone();
            let _guard = tauri::async_runtime::spawn_blocking(move || lock_file(&lock_dir, &name))
                .await
                .map_err(|e| e.to_string())??;
            download_package_zip(&dir, &item, &progress).await?;
            Ok(())
        },
        registration,
    )
    .await;
    downloads.0.lock().unwrap().remove(&channel);
    result.map_err(|_| "downloadCancelled".to_string())?
}

#[tauri::command]
pub async fn verify_package(
    app: AppHandle,
    id: String,
    version: String,
    sha256: Option<String>,
) -> Result<(), String> {
    let item = package_entry(&app, &id, &version, sha256.as_deref())?;
    let dir = config_dir(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, &format!("package-{}", item.id))?;
        packages::verified(&dir, &item).map(|_| ())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn cached_packages(
    app: AppHandle,
) -> Result<std::collections::BTreeMap<String, String>, String> {
    let dir = config_dir(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let mut found = std::collections::BTreeMap::new();
        for item in active_entries(&app)? {
            if let Some(pkg) = &item.package
                && packages::verified(&dir, &item).is_ok()
            {
                found.insert(item.id, pkg.sha256.clone());
            }
        }
        Ok(found)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn clear_package(
    app: AppHandle,
    id: String,
    version: String,
    sha256: Option<String>,
) -> Result<(), String> {
    let item = package_entry(&app, &id, &version, sha256.as_deref())?;
    let dir = config_dir(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, &format!("package-{}", item.id))?;
        packages::clear(&dir, &item)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn validate_game_mods(
    app: AppHandle,
    path: PathBuf,
    force: Option<bool>,
) -> Result<installer::CopyValidation, String> {
    let dir = config_dir(&app)?;
    let list = active_entries(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, "inventory")?;
        installer::update::recover(&dir, &path, &list, &installer::SystemGameLockCheck)?;
        installer::scan_copy(&dir, &path, &list, force.unwrap_or(false))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn authorized_mod(item: &catalog::ModEntry) -> bool {
    if cfg!(windows) && catalog::preview_entry(env!("CARGO_PKG_VERSION")).is_some() {
        return catalog::matches_preview(item, env!("CARGO_PKG_VERSION"));
    }
    item.verified
}

#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn install_mod(
    app: AppHandle,
    path: PathBuf,
    id: String,
    version: String,
    sha256: Option<String>,
    adopt: Option<bool>,
    removals: Option<Vec<String>>,
    expected_dir: PathBuf,
    progress: Channel<u64>,
) -> Result<installer::CopyValidation, String> {
    let mod_entry = package_entry(&app, &id, &version, sha256.as_deref())?;
    if !authorized_mod(&mod_entry)
        && !app
            .state::<UpdateCatalog>()
            .active
            .lock()
            .map_err(|_| "catalogUnavailable")?
            .contains(&mod_entry)
    {
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
    let list = active_entries(&app)?;

    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, "inventory")?;
        let _package = lock_file(&dir, &format!("package-{}", mod_entry.id))?;
        let zip_path = packages::verified(&dir, &mod_entry)?;
        use installer::GameLockCheck;
        let pck_dir = game::resolve_pck_dir(&path).ok_or("invalidGame")?;
        if pck_dir != expected_dir {
            return Err("statusUnavailable".into());
        }
        installer::SystemGameLockCheck
            .ensure_unlocked(&pck_dir, &pck_dir.join(&adapter.baseline.file))?;
        installer::update::recover(&dir, &path, &list, &installer::SystemGameLockCheck)?;
        let validation = installer::validate_game_mods(&dir, &path, &list)?;
        let is_manual = adopt.unwrap_or(false);
        let state = validation.mod_states.get(&id).map(String::as_str);
        let removals = removals.unwrap_or_default();
        if matches!(state, Some("modConflict" | "legacyInstalled")) == removals.is_empty() {
            return Err("statusUnavailable".into());
        }
        match (state, is_manual) {
            (Some("manualInstall"), true)
            | (Some("vanilla"), false)
            | (Some("modConflict" | "legacyInstalled"), false) => {}
            (Some("manualInstall"), false) => return Err("manualDetected".into()),
            (Some("vanilla"), true) | (Some("modConflict"), true) => {
                return Err("statusUnavailable".into());
            }
            (Some(reason), _) => return Err(reason.into()),
            _ => return Err("unsupportedAdapter".into()),
        }
        let staging_dir = dir.join("staging").join(&mod_entry.id);
        let pkg = mod_entry
            .package
            .as_ref()
            .ok_or_else(|| "missingPackage".to_string())?;
        if is_manual {
            installer::check_exclusive_conflicts(&dir, &path, &mod_entry, &adapter, &list)?;
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
        } else if matches!(state, Some("modConflict" | "legacyInstalled")) {
            installer::switch_from_zip(
                &removals,
                &dir,
                &path,
                &zip_path,
                &staging_dir,
                &mod_entry,
                &list,
                &installer::SystemRunner,
                &installer::SystemGameLockCheck,
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
        installer::scan_copy(&dir, &path, &list, true)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn uninstall_mod(
    app: AppHandle,
    path: PathBuf,
    id: String,
    version: String,
    sha256: Option<String>,
    expected_dir: PathBuf,
) -> Result<installer::CopyValidation, String> {
    let mod_entry = package_entry(&app, &id, &version, sha256.as_deref()).or_else(|error| {
        app.state::<UpdateCatalog>()
            .retained
            .lock()
            .map_err(|_| "catalogUnavailable")?
            .iter()
            .find(|item| item.id == id)
            .cloned()
            .ok_or(error)
    })?;
    let adapter = mod_entry
        .adapter
        .as_ref()
        .ok_or_else(|| "unsupportedAdapter".to_string())?;
    installer::check_platform_supported(adapter)?;
    let dir = config_dir(&app)?;
    let list = active_entries(&app)?;

    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock_file(&dir, "inventory")?;
        if game::resolve_pck_dir(&path).as_ref() != Some(&expected_dir) {
            return Err("statusUnavailable".into());
        }
        installer::update::recover(&dir, &path, &list, &installer::SystemGameLockCheck)?;
        // Offline loader removal is authorized by the installation transaction.
        if cfg!(windows)
            && catalog::preview_entry(env!("CARGO_PKG_VERSION")).is_some()
            && !authorized_mod(&mod_entry)
            && !installer::get_transaction(&dir, &path, &id)?
                .is_some_and(|tx| tx.exclusive == "loader")
        {
            return Err("installPending".into());
        }
        installer::uninstall_mod(
            &dir,
            &path,
            &mod_entry,
            &installer::SystemRunner,
            &installer::SystemGameLockCheck,
        )?;
        installer::scan_copy(&dir, &path, &list, true)
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
