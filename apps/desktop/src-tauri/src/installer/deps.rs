use std::{
    cmp::Ordering,
    collections::{BTreeMap, HashMap, HashSet},
    path::{Path, PathBuf},
};

use super::{
    TransactionRecord, TransactionStatus, get_transaction, install_from_zip,
    runner::{GameLockCheck, ProcessRunner},
    set_mods_enabled,
    state::read_disabled_set,
    transaction::{read_transactions, save_transaction},
    uninstall_mod, update,
};
use crate::{
    catalog::{ModEntry, compare_numeric_versions},
    game,
};

fn find_entry<'a>(id: &str, all_mods: &'a [ModEntry]) -> Option<&'a ModEntry> {
    all_mods.iter().find(|item| item.id == id)
}

fn satisfies_min_version(installed: &str, min_version: Option<&str>) -> bool {
    let Some(min_v) = min_version else {
        return true;
    };
    matches!(
        compare_numeric_versions(installed, min_v),
        Some(Ordering::Greater | Ordering::Equal)
    )
}

/// Resolves the topological install order for `target_id` (prerequisites first, target last).
pub fn resolve_install_order(
    target_id: &str,
    all_mods: &[ModEntry],
) -> Result<Vec<ModEntry>, String> {
    let mut state: HashMap<String, u8> = HashMap::new();
    let mut order: Vec<ModEntry> = Vec::new();

    fn visit(
        id: &str,
        min_version: Option<&str>,
        all_mods: &[ModEntry],
        state: &mut HashMap<String, u8>,
        order: &mut Vec<ModEntry>,
    ) -> Result<(), String> {
        let entry = find_entry(id, all_mods).ok_or_else(|| format!("dependencyMissing: {id}"))?;
        if let Some(min_v) = min_version {
            let Some(avail) = entry.version.as_deref() else {
                return Err(format!("dependencyVersion: {id}"));
            };
            if !satisfies_min_version(avail, Some(min_v)) {
                return Err(format!("dependencyVersion: {id}"));
            }
        }
        match state.get(id).copied() {
            Some(1) => return Err("dependencyCycle".into()),
            Some(2) => return Ok(()),
            _ => {}
        }
        state.insert(id.to_owned(), 1);
        for req in &entry.requires {
            visit(&req.id, req.min_version.as_deref(), all_mods, state, order)?;
        }
        state.insert(id.to_owned(), 2);
        order.push(entry.clone());
        Ok(())
    }

    visit(target_id, None, all_mods, &mut state, &mut order)?;
    Ok(order)
}

/// Rejects disabling any mod that is still required by another installed, enabled mod.
pub fn check_disable_allowed(
    config_dir: &Path,
    game_root: &Path,
    mod_ids: &[String],
    all_mods: &[ModEntry],
) -> Result<(), String> {
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let txs = read_transactions(config_dir)?;
    let Some(copy_txs) = txs.get(game_root) else {
        return Ok(());
    };
    let disabled = read_disabled_set(&pck_dir)?;
    let disabling: HashSet<&str> = mod_ids.iter().map(String::as_str).collect();
    let mut dependents = Vec::new();
    for (id, tx) in copy_txs {
        if tx.status != TransactionStatus::Committed
            || disabling.contains(id.as_str())
            || disabled.contains(id)
        {
            continue;
        }
        if let Some(entry) = find_entry(id, all_mods)
            && entry
                .requires
                .iter()
                .any(|req| disabling.contains(req.id.as_str()))
        {
            dependents.push(id.clone());
        }
    }
    if !dependents.is_empty() {
        dependents.sort();
        return Err(format!("dependencyRequiredBy: {}", dependents.join(", ")));
    }
    Ok(())
}

