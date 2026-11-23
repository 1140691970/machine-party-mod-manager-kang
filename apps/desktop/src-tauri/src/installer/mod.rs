pub mod deps;
pub mod steam_restore;
pub mod update;

mod adapters;
mod conflicts;
mod inspect;
mod prepare;
mod runner;
mod state;
#[cfg(test)]
mod tests;
mod transaction;
mod zip;

use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

#[allow(unused_imports)] // Re-exported via `super::*` for `steam_restore` and `update`.
use std::path::Component;

#[allow(unused_imports)] // Re-exported via `super::*` for `steam_restore` and `update`.
use serde::{Deserialize, Serialize};
#[allow(unused_imports)] // Re-exported via `super::*` for `steam_restore`.
use sha2::{Digest, Sha256};

use crate::{catalog::ModEntry, game, inventory, pck_loader};

use adapters::{
    RESTORE_DAT, install_loader_files, mirror_delta_backup, resumable_loader_cleanup,
    run_status_cmd, uses_delta_restore,
};
#[allow(unused_imports)] // Public adapter helpers exercised by unit tests and future stages.
pub use adapters::{RestoreHeader, parse_status};
pub use adapters::{build_command, parse_mp8r_restore, validate_adapter};
pub use conflicts::{check_exclusive_conflicts, check_platform_supported};
use conflicts::{
    has_other_loader_tx, has_remaining_mod_dirs, incompatible, loader_marker_present,
    loader_mod_dir, manual_eight_player_conflict, sidecars_absent,
};
#[allow(unused_imports)]
// `ModInspection` and `ReconcileState` remain part of the installer API.
pub use inspect::{
    CopyValidation, ModInspection, ReconcileState, adopt_manual_install, inspect_mod,
    reconcile_copy, scan_copy, validate_game_mods,
};
#[allow(unused_imports)] // Public runner types exercised by unit tests.
pub use runner::{CommandOutput, CommandRequest};
pub use runner::{GameLockCheck, ProcessRunner, SystemGameLockCheck, SystemRunner};
#[allow(unused_imports)]
pub use state::{MOD_STATE_FILE, read_disabled_mods, set_mods_enabled};
use state::{mod_state_path, read_disabled_set, write_disabled_mods};
#[cfg(test)]
use transaction::PCK_READS;
pub use transaction::{
    DiskModState, FileFingerprint, TransactionRecord, TransactionStatus, file_fingerprint,
};
use transaction::{
    TRANSACTIONS_FILE, backup_dir_for, clear_mod_records, collect_dir_fingerprints,
    read_transactions, remove_transaction, save_transaction, snapshot_dir, verify_only_touches,
};
pub(crate) use transaction::{
    check_space, copy_atomic, get_transaction, is_hex_sha256, is_safe_filename, write_atomic,
};
pub use zip::{extract_zip, stage_package};
use zip::{validate_rel_components, verify_checksum_manifest};

