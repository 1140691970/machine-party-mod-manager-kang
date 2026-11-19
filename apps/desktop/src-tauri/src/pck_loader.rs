use std::{
    fs::{self, File, OpenOptions},
    io::{self, Cursor, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    catalog::BaselineSpec,
    installer::{self, FileFingerprint, file_fingerprint},
};

pub const LOADER_SIDECAR: &str = "Machine Party.pck.modloader.json";
pub const EXTERNAL_LOADER_EXE: &str = "MachinePartyModLoader.exe";
pub const MANAGED_BY: &str = "machine-party-mod-manager";
pub const LOADER_VERSION: &str = "3";

const BOOTSTRAP_SRC: &str = include_str!("../assets/mpm_bootstrap.gd");
const PCK_MAGIC: &[u8; 4] = b"GDPC";
const ECFG_MAGIC: &[u8; 4] = b"ECFG";
const PACK_DIR_ENCRYPTED: u32 = 1 << 0;
const PACK_REL_FILEBASE: u32 = 1 << 1;

const OFF_FORMAT: usize = 4;
const OFF_VERSION: usize = 8;
const OFF_FLAGS: usize = 20;
const OFF_FILE_BASE: usize = 24;
const OFF_DIR_OFFSET: usize = 32;
const HEAD_SCAN_LIMIT: usize = 256;
const MAX_PCK_ENTRIES: u32 = 5_000_000;

const AUTOLOAD_KEY: &str = "autoload/ModLoader";
const AUTOLOAD_VALUE: &str = "*res://modloader/bootstrap.gd";
const BOOTSTRAP_RES: &str = "res://modloader/bootstrap.gd";
const STAMP_RES: &str = "res://modloader/.stamp";
const PROJECT_BINARY_RES: &str = "res://project.binary";

/// Persisted state written to `Machine Party.pck.modloader.json` for manager-owned PCK patches.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ManagedLoaderState {
    pub managed_by: String,
    pub loader_version: String,
    pub vanilla_dir_offset: u64,
    pub vanilla_size: u64,
    pub vanilla_sha256: String,
    pub dir_field: u64,
    pub dir_field_base: u64,
    pub patched_size: u64,
    pub patched_sha256: String,
}

// During an upgrade the PCK rename and marker rename cannot be one filesystem operation.
#[derive(Serialize, Deserialize)]
struct LoaderMarker {
    #[serde(flatten)]
    active: ManagedLoaderState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    previous: Option<ManagedLoaderState>,
}

#[derive(Clone)]
struct PckEntry {
    path: String,
    offset: u64,
    size: u64,
    md5: [u8; 16],
    flags: u32,
    pending_data: Option<Vec<u8>>,
}

struct PckArchive {
    path: PathBuf,
    flags: u32,
    file_base: u64,
    dir_offset: u64,
    dir_field: u64,
    dir_field_base: u64,
    dir_has_count: bool,
    res_prefix: bool,
    entries: Vec<PckEntry>,
}

/// Computes an RFC 1321 MD5 digest for Godot PCK directory entries.
pub fn md5_digest(input: &[u8]) -> [u8; 16] {
    const SHIFTS: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613,
        0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
        0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
        0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
        0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244,
        0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb,
        0xeb86d391,
    ];

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = input.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    let (mut a0, mut b0, mut c0, mut d0) = (0x67452301u32, 0xefcdab89, 0x98badcfe, 0x10325476);
    for chunk in msg.as_chunks::<64>().0 {
        let mut m = [0u32; 16];
        for (idx, word) in m.iter_mut().enumerate() {
            let off = idx * 4;
            *word =
                u32::from_le_bytes([chunk[off], chunk[off + 1], chunk[off + 2], chunk[off + 3]]);
        }
        let (mut a, mut b, mut c, mut d) = (a0, b0, c0, d0);
        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | ((!b) & d), i),
                16..=31 => ((d & b) | ((!d) & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | (!d)), (7 * i) % 16),
            };
            let sum = a.wrapping_add(f).wrapping_add(K[i]).wrapping_add(m[g]);
            a = d;
            d = c;
            c = b;
            b = b.wrapping_add(sum.rotate_left(SHIFTS[i]));
        }
        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }
    let mut out = [0u8; 16];
    out[0..4].copy_from_slice(&a0.to_le_bytes());
    out[4..8].copy_from_slice(&b0.to_le_bytes());
    out[8..12].copy_from_slice(&c0.to_le_bytes());
    out[12..16].copy_from_slice(&d0.to_le_bytes());
    out
}

fn pad4_len(len: usize) -> usize {
    len + ((4 - (len % 4)) % 4)
}

fn read_le_u32(slice: &[u8], off: usize) -> Option<u32> {
    let bytes: [u8; 4] = slice.get(off..off + 4)?.try_into().ok()?;
    Some(u32::from_le_bytes(bytes))
}

fn read_le_u64(slice: &[u8], off: usize) -> Option<u64> {
    let bytes: [u8; 8] = slice.get(off..off + 8)?.try_into().ok()?;
    Some(u64::from_le_bytes(bytes))
}

