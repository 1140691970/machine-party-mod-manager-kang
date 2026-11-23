use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use super::{
    adapters::{
        RESTORE_DAT, mirror_delta_backup, parse_mp8r_restore, resumable_loader_cleanup,
        run_status_cmd, uses_delta_restore, validate_adapter,
    },
    conflicts::{
        has_unmanaged_loader_dirs, loader_marker_present, loader_mod_dir,
        manual_eight_player_conflict, sidecars_absent,
    },
    runner::{GameLockCheck, ProcessRunner, SystemGameLockCheck, SystemRunner},
    state::{MOD_STATE_FILE, read_disabled_mods},
    transaction::{
        DiskModState, FileFingerprint, TRANSACTIONS_FILE, TransactionRecord, TransactionStatus,
        backup_dir_for, check_space, clear_mod_records, collect_dir_paths, copy_atomic,
        file_fingerprint, get_transaction, is_safe_filename, read_transactions, remove_transaction,
        save_transaction, short_hash, write_atomic,
    },
    update,
    zip::stage_package,
};
use crate::{catalog::ModEntry, game, inventory, pck_loader};

/// Inspection snapshot combining disk fingerprints, CLI status, and local records.
#[derive(Clone, Debug, PartialEq, Eq)]
#[allow(dead_code)] // Fields read by Stage 3 IPC and unit tests.
pub struct ModInspection {
    pub pck_dir: PathBuf,
    pub pck_fingerprint: FileFingerprint,
    pub disk_state: DiskModState,
    pub recorded_version: Option<String>,
    pub has_backup: bool,
    pub adoptable_manual_install: bool,
    pub game_updated_or_modified: bool,
}

/// Validation summary for a game copy evaluated against the active mod list.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CopyValidation {
    pub pck_dir: PathBuf,
    pub pck_path: PathBuf,
    pub pck_size: u64,
    pub pck_sha256: String,
    pub repair: BTreeMap<String, (PathBuf, Option<String>)>,
    pub installed: inventory::Installed,
    pub mod_states: BTreeMap<String, String>,
    #[serde(default)]
    pub disabled_mods: Vec<String>,
    pub loader: pck_loader::LoaderStatus,
}

/// Reconciled state of a game copy after restart, interruption, or Steam update.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReconcileState {
    Vanilla,
    Installed,
    ReconciledVanilla,
    NeedsRepair,
    ManualInstallAdoptable,
    GameUpdatedOrModified,
    UnknownModification,
}