/// Runs the full verified installation transaction from a downloaded package ZIP.
#[allow(clippy::too_many_arguments)]
pub fn install_from_zip(
    config_dir: &Path,
    game_root: &Path,
    zip_path: &Path,
    staging_dir: &Path,
    mod_entry: &ModEntry,
    all_mods: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<TransactionRecord, String> {
    let pkg = mod_entry.package.as_ref().ok_or("missingPackage")?;
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    if adapter.kind == "loader-files" {
        stage_package(zip_path, staging_dir, pkg, adapter, &pck_dir, runner)?;
        return install_loader_files(
            config_dir,
            game_root,
            staging_dir,
            mod_entry,
            all_mods,
            lock_check,
        );
    }
    check_exclusive_conflicts(config_dir, game_root, mod_entry, adapter, all_mods)?;

    stage_package(zip_path, staging_dir, pkg, adapter, &pck_dir, runner)?;

    let pre_pck = file_fingerprint(&pck_path)?;
    if pre_pck.size != adapter.baseline.size
        || !pre_pck
            .sha256
            .eq_ignore_ascii_case(&adapter.baseline.sha256)
    {
        return Err("baselineMismatch".into());
    }
    if run_status_cmd(adapter, staging_dir, &pck_dir, runner)? != DiskModState::Vanilla {
        return Err("baselineMismatch".into());
    }

    let before_snapshot = snapshot_dir(&pck_dir, &adapter.baseline.file)?;
    let backup_dir = backup_dir_for(config_dir, game_root, &mod_entry.id);
    let version = mod_entry.version.clone().unwrap_or_default();
    let mut record = TransactionRecord {
        mod_id: mod_entry.id.clone(),
        repo: mod_entry.repo.clone(),
        version: version.clone(),
        exclusive: adapter.exclusive.clone(),
        pck_dir: pck_dir.clone(),
        status: TransactionStatus::Pending,
        pre_pck: pre_pck.clone(),
        post_pck: None,
        upstream_uninstall: adapter.upstream_uninstall,
        backup_dir: backup_dir.clone(),
        touched_files: adapter.touches.clone(),
        owned_files: BTreeMap::new(),
        failure: None,
        source_sha256: None,
        restoring_pck: None,
        preparation_rule: None,
        auto_installed: false,
    };
    if !sidecars_absent(adapter, &pck_dir)? {
        return Err("restoreResidue".into());
    }
    fs::create_dir_all(config_dir).map_err(|_| "fileWriteError")?;
    check_space(config_dir, pre_pck.size)?;
    let full_backup = backup_dir.join(&adapter.baseline.file);
    copy_atomic(&pck_path, &full_backup)?;
    if file_fingerprint(&full_backup)? != pre_pck {
        return Err("fileWriteError".into());
    }
    check_space(&pck_dir, pre_pck.size)?;
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    if file_fingerprint(&pck_path)? != pre_pck || !sidecars_absent(adapter, &pck_dir)? {
        return Err("gameUpdatedOrModified".into());
    }
    save_transaction(config_dir, game_root, record.clone())?;

    let outcome: Result<FileFingerprint, String> = (|| {
        let req = build_command(adapter, staging_dir, &pck_dir, &adapter.actions.install)?;
        let out = runner.run(&req)?;
        if out.code != 0 {
            return Err("installFailed".into());
        }
        let after_snapshot = snapshot_dir(&pck_dir, &adapter.baseline.file)?;
        verify_only_touches(&before_snapshot, &after_snapshot, &adapter.touches)?;
        if run_status_cmd(adapter, staging_dir, &pck_dir, runner)? != DiskModState::Installed {
            return Err("installFailed".into());
        }
        let post_pck = file_fingerprint(&pck_path)?;
        if post_pck == pre_pck {
            return Err("installFailed".into());
        }
        if uses_delta_restore(adapter) {
            mirror_delta_backup(adapter, staging_dir, &pck_dir, &backup_dir, &pre_pck.sha256)?;
        }
        Ok(post_pck)
    })();

    match outcome {
        Ok(post_pck) => {
            record.status = TransactionStatus::Committed;
            record.post_pck = Some(post_pck);
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
            let recovered = (|| -> Result<(), String> {
                lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
                copy_atomic(&full_backup, &pck_path)?;
                for name in adapter
                    .touches
                    .iter()
                    .filter(|n| *n != &adapter.baseline.file)
                {
                    let path = pck_dir.join(name);
                    if path.is_file() {
                        fs::remove_file(path).map_err(|_| "fileWriteError")?;
                    }
                }
                verify_only_touches(
                    &before_snapshot,
                    &snapshot_dir(&pck_dir, &adapter.baseline.file)?,
                    &adapter.touches,
                )?;
                if file_fingerprint(&pck_path)? != pre_pck || !sidecars_absent(adapter, &pck_dir)? {
                    return Err("restoreVerifyFailed".into());
                }
                Ok(())
            })()
            .is_ok();
            record.failure = Some(err.clone());
            record.status = if recovered {
                TransactionStatus::RolledBack
            } else {
                TransactionStatus::NeedsRepair
            };
            let _ = save_transaction(config_dir, game_root, record);
            if recovered {
                Err(err)
            } else {
                Err("restoreVerifyFailed".into())
            }
        }
    }
}

/// Offline uninstallation using mirrored delta restore + offline CLI or full-PCK backup.
pub fn uninstall_mod(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<FileFingerprint, String> {
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;

    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;

    let tx = get_transaction(config_dir, game_root, &mod_entry.id)?
        .ok_or_else(|| "missingTransaction".to_string())?;
    // Loader uninstall uses the installed transaction's fingerprints across catalog updates.
    let recorded_loader = tx.exclusive == "loader" && adapter.kind == "loader-files";
    if tx.mod_id != mod_entry.id
        || tx.pck_dir != pck_dir
        || tx.backup_dir != backup_dir_for(config_dir, game_root, &mod_entry.id)
        || (!recorded_loader && tx.version != mod_entry.version.as_deref().unwrap_or_default())
        || (tx.repo != mod_entry.repo
            && !(recorded_loader && mod_entry.legacy_inventory_repos.contains(&tx.repo)))
    {
        return Err("gameUpdatedOrModified".into());
    }
    if !(matches!(
        tx.status,
        TransactionStatus::Committed | TransactionStatus::NeedsRepair
    ) || tx.status == TransactionStatus::Pending && tx.exclusive == "loader")
    {
        return Err("missingTransaction".into());
    }

    if tx.exclusive == "pck" && adapter.source_rule.is_some() {
        let legacy = crate::catalog::legacy_entry(mod_entry)
            .filter(|m| m.adapter.as_ref().is_some_and(|a| a.exclusive == "pck"))
            .ok_or("gameUpdatedOrModified")?;
        let old = legacy.adapter.as_ref().ok_or("unsupportedAdapter")?;
        if tx.touched_files != old.touches
            || tx.pre_pck.size != adapter.baseline.size
            || tx.pre_pck.sha256 != adapter.baseline.sha256
        {
            return Err("gameUpdatedOrModified".into());
        }
        for sidecar in old
            .touches
            .iter()
            .filter(|name| *name != &old.baseline.file)
        {
            let path = pck_dir.join(sidecar);
            if path.exists() && file_fingerprint(&path)? != tx.pre_pck {
                return Err("gameUpdatedOrModified".into());
            }
        }
        return uninstall_mod(config_dir, game_root, &legacy, runner, lock_check);
    }

    if adapter.kind == "loader-files" {
        let managed_marker = pck_loader::read_managed_marker(&pck_dir)?;
        let current = file_fingerprint(&pck_path)?;
        let vanilla = (current.size == adapter.baseline.size
            && current.sha256 == adapter.baseline.sha256)
            || tx.restoring_pck.as_ref() == Some(&current);
        if let Some(marker) = &managed_marker {
            if (current.size != marker.patched_size || current.sha256 != marker.patched_sha256)
                && !resumable_loader_cleanup(&tx, marker, &current, &adapter.baseline)
            {
                return Err("gameUpdatedOrModified".into());
            }
        } else if adapter.auto_loader && !vanilla && !pck_loader::external_loader_present(&pck_dir)?
        {
            return Err("gameUpdatedOrModified".into());
        }

        let mod_dir = loader_mod_dir(&pck_dir, mod_entry);
        if pck_dir.join("mods").is_symlink() || mod_dir.is_symlink() {
            return Err("gameUpdatedOrModified".into());
        }
        let mods_root = pck_dir.join("mods");
        let loader_backup_dir = backup_dir_for(config_dir, game_root, "_mpm_loader");
        let prepared = if let Some(marker) = managed_marker
            && !pck_loader::external_loader_present(&pck_dir)?
            && !has_other_loader_tx(config_dir, game_root, &mod_entry.id, &adapter.exclusive)?
            && !has_remaining_mod_dirs(&mods_root, Some(&mod_dir))?
        {
            let backup = loader_backup_dir.join(&adapter.baseline.file);
            // A newer catalog can target a different game build than this installation.
            let vanilla = FileFingerprint {
                size: marker.vanilla_size,
                sha256: marker.vanilla_sha256.to_ascii_lowercase(),
            };
            if !(vanilla.size == adapter.baseline.size
                && vanilla
                    .sha256
                    .eq_ignore_ascii_case(&adapter.baseline.sha256))
                && vanilla != tx.pre_pck
                && tx.restoring_pck.as_ref() != Some(&vanilla)
                && file_fingerprint(&backup).ok().as_ref() != Some(&vanilla)
            {
                return Err("restoreCorrupt".into());
            }
            Some(pck_loader::prepare_managed_restore(
                &pck_dir, &backup, marker, current,
            )?)
        } else {
            None
        };
        let verify_mod = || -> Result<bool, String> {
            if pck_dir.join("mods").is_symlink() || mod_dir.is_symlink() {
                return Err("gameUpdatedOrModified".into());
            }
            if !mod_dir.try_exists().map_err(|_| "fileReadError")? {
                return Ok(false);
            }
            let disk = collect_dir_fingerprints(&mod_dir)?;
            let interrupted = tx.status == TransactionStatus::Pending
                || tx.failure.as_deref() == Some("uninstall");
            let matches = if interrupted {
                disk.iter()
                    .all(|(name, fp)| tx.owned_files.get(name) == Some(fp))
            } else {
                disk == tx.owned_files
            };
            if tx.owned_files.is_empty() || !matches {
                return Err("gameUpdatedOrModified".into());
            }
            Ok(true)
        };
        let mut mod_present = verify_mod()?;
        lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
        let mut undo = tx.clone();
        undo.status = TransactionStatus::NeedsRepair;
        undo.failure = Some("uninstall".into());
        if let Some(restore) = &prepared {
            undo.restoring_pck = Some(restore.restored.clone());
        }
        let restored_pck = undo.restoring_pck.clone();
        save_transaction(config_dir, game_root, undo)?;
        if let Some(restore) = prepared
            && !has_remaining_mod_dirs(&mods_root, Some(&mod_dir))?
            && !pck_loader::external_loader_present(&pck_dir)?
        {
            restore.apply(|| lock_check.ensure_unlocked(&pck_dir, &pck_path))?;
            mod_present = verify_mod()?;
            lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
        }
        if mod_present {
            fs::remove_dir_all(&mod_dir).map_err(|_| "fileWriteError")?;
            if mod_dir.exists() {
                return Err("restoreVerifyFailed".into());
            }
        }
        if !has_remaining_mod_dirs(&mods_root, None)? {
            match fs::remove_file(mod_state_path(&pck_dir)) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(_) => return Err("fileWriteError".into()),
            }
        } else if let Ok(mut disabled) = read_disabled_set(&pck_dir)
            && disabled.remove(&mod_entry.id)
        {
            write_disabled_mods(&pck_dir, &disabled)?;
        }
        let _ = fs::remove_dir(&mods_root);
        let disk = file_fingerprint(&pck_path)?;
        if restored_pck.as_ref() == Some(&disk)
            && !loader_marker_present(&pck_dir)?
            && !has_remaining_mod_dirs(&mods_root, None)?
        {
            let _ = fs::remove_dir_all(&loader_backup_dir);
        }
        clear_mod_records(config_dir, game_root, mod_entry, None)?;
        return Ok(disk);
    }

    let current_pck = file_fingerprint(&pck_path)?;
    if current_pck == tx.pre_pck {
        if !sidecars_absent(adapter, &pck_dir)? {
            return Err("restoreResidue".into());
        }
        clear_mod_records(config_dir, game_root, mod_entry, Some(&tx.backup_dir))?;
        return Ok(current_pck);
    }
    if tx.post_pck.as_ref() != Some(&current_pck) {
        return Err("gameUpdatedOrModified".into());
    }

    check_space(&pck_dir, tx.pre_pck.size)?;
    let full_backup = tx.backup_dir.join(&adapter.baseline.file);
    let disk_restore = pck_dir.join(RESTORE_DAT);
    if uses_delta_restore(adapter)
        && disk_restore.is_file()
        && file_fingerprint(&disk_restore)? != file_fingerprint(&tx.backup_dir.join(RESTORE_DAT))?
    {
        return Err("gameUpdatedOrModified".into());
    }
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    if file_fingerprint(&pck_path)? != current_pck {
        return Err("gameUpdatedOrModified".into());
    }
    let mut undo = tx.clone();
    undo.status = TransactionStatus::NeedsRepair;
    undo.failure = Some("uninstall".into());
    save_transaction(config_dir, game_root, undo)?;
    let before_snapshot = snapshot_dir(&pck_dir, &adapter.baseline.file)?;

    if !full_backup.is_file() && uses_delta_restore(adapter) {
        let program_path = tx.backup_dir.join(&adapter.run.program);
        if !program_path.is_file() {
            return Err("uninstallFailed".into());
        }
        if let Some(manifest) = &adapter.verify_files {
            verify_checksum_manifest(&tx.backup_dir, manifest, &adapter.run.program, &[])?;
        }
        let disk_restore = pck_dir.join(RESTORE_DAT);
        if !disk_restore.is_file() {
            let saved_restore = tx.backup_dir.join(RESTORE_DAT);
            if !saved_restore.is_file() {
                return Err("restoreCorrupt".into());
            }
            copy_atomic(&saved_restore, &disk_restore)?;
        }
        let header = parse_mp8r_restore(&disk_restore)?;
        if !header.base_sha.eq_ignore_ascii_case(&tx.pre_pck.sha256) {
            return Err("restoreCorrupt".into());
        }
        let req = build_command(
            adapter,
            &tx.backup_dir,
            &pck_dir,
            &adapter.actions.uninstall,
        )?;
        let out = runner.run(&req)?;
        if out.code != 0 {
            return Err("uninstallFailed".into());
        }
    } else {
        let full_backup = tx.backup_dir.join(&adapter.baseline.file);
        if !full_backup.is_file() || file_fingerprint(&full_backup)? != tx.pre_pck {
            return Err("restoreCorrupt".into());
        }
        copy_atomic(&full_backup, &pck_path)?;
        for name in adapter
            .touches
            .iter()
            .filter(|n| *n != &adapter.baseline.file)
        {
            let sidecar = pck_dir.join(name);
            if sidecar.is_file() {
                fs::remove_file(&sidecar).map_err(|_| "fileWriteError")?;
            }
        }
    }

    let after_snapshot = snapshot_dir(&pck_dir, &adapter.baseline.file)?;
    verify_only_touches(&before_snapshot, &after_snapshot, &adapter.touches)?;

    let restored = file_fingerprint(&pck_path)?;
    if restored != tx.pre_pck || !sidecars_absent(adapter, &pck_dir)? {
        return Err("restoreVerifyFailed".into());
    }

    clear_mod_records(config_dir, game_root, mod_entry, Some(&tx.backup_dir))?;
    Ok(restored)
}

/// Safely switches from conflicting manager-installed mod(s) to `mod_entry`.
#[allow(clippy::too_many_arguments)]
pub fn switch_from_zip(
    confirmed: &[String],
    config_dir: &Path,
    game_root: &Path,
    zip_path: &Path,
    staging_dir: &Path,
    mod_entry: &ModEntry,
    all_mods: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<TransactionRecord, String> {
    let pkg = mod_entry.package.as_ref().ok_or("missingPackage")?;
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;

    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;

    let validation = validate_game_mods(config_dir, game_root, all_mods)?;
    match validation.mod_states.get(&mod_entry.id).map(String::as_str) {
        Some("vanilla") => return Err("statusUnavailable".into()),
        Some("modConflict" | "legacyInstalled") => {}
        Some(other) => return Err(other.to_string()),
        None => return Err("unsupportedAdapter".into()),
    }

    let mut to_uninstall = Vec::new();
    for other in all_mods {
        if other.id == mod_entry.id {
            if validation.mod_states.get(&other.id).map(String::as_str) == Some("legacyInstalled") {
                to_uninstall.push(other);
            }
            continue;
        }
        let Some(other_adapter) = &other.adapter else {
            continue;
        };
        let conflicts = incompatible(adapter, other_adapter)
            || get_transaction(config_dir, game_root, &other.id)?
                .is_some_and(|tx| tx.exclusive == "pck");
        if !conflicts {
            continue;
        }
        match validation.mod_states.get(&other.id).map(String::as_str) {
            Some("installed" | "legacyInstalled") => to_uninstall.push(other),
            Some("vanilla") | Some("modConflict") | Some("loaderConflict") => {}
            _ => return Err("modConflict".into()),
        }
    }
    if confirmed.len() != to_uninstall.len()
        || to_uninstall
            .iter()
            .any(|item| !confirmed.contains(&item.id))
    {
        return Err("statusUnavailable".into());
    }
    if to_uninstall.is_empty() {
        return Err("modConflict".into());
    }

    let installed = inventory::installed_versions(config_dir, game_root)?;
    for repo in installed.keys() {
        if repo == mod_entry.inventory_key() {
            continue;
        }
        let handled = all_mods.iter().any(|other| {
            other.inventory_key() == repo
                && (to_uninstall.iter().any(|u| u.id == other.id)
                    || other.adapter.as_ref().is_some_and(|a| {
                        adapter.exclusive != "pck" && a.exclusive == adapter.exclusive
                    }))
        });
        if !handled {
            return Err("modConflict".into());
        }
    }

    if manual_eight_player_conflict(&pck_dir, adapter) {
        return Err("manualBroadcastConflict".into());
    }
    // Stage and preflight-verify the target archive before uninstalling the active mod.
    stage_package(zip_path, staging_dir, pkg, adapter, &pck_dir, runner)?;
    check_space(&pck_dir, adapter.baseline.size)?;

    for old_mod in to_uninstall {
        uninstall_mod(config_dir, game_root, old_mod, runner, lock_check)?;
    }

    let restored_pck = file_fingerprint(&pck_path)?;
    if !(adapter.exclusive == "loader" && loader_marker_present(&pck_dir)?)
        && (restored_pck.size != adapter.baseline.size
            || !restored_pck
                .sha256
                .eq_ignore_ascii_case(&adapter.baseline.sha256))
    {
        return Err("baselineMismatch".into());
    }

    if adapter.kind == "loader-files" {
        return install_loader_files(
            config_dir,
            game_root,
            staging_dir,
            mod_entry,
            all_mods,
            lock_check,
        );
    }
    install_from_zip(
        config_dir,
        game_root,
        zip_path,
        staging_dir,
        mod_entry,
        all_mods,
        runner,
        lock_check,
    )
}

/// Reloads or upgrades the built-in loader for `game_root` without touching installed mods.
pub fn reload_loader(
    config_dir: &Path,
    game_root: &Path,
    mods: &[ModEntry],
    expected_dir: Option<&Path>,
    force: bool,
    lock_check: &dyn GameLockCheck,
) -> Result<CopyValidation, String> {
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    if let Some(expected) = expected_dir
        && pck_dir != expected
    {
        return Err("statusUnavailable".into());
    }
    let baseline = mods
        .iter()
        .find_map(|item| {
            item.adapter
                .as_ref()
                .filter(|a| a.auto_loader)
                .map(|a| &a.baseline)
        })
        .ok_or("unsupportedMod")?;
    let pck_path = pck_dir.join(&baseline.file);
    lock_check.ensure_unlocked(&pck_dir, &pck_path)?;
    let pre_pck = file_fingerprint(&pck_path)?;
    check_space(&pck_dir, pre_pck.size)?;
    check_space(config_dir, pre_pck.size)?;
    let loader_backup_dir = backup_dir_for(config_dir, game_root, "_mpm_loader");
    let loader_backup_pck = loader_backup_dir.join(&baseline.file);
    pck_loader::reload_managed_loader(&pck_dir, &loader_backup_pck, baseline, force, || {
        lock_check.ensure_unlocked(&pck_dir, &pck_path)
    })?;
    scan_copy(config_dir, game_root, mods, true)
}
