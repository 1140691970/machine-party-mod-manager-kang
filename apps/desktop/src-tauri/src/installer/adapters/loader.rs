use std::{fs, io, path::Path};

use super::super::{
    conflicts::{
        check_exclusive_conflicts, has_other_loader_tx, has_remaining_mod_dirs,
        loader_marker_present, loader_mod_dir, sidecars_absent,
    },
    runner::GameLockCheck,
    transaction::{
        FileFingerprint, TransactionRecord, TransactionStatus, backup_dir_for, check_space,
        collect_dir_fingerprints, copy_atomic, file_fingerprint, save_transaction, unique_suffix,
    },
};
use crate::{
    catalog::{BaselineSpec, ModEntry},
    game, inventory, pck_loader,
};

pub fn normalize_loader_staging(staging_dir: &Path) -> Result<(), String> {
    if staging_dir.join("mod.json").is_file() {
        return Ok(());
    }
    let mut dirs = Vec::new();
    let mut has_files = false;
    let entries = fs::read_dir(staging_dir).map_err(|_| "fileReadError".to_string())?;
    for item in entries {
        let item = item.map_err(|_| "fileReadError".to_string())?;
        let file_type = item.file_type().map_err(|_| "fileReadError".to_string())?;
        if file_type.is_symlink() {
            return Err("packageCorrupt".into());
        }
        if file_type.is_dir() {
            dirs.push(item.path());
        } else if file_type.is_file() {
            has_files = true;
        }
    }
    if !has_files && dirs.len() == 1 && dirs[0].join("mod.json").is_file() {
        let tmp_dir = staging_dir.join(format!(".hoist-{}", unique_suffix()));
        fs::rename(&dirs[0], &tmp_dir).map_err(|_| "fileWriteError".to_string())?;
        for item in fs::read_dir(&tmp_dir).map_err(|_| "fileReadError".to_string())? {
            let item = item.map_err(|_| "fileReadError".to_string())?;
            let dst = staging_dir.join(item.file_name());
            fs::rename(item.path(), dst).map_err(|_| "fileWriteError".to_string())?;
        }
        fs::remove_dir(&tmp_dir).map_err(|_| "fileWriteError".to_string())?;
    }
    Ok(())
}

