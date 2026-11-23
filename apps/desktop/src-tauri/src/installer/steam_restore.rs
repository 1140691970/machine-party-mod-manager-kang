use super::*;

use crate::{game::steam_verify::directory_id, pck_loader::LOADER_SIDECAR};

const PCK: &str = "Machine Party.pck";

// Resolve each component without following links or Windows junctions, including on retries.
fn present(root: &Path, rel: &Path) -> Result<bool, String> {
    let mut path = root.to_owned();
    for part in rel.components() {
        let Component::Normal(name) = part else {
            return Err("gameUpdatedOrModified".into());
        };
        path.push(name);
        match fs::symlink_metadata(&path) {
            Ok(meta) if update::redirected(&meta) => return Err("gameUpdatedOrModified".into()),
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
            Err(_) => return Err("fileReadError".into()),
        }
    }
    Ok(true)
}

#[derive(Default, PartialEq, Eq, Serialize, Deserialize)]
struct Cleanup {
    files: BTreeMap<PathBuf, FileFingerprint>,
    mods: Vec<(PathBuf, String, String)>,
    dirs: std::collections::BTreeSet<PathBuf>,
}

fn plan(config: &Path, dir: &Path, entries: &[ModEntry]) -> Result<Cleanup, String> {
    let mut plan = Cleanup::default();
    let identity = directory_id(dir)?;
    for (root, records) in read_transactions(config)? {
        let Some(recorded) = game::resolve_pck_dir(&root) else {
            continue;
        };
        if directory_id(&recorded)? != identity {
            continue;
        }
        for (id, tx) in records {
            if tx.status == TransactionStatus::RolledBack {
                continue;
            }
            let item = entries
                .iter()
                .find(|item| item.id == id)
                .ok_or("missingTransaction")?;
            if !is_safe_filename(&id)
                || tx.mod_id != id
                || (tx.repo != item.repo && !item.legacy_inventory_repos.contains(&tx.repo))
                || directory_id(&tx.pck_dir)? != identity
                || tx.backup_dir != backup_dir_for(config, &root, &id)
                || tx.status != TransactionStatus::Committed
                || tx.backup_dir.join("update.json").exists()
            {
                return Err("needsRepair".into());
            }
            if tx.exclusive == "loader" {
                let rel = Path::new("mods").join(&id);
                if present(dir, &rel)? {
                    if tx.owned_files.is_empty() {
                        return Err("missingTransaction".into());
                    }
                    for (name, fp) in collect_dir_fingerprints(&dir.join(&rel))? {
                        if tx.owned_files.get(&name) != Some(&fp) {
                            return Err(format!("gameUpdatedOrModified: {name}"));
                        }
                        plan.files
                            .insert(rel.join(validate_rel_components(&name)?), fp);
                    }
                    for name in tx.owned_files.keys() {
                        let file = rel.join(validate_rel_components(name)?);
                        plan.dirs.extend(
                            file.ancestors()
                                .skip(1)
                                .take_while(|p| p.starts_with(&rel))
                                .map(Path::to_owned),
                        );
                    }
                }
            } else if tx.exclusive == "pck" {
                let legacy = crate::catalog::legacy_entry(item);
                // Early delta installations predate the catalog's MPML conversion.
                let delta = tx.upstream_uninstall && tx.touched_files == [PCK, RESTORE_DAT];
                let known = legacy
                    .iter()
                    .chain(std::iter::once(item))
                    .filter_map(|entry| entry.adapter.as_ref())
                    .any(|a| a.exclusive == "pck" && a.touches == tx.touched_files);
                if !delta && !known {
                    return Err("gameUpdatedOrModified".into());
                }
                for name in tx.touched_files.iter().filter(|n| n.as_str() != PCK) {
                    if !is_safe_filename(name) {
                        return Err("restoreCorrupt".into());
                    }
                    if !present(dir, Path::new(name))? {
                        continue;
                    }
                    let fp = file_fingerprint(&dir.join(name))?;
                    let expected = if name == RESTORE_DAT {
                        file_fingerprint(&tx.backup_dir.join(name))?
                    } else {
                        tx.pre_pck.clone()
                    };
                    if fp != expected {
                        return Err("gameUpdatedOrModified".into());
                    }
                    plan.files.insert(name.into(), fp);
                }
            } else {
                return Err("unsupportedAdapter".into());
            }
            plan.mods
                .push((root.clone(), id, item.inventory_key().to_owned()));
        }
    }
    for (root, installed) in inventory::installed_copies(config)? {
        let Some(recorded) = game::resolve_pck_dir(&root) else {
            continue;
        };
        if directory_id(&recorded)? == identity
            && installed
                .keys()
                .any(|key| !plan.mods.iter().any(|(r, _, k)| r == &root && k == key))
        {
            return Err("missingTransaction".into());
        }
    }
    if present(dir, Path::new(LOADER_SIDECAR))?
        && pck_loader::read_managed_marker(dir)?.is_some()
        && !pck_loader::external_loader_present(dir)?
    {
        plan.files.insert(
            LOADER_SIDECAR.into(),
            file_fingerprint(&dir.join(LOADER_SIDECAR))?,
        );
    }
    Ok(plan)
}