/// Rejects uninstalling a mod while another installed mod still declares it in `requires`.
pub fn check_uninstall_allowed(
    config_dir: &Path,
    game_root: &Path,
    mod_id: &str,
    all_mods: &[ModEntry],
) -> Result<(), String> {
    let txs = read_transactions(config_dir)?;
    let Some(copy_txs) = txs.get(game_root) else {
        return Ok(());
    };
    let mut dependents = Vec::new();
    for (id, tx) in copy_txs {
        if id == mod_id || tx.status != TransactionStatus::Committed {
            continue;
        }
        if let Some(entry) = find_entry(id, all_mods)
            && entry.requires.iter().any(|req| req.id == mod_id)
        {
            dependents.push(id.clone());
        }
    }
    if !dependents.is_empty() {
        dependents.sort();
        return Err(format!("dependencyRequiredBy: {}", dependents.join(", ")));
    }
    Ok(())
}

fn required_min_version<'a>(dep_id: &str, chain: &'a [ModEntry]) -> Option<&'a str> {
    let mut best: Option<&'a str> = None;
    for item in chain {
        for req in &item.requires {
            if req.id == dep_id
                && let Some(min_v) = req.min_version.as_deref()
            {
                let replace = match best {
                    None => true,
                    Some(prev) => matches!(
                        compare_numeric_versions(min_v, prev),
                        Some(Ordering::Greater)
                    ),
                };
                if replace {
                    best = Some(min_v);
                }
            }
        }
    }
    best
}

/// Rolls back newly auto-installed dependency mods in reverse installation order.
pub fn rollback_dependencies(
    config_dir: &Path,
    game_root: &Path,
    auto_installed: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) {
    for dep in auto_installed.iter().rev() {
        let _ = uninstall_mod(config_dir, game_root, dep, runner, lock_check);
    }
}