pub fn install_loader_files(
    config_dir: &Path,
    game_root: &Path,
    staging_dir: &Path,
    mod_entry: &ModEntry,
    all_mods: &[ModEntry],
    lock_check: &dyn GameLockCheck,
) -> Result<TransactionRecord, String> {
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    check_exclusive_conflicts(config_dir, game_root, mod_entry, adapter, all_mods)?;
    for other in all_mods {
        if let Some(other_adapter) = &other.adapter
            && other_adapter.exclusive == "pck"
            && !sidecars_absent(other_adapter, &pck_dir)?
        {
            return Err("modConflict".into());
        }
    }

    let pre_pck = file_fingerprint(&pck_path)?;
    let is_vanilla = pre_pck.size == adapter.baseline.size
        && pre_pck
            .sha256
            .eq_ignore_ascii_case(&adapter.baseline.sha256);
    let had_managed_loader = pck_loader::read_managed_marker(&pck_dir)?.is_some();
    let has_loader = loader_marker_present(&pck_dir)?;
    if !is_vanilla && !has_loader {
        return Err("gameUpdatedOrModified".into());
    }

    let pkg = mod_entry.package.as_ref().ok_or("missingPackage")?;

    let mod_dir = loader_mod_dir(&pck_dir, mod_entry);
    if mod_dir.exists() {
        return Err("restoreResidue".into());
    }
    let owned_files = collect_dir_fingerprints(staging_dir)?;
    if owned_files.is_empty() {
        return Err("packageCorrupt".into());
    }
    let total_bytes: u64 = owned_files.values().map(|fp| fp.size).sum();
    fs::create_dir_all(config_dir).map_err(|_| "fileWriteError")?;
    check_space(&pck_dir, total_bytes.max(1))?;

    let loader_backup_dir = backup_dir_for(config_dir, game_root, "_mpm_loader");
    let loader_backup_pck = loader_backup_dir.join(&adapter.baseline.file);
    if adapter.auto_loader {
        check_space(config_dir, pre_pck.size)?;
    }
    let backup_dir = backup_dir_for(config_dir, game_root, &mod_entry.id);
    let version = mod_entry.version.clone().unwrap_or_default();
    let mut record = TransactionRecord {
        mod_id: mod_entry.id.clone(),
        repo: mod_entry.repo.clone(),
        version: version.clone(),
        exclusive: adapter.exclusive.clone(),
        pck_dir: pck_dir.clone(),
        status: TransactionStatus::Pending,
        pre_pck,
        post_pck: None,
        upstream_uninstall: false,
        backup_dir,
        touched_files: adapter.touches.clone(),
        owned_files: owned_files.clone(),
        failure: None,
        source_sha256: Some(pkg.sha256.clone()),
        restoring_pck: None,
        preparation_rule: Some(
            adapter
                .source_rule
                .clone()
                .unwrap_or_else(|| "native-v1".into()),
        ),
        auto_installed: false,
    };
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    if file_fingerprint(&pck_path)? != record.pre_pck {
        return Err("gameUpdatedOrModified".into());
    }
    let mods_root = pck_dir.join("mods");
    if mods_root.is_symlink() {
        return Err("restoreResidue".into());
    }
    save_transaction(config_dir, game_root, record.clone())?;
    let mut created_mod_dir = false;
    let mut created_mods_root = false;
    let outcome = (|| -> Result<(), String> {
        if adapter.auto_loader {
            pck_loader::ensure_loader_installed(
                &pck_dir,
                &loader_backup_pck,
                &adapter.baseline,
                || lock_check.ensure_unlocked(&pck_dir, &pck_path),
            )?;
        }
        record.post_pck = Some(file_fingerprint(&pck_path)?);

        lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
        match fs::create_dir(&mods_root) {
            Ok(()) => created_mods_root = true,
            Err(e)
                if e.kind() == io::ErrorKind::AlreadyExists
                    && mods_root.is_dir()
                    && !mods_root.is_symlink() => {}
            Err(_) => return Err("fileWriteError".into()),
        }
        fs::create_dir(&mod_dir).map_err(|_| "restoreResidue")?;
        created_mod_dir = true;
        for rel in owned_files.keys() {
            copy_atomic(&staging_dir.join(rel), &mod_dir.join(rel))?;
        }
        if collect_dir_fingerprints(&mod_dir)? != owned_files {
            return Err("installFailed".into());
        }
        Ok(())
    })();

    match outcome {
        Ok(()) => {
            record.status = TransactionStatus::Committed;
            save_transaction(config_dir, game_root, record.clone())?;
            inventory::record_installed(
                config_dir,
                game_root,
                mod_entry.inventory_key(),
                &version,
            )?;
            Ok(record)
        }
        Err(err) => {
            let mut cleaned = !created_mod_dir
                || (!mod_dir.is_symlink()
                    && collect_dir_fingerprints(&mod_dir).is_ok_and(|files| {
                        files
                            .iter()
                            .all(|(name, fp)| owned_files.get(name) == Some(fp))
                    })
                    && fs::remove_dir_all(&mod_dir).is_ok());
            if created_mods_root {
                let _ = fs::remove_dir(&mods_root);
            }
            if !had_managed_loader
                && pck_loader::read_managed_marker(&pck_dir)?.is_some()
                && !has_other_loader_tx(config_dir, game_root, &mod_entry.id, &adapter.exclusive)
                    .unwrap_or(true)
                && !has_remaining_mod_dirs(&pck_dir.join("mods"), None).unwrap_or(true)
            {
                if pck_loader::restore_managed_loader(&pck_dir, &loader_backup_pck, || {
                    lock_check.ensure_unlocked(&pck_dir, &pck_path)
                })
                .is_ok()
                {
                    let _ = fs::remove_dir_all(&loader_backup_dir);
                } else {
                    cleaned = false;
                }
            }
            record.failure = Some(err.clone());
            record.status = if cleaned {
                TransactionStatus::RolledBack
            } else {
                TransactionStatus::NeedsRepair
            };
            let _ = save_transaction(config_dir, game_root, record);
            if cleaned {
                Err(err)
            } else {
                Err("restoreVerifyFailed".into())
            }
        }
    }
}

pub fn resumable_loader_cleanup(
    tx: &TransactionRecord,
    marker: &pck_loader::ManagedLoaderState,
    current: &FileFingerprint,
    baseline: &BaselineSpec,
) -> bool {
    tx.exclusive == "loader"
        && matches!(
            tx.status,
            TransactionStatus::Pending | TransactionStatus::NeedsRepair
        )
        && ((current.size == baseline.size && current.sha256 == baseline.sha256)
            || tx.restoring_pck.as_ref() == Some(current))
        && current.size == marker.vanilla_size
        && current.sha256 == marker.vanilla_sha256
}