// Repeated requests against the same files reuse the verified snapshot, including the large PCK.
fn backup(config: &Path, root: &Path, dir: &Path, cleanup: &Cleanup) -> Result<(), String> {
    let backups = backup_dir_for(config, root, "_steam_restore");
    fs::create_dir_all(&backups).map_err(|_| "fileWriteError")?;
    let mut files = cleanup.files.clone();
    if !present(dir, Path::new(PCK))? {
        return Err("invalidGame".into());
    }
    files.insert(PCK.into(), file_fingerprint(&dir.join(PCK))?);
    for name in [TRANSACTIONS_FILE, inventory::INVENTORY_FILE] {
        let source = config.join(name);
        if source.try_exists().map_err(|_| "inventoryError")? {
            files.insert(Path::new("records").join(name), file_fingerprint(&source)?);
        }
    }
    let manifest = serde_json::to_vec(&files).map_err(|_| "inventoryError")?;
    let dest = backups.join(hex::encode(Sha256::digest(manifest)));
    let staging = if dest.try_exists().map_err(|_| "fileReadError")? {
        None
    } else {
        Some(tempfile::tempdir_in(&backups).map_err(|_| "fileWriteError")?)
    };
    for (rel, fp) in files {
        let saved = staging
            .as_ref()
            .map_or(dest.as_path(), |d| d.path())
            .join(&rel);
        if staging.is_some() {
            let source = if let Ok(record) = rel.strip_prefix("records") {
                config.join(record)
            } else {
                if !present(dir, &rel)? {
                    return Err("gameUpdatedOrModified".into());
                }
                dir.join(&rel)
            };
            copy_atomic(&source, &saved)?;
        }
        if file_fingerprint(&saved)? != fp {
            return Err("restoreCorrupt".into());
        }
    }
    if let Some(staging) = staging {
        fs::rename(staging.path(), dest).map_err(|_| "fileWriteError")?;
    }
    Ok(())
}

#[derive(Serialize, Deserialize)]
struct Journal {
    pck: FileFingerprint,
    cleanup: Cleanup,
}

fn journal_path(config: &Path, dir: &Path) -> Result<PathBuf, String> {
    use file_id::FileId;
    let key = match directory_id(dir)? {
        FileId::Inode {
            device_id,
            inode_number,
        } => format!("inode-{device_id:x}-{inode_number:x}"),
        FileId::LowRes {
            volume_serial_number,
            file_index,
        } => format!("low-{volume_serial_number:x}-{file_index:x}"),
        FileId::HighRes {
            volume_serial_number,
            file_id,
        } => format!("high-{volume_serial_number:x}-{file_id:x}"),
    };
    Ok(config.join("steam-restore").join(format!("{key}.json")))
}

pub fn pending(config: &Path, dir: &Path) -> Result<bool, String> {
    journal_path(config, dir)?
        .try_exists()
        .map_err(|_| "fileReadError".into())
}