impl PckArchive {
    fn open(path: &Path) -> Result<Self, String> {
        let mut file = File::open(path).map_err(|_| "fileReadError".to_string())?;
        let filesize = file
            .metadata()
            .map_err(|_| "fileReadError".to_string())?
            .len();
        let head_len = usize::try_from(filesize.min(HEAD_SCAN_LIMIT as u64)).unwrap_or(0);
        let mut head = vec![0u8; head_len];
        file.read_exact(&mut head)
            .map_err(|_| "fileReadError".to_string())?;

        if head.get(..4) != Some(PCK_MAGIC) {
            return Err("gameUpdatedOrModified".into());
        }
        let fmt = read_le_u32(&head, OFF_FORMAT).ok_or("gameUpdatedOrModified")?;
        if fmt < 3 {
            return Err("gameUpdatedOrModified".into());
        }
        let _ver = (
            read_le_u32(&head, OFF_VERSION).ok_or("gameUpdatedOrModified")?,
            read_le_u32(&head, OFF_VERSION + 4).ok_or("gameUpdatedOrModified")?,
            read_le_u32(&head, OFF_VERSION + 8).ok_or("gameUpdatedOrModified")?,
        );
        let flags = read_le_u32(&head, OFF_FLAGS).ok_or("gameUpdatedOrModified")?;
        let file_base = read_le_u64(&head, OFF_FILE_BASE).ok_or("gameUpdatedOrModified")?;
        if flags & PACK_DIR_ENCRYPTED != 0 {
            return Err("gameUpdatedOrModified".into());
        }

        let rel = (flags & PACK_REL_FILEBASE) != 0;
        let mut fields = vec![OFF_DIR_OFFSET];
        for f in (24..112).step_by(8) {
            if f != OFF_DIR_OFFSET {
                fields.push(f);
            }
        }
        for field in fields {
            let Some(raw) = read_le_u64(&head, field) else {
                continue;
            };
            for base in [0u64, file_base] {
                let Some(target) = raw.checked_add(base) else {
                    continue;
                };
                if target <= file_base || target >= filesize {
                    continue;
                }
                for has_count in [true, false] {
                    if let Some(entries) = Self::parse_directory(
                        &mut file, filesize, file_base, rel, target, has_count,
                    )? {
                        let res_prefix = entries
                            .first()
                            .is_none_or(|first| first.path.starts_with("res://"));
                        return Ok(Self {
                            path: path.to_path_buf(),
                            flags,
                            file_base,
                            dir_offset: target,
                            dir_field: field as u64,
                            dir_field_base: base,
                            dir_has_count: has_count,
                            res_prefix,
                            entries,
                        });
                    }
                }
            }
        }
        Err("gameUpdatedOrModified".into())
    }

    fn parse_directory(
        file: &mut File,
        filesize: u64,
        file_base: u64,
        rel: bool,
        start: u64,
        has_count: bool,
    ) -> Result<Option<Vec<PckEntry>>, String> {
        let dir_len = filesize.saturating_sub(start);
        if dir_len == 0 || dir_len > 64 * 1024 * 1024 {
            return Ok(None);
        }
        file.seek(SeekFrom::Start(start))
            .map_err(|_| "fileReadError".to_string())?;
        let mut region = vec![0u8; usize::try_from(dir_len).map_err(|_| "fileReadError")?];
        file.read_exact(&mut region)
            .map_err(|_| "fileReadError".to_string())?;

        let mut pos = 0usize;
        let expected_count = if has_count {
            let Some(count) = read_le_u32(&region, 0) else {
                return Ok(None);
            };
            if count == 0 || count > MAX_PCK_ENTRIES {
                return Ok(None);
            }
            pos = 4;
            Some(count)
        } else {
            None
        };

        let mut entries = Vec::new();
        while pos < region.len() {
            if expected_count.is_some_and(|c| entries.len() >= c as usize) {
                break;
            }
            let Some(plen) = read_le_u32(&region, pos) else {
                return Ok(None);
            };
            pos += 4;
            if !(4..=4096).contains(&plen) || plen % 4 != 0 {
                return Ok(None);
            }
            let plen_usize = plen as usize;
            let Some(raw_path) = region.get(pos..pos + plen_usize) else {
                return Ok(None);
            };
            pos += plen_usize;
            let trimmed = match raw_path.iter().rposition(|&b| b != 0) {
                Some(last) => &raw_path[..=last],
                None => return Ok(None),
            };
            let Ok(path_str) = std::str::from_utf8(trimmed) else {
                return Ok(None);
            };
            if path_str.is_empty() {
                return Ok(None);
            }
            let (Some(off), Some(size)) =
                (read_le_u64(&region, pos), read_le_u64(&region, pos + 8))
            else {
                return Ok(None);
            };
            pos += 16;
            let Some(md5_slice) = region.get(pos..pos + 16) else {
                return Ok(None);
            };
            let mut md5 = [0u8; 16];
            md5.copy_from_slice(md5_slice);
            pos += 16;
            let Some(eflags) = read_le_u32(&region, pos) else {
                return Ok(None);
            };
            pos += 4;

            let abs_off = if rel {
                let Some(val) = off.checked_add(file_base) else {
                    return Ok(None);
                };
                val
            } else {
                off
            };
            let Some(end) = abs_off.checked_add(size) else {
                return Ok(None);
            };
            if end > filesize {
                return Ok(None);
            }
            entries.push(PckEntry {
                path: path_str.to_string(),
                offset: abs_off,
                size,
                md5,
                flags: eflags,
                pending_data: None,
            });
        }

        if entries.is_empty() || pos != region.len() {
            return Ok(None);
        }
        if expected_count.is_some_and(|c| entries.len() != c as usize) {
            return Ok(None);
        }
        Ok(Some(entries))
    }

    fn norm(&self, res_path: &str) -> String {
        match (self.res_prefix, res_path.strip_prefix("res://")) {
            (true, None) => format!("res://{res_path}"),
            (false, Some(bare)) => bare.to_string(),
            _ => res_path.to_string(),
        }
    }

