use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{self, BufReader, Cursor, Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicU64, Ordering},
    time::UNIX_EPOCH,
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(windows)]
use std::os::windows::{fs::OpenOptionsExt, process::CommandExt};

use flate2::read::DeflateDecoder;
use regex::Regex;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    catalog::{AdapterProfile, ModEntry, PackageSpec},
    game, inventory,
};

const TRANSACTIONS_FILE: &str = "transactions.json";
const BACKUPS_DIR: &str = "backups";
const RESTORE_DAT: &str = "overtime_restore.dat";
const MP8R_MAGIC: u32 = 0x3852_504D;
const MAX_RESTORE_BYTES: u64 = 512 * 1024;
const MAX_ZIP_ENTRY_BYTES: u64 = 256 * 1024 * 1024;
const SMALL_FILE_HASH_LIMIT: u64 = 64 * 1024 * 1024;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Request passed to an external process runner.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandRequest {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
}

/// Captured output from an external command execution.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandOutput {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Abstracts subprocess invocation for L1 unit simulation vs. L2/production execution.
pub trait ProcessRunner {
    fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String>;
}

/// Real OS subprocess runner with stdin closed to prevent interactive hangs.
pub struct SystemRunner;

#[cfg(not(windows))]
fn is_pe_executable(path: &Path) -> bool {
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let mut magic = [0u8; 2];
    file.read_exact(&mut magic).is_ok() && magic == *b"MZ"
}

impl ProcessRunner for SystemRunner {
    fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String> {
        #[cfg(not(windows))]
        let mut cmd = if is_pe_executable(&req.program) {
            let mut mono = Command::new("mono");
            mono.arg(&req.program);
            mono
        } else {
            Command::new(&req.program)
        };
        #[cfg(windows)]
        let mut cmd = Command::new(&req.program);
        #[cfg(windows)]
        cmd.creation_flags(0x08000000);

        let output = cmd
            .args(&req.args)
            .current_dir(&req.cwd)
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("processSpawnFailed: {e}"))?;
        Ok(CommandOutput {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

/// Checks whether the target game copy is currently locked or running.
pub trait GameLockCheck {
    fn ensure_unlocked(&self, pck_dir: &Path, pck_path: &Path) -> Result<(), String>;
}

/// OS-level lock and writability check for the target PCK file.
pub struct SystemGameLockCheck;

impl GameLockCheck for SystemGameLockCheck {
    fn ensure_unlocked(&self, _pck_dir: &Path, pck_path: &Path) -> Result<(), String> {
        if !pck_path.is_file() {
            return Err("invalidGame".into());
        }
        let mut opts = OpenOptions::new();
        opts.read(true).write(true);
        #[cfg(windows)]
        {
            use sysinfo::{ProcessRefreshKind, RefreshKind, System, UpdateKind};
            let exe = _pck_dir.join("Machine Party.exe");
            let target = file_id::get_file_id(&exe).map_err(|_| "invalidGame")?;
            let system = System::new_with_specifics(
                RefreshKind::nothing()
                    .with_processes(ProcessRefreshKind::nothing().with_exe(UpdateKind::Always)),
            );
            for proc in system.processes().values().filter(|p| {
                p.name()
                    .eq_ignore_ascii_case(std::ffi::OsStr::new("Machine Party.exe"))
            }) {
                let Some(path) = proc.exe() else {
                    return Err("gameRunning".into());
                };
                if !matches!(file_id::get_file_id(path), Ok(id) if id != target) {
                    return Err("gameRunning".into());
                }
            }
            opts.share_mode(0);
        }
        match opts.open(pck_path) {
            Ok(_) => Ok(()),
            Err(err) if err.kind() == io::ErrorKind::PermissionDenied => {
                Err("gamePermissionDenied".into())
            }
            Err(_) => Err("gameRunning".into()),
        }
    }
}

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
    pub failure: Option<String>,
}

type Transactions = BTreeMap<PathBuf, BTreeMap<String, TransactionRecord>>;

/// Parsed header of an `overtime_restore.dat` (`MP8R`) delta restore record.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RestoreHeader {
    pub format: u32,
    pub orig_len: i64,
    pub patched_len: i64,
    pub base_sha: String,
    pub game_ver: String,
    pub mod_tag: String,
    pub entry_count: i32,
}

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

#[derive(Clone, Debug, PartialEq, Eq)]
enum EntryDigest {
    Dir,
    Hashed(u64, String),
    StatOnly(u64, u128),
}

type DirSnapshot = BTreeMap<String, EntryDigest>;

fn unique_suffix() -> String {
    let seq = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{}-{seq}", std::process::id())
}

fn is_safe_filename(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && !name.contains("..")
        && !name.contains('/')
        && !name.contains('\\')
        && !name.contains('\0')
}

fn is_hex_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit())
}

fn short_hash(path: &Path) -> String {
    let digest = Sha256::digest(path.to_string_lossy().as_bytes());
    hex::encode(&digest[..8])
}

fn backup_dir_for(config_dir: &Path, game_root: &Path, mod_id: &str) -> PathBuf {
    config_dir
        .join(BACKUPS_DIR)
        .join(short_hash(game_root))
        .join(mod_id)
}

