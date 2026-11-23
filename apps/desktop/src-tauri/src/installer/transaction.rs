use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{self, BufReader, Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::UNIX_EPOCH,
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::update;
use crate::{catalog::ModEntry, inventory};

pub(super) const TRANSACTIONS_FILE: &str = "transactions.json";
const BACKUPS_DIR: &str = "backups";
const SMALL_FILE_HASH_LIMIT: u64 = 64 * 1024 * 1024;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Mod state reported by parsing upstream CLI `--status` output.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DiskModState {
    Vanilla,
    Installed,
    OlderVersion,
    Unrecognized(String),
}

/// Size and lowercase SHA-256 fingerprint of a file on disk.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct FileFingerprint {
    pub size: u64,
    pub sha256: String,
}

/// Lifecycle state of a recorded mod install transaction.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TransactionStatus {
    Pending,
    Committed,
    RolledBack,
    NeedsRepair,
}

/// Per-mod transaction record stored in `transactions.json`.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct TransactionRecord {
    pub mod_id: String,
    pub repo: String,
    pub version: String,
    pub exclusive: String,
    pub pck_dir: PathBuf,
    pub status: TransactionStatus,
    pub pre_pck: FileFingerprint,
    pub post_pck: Option<FileFingerprint>,
    pub upstream_uninstall: bool,
    pub backup_dir: PathBuf,
    pub touched_files: Vec<String>,
    #[serde(default)]
    pub owned_files: BTreeMap<String, FileFingerprint>,
    #[serde(default)]
    pub failure: Option<String>,
    #[serde(default)]
    pub source_sha256: Option<String>,
    #[serde(default)]
    pub preparation_rule: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) restoring_pck: Option<FileFingerprint>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub auto_installed: bool,
}

pub(super) type Transactions = BTreeMap<PathBuf, BTreeMap<String, TransactionRecord>>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum EntryDigest {
    Dir,
    Hashed(u64, String),
    StatOnly(u64, u128),
}

pub(super) type DirSnapshot = BTreeMap<String, EntryDigest>;

pub(super) fn unique_suffix() -> String {
    let seq = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{}-{seq}", std::process::id())
}

pub(crate) fn is_safe_filename(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && !name.contains("..")
        && !name.contains('/')
        && !name.contains('\\')
        && !name.contains('\0')
}

pub(crate) fn is_hex_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit())
}

pub(super) fn short_hash(path: &Path) -> String {
    let digest = Sha256::digest(path.to_string_lossy().as_bytes());
    hex::encode(&digest[..8])
}

pub(super) fn backup_dir_for(config_dir: &Path, game_root: &Path, mod_id: &str) -> PathBuf {
    config_dir
        .join(BACKUPS_DIR)
        .join(short_hash(game_root))
        .join(mod_id)
}

#[cfg(test)]
thread_local! {
    pub(super) static PCK_READS: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// Computes byte size and lowercase SHA-256 digest by streaming the file.
pub fn file_fingerprint(path: &Path) -> Result<FileFingerprint, String> {
    #[cfg(test)]
    if path.file_name() == Some(std::ffi::OsStr::new("Machine Party.pck")) {
        PCK_READS.with(|count| count.set(count.get() + 1));
    }
    let file = File::open(path).map_err(|_| "fileReadError".to_string())?;
    let mut reader = BufReader::with_capacity(64 * 1024, file);
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    let mut total = 0u64;
    loop {
        let read = reader
            .read(&mut buf)
            .map_err(|_| "fileReadError".to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
        total += read as u64;
    }
    Ok(FileFingerprint {
        size: total,
        sha256: hex::encode(hasher.finalize()),
    })
}

pub(crate) fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|_| "fileWriteError".to_string())?;
    }
    let temp = path.with_file_name(format!(
        "{}.tmp-{}",
        path.file_name().and_then(|s| s.to_str()).unwrap_or("file"),
        unique_suffix()
    ));
    let mut file = File::create(&temp).map_err(|_| "fileWriteError".to_string())?;
    if file.write_all(bytes).is_err() || file.sync_all().is_err() {
        let _ = fs::remove_file(&temp);
        return Err("fileWriteError".into());
    }
    drop(file);
    fs::rename(&temp, path).map_err(|_| {
        let _ = fs::remove_file(&temp);
        "fileWriteError".into()
    })
}

pub(crate) fn copy_atomic(src: &Path, dst: &Path) -> Result<(), String> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent).map_err(|_| "fileWriteError".to_string())?;
    }
    let temp = dst.with_file_name(format!(
        "{}.tmp-{}",
        dst.file_name().and_then(|s| s.to_str()).unwrap_or("copy"),
        unique_suffix()
    ));
    let copy_result = (|| -> io::Result<()> {
        let mut reader = BufReader::with_capacity(64 * 1024, File::open(src)?);
        let mut writer = File::create(&temp)?;
        io::copy(&mut reader, &mut writer)?;
        writer.sync_all()?;
        Ok(())
    })();
    if copy_result.is_err() {
        let _ = fs::remove_file(&temp);
        return Err("fileWriteError".into());
    }
    fs::rename(&temp, dst).map_err(|_| {
        let _ = fs::remove_file(&temp);
        "fileWriteError".into()
    })
}

pub(super) fn read_transactions(config_dir: &Path) -> Result<Transactions, String> {
    let bytes = match fs::read(config_dir.join(TRANSACTIONS_FILE)) {
        Ok(bytes) => bytes,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(Transactions::new()),
        Err(_) => return Err("inventoryError".into()),
    };
    serde_json::from_slice(&bytes).map_err(|_| "inventoryError".into())
}