    fn read_file(&self, res_path: &str) -> Result<Option<Vec<u8>>, String> {
        let key = self.norm(res_path);
        let Some(entry) = self.entries.iter().find(|e| e.path == key) else {
            return Ok(None);
        };
        if let Some(data) = &entry.pending_data {
            return Ok(Some(data.clone()));
        }
        let mut file = File::open(&self.path).map_err(|_| "fileReadError".to_string())?;
        file.seek(SeekFrom::Start(entry.offset))
            .map_err(|_| "fileReadError".to_string())?;
        let mut buf = vec![0u8; usize::try_from(entry.size).map_err(|_| "fileReadError")?];
        file.read_exact(&mut buf)
            .map_err(|_| "fileReadError".to_string())?;
        Ok(Some(buf))
    }

    fn put(&mut self, res_path: &str, data: Vec<u8>) {
        let key = self.norm(res_path);
        let md5 = md5_digest(&data);
        let size = data.len() as u64;
        if let Some(existing) = self.entries.iter_mut().find(|e| e.path == key) {
            existing.size = size;
            existing.md5 = md5;
            existing.pending_data = Some(data);
        } else {
            self.entries.push(PckEntry {
                path: key,
                offset: 0,
                size,
                md5,
                flags: 0,
                pending_data: Some(data),
            });
        }
    }

    fn encode_index(&self, sorted: &[&PckEntry]) -> Vec<u8> {
        let rel = (self.flags & PACK_REL_FILEBASE) != 0;
        let mut out = Vec::new();
        if self.dir_has_count {
            out.extend_from_slice(&(sorted.len() as u32).to_le_bytes());
        }
        for e in sorted {
            let pbytes = e.path.as_bytes();
            let padded_len = pad4_len(pbytes.len()).max(4);
            let stored_off = if rel {
                e.offset.saturating_sub(self.file_base)
            } else {
                e.offset
            };
            out.extend_from_slice(&(padded_len as u32).to_le_bytes());
            out.extend_from_slice(pbytes);
            out.resize(out.len() + (padded_len - pbytes.len()), 0);
            out.extend_from_slice(&stored_off.to_le_bytes());
            out.extend_from_slice(&e.size.to_le_bytes());
            out.extend_from_slice(&e.md5);
            out.extend_from_slice(&e.flags.to_le_bytes());
        }
        out
    }

    fn append_patch_v3(&mut self) -> Result<u64, String> {
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&self.path)
            .map_err(|e| match e.kind() {
                io::ErrorKind::PermissionDenied => "gamePermissionDenied".to_string(),
                _ => "fileWriteError".to_string(),
            })?;
        file.seek(SeekFrom::End(0))
            .map_err(|_| "fileWriteError".to_string())?;
        for entry in &mut self.entries {
            if let Some(data) = &entry.pending_data {
                entry.offset = file
                    .stream_position()
                    .map_err(|_| "fileWriteError".to_string())?;
                file.write_all(data)
                    .map_err(|_| "fileWriteError".to_string())?;
            }
        }
        let new_dir = file
            .stream_position()
            .map_err(|_| "fileWriteError".to_string())?;
        let mut sorted: Vec<&PckEntry> = self.entries.iter().collect();
        sorted.sort_by(|a, b| a.path.cmp(&b.path));
        let index = self.encode_index(&sorted);
        file.write_all(&index)
            .map_err(|_| "fileWriteError".to_string())?;
        file.flush().map_err(|_| "fileWriteError".to_string())?;

        let ptr = new_dir
            .checked_sub(self.dir_field_base)
            .ok_or("fileWriteError")?;
        file.seek(SeekFrom::Start(self.dir_field))
            .map_err(|_| "fileWriteError".to_string())?;
        file.write_all(&ptr.to_le_bytes())
            .map_err(|_| "fileWriteError".to_string())?;
        file.sync_all().map_err(|_| "fileWriteError".to_string())?;
        self.dir_offset = new_dir;
        Ok(new_dir)
    }
}

fn read_cursor_u32(cursor: &mut Cursor<&[u8]>) -> Result<u32, String> {
    let mut b = [0u8; 4];
    cursor
        .read_exact(&mut b)
        .map_err(|_| "gameUpdatedOrModified".to_string())?;
    Ok(u32::from_le_bytes(b))
}

fn ecfg_parse(data: &[u8]) -> Result<Vec<(String, Vec<u8>)>, String> {
    if data.get(..4) != Some(ECFG_MAGIC) {
        return Err("gameUpdatedOrModified".into());
    }
    let mut cursor = Cursor::new(&data[4..]);
    let count = read_cursor_u32(&mut cursor)?;
    let mut entries = Vec::with_capacity(count.min(4096) as usize);
    for _ in 0..count {
        let klen = read_cursor_u32(&mut cursor)? as usize;
        let mut key_bytes = vec![0u8; klen];
        cursor
            .read_exact(&mut key_bytes)
            .map_err(|_| "gameUpdatedOrModified".to_string())?;
        let key = String::from_utf8(key_bytes).map_err(|_| "gameUpdatedOrModified")?;
        let vlen = read_cursor_u32(&mut cursor)? as usize;
        let mut val_bytes = vec![0u8; vlen];
        cursor
            .read_exact(&mut val_bytes)
            .map_err(|_| "gameUpdatedOrModified".to_string())?;
        entries.push((key, val_bytes));
    }
    Ok(entries)
}

fn ecfg_build(entries: &[(String, Vec<u8>)]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(ECFG_MAGIC);
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    for (key, val) in entries {
        let kb = key.as_bytes();
        out.extend_from_slice(&(kb.len() as u32).to_le_bytes());
        out.extend_from_slice(kb);
        out.extend_from_slice(&(val.len() as u32).to_le_bytes());
        out.extend_from_slice(val);
    }
    out
}

fn enc_godot_string(value: &str) -> Vec<u8> {
    let b = value.as_bytes();
    let mut out = Vec::with_capacity(8 + pad4_len(b.len()));
    out.extend_from_slice(&4u32.to_le_bytes());
    out.extend_from_slice(&(b.len() as u32).to_le_bytes());
    out.extend_from_slice(b);
    let pad = (4 - (out.len() % 4)) % 4;
    out.resize(out.len() + pad, 0);
    out
}

