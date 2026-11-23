use super::*;

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
        uninstall_mod(&config_dir, &game_root, &mod_entry, &runner, &UnlockedCheck).unwrap_err(),
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

#[test]
fn steam_restore_cleans_a_recorded_legacy_delta_after_steam_replaces_the_pck() {
    let root = tempfile::tempdir().unwrap();
    let vanilla = build_synthetic_pck();
    let (game, dir, baseline) = setup_synthetic_game(root.path(), &vanilla);
    let zip = make_fake_package_zip(b"FAKE_EXE", b"FAKE_PAYLOAD");
    let path = root.path().join("overtime.zip");
    fs::write(&path, &zip).unwrap();
    let old = synthetic_overtime_entry(&baseline, &zip, true);
    let config = root.path().join("config");
    let runner = FakeCliRunner {
        vanilla_bytes: vanilla.clone(),
        vanilla_sha: baseline.sha256.clone(),
        fault: FakeFault::None,
        calls: RefCell::new(Vec::new()),
    };
    install_from_zip(
        &config,
        &game,
        &path,
        &root.path().join("stage"),
        &old,
        std::slice::from_ref(&old),
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let mut current = crate::catalog::entry("overtime").unwrap();
    current.adapter.as_mut().unwrap().baseline = old.adapter.unwrap().baseline;
    steam_restore::restore(&config, &game, &dir, &[current], &UnlockedCheck, || {
        assert!(dir.join(RESTORE_DAT).is_file());
        fs::write(dir.join("Machine Party.pck"), vanilla).unwrap();
        Ok(())
    })
    .unwrap();
    assert!(!dir.join(RESTORE_DAT).exists());
    assert_eq!(
        file_fingerprint(&dir.join("Machine Party.pck")).unwrap(),
        baseline
    );
    assert!(
        get_transaction(&config, &game, "overtime")
            .unwrap()
            .is_none()
    );
}

#[test]
fn interrupted_steam_cleanup_resumes_through_another_spelling_of_the_copy() {
    let root = tempfile::tempdir().unwrap();
    let vanilla = pck_loader::build_synthetic_pck_v3(false, true);
    let (game, dir, baseline) = setup_synthetic_game(root.path(), &vanilla);
    // Keep the spelling used to install distinct from the Steam registration.
    let alias = root.path().join("via");
    fs::create_dir(&alias).unwrap();
    let alias = alias.join("..").join(game.file_name().unwrap());
    assert_ne!(alias, game);
    let config = root.path().join("config");
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"managed", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &baseline);
    let items = std::slice::from_ref(&item);
    let zip = root.path().join("source.zip");
    fs::write(&zip, bytes).unwrap();
    install_from_zip(
        &config,
        &alias,
        &zip,
        &root.path().join("stage"),
        &item,
        items,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();

    struct InterruptAfterRemoval(PathBuf);
    impl GameLockCheck for InterruptAfterRemoval {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            if self.0.exists() {
                Ok(())
            } else {
                Err("gameRunning".into())
            }
        }
    }
    let owned = loader_mod_dir(&dir, &item).join("main.gd");
    let lock = InterruptAfterRemoval(owned.clone());
    assert_eq!(
        steam_restore::restore(&config, &game, &dir, items, &lock, || {
            fs::write(dir.join("Machine Party.pck"), &vanilla).unwrap();
            Ok(())
        })
        .unwrap_err(),
        "gameRunning"
    );
    assert!(!owned.exists());
    assert!(steam_restore::pending(&config, &dir).unwrap());
    assert!(
        get_transaction(&config, &alias, &item.id)
            .unwrap()
            .is_some()
    );
    let manifest = owned.with_file_name("mod.json");
    let original = fs::read(&manifest).unwrap();
    fs::write(&manifest, b"edited after interruption").unwrap();
    assert!(
        steam_restore::recover(&config, &game, items, &UnlockedCheck)
            .unwrap_err()
            .contains("gameUpdatedOrModified")
    );
    assert_eq!(fs::read(&manifest).unwrap(), b"edited after interruption");
    fs::write(&manifest, original).unwrap();
    assert!(steam_restore::recover(&config, &game, items, &UnlockedCheck).unwrap());
    assert!(!steam_restore::recover(&config, &alias, items, &UnlockedCheck).unwrap());
    assert!(!owned.parent().unwrap().exists());
    assert!(
        get_transaction(&config, &alias, &item.id)
            .unwrap()
            .is_none()
    );
    assert!(
        inventory::installed_versions(&config, &alias)
            .unwrap()
            .is_empty()
    );
    inventory::record_installed(&config, &alias, "orphan", "v1").unwrap();
    assert_eq!(
        steam_restore::restore(&config, &game, &dir, items, &UnlockedCheck, || panic!(
            "must keep unaccounted installations"
        ))
        .unwrap_err(),
        "missingTransaction"
    );
}