/// Adopts a pre-existing manual installation only when its restore baseline matches vanilla.
pub fn adopt_manual_install(
    config_dir: &Path,
    game_root: &Path,
    package_dir: &Path,
    mod_entry: &ModEntry,
    runner: &dyn ProcessRunner,
) -> Result<TransactionRecord, String> {
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;
    if !uses_delta_restore(adapter) {
        return Err("unsupportedAdapter".into());
    }

    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    if run_status_cmd(adapter, package_dir, &pck_dir, runner)? != DiskModState::Installed {
        return Err("baselineMismatch".into());
    }

    let restore_path = pck_dir.join(RESTORE_DAT);
    let header = parse_mp8r_restore(&restore_path)?;
    if !header
        .base_sha
        .eq_ignore_ascii_case(&adapter.baseline.sha256)
    {
        return Err("baselineMismatch".into());
    }

    let post_pck = file_fingerprint(&pck_path)?;
    let backup_dir = backup_dir_for(config_dir, game_root, &mod_entry.id);
    fs::create_dir_all(config_dir).map_err(|_| "fileWriteError")?;
    check_space(config_dir, post_pck.size.saturating_mul(2))?;
    let trial = tempfile::tempdir_in(config_dir).map_err(|_| "fileWriteError")?;
    let trial_pck = trial.path().join(&adapter.baseline.file);
    copy_atomic(&pck_path, &trial_pck)?;
    copy_atomic(&restore_path, &trial.path().join(RESTORE_DAT))?;
    let req = super::adapters::build_command(
        adapter,
        package_dir,
        trial.path(),
        &adapter.actions.uninstall,
    )?;
    let result = runner.run(&req)?;
    let original = file_fingerprint(&trial_pck)?;
    if result.code != 0
        || original.size != adapter.baseline.size
        || original.sha256 != adapter.baseline.sha256
        || !sidecars_absent(adapter, trial.path())?
    {
        return Err("restoreCorrupt".into());
    }
    SystemGameLockCheck.ensure_unlocked(&pck_dir, &pck_path)?;
    if file_fingerprint(&pck_path)? != post_pck {
        return Err("gameUpdatedOrModified".into());
    }
    let full_backup = backup_dir.join(&adapter.baseline.file);
    copy_atomic(&trial_pck, &full_backup)?;
    if file_fingerprint(&full_backup)? != original {
        return Err("fileWriteError".into());
    }
    mirror_delta_backup(
        adapter,
        package_dir,
        &pck_dir,
        &backup_dir,
        &adapter.baseline.sha256,
    )?;

    let version = mod_entry.version.clone().unwrap_or_default();
    let record = TransactionRecord {
        mod_id: mod_entry.id.clone(),
        repo: mod_entry.repo.clone(),
        version: version.clone(),
        exclusive: adapter.exclusive.clone(),
        pck_dir,
        status: TransactionStatus::Committed,
        pre_pck: FileFingerprint {
            size: adapter.baseline.size,
            sha256: adapter.baseline.sha256.clone(),
        },
        post_pck: Some(post_pck),
        upstream_uninstall: adapter.upstream_uninstall,
        backup_dir,
        touched_files: adapter.touches.clone(),
        owned_files: BTreeMap::new(),
        failure: None,
        source_sha256: None,
        restoring_pck: None,
        preparation_rule: None,
        auto_installed: false,
    };
    save_transaction(config_dir, game_root, record.clone())?;
    inventory::record_installed(config_dir, game_root, mod_entry.inventory_key(), &version)?;
    Ok(record)
}

/// Reconciles transaction records, `installations.json`, and disk reality for one mod.
#[allow(dead_code)] // Wired into Tauri commands in Stage 3; exercised by L1 tests.
pub fn reconcile_copy(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    package_dir: Option<&Path>,
    runner: &dyn ProcessRunner,
) -> Result<ReconcileState, String> {
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    let current_pck = file_fingerprint(&pck_path)?;
    let is_vanilla = current_pck.size == adapter.baseline.size
        && current_pck
            .sha256
            .eq_ignore_ascii_case(&adapter.baseline.sha256);

    let tx = get_transaction(config_dir, game_root, &mod_entry.id)?;
    let installed = inventory::installed_versions(config_dir, game_root)?;
    let in_inventory = installed.contains_key(mod_entry.inventory_key());

    if let Some(ref record) = tx
        && record.status == TransactionStatus::Pending
    {
        if current_pck == record.pre_pck {
            let _ = fs::remove_dir_all(&record.backup_dir);
            remove_transaction(config_dir, game_root, &mod_entry.id)?;
            return Ok(ReconcileState::Vanilla);
        }
        return Ok(ReconcileState::NeedsRepair);
    }

    if in_inventory
        || tx
            .as_ref()
            .is_some_and(|r| r.status == TransactionStatus::Committed)
    {
        if is_vanilla {
            clear_mod_records(
                config_dir,
                game_root,
                mod_entry,
                tx.as_ref().map(|r| r.backup_dir.as_path()),
            )?;
            return Ok(ReconcileState::ReconciledVanilla);
        }
        if let Some(record) = &tx
            && record
                .post_pck
                .as_ref()
                .is_some_and(|post| post != &current_pck)
        {
            return Ok(ReconcileState::GameUpdatedOrModified);
        }
        let tool_dir = package_dir.or_else(|| {
            tx.as_ref()
                .map(|r| r.backup_dir.as_path())
                .filter(|dir| dir.join(&adapter.run.program).is_file())
        });
        if let Some(dir) = tool_dir {
            match run_status_cmd(adapter, dir, &pck_dir, runner)? {
                DiskModState::Installed => return Ok(ReconcileState::Installed),
                DiskModState::Vanilla => {
                    clear_mod_records(
                        config_dir,
                        game_root,
                        mod_entry,
                        tx.as_ref().map(|r| r.backup_dir.as_path()),
                    )?;
                    return Ok(ReconcileState::ReconciledVanilla);
                }
                _ => return Ok(ReconcileState::GameUpdatedOrModified),
            }
        }
        return Ok(ReconcileState::Installed);
    }

    if is_vanilla {
        return Ok(ReconcileState::Vanilla);
    }

    if let Some(dir) = package_dir
        && run_status_cmd(adapter, dir, &pck_dir, runner)? == DiskModState::Installed
    {
        let restore_path = pck_dir.join(RESTORE_DAT);
        if restore_path.is_file()
            && parse_mp8r_restore(&restore_path)
                .is_ok_and(|h| h.base_sha.eq_ignore_ascii_case(&adapter.baseline.sha256))
        {
            return Ok(ReconcileState::ManualInstallAdoptable);
        }
    }

    Ok(ReconcileState::UnknownModification)
}