fn write_transactions(config_dir: &Path, txs: &Transactions) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(txs).map_err(|_| "inventoryError".to_string())?;
    write_atomic(&config_dir.join(TRANSACTIONS_FILE), &bytes)
}

pub(super) fn save_transaction(
    config_dir: &Path,
    game_root: &Path,
    record: TransactionRecord,
) -> Result<(), String> {
    let mut txs = read_transactions(config_dir)?;
    txs.entry(game_root.to_path_buf())
        .or_default()
        .insert(record.mod_id.clone(), record);
    write_transactions(config_dir, &txs)
}

pub(super) fn remove_transaction(
    config_dir: &Path,
    game_root: &Path,
    mod_id: &str,
) -> Result<(), String> {
    let mut txs = read_transactions(config_dir)?;
    let Some(per_copy) = txs.get_mut(game_root) else {
        return Ok(());
    };
    if per_copy.remove(mod_id).is_none() {
        return Ok(());
    }
    if per_copy.is_empty() {
        txs.remove(game_root);
    }
    write_transactions(config_dir, &txs)
}

pub(crate) fn get_transaction(
    config_dir: &Path,
    game_root: &Path,
    mod_id: &str,
) -> Result<Option<TransactionRecord>, String> {
    let txs = read_transactions(config_dir)?;
    Ok(txs
        .get(game_root)
        .and_then(|per_copy| per_copy.get(mod_id))
        .cloned())
}

pub(super) fn snapshot_dir(dir: &Path, large_name: &str) -> Result<DirSnapshot, String> {
    let mut map = DirSnapshot::new();
    let entries = fs::read_dir(dir).map_err(|_| "fileReadError".to_string())?;
    for item in entries {
        let item = item.map_err(|_| "fileReadError".to_string())?;
        let name = item.file_name().to_string_lossy().into_owned();
        let meta = item.metadata().map_err(|_| "fileReadError".to_string())?;
        let digest = if meta.is_dir() {
            EntryDigest::Dir
        } else if name != large_name && meta.len() <= SMALL_FILE_HASH_LIMIT {
            EntryDigest::Hashed(meta.len(), file_fingerprint(&item.path())?.sha256)
        } else {
            let mtime = meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map_or(0, |d| d.as_nanos());
            EntryDigest::StatOnly(meta.len(), mtime)
        };
        map.insert(name, digest);
    }
    Ok(map)
}

pub(super) fn verify_only_touches(
    before: &DirSnapshot,
    after: &DirSnapshot,
    touches: &[String],
) -> Result<(), String> {
    for (name, digest) in after {
        if touches.iter().any(|t| t == name) {
            continue;
        }
        if before.get(name) != Some(digest) {
            return Err("undeclaredFileModified".into());
        }
    }
    for (name, digest) in before {
        if touches.iter().any(|t| t == name) {
            continue;
        }
        if after.get(name) != Some(digest) {
            return Err("undeclaredFileModified".into());
        }
    }
    Ok(())
}

fn collect_dir_fingerprints_into(
    base: &Path,
    dir: &Path,
    out: &mut BTreeMap<String, FileFingerprint>,
) -> Result<(), String> {
    let entries = fs::read_dir(dir).map_err(|_| "fileReadError".to_string())?;
    for item in entries {
        let item = item.map_err(|_| "fileReadError".to_string())?;
        let path = item.path();
        let meta = fs::symlink_metadata(&path).map_err(|_| "fileReadError")?;
        if update::redirected(&meta) || !(meta.is_file() || meta.is_dir()) {
            return Err(format!(
                "gameUpdatedOrModified: {}",
                path.strip_prefix(base).unwrap_or(&path).display()
            ));
        }
        if meta.is_dir() {
            collect_dir_fingerprints_into(base, &path, out)?;
        } else {
            let rel = path
                .strip_prefix(base)
                .map_err(|_| "fileReadError".to_string())?
                .to_string_lossy()
                .replace('\\', "/");
            out.insert(rel, file_fingerprint(&path)?);
        }
    }
    Ok(())
}

pub(super) fn collect_dir_fingerprints(
    dir: &Path,
) -> Result<BTreeMap<String, FileFingerprint>, String> {
    let mut out = BTreeMap::new();
    collect_dir_fingerprints_into(dir, dir, &mut out)?;
    Ok(out)
}

pub(super) fn collect_dir_paths(dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = fs::read_dir(dir).map_err(|_| "fileReadError".to_string())?;
    for item in entries {
        let item = item.map_err(|_| "fileReadError".to_string())?;
        let path = item.path();
        let file_type = item.file_type().map_err(|_| "fileReadError".to_string())?;
        if file_type.is_symlink() {
            return Err("fileReadError".into());
        }
        out.push(path.clone());
        if file_type.is_dir() {
            collect_dir_paths(&path, out)?;
        }
    }
    Ok(())
}

pub(super) fn clear_mod_records(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    backup_dir: Option<&Path>,
) -> Result<(), String> {
    inventory::remove_installed(config_dir, game_root, mod_entry.inventory_key())?;
    remove_transaction(config_dir, game_root, &mod_entry.id)?;
    if let Some(dir) = backup_dir {
        let _ = fs::remove_dir_all(dir);
    }
    Ok(())
}

pub(crate) fn check_space(dir: &Path, required: u64) -> Result<(), String> {
    if fs2::available_space(dir).map_err(|_| "fileReadError")? < required {
        return Err(format!("{}: {}", "diskSpace", dir.display()));
    }
    Ok(())
}