#[test]
fn steam_restore_keeps_owned_files_until_success_and_preserves_manual_mods() {
    let root = tempfile::tempdir().unwrap();
    let vanilla = pck_loader::build_synthetic_pck_v3(false, true);
    let (game, dir, baseline) = setup_synthetic_game(root.path(), &vanilla);
    let config = root.path().join("config");
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &baseline);
    let mods = std::slice::from_ref(&item);
    let zip = root.path().join("release.zip");
    fs::write(&zip, bytes).unwrap();
    install_from_zip(
        &config,
        &game,
        &zip,
        &root.path().join("stage"),
        &item,
        mods,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    let manual = dir.join("mods/manual");
    fs::create_dir(&manual).unwrap();
    fs::write(manual.join("keep.gd"), b"player").unwrap();
    let owned = loader_mod_dir(&dir, &item).join("main.gd");
    let restore = |verify: &dyn Fn() -> Result<(), String>| {
        steam_restore::restore(&config, &game, &dir, mods, &UnlockedCheck, verify)
    };
    assert_eq!(
        restore(&|| Err("steamRestoreUnconfirmed".into())).unwrap_err(),
        "steamRestoreUnconfirmed"
    );
    assert_eq!(restore(&|| Ok(())).unwrap_err(), "baselineMismatch");
    struct Relaunched(std::cell::Cell<bool>);
    impl GameLockCheck for Relaunched {
        fn ensure_unlocked(&self, _: &Path, _: &Path) -> Result<(), String> {
            if self.0.get() {
                Err("gameRunning".into())
            } else {
                Ok(())
            }
        }
    }
    let relaunched = Relaunched(false.into());
    assert_eq!(
        steam_restore::restore(&config, &game, &dir, mods, &relaunched, || {
            relaunched.0.set(true);
            Ok(())
        })
        .unwrap_err(),
        "gameRunning"
    );
    assert!(owned.is_file());
    assert!(get_transaction(&config, &game, &item.id).unwrap().is_some());
    assert!(
        restore(&|| {
            fs::write(dir.join("Machine Party.pck"), &vanilla).unwrap();
            fs::write(&owned, b"player edit").unwrap();
            Ok(())
        })
        .unwrap_err()
        .contains("gameUpdatedOrModified")
    );
    assert_eq!(fs::read(&owned).unwrap(), b"player edit");
    fs::write(&owned, b"extends Node").unwrap();
    restore(&|| Ok(())).unwrap();
    assert!(!owned.parent().unwrap().exists());
    assert!(!dir.join(pck_loader::LOADER_SIDECAR).exists());
    assert_eq!(fs::read(manual.join("keep.gd")).unwrap(), b"player");
    assert!(
        inventory::installed_versions(&config, &game)
            .unwrap()
            .is_empty()
    );
    assert!(get_transaction(&config, &game, &item.id).unwrap().is_none());
    assert_eq!(
        file_fingerprint(&dir.join("Machine Party.pck")).unwrap(),
        baseline
    );
    assert!(
        fs::read_dir(backup_dir_for(&config, &game, "_steam_restore"))
            .unwrap()
            .any(|e| e
                .unwrap()
                .path()
                .join("mods/machineparty-plus/main.gd")
                .is_file())
    );
}

#[test]
fn clean_game_reinstall_allows_clearing_a_committed_mpml_record_and_reinstalling() {
    let root = tempfile::tempdir().unwrap();
    let vanilla = pck_loader::build_synthetic_pck_v3(false, true);
    let (game, dir, baseline) = setup_synthetic_game(root.path(), &vanilla);
    let config = root.path().join("config");
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &baseline);
    let mods = std::slice::from_ref(&item);
    let archive = root.path().join("release.zip");
    fs::write(&archive, bytes).unwrap();
    let install = || {
        install_from_zip(
            &config,
            &game,
            &archive,
            &root.path().join("stage"),
            &item,
            mods,
            &SystemRunner,
            &UnlockedCheck,
        )
        .unwrap()
    };
    install();
    fs::remove_dir_all(dir.join("mods")).unwrap();
    fs::remove_file(dir.join(pck_loader::LOADER_SIDECAR)).unwrap();
    fs::write(dir.join("Machine Party.pck"), vanilla).unwrap();
    let scan = validate_game_mods(&config, &game, mods).unwrap();
    assert_eq!(scan.mod_states[&item.id], "needsRepair");
    assert!(scan.repair.contains_key(&item.id));
    assert_eq!(
        uninstall_mod(&config, &game, &item, &SystemRunner, &UnlockedCheck).unwrap(),
        baseline
    );
    assert!(
        inventory::installed_versions(&config, &game)
            .unwrap()
            .is_empty()
    );
    install();
    assert_eq!(
        validate_game_mods(&config, &game, mods).unwrap().mod_states[&item.id],
        "installed"
    );
}