/// Returns a full inspection summary for a single mod and game copy.
#[allow(dead_code)] // Wired into Tauri commands in Stage 3; exercised by L1 tests.
pub fn inspect_mod(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    package_dir: Option<&Path>,
    runner: &dyn ProcessRunner,
) -> Result<ModInspection, String> {
    let adapter = mod_entry.adapter.as_ref().ok_or("unsupportedAdapter")?;
    validate_adapter(adapter)?;
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let pck_path = pck_dir.join(&adapter.baseline.file);
    let pck_fingerprint = file_fingerprint(&pck_path)?;
    let installed = inventory::installed_versions(config_dir, game_root)?;
    let recorded_version = installed.get(mod_entry.inventory_key()).cloned();
    let tx = get_transaction(config_dir, game_root, &mod_entry.id)?;
    let has_backup = tx.as_ref().is_some_and(|r| r.backup_dir.is_dir());

    let tool_dir = package_dir.or_else(|| {
        tx.as_ref()
            .map(|r| r.backup_dir.as_path())
            .filter(|dir| dir.join(&adapter.run.program).is_file())
    });
    let disk_state = if let Some(dir) = tool_dir {
        run_status_cmd(adapter, dir, &pck_dir, runner)?
    } else if pck_fingerprint.size == adapter.baseline.size
        && pck_fingerprint
            .sha256
            .eq_ignore_ascii_case(&adapter.baseline.sha256)
    {
        DiskModState::Vanilla
    } else {
        DiskModState::Unrecognized(String::new())
    };

    let reconciled = reconcile_copy(config_dir, game_root, mod_entry, package_dir, runner)?;
    Ok(ModInspection {
        pck_dir,
        pck_fingerprint,
        disk_state,
        recorded_version,
        has_backup,
        adoptable_manual_install: reconciled == ReconcileState::ManualInstallAdoptable,
        game_updated_or_modified: reconciled == ReconcileState::GameUpdatedOrModified,
    })
}

