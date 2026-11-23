use std::{
    fs,
    io::{Cursor, Read},
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use regex::Regex;

use super::super::{
    runner::{CommandRequest, ProcessRunner},
    transaction::{DiskModState, copy_atomic, is_hex_sha256, is_safe_filename},
};
use crate::catalog::AdapterProfile;

pub const RESTORE_DAT: &str = "overtime_restore.dat";
#[cfg(test)]
pub const MP8R_MAGIC: u32 = 0x3852_504D;
#[cfg(not(test))]
const MP8R_MAGIC: u32 = 0x3852_504D;
const MAX_RESTORE_BYTES: u64 = 512 * 1024;

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
    if !matches!(adapter.kind.as_str(), "upstream-cli" | "loader-files")
        || adapter.target != "pckDir"
    {
        return Err("unsafeAdapter".into());
    }
    if let Some(rule) = &adapter.source_rule
        && (adapter.kind != "loader-files"
            || !matches!(
                rule.as_str(),
                "overtime-manifest-v1" | "binary-tree-v1" | "broadcast-tree-v1"
            )
            || adapter.verify_files.is_some())
    {
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
    if !adapter.required_files.iter().all(|f| is_safe_filename(f)) {
        return Err("unsafeAdapter".into());
    }
    if adapter.kind == "loader-files" {
        if adapter.touches != ["mods"]
            || adapter.required_files.is_empty()
            || adapter.upstream_uninstall
        {
            return Err("unsafeAdapter".into());
        }
        return Ok(());
    }
    if adapter.auto_loader {
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
            let python = if cfg!(windows) && bundled.is_file() {
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
    let state = parse_status(adapter, &out.stdout)?;
    if out.code != 0 && matches!(state, DiskModState::Unrecognized(_)) {
        return Err("statusUnavailable".into());
    }
    Ok(state)
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

pub fn uses_delta_restore(adapter: &AdapterProfile) -> bool {
    adapter.upstream_uninstall && adapter.touches.iter().any(|name| name == RESTORE_DAT)
}

pub fn mirror_delta_backup(
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
