use super::*;

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
fn l1_powershell_patcher_installs_and_removes_backup_sidecar_on_uninstall() {
    let root = test_root("l1-ps-patcher");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
    let zip_bytes = build_test_zip(&[("patcher.ps1", b"# ps", true)]);
    let zip_path = root.join("broadcast.zip");
    fs::write(&zip_path, &zip_bytes).unwrap();

    let broadcast = ModEntry {
        inventory_by_id: false,
        legacy_inventory_repos: Vec::new(),
        id: "broadcast-8p-freecam".into(),
        order: 3,
        repo: "Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher".into(),
        version: Some("v0.91".into()),
        verified: true,
        requires: Vec::new(),
        role: None,
        package: Some(PackageSpec {
            asset_id: "517871491".into(),
            filename: "MachineParty_Broadcast8P_Freecam_OneClick_Patcher_v0_91_BuiltIn120Fps.zip"
                .into(),
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
            touches: vec![
                "Machine Party.pck".into(),
                "Machine Party.pck.broadcast_backup".into(),
            ],
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
                interpreter: "powershell".into(),
                program: "patcher.ps1".into(),
                common: vec!["-GameDir".into(), "{gameDir}".into()],
            },
            actions: ActionSpec {
                preflight: vec![],
                status: vec!["-Action".into(), "verify".into()],
                install: vec!["-Action".into(), "install".into()],
                uninstall: vec!["-Action".into(), "uninstall".into()],
            },
            status: StatusMatchers {
                installed: r"^State:\s+patched$".into(),
                vanilla: r"^State:\s+clean$".into(),
                older: None,
            },
            forbidden_args: vec!["--force".into()],
        }),
    };

    struct FakePsRunner {
        vanilla_sha: String,
    }
    impl ProcessRunner for FakePsRunner {
        fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String> {
            let idx = req
                .args
                .iter()
                .position(|a| a == "-GameDir")
                .expect("-GameDir passed");
            let dir = PathBuf::from(&req.args[idx + 1]);
            let pck = dir.join("Machine Party.pck");
            let action_idx = req
                .args
                .iter()
                .position(|a| a == "-Action")
                .expect("-Action passed");
            match req.args[action_idx + 1].as_str() {
                "verify" => {
                    let fp = file_fingerprint(&pck)?;
                    let state = if fp.sha256 == self.vanilla_sha {
                        "State: clean\n"
                    } else {
                        "State: patched\n"
                    };
                    Ok(CommandOutput {
                        code: 0,
                        stdout: state.into(),
                        stderr: String::new(),
                    })
                }
                "install" => {
                    let orig = fs::read(&pck).unwrap();
                    fs::write(dir.join("Machine Party.pck.broadcast_backup"), &orig).unwrap();
                    let mut patched = orig;
                    patched.extend_from_slice(b"BROADCAST");
                    fs::write(&pck, patched).unwrap();
                    Ok(CommandOutput {
                        code: 0,
                        stdout: "Installed.\n".into(),
                        stderr: String::new(),
                    })
                }
                other => panic!("unexpected action {other}"),
            }
        }
    }

    let config_dir = root.join("config");
    let staging_dir = root.join("staging");
    let runner = FakePsRunner {
        vanilla_sha: baseline.sha256.clone(),
    };
    let mods = vec![broadcast.clone()];
    let tx = install_from_zip(
        &config_dir,
        &game_root,
        &zip_path,
        &staging_dir,
        &broadcast,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(tx.status, TransactionStatus::Committed);
    assert!(pck_dir.join("Machine Party.pck.broadcast_backup").is_file());

    let v1 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v1.mod_states["broadcast-8p-freecam"], "installed");

    let mut converted = broadcast.clone();
    converted.package.as_mut().unwrap().sha256 = hex::encode(Sha256::digest(b"replacement"));
    converted.adapter = Some(
        serde_json::from_value(serde_json::json!({
            "kind": "loader-files",
            "platforms": ["windows"],
            "target": "pckDir",
            "touches": ["mods"],
            "exclusive": "loader",
            "autoLoader": true,
            "baseline": broadcast.adapter.as_ref().unwrap().baseline,
            "requiredFiles": ["mod.json", "main.gd", "overlay.zip"],
            "upstreamUninstall": false,
            "sourceRule": "broadcast-tree-v1",
            "conflictGroup": "eight-player"
        }))
        .unwrap(),
    );
    let current = vec![converted.clone()];
    assert_eq!(
        validate_game_mods(&config_dir, &game_root, &current)
            .unwrap()
            .mod_states[&broadcast.id],
        "legacyInstalled"
    );
    // A damaged replacement archive must leave the old installation and its backup intact.
    assert_eq!(
        switch_from_zip(
            &["broadcast-8p-freecam".into()],
            &config_dir,
            &game_root,
            &zip_path,
            &staging_dir,
            &converted,
            &current,
            &runner,
            &UnlockedCheck
        )
        .unwrap_err(),
        "packageCorrupt"
    );
    assert_eq!(
        file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
        tx.post_pck.unwrap()
    );
    let mut names: Vec<String> = (0..65)
        .map(|i| format!("mod/scripts/player{i}.gd"))
        .collect();
    names.extend(
        [
            "director_hd.ps1",
            "Director2K.cmd",
            "DirectorHD.cmd",
            "DirectorInternal1080Host.cmd",
            "DirectorInternal2KHost.cmd",
            "DirectorMaxQualityHost.cmd",
        ]
        .map(str::to_string),
    );
    let files: Vec<_> = names
        .iter()
        .map(|name| (name.as_str(), b"# fixture".as_slice(), false))
        .collect();
    let zip = build_test_zip(&files);
    let pkg = converted.package.as_mut().unwrap();
    pkg.size = zip.len() as u64;
    pkg.sha256 = hex::encode(Sha256::digest(&zip));
    fs::write(&zip_path, zip).unwrap();
    let current = vec![converted.clone()];
    let migrated = switch_from_zip(
        &["broadcast-8p-freecam".into()],
        &config_dir,
        &game_root,
        &zip_path,
        &staging_dir,
        &converted,
        &current,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(migrated.exclusive, "loader");
    assert_eq!(
        migrated.preparation_rule.as_deref(),
        Some("broadcast-tree-v1")
    );
    assert!(
        pck_dir
            .join("mods/broadcast-8p-freecam/overlay.zip")
            .is_file()
    );
    let restored =
        uninstall_mod(&config_dir, &game_root, &converted, &runner, &UnlockedCheck).unwrap();
    assert_eq!(restored, baseline);
    assert!(!pck_dir.join("Machine Party.pck.broadcast_backup").exists());

    let v2 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v2.mod_states["broadcast-8p-freecam"], "vanilla");

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn gameplay_switch_preserves_sibling_and_recovers_partial_loader_transaction() {
    let root = tempfile::tempdir().unwrap();
    let (game, pck, base) = setup_synthetic_game(
        root.path(),
        &pck_loader::build_synthetic_pck_v3(false, true),
    );
    let config = root.path().join("config");
    let stage = root.path().join("stage");
    let mut mods = Vec::new();
    let mut zips = Vec::new();
    for (id, group) in [
        ("first", Some("eight-player")),
        ("second", Some("eight-player")),
        ("sibling", None),
    ] {
        let manifest = format!(r#"{{"id":"{id}","entry":"main.gd"}}"#);
        let data = build_test_zip(&[
            ("mod.json", manifest.as_bytes(), true),
            ("main.gd", b"extends Node", true),
        ]);
        let mut item = make_loader_entry_from_catalog("machineparty-plus", &data, &base);
        item.id = id.into();
        item.inventory_by_id = true;
        item.adapter.as_mut().unwrap().conflict_group = group.map(str::to_string);
        let zip = root.path().join(format!("{id}.zip"));
        fs::write(&zip, data).unwrap();
        mods.push(item);
        zips.push(zip);
    }
    for i in [0, 2] {
        install_from_zip(
            &config,
            &game,
            &zips[i],
            &stage,
            &mods[i],
            &mods,
            &SystemRunner,
            &UnlockedCheck,
        )
        .unwrap();
    }
    assert_eq!(
        validate_game_mods(&config, &game, &mods)
            .unwrap()
            .mod_states["second"],
        "modConflict"
    );
    for stale in [vec![], vec!["sibling".into()]] {
        assert_eq!(
            switch_from_zip(
                &stale,
                &config,
                &game,
                &zips[1],
                &stage,
                &mods[1],
                &mods,
                &SystemRunner,
                &UnlockedCheck
            )
            .unwrap_err(),
            "statusUnavailable"
        );
        assert!(pck.join("mods/first/main.gd").is_file());
    }
    let tx = switch_from_zip(
        &["first".into()],
        &config,
        &game,
        &zips[1],
        &stage,
        &mods[1],
        &mods,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(tx.preparation_rule.as_deref(), Some("native-v1"));
    assert_eq!(
        tx.source_sha256.as_ref(),
        Some(&mods[1].package.as_ref().unwrap().sha256)
    );
    assert!(!pck.join("mods/first").exists());
    assert!(pck.join("mods/sibling/main.gd").is_file());
    let mut interrupted = tx;
    interrupted.status = TransactionStatus::Pending;
    save_transaction(&config, &game, interrupted).unwrap();
    fs::remove_file(pck.join("mods/second/main.gd")).unwrap();
    fs::write(pck.join("mods/second/unowned"), b"user").unwrap();
    assert_eq!(
        uninstall_mod(&config, &game, &mods[1], &SystemRunner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );
    fs::remove_file(pck.join("mods/second/unowned")).unwrap();
    uninstall_mod(&config, &game, &mods[1], &SystemRunner, &UnlockedCheck).unwrap();
    assert_eq!(
        uninstall_mod(&config, &game, &mods[2], &SystemRunner, &UnlockedCheck).unwrap(),
        base
    );
}

#[test]
fn game_started_during_loader_preparation_preserves_existing_mods_root() {
    struct StartedAfterBackup(PathBuf);
    impl GameLockCheck for StartedAfterBackup {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            if self.0.is_file() {
                Err("gameRunning".into())
            } else {
                Ok(())
            }
        }
    }
    let root = tempfile::tempdir().unwrap();
    let (game, dir, base) = setup_synthetic_game(
        root.path(),
        &pck_loader::build_synthetic_pck_v3(false, true),
    );
    fs::create_dir(dir.join("mods")).unwrap();
    let config = root.path().join("config");
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &base);
    let archive = root.path().join("release.zip");
    fs::write(&archive, bytes).unwrap();
    let backup = backup_dir_for(&config, &game, "_mpm_loader").join("Machine Party.pck");
    let result = install_from_zip(
        &config,
        &game,
        &archive,
        &root.path().join("stage"),
        &item,
        std::slice::from_ref(&item),
        &SystemRunner,
        &StartedAfterBackup(backup),
    );
    assert_eq!(result.unwrap_err(), "gameRunning");
    assert_eq!(
        file_fingerprint(&dir.join("Machine Party.pck")).unwrap(),
        base
    );
    assert!(!dir.join(pck_loader::LOADER_SIDECAR).exists());
    assert_eq!(fs::read_dir(dir.join("mods")).unwrap().count(), 0);
    assert_eq!(
        get_transaction(&config, &game, &item.id)
            .unwrap()
            .unwrap()
            .status,
        TransactionStatus::RolledBack
    );
}

#[test]
fn linked_mod_directory_keeps_the_shared_loader() {
    let root = tempfile::tempdir().unwrap();
    let (game, dir, base) = setup_synthetic_game(
        root.path(),
        &pck_loader::build_synthetic_pck_v3(false, true),
    );
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &base);
    let zip = root.path().join("release.zip");
    fs::write(&zip, bytes).unwrap();
    let config = root.path().join("config");
    let installed = install_from_zip(
        &config,
        &game,
        &zip,
        &root.path().join("stage"),
        &item,
        std::slice::from_ref(&item),
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    let manual = root.path().join("manual");
    let link = dir.join("mods/linked");
    fs::create_dir(&manual).unwrap();
    fs::write(manual.join("main.gd"), b"player mod").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(&manual, &link).unwrap();
    #[cfg(windows)]
    assert!(
        std::process::Command::new("cmd")
            .args(["/D", "/C", "mklink", "/J"])
            .arg(&link)
            .arg(&manual)
            .status()
            .unwrap()
            .success()
    );
    let pck = uninstall_mod(&config, &game, &item, &SystemRunner, &UnlockedCheck).unwrap();
    assert_eq!(Some(pck), installed.post_pck);
    assert!(!loader_mod_dir(&dir, &item).exists());
    assert!(dir.join(pck_loader::LOADER_SIDECAR).is_file());
    assert_eq!(fs::read(link.join("main.gd")).unwrap(), b"player mod");
}

#[test]
fn l1_switch_between_loader_mods_and_pck_mods() {
    let root = test_root("l1-switch-mods");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

    let ot_zip_bytes = build_test_zip(&[
        ("overtime/BUILDINFO.json", b"{}", true),
        ("overtime/main.gd", b"extends Node\n# ot", true),
        (
            "overtime/mod.json",
            b"{\"id\":\"overtime\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("overtime/overtime_overlay.zip", b"PK\x05\x06", false),
        ("overtime/vanilla_md5.json", b"{}", true),
    ]);
    let ot_zip = root.join("ot.zip");
    fs::write(&ot_zip, &ot_zip_bytes).unwrap();
    let overtime = make_loader_entry_from_catalog("overtime", &ot_zip_bytes, &baseline);

    let roller_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"roller-carnival\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# roller", true),
        ("config.gd", b"extends RefCounted\n", true),
        ("carnival_meshes.gd", b"extends RefCounted\n", true),
        ("roller_carnival_game.gd", b"extends Node3D\n", true),
        ("official_minigame.gd", b"extends Minigame\n", true),
        ("override_game.gd", b"extends Node\n", true),
        ("override_local_game.gd", b"extends Node\n", true),
        ("override_playlist.gd", b"extends Node\n", true),
        ("override_picker.gd", b"extends Node\n", true),
    ]);
    let roller_zip = root.join("roller.zip");
    fs::write(&roller_zip, &roller_zip_bytes).unwrap();
    let roller = make_loader_entry_from_catalog("roller-carnival", &roller_zip_bytes, &baseline);

    let b_zip_bytes = build_test_zip(&[("patcher.ps1", b"# ps", true)]);
    let b_zip = root.join("broadcast.zip");
    fs::write(&b_zip, &b_zip_bytes).unwrap();
    let retired_entry = |id: &str, repo: &str, order| {
        let item = ModEntry {
            id: id.into(),
            repo: repo.into(),
            order,
            inventory_by_id: false,
            legacy_inventory_repos: Vec::new(),
            verified: true,
            version: None,
            package: None,
            adapter: None,
            requires: Vec::new(),
            role: None,
        };
        crate::catalog::legacy_entry(&item).unwrap()
    };
    let mut broadcast = retired_entry(
        "broadcast-8p-freecam",
        "Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher",
        3,
    );
    broadcast.package.as_mut().unwrap().size = b_zip_bytes.len() as u64;
    broadcast.package.as_mut().unwrap().sha256 = hex::encode(Sha256::digest(&b_zip_bytes));
    broadcast.adapter.as_mut().unwrap().baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: baseline.size,
        sha256: baseline.sha256.clone(),
    };

    let p_zip_bytes = build_test_zip(&[("install.py", b"# py", true)]);
    let p_zip = root.join("b8p.zip");
    fs::write(&p_zip, &p_zip_bytes).unwrap();
    let mut b8p = retired_entry("binary1936-8p", "Binary1936/machine-party-8p", 4);
    b8p.package.as_mut().unwrap().size = p_zip_bytes.len() as u64;
    b8p.package.as_mut().unwrap().sha256 = hex::encode(Sha256::digest(&p_zip_bytes));
    b8p.adapter.as_mut().unwrap().baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: baseline.size,
        sha256: baseline.sha256.clone(),
    };

    struct SwitchRunner {
        vanilla_sha: String,
    }
    impl ProcessRunner for SwitchRunner {
        fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String> {
            if let Some(idx) = req.args.iter().position(|a| a == "-GameDir") {
                let dir = PathBuf::from(&req.args[idx + 1]);
                let pck = dir.join("Machine Party.pck");
                let action = req
                    .args
                    .iter()
                    .position(|a| a == "-Action")
                    .map(|i| req.args[i + 1].as_str())
                    .unwrap_or("");
                return match action {
                    "verify" => {
                        let bytes = fs::read(&pck).unwrap();
                        let s = if bytes.ends_with(b"BROADCAST") {
                            "State: patched\n"
                        } else if file_fingerprint(&pck)?.sha256 == self.vanilla_sha {
                            "State: clean\n"
                        } else {
                            "State: other\n"
                        };
                        Ok(CommandOutput {
                            code: 0,
                            stdout: s.into(),
                            stderr: String::new(),
                        })
                    }
                    "install" => {
                        let mut orig = fs::read(&pck).unwrap();
                        fs::write(dir.join("Machine Party.pck.broadcast_backup"), &orig).unwrap();
                        orig.extend_from_slice(b"BROADCAST");
                        fs::write(&pck, orig).unwrap();
                        Ok(CommandOutput {
                            code: 0,
                            stdout: "Installed.\n".into(),
                            stderr: String::new(),
                        })
                    }
                    _ => panic!("unexpected ps action {action}"),
                };
            }
            if let Some(idx) = req.args.iter().position(|a| a == "--game-dir") {
                let dir = PathBuf::from(&req.args[idx + 1]);
                let pck = dir.join("Machine Party.pck");
                if req.args.iter().any(|a| a == "--verify") {
                    let bytes = fs::read(&pck).unwrap();
                    return if bytes.ends_with(b"B8P_V1_5") {
                        Ok(CommandOutput {
                            code: 0,
                            stdout: "PATCHED\n".into(),
                            stderr: String::new(),
                        })
                    } else {
                        Ok(CommandOutput {
                            code: 1,
                            stdout: "NOT PATCHED\n".into(),
                            stderr: String::new(),
                        })
                    };
                }
                let mut orig = fs::read(&pck).unwrap();
                orig.extend_from_slice(b"B8P_V1_5");
                fs::write(&pck, orig).unwrap();
                return Ok(CommandOutput {
                    code: 0,
                    stdout: "Patched\n".into(),
                    stderr: String::new(),
                });
            }
            panic!("unexpected command {:?}", req.args);
        }
    }

    let mods = vec![
        overtime.clone(),
        roller.clone(),
        broadcast.clone(),
        b8p.clone(),
    ];
    let config_dir = root.join("config");
    let staging_dir = root.join("staging");
    let runner = SwitchRunner {
        vanilla_sha: baseline.sha256.clone(),
    };

    // Install two coexisting autoLoader mods.
    install_from_zip(
        &config_dir,
        &game_root,
        &ot_zip,
        &staging_dir.join("ot"),
        &overtime,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    install_from_zip(
        &config_dir,
        &game_root,
        &roller_zip,
        &staging_dir.join("roller"),
        &roller,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();

    let v_loader = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v_loader.mod_states["broadcast-8p-freecam"], "modConflict");
    assert_eq!(v_loader.mod_states["binary1936-8p"], "modConflict");

    // Corrupt target ZIP must fail before uninstalling existing mods.
    let bad_zip = root.join("bad.zip");
    fs::write(&bad_zip, b"CORRUPT").unwrap();
    assert_eq!(
        switch_from_zip(
            &["overtime".into(), "roller-carnival".into()],
            &config_dir,
            &game_root,
            &bad_zip,
            &staging_dir.join("bad"),
            &broadcast,
            &mods,
            &runner,
            &UnlockedCheck,
        )
        .unwrap_err(),
        "packageCorrupt"
    );
    let after_bad = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(after_bad.mod_states["overtime"], "installed");
    assert_eq!(after_bad.mod_states["roller-carnival"], "installed");

    // Switch from both loader mods -> Broadcast 8P Freecam (PCK patcher).
    switch_from_zip(
        &["overtime".into(), "roller-carnival".into()],
        &config_dir,
        &game_root,
        &b_zip,
        &staging_dir.join("broadcast"),
        &broadcast,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let v_broadcast = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v_broadcast.mod_states["broadcast-8p-freecam"], "installed");
    assert_eq!(v_broadcast.mod_states["overtime"], "modConflict");
    assert_eq!(v_broadcast.mod_states["roller-carnival"], "modConflict");
    assert_eq!(v_broadcast.mod_states["binary1936-8p"], "modConflict");
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_none());
    assert!(!pck_dir.join("mods").exists());

    // Switch from Broadcast 8P Freecam -> Binary1936 8P (PCK -> PCK).
    switch_from_zip(
        &["broadcast-8p-freecam".into()],
        &config_dir,
        &game_root,
        &p_zip,
        &staging_dir.join("b8p"),
        &b8p,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let v_b8p = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v_b8p.mod_states["binary1936-8p"], "installed");
    assert_eq!(v_b8p.mod_states["broadcast-8p-freecam"], "modConflict");
    assert!(!pck_dir.join("Machine Party.pck.broadcast_backup").exists());

    // Switch from Binary1936 8P -> Overtime MPML (PCK -> loader).
    switch_from_zip(
        &["binary1936-8p".into()],
        &config_dir,
        &game_root,
        &ot_zip,
        &staging_dir.join("ot2"),
        &overtime,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let v_ot = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v_ot.mod_states["overtime"], "installed");
    assert_eq!(v_ot.mod_states["roller-carnival"], "vanilla");
    assert_eq!(v_ot.mod_states["broadcast-8p-freecam"], "modConflict");

    // Unmanaged loader folder blocks switching with loaderConflict.
    write_atomic(&pck_dir.join("mods/manual_mod/main.gd"), b"extends Node\n").unwrap();
    let v_unmanaged = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(
        v_unmanaged.mod_states["broadcast-8p-freecam"],
        "loaderConflict"
    );
    assert_eq!(
        switch_from_zip(
            &["overtime".into()],
            &config_dir,
            &game_root,
            &b_zip,
            &staging_dir.join("broadcast2"),
            &broadcast,
            &mods,
            &runner,
            &UnlockedCheck,
        )
        .unwrap_err(),
        "loaderConflict"
    );

    fs::remove_dir_all(root).unwrap();
}
