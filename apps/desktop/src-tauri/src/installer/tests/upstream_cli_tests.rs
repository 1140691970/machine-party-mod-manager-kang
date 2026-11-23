#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(windows)]
use std::{
    os::windows::process::CommandExt,
    process::{Command, Stdio},
};

use super::*;

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
    if data.endswith(b"B8P_V1_5"):
        print("  PATCHED - all mod files present")
        sys.exit(0)
    print("  NOT PATCHED - this is the original game.")
    sys.exit(1)
if input("  Proceed? [y/N] ").strip().lower() != "y":
    sys.exit(2)
open(pck, "wb").write(data + b"B8P_V1_5")
print("Patched")
"#;
    let zip_bytes = build_test_zip(&[("install.py", py_script.as_bytes(), true)]);
    let zip_path = root.join("b8p.zip");
    fs::write(&zip_path, &zip_bytes).unwrap();

    let mod_entry = ModEntry {
        inventory_by_id: false,
        legacy_inventory_repos: Vec::new(),
        id: "binary1936-8p".into(),
        order: 4,
        repo: "Binary1936/machine-party-8p".into(),
        version: Some("v1.5".into()),
        verified: true,
        requires: Vec::new(),
        role: None,
        package: Some(PackageSpec {
            asset_id: "520133712".into(),
            filename: "machine-party-8p-mod.zip".into(),
            size: zip_bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&zip_bytes)),
            mirror_approved: true,
        }),
        adapter: Some(AdapterProfile {
            source_rule: None,
            conflict_group: None,
            kind: "upstream-cli".into(),
            platforms: vec!["windows".into()],
            target: "pckDir".into(),
            touches: vec!["Machine Party.pck".into()],
            exclusive: "pck".into(),
            auto_loader: false,
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
                installed: r"^\s*PATCHED\b".into(),
                vanilla: r"^\s*NOT PATCHED\b".into(),
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
    let source = PathBuf::from(std::env::var_os("SystemRoot").unwrap()).join("System32/cmd.exe");
    for copy in ["running", "idle"] {
        let dir = root.path().join(copy);
        fs::create_dir(&dir).unwrap();
        fs::write(dir.join("Machine Party.pck"), b"copy").unwrap();
    }
    let running = root.path().join("running");
    let idle = root.path().join("idle");
    fs::copy(&source, running.join("Machine Party.exe")).unwrap();
    fs::hard_link(
        running.join("Machine Party.exe"),
        idle.join("Machine Party.exe"),
    )
    .unwrap();
    let mut child = Command::new(running.join("Machine Party.exe"))
        .args(["/D", "/Q", "/K"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .creation_flags(0x08000000)
        .spawn()
        .unwrap();
    let blocked = SystemGameLockCheck.ensure_unlocked(&running, &running.join("Machine Party.pck"));
    let allowed = SystemGameLockCheck.ensure_unlocked(&idle, &idle.join("Machine Party.pck"));
    assert!(!game::process::apply(&idle, game::ProcessAction::Close).unwrap());
    assert!(!game::process::apply(&idle, game::ProcessAction::Force).unwrap());
    assert!(child.try_wait().unwrap().is_none());
    // This fixture has no window and can only be closed by the explicit force action.
    assert!(game::process::apply(&running, game::ProcessAction::Close).unwrap());
    game::process::apply(&running, game::ProcessAction::Force).unwrap();
    child.wait().unwrap();
    assert!(!game::process::apply(&running, game::ProcessAction::Check).unwrap());
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

    let src_bytes = fs::read(&src_zip).unwrap();
    let src_fp = file_fingerprint(&src_pck).unwrap();
    let mut overtime = synthetic_overtime_entry(&src_fp, &src_bytes, true);
    overtime.package.as_mut().unwrap().asset_id = "594522625".into();
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
        adopt_manual_install(&manual, &game_root, &staging_dir, &overtime, &SystemRunner).unwrap();
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