/// Validates a game copy's disk state against the active mod list with one PCK fingerprint pass.
pub fn validate_game_mods(
    config_dir: &Path,
    game_root: &Path,
    mods: &[ModEntry],
) -> Result<CopyValidation, String> {
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let current_pck = file_fingerprint(&pck_dir.join("Machine Party.pck"))?;
    let mut installed = inventory::installed_versions(config_dir, game_root)?;
    let transactions = read_transactions(config_dir)?;
    let effective: Vec<_> = mods
        .iter()
        .map(|item| {
            if item
                .adapter
                .as_ref()
                .is_some_and(|a| a.source_rule.is_some())
                && transactions
                    .get(game_root)
                    .and_then(|records| records.get(&item.id))
                    .is_some_and(|r| {
                        r.exclusive == "pck" && r.status != TransactionStatus::RolledBack
                    })
            {
                crate::catalog::legacy_entry(item).unwrap_or_else(|| item.clone())
            } else {
                item.clone()
            }
        })
        .collect();
    let catalog_mods = mods;
    let mods = effective.as_slice();
    let mut mod_states = BTreeMap::new();
    let mut repair = BTreeMap::new();
    let loader_present = loader_marker_present(&pck_dir)?;
    let external_loader = pck_loader::external_loader_present(&pck_dir)?;
    let managed_marker = pck_loader::read_managed_marker(&pck_dir)?;
    let managed_loader_tampered = managed_marker.as_ref().is_some_and(|m| {
        current_pck.size != m.patched_size
            || !current_pck.sha256.eq_ignore_ascii_case(&m.patched_sha256)
    });
    let unmanaged_loader_dirs =
        has_unmanaged_loader_dirs(&pck_dir, mods, &transactions, game_root)?;
    let active_pck_mod = mods.iter().find_map(|item| {
        let adapter = item.adapter.as_ref()?;
        if adapter.exclusive != "pck" {
            return None;
        }
        let tx = transactions.get(game_root)?.get(&item.id)?;
        (tx.status == TransactionStatus::Committed && tx.post_pck.as_ref() == Some(&current_pck))
            .then_some(item.id.as_str())
    });
    let has_pck_sidecar_residue = active_pck_mod.is_none()
        && (pck_dir.join("Machine Party.pck.broadcast_backup").exists()
            || mods.iter().any(|other| {
                other.adapter.as_ref().is_some_and(|a| {
                    a.exclusive == "pck" && !sidecars_absent(a, &pck_dir).unwrap_or(false)
                })
            }));
    let mut has_active_loader_mod = false;
    for item in mods {
        if item
            .adapter
            .as_ref()
            .is_some_and(|adapter| adapter.kind == "loader-files")
            && loader_mod_dir(&pck_dir, item).exists()
        {
            has_active_loader_mod = true;
            break;
        }
    }

    for item in mods {
        let Some(adapter) = &item.adapter else {
            continue;
        };
        validate_adapter(adapter)?;
        let tx = transactions
            .get(game_root)
            .and_then(|records| records.get(&item.id));
        let vanilla = current_pck.size == adapter.baseline.size
            && current_pck.sha256 == adapter.baseline.sha256;
        let restore = pck_dir.join(RESTORE_DAT);
        let mut failure = tx.and_then(|r| r.failure.clone());
        let state = if adapter.kind == "loader-files" {
            let mod_dir = loader_mod_dir(&pck_dir, item);
            if tx.zip(managed_marker.as_ref()).is_some_and(|(r, marker)| {
                resumable_loader_cleanup(r, marker, &current_pck, &adapter.baseline)
            }) {
                "needsRepair"
            } else if managed_loader_tampered
                || (tx.is_some_and(|r| {
                    r.exclusive == "loader" && r.status != TransactionStatus::RolledBack
                }) && adapter.auto_loader
                    && !loader_present
                    && !vanilla
                    && !tx.is_some_and(|r| r.restoring_pck.as_ref() == Some(&current_pck)))
            {
                "gameUpdatedOrModified"
            } else if tx.is_some_and(|r| match r.status {
                TransactionStatus::Committed => {
                    !mod_dir.is_dir() || (adapter.auto_loader && !loader_present)
                }
                TransactionStatus::NeedsRepair | TransactionStatus::Pending => true,
                TransactionStatus::RolledBack => false,
            }) {
                "needsRepair"
            } else if mod_dir.exists() {
                if let Some(record) = tx.filter(|r| r.status == TransactionStatus::Committed)
                    && !record.owned_files.is_empty()
                {
                    match update::verify_files(&mod_dir, &record.owned_files) {
                        Ok(()) => {
                            installed
                                .insert(item.inventory_key().to_owned(), record.version.clone());
                            "installed"
                        }
                        Err(reason) => {
                            failure = Some(reason);
                            "needsRepair"
                        }
                    }
                } else if installed.contains_key(item.inventory_key()) {
                    "needsRepair"
                } else {
                    "restoreResidue"
                }
            } else {
                installed.remove(item.inventory_key());
                if manual_eight_player_conflict(&pck_dir, adapter) {
                    "manualBroadcastConflict"
                } else if active_pck_mod.is_some()
                    || mods.iter().any(|other| {
                        other.id != item.id
                            && other.adapter.as_ref().is_some_and(|a| {
                                a.conflict_group.is_some()
                                    && a.conflict_group == adapter.conflict_group
                            })
                            && loader_mod_dir(&pck_dir, other).exists()
                    })
                {
                    "modConflict"
                } else if has_pck_sidecar_residue {
                    "restoreResidue"
                } else if !vanilla && !loader_present {
                    "gameUpdatedOrModified"
                } else {
                    "vanilla"
                }
            }
        } else if tx.is_some_and(|r| {
            matches!(
                r.status,
                TransactionStatus::Pending | TransactionStatus::NeedsRepair
            )
        }) {
            "needsRepair"
        } else if external_loader && adapter.exclusive == "pck" {
            "loaderConflict"
        } else if managed_loader_tampered {
            "gameUpdatedOrModified"
        } else if has_active_loader_mod
            && adapter.exclusive == "pck"
            && (vanilla || managed_marker.is_some())
        {
            if unmanaged_loader_dirs {
                "loaderConflict"
            } else {
                "modConflict"
            }
        } else if managed_marker.is_some() && adapter.exclusive == "pck" {
            "loaderConflict"
        } else if vanilla {
            installed.remove(item.inventory_key());
            if sidecars_absent(adapter, &pck_dir)? {
                "vanilla"
            } else {
                "restoreResidue"
            }
        } else if let Some(record) = tx.filter(|r| r.status == TransactionStatus::Committed) {
            if record.post_pck.as_ref() == Some(&current_pck) {
                installed.insert(item.inventory_key().to_owned(), record.version.clone());
                "installed"
            } else {
                "gameUpdatedOrModified"
            }
        } else if installed.contains_key(item.inventory_key()) {
            "needsRepair"
        } else if active_pck_mod.is_some_and(|id| id != item.id) {
            "modConflict"
        } else if uses_delta_restore(adapter)
            && restore.is_file()
            && parse_mp8r_restore(&restore).is_ok_and(|h| {
                h.base_sha.eq_ignore_ascii_case(&adapter.baseline.sha256)
                    && h.patched_len > 0
                    && h.patched_len as u64 == current_pck.size
            })
        {
            let pkg = item.package.as_ref().ok_or("missingPackage")?;
            let zip = crate::packages::existing(config_dir, item)?;
            if zip.is_file() {
                let tmp = tempfile::tempdir().map_err(|_| "fileWriteError")?;
                let staging = tmp.path().join("inspect");
                stage_package(&zip, &staging, pkg, adapter, &pck_dir, &SystemRunner)?;
                if run_status_cmd(adapter, &staging, &pck_dir, &SystemRunner)?
                    == DiskModState::Installed
                {
                    "manualInstall"
                } else {
                    "gameUpdatedOrModified"
                }
            } else {
                "identifyPending"
            }
        } else {
            "gameUpdatedOrModified"
        };
        if let Some(record) = tx
            && matches!(
                state,
                "needsRepair" | "gameUpdatedOrModified" | "restoreResidue"
            )
        {
            repair.insert(item.id.clone(), (record.backup_dir.clone(), failure));
        }
        let state = if state == "installed"
            && tx.is_some_and(|r| r.exclusive == "pck")
            && catalog_mods.iter().any(|m| {
                m.id == item.id && m.adapter.as_ref().is_some_and(|a| a.source_rule.is_some())
            }) {
            "legacyInstalled"
        } else {
            state
        };
        mod_states.insert(item.id.clone(), state.to_owned());
    }
    let loader = pck_loader::inspect_loader(&pck_dir, &current_pck)?;
    let disabled_mods = read_disabled_mods(&pck_dir)?
        .into_iter()
        .filter(|id| is_safe_filename(id) && pck_dir.join("mods").join(id).is_dir())
        .collect();
    Ok(CopyValidation {
        pck_path: pck_dir.join("Machine Party.pck"),
        pck_dir,
        pck_size: current_pck.size,
        pck_sha256: current_pck.sha256,
        repair,
        installed,
        mod_states,
        disabled_mods,
        loader,
    })
}