fn sidecar_path(pck_dir: &Path) -> PathBuf {
    pck_dir.join(LOADER_SIDECAR)
}

/// Returns true if a non-manager external loader (`MachinePartyModLoader.exe` or unmanaged sidecar) exists.
pub fn external_loader_present(pck_dir: &Path) -> Result<bool, String> {
    if pck_dir
        .join(EXTERNAL_LOADER_EXE)
        .try_exists()
        .map_err(|_| "fileReadError")?
    {
        return Ok(true);
    }
    Ok(matches!(
        read_loader_sidecar(pck_dir)?,
        LoaderSidecar::External
    ))
}

enum LoaderSidecar {
    Missing,
    External,
    Managed(Box<LoaderMarker>),
}

fn read_loader_sidecar(pck_dir: &Path) -> Result<LoaderSidecar, String> {
    let bytes = match fs::read(sidecar_path(pck_dir)) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(LoaderSidecar::Missing),
        Err(_) => return Err("fileReadError".into()),
    };
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
        return Ok(LoaderSidecar::External);
    };
    if value.get("managed_by").and_then(|v| v.as_str()) != Some(MANAGED_BY) {
        return Ok(LoaderSidecar::External);
    }
    serde_json::from_value(value)
        .map(LoaderSidecar::Managed)
        .map_err(|_| "restoreCorrupt".into())
}

/// Returns our manager's recorded loader state when the sidecar is manager-owned.
pub fn read_managed_marker(pck_dir: &Path) -> Result<Option<ManagedLoaderState>, String> {
    let LoaderSidecar::Managed(marker) = read_loader_sidecar(pck_dir)? else {
        return Ok(None);
    };
    if let Some(previous) = marker.previous {
        let disk = file_fingerprint(&pck_dir.join("Machine Party.pck"))?;
        if previous.managed_by == MANAGED_BY
            && disk.size == previous.patched_size
            && disk.sha256.eq_ignore_ascii_case(&previous.patched_sha256)
        {
            return Ok(Some(previous));
        }
    }
    Ok(Some(marker.active))
}

fn truncate_and_restore_header(
    pck_path: &Path,
    dir_field: u64,
    dir_field_base: u64,
    vanilla_dir_offset: u64,
    vanilla_size: u64,
) -> Result<(), String> {
    let ptr = vanilla_dir_offset
        .checked_sub(dir_field_base)
        .ok_or("restoreCorrupt")?;
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(pck_path)
        .map_err(|e| match e.kind() {
            io::ErrorKind::PermissionDenied => "gamePermissionDenied".to_string(),
            _ => "fileWriteError".to_string(),
        })?;
    file.seek(SeekFrom::Start(dir_field))
        .map_err(|_| "fileWriteError".to_string())?;
    file.write_all(&ptr.to_le_bytes())
        .map_err(|_| "fileWriteError".to_string())?;
    file.flush().map_err(|_| "fileWriteError".to_string())?;
    file.set_len(vanilla_size)
        .map_err(|_| "fileWriteError".to_string())?;
    file.sync_all().map_err(|_| "fileWriteError".to_string())?;
    Ok(())
}

/// Ensures the built-in autoload bootstrap is injected into `Machine Party.pck`.
/// Leaves external MPML installations untouched (`Ok(None)`).
pub fn ensure_loader_installed(
    pck_dir: &Path,
    backup_pck: &Path,
    baseline: &BaselineSpec,
) -> Result<Option<ManagedLoaderState>, String> {
    if external_loader_present(pck_dir)? {
        return Ok(None);
    }
    let pck_path = pck_dir.join(&baseline.file);
    let current = file_fingerprint(&pck_path)?;
    let previous = read_managed_marker(pck_dir)?;
    let vanilla = if let Some(marker) = &previous {
        if current.size != marker.patched_size
            || !current.sha256.eq_ignore_ascii_case(&marker.patched_sha256)
        {
            return Err("gameUpdatedOrModified".into());
        }
        let check = PckArchive::open(&pck_path)?;
        let Some(got_boot) = check.read_file(BOOTSTRAP_RES)? else {
            return Err("gameUpdatedOrModified".into());
        };
        if got_boot == BOOTSTRAP_SRC.as_bytes() {
            return Ok(previous);
        }
        FileFingerprint {
            size: marker.vanilla_size,
            sha256: marker.vanilla_sha256.clone(),
        }
    } else {
        current.clone()
    };
    if vanilla.size != baseline.size || !vanilla.sha256.eq_ignore_ascii_case(&baseline.sha256) {
        return Err("baselineMismatch".into());
    }
    let candidate = stage_pck(&pck_path, &current)?;
    if let Some(marker) = &previous {
        restore_candidate(&candidate, backup_pck, marker)?;
    }
    let mut pck = PckArchive::open(&candidate)?;
    let Some(pb) = pck.read_file(PROJECT_BINARY_RES)? else {
        return Err("gameUpdatedOrModified".into());
    };
    let entries = ecfg_parse(&pb)?;
    let mut new_entries = vec![(AUTOLOAD_KEY.to_string(), enc_godot_string(AUTOLOAD_VALUE))];
    for (k, v) in entries {
        if k != AUTOLOAD_KEY {
            new_entries.push((k, v));
        }
    }

    let vanilla_dir_offset = pck.dir_offset;
    let vanilla_size = vanilla.size;
    let vanilla_sha256 = vanilla.sha256.clone();
    let dir_field = pck.dir_field;
    let dir_field_base = pck.dir_field_base;

    installer::copy_atomic(&candidate, backup_pck)?;
    if file_fingerprint(backup_pck)? != vanilla {
        return Err("fileWriteError".into());
    }

    let boot_hash = hex::encode(Sha256::digest(BOOTSTRAP_SRC.as_bytes()));
    let stamp = format!("{LOADER_VERSION}:{}", &boot_hash[..16]);
    pck.put(PROJECT_BINARY_RES, ecfg_build(&new_entries));
    pck.put(BOOTSTRAP_RES, BOOTSTRAP_SRC.as_bytes().to_vec());
    pck.put(STAMP_RES, stamp.into_bytes());

    pck.append_patch_v3()?;
    let verify = PckArchive::open(&candidate)?;
    let got_boot = verify.read_file(BOOTSTRAP_RES)?.ok_or("installFailed")?;
    let got_pb = verify
        .read_file(PROJECT_BINARY_RES)?
        .ok_or("installFailed")?;
    if got_boot != BOOTSTRAP_SRC.as_bytes()
        || ecfg_parse(&got_pb)?.first().map(|(k, _)| k.as_str()) != Some(AUTOLOAD_KEY)
    {
        return Err("installFailed".into());
    }
    let patched = file_fingerprint(&candidate)?;
    if file_fingerprint(&pck_path)? != current {
        return Err("gameUpdatedOrModified".into());
    }

    let state = ManagedLoaderState {
        managed_by: MANAGED_BY.into(),
        loader_version: LOADER_VERSION.into(),
        vanilla_dir_offset,
        vanilla_size,
        vanilla_sha256,
        dir_field,
        dir_field_base,
        patched_size: patched.size,
        patched_sha256: patched.sha256,
    };
    let state_bytes = serde_json::to_vec_pretty(&state).map_err(|_| "fileWriteError")?;
    let sidecar = sidecar_path(pck_dir);
    let marker_bytes = if previous.is_some() {
        let transition = LoaderMarker {
            active: state.clone(),
            previous,
        };
        Some(serde_json::to_vec_pretty(&transition).map_err(|_| "fileWriteError")?)
    } else {
        None
    };
    installer::write_atomic(&sidecar, marker_bytes.as_ref().unwrap_or(&state_bytes))?;
    candidate.persist(&pck_path).map_err(|_| "fileWriteError")?;
    if marker_bytes.is_some() {
        // Both fingerprints still work if only this compaction fails.
        let _ = installer::write_atomic(&sidecar, &state_bytes);
    }
    Ok(Some(state))
}

