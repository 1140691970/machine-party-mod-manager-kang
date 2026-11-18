use serde::Serialize;
use tauri::{AppHandle, ipc::Channel};
#[cfg(windows)]
use tauri_plugin_updater::UpdaterExt;

#[derive(Serialize)]
pub struct AppRelease {
    version: String,
    notes: Option<String>,
}

#[cfg(windows)]
async fn latest(app: &AppHandle) -> Result<Option<tauri_plugin_updater::Update>, String> {
    let updater = app
        .updater_builder()
        .timeout(std::time::Duration::from_secs(180))
        .build()
        .map_err(|e| e.to_string())?;
    updater.check().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn check_app_update(app: AppHandle) -> Result<Option<AppRelease>, String> {
    #[cfg(windows)]
    return Ok(latest(&app).await?.map(|update| AppRelease {
        version: update.version,
        notes: update.body,
    }));
    #[cfg(not(windows))]
    {
        let _ = app;
        Err("windowsOnly".into())
    }
}

#[tauri::command]
pub async fn install_app_update(
    app: AppHandle,
    version: String,
    progress: Channel<u64>,
) -> Result<(), String> {
    #[cfg(windows)]
    {
        let update = latest(&app)
            .await?
            .filter(|update| update.version == version)
            .ok_or("releaseChanged")?;
        let mut received = 0u64;
        let mut reported = None;
        update
            .download_and_install(
                move |size, total| {
                    received += size as u64;
                    if let Some(total) = total.filter(|total| *total > 0) {
                        let percent = (received.saturating_mul(100) / total).min(100);
                        if reported != Some(percent) {
                            let _ = progress.send(percent);
                            reported = Some(percent);
                        }
                    }
                },
                || {},
            )
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(not(windows))]
    {
        let _ = (app, version, progress);
        Err("windowsOnly".into())
    }
}
