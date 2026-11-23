use std::{
    fs::File,
    io::{self, Cursor, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

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

#[derive(Clone)]
struct PckEntry {
    path: String,
    offset: u64,
    size: u64,
    md5: [u8; 16],
    flags: u32,
    pending_data: Option<Vec<u8>>,
}

pub(super) struct PckArchive {
    path: PathBuf,
    flags: u32,
    file_base: u64,
    pub(super) dir_offset: u64,
    pub(super) dir_field: u64,
    pub(super) dir_field_base: u64,
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
    pub(super) fn open(path: &Path) -> Result<Self, String> {
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

    pub(super) fn read_file(&self, res_path: &str) -> Result<Option<Vec<u8>>, String> {
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

    pub(super) fn put(&mut self, res_path: &str, data: Vec<u8>) {
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

    pub(super) fn append_patch_v3(&mut self) -> Result<u64, String> {
        let mut file = std::fs::OpenOptions::new()
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

pub(super) fn ecfg_parse(data: &[u8]) -> Result<Vec<(String, Vec<u8>)>, String> {
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

pub(super) fn ecfg_build(entries: &[(String, Vec<u8>)]) -> Vec<u8> {
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

pub(super) fn enc_godot_string(value: &str) -> Vec<u8> {
    let b = value.as_bytes();
    let mut out = Vec::with_capacity(8 + pad4_len(b.len()));
    out.extend_from_slice(&4u32.to_le_bytes());
    out.extend_from_slice(&(b.len() as u32).to_le_bytes());
    out.extend_from_slice(b);
    let pad = (4 - (out.len() % 4)) % 4;
    out.resize(out.len() + pad, 0);
    out
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