/// Installs or upgrades missing/outdated prerequisites for `target_entry`, returning
/// `(newly_auto_installed_entries, all_dependency_records)` and rolling back on failure.
#[allow(clippy::too_many_arguments)]
pub fn ensure_dependencies_installed(
    config_dir: &Path,
    game_root: &Path,
    target_entry: &ModEntry,
    zip_paths: &BTreeMap<String, PathBuf>,
    staging_root: &Path,
    all_mods: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<(Vec<ModEntry>, Vec<TransactionRecord>), String> {
    let pck_dir = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    let order = resolve_install_order(&target_entry.id, all_mods)?;
    let mut newly_auto_installed: Vec<ModEntry> = Vec::new();
    let mut records: Vec<TransactionRecord> = Vec::new();

    for dep in order.iter().take(order.len().saturating_sub(1)) {
        let min_v = required_min_version(&dep.id, &order);
        let existing = get_transaction(config_dir, game_root, &dep.id)?;
        if let Some(tx) = existing
            && tx.status == TransactionStatus::Committed
        {
            if !satisfies_min_version(&tx.version, min_v) {
                let Some(dep_zip) = zip_paths.get(&dep.id) else {
                    rollback_dependencies(
                        config_dir,
                        game_root,
                        &newly_auto_installed,
                        runner,
                        lock_check,
                    );
                    return Err("downloadFirst".into());
                };
                if let Err(err) = update::apply(
                    config_dir,
                    game_root,
                    &pck_dir,
                    dep_zip,
                    dep,
                    &tx.version,
                    all_mods,
                    lock_check,
                ) {
                    rollback_dependencies(
                        config_dir,
                        game_root,
                        &newly_auto_installed,
                        runner,
                        lock_check,
                    );
                    return Err(err);
                }
            }
            let disabled = read_disabled_set(&pck_dir)?;
            if disabled.contains(&dep.id)
                && let Err(err) =
                    set_mods_enabled(game_root, std::slice::from_ref(&dep.id), true, lock_check)
            {
                rollback_dependencies(
                    config_dir,
                    game_root,
                    &newly_auto_installed,
                    runner,
                    lock_check,
                );
                return Err(err);
            }
            if let Some(updated_tx) = get_transaction(config_dir, game_root, &dep.id)? {
                records.push(updated_tx);
            }
            continue;
        }

        let Some(dep_zip) = zip_paths.get(&dep.id) else {
            rollback_dependencies(
                config_dir,
                game_root,
                &newly_auto_installed,
                runner,
                lock_check,
            );
            return Err("downloadFirst".into());
        };
        let mut dep_tx = match install_from_zip(
            config_dir,
            game_root,
            dep_zip,
            &staging_root.join(&dep.id),
            dep,
            all_mods,
            runner,
            lock_check,
        ) {
            Ok(tx) => tx,
            Err(err) => {
                rollback_dependencies(
                    config_dir,
                    game_root,
                    &newly_auto_installed,
                    runner,
                    lock_check,
                );
                return Err(err);
            }
        };
        dep_tx.auto_installed = true;
        save_transaction(config_dir, game_root, dep_tx.clone())?;
        newly_auto_installed.push(dep.clone());
        records.push(dep_tx);
    }

    Ok((newly_auto_installed, records))
}

/// Installs `target_entry` after installing or upgrading any missing/outdated prerequisites,
/// rolling back newly auto-installed prerequisites on failure.
#[allow(clippy::too_many_arguments)]
pub fn install_with_dependencies(
    config_dir: &Path,
    game_root: &Path,
    target_entry: &ModEntry,
    zip_paths: &BTreeMap<String, PathBuf>,
    staging_root: &Path,
    all_mods: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<Vec<TransactionRecord>, String> {
    let (newly_auto_installed, mut records) = ensure_dependencies_installed(
        config_dir,
        game_root,
        target_entry,
        zip_paths,
        staging_root,
        all_mods,
        runner,
        lock_check,
    )?;

    let Some(target_zip) = zip_paths.get(&target_entry.id) else {
        rollback_dependencies(
            config_dir,
            game_root,
            &newly_auto_installed,
            runner,
            lock_check,
        );
        return Err("downloadFirst".into());
    };
    let target_tx = match install_from_zip(
        config_dir,
        game_root,
        target_zip,
        &staging_root.join(&target_entry.id),
        target_entry,
        all_mods,
        runner,
        lock_check,
    ) {
        Ok(tx) => tx,
        Err(err) => {
            rollback_dependencies(
                config_dir,
                game_root,
                &newly_auto_installed,
                runner,
                lock_check,
            );
            return Err(err);
        }
    };
    records.push(target_tx);
    Ok(records)
}

/// Uninstalls `mod_entry` and cleans up any unreferenced `auto_installed` dependencies.
pub fn uninstall_with_auto_cleanup(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    all_mods: &[ModEntry],
    runner: &dyn ProcessRunner,
    lock_check: &dyn GameLockCheck,
) -> Result<Vec<String>, String> {
    check_uninstall_allowed(config_dir, game_root, &mod_entry.id, all_mods)?;
    uninstall_mod(config_dir, game_root, mod_entry, runner, lock_check)?;
    let mut removed = vec![mod_entry.id.clone()];

    loop {
        let txs = read_transactions(config_dir)?;
        let Some(copy_txs) = txs.get(game_root) else {
            break;
        };
        let orphan_id = copy_txs
            .iter()
            .filter(|(_, tx)| tx.status == TransactionStatus::Committed && tx.auto_installed)
            .find(|(cand_id, _)| {
                !copy_txs.iter().any(|(other_id, other_tx)| {
                    other_id != *cand_id
                        && other_tx.status == TransactionStatus::Committed
                        && find_entry(other_id, all_mods)
                            .is_some_and(|e| e.requires.iter().any(|r| r.id == **cand_id))
                })
            })
            .map(|(id, _)| id.clone());

        let Some(id) = orphan_id else {
            break;
        };
        let Some(dep_entry) = find_entry(&id, all_mods) else {
            break;
        };
        uninstall_mod(config_dir, game_root, dep_entry, runner, lock_check)?;
        removed.push(id);
    }

    Ok(removed)
}