#[cfg(test)]
thread_local! {
    static PCK_READS: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
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

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
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

fn copy_atomic(src: &Path, dst: &Path) -> Result<(), String> {
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

fn read_transactions(config_dir: &Path) -> Result<Transactions, String> {
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

fn save_transaction(
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

fn remove_transaction(config_dir: &Path, game_root: &Path, mod_id: &str) -> Result<(), String> {
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

fn get_transaction(
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

fn snapshot_dir(dir: &Path, large_name: &str) -> Result<DirSnapshot, String> {
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

fn verify_only_touches(
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

fn safe_zip_rel_path(raw: &str) -> Result<Option<PathBuf>, String> {
    let normalized = raw.replace('\\', "/");
    if normalized.is_empty() || normalized.ends_with('/') {
        let trimmed = normalized.trim_end_matches('/');
        if !trimmed.is_empty() {
            validate_rel_components(trimmed)?;
        }
        return Ok(None);
    }
    Ok(Some(validate_rel_components(&normalized)?))
}

fn validate_rel_components(normalized: &str) -> Result<PathBuf, String> {
    if normalized.starts_with('/') || normalized.contains(':') || normalized.contains('\0') {
        return Err("packageCorrupt".into());
    }
    let mut rel = PathBuf::new();
    for part in normalized.split('/') {
        if part.is_empty() || part == "." || part == ".." {
            return Err("packageCorrupt".into());
        }
        let mut comps = Path::new(part).components();
        match (comps.next(), comps.next()) {
            (Some(Component::Normal(seg)), None) => rel.push(seg),
            _ => return Err("packageCorrupt".into()),
        }
    }
    if rel.as_os_str().is_empty() {
        return Err("packageCorrupt".into());
    }
    Ok(rel)
}

fn le_u16(bytes: &[u8], offset: usize) -> Result<u16, String> {
    let slice = bytes.get(offset..offset + 2).ok_or("packageCorrupt")?;
    Ok(u16::from_le_bytes([slice[0], slice[1]]))
}

fn le_u32(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let slice = bytes.get(offset..offset + 4).ok_or("packageCorrupt")?;
    Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

/// Safely extracts a ZIP archive (Stored and Deflate) with CRC-32 and zip-slip checks.
pub fn extract_zip(zip_path: &Path, dest_dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut file = File::open(zip_path).map_err(|_| "packageCorrupt".to_string())?;
    let total_len = file
        .metadata()
        .map_err(|_| "packageCorrupt".to_string())?
        .len();
    if total_len < 22 {
        return Err("packageCorrupt".into());
    }
    let tail_start = total_len.saturating_sub(65_536 + 22);
    let tail_len = (total_len - tail_start) as usize;
    file.seek(SeekFrom::Start(tail_start))
        .map_err(|_| "packageCorrupt".to_string())?;
    let mut tail = vec![0u8; tail_len];
    file.read_exact(&mut tail)
        .map_err(|_| "packageCorrupt".to_string())?;

    let eocd_pos = (0..=tail_len - 22)
        .rev()
        .find(|&pos| {
            tail[pos..pos + 4] == [0x50, 0x4b, 0x05, 0x06]
                && le_u16(&tail, pos + 20)
                    .is_ok_and(|comment_len| pos + 22 + comment_len as usize == tail_len)
        })
        .ok_or_else(|| "packageCorrupt".to_string())?;

    let total_entries = le_u16(&tail, eocd_pos + 10)? as usize;
    let cd_size = le_u32(&tail, eocd_pos + 12)? as u64;
    let cd_offset = le_u32(&tail, eocd_pos + 16)? as u64;
    let eocd_abs = tail_start + eocd_pos as u64;
    if cd_offset
        .checked_add(cd_size)
        .is_none_or(|end| end > eocd_abs)
        || cd_size > 16 * 1024 * 1024
    {
        return Err("packageCorrupt".into());
    }

    file.seek(SeekFrom::Start(cd_offset))
        .map_err(|_| "packageCorrupt".to_string())?;
    let mut cd = vec![0u8; cd_size as usize];
    file.read_exact(&mut cd)
        .map_err(|_| "packageCorrupt".to_string())?;

    fs::create_dir_all(dest_dir).map_err(|_| "fileWriteError".to_string())?;

    let mut extracted = Vec::new();
    let mut cursor = 0usize;
    for _ in 0..total_entries {
        if cursor + 46 > cd.len() || cd[cursor..cursor + 4] != [0x50, 0x4b, 0x01, 0x02] {
            return Err("packageCorrupt".into());
        }
        let flags = le_u16(&cd, cursor + 8)?;
        if flags & 0x0001 != 0 {
            return Err("packageCorrupt".into());
        }
        let method = le_u16(&cd, cursor + 10)?;
        let expected_crc = le_u32(&cd, cursor + 16)?;
        let comp_size = le_u32(&cd, cursor + 20)? as u64;
        let uncomp_size = le_u32(&cd, cursor + 24)? as u64;
        let name_len = le_u16(&cd, cursor + 28)? as usize;
        let extra_len = le_u16(&cd, cursor + 30)? as usize;
        let comment_len = le_u16(&cd, cursor + 32)? as usize;
        let local_offset = le_u32(&cd, cursor + 42)? as u64;

        let name_start = cursor + 46;
        let name_end = name_start + name_len;
        let next_cursor = name_end + extra_len + comment_len;
        if next_cursor > cd.len() {
            return Err("packageCorrupt".into());
        }
        let raw_name =
            std::str::from_utf8(&cd[name_start..name_end]).map_err(|_| "packageCorrupt")?;
        cursor = next_cursor;

        let Some(rel_path) = safe_zip_rel_path(raw_name)? else {
            continue;
        };
        if uncomp_size > MAX_ZIP_ENTRY_BYTES || comp_size > total_len {
            return Err("packageCorrupt".into());
        }

        file.seek(SeekFrom::Start(local_offset))
            .map_err(|_| "packageCorrupt".to_string())?;
        let mut lfh = [0u8; 30];
        file.read_exact(&mut lfh)
            .map_err(|_| "packageCorrupt".to_string())?;
        if lfh[0..4] != [0x50, 0x4b, 0x03, 0x04] {
            return Err("packageCorrupt".into());
        }
        let lf_name_len = le_u16(&lfh, 26)? as u64;
        let lf_extra_len = le_u16(&lfh, 28)? as u64;
        let data_offset = local_offset + 30 + lf_name_len + lf_extra_len;
        if data_offset
            .checked_add(comp_size)
            .is_none_or(|end| end > cd_offset)
        {
            return Err("packageCorrupt".into());
        }
        file.seek(SeekFrom::Start(data_offset))
            .map_err(|_| "packageCorrupt".to_string())?;
        let mut compressed = vec![0u8; comp_size as usize];
        file.read_exact(&mut compressed)
            .map_err(|_| "packageCorrupt".to_string())?;

        let data = match method {
            0 => {
                if comp_size != uncomp_size {
                    return Err("packageCorrupt".into());
                }
                compressed
            }
            8 => {
                let mut decoder = DeflateDecoder::new(&compressed[..]);
                let mut out = Vec::with_capacity(uncomp_size.min(4 * 1024 * 1024) as usize);
                decoder
                    .by_ref()
                    .take(uncomp_size + 1)
                    .read_to_end(&mut out)
                    .map_err(|_| "packageCorrupt".to_string())?;
                if out.len() as u64 != uncomp_size {
                    return Err("packageCorrupt".into());
                }
                out
            }
            _ => return Err("packageCorrupt".into()),
        };

        if crc32fast::hash(&data) != expected_crc {
            return Err("packageCorrupt".into());
        }

        let target = dest_dir.join(&rel_path);
        write_atomic(&target, &data)?;
        #[cfg(unix)]
        if target
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|ext| matches!(ext.to_ascii_lowercase().as_str(), "exe" | "sh" | "py"))
        {
            fs::set_permissions(&target, fs::Permissions::from_mode(0o755))
                .map_err(|_| "fileWriteError".to_string())?;
        }
        extracted.push(rel_path);
    }
    if cursor != cd.len() {
        return Err("packageCorrupt".into());
    }
    Ok(extracted)
}

fn validate_arg_list(args: &[String], forbidden: &[String]) -> Result<(), String> {
    for arg in args {
        if arg.eq_ignore_ascii_case("--force") || forbidden.iter().any(|f| f == arg) {
            return Err("unsafeAdapter".into());
        }
        if (arg.contains('{') || arg.contains('}')) && arg != "{gameDir}" {
            return Err("unsafeAdapter".into());
        }
    }
    Ok(())
}

/// Validates a declarative `adapter` profile before touching staging or game files.
pub fn validate_adapter(adapter: &AdapterProfile) -> Result<(), String> {
    if adapter.kind != "upstream-cli" || adapter.target != "pckDir" {
        return Err("unsafeAdapter".into());
    }
    if adapter.platforms.is_empty() || adapter.platforms.iter().any(|p| p != "windows") {
        return Err("unsafeAdapter".into());
    }
    if adapter.touches.is_empty() || !adapter.touches.iter().all(|f| is_safe_filename(f)) {
        return Err("unsafeAdapter".into());
    }
    if adapter.exclusive.is_empty() {
        return Err("unsafeAdapter".into());
    }
    if !is_safe_filename(&adapter.baseline.file)
        || adapter.baseline.size == 0
        || !is_hex_sha256(&adapter.baseline.sha256)
    {
        return Err("unsafeAdapter".into());
    }
    if let Some(vf) = &adapter.verify_files
        && !is_safe_filename(vf)
    {
        return Err("unsafeAdapter".into());
    }
    if !matches!(
        adapter.run.interpreter.as_str(),
        "exe" | "bundled-python" | "powershell"
    ) || !is_safe_filename(&adapter.run.program)
    {
        return Err("unsafeAdapter".into());
    }
    if !adapter.forbidden_args.iter().any(|arg| arg == "--force") {
        return Err("unsafeAdapter".into());
    }
    for list in [
        &adapter.run.common,
        &adapter.actions.preflight,
        &adapter.actions.status,
        &adapter.actions.install,
        &adapter.actions.uninstall,
    ] {
        validate_arg_list(list, &adapter.forbidden_args)?;
    }
    Regex::new(&adapter.status.installed).map_err(|_| "unsafeAdapter".to_string())?;
    Regex::new(&adapter.status.vanilla).map_err(|_| "unsafeAdapter".to_string())?;
    if let Some(older) = &adapter.status.older {
        Regex::new(older).map_err(|_| "unsafeAdapter".to_string())?;
    }
    Ok(())
}

/// Expands validated argument templates into an allowlisted subprocess invocation.
pub fn build_command(
    adapter: &AdapterProfile,
    work_dir: &Path,
    pck_dir: &Path,
    action_args: &[String],
) -> Result<CommandRequest, String> {
    validate_adapter(adapter)?;
    let game_dir_str = pck_dir.to_string_lossy().into_owned();
    let expand = |raw: &[String]| -> Vec<String> {
        raw.iter()
            .map(|arg| {
                if arg == "{gameDir}" {
                    game_dir_str.clone()
                } else {
                    arg.clone()
                }
            })
            .collect()
    };
    let mut expanded = expand(&adapter.run.common);
    expanded.extend(expand(action_args));
    let program_path = work_dir.join(&adapter.run.program);
    let program_str = program_path.to_string_lossy().into_owned();

    match adapter.run.interpreter.as_str() {
        "exe" => Ok(CommandRequest {
            program: program_path,
            args: expanded,
            cwd: work_dir.to_path_buf(),
        }),
        "bundled-python" => {
            let bundled = work_dir.join("python").join("python.exe");
            let python = if bundled.is_file() {
                bundled
            } else if cfg!(windows) {
                PathBuf::from("python")
            } else {
                PathBuf::from("python3")
            };
            let mut args = Vec::with_capacity(1 + expanded.len());
            args.push(program_str);
            args.extend(expanded);
            Ok(CommandRequest {
                program: python,
                args,
                cwd: work_dir.to_path_buf(),
            })
        }
        "powershell" => {
            let shell = if cfg!(windows) {
                "powershell.exe"
            } else {
                "pwsh"
            };
            let mut args = vec!["-NoProfile".to_string()];
            if cfg!(windows) {
                args.extend(["-ExecutionPolicy".to_string(), "Bypass".to_string()]);
            }
            args.extend(["-File".to_string(), program_str]);
            args.extend(expanded);
            Ok(CommandRequest {
                program: PathBuf::from(shell),
                args,
                cwd: work_dir.to_path_buf(),
            })
        }
        _ => Err("unsafeAdapter".into()),
    }
}

/// Parses upstream `--status` stdout line-by-line into `DiskModState`.
pub fn parse_status(adapter: &AdapterProfile, stdout: &str) -> Result<DiskModState, String> {
    let installed_re =
        Regex::new(&adapter.status.installed).map_err(|_| "unsafeAdapter".to_string())?;
    let vanilla_re =
        Regex::new(&adapter.status.vanilla).map_err(|_| "unsafeAdapter".to_string())?;
    let older_re = adapter
        .status
        .older
        .as_deref()
        .map(Regex::new)
        .transpose()
        .map_err(|_| "unsafeAdapter".to_string())?;

    for line in stdout.lines() {
        let line = line.trim_end_matches('\r');
        if installed_re.is_match(line) {
            return Ok(DiskModState::Installed);
        }
        if vanilla_re.is_match(line) {
            return Ok(DiskModState::Vanilla);
        }
        if older_re.as_ref().is_some_and(|re| re.is_match(line)) {
            return Ok(DiskModState::OlderVersion);
        }
    }
    Ok(DiskModState::Unrecognized(stdout.trim().to_string()))
}

pub fn run_status_cmd(
    adapter: &AdapterProfile,
    work_dir: &Path,
    pck_dir: &Path,
    runner: &dyn ProcessRunner,
) -> Result<DiskModState, String> {
    let req = build_command(adapter, work_dir, pck_dir, &adapter.actions.status)?;
    let out = runner.run(&req)?;
    if out.code != 0 {
        return Err("statusUnavailable".into());
    }
    parse_status(adapter, &out.stdout)
}

fn verify_checksum_manifest(
    dir: &Path,
    manifest_name: &str,
    required_program: &str,
    required_files: &[String],
) -> Result<(), String> {
    let manifest_path = dir.join(manifest_name);
    let content = fs::read_to_string(&manifest_path).map_err(|_| "packageCorrupt".to_string())?;
    let mut verified_program = false;
    let mut verified_names = std::collections::BTreeSet::new();

    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.splitn(2, char::is_whitespace);
        let expected_sha = parts.next().unwrap_or("");
        let rest = parts.next().unwrap_or("").trim();
        let filename = rest.strip_prefix('*').unwrap_or(rest);
        if !is_hex_sha256(expected_sha) || !is_safe_filename(filename) {
            return Err("packageCorrupt".into());
        }
        let file_path = dir.join(filename);
        if file_path.is_file() {
            let fp = file_fingerprint(&file_path)?;
            if !fp.sha256.eq_ignore_ascii_case(expected_sha) {
                return Err("packageCorrupt".into());
            }
            verified_names.insert(filename.to_owned());
            if filename == required_program {
                verified_program = true;
            }
        } else if required_files.iter().any(|name| name == filename) || filename == required_program
        {
            return Err("packageCorrupt".into());
        }
    }

    if !verified_program
        || !required_files
            .iter()
            .all(|name| verified_names.contains(name))
    {
        return Err("packageCorrupt".into());
    }
    Ok(())
}

/// Verifies an outer package ZIP, extracts it into staging, verifies `SHA256SUMS.txt`, and runs `preflight`.
pub fn stage_package(
    zip_path: &Path,
    staging_dir: &Path,
    pkg: &PackageSpec,
    adapter: &AdapterProfile,
    pck_dir: &Path,
    runner: &dyn ProcessRunner,
) -> Result<(), String> {
    validate_adapter(adapter)?;
    let outer = file_fingerprint(zip_path).map_err(|_| "packageCorrupt".to_string())?;
    if outer.size != pkg.size || !outer.sha256.eq_ignore_ascii_case(&pkg.sha256) {
        return Err("packageCorrupt".into());
    }
    if staging_dir.exists() {
        fs::remove_dir_all(staging_dir).map_err(|_| "fileWriteError".to_string())?;
    }
    extract_zip(zip_path, staging_dir).map_err(|e| {
        if e == "packageCorrupt" {
            format!("internalPackage: {}", pkg.filename)
        } else {
            e
        }
    })?;
    if let Some(manifest) = &adapter.verify_files {
        verify_checksum_manifest(
            staging_dir,
            manifest,
            &adapter.run.program,
            &adapter.required_files,
        )
        .map_err(|_| format!("internalPackage: {manifest}"))?;
    } else if !staging_dir.join(&adapter.run.program).is_file() {
        return Err("packageCorrupt".into());
    }
    if !adapter.actions.preflight.is_empty() {
        let req = build_command(adapter, staging_dir, pck_dir, &adapter.actions.preflight)?;
        let out = runner.run(&req)?;
        if out.code != 0 {
            return Err(format!("internalPackage: {}", pkg.filename));
        }
    }
    Ok(())
}

fn read_u32_le(cursor: &mut Cursor<&[u8]>) -> Result<u32, String> {
    let mut buf = [0u8; 4];
    cursor
        .read_exact(&mut buf)
        .map_err(|_| "restoreCorrupt".to_string())?;
    Ok(u32::from_le_bytes(buf))
}

fn read_i32_le(cursor: &mut Cursor<&[u8]>) -> Result<i32, String> {
    let mut buf = [0u8; 4];
    cursor
        .read_exact(&mut buf)
        .map_err(|_| "restoreCorrupt".to_string())?;
    Ok(i32::from_le_bytes(buf))
}

fn read_i64_le(cursor: &mut Cursor<&[u8]>) -> Result<i64, String> {
    let mut buf = [0u8; 8];
    cursor
        .read_exact(&mut buf)
        .map_err(|_| "restoreCorrupt".to_string())?;
    Ok(i64::from_le_bytes(buf))
}

fn read_dotnet_string(cursor: &mut Cursor<&[u8]>) -> Result<String, String> {
    let mut len = 0usize;
    let mut shift = 0u32;
    loop {
        if shift >= 35 {
            return Err("restoreCorrupt".into());
        }
        let mut byte = [0u8; 1];
        cursor
            .read_exact(&mut byte)
            .map_err(|_| "restoreCorrupt".to_string())?;
        len |= ((byte[0] & 0x7f) as usize) << shift;
        if byte[0] & 0x80 == 0 {
            break;
        }
        shift += 7;
    }
    if len > MAX_RESTORE_BYTES as usize {
        return Err("restoreCorrupt".into());
    }
    let mut bytes = vec![0u8; len];
    cursor
        .read_exact(&mut bytes)
        .map_err(|_| "restoreCorrupt".to_string())?;
    String::from_utf8(bytes).map_err(|_| "restoreCorrupt".into())
}

/// Parses the header of an `overtime_restore.dat` (`MP8R`) delta restore record.
pub fn parse_mp8r_restore(path: &Path) -> Result<RestoreHeader, String> {
    let meta = fs::metadata(path).map_err(|_| "restoreCorrupt".to_string())?;
    if meta.len() > MAX_RESTORE_BYTES {
        return Err("restoreCorrupt".into());
    }
    let bytes = fs::read(path).map_err(|_| "restoreCorrupt".to_string())?;
    let mut cursor = Cursor::new(bytes.as_slice());
    if read_u32_le(&mut cursor)? != MP8R_MAGIC {
        return Err("restoreCorrupt".into());
    }
    let format = read_u32_le(&mut cursor)?;
    if format != 1 && format != 2 {
        return Err("restoreCorrupt".into());
    }
    let orig_len = read_i64_le(&mut cursor)?;
    let patched_len = read_i64_le(&mut cursor)?;
    if orig_len <= 0 || patched_len <= 0 {
        return Err("restoreCorrupt".into());
    }
    let base_sha = read_dotnet_string(&mut cursor)?;
    let game_ver = read_dotnet_string(&mut cursor)?;
    let mod_tag = read_dotnet_string(&mut cursor)?;
    let entry_count = read_i32_le(&mut cursor)?;
    if format == 2 && (!is_hex_sha256(&base_sha) || entry_count <= 0) {
        return Err("restoreCorrupt".into());
    }
    Ok(RestoreHeader {
        format,
        orig_len,
        patched_len,
        base_sha,
        game_ver,
        mod_tag,
        entry_count,
    })
}

fn uses_delta_restore(adapter: &AdapterProfile) -> bool {
    adapter.upstream_uninstall && adapter.touches.iter().any(|name| name == RESTORE_DAT)
}

pub fn check_exclusive_conflicts(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    adapter: &AdapterProfile,
    all_mods: &[ModEntry],
) -> Result<(), String> {
    let target = game::resolve_pck_dir(game_root).ok_or("invalidGame")?;
    if adapter.exclusive == "pck"
        && target
            .join("MachinePartyModLoader.exe")
            .try_exists()
            .map_err(|_| "fileReadError")?
    {
        return Err("loaderConflict".into());
    }
    let installed = inventory::installed_versions(config_dir, game_root)?;
    for repo in installed.keys() {
        if repo == &mod_entry.repo {
            continue;
        }
        let Some(other) = all_mods.iter().find(|entry| &entry.repo == repo) else {
            return Err("modConflict".into());
        };
        if other
            .adapter
            .as_ref()
            .is_none_or(|other_adapter| other_adapter.exclusive == adapter.exclusive)
        {
            return Err("modConflict".into());
        }
    }
    Ok(())
}

fn mirror_delta_backup(
    adapter: &AdapterProfile,
    staging_dir: &Path,
    pck_dir: &Path,
    backup_dir: &Path,
    expected_base_sha: &str,
) -> Result<(), String> {
    let restore_src = pck_dir.join(RESTORE_DAT);
    let header = parse_mp8r_restore(&restore_src)?;
    if !header.base_sha.eq_ignore_ascii_case(expected_base_sha) {
        return Err("restoreCorrupt".into());
    }
    copy_atomic(&restore_src, &backup_dir.join(RESTORE_DAT))?;
    copy_atomic(
        &staging_dir.join(&adapter.run.program),
        &backup_dir.join(&adapter.run.program),
    )?;
    #[cfg(unix)]
    fs::set_permissions(
        backup_dir.join(&adapter.run.program),
        fs::Permissions::from_mode(0o755),
    )
    .map_err(|_| "fileWriteError".to_string())?;
    if let Some(manifest) = &adapter.verify_files {
        let src_manifest = staging_dir.join(manifest);
        if src_manifest.is_file() {
            copy_atomic(&src_manifest, &backup_dir.join(manifest))?;
        }
    }
    Ok(())
}

fn check_space(dir: &Path, required: u64) -> Result<(), String> {
    if fs2::available_space(dir).map_err(|_| "fileReadError")? < required {
        return Err(format!("{}: {}", "diskSpace", dir.display()));
    }
    Ok(())
}

// This adapter owns only the baseline and sidecars created during its transaction.
fn sidecars_absent(adapter: &AdapterProfile, dir: &Path) -> Result<bool, String> {
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
        failure: None,
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
            inventory::record_installed(config_dir, game_root, &mod_entry.repo, &version)?;
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

fn clear_mod_records(
    config_dir: &Path,
    game_root: &Path,
    mod_entry: &ModEntry,
    backup_dir: Option<&Path>,
) -> Result<(), String> {
    inventory::remove_installed(config_dir, game_root, &mod_entry.repo)?;
    remove_transaction(config_dir, game_root, &mod_entry.id)?;
    if let Some(dir) = backup_dir {
        let _ = fs::remove_dir_all(dir);
    }
    Ok(())
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
    if tx.pck_dir != pck_dir
        || tx.backup_dir != backup_dir_for(config_dir, game_root, &mod_entry.id)
        || tx.version != mod_entry.version.as_deref().unwrap_or_default()
        || tx.repo != mod_entry.repo
    {
        return Err("gameUpdatedOrModified".into());
    }
    if !matches!(
        tx.status,
        TransactionStatus::Committed | TransactionStatus::NeedsRepair
    ) {
        return Err("missingTransaction".into());
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
        if uses_delta_restore(adapter) && disk_restore.is_file() {
            fs::remove_file(&disk_restore).map_err(|_| "fileWriteError")?;
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
    let req = build_command(
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
        failure: None,
    };
    save_transaction(config_dir, game_root, record.clone())?;
    inventory::record_installed(config_dir, game_root, &mod_entry.repo, &version)?;
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
    let in_inventory = installed.contains_key(&mod_entry.repo);

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
    let recorded_version = installed.get(&mod_entry.repo).cloned();
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

/// Checks whether the current OS is supported by an adapter's `platforms` list.
pub fn check_platform_supported(adapter: &AdapterProfile) -> Result<(), String> {
    if adapter.platforms.iter().any(|p| p == std::env::consts::OS) {
        Ok(())
    } else {
        Err("windowsOnlyMod".into())
    }
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
    let mut mod_states = BTreeMap::new();
    let mut repair = BTreeMap::new();

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
        let state =
            if pck_dir.join("MachinePartyModLoader.exe").is_file() && adapter.exclusive == "pck" {
                "loaderConflict"
            } else if tx.is_some_and(|r| {
                matches!(
                    r.status,
                    TransactionStatus::Pending | TransactionStatus::NeedsRepair
                )
            }) {
                "needsRepair"
            } else if vanilla {
                installed.remove(&item.repo);
                if sidecars_absent(adapter, &pck_dir)? {
                    "vanilla"
                } else {
                    "restoreResidue"
                }
            } else if let Some(record) = tx.filter(|r| r.status == TransactionStatus::Committed) {
                if record.post_pck.as_ref() == Some(&current_pck) {
                    installed.insert(item.repo.clone(), record.version.clone());
                    "installed"
                } else {
                    "gameUpdatedOrModified"
                }
            } else if installed.contains_key(&item.repo) {
                "needsRepair"
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
            repair.insert(
                item.id.clone(),
                (record.backup_dir.clone(), record.failure.clone()),
            );
        }
        mod_states.insert(item.id.clone(), state.to_owned());
    }
    Ok(CopyValidation {
        pck_path: pck_dir.join("Machine Party.pck"),
        pck_dir,
        pck_size: current_pck.size,
        pck_sha256: current_pck.sha256,
        repair,
        installed,
        mod_states,
    })
}

#[derive(Serialize, Deserialize, PartialEq, Eq)]
struct ScanStamp {
    catalog: Vec<ModEntry>,
    files: BTreeMap<PathBuf, Option<(String, u64, std::time::SystemTime)>>,
}

fn scan_stamp(config: &Path, root: &Path, mods: &[ModEntry]) -> Result<ScanStamp, String> {
    let dir = game::resolve_pck_dir(root).ok_or("invalidGame")?;
    let mut paths = vec![
        dir.join("MachinePartyModLoader.exe"),
        dir.join("Machine Party.exe"),
        dir.join("Machine Party.pck"),
        config.join(TRANSACTIONS_FILE),
        config.join("installations.json"),
    ];
    for item in mods {
        if let Some(adapter) = &item.adapter {
            paths.extend(adapter.touches.iter().map(|name| dir.join(name)));
            let backup = backup_dir_for(config, root, &item.id);
            paths.push(backup.join(&adapter.baseline.file));
            paths.push(backup.join(RESTORE_DAT));
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
    let cache = config.join("scan-v1").join(short_hash(root));
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{ActionSpec, BaselineSpec, RunSpec, StatusMatchers};
    use flate2::{Compression, write::DeflateEncoder};
    use std::cell::RefCell;

    fn test_root(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mpm-inst-{name}-{}", unique_suffix()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn build_synthetic_pck() -> Vec<u8> {
        let script_path = b"res://scenes/lobby/scripts/lobby_scene.gdc\0";
        let payload = b"GDPC_SYNTHETIC_SCRIPT_V212";
        let mut out = Vec::new();
        out.extend_from_slice(b"GDPC");
        out.extend_from_slice(&2u32.to_le_bytes()); // pack format v2
        out.extend_from_slice(&4u32.to_le_bytes()); // godot major
        out.extend_from_slice(&3u32.to_le_bytes()); // godot minor
        out.extend_from_slice(&0u32.to_le_bytes()); // godot patch
        out.extend_from_slice(&0u32.to_le_bytes()); // flags
        let file_base = 96u64;
        out.extend_from_slice(&file_base.to_le_bytes());
        out.resize(96, 0);
        let payload_offset = 256u64;
        out.extend_from_slice(&1u32.to_le_bytes());
        out.extend_from_slice(&(script_path.len() as u32).to_le_bytes());
        out.extend_from_slice(script_path);
        out.extend_from_slice(&(payload_offset - file_base).to_le_bytes());
        out.extend_from_slice(&(payload.len() as u64).to_le_bytes());
        out.extend_from_slice(&[0x11u8; 16]);
        out.extend_from_slice(&0u32.to_le_bytes());
        out.resize(payload_offset as usize, 0);
        out.extend_from_slice(payload);
        out
    }

    fn write_dotnet_string(buf: &mut Vec<u8>, s: &str) {
        let bytes = s.as_bytes();
        let mut len = bytes.len();
        while len >= 0x80 {
            buf.push(((len as u8) & 0x7f) | 0x80);
            len >>= 7;
        }
        buf.push(len as u8);
        buf.extend_from_slice(bytes);
    }

    fn build_mp8r_restore(
        orig_len: u64,
        patched_len: u64,
        base_sha_upper: &str,
        game_ver: &str,
        mod_tag: &str,
    ) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(&MP8R_MAGIC.to_le_bytes());
        buf.extend_from_slice(&2u32.to_le_bytes());
        buf.extend_from_slice(&(orig_len as i64).to_le_bytes());
        buf.extend_from_slice(&(patched_len as i64).to_le_bytes());
        write_dotnet_string(&mut buf, base_sha_upper);
        write_dotnet_string(&mut buf, game_ver);
        write_dotnet_string(&mut buf, mod_tag);
        buf.extend_from_slice(&1i32.to_le_bytes());
        write_dotnet_string(&mut buf, "res://scenes/lobby/scripts/lobby_scene.gdc");
        buf.extend_from_slice(&160u64.to_le_bytes());
        buf.extend_from_slice(&26u64.to_le_bytes());
        buf.extend_from_slice(&[0x11u8; 16]);
        buf.extend_from_slice(&orig_len.to_le_bytes());
        buf.extend_from_slice(&28u64.to_le_bytes());
        buf.extend_from_slice(&[0x22u8; 16]);
        buf
    }

    fn build_test_zip(entries: &[(&str, &[u8], bool)]) -> Vec<u8> {
        let mut out = Vec::new();
        let mut central = Vec::new();
        for (name, data, deflate) in entries {
            let local_offset = out.len() as u32;
            let crc = crc32fast::hash(data);
            let (method, compressed) = if *deflate {
                let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
                enc.write_all(data).unwrap();
                (8u16, enc.finish().unwrap())
            } else {
                (0u16, data.to_vec())
            };
            let name_bytes = name.as_bytes();
            out.extend_from_slice(&[0x50, 0x4b, 0x03, 0x04]);
            out.extend_from_slice(&20u16.to_le_bytes());
            out.extend_from_slice(&0u16.to_le_bytes());
            out.extend_from_slice(&method.to_le_bytes());
            out.extend_from_slice(&0u16.to_le_bytes());
            out.extend_from_slice(&0u16.to_le_bytes());
            out.extend_from_slice(&crc.to_le_bytes());
            out.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
            out.extend_from_slice(&(data.len() as u32).to_le_bytes());
            out.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
            out.extend_from_slice(&0u16.to_le_bytes());
            out.extend_from_slice(name_bytes);
            out.extend_from_slice(&compressed);

            central.extend_from_slice(&[0x50, 0x4b, 0x01, 0x02]);
            central.extend_from_slice(&20u16.to_le_bytes());
            central.extend_from_slice(&20u16.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&method.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&crc.to_le_bytes());
            central.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
            central.extend_from_slice(&(data.len() as u32).to_le_bytes());
            central.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&0u16.to_le_bytes());
            central.extend_from_slice(&0u32.to_le_bytes());
            central.extend_from_slice(&local_offset.to_le_bytes());
            central.extend_from_slice(name_bytes);
        }
        let cd_offset = out.len() as u32;
        let cd_size = central.len() as u32;
        out.extend_from_slice(&central);
        out.extend_from_slice(&[0x50, 0x4b, 0x05, 0x06]);
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        out.extend_from_slice(&(entries.len() as u16).to_le_bytes());
        out.extend_from_slice(&cd_size.to_le_bytes());
        out.extend_from_slice(&cd_offset.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out
    }

    fn setup_synthetic_game(root: &Path, pck_bytes: &[u8]) -> (PathBuf, PathBuf, FileFingerprint) {
        let game_root = root.join("party project");
        let pck_dir = game_root.join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        fs::write(pck_dir.join("Machine Party.exe"), b"MZ_SYNTHETIC").unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        fs::write(&pck_path, pck_bytes).unwrap();
        let fp = file_fingerprint(&pck_path).unwrap();
        (game_root, pck_dir, fp)
    }

    fn synthetic_overtime_entry(
        baseline: &FileFingerprint,
        zip_bytes: &[u8],
        upstream_uninstall: bool,
    ) -> ModEntry {
        let zip_sha = hex::encode(Sha256::digest(zip_bytes));
        ModEntry {
            id: "overtime".into(),
            order: 1,
            repo: "DarkJadeStone/MachineParty-Overtime".into(),
            version: Some("v1.7".into()),
            verified: true,
            package: Some(PackageSpec {
                asset_id: "594522625".into(),
                filename: "Machine-Party-Overtime-1.7-CLI.zip".into(),
                size: zip_bytes.len() as u64,
                sha256: zip_sha,
                mirror_approved: true,
            }),
            adapter: Some(AdapterProfile {
                kind: "upstream-cli".into(),
                platforms: vec!["windows".into()],
                target: "pckDir".into(),
                touches: if upstream_uninstall {
                    vec!["Machine Party.pck".into(), RESTORE_DAT.into()]
                } else {
                    vec!["Machine Party.pck".into()]
                },
                exclusive: "pck".into(),
                baseline: BaselineSpec {
                    file: "Machine Party.pck".into(),
                    size: baseline.size,
                    sha256: baseline.sha256.clone(),
                },
                required_files: vec!["overtime_payload.zip".into()],
                verify_files: Some("SHA256SUMS.txt".into()),
                upstream_uninstall,
                run: RunSpec {
                    interpreter: "exe".into(),
                    program: "overtime_install.exe".into(),
                    common: vec![
                        "--game".into(),
                        "{gameDir}".into(),
                        "--lang".into(),
                        "en".into(),
                        "--no-pause".into(),
                    ],
                },
                actions: ActionSpec {
                    preflight: vec!["--verify-package".into()],
                    status: vec!["--status".into()],
                    install: vec![],
                    uninstall: if upstream_uninstall {
                        vec!["--uninstall".into()]
                    } else {
                        vec![]
                    },
                },
                status: StatusMatchers {
                    installed: r"^State:\s+Overtime overtime-1\.7 installed".into(),
                    vanilla: r"^State:\s+vanilla".into(),
                    older: Some(r"^State:\s+Overtime .* installed \(this program".into()),
                },
                forbidden_args: vec!["--force".into()],
            }),
        }
    }

    fn make_fake_package_zip(exe_bytes: &[u8], payload_bytes: &[u8]) -> Vec<u8> {
        let exe_sha = hex::encode(Sha256::digest(exe_bytes)).to_ascii_uppercase();
        let payload_sha = hex::encode(Sha256::digest(payload_bytes)).to_ascii_uppercase();
        let sums = format!(
            "BFFA0F01B476A34763E5B6FA53513DBABCBBEAFE72686328CEAEE21F4ACD71C8  overtime_launcher.exe\n\
             {exe_sha}  overtime_install.exe\n\
             {payload_sha}  overtime_payload.zip\n"
        );
        build_test_zip(&[
            ("overtime_install.exe", exe_bytes, false),
            ("overtime_payload.zip", payload_bytes, true),
            ("SHA256SUMS.txt", sums.as_bytes(), true),
        ])
    }

    struct UnlockedCheck;
    impl GameLockCheck for UnlockedCheck {
        fn ensure_unlocked(&self, _pck_dir: &Path, _pck_path: &Path) -> Result<(), String> {
            Ok(())
        }
    }

    struct LockedCheck;
    impl GameLockCheck for LockedCheck {
        fn ensure_unlocked(&self, _pck_dir: &Path, _pck_path: &Path) -> Result<(), String> {
            Err("gameRunning".into())
        }
    }

    enum FakeFault {
        None,
        FailInstallMidWrite,
        WriteUndeclaredFile,
    }

    struct FakeCliRunner {
        vanilla_bytes: Vec<u8>,
        vanilla_sha: String,
        fault: FakeFault,
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl ProcessRunner for FakeCliRunner {
        fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String> {
            self.calls.borrow_mut().push(req.args.clone());
            if req.args.iter().any(|a| a == "--verify-package") {
                return Ok(CommandOutput {
                    code: 0,
                    stdout: "Payload OK: overtime-1.7 | scripts=70\n".into(),
                    stderr: String::new(),
                });
            }
            let idx = req
                .args
                .iter()
                .position(|a| a == "--game")
                .expect("--game passed");
            let pck_dir = PathBuf::from(&req.args[idx + 1]);
            let pck_path = pck_dir.join("Machine Party.pck");
            let restore_path = pck_dir.join(RESTORE_DAT);

            if req.args.iter().any(|a| a == "--status") {
                let fp = file_fingerprint(&pck_path)?;
                let state_line = if fp.sha256 == self.vanilla_sha {
                    "State:    vanilla (mod not installed)"
                } else if pck_path.is_file()
                    && fs::read(&pck_path).unwrap().ends_with(b"OVERTIME_1_7")
                {
                    "State:    Overtime overtime-1.7 installed"
                } else {
                    "State:    unrecognised"
                };
                return Ok(CommandOutput {
                    code: 0,
                    stdout: format!("PCK: {}\n{}\n", pck_path.display(), state_line),
                    stderr: String::new(),
                });
            }

            if req.args.iter().any(|a| a == "--uninstall") {
                assert!(restore_path.is_file(), "restore record must exist");
                fs::write(&pck_path, &self.vanilla_bytes).unwrap();
                let _ = fs::remove_file(&restore_path);
                return Ok(CommandOutput {
                    code: 0,
                    stdout: "Reverted to vanilla.\n".into(),
                    stderr: String::new(),
                });
            }

            let mut patched = self.vanilla_bytes.clone();
            patched.extend_from_slice(b"OVERTIME_1_7");
            let restore = build_mp8r_restore(
                self.vanilla_bytes.len() as u64,
                patched.len() as u64,
                &self.vanilla_sha.to_ascii_uppercase(),
                "v2.1.2",
                "overtime-1.7",
            );
            fs::write(&restore_path, &restore).unwrap();
            match self.fault {
                FakeFault::FailInstallMidWrite => {
                    fs::write(&pck_path, b"CORRUPTED_PARTIAL").unwrap();
                    return Ok(CommandOutput {
                        code: 1,
                        stdout: String::new(),
                        stderr: "simulated crash".into(),
                    });
                }
                FakeFault::WriteUndeclaredFile => {
                    fs::write(&pck_path, &patched).unwrap();
                    fs::write(pck_dir.join("unexpected_extra.dll"), b"bad").unwrap();
                }
                FakeFault::None => {
                    fs::write(&pck_path, &patched).unwrap();
                }
            }
            Ok(CommandOutput {
                code: 0,
                stdout: "Done\n".into(),
                stderr: String::new(),
            })
        }
    }

    #[test]
    fn l1_clean_install_and_offline_uninstall_restores_vanilla() {
        let root = test_root("l1-clean");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();

        let mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        let config_dir = root.join("config");
        let staging_dir = root.join("staging");
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };

        let tx = install_from_zip(
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &mod_entry,
            std::slice::from_ref(&mod_entry),
            &runner,
            &UnlockedCheck,
        )
        .unwrap();
        assert_eq!(tx.status, TransactionStatus::Committed);
        assert_eq!(
            inventory::installed_versions(&config_dir, &game_root).unwrap()["DarkJadeStone/MachineParty-Overtime"],
            "v1.7"
        );
        assert!(tx.backup_dir.join("overtime_install.exe").is_file());
        assert!(tx.backup_dir.join(RESTORE_DAT).is_file());

        fs::remove_dir_all(&staging_dir).unwrap();
        fs::remove_file(&zip_path).unwrap();
        fs::remove_file(pck_dir.join(RESTORE_DAT)).unwrap();

        let restored =
            uninstall_mod(&config_dir, &game_root, &mod_entry, &runner, &UnlockedCheck).unwrap();
        assert_eq!(restored, baseline);
        assert!(
            inventory::installed_versions(&config_dir, &game_root)
                .unwrap()
                .is_empty()
        );
        assert!(!tx.backup_dir.exists());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l1_rejects_corrupt_zip_inner_checksum_and_forbidden_force() {
        let root = test_root("l1-verify");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes,
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };

        let mut bad_outer = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        bad_outer.package.as_mut().unwrap().sha256 = "0".repeat(64);
        assert_eq!(
            install_from_zip(
                &root.join("cfg1"),
                &game_root,
                &zip_path,
                &root.join("stg1"),
                &bad_outer,
                std::slice::from_ref(&bad_outer),
                &runner,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "packageCorrupt"
        );

        let sums = format!(
            "{}  overtime_install.exe\n{}  overtime_payload.zip\n",
            hex::encode(Sha256::digest(b"FAKE_EXE")),
            "f".repeat(64)
        );
        let bad_inner_zip = build_test_zip(&[
            ("overtime_install.exe", b"FAKE_EXE", false),
            ("overtime_payload.zip", b"FAKE_PAYLOAD", true),
            ("SHA256SUMS.txt", sums.as_bytes(), true),
        ]);
        let bad_inner_path = root.join("bad_inner.zip");
        fs::write(&bad_inner_path, &bad_inner_zip).unwrap();
        let bad_inner_entry = synthetic_overtime_entry(&baseline, &bad_inner_zip, true);
        assert_eq!(
            install_from_zip(
                &root.join("cfg2"),
                &game_root,
                &bad_inner_path,
                &root.join("stg2"),
                &bad_inner_entry,
                std::slice::from_ref(&bad_inner_entry),
                &runner,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "internalPackage: SHA256SUMS.txt"
        );

        let mut forced = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        forced
            .adapter
            .as_mut()
            .unwrap()
            .actions
            .install
            .push("--force".into());
        assert_eq!(
            install_from_zip(
                &root.join("cfg3"),
                &game_root,
                &zip_path,
                &root.join("stg3"),
                &forced,
                std::slice::from_ref(&forced),
                &runner,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "unsafeAdapter"
        );
        assert_eq!(
            file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
            baseline
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l1_rejects_locked_game_and_rolls_back_mid_write_or_undeclared_faults() {
        let root = test_root("l1-faults");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);

        let runner_ok = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };
        assert_eq!(
            install_from_zip(
                &root.join("cfg-lock"),
                &game_root,
                &zip_path,
                &root.join("stg-lock"),
                &mod_entry,
                std::slice::from_ref(&mod_entry),
                &runner_ok,
                &LockedCheck,
            )
            .unwrap_err(),
            "gameRunning"
        );
        assert!(runner_ok.calls.borrow().is_empty());

        let runner_crash = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::FailInstallMidWrite,
            calls: RefCell::new(Vec::new()),
        };
        let cfg_crash = root.join("cfg-crash");
        assert_eq!(
            install_from_zip(
                &cfg_crash,
                &game_root,
                &zip_path,
                &root.join("stg-crash"),
                &mod_entry,
                std::slice::from_ref(&mod_entry),
                &runner_crash,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "installFailed"
        );
        assert_eq!(
            file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
            baseline
        );
        assert!(
            inventory::installed_versions(&cfg_crash, &game_root)
                .unwrap()
                .is_empty()
        );

        let runner_extra = FakeCliRunner {
            vanilla_bytes: pck_bytes,
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::WriteUndeclaredFile,
            calls: RefCell::new(Vec::new()),
        };
        let cfg_extra = root.join("cfg-extra");
        assert_eq!(
            install_from_zip(
                &cfg_extra,
                &game_root,
                &zip_path,
                &root.join("stg-extra"),
                &mod_entry,
                std::slice::from_ref(&mod_entry),
                &runner_extra,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "restoreVerifyFailed"
        );
        assert_eq!(
            file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
            baseline
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l1_reconciles_steam_update_and_verify_integrity_without_overwriting() {
        let root = test_root("l1-steam");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        let config_dir = root.join("config");
        let staging_dir = root.join("staging");
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };

        install_from_zip(
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &mod_entry,
            std::slice::from_ref(&mod_entry),
            &runner,
            &UnlockedCheck,
        )
        .unwrap();

        let pck_path = pck_dir.join("Machine Party.pck");
        let updated_bytes = b"GDPC_NEW_STEAM_BUILD_2_2_0";
        fs::write(&pck_path, updated_bytes).unwrap();
        let updated_fp = file_fingerprint(&pck_path).unwrap();
        assert_eq!(
            reconcile_copy(
                &config_dir,
                &game_root,
                &mod_entry,
                Some(&staging_dir),
                &runner,
            )
            .unwrap(),
            ReconcileState::GameUpdatedOrModified
        );
        assert_eq!(
            uninstall_mod(&config_dir, &game_root, &mod_entry, &runner, &UnlockedCheck)
                .unwrap_err(),
            "gameUpdatedOrModified"
        );
        assert_eq!(file_fingerprint(&pck_path).unwrap(), updated_fp);

        fs::write(&pck_path, &pck_bytes).unwrap();
        assert_eq!(
            reconcile_copy(
                &config_dir,
                &game_root,
                &mod_entry,
                Some(&staging_dir),
                &runner,
            )
            .unwrap(),
            ReconcileState::ReconciledVanilla
        );
        assert!(
            inventory::installed_versions(&config_dir, &game_root)
                .unwrap()
                .is_empty()
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l1_adopts_valid_manual_install_and_rejects_mismatched_baseline() {
        let root = test_root("l1-adopt");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        let staging_dir = root.join("staging");
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };
        stage_package(
            &zip_path,
            &staging_dir,
            mod_entry.package.as_ref().unwrap(),
            mod_entry.adapter.as_ref().unwrap(),
            &pck_dir,
            &runner,
        )
        .unwrap();

        let mut patched = pck_bytes.clone();
        patched.extend_from_slice(b"OVERTIME_1_7");
        let pck_path = pck_dir.join("Machine Party.pck");
        fs::write(&pck_path, &patched).unwrap();
        let bad_restore = build_mp8r_restore(
            pck_bytes.len() as u64,
            patched.len() as u64,
            &"A".repeat(64),
            "v2.1.2",
            "overtime-1.7",
        );
        fs::write(pck_dir.join(RESTORE_DAT), bad_restore).unwrap();
        let config_dir = root.join("config");
        assert_eq!(
            reconcile_copy(
                &config_dir,
                &game_root,
                &mod_entry,
                Some(&staging_dir),
                &runner,
            )
            .unwrap(),
            ReconcileState::UnknownModification
        );
        assert_eq!(
            adopt_manual_install(&config_dir, &game_root, &staging_dir, &mod_entry, &runner)
                .unwrap_err(),
            "baselineMismatch"
        );

        let good_restore = build_mp8r_restore(
            pck_bytes.len() as u64,
            patched.len() as u64,
            &baseline.sha256.to_ascii_uppercase(),
            "v2.1.2",
            "overtime-1.7",
        );
        fs::write(pck_dir.join(RESTORE_DAT), good_restore).unwrap();
        let inspection = inspect_mod(
            &config_dir,
            &game_root,
            &mod_entry,
            Some(&staging_dir),
            &runner,
        )
        .unwrap();
        assert!(inspection.adoptable_manual_install);

        adopt_manual_install(&config_dir, &game_root, &staging_dir, &mod_entry, &runner).unwrap();
        let restored =
            uninstall_mod(&config_dir, &game_root, &mod_entry, &runner, &UnlockedCheck).unwrap();
        assert_eq!(restored, baseline);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l2_real_subprocess_delta_cli_install_and_offline_uninstall() {
        let root = test_root("l2-overtime-cli");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

        let cli_script = r#"#!/usr/bin/env python3
import hashlib, os, struct, sys

def read_arg(flag):
    if flag in sys.argv:
        i = sys.argv.index(flag)
        return sys.argv[i + 1]
    return ""

def dotnet_str(s):
    b = s.encode("utf-8")
    n = len(b)
    out = bytearray()
    while n >= 0x80:
        out.append((n & 0x7f) | 0x80)
        n >>= 7
    out.append(n)
    out.extend(b)
    return bytes(out)

if "--verify-package" in sys.argv:
    assert os.path.isfile("overtime_payload.zip")
    print("Payload OK: overtime-1.7 | scripts=70")
    sys.exit(0)

game_dir = read_arg("--game")
pck = os.path.join(game_dir, "Machine Party.pck")
restore = os.path.join(game_dir, "overtime_restore.dat")
data = open(pck, "rb").read()

if "--status" in sys.argv:
    if data.endswith(b"OVERTIME_1_7"):
        print("State:    Overtime overtime-1.7 installed")
    elif os.path.isfile(restore):
        print("State:    unrecognised")
    else:
        print("State:    vanilla (mod not installed)")
    sys.exit(0)

if "--uninstall" in sys.argv:
    raw = open(restore, "rb").read()
    magic, fmt, orig_len, patched_len = struct.unpack("<IIqq", raw[:24])
    assert magic == 0x3852504D and fmt == 2
    open(pck, "wb").write(data[:orig_len])
    os.remove(restore)
    print("Reverted to vanilla.")
    sys.exit(0)

sha = hashlib.sha256(data).hexdigest().upper()
patched = data + b"OVERTIME_1_7"
rec = bytearray(struct.pack("<IIqq", 0x3852504D, 2, len(data), len(patched)))
rec += dotnet_str(sha) + dotnet_str("v2.1.2") + dotnet_str("overtime-1.7")
rec += struct.pack("<i", 1)
rec += dotnet_str("res://scenes/lobby/scripts/lobby_scene.gdc")
rec += struct.pack("<QQ16sQQ16s", 160, 26, b"\x11"*16, len(data), 12, b"\x22"*16)
open(restore, "wb").write(rec)
open(pck, "wb").write(patched)
print("Done")
"#;
        let zip_bytes = make_fake_package_zip(cli_script.as_bytes(), b"SYNTHETIC_PAYLOAD");
        let zip_path = root.join("ot-l2.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let mut mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        mod_entry.adapter.as_mut().unwrap().run.interpreter = "bundled-python".into();
        let config_dir = root.join("config");
        let staging_dir = root.join("staging");

        let tx = install_from_zip(
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &mod_entry,
            std::slice::from_ref(&mod_entry),
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert_eq!(tx.status, TransactionStatus::Committed);
        assert!(pck_dir.join(RESTORE_DAT).is_file());

        fs::remove_dir_all(&staging_dir).unwrap();
        fs::remove_file(&zip_path).unwrap();

        let restored = uninstall_mod(
            &config_dir,
            &game_root,
            &mod_entry,
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert_eq!(restored, baseline);
        assert!(!pck_dir.join(RESTORE_DAT).exists());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l2_real_subprocess_python_patcher_uses_app_full_backup() {
        let root = test_root("l2-python-full-backup");
        let pck_bytes = build_synthetic_pck();
        let (game_root, _pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

        let py_script = r#"import os, sys
game_dir = sys.argv[sys.argv.index("--game-dir") + 1]
pck = os.path.join(game_dir, "Machine Party.pck")
data = open(pck, "rb").read()
if "--verify" in sys.argv:
    print("PATCHED" if data.endswith(b"B8P_V1_5") else "NOT PATCHED")
    sys.exit(0)
open(pck, "wb").write(data + b"B8P_V1_5")
print("Patched")
"#;
        let zip_bytes = build_test_zip(&[("install.py", py_script.as_bytes(), true)]);
        let zip_path = root.join("b8p.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();

        let mod_entry = ModEntry {
            id: "binary1936-8p".into(),
            order: 4,
            repo: "Binary1936/machine-party-8p".into(),
            version: Some("v1.5".into()),
            verified: true,
            package: Some(PackageSpec {
                asset_id: "520133712".into(),
                filename: "machine-party-8p-mod.zip".into(),
                size: zip_bytes.len() as u64,
                sha256: hex::encode(Sha256::digest(&zip_bytes)),
                mirror_approved: true,
            }),
            adapter: Some(AdapterProfile {
                kind: "upstream-cli".into(),
                platforms: vec!["windows".into()],
                target: "pckDir".into(),
                touches: vec!["Machine Party.pck".into()],
                exclusive: "pck".into(),
                baseline: BaselineSpec {
                    file: "Machine Party.pck".into(),
                    size: baseline.size,
                    sha256: baseline.sha256.clone(),
                },
                required_files: Vec::new(),
                verify_files: None,
                upstream_uninstall: false,
                run: RunSpec {
                    interpreter: "bundled-python".into(),
                    program: "install.py".into(),
                    common: vec!["--game-dir".into(), "{gameDir}".into()],
                },
                actions: ActionSpec {
                    preflight: vec![],
                    status: vec!["--verify".into()],
                    install: vec![],
                    uninstall: vec![],
                },
                status: StatusMatchers {
                    installed: r"^PATCHED$".into(),
                    vanilla: r"^NOT PATCHED$".into(),
                    older: None,
                },
                forbidden_args: vec!["--force".into()],
            }),
        };

        let config_dir = root.join("config");
        let staging_dir = root.join("staging");
        let tx = install_from_zip(
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &mod_entry,
            std::slice::from_ref(&mod_entry),
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert!(!tx.upstream_uninstall);
        assert!(tx.backup_dir.join("Machine Party.pck").is_file());

        fs::remove_dir_all(&staging_dir).unwrap();
        let restored = uninstall_mod(
            &config_dir,
            &game_root,
            &mod_entry,
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert_eq!(restored, baseline);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn l1_rejects_conflicting_mod_in_same_exclusive_group_and_zip_slip() {
        let root = test_root("l1-conflict-zipslip");
        let pck_bytes = build_synthetic_pck();
        let (game_root, _pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let overtime = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        let mut other = overtime.clone();
        other.id = "binary1936-8p".into();
        other.repo = "Binary1936/machine-party-8p".into();

        let config_dir = root.join("config");
        inventory::record_installed(&config_dir, &game_root, &other.repo, "v1.5").unwrap();
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes,
            vanilla_sha: baseline.sha256,
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };
        assert_eq!(
            install_from_zip(
                &config_dir,
                &game_root,
                &zip_path,
                &root.join("staging"),
                &overtime,
                &[overtime.clone(), other],
                &runner,
                &UnlockedCheck,
            )
            .unwrap_err(),
            "modConflict"
        );
        assert!(runner.calls.borrow().is_empty());

        let evil_zip = build_test_zip(&[("../outside.txt", b"bad", false)]);
        let evil_zip_path = root.join("evil.zip");
        fs::write(&evil_zip_path, &evil_zip).unwrap();
        assert_eq!(
            extract_zip(&evil_zip_path, &root.join("extract")).unwrap_err(),
            "packageCorrupt"
        );

        let slash_zip = build_test_zip(&[(r"mod\minigames\test.gd", b"ok", true)]);
        let slash_zip_path = root.join("slash.zip");
        fs::write(&slash_zip_path, &slash_zip).unwrap();
        let extract_dir = root.join("extract-ok");
        extract_zip(&slash_zip_path, &extract_dir).unwrap();
        assert_eq!(
            fs::read(extract_dir.join("mod").join("minigames").join("test.gd")).unwrap(),
            b"ok"
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn validates_game_copy_states_against_mod_list() {
        let root = test_root("validate-mods");
        let pck_bytes = build_synthetic_pck();
        let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
        let zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
        let zip_path = root.join("ot.zip");
        fs::write(&zip_path, &zip_bytes).unwrap();
        let mod_entry = synthetic_overtime_entry(&baseline, &zip_bytes, true);
        let mods = vec![mod_entry.clone()];
        let config_dir = root.join("config");
        let staging_dir = root.join("staging");
        let runner = FakeCliRunner {
            vanilla_bytes: pck_bytes.clone(),
            vanilla_sha: baseline.sha256.clone(),
            fault: FakeFault::None,
            calls: RefCell::new(Vec::new()),
        };

        PCK_READS.with(|n| n.set(0));
        scan_copy(&config_dir, &game_root, &mods, false).unwrap();
        assert_eq!(PCK_READS.with(|n| n.get()), 1);
        scan_copy(&config_dir, &game_root, &mods, false).unwrap();
        assert_eq!(
            PCK_READS.with(|n| n.get()),
            1,
            "warm restart only reads metadata"
        );
        scan_copy(&config_dir, &game_root, &mods, true).unwrap();
        assert_eq!(
            PCK_READS.with(|n| n.get()),
            2,
            "forced recheck reads the PCK once"
        );

        // 1. Clean vanilla copy
        let v1 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v1.pck_dir, pck_dir);
        assert_eq!(v1.pck_size, baseline.size);
        assert!(v1.installed.is_empty());
        assert_eq!(v1.mod_states["overtime"], "vanilla");

        fs::write(pck_dir.join(RESTORE_DAT), b"unknown residue").unwrap();
        let residue = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(residue.mod_states["overtime"], "restoreResidue");
        fs::remove_file(pck_dir.join(RESTORE_DAT)).unwrap();

        // 2. Installed copy
        install_from_zip(
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &mod_entry,
            &mods,
            &runner,
            &UnlockedCheck,
        )
        .unwrap();
        let v2 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v2.mod_states["overtime"], "installed");
        assert_eq!(v2.installed[&mod_entry.repo], "v1.7");

        // 3. Steam update replaces PCK
        let pck_path = pck_dir.join("Machine Party.pck");
        fs::write(&pck_path, b"GDPC_UPDATED_STEAM").unwrap();
        let v3 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v3.mod_states["overtime"], "gameUpdatedOrModified");

        // 4. A read-only scan hides the stale inventory entry but preserves recovery evidence.
        fs::write(&pck_path, &pck_bytes).unwrap();
        let _ = fs::remove_file(pck_dir.join(RESTORE_DAT));
        let v4 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v4.mod_states["overtime"], "vanilla");
        assert!(v4.installed.is_empty());

        // 5. A plausible MP8R alone cannot authorize adoption.
        let mut patched = pck_bytes.clone();
        patched.extend_from_slice(b"OVERTIME_1_7");
        fs::write(&pck_path, &patched).unwrap();
        let restore = build_mp8r_restore(
            pck_bytes.len() as u64,
            patched.len() as u64,
            &baseline.sha256.to_ascii_uppercase(),
            "v2.1.2",
            "overtime-1.7",
        );
        fs::write(pck_dir.join(RESTORE_DAT), restore).unwrap();
        assert!(
            get_transaction(&config_dir, &game_root, &mod_entry.id)
                .unwrap()
                .is_some()
        );
        clear_mod_records(&config_dir, &game_root, &mod_entry, None).unwrap();
        let v5 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v5.mod_states["overtime"], "identifyPending");

        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn windows_cli_has_no_console_and_running_game_is_detected_by_copy() {
        let root = tempfile::tempdir().unwrap();
        let req = CommandRequest {
            program: PathBuf::from("python"),
            args: vec![
                "-c".into(),
                "import ctypes; print(int(bool(ctypes.windll.kernel32.GetConsoleWindow())))".into(),
            ],
            cwd: root.path().to_owned(),
        };
        let out = SystemRunner.run(&req).unwrap();
        assert_eq!(out.code, 0);
        assert_eq!(out.stdout.trim(), "0");
        let source =
            PathBuf::from(std::env::var_os("SystemRoot").unwrap()).join("System32/cmd.exe");
        for copy in ["running", "idle"] {
            let dir = root.path().join(copy);
            fs::create_dir(&dir).unwrap();
            fs::copy(&source, dir.join("Machine Party.exe")).unwrap();
            fs::write(dir.join("Machine Party.pck"), b"copy").unwrap();
        }
        let running = root.path().join("running");
        let idle = root.path().join("idle");
        let mut child = Command::new(running.join("Machine Party.exe"))
            .args(["/D", "/Q", "/K"])
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .creation_flags(0x08000000)
            .spawn()
            .unwrap();
        let blocked =
            SystemGameLockCheck.ensure_unlocked(&running, &running.join("Machine Party.pck"));
        let allowed = SystemGameLockCheck.ensure_unlocked(&idle, &idle.join("Machine Party.pck"));
        child.kill().unwrap();
        child.wait().unwrap();
        assert_eq!(blocked.unwrap_err(), "gameRunning");
        allowed.unwrap();
    }

    #[test]
    fn l3_real_overtime_cli_and_real_vanilla_pck_when_available() {
        let (Ok(src_pck), Ok(src_zip)) = (std::env::var("MPM_L3_PCK"), std::env::var("MPM_L3_ZIP"))
        else {
            return;
        };
        let src_pck = PathBuf::from(src_pck);
        let src_zip = PathBuf::from(src_zip);
        assert!(src_pck.is_file(), "MPM_L3_PCK must exist");
        assert!(src_zip.is_file(), "MPM_L3_ZIP must exist");

        let root = test_root("l3-overtime-real");
        let game_root = root.join("party project");
        let pck_dir = game_root.join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        fs::write(pck_dir.join("Machine Party.exe"), b"MZ_L3").unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        fs::copy(&src_pck, &pck_path).unwrap();
        #[cfg(unix)]
        fs::set_permissions(&pck_path, fs::Permissions::from_mode(0o644)).unwrap();

        let overtime = crate::catalog::entry("overtime").expect("overtime entry present");
        let mods = vec![overtime.clone()];
        let config_dir = root.join("config");
        let staging_dir = root.join("staging");

        let v1 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v1.mod_states["overtime"], "vanilla");

        let tx = install_from_zip(
            &config_dir,
            &game_root,
            &src_zip,
            &staging_dir,
            &overtime,
            &mods,
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert_eq!(tx.status, TransactionStatus::Committed);

        let restore = parse_mp8r_restore(&pck_dir.join(RESTORE_DAT)).unwrap();
        let expected_sha = &overtime.adapter.as_ref().unwrap().baseline.sha256;
        assert_eq!(restore.format, 2);
        assert_eq!(restore.orig_len, 634_798_100);
        assert!(restore.base_sha.eq_ignore_ascii_case(expected_sha));
        assert_eq!(restore.game_ver, "v2.1.2");
        assert_eq!(restore.mod_tag, "overtime-1.7");
        assert_eq!(restore.entry_count, 70);

        let v2 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v2.mod_states["overtime"], "installed");
        assert_eq!(v2.installed["DarkJadeStone/MachineParty-Overtime"], "v1.7");

        // The very same bytes without manager records model an existing manual install.
        let manual = root.join("manual-config");
        let pkg = overtime.package.as_ref().unwrap();
        let cached = manual
            .join("packages")
            .join(&overtime.id)
            .join(&pkg.filename);
        copy_atomic(&src_zip, &cached).unwrap();
        let identified = validate_game_mods(&manual, &game_root, &mods).unwrap();
        assert_eq!(identified.mod_states["overtime"], "manualInstall");
        let adopted =
            adopt_manual_install(&manual, &game_root, &staging_dir, &overtime, &SystemRunner)
                .unwrap();
        assert_eq!(adopted.post_pck, tx.post_pck);
        assert_eq!(
            file_fingerprint(&adopted.backup_dir.join("Machine Party.pck")).unwrap(),
            tx.pre_pck
        );

        fs::remove_dir_all(&staging_dir).unwrap();
        fs::remove_file(pck_dir.join(RESTORE_DAT)).unwrap();

        let restored = uninstall_mod(
            &config_dir,
            &game_root,
            &overtime,
            &SystemRunner,
            &SystemGameLockCheck,
        )
        .unwrap();
        assert_eq!(restored.size, 634_798_100);
        assert_eq!(
            restored.sha256,
            "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"
        );

        let v3 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
        assert_eq!(v3.mod_states["overtime"], "vanilla");
        assert!(v3.installed.is_empty());

        fs::remove_dir_all(root).unwrap();
    }
}
