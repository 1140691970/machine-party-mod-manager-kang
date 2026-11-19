// A committed transaction selects the winner after a restart. Both directories stay
// on the game volume, outside the loader's search path except for the active copy.
use super::*;

#[derive(Deserialize, Serialize)]
struct Journal {
    workspace: String,
    pck: FileFingerprint,
    before: TransactionRecord,
    after: TransactionRecord,
}

fn journal_path(config: &Path, game: &Path, id: &str) -> PathBuf {
    backup_dir_for(config, game, id).join("update.json")
}

fn directory(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.is_dir() && !redirected(&meta) => Ok(true),
        Ok(_) => Err("gameUpdatedOrModified".into()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err("fileReadError".into()),
    }
}

pub(super) fn redirected(meta: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        meta.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    meta.is_symlink()
}

pub(super) fn verify_files(
    dir: &Path,
    files: &BTreeMap<String, FileFingerprint>,
) -> Result<(), String> {
    if !directory(dir)? {
        return Err("gameUpdatedOrModified".into());
    }
    let disk = collect_dir_fingerprints(dir)?;
    if let Some(name) = disk
        .keys()
        .chain(files.keys())
        .find(|name| disk.get(*name) != files.get(*name))
    {
        return Err(format!("gameUpdatedOrModified: {name}"));
    }
    Ok(())
}

fn move_dir(from: &Path, to: &Path) -> Result<(), String> {
    if directory(to)? {
        return Err("restoreResidue".into());
    }
    fs::rename(from, to).map_err(|_| "fileWriteError".into())
}

impl Journal {
    fn finish(
        &self,
        config: &Path,
        game: &Path,
        item: &ModEntry,
        lock: &dyn GameLockCheck,
    ) -> Result<(), String> {
        let dir = game::resolve_pck_dir(game).ok_or("invalidGame")?;
        let backup = backup_dir_for(config, game, &item.id);
        if !self
            .workspace
            .strip_prefix(".mpm-update-")
            .is_some_and(|s| !s.is_empty() && s.bytes().all(|c| c.is_ascii_alphanumeric()))
            || [&self.before, &self.after].iter().any(|tx| {
                tx.mod_id != item.id
                    || tx.pck_dir != dir
                    || tx.backup_dir != backup
                    || tx.exclusive != "loader"
                    || tx.owned_files.is_empty()
            })
        {
            return Err("restoreCorrupt".into());
        }
        let work = dir.join(&self.workspace);
        let live = loader_mod_dir(&dir, item);
        let old = work.join("previous");
        let next = work.join("next");
        let pck = dir.join("Machine Party.pck");
        lock.ensure_unlocked(&dir, &pck)?;
        if !directory(&dir.join("mods"))? || file_fingerprint(&pck)? != self.pck {
            return Err("gameUpdatedOrModified".into());
        }
        let tx = get_transaction(config, game, &item.id)?.ok_or("missingTransaction")?;
        let committed = tx == self.after;
        if !committed && tx != self.before {
            return Err("restoreCorrupt".into());
        }
        let work_present = directory(&work)?;
        if !committed && work_present && directory(&old)? {
            verify_files(&old, &self.before.owned_files)?;
            if directory(&live)? {
                verify_files(&live, &self.after.owned_files)?;
                lock.ensure_unlocked(&dir, &pck)?;
                move_dir(&live, &next)?;
            }
            lock.ensure_unlocked(&dir, &pck)?;
            move_dir(&old, &live)?;
        }
        verify_files(&live, &tx.owned_files)?;
        inventory::record_installed(config, game, item.inventory_key(), &tx.version)?;
        if work_present {
            // Only retire recognized files. A partially cleaned directory can be retried.
            for (path, expected) in [
                (&next, &self.after.owned_files),
                (&old, &self.before.owned_files),
            ] {
                if directory(path)? {
                    let disk = collect_dir_fingerprints(path)?;
                    if !disk.iter().all(|(k, v)| expected.get(k) == Some(v)) {
                        return Err("restoreResidue".into());
                    }
                    fs::remove_dir_all(path).map_err(|_| "fileWriteError")?;
                }
            }
            fs::remove_dir(&work).map_err(|_| "restoreResidue")?;
        }
        fs::remove_file(journal_path(config, game, &item.id)).map_err(|_| "fileWriteError".into())
    }
}