#[test]
fn missing_loader_files_and_interrupted_cleanup_keep_the_transaction_recoverable() {
    let root = tempfile::tempdir().unwrap();
    let vanilla = pck_loader::build_synthetic_pck_v3(false, true);
    let (game, dir, baseline) = setup_synthetic_game(root.path(), &vanilla);
    let config = root.path().join("config");
    let bytes = build_test_zip(&[
        (
            "mod.json",
            br#"{"id":"machineparty_plus","entry":"main.gd"}"#,
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let item = make_loader_entry_from_catalog("machineparty-plus", &bytes, &baseline);
    let mods = std::slice::from_ref(&item);
    let archive = root.path().join("release.zip");
    fs::write(&archive, bytes).unwrap();
    let mut tx = install_from_zip(
        &config,
        &game,
        &archive,
        &root.path().join("staging"),
        &item,
        mods,
        &SystemRunner,
        &UnlockedCheck,
    )
    .unwrap();
    let state = || validate_game_mods(&config, &game, mods).unwrap().mod_states[&item.id].clone();
    let marker = dir.join(pck_loader::LOADER_SIDECAR);
    let marker_bytes = fs::read(&marker).unwrap();
    let backup = backup_dir_for(&config, &game, "_mpm_loader").join("Machine Party.pck");
    let mut damaged: pck_loader::ManagedLoaderState =
        serde_json::from_slice(&marker_bytes).unwrap();
    damaged.dir_field += 1;
    fs::write(&marker, serde_json::to_vec(&damaged).unwrap()).unwrap();
    fs::write(&backup, b"damaged backup").unwrap();
    assert_eq!(
        uninstall_mod(&config, &game, &item, &SystemRunner, &UnlockedCheck).unwrap_err(),
        "restoreVerifyFailed"
    );
    assert_eq!(
        get_transaction(&config, &game, &item.id)
            .unwrap()
            .unwrap()
            .status,
        TransactionStatus::Committed
    );
    assert_eq!(
        collect_dir_fingerprints(&loader_mod_dir(&dir, &item)).unwrap(),
        tx.owned_files
    );
    assert_eq!(
        file_fingerprint(&dir.join("Machine Party.pck")).unwrap(),
        *tx.post_pck.as_ref().unwrap()
    );
    fs::write(&backup, &vanilla).unwrap();

    fs::remove_file(&marker).unwrap();
    assert_eq!(state(), "gameUpdatedOrModified");
    assert_eq!(
        uninstall_mod(&config, &game, &item, &SystemRunner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );
    assert!(loader_mod_dir(&dir, &item).is_dir());
    fs::write(&marker, &marker_bytes).unwrap();
    fs::remove_dir_all(loader_mod_dir(&dir, &item)).unwrap();
    assert_eq!(state(), "needsRepair");
    tx.status = TransactionStatus::NeedsRepair;
    tx.failure = Some("uninstall".into());
    tx.restoring_pck = Some(baseline.clone());
    save_transaction(&config, &game, tx).unwrap();
    let pck = dir.join("Machine Party.pck");
    fs::write(&pck, b"unknown modification").unwrap();
    assert_eq!(state(), "gameUpdatedOrModified");
    assert_eq!(
        uninstall_mod(&config, &game, &item, &SystemRunner, &UnlockedCheck).unwrap_err(),
        "gameUpdatedOrModified"
    );
    fs::write(&pck, vanilla).unwrap();
    assert_eq!(state(), "needsRepair");
    let mut updated = item.clone();
    updated.adapter.as_mut().unwrap().baseline.sha256 = "0".repeat(64);
    // The PCK rename and marker cleanup completed before the app stopped.
    fs::remove_file(&marker).unwrap();
    let scan = validate_game_mods(&config, &game, std::slice::from_ref(&updated)).unwrap();
    assert_eq!(scan.mod_states[&item.id], "needsRepair");
    assert_eq!(
        uninstall_mod(&config, &game, &updated, &SystemRunner, &UnlockedCheck).unwrap(),
        baseline
    );
    assert!(!backup.exists());
    assert!(!marker.exists());
    assert!(get_transaction(&config, &game, &item.id).unwrap().is_none());
    assert_eq!(state(), "vanilla");
}
