use std::{
    fs::{self, File},
    io::{Read, Seek, SeekFrom},
    path::{Component, Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use flate2::read::DeflateDecoder;

use super::{
    adapters::{build_command, normalize_loader_staging, validate_adapter},
    prepare,
    runner::ProcessRunner,
    transaction::{file_fingerprint, is_hex_sha256, is_safe_filename, write_atomic},
};
use crate::catalog::{AdapterProfile, PackageSpec};

const MAX_ZIP_ENTRY_BYTES: u64 = 256 * 1024 * 1024;

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

pub(super) fn validate_rel_components(normalized: &str) -> Result<PathBuf, String> {
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

pub(super) fn verify_checksum_manifest(
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
    if let Some(rule) = &adapter.source_rule {
        prepare::from_source(rule, zip_path, staging_dir, &adapter.baseline)?;
    } else {
        extract_zip(zip_path, staging_dir).map_err(|e| {
            if e == "packageCorrupt" {
                format!("internalPackage: {}", pkg.filename)
            } else {
                e
            }
        })?;
    }
    if let Some(manifest) = &adapter.verify_files {
        verify_checksum_manifest(
            staging_dir,
            manifest,
            &adapter.run.program,
            &adapter.required_files,
        )
        .map_err(|_| format!("internalPackage: {manifest}"))?;
    } else if adapter.kind == "loader-files" {
        normalize_loader_staging(staging_dir)?;
        let manifest: serde_json::Value = serde_json::from_slice(
            &fs::read(staging_dir.join("mod.json")).map_err(|_| "packageCorrupt")?,
        )
        .map_err(|_| "packageCorrupt")?;
        let entry = manifest["entry"].as_str().ok_or("packageCorrupt")?;
        if manifest["id"].as_str().is_none_or(str::is_empty)
            || !staging_dir.join(validate_rel_components(entry)?).is_file()
        {
            return Err("packageCorrupt".into());
        }
        if !adapter
            .required_files
            .iter()
            .all(|file| staging_dir.join(file).is_file())
        {
            return Err("packageCorrupt".into());
        }
        return Ok(());
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
