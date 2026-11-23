use std::{
    fs, io,
    path::{Path, PathBuf},
};

use super::transaction::{
    TransactionStatus, Transactions, collect_dir_fingerprints, read_transactions,
};
use crate::{
    catalog::{AdapterProfile, ModEntry},
    game, inventory, pck_loader,
};

pub(super) fn loader_mod_dir(pck_dir: &Path, mod_entry: &ModEntry) -> PathBuf {
    pck_dir.join("mods").join(&mod_entry.id)
}

pub(super) fn loader_marker_present(pck_dir: &Path) -> Result<bool, String> {
    Ok(pck_dir
        .join("MachinePartyModLoader.exe")
        .try_exists()
        .map_err(|_| "fileReadError")?
        || pck_dir
            .join("Machine Party.pck.modloader.json")
            .try_exists()
            .map_err(|_| "fileReadError")?)
}

pub(super) fn has_unmanaged_loader_dirs(
    pck_dir: &Path,
    mods: &[ModEntry],
    transactions: &Transactions,
    game_root: &Path,
) -> Result<bool, String> {
    let mods_root = pck_dir.join("mods");
    if !mods_root.is_dir() {
        return Ok(false);
    }
    let per_copy = transactions.get(game_root);
    let entries = fs::read_dir(&mods_root).map_err(|_| "fileReadError".to_string())?;
    for entry in entries {
        let entry = entry.map_err(|_| "fileReadError".to_string())?;
        let name = entry.file_name();
        let Some(name_str) = name.to_str() else {
            return Ok(true);
        };
        if name_str.starts_with('.') {
            continue;
        }
        let file_type = entry.file_type().map_err(|_| "fileReadError".to_string())?;
        if !file_type.is_dir() {
            return Ok(true);
        }
        let managed_ok = mods.iter().any(|item| {
            item.id == name_str
                && item
                    .adapter
                    .as_ref()
                    .is_some_and(|a| a.kind == "loader-files")
                && per_copy
                    .and_then(|map| map.get(&item.id))
                    .is_some_and(|record| {
                        record.status == TransactionStatus::Committed
                            && !record.owned_files.is_empty()
                            && collect_dir_fingerprints(&entry.path()).ok().as_ref()
                                == Some(&record.owned_files)
                    })
        });
        if !managed_ok {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(super) fn incompatible(target: &AdapterProfile, other: &AdapterProfile) -> bool {
    target.exclusive == "pck"
        || target.exclusive != other.exclusive
        || (target.conflict_group.is_some() && target.conflict_group == other.conflict_group)
}

pub(super) fn manual_eight_player_conflict(dir: &Path, adapter: &AdapterProfile) -> bool {
    adapter.source_rule.is_some() && dir.join("mods/broadcast-8p").exists()
}

pub fn check_exclusive_conflicts(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    adapter: &AdapterProfile,
    all_mods: &[ModEntry],
) -> Result<(), String> {
    let target = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    if adapter.kind == "loader-files" && target.join("Machine Party.pck.broadcast_backup").exists()
    {
        return Err("restoreResidue".into());
    }
    if manual_eight_player_conflict(&target, adapter) {
        return Err("manualBroadcastConflict".into());
    }
    if adapter.exclusive == "pck" && pck_loader::external_loader_present(&target)? {
        return Err("loaderConflict".into());
    }
    let installed = inventory::installed_versions(config_dir, game_root)?;
    for repo in installed.keys() {
        if repo == mod_entry.inventory_key() {
            continue;
        }
        if adapter.exclusive == "pck" {
            return Err("modConflict".into());
        }
        let Some(other) = all_mods.iter().find(|entry| entry.inventory_key() == repo) else {
            return Err("modConflict".into());
        };
        if other
            .adapter
            .as_ref()
            .is_none_or(|other_adapter| incompatible(adapter, other_adapter))
        {
            return Err("modConflict".into());
        }
    }
    if adapter.exclusive == "pck" && loader_marker_present(&target)? {
        return Err("loaderConflict".into());
    }
    Ok(())
}

// This adapter owns only the baseline and sidecars created during its transaction.
pub(super) fn sidecars_absent(adapter: &AdapterProfile, dir: &Path) -> Result<bool, String> {
    for name in adapter
        .touches
        .iter()
        .filter(|n| *n != &adapter.baseline.file)
    {
        if dir.join(name).try_exists().map_err(|_| "fileReadError")? {
            return Ok(false);
        }
    }
    Ok(true)
}

pub(super) fn has_remaining_mod_dirs(
    mods_dir: &Path,
    excluding: Option<&Path>,
) -> Result<bool, String> {
    let entries = match fs::read_dir(mods_dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(_) => return Err("fileReadError".into()),
    };
    for entry in entries {
        let entry = entry.map_err(|_| "fileReadError".to_string())?;
        let name = entry.file_name();
        if name.to_str().is_some_and(|s| s.starts_with('.')) {
            continue;
        }
        let kind = entry.file_type().map_err(|_| "fileReadError")?;
        if (kind.is_dir() || kind.is_symlink()) && excluding != Some(entry.path().as_path()) {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(super) fn has_other_loader_tx(
    config_dir: &Path,
    game_root: &Path,
    excluded_id: &str,
    exclusive: &str,
) -> Result<bool, String> {
    let txs = read_transactions(config_dir)?;
    let Some(per_copy) = txs.get(game_root) else {
        return Ok(false);
    };
    Ok(per_copy.iter().any(|(id, tx)| {
        id != excluded_id && tx.exclusive == exclusive && tx.status != TransactionStatus::RolledBack
    }))
}

/// Checks whether the current OS is supported by an adapter's `platforms` list.
pub fn check_platform_supported(adapter: &AdapterProfile) -> Result<(), String> {
    if adapter.platforms.iter().any(|p| p == std::env::consts::OS) {
        Ok(())
    } else {
        Err("windowsOnlyMod".into())
    }
}