fn stage_pck(path: &Path, expected: &FileFingerprint) -> Result<tempfile::TempPath, String> {
    let dir = path.parent().ok_or("invalidGame")?;
    installer::check_space(dir, expected.size)?;
    let candidate = tempfile::NamedTempFile::new_in(dir)
        .map_err(|_| "fileWriteError")?
        .into_temp_path();
    fs::copy(path, &candidate).map_err(|_| "fileWriteError")?;
    if file_fingerprint(&candidate)? != *expected {
        return Err("gameUpdatedOrModified".into());
    }
    Ok(candidate)
}

/// Restores a manager-patched `Machine Party.pck` back to the exact original vanilla fingerprint.
pub fn restore_managed_loader(
    pck_dir: &Path,
    backup_pck: &Path,
) -> Result<FileFingerprint, String> {
    if external_loader_present(pck_dir)? {
        return Err("loaderConflict".into());
    }
    let state = read_managed_marker(pck_dir)?.ok_or_else(|| "missingTransaction".to_string())?;
    let pck_path = pck_dir.join("Machine Party.pck");
    let current = file_fingerprint(&pck_path)?;

    prepare_managed_restore(pck_dir, backup_pck, state, current)?.apply()
}

pub(super) struct PreparedRestore {
    pck_dir: PathBuf,
    marker: ManagedLoaderState,
    original: FileFingerprint,
    pub(super) restored: FileFingerprint,
    candidate: Option<tempfile::TempPath>,
}

pub(super) fn prepare_managed_restore(
    pck_dir: &Path,
    backup_pck: &Path,
    marker: ManagedLoaderState,
    current: FileFingerprint,
) -> Result<PreparedRestore, String> {
    let (candidate, restored) = if current.size == marker.vanilla_size
        && current.sha256.eq_ignore_ascii_case(&marker.vanilla_sha256)
    {
        (None, current.clone())
    } else {
        if current.size != marker.patched_size
            || !current.sha256.eq_ignore_ascii_case(&marker.patched_sha256)
        {
            return Err("gameUpdatedOrModified".into());
        }
        let candidate = stage_pck(&pck_dir.join("Machine Party.pck"), &current)?;
        let restored = restore_candidate(&candidate, backup_pck, &marker)?;
        (Some(candidate), restored)
    };
    Ok(PreparedRestore {
        pck_dir: pck_dir.to_owned(),
        marker,
        original: current,
        restored,
        candidate,
    })
}

impl PreparedRestore {
    pub(super) fn apply(self) -> Result<FileFingerprint, String> {
        let pck = self.pck_dir.join("Machine Party.pck");
        if external_loader_present(&self.pck_dir)?
            || read_managed_marker(&self.pck_dir)?.as_ref() != Some(&self.marker)
            || file_fingerprint(&pck)? != self.original
        {
            return Err("gameUpdatedOrModified".into());
        }
        if let Some(candidate) = self.candidate {
            candidate.persist(&pck).map_err(|_| "fileWriteError")?;
        }
        fs::remove_file(sidecar_path(&self.pck_dir)).map_err(|_| "fileWriteError")?;
        Ok(self.restored)
    }
}

