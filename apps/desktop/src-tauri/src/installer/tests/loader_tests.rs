use super::*;

#[test]
fn l1_loader_files_installs_conflicts_rejects_tamper_and_preserves_siblings() {
    let root = test_root("l1-loader-files");
    let pck_bytes = build_synthetic_pck();
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
    let sibling_file = pck_dir.join("mods").join("console").join("main.gd");
    write_atomic(&sibling_file, b"extends Node\n").unwrap();

    let plus_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"machineparty_plus\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# plus", true),
    ]);
    let plus_zip = root.join("plus.zip");
    fs::write(&plus_zip, &plus_zip_bytes).unwrap();
    let plus_entry = ModEntry {
        inventory_by_id: false,
        legacy_inventory_repos: Vec::new(),
        id: "machineparty-plus".into(),
        order: 2,
        repo: "Ghostx10742/MachineParty-Plus".into(),
        version: Some("v2.1.0".into()),
        verified: true,
        requires: Vec::new(),
        role: None,
        package: Some(PackageSpec {
            asset_id: "511918824".into(),
            filename: "Jarunk-MachinePartyPlus.zip".into(),
            size: plus_zip_bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&plus_zip_bytes)),
            mirror_approved: true,
        }),
        adapter: Some(AdapterProfile {
            source_rule: None,
            conflict_group: None,
            kind: "loader-files".into(),
            platforms: vec!["windows".into()],
            target: "pckDir".into(),
            touches: vec!["mods".into()],
            exclusive: "loader".into(),
            auto_loader: false,
            baseline: BaselineSpec {
                file: "Machine Party.pck".into(),
                size: baseline.size,
                sha256: baseline.sha256.clone(),
            },
            required_files: vec!["mod.json".into(), "main.gd".into()],
            verify_files: None,
            upstream_uninstall: false,
            run: RunSpec::default(),
            actions: ActionSpec::default(),
            status: StatusMatchers::default(),
            forbidden_args: Vec::new(),
        }),
    };

    let ot_zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
    let ot_zip = root.join("ot.zip");
    fs::write(&ot_zip, &ot_zip_bytes).unwrap();
    let overtime = synthetic_overtime_entry(&baseline, &ot_zip_bytes, true);
    let mods = vec![overtime.clone(), plus_entry.clone()];
    let config_dir = root.join("config");
    let staging_dir = root.join("staging");
    let runner = FakeCliRunner {
        vanilla_bytes: pck_bytes,
        vanilla_sha: baseline.sha256.clone(),
        fault: FakeFault::None,
        calls: RefCell::new(Vec::new()),
    };

    let tx = install_from_zip(
        &config_dir,
        &game_root,
        &plus_zip,
        &staging_dir,
        &plus_entry,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(tx.status, TransactionStatus::Committed);
    assert!(
        pck_dir
            .join("mods")
            .join("machineparty-plus")
            .join("main.gd")
            .is_file()
    );

    let v1 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v1.mod_states["machineparty-plus"], "installed");
    assert_eq!(v1.mod_states["overtime"], "loaderConflict");
    assert_eq!(
        install_from_zip(
            &config_dir,
            &game_root,
            &ot_zip,
            &root.join("staging-ot"),
            &overtime,
            &mods,
            &runner,
            &UnlockedCheck,
        )
        .unwrap_err(),
        "modConflict"
    );

    let installed_main = pck_dir
        .join("mods")
        .join("machineparty-plus")
        .join("main.gd");
    fs::write(&installed_main, b"tampered").unwrap();
    let v_tamper = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v_tamper.mod_states["machineparty-plus"], "needsRepair");
    assert_eq!(
        uninstall_mod(
            &config_dir,
            &game_root,
            &plus_entry,
            &runner,
            &UnlockedCheck,
        )
        .unwrap_err(),
        "gameUpdatedOrModified"
    );

    fs::write(&installed_main, b"extends Node\n# plus").unwrap();
    let restored = uninstall_mod(
        &config_dir,
        &game_root,
        &plus_entry,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(restored, baseline);
    assert!(!pck_dir.join("mods").join("machineparty-plus").exists());
    assert_eq!(fs::read(&sibling_file).unwrap(), b"extends Node\n");

    let v2 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v2.mod_states["machineparty-plus"], "vanilla");
    assert_eq!(v2.mod_states["overtime"], "vanilla");

    fs::remove_dir_all(root).unwrap();
}