pub fn recover(
    config: &Path,
    root: &Path,
    entries: &[ModEntry],
    lock_check: &dyn GameLockCheck,
) -> Result<bool, String> {
    let Some(dir) = game::resolve_pck_dir(root) else {
        return Ok(false);
    };
    let path = journal_path(config, &dir)?;
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(_) => return Err("fileReadError".into()),
    };
    let journal: Journal = serde_json::from_slice(&bytes).map_err(|_| "restoreCorrupt")?;
    lock_check.ensure_unlocked(&dir, &dir.join(PCK))?;
    if file_fingerprint(&dir.join(PCK))? != journal.pck {
        return Err("gameUpdatedOrModified".into());
    }
    // Derive every write target from the current ownership records again. Missing files or
    // records may already have been removed before the interruption.
    let remaining = plan(config, &dir, entries)?;
    if remaining
        .files
        .iter()
        .any(|(name, fp)| journal.cleanup.files.get(name) != Some(fp))
        || remaining
            .mods
            .iter()
            .any(|m| !journal.cleanup.mods.contains(m))
        || remaining
            .dirs
            .iter()
            .any(|d| !journal.cleanup.dirs.contains(d))
    {
        return Err("gameUpdatedOrModified".into());
    }
    for m in &journal.cleanup.mods {
        if !remaining.mods.contains(m) && get_transaction(config, &m.0, &m.1)?.is_some() {
            return Err("gameUpdatedOrModified".into());
        }
    }
    finish(config, &dir, remaining, lock_check, &path)?;
    Ok(true)
}

pub fn restore(
    config: &Path,
    root: &Path,
    dir: &Path,
    entries: &[ModEntry],
    lock_check: &dyn GameLockCheck,
    verify: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    let lock = || lock_check.ensure_unlocked(dir, &dir.join(PCK));
    lock()?;
    let cleanup = plan(config, dir, entries)?;
    backup(config, root, dir, &cleanup)?;
    lock()?;
    verify()?;
    lock()?;
    let restored = file_fingerprint(&dir.join(PCK))?;
    if !entries.iter().filter_map(|m| m.adapter.as_ref()).any(|a| {
        a.baseline.size == restored.size && a.baseline.sha256.eq_ignore_ascii_case(&restored.sha256)
    }) {
        return Err("baselineMismatch".into());
    }
    if cleanup != plan(config, dir, entries)? {
        return Err("gameUpdatedOrModified".into());
    }
    let path = journal_path(config, dir)?;
    let journal = Journal {
        pck: restored,
        cleanup,
    };
    write_atomic(
        &path,
        &serde_json::to_vec(&journal).map_err(|_| "inventoryError")?,
    )?;
    finish(config, dir, journal.cleanup, lock_check, &path)
}

fn finish(
    config: &Path,
    dir: &Path,
    cleanup: Cleanup,
    lock_check: &dyn GameLockCheck,
    journal: &Path,
) -> Result<(), String> {
    let lock = || lock_check.ensure_unlocked(dir, &dir.join(PCK));
    for (rel, fp) in &cleanup.files {
        lock()?;
        if !present(dir, rel)? || file_fingerprint(&dir.join(rel))? != *fp {
            return Err("gameUpdatedOrModified".into());
        }
        fs::remove_file(dir.join(rel)).map_err(|_| "fileWriteError")?;
    }
    for rel in cleanup.dirs.iter().rev() {
        if present(dir, rel)? {
            lock()?;
            match fs::remove_dir(dir.join(rel)) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::DirectoryNotEmpty => {}
                Err(_) => return Err("fileWriteError".into()),
            }
        }
    }
    let state_path = dir.join("mods").join(MOD_STATE_FILE);
    if !matches!(
        fs::symlink_metadata(&state_path),
        Err(ref e) if e.kind() == io::ErrorKind::NotFound
    ) {
        lock()?;
        match fs::remove_file(&state_path) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(_) => return Err("fileWriteError".into()),
        }
    }
    let _ = fs::remove_dir(dir.join("mods"));
    for (root, id, key) in cleanup.mods {
        inventory::remove_installed(config, &root, &key)?;
        remove_transaction(config, &root, &id)?;
    }
    fs::remove_file(journal).map_err(|_| "fileWriteError".into())
}
