use std::{
    collections::BTreeSet,
    fs, io,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use super::{
    runner::GameLockCheck,
    transaction::{is_safe_filename, write_atomic},
    update,
};
use crate::game;

pub const MOD_STATE_FILE: &str = ".mpm-state.json";

#[derive(Serialize, Deserialize, Default)]
struct ModStateFile {
    #[serde(default)]
    version: u32,
    #[serde(default)]
    disabled: BTreeSet<String>,
}

pub(super) fn mod_state_path(pck_dir: &Path) -> PathBuf {
    pck_dir.join("mods").join(MOD_STATE_FILE)
}

fn ensure_unredirected_file(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(meta) if update::redirected(&meta) || !meta.is_file() => {
            Err("gameUpdatedOrModified".into())
        }
        Ok(_) => Ok(true),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err("fileReadError".into()),
    }
}

pub(super) fn read_disabled_set(pck_dir: &Path) -> Result<BTreeSet<String>, String> {
    let path = mod_state_path(pck_dir);
    if !ensure_unredirected_file(&path)? {
        return Ok(BTreeSet::new());
    }
    let bytes = fs::read(&path).map_err(|_| "fileReadError".to_string())?;
    let Ok(parsed) = serde_json::from_slice::<ModStateFile>(&bytes) else {
        return Ok(BTreeSet::new());
    };
    Ok(parsed
        .disabled
        .into_iter()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect())
}

/// Returns the sorted list of disabled mod IDs recorded in `mods/.mpm-state.json`.
pub fn read_disabled_mods(pck_dir: &Path) -> Result<Vec<String>, String> {
    Ok(read_disabled_set(pck_dir)?.into_iter().collect())
}

pub(super) fn write_disabled_mods(
    pck_dir: &Path,
    disabled: &BTreeSet<String>,
) -> Result<(), String> {
    let path = mod_state_path(pck_dir);
    let existed = ensure_unredirected_file(&path)?;
    if disabled.is_empty() {
        if existed {
            fs::remove_file(&path).map_err(|_| "fileWriteError".to_string())?;
        }
        return Ok(());
    }
    let state = ModStateFile {
        version: 1,
        disabled: disabled.clone(),
    };
    let bytes = serde_json::to_vec_pretty(&state).map_err(|_| "fileWriteError".to_string())?;
    write_atomic(&path, &bytes)
}

/// Updates the enabled/disabled state for installed loader mods in `mods/.mpm-state.json`.
pub fn set_mods_enabled(
    game_root: &Path,
    mod_ids: &[String],
    enabled: bool,
    lock_check: &dyn GameLockCheck,
) -> Result<(), String> {
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join("Machine Party.pck");
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    let mods_root = pck_dir.join("mods");
    match fs::symlink_metadata(&mods_root) {
        Ok(meta) if meta.is_dir() && !update::redirected(&meta) => {}
        Ok(_) => return Err("gameUpdatedOrModified".into()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Err("statusUnavailable".into()),
        Err(_) => return Err("fileReadError".into()),
    }
    for id in mod_ids {
        if !is_safe_filename(id) || id.starts_with('.') {
            return Err("statusUnavailable".into());
        }
        let mod_dir = mods_root.join(id);
        match fs::symlink_metadata(&mod_dir) {
            Ok(meta) if meta.is_dir() && !update::redirected(&meta) => {}
            Ok(_) => return Err("gameUpdatedOrModified".into()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err("statusUnavailable".into());
            }
            Err(_) => return Err("fileReadError".into()),
        }
    }
    if mod_ids.is_empty() {
        return Ok(());
    }
    let mut disabled = read_disabled_set(&pck_dir)?;
    for id in mod_ids {
        if enabled {
            disabled.remove(id);
        } else {
            disabled.insert(id.clone());
        }
    }
    write_disabled_mods(&pck_dir, &disabled)
}