#[test]
#[ignore = "requires the released Standalone HD ZIP in MPM_SOURCE_FIXTURES"]
fn released_hd_installs_from_vanilla_and_restores_the_copy() {
    let fixtures = PathBuf::from(std::env::var_os("MPM_SOURCE_FIXTURES").unwrap());
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("config");
    let game = root.path().join("test copy");
    let dir = game.join("Machine Party_Windows");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join("Machine Party.exe"), b"MZ fixture").unwrap();
    let pck = dir.join("Machine Party.pck");
    let mut hd = crate::catalog::entry("standalone-hd").unwrap();
    if let Some(original) = std::env::var_os("MPM_L3_VANILLA_PCK") {
        std::io::copy(
            &mut fs::File::open(original).unwrap(),
            &mut fs::File::create(&pck).unwrap(),
        )
        .unwrap();
    } else {
        fs::write(&pck, pck_loader::build_synthetic_pck_v3(false, true)).unwrap();
        let fp = file_fingerprint(&pck).unwrap();
        let base = &mut hd.adapter.as_mut().unwrap().baseline;
        base.size = fp.size;
        base.sha256 = fp.sha256;
    }
    let original = file_fingerprint(&pck).unwrap();
    let list = std::slice::from_ref(&hd);
    let zip = fixtures.join(&hd.package.as_ref().unwrap().filename);
    assert_eq!(
        validate_game_mods(&config, &game, list).unwrap().mod_states[&hd.id],
        "vanilla"
    );
    install_from_zip(
        &config,
        &game,
        &zip,
        &config.join("stage"),
        &hd,
        list,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    let scan = validate_game_mods(&config, &game, list).unwrap();
    assert_eq!(scan.mod_states[&hd.id], "installed");
    assert_eq!(
        scan.installed[hd.inventory_key()],
        hd.version.as_deref().unwrap()
    );
    assert!(dir.join("mods/standalone-hd/main.gd").is_file());
    uninstall_mod(&config, &game, &hd, &SystemRunner, &UnlockedCheck).unwrap();
    assert_eq!(file_fingerprint(&pck).unwrap(), original);
    assert_eq!(
        validate_game_mods(&config, &game, list).unwrap().mod_states[&hd.id],
        "vanilla"
    );
}