pub fn recover(
    config: &Path,
    game: &Path,
    mods: &[ModEntry],
    lock: &dyn GameLockCheck,
) -> Result<(), String> {
    for item in mods {
        let bytes = match fs::read(journal_path(config, game, &item.id)) {
            Ok(v) => v,
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(_) => return Err("fileReadError".into()),
        };
        let journal: Journal = serde_json::from_slice(&bytes).map_err(|_| "restoreCorrupt")?;
        journal.finish(config, game, item, lock)?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn apply(
    config: &Path,
    game: &Path,
    expected_dir: &Path,
    zip: &Path,
    item: &ModEntry,
    from: &str,
    mods: &[ModEntry],
    lock: &dyn GameLockCheck,
) -> Result<(), String> {
    let dir = game::resolve_pck_dir(game).ok_or("invalidGame")?;
    if dir != expected_dir {
        return Err("statusUnavailable".into());
    }
    recover(config, game, mods, lock)?;
    let adapter = item.adapter.as_ref().ok_or("unsupportedAdapter")?;
    let pkg = item.package.as_ref().ok_or("missingPackage")?;
    let version = item.version.as_deref().ok_or("missingPackage")?;
    let before = get_transaction(config, game, &item.id)?.ok_or("missingTransaction")?;
    if adapter.kind != "loader-files"
        || before.exclusive != "loader"
        || before.status != TransactionStatus::Committed
        || before.mod_id != item.id
        || before.pck_dir != dir
        || before.backup_dir != backup_dir_for(config, game, &item.id)
        || (before.repo != item.repo && !item.legacy_inventory_repos.contains(&before.repo))
        || before.version != from
        || !crate::catalog::newer(version, from)
        || before.owned_files.is_empty()
    {
        return Err("statusUnavailable".into());
    }
    let pck = dir.join(&adapter.baseline.file);
    let live = loader_mod_dir(&dir, item);
    lock.ensure_unlocked(&dir, &pck)?;
    if !directory(&dir.join("mods"))? {
        return Err("statusUnavailable".into());
    }
    verify_files(&live, &before.owned_files)?;
    let scan = validate_game_mods(config, game, mods)?;
    if scan.mod_states.get(&item.id).map(String::as_str) != Some("installed") {
        return Err("gameUpdatedOrModified".into());
    }
    let current = FileFingerprint {
        size: scan.pck_size,
        sha256: scan.pck_sha256,
    };
    let supported = match pck_loader::read_managed_marker(&dir)? {
        Some(marker) => {
            marker.vanilla_size == adapter.baseline.size
                && marker
                    .vanilla_sha256
                    .eq_ignore_ascii_case(&adapter.baseline.sha256)
        }
        None => {
            (current.size == adapter.baseline.size
                && current
                    .sha256
                    .eq_ignore_ascii_case(&adapter.baseline.sha256))
                || (pck_loader::external_loader_present(&dir)?
                    && before.post_pck.as_ref() == Some(&current))
        }
    };
    if !supported {
        return Err("gameUpdatedOrModified".into());
    }
    check_space(&dir, pkg.size)?;
    let work = tempfile::Builder::new()
        .prefix(".mpm-update-")
        .tempdir_in(&dir)
        .map_err(|_| "fileWriteError")?;
    let next = work.path().join("next");
    stage_package(zip, &next, pkg, adapter, &dir, &SystemRunner)?;
    let manifest = |path: &Path| -> Result<serde_json::Value, String> {
        serde_json::from_slice(&fs::read(path.join("mod.json")).map_err(|_| "fileReadError")?)
            .map_err(|_| "packageCorrupt".into())
    };
    let target = manifest(&next)?;
    if target["id"] != manifest(&live)?["id"]
        || target["version"].as_str().is_none_or(|v| {
            crate::catalog::numeric_version(v)
                .zip(crate::catalog::numeric_version(version))
                .is_none_or(|(a, b)| a != b)
        })
    {
        return Err("packageCorrupt".into());
    }
    let after = TransactionRecord {
        version: version.to_owned(),
        repo: item.repo.clone(),
        owned_files: collect_dir_fingerprints(&next)?,
        preparation_rule: Some(
            adapter
                .source_rule
                .clone()
                .unwrap_or_else(|| "native-v1".into()),
        ),
        source_sha256: Some(pkg.sha256.clone()),
        ..before.clone()
    };
    let journal = Journal {
        workspace: work
            .path()
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned(),
        pck: current,
        before,
        after,
    };
    let path = journal_path(config, game, &item.id);
    verify_files(&live, &journal.before.owned_files)?;
    if file_fingerprint(&pck)? != journal.pck {
        return Err("gameUpdatedOrModified".into());
    }
    lock.ensure_unlocked(&dir, &pck)?;
    write_atomic(
        &path,
        &serde_json::to_vec(&journal).map_err(|_| "inventoryError")?,
    )?;
    let work = work.keep();
    let result = (|| {
        move_dir(&live, &work.join("previous"))?;
        verify_files(&work.join("previous"), &journal.before.owned_files)?;
        lock.ensure_unlocked(&dir, &pck)?;
        move_dir(&next, &live)?;
        verify_files(&live, &journal.after.owned_files)?;
        if file_fingerprint(&pck)? != journal.pck {
            return Err("gameUpdatedOrModified".to_owned());
        }
        lock.ensure_unlocked(&dir, &pck)?;
        // Commit point: before this write recovery restores the previous directory.
        inventory::record_installed(config, game, item.inventory_key(), version)?;
        save_transaction(config, game, journal.after.clone())
    })();
    if let Err(error) = result {
        journal.finish(config, game, item, lock)?;
        return Err(error);
    }
    // The transaction is committed. A locked file can defer cleanup until the next scan.
    let _ = journal.finish(config, game, item, lock);
    Ok(())
}