#[derive(Serialize, Deserialize, PartialEq, Eq)]
struct ScanStamp {
    loader_version: String,
    catalog: Vec<ModEntry>,
    files: BTreeMap<PathBuf, Option<(String, u64, std::time::SystemTime)>>,
}

fn scan_stamp(config: &Path, root: &Path, mods: &[ModEntry]) -> Result<ScanStamp, String> {
    let dir = game::resolve_pck_dir(root).ok_or("invalidGame")?;
    let mut paths = vec![
        dir.join("MachinePartyModLoader.exe"),
        dir.join("Machine Party.pck.modloader.json"),
        dir.join("Machine Party.exe"),
        dir.join("Machine Party.pck"),
        dir.join("mods"),
        dir.join("Machine Party.pck.broadcast_backup"),
        config.join(TRANSACTIONS_FILE),
        config.join("installations.json"),
    ];
    let mods_root = dir.join("mods");
    paths.push(mods_root.join(MOD_STATE_FILE));
    if mods_root.is_dir() {
        for entry in fs::read_dir(&mods_root).map_err(|_| "fileReadError".to_string())? {
            let entry = entry.map_err(|_| "fileReadError".to_string())?;
            paths.push(entry.path());
        }
    }
    for item in mods {
        if let Some(adapter) = &item.adapter {
            if adapter.kind == "loader-files" {
                let mod_dir = loader_mod_dir(&dir, item);
                paths.push(mod_dir.clone());
                if mod_dir.is_dir() {
                    collect_dir_paths(&mod_dir, &mut paths)?;
                }
            } else {
                paths.extend(adapter.touches.iter().map(|name| dir.join(name)));
                let backup = backup_dir_for(config, root, &item.id);
                paths.push(backup.join(&adapter.baseline.file));
                paths.push(backup.join(RESTORE_DAT));
            }
            if item.package.is_some() {
                paths.push(crate::packages::existing(config, item)?);
            }
        }
    }
    let mut files = BTreeMap::new();
    for path in paths {
        let stamp = match fs::metadata(&path) {
            Ok(m) => Some((
                format!(
                    "{:?}",
                    file_id::get_file_id(&path).map_err(|_| "fileReadError")?
                ),
                m.len(),
                m.modified().map_err(|_| "fileReadError")?,
            )),
            Err(e) if e.kind() == io::ErrorKind::NotFound => None,
            Err(_) => return Err("fileReadError".into()),
        };
        files.insert(path, stamp);
    }
    Ok(ScanStamp {
        loader_version: pck_loader::LOADER_VERSION.into(),
        catalog: mods.to_vec(),
        files,
    })
}

pub fn scan_copy(
    config: &Path,
    root: &Path,
    mods: &[ModEntry],
    force: bool,
) -> Result<CopyValidation, String> {
    let cache = config.join("scan-v2").join(short_hash(root));
    let before = scan_stamp(config, root, mods)?;
    if !force
        && let Some((stamp, prior)) = fs::read(&cache)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<(ScanStamp, CopyValidation)>(&bytes).ok())
        && stamp == before
        && !prior.mod_states.values().any(|s| s == "needsRepair")
    {
        return Ok(prior);
    }
    let result = validate_game_mods(config, root, mods)?;
    if scan_stamp(config, root, mods)? != before {
        return Err("statusUnavailable".into());
    }
    let bytes = serde_json::to_vec(&(before, &result)).map_err(|_| "fileWriteError")?;
    write_atomic(&cache, &bytes)?;
    Ok(result)
}