fn restore_candidate(
    candidate: &Path,
    backup_pck: &Path,
    state: &ManagedLoaderState,
) -> Result<FileFingerprint, String> {
    if state.vanilla_dir_offset < state.dir_field_base || state.vanilla_size > state.patched_size {
        return Err("restoreCorrupt".into());
    }
    let truncated_ok = truncate_and_restore_header(
        candidate,
        state.dir_field,
        state.dir_field_base,
        state.vanilla_dir_offset,
        state.vanilla_size,
    )
    .is_ok();
    let mut restored = file_fingerprint(candidate)?;
    if (!truncated_ok
        || restored.size != state.vanilla_size
        || !restored.sha256.eq_ignore_ascii_case(&state.vanilla_sha256))
        && backup_pck.is_file()
    {
        let backup_fp = file_fingerprint(backup_pck)?;
        if backup_fp.size == state.vanilla_size
            && backup_fp.sha256.eq_ignore_ascii_case(&state.vanilla_sha256)
        {
            fs::copy(backup_pck, candidate).map_err(|_| "fileWriteError")?;
            File::options()
                .write(true)
                .open(candidate)
                .and_then(|f| f.sync_all())
                .map_err(|_| "fileWriteError")?;
            restored = file_fingerprint(candidate)?;
        }
    }

    if restored.size != state.vanilla_size
        || !restored.sha256.eq_ignore_ascii_case(&state.vanilla_sha256)
    {
        return Err("restoreVerifyFailed".into());
    }

    Ok(restored)
}

