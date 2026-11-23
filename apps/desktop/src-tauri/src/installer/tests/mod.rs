mod deps_tests;
mod loader_tests;
mod reconcile_and_restore_tests;
mod switch_and_conflict_tests;
mod upstream_cli_tests;

use std::{cell::RefCell, io::Write};

use flate2::{Compression, write::DeflateEncoder};
use sha2::{Digest, Sha256};

use super::adapters::MP8R_MAGIC;
use super::transaction::unique_suffix;
use super::*;
use crate::catalog::{
    ActionSpec, AdapterProfile, BaselineSpec, PackageSpec, RunSpec, StatusMatchers,
};

pub(super) fn test_root(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mpm-inst-{name}-{}", unique_suffix()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

pub(super) fn build_synthetic_pck() -> Vec<u8> {
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

pub(super) fn write_dotnet_string(buf: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    let mut len = bytes.len();
    while len >= 0x80 {
        buf.push(((len as u8) & 0x7f) | 0x80);
        len >>= 7;
    }
    buf.push(len as u8);
    buf.extend_from_slice(bytes);
}

pub(super) fn build_mp8r_restore(
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

pub(super) fn build_test_zip(entries: &[(&str, &[u8], bool)]) -> Vec<u8> {
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

pub(super) fn setup_synthetic_game(
    root: &Path,
    pck_bytes: &[u8],
) -> (PathBuf, PathBuf, FileFingerprint) {
    let game_root = root.join("party project");
    let pck_dir = game_root.join("Machine Party_Windows");
    fs::create_dir_all(&pck_dir).unwrap();
    fs::write(pck_dir.join("Machine Party.exe"), b"MZ_SYNTHETIC").unwrap();
    let pck_path = pck_dir.join("Machine Party.pck");
    fs::write(&pck_path, pck_bytes).unwrap();
    let fp = file_fingerprint(&pck_path).unwrap();
    (game_root, pck_dir, fp)
}

pub(super) fn synthetic_overtime_entry(
    baseline: &FileFingerprint,
    zip_bytes: &[u8],
    upstream_uninstall: bool,
) -> ModEntry {
    let zip_sha = hex::encode(Sha256::digest(zip_bytes));
    ModEntry {
        inventory_by_id: false,
        legacy_inventory_repos: Vec::new(),
        id: "overtime".into(),
        order: 1,
        repo: "DarkJadeStone/MachineParty-Overtime".into(),
        version: Some("v1.7".into()),
        verified: true,
        requires: Vec::new(),
        role: None,
        package: Some(PackageSpec {
            asset_id: "594522625".into(),
            filename: "Machine-Party-Overtime-1.7-CLI.zip".into(),
            size: zip_bytes.len() as u64,
            sha256: zip_sha,
            mirror_approved: true,
        }),
        adapter: Some(AdapterProfile {
            source_rule: None,
            conflict_group: None,
            kind: "upstream-cli".into(),
            platforms: vec!["windows".into()],
            target: "pckDir".into(),
            touches: if upstream_uninstall {
                vec!["Machine Party.pck".into(), RESTORE_DAT.into()]
            } else {
                vec!["Machine Party.pck".into()]
            },
            exclusive: "pck".into(),
            auto_loader: false,
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

pub(super) fn make_fake_package_zip(exe_bytes: &[u8], payload_bytes: &[u8]) -> Vec<u8> {
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

pub(super) fn make_loader_entry_from_catalog(
    id: &str,
    zip_bytes: &[u8],
    baseline: &FileFingerprint,
) -> ModEntry {
    let entry = crate::catalog::entry(id).unwrap();
    let mut entry = crate::catalog::legacy_entry(&entry).unwrap_or(entry);
    entry.verified = true;
    let pkg = entry.package.as_mut().unwrap();
    pkg.size = zip_bytes.len() as u64;
    pkg.sha256 = hex::encode(Sha256::digest(zip_bytes));
    entry.adapter.as_mut().unwrap().baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: baseline.size,
        sha256: baseline.sha256.clone(),
    };
    entry
}

pub(super) struct UnlockedCheck;
impl GameLockCheck for UnlockedCheck {
    fn ensure_unlocked(&self, _pck_dir: &Path, _pck_path: &Path) -> Result<(), String> {
        Ok(())
    }
}

pub(super) struct LockedCheck;
impl GameLockCheck for LockedCheck {
    fn ensure_unlocked(&self, _pck_dir: &Path, _pck_path: &Path) -> Result<(), String> {
        Err("gameRunning".into())
    }
}

pub(super) enum FakeFault {
    None,
    FailInstallMidWrite,
    WriteUndeclaredFile,
}

pub(super) struct FakeCliRunner {
    pub(super) vanilla_bytes: Vec<u8>,
    pub(super) vanilla_sha: String,
    pub(super) fault: FakeFault,
    pub(super) calls: RefCell<Vec<Vec<String>>>,
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
            } else if pck_path.is_file() && fs::read(&pck_path).unwrap().ends_with(b"OVERTIME_1_7")
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
