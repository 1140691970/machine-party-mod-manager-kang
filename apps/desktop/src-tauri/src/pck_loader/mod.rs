mod gdpc;
#[cfg(test)]
mod tests;

use std::{
    fs::{self, File, OpenOptions},
    io::{self, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    catalog::BaselineSpec,
    installer::{self, FileFingerprint, file_fingerprint},
};

#[cfg(test)]
pub(crate) use gdpc::build_synthetic_pck_v3;
#[cfg(test)]
use gdpc::md5_digest;
use gdpc::{PckArchive, ecfg_build, ecfg_parse, enc_godot_string};

pub const LOADER_SIDECAR: &str = "Machine Party.pck.modloader.json";
pub const EXTERNAL_LOADER_EXE: &str = "MachinePartyModLoader.exe";
pub const MANAGED_BY: &str = "machine-party-mod-manager";
pub const LOADER_VERSION: &str = "6";

const BOOTSTRAP_SRC: &str = include_str!("../../assets/mpm_bootstrap.gd");

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

/// Loader state reported to the UI for a selected game copy.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LoaderStatus {
    pub kind: String,
    pub installed_version: Option<String>,
    pub target_version: String,
    pub needs_upgrade: bool,
    pub can_reload: bool,
}

// During an upgrade the PCK rename and marker rename cannot be one filesystem operation.
#[derive(Serialize, Deserialize)]
struct LoaderMarker {
    #[serde(flatten)]
    active: ManagedLoaderState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    previous: Option<ManagedLoaderState>,
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

/// Inspects the loader state for `pck_dir` without modifying any files.
pub fn inspect_loader(
    pck_dir: &Path,
    current_pck: &FileFingerprint,
) -> Result<LoaderStatus, String> {
    let target_version = LOADER_VERSION.to_string();
    if external_loader_present(pck_dir)? {
        return Ok(LoaderStatus {
            kind: "external".into(),
            installed_version: None,
            target_version,
            needs_upgrade: false,
            can_reload: false,
        });
    }
    let Some(marker) = read_managed_marker(pck_dir)? else {
        return Ok(LoaderStatus {
            kind: "none".into(),
            installed_version: None,
            target_version,
            needs_upgrade: false,
            can_reload: false,
        });
    };
    if current_pck.size != marker.patched_size
        || !current_pck
            .sha256
            .eq_ignore_ascii_case(&marker.patched_sha256)
    {
        return Ok(LoaderStatus {
            kind: "modified".into(),
            installed_version: Some(marker.loader_version),
            target_version,
            needs_upgrade: false,
            can_reload: false,
        });
    }
    let pck_path = pck_dir.join("Machine Party.pck");
    let bootstrap_matches = PckArchive::open(&pck_path)
        .ok()
        .and_then(|pck| pck.read_file(BOOTSTRAP_RES).ok().flatten())
        .is_some_and(|got| got == BOOTSTRAP_SRC.as_bytes());
    let needs_upgrade = marker.loader_version != LOADER_VERSION || !bootstrap_matches;
    Ok(LoaderStatus {
        kind: "managed".into(),
        installed_version: Some(marker.loader_version),
        target_version,
        needs_upgrade,
        can_reload: true,
    })
}

/// Ensures the built-in autoload bootstrap is injected into `Machine Party.pck`.
/// Leaves external MPML installations untouched (`Ok(None)`).
pub fn ensure_loader_installed(
    pck_dir: &Path,
    backup_pck: &Path,
    baseline: &BaselineSpec,
    before_write: impl FnOnce() -> Result<(), String>,
) -> Result<Option<ManagedLoaderState>, String> {
    ensure_loader_inner(pck_dir, backup_pck, baseline, false, before_write)
}

/// Reloads or upgrades an already-installed managed loader without touching any mods.
pub fn reload_managed_loader(
    pck_dir: &Path,
    backup_pck: &Path,
    baseline: &BaselineSpec,
    force: bool,
    before_write: impl FnOnce() -> Result<(), String>,
) -> Result<ManagedLoaderState, String> {
    if external_loader_present(pck_dir)? {
        return Err("externalLoaderPresent".into());
    }
    if read_managed_marker(pck_dir)?.is_none() {
        return Err("loaderNotInstalled".into());
    }
    ensure_loader_inner(pck_dir, backup_pck, baseline, force, before_write)?
        .ok_or_else(|| "externalLoaderPresent".into())
}

fn ensure_loader_inner(
    pck_dir: &Path,
    backup_pck: &Path,
    baseline: &BaselineSpec,
    force: bool,
    before_write: impl FnOnce() -> Result<(), String>,
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
        if !force && marker.loader_version == LOADER_VERSION && got_boot == BOOTSTRAP_SRC.as_bytes()
        {
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
    before_write()?;
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
    before_write: impl FnOnce() -> Result<(), String>,
) -> Result<FileFingerprint, String> {
    if external_loader_present(pck_dir)? {
        return Err("loaderConflict".into());
    }
    let state = read_managed_marker(pck_dir)?.ok_or_else(|| "missingTransaction".to_string())?;
    let pck_path = pck_dir.join("Machine Party.pck");
    let current = file_fingerprint(&pck_path)?;

    prepare_managed_restore(pck_dir, backup_pck, state, current)?.apply(before_write)
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
    pub(super) fn apply(
        self,
        before_write: impl FnOnce() -> Result<(), String>,
    ) -> Result<FileFingerprint, String> {
        let pck = self.pck_dir.join("Machine Party.pck");
        if external_loader_present(&self.pck_dir)?
            || read_managed_marker(&self.pck_dir)?.as_ref() != Some(&self.marker)
            || file_fingerprint(&pck)? != self.original
        {
            return Err("gameUpdatedOrModified".into());
        }
        before_write()?;
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