#[cfg(test)]
pub(crate) fn build_synthetic_pck_v3(res_prefix: bool, rel_filebase: bool) -> Vec<u8> {
    fn encode_godot_str(s: &str) -> Vec<u8> {
        enc_godot_string(s)
    }

    let pb_bytes = ecfg_build(&[
        (
            "autoload/Globals".to_string(),
            encode_godot_str("*res://autoloads/globals.gd"),
        ),
        (
            "application/config/name".to_string(),
            encode_godot_str("Machine Party"),
        ),
    ]);
    let other_bytes = b"extends Node\n".to_vec();
    let pb_path = if res_prefix {
        "res://project.binary"
    } else {
        "project.binary"
    };
    let other_path = if res_prefix {
        "res://autoloads/globals.gd"
    } else {
        "autoloads/globals.gd"
    };

    let file_base = 112u64;
    let flags = if rel_filebase { PACK_REL_FILEBASE } else { 0 };
    let mut out = vec![0u8; file_base as usize];
    out[0..4].copy_from_slice(PCK_MAGIC);
    out[OFF_FORMAT..OFF_FORMAT + 4].copy_from_slice(&3u32.to_le_bytes());
    out[OFF_VERSION..OFF_VERSION + 4].copy_from_slice(&4u32.to_le_bytes());
    out[OFF_VERSION + 4..OFF_VERSION + 8].copy_from_slice(&5u32.to_le_bytes());
    out[OFF_VERSION + 8..OFF_VERSION + 12].copy_from_slice(&2u32.to_le_bytes());
    out[OFF_FLAGS..OFF_FLAGS + 4].copy_from_slice(&flags.to_le_bytes());
    out[OFF_FILE_BASE..OFF_FILE_BASE + 8].copy_from_slice(&file_base.to_le_bytes());

    let off1 = out.len() as u64;
    out.extend_from_slice(&other_bytes);
    let off2 = out.len() as u64;
    out.extend_from_slice(&pb_bytes);
    let dir_offset = out.len() as u64;
    out[OFF_DIR_OFFSET..OFF_DIR_OFFSET + 8].copy_from_slice(&dir_offset.to_le_bytes());

    let e1 = PckEntry {
        path: other_path.into(),
        offset: off1,
        size: other_bytes.len() as u64,
        md5: md5_digest(&other_bytes),
        flags: 0,
        pending_data: None,
    };
    let e2 = PckEntry {
        path: pb_path.into(),
        offset: off2,
        size: pb_bytes.len() as u64,
        md5: md5_digest(&pb_bytes),
        flags: 0,
        pending_data: None,
    };
    let archive = PckArchive {
        path: PathBuf::new(),
        flags,
        file_base,
        dir_offset,
        dir_field: OFF_DIR_OFFSET as u64,
        dir_field_base: 0,
        dir_has_count: true,
        res_prefix,
        entries: Vec::new(),
    };
    let sorted = [&e1, &e2];
    out.extend_from_slice(&archive.encode_index(&sorted));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn md5_matches_rfc1321_vectors() {
        assert_eq!(
            hex::encode(md5_digest(b"")),
            "d41d8cd98f00b204e9800998ecf8427e"
        );
        assert_eq!(
            hex::encode(md5_digest(b"abc")),
            "900150983cd24fb0d6963f7d28e17f72"
        );
        assert_eq!(
            hex::encode(md5_digest(b"message digest")),
            "f96b697d7cb7938d525a2f31aaf161d0"
        );
    }

    #[test]
    fn pck_v3_patch_is_idempotent_and_restores_exact_vanilla_hash() {
        for (res_prefix, rel_filebase) in [(false, true), (true, false)] {
            let tmp = tempfile::tempdir().unwrap();
            let pck_dir = tmp.path().join("Machine Party_Windows");
            fs::create_dir_all(&pck_dir).unwrap();
            let pck_path = pck_dir.join("Machine Party.pck");
            let vanilla_bytes = build_synthetic_pck_v3(res_prefix, rel_filebase);
            fs::write(&pck_path, &vanilla_bytes).unwrap();
            let vanilla_fp = file_fingerprint(&pck_path).unwrap();
            let baseline = BaselineSpec {
                file: "Machine Party.pck".into(),
                size: vanilla_fp.size,
                sha256: vanilla_fp.sha256.clone(),
            };
            let backup_pck = tmp.path().join("backup.pck");

            let state = ensure_loader_installed(&pck_dir, &backup_pck, &baseline)
                .unwrap()
                .expect("managed loader state created");
            assert_eq!(state.vanilla_sha256, vanilla_fp.sha256);
            assert!(state.patched_size > state.vanilla_size);
            assert!(!external_loader_present(&pck_dir).unwrap());
            assert_eq!(read_managed_marker(&pck_dir).unwrap(), Some(state.clone()));

            // Verify patched PCK reads back autoload first & bootstrap script intact
            let parsed = PckArchive::open(&pck_path).unwrap();
            assert_eq!(
                parsed.read_file(BOOTSTRAP_RES).unwrap().as_deref(),
                Some(BOOTSTRAP_SRC.as_bytes())
            );
            let pb = ecfg_parse(&parsed.read_file(PROJECT_BINARY_RES).unwrap().unwrap()).unwrap();
            assert_eq!(pb[0].0, AUTOLOAD_KEY);
            assert_eq!(pb[1].0, "autoload/Globals");

            // Idempotent re-run must not append twice
            let state2 = ensure_loader_installed(&pck_dir, &backup_pck, &baseline)
                .unwrap()
                .unwrap();
            assert_eq!(state2, state);
            assert_eq!(
                file_fingerprint(&pck_path).unwrap().size,
                state.patched_size
            );

            // Lossless restore returns exact byte size and SHA-256
            let restored = restore_managed_loader(&pck_dir, &backup_pck).unwrap();
            assert_eq!(restored, vanilla_fp);
            assert_eq!(fs::read(&pck_path).unwrap(), vanilla_bytes);
            assert!(!sidecar_path(&pck_dir).exists());
        }
    }

    #[test]
    fn malformed_manager_record_is_not_treated_as_an_external_loader() {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path();
        let record = sidecar_path(dir);
        fs::write(
            &record,
            br#"{"managed_by":"machine-party-mod-manager","patched_size":"broken"}"#,
        )
        .unwrap();
        assert_eq!(external_loader_present(dir).unwrap_err(), "restoreCorrupt");
        assert_eq!(read_managed_marker(dir).unwrap_err(), "restoreCorrupt");
        fs::write(&record, br#"{"managed_by":"another-loader"}"#).unwrap();
        assert!(external_loader_present(dir).unwrap());
        assert!(read_managed_marker(dir).unwrap().is_none());
    }

    #[test]
    fn invalid_restore_data_leaves_the_installed_pck_intact() {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path();
        let pck = dir.join("Machine Party.pck");
        fs::write(&pck, build_synthetic_pck_v3(false, true)).unwrap();
        let vanilla = file_fingerprint(&pck).unwrap();
        let baseline = BaselineSpec {
            file: "Machine Party.pck".into(),
            size: vanilla.size,
            sha256: vanilla.sha256,
        };
        let backup = dir.join("backup.pck");
        let mut marker = ensure_loader_installed(dir, &backup, &baseline)
            .unwrap()
            .unwrap();
        let installed = fs::read(&pck).unwrap();
        marker.dir_field += 1;
        fs::write(sidecar_path(dir), serde_json::to_vec(&marker).unwrap()).unwrap();
        fs::write(&backup, b"incomplete backup").unwrap();
        assert_eq!(
            restore_managed_loader(dir, &backup).unwrap_err(),
            "restoreVerifyFailed"
        );
        assert_eq!(fs::read(&pck).unwrap(), installed);
        assert_eq!(read_managed_marker(dir).unwrap(), Some(marker));
    }

    #[test]
    fn steam_update_rejects_managed_restore() {
        let tmp = tempfile::tempdir().unwrap();
        let pck_dir = tmp.path().join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        let vanilla = build_synthetic_pck_v3(false, true);
        fs::write(&pck_path, &vanilla).unwrap();
        let fp = file_fingerprint(&pck_path).unwrap();
        let baseline = BaselineSpec {
            file: "Machine Party.pck".into(),
            size: fp.size,
            sha256: fp.sha256,
        };
        let backup_pck = tmp.path().join("backup.pck");
        ensure_loader_installed(&pck_dir, &backup_pck, &baseline).unwrap();

        fs::write(&pck_path, b"STEAM_UPDATED_PCK").unwrap();
        assert_eq!(
            restore_managed_loader(&pck_dir, &backup_pck).unwrap_err(),
            "gameUpdatedOrModified"
        );
        assert_eq!(
            ensure_loader_installed(&pck_dir, &backup_pck, &baseline).unwrap_err(),
            "gameUpdatedOrModified"
        );
    }

    #[test]
    fn external_loader_is_detected_and_left_untouched() {
        let tmp = tempfile::tempdir().unwrap();
        let pck_dir = tmp.path().join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        fs::write(&pck_path, build_synthetic_pck_v3(false, true)).unwrap();
        fs::write(pck_dir.join(EXTERNAL_LOADER_EXE), b"MZ").unwrap();
        let fp = file_fingerprint(&pck_path).unwrap();
        let baseline = BaselineSpec {
            file: "Machine Party.pck".into(),
            size: fp.size,
            sha256: fp.sha256,
        };
        let backup_pck = tmp.path().join("backup.pck");
        assert!(external_loader_present(&pck_dir).unwrap());
        assert_eq!(
            ensure_loader_installed(&pck_dir, &backup_pck, &baseline).unwrap(),
            None
        );
        assert!(!backup_pck.exists());
    }

    #[test]
    fn ensure_loader_upgrades_older_managed_bootstrap() {
        let tmp = tempfile::tempdir().unwrap();
        let pck_dir = tmp.path().join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        let vanilla_bytes = build_synthetic_pck_v3(false, true);
        fs::write(&pck_path, &vanilla_bytes).unwrap();
        let vanilla_fp = file_fingerprint(&pck_path).unwrap();
        let baseline = BaselineSpec {
            file: "Machine Party.pck".into(),
            size: vanilla_fp.size,
            sha256: vanilla_fp.sha256.clone(),
        };
        let backup_pck = tmp.path().join("backup.pck");

        // Simulate an older manager-owned patch whose bootstrap differs from BOOTSTRAP_SRC.
        let mut old_pck = PckArchive::open(&pck_path).unwrap();
        let vanilla_dir_offset = old_pck.dir_offset;
        let dir_field = old_pck.dir_field;
        let dir_field_base = old_pck.dir_field_base;
        let old_boot = b"extends Node\n# old bootstrap\n".to_vec();
        old_pck.put(BOOTSTRAP_RES, old_boot);
        old_pck.append_patch_v3().unwrap();
        let old_patched = file_fingerprint(&pck_path).unwrap();
        let old_marker = ManagedLoaderState {
            managed_by: MANAGED_BY.into(),
            loader_version: "2".into(),
            vanilla_dir_offset,
            vanilla_size: vanilla_fp.size,
            vanilla_sha256: vanilla_fp.sha256.clone(),
            dir_field,
            dir_field_base,
            patched_size: old_patched.size,
            patched_sha256: old_patched.sha256.clone(),
        };
        installer::write_atomic(
            &sidecar_path(&pck_dir),
            &serde_json::to_vec_pretty(&old_marker).unwrap(),
        )
        .unwrap();

        // A failed backup write must leave the previous bootstrap available to its mods.
        fs::create_dir(&backup_pck).unwrap();
        assert_eq!(
            ensure_loader_installed(&pck_dir, &backup_pck, &baseline).unwrap_err(),
            "fileWriteError"
        );
        assert_eq!(file_fingerprint(&pck_path).unwrap(), old_patched);
        assert_eq!(
            read_managed_marker(&pck_dir).unwrap().as_ref(),
            Some(&old_marker)
        );
        fs::remove_dir(&backup_pck).unwrap();
        let old_bytes = fs::read(&pck_path).unwrap();
        let upgraded = ensure_loader_installed(&pck_dir, &backup_pck, &baseline)
            .unwrap()
            .expect("upgraded loader marker created");
        assert_eq!(upgraded.loader_version, LOADER_VERSION);
        assert_eq!(upgraded.vanilla_sha256, vanilla_fp.sha256);

        let parsed = PckArchive::open(&pck_path).unwrap();
        assert_eq!(
            parsed.read_file(BOOTSTRAP_RES).unwrap().as_deref(),
            Some(BOOTSTRAP_SRC.as_bytes())
        );
        // Model both crash boundaries of publishing the new PCK while the dual marker exists.
        let new_bytes = fs::read(&pck_path).unwrap();
        let transition = LoaderMarker {
            active: upgraded.clone(),
            previous: Some(old_marker.clone()),
        };
        fs::write(
            sidecar_path(&pck_dir),
            serde_json::to_vec(&transition).unwrap(),
        )
        .unwrap();
        fs::write(&pck_path, old_bytes).unwrap();
        assert_eq!(read_managed_marker(&pck_dir).unwrap(), Some(old_marker));
        fs::write(&pck_path, new_bytes).unwrap();
        assert_eq!(read_managed_marker(&pck_dir).unwrap(), Some(upgraded));
        let restored = restore_managed_loader(&pck_dir, &backup_pck).unwrap();
        assert_eq!(restored, vanilla_fp);
    }

    #[test]
    fn l3_real_vanilla_pck_auto_loader_when_env_set() {
        let Some(src_pck) = std::env::var_os("MPM_L3_VANILLA_PCK").map(PathBuf::from) else {
            return;
        };
        if !src_pck.is_file() {
            return;
        }
        let tmp = tempfile::tempdir().unwrap();
        let pck_dir = tmp.path().join("Machine Party_Windows");
        fs::create_dir_all(&pck_dir).unwrap();
        let pck_path = pck_dir.join("Machine Party.pck");
        installer::copy_atomic(&src_pck, &pck_path).unwrap();

        let vanilla_fp = file_fingerprint(&pck_path).unwrap();
        assert_eq!(vanilla_fp.size, 634_798_100);
        assert_eq!(
            vanilla_fp.sha256,
            "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"
        );
        let baseline = BaselineSpec {
            file: "Machine Party.pck".into(),
            size: vanilla_fp.size,
            sha256: vanilla_fp.sha256.clone(),
        };
        let backup_pck = tmp.path().join("backup.pck");

        let state = ensure_loader_installed(&pck_dir, &backup_pck, &baseline)
            .unwrap()
            .expect("managed loader applied to v2.1.2 PCK");
        assert_eq!(state.vanilla_sha256, vanilla_fp.sha256);

        let parsed = PckArchive::open(&pck_path).unwrap();
        let guard: serde_json::Value =
            serde_json::from_str(include_str!("../assets/recipes/overtime/vanilla_md5.json"))
                .unwrap();
        for (path, expected) in guard["files"].as_object().unwrap() {
            let original = parsed.read_file(path).unwrap().unwrap();
            assert_eq!(
                hex::encode(md5_digest(&original)),
                expected.as_str().unwrap(),
                "{path}"
            );
        }
        let pb = ecfg_parse(&parsed.read_file(PROJECT_BINARY_RES).unwrap().unwrap()).unwrap();
        assert_eq!(pb[0].0, AUTOLOAD_KEY);
        assert_eq!(
            parsed.read_file(BOOTSTRAP_RES).unwrap().as_deref(),
            Some(BOOTSTRAP_SRC.as_bytes())
        );

        let restored = restore_managed_loader(&pck_dir, &backup_pck).unwrap();
        assert_eq!(restored, vanilla_fp);
        assert!(!sidecar_path(&pck_dir).exists());
    }
}