#[test]
fn l1_zip_loader_mod_auto_installs_and_restores_loader_on_last_uninstall() {
    let root = test_root("l1-zip-auto-loader");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

    let roller_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"roller-carnival\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# main", true),
        ("config.gd", b"extends RefCounted\n", true),
        ("carnival_meshes.gd", b"extends RefCounted\n", true),
        ("fx_pool.gd", b"extends RefCounted\n", true),
        ("hud_ui.gd", b"extends RefCounted\n", true),
        ("self_test.gd", b"extends RefCounted\n", true),
        ("team_support.gd", b"extends RefCounted\n", true),
        ("roller_carnival_game.gd", b"extends Node3D\n", true),
        ("official_minigame.gd", b"extends Minigame\n", true),
        ("override_game.gd", b"extends Node\n", true),
        ("override_local_game.gd", b"extends Node\n", true),
        ("override_playlist.gd", b"extends Node\n", true),
        ("override_picker.gd", b"extends Node\n", true),
    ]);
    let roller_zip = root.join("roller.zip");
    fs::write(&roller_zip, &roller_zip_bytes).unwrap();

    let mut roller = crate::catalog::entry("roller-carnival").unwrap();
    roller.verified = true;
    {
        let pkg = roller.package.as_mut().unwrap();
        pkg.size = roller_zip_bytes.len() as u64;
        pkg.sha256 = hex::encode(Sha256::digest(&roller_zip_bytes));
    }
    roller.adapter.as_mut().unwrap().baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: baseline.size,
        sha256: baseline.sha256.clone(),
    };

    let plus_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"machineparty_plus\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# plus", true),
    ]);
    let plus_zip = root.join("plus.zip");
    fs::write(&plus_zip, &plus_zip_bytes).unwrap();
    let plus_entry = ModEntry {
        inventory_by_id: false,
        legacy_inventory_repos: Vec::new(),
        id: "machineparty-plus".into(),
        order: 2,
        repo: "Ghostx10742/MachineParty-Plus".into(),
        version: Some("v2.1.0".into()),
        verified: true,
        requires: Vec::new(),
        role: None,
        package: Some(PackageSpec {
            asset_id: "511918824".into(),
            filename: "Jarunk-MachinePartyPlus.zip".into(),
            size: plus_zip_bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&plus_zip_bytes)),
            mirror_approved: true,
        }),
        adapter: Some(AdapterProfile {
            source_rule: None,
            conflict_group: None,
            kind: "loader-files".into(),
            platforms: vec!["windows".into()],
            target: "pckDir".into(),
            touches: vec!["mods".into()],
            exclusive: "loader".into(),
            auto_loader: false,
            baseline: BaselineSpec {
                file: "Machine Party.pck".into(),
                size: baseline.size,
                sha256: baseline.sha256.clone(),
            },
            required_files: vec!["mod.json".into(), "main.gd".into()],
            verify_files: None,
            upstream_uninstall: false,
            run: RunSpec::default(),
            actions: ActionSpec::default(),
            status: StatusMatchers::default(),
            forbidden_args: Vec::new(),
        }),
    };

    let ot_zip_bytes = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
    let ot_zip = root.join("ot.zip");
    fs::write(&ot_zip, &ot_zip_bytes).unwrap();
    let overtime = synthetic_overtime_entry(&baseline, &ot_zip_bytes, true);
    let bot_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"lobby-bots\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node", true),
        ("junk_platform.gd", b"extends Node", true),
    ]);
    let bot = make_loader_entry_from_catalog("lobby-bots", &bot_bytes, &baseline);
    let bot_zip = root.join("bot.zip");
    fs::write(&bot_zip, &bot_bytes).unwrap();
    let mods = vec![
        overtime.clone(),
        plus_entry.clone(),
        roller.clone(),
        bot.clone(),
    ];
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
        &roller_zip,
        &staging_dir.join("roller"),
        &roller,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(tx.status, TransactionStatus::Committed);
    assert!(pck_dir.join("mods/roller-carnival/main.gd").is_file());
    assert!(
        pck_dir
            .join("mods/roller-carnival/override_game.gd")
            .is_file()
    );
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_some());
    assert!(!pck_loader::external_loader_present(&pck_dir).unwrap());

    let v1 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v1.mod_states["roller-carnival"], "installed");
    assert_eq!(v1.mod_states["overtime"], "modConflict");
    assert_eq!(v1.mod_states["machineparty-plus"], "vanilla");

    // Co-install a second loader mod alongside first-party roller-carnival.
    install_from_zip(
        &config_dir,
        &game_root,
        &plus_zip,
        &staging_dir.join("plus"),
        &plus_entry,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();

    // A second first-party mod uses the same author page and its own install record.
    install_from_zip(
        &config_dir,
        &game_root,
        &bot_zip,
        &staging_dir.join("bot"),
        &bot,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let both = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(bot.repo, roller.repo);
    assert_eq!(
        both.installed[bot.inventory_key()],
        bot.version.as_deref().unwrap()
    );
    assert_eq!(
        both.installed[roller.inventory_key()],
        roller.version.as_deref().unwrap()
    );
    uninstall_mod(&config_dir, &game_root, &bot, &runner, &UnlockedCheck).unwrap();
    let after_bot = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert!(!after_bot.installed.contains_key(bot.inventory_key()));
    assert_eq!(after_bot.mod_states[&roller.id], "installed");

    // Removing roller-carnival first keeps managed loader intact for machineparty-plus.
    uninstall_mod(&config_dir, &game_root, &roller, &runner, &UnlockedCheck).unwrap();
    assert!(!pck_dir.join("mods/roller-carnival").exists());
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_some());

    // Removing the last loader mod triggers lossless vanilla PCK restoration.
    let restored = uninstall_mod(
        &config_dir,
        &game_root,
        &plus_entry,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(restored, baseline);
    assert_eq!(
        fs::read(pck_dir.join("Machine Party.pck")).unwrap(),
        pck_bytes
    );
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_none());
    assert!(!pck_dir.join(pck_loader::LOADER_SIDECAR).exists());

    let v2 = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(v2.mod_states["roller-carnival"], "vanilla");
    assert_eq!(v2.mod_states["overtime"], "vanilla");

    // External MPML is preserved even after installing & uninstalling autoLoader ZIP mod.
    fs::write(pck_dir.join(pck_loader::EXTERNAL_LOADER_EXE), b"MZ").unwrap();
    install_from_zip(
        &config_dir,
        &game_root,
        &roller_zip,
        &staging_dir.join("roller2"),
        &roller,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert!(pck_loader::external_loader_present(&pck_dir).unwrap());
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_none());
    uninstall_mod(&config_dir, &game_root, &roller, &runner, &UnlockedCheck).unwrap();
    assert!(pck_dir.join(pck_loader::EXTERNAL_LOADER_EXE).is_file());
    fs::remove_file(pck_dir.join(pck_loader::EXTERNAL_LOADER_EXE)).unwrap();

    // Steam update while managed loader mod is installed surfaces gameUpdatedOrModified and blocks uninstall.
    install_from_zip(
        &config_dir,
        &game_root,
        &roller_zip,
        &staging_dir.join("roller3"),
        &roller,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    fs::write(pck_dir.join("Machine Party.pck"), b"STEAM_UPDATE").unwrap();
    let v_tamper = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(
        v_tamper.mod_states["roller-carnival"],
        "gameUpdatedOrModified"
    );
    assert_eq!(
        uninstall_mod(&config_dir, &game_root, &roller, &runner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn single_mod_update_and_recovery_keep_sibling_and_loader_intact() {
    fn fixture(id: &str, version: &str) -> Vec<u8> {
        let manifest = format!(r#"{{"id":"{id}","version":"{version}","entry":"main.gd"}}"#);
        build_test_zip(&[
            ("mod.json", manifest.as_bytes(), true),
            ("main.gd", version.as_bytes(), true),
        ])
    }
    exercise_single_update(
        fixture("roller-carnival", "0.1.0"),
        fixture("roller-carnival", "0.1.1"),
        fixture("lobby-bots", "0.1.4"),
        false,
    );
}

#[test]
#[ignore = "requires three published archives in MPM_SOURCE_FIXTURES"]
fn released_roller_010_to_011_with_lobby_bots() {
    let dir = PathBuf::from(std::env::var_os("MPM_SOURCE_FIXTURES").unwrap());
    let read = |name: &str, sha: &str| {
        let bytes = fs::read(dir.join(name)).unwrap();
        assert_eq!(hex::encode(Sha256::digest(&bytes)), sha);
        bytes
    };
    exercise_single_update(
        read(
            "roller-carnival-0.1.0.zip",
            "ec10da25ecd98ac6e9179d81c2188f82ae752baf4783058c87f93ea020802ca4",
        ),
        read(
            "roller-carnival-0.1.1.zip",
            "a7f323e7c0fec56b2ec124dd591bf5898b57cb7333a25539322d8b3e00d56986",
        ),
        read(
            "lobby-bots-0.1.4.zip",
            "098e69f28452bc146142b83706060d4334f6d0c2b0b1fca1a7636048c6f54845",
        ),
        true,
    );
}

fn exercise_single_update(old_zip: Vec<u8>, new_zip: Vec<u8>, bot_zip: Vec<u8>, real: bool) {
    use std::cell::Cell;
    // Fail (or simulate loss of the process) after the replacement is live,
    // before its version has been committed.
    struct Interrupt {
        live: PathBuf,
        new: FileFingerprint,
        crash: bool,
        triggered: Cell<bool>,
        between_renames: bool,
    }
    impl GameLockCheck for Interrupt {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            if !self.triggered.get()
                && (if self.between_renames {
                    !self.live.exists()
                } else {
                    file_fingerprint(&self.live).ok() == Some(self.new.clone())
                })
            {
                self.triggered.set(true);
                if self.crash {
                    panic!("simulated process stop");
                }
                return Err("gameRunning".into());
            }
            Ok(())
        }
    }
    let root = tempfile::tempdir().unwrap();
    let (game, dir, baseline) = setup_synthetic_game(
        root.path(),
        &pck_loader::build_synthetic_pck_v3(false, true),
    );
    let config = root.path().join("config");
    let make = |id: &str, version: &str, bytes: &[u8]| {
        let mut item = make_loader_entry_from_catalog(id, bytes, &baseline);
        item.version = Some(version.into());
        let pkg = item.package.as_mut().unwrap();
        pkg.filename = format!("{id}-{}.zip", version.trim_start_matches('v'));
        pkg.asset_id = if id == "lobby-bots" { "1006" } else { "1001" }.into();
        if !real {
            item.adapter.as_mut().unwrap().required_files =
                vec!["mod.json".into(), "main.gd".into()];
        }
        let file = root.path().join(format!("{id}-{version}.zip"));
        fs::write(&file, bytes).unwrap();
        (item, file)
    };
    let (mut old, archive) = make("roller-carnival", "v0.1.0", &old_zip);
    if !real {
        old.repo = "JamesGZM/roller-carnival".into();
    }
    old.legacy_inventory_repos.clear();
    let (new, target) = make("roller-carnival", "v0.1.1", &new_zip);
    let (bot, bots) = make("lobby-bots", "v0.1.4", &bot_zip);
    let stage = root.path().join("stage");
    let list = [new.clone(), bot.clone()];
    let mut before = install_from_zip(
        &config,
        &game,
        &archive,
        &stage,
        &old,
        &list,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    // Older managers recorded ownership before source/recipe provenance was added.
    before.source_sha256 = None;
    before.preparation_rule = None;
    save_transaction(&config, &game, before.clone()).unwrap();
    let sibling = install_from_zip(
        &config,
        &game,
        &bots,
        &stage,
        &bot,
        &list,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    let marker = dir.join(pck_loader::LOADER_SIDECAR);
    let loader = fs::read(&marker).unwrap();
    let pck = dir.join("Machine Party.pck");
    let patched = file_fingerprint(&pck).unwrap();
    let live = loader_mod_dir(&dir, &new);
    let apply = |lock: &dyn GameLockCheck| {
        update::apply(&config, &game, &dir, &target, &new, "v0.1.0", &list, lock)
    };
    let verify_old = || {
        assert_eq!(
            get_transaction(&config, &game, &new.id).unwrap(),
            Some(before.clone())
        );
        assert_eq!(collect_dir_fingerprints(&live).unwrap(), before.owned_files);
        assert_eq!(
            inventory::installed_versions(&config, &game).unwrap()[new.inventory_key()],
            "v0.1.0"
        );
    };
    fs::write(&target, b"corrupt").unwrap();
    assert_eq!(apply(&UnlockedCheck).unwrap_err(), "packageCorrupt");
    verify_old();
    fs::write(&target, &new_zip).unwrap();
    fs::write(live.join("player.cfg"), b"user data").unwrap();
    assert!(apply(&UnlockedCheck).unwrap_err().contains("player.cfg"));
    assert_eq!(fs::read(live.join("player.cfg")).unwrap(), b"user data");
    fs::remove_file(live.join("player.cfg")).unwrap();
    stage_package(
        &target,
        &stage,
        new.package.as_ref().unwrap(),
        new.adapter.as_ref().unwrap(),
        &dir,
        &SystemRunner,
    )
    .unwrap();
    for (crash, between_renames) in [(false, false), (true, true), (true, false)] {
        let fault = Interrupt {
            live: live.join("mod.json"),
            new: file_fingerprint(&stage.join("mod.json")).unwrap(),
            crash,
            triggered: Cell::new(false),
            between_renames,
        };
        if crash {
            assert!(
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| apply(&fault))).is_err()
            );
            if !between_renames {
                // The inventory write is durable just before the transaction commit.
                inventory::record_installed(&config, &game, new.inventory_key(), "v0.1.1").unwrap();
            }
            let journal = before.backup_dir.join("update.json");
            let pending = fs::read(&journal).unwrap();
            assert_eq!(
                update::recover(&config, &game, &list, &LockedCheck).unwrap_err(),
                "gameRunning"
            );
            assert_eq!(fs::read(&journal).unwrap(), pending);
            update::recover(&config, &game, &list, &UnlockedCheck).unwrap();
        } else {
            assert_eq!(apply(&fault).unwrap_err(), "gameRunning");
        }
        assert!(fault.triggered.get());
        verify_old();
        assert_eq!(
            get_transaction(&config, &game, &bot.id).unwrap(),
            Some(sibling.clone())
        );
        assert_eq!(
            collect_dir_fingerprints(&loader_mod_dir(&dir, &bot)).unwrap(),
            sibling.owned_files
        );
    }
    // A lock after the commit delays cleanup without turning success into a rollback.
    struct LockAfterCommit<'a>(&'a Path, &'a Path, &'a ModEntry);
    impl GameLockCheck for LockAfterCommit<'_> {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            let tx = get_transaction(self.0, self.1, &self.2.id)?.unwrap();
            if Some(&tx.version) == self.2.version.as_ref() {
                return Err("gameRunning".into());
            }
            Ok(())
        }
    }
    let journal = before.backup_dir.join("update.json");
    apply(&LockAfterCommit(&config, &game, &new)).unwrap();
    assert!(journal.is_file());
    update::recover(&config, &game, &list, &UnlockedCheck).unwrap();
    assert!(!journal.exists());
    assert_eq!(apply(&UnlockedCheck).unwrap_err(), "statusUnavailable");
    let scan = validate_game_mods(&config, &game, &list).unwrap();
    assert_eq!(scan.installed[new.inventory_key()], "v0.1.1");
    assert_eq!(scan.installed[bot.inventory_key()], "v0.1.4");
    assert_eq!(scan.installed.len(), 2);
    let after = get_transaction(&config, &game, &new.id).unwrap().unwrap();
    assert_eq!(after.owned_files, collect_dir_fingerprints(&stage).unwrap());
    assert_eq!(after.owned_files, collect_dir_fingerprints(&live).unwrap());
    assert_eq!(
        after.source_sha256,
        Some(hex::encode(Sha256::digest(new_zip)))
    );
    assert_eq!(fs::read(&marker).unwrap(), loader);
    assert_eq!(file_fingerprint(&pck).unwrap(), patched);
    fs::remove_file(target).unwrap();
    uninstall_mod(&config, &game, &new, &SystemRunner, &UnlockedCheck).unwrap();
    assert_eq!(
        get_transaction(&config, &game, &bot.id).unwrap(),
        Some(sibling.clone())
    );
    assert_eq!(
        collect_dir_fingerprints(&loader_mod_dir(&dir, &bot)).unwrap(),
        sibling.owned_files
    );
    assert_eq!(
        uninstall_mod(&config, &game, &bot, &SystemRunner, &UnlockedCheck).unwrap(),
        baseline
    );
}

#[test]
fn legacy_roller_inventory_and_uninstall_use_the_catalog_id() {
    let root = tempfile::tempdir().unwrap();
    let bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game, pck, baseline) = setup_synthetic_game(root.path(), &bytes);
    let config = root.path().join("config");
    let zip = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"roller-carnival","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let zip_path = root.path().join("roller.zip");
    fs::write(&zip_path, &zip).unwrap();
    let current = crate::catalog::entry("roller-carnival").unwrap();
    let historical_repo = "JamesGZM/roller-carnival";
    let mut old = make_loader_entry_from_catalog(&current.id, &zip, &baseline);
    old.repo = historical_repo.into();
    old.legacy_inventory_repos.clear();
    old.adapter.as_mut().unwrap().required_files = vec!["mod.json".into(), "main.gd".into()];
    let mut tx = install_from_zip(
        &config,
        &game,
        &zip_path,
        &root.path().join("stage"),
        &old,
        std::slice::from_ref(&old),
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    tx.source_sha256 = None;
    tx.preparation_rule = None;
    save_transaction(&config, &game, tx.clone()).unwrap();

    let other_game = root.path().join("other");
    let inventory_path = config.join("installations.json");
    let historical = serde_json::json!({
        game.to_str().unwrap(): {
            historical_repo: "v0.1.0", &current.repo: "v0.1.0", "lobby-bots": "v0.1.4"
        },
        other_game.to_str().unwrap(): {historical_repo: "v0.1.0"}
    });
    fs::write(&inventory_path, serde_json::to_vec(&historical).unwrap()).unwrap();
    let scan = validate_game_mods(&config, &game, std::slice::from_ref(&current)).unwrap();
    assert_eq!(scan.mod_states[&current.id], "installed");
    assert_eq!(scan.installed.len(), 2);
    assert_eq!(scan.installed[&current.id], "v0.1.0");
    assert_eq!(
        inventory::installed_versions(&config, &game).unwrap(),
        scan.installed
    );
    let script = pck.join("mods/roller-carnival/main.gd");
    let original = fs::read(&script).unwrap();
    let patched = file_fingerprint(&pck.join("Machine Party.pck")).unwrap();
    fs::write(&script, b"player change").unwrap();
    assert_eq!(
        uninstall_mod(&config, &game, &current, &SystemRunner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );
    assert_eq!(fs::read(&script).unwrap(), b"player change");
    assert_eq!(
        file_fingerprint(&pck.join("Machine Party.pck")).unwrap(),
        patched
    );
    fs::write(&script, original).unwrap();
    tx.repo = "unknown/repo".into();
    save_transaction(&config, &game, tx.clone()).unwrap();
    assert_eq!(
        uninstall_mod(&config, &game, &current, &SystemRunner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );
    tx.repo = historical_repo.into();
    save_transaction(&config, &game, tx).unwrap();
    let restored = uninstall_mod(&config, &game, &current, &SystemRunner, &UnlockedCheck).unwrap();
    assert_eq!(restored, baseline);
    assert!(!script.exists());
    assert!(
        get_transaction(&config, &game, &current.id)
            .unwrap()
            .is_none()
    );
    let raw: serde_json::Value =
        serde_json::from_slice(&fs::read(inventory_path).unwrap()).unwrap();
    assert_eq!(
        raw[game.to_str().unwrap()],
        serde_json::json!({"lobby-bots":"v0.1.4"})
    );
    assert_eq!(
        raw[other_game.to_str().unwrap()],
        historical[other_game.to_str().unwrap()]
    );
}

#[test]
fn l1_nested_mpml_zip_coexists_with_loader_mods() {
    let root = test_root("l1-nested-mpml-coexist");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

    let ot_zip_bytes = build_test_zip(&[
        ("overtime/BUILDINFO.json", b"{}", true),
        ("overtime/main.gd", b"extends Node\n# overtime", true),
        (
            "overtime/mod.json",
            b"{\"id\":\"overtime\",\"entry\":\"main.gd\",\"priority\":-1000}",
            true,
        ),
        ("overtime/overtime_overlay.zip", b"PK\x05\x06", false),
        ("overtime/vanilla_md5.json", b"{}", true),
    ]);
    let ot_zip = root.join("overtime-mpml.zip");
    fs::write(&ot_zip, &ot_zip_bytes).unwrap();
    let overtime = make_loader_entry_from_catalog("overtime", &ot_zip_bytes, &baseline);

    let plus_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"machineparty_plus\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# plus", true),
    ]);
    let plus_zip = root.join("plus.zip");
    fs::write(&plus_zip, &plus_zip_bytes).unwrap();
    let plus = make_loader_entry_from_catalog("machineparty-plus", &plus_zip_bytes, &baseline);

    let roller_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"roller-carnival\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# roller", true),
        ("config.gd", b"extends RefCounted\n", true),
        ("carnival_meshes.gd", b"extends RefCounted\n", true),
        ("fx_pool.gd", b"extends RefCounted\n", true),
        ("hud_ui.gd", b"extends RefCounted\n", true),
        ("self_test.gd", b"extends RefCounted\n", true),
        ("team_support.gd", b"extends RefCounted\n", true),
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

    let mods = vec![overtime.clone(), plus.clone(), roller.clone()];
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
        &ot_zip,
        &staging_dir.join("ot"),
        &overtime,
        &mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert!(pck_dir.join("mods/overtime/mod.json").is_file());
    assert!(!pck_dir.join("mods/overtime/overtime").exists());

    install_from_zip(
        &config_dir,
        &game_root,
        &plus_zip,
        &staging_dir.join("plus"),
        &plus,
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

    let state = validate_game_mods(&config_dir, &game_root, &mods).unwrap();
    assert_eq!(state.mod_states["overtime"], "installed");
    assert_eq!(state.mod_states["machineparty-plus"], "installed");
    assert_eq!(state.mod_states["roller-carnival"], "installed");
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_some());

    uninstall_mod(&config_dir, &game_root, &overtime, &runner, &UnlockedCheck).unwrap();
    uninstall_mod(&config_dir, &game_root, &plus, &runner, &UnlockedCheck).unwrap();
    let current_roller = crate::catalog::entry("roller-carnival").unwrap();
    assert_eq!(roller.version.as_deref(), Some("v0.1.0"));
    assert_ne!(current_roller.version, roller.version);
    let restored = uninstall_mod(
        &config_dir,
        &game_root,
        &current_roller,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(restored, baseline);
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_none());

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn set_mods_enabled_persists_state_checks_game_lock_and_cleans_on_uninstall() {
    let root = test_root("l1-enable-disable");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(false, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);
    let config_dir = root.join("config");
    let staging_dir = root.join("staging");

    let roller_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"roller-carnival\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# roller", true),
        ("config.gd", b"extends RefCounted\n", true),
        ("carnival_meshes.gd", b"extends RefCounted\n", true),
        ("fx_pool.gd", b"extends RefCounted\n", true),
        ("hud_ui.gd", b"extends RefCounted\n", true),
        ("self_test.gd", b"extends RefCounted\n", true),
        ("team_support.gd", b"extends RefCounted\n", true),
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

    let bots_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"lobby-bots\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node\n# bots", true),
        ("junk_platform.gd", b"extends Node\n", true),
    ]);
    let bots_zip = root.join("bots.zip");
    fs::write(&bots_zip, &bots_zip_bytes).unwrap();
    let bots = make_loader_entry_from_catalog("lobby-bots", &bots_zip_bytes, &baseline);

    let mods = vec![roller.clone(), bots.clone()];
    install_from_zip(
        &config_dir,
        &game_root,
        &roller_zip,
        &staging_dir.join("roller"),
        &roller,
        &mods,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    install_from_zip(
        &config_dir,
        &game_root,
        &bots_zip,
        &staging_dir.join("bots"),
        &bots,
        &mods,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();

    struct LockedCheck;
    impl GameLockCheck for LockedCheck {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            Err("gameRunning".into())
        }
    }
    assert_eq!(
        set_mods_enabled(&game_root, &["roller-carnival".into()], false, &LockedCheck).unwrap_err(),
        "gameRunning"
    );
    assert_eq!(
        set_mods_enabled(&game_root, &[".hidden".into()], false, &UnlockedCheck).unwrap_err(),
        "statusUnavailable"
    );

    // Corrupt JSON in .mpm-state.json falls back cleanly without blocking scan or overwrite.
    fs::write(
        pck_dir.join("mods").join(MOD_STATE_FILE),
        b"{not valid json",
    )
    .unwrap();
    let v_corrupt = scan_copy(&config_dir, &game_root, &mods, true).unwrap();
    assert!(v_corrupt.disabled_mods.is_empty());

    // Disable both mods -> loader remains installed and fingerprints stay intact.
    set_mods_enabled(
        &game_root,
        &["roller-carnival".into(), "lobby-bots".into()],
        false,
        &UnlockedCheck,
    )
    .unwrap();
    let v_disabled = scan_copy(&config_dir, &game_root, &mods, false).unwrap();
    assert_eq!(v_disabled.mod_states["roller-carnival"], "installed");
    assert_eq!(v_disabled.mod_states["lobby-bots"], "installed");
    assert_eq!(
        v_disabled.disabled_mods,
        vec!["lobby-bots".to_string(), "roller-carnival".to_string()]
    );
    assert!(pck_loader::read_managed_marker(&pck_dir).unwrap().is_some());

    // Re-enable one mod.
    set_mods_enabled(&game_root, &["lobby-bots".into()], true, &UnlockedCheck).unwrap();
    let v_partial = scan_copy(&config_dir, &game_root, &mods, false).unwrap();
    assert_eq!(v_partial.disabled_mods, vec!["roller-carnival".to_string()]);

    // Disable lobby-bots again, then uninstall both mods one by one.
    set_mods_enabled(&game_root, &["lobby-bots".into()], false, &UnlockedCheck).unwrap();
    uninstall_mod(
        &config_dir,
        &game_root,
        &roller,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(
        read_disabled_mods(&pck_dir).unwrap(),
        vec!["lobby-bots".to_string()]
    );
    assert!(pck_dir.join("mods").join(MOD_STATE_FILE).is_file());

    let restored = uninstall_mod(
        &config_dir,
        &game_root,
        &bots,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(restored, baseline);
    assert!(!pck_dir.join("mods").join(MOD_STATE_FILE).exists());
    assert!(!pck_dir.join("mods").exists());

    fs::remove_dir_all(root).unwrap();
}
