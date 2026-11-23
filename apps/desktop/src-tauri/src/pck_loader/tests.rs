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

        let state = ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(()))
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
        let state2 = ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(()))
            .unwrap()
            .unwrap();
        assert_eq!(state2, state);
        assert_eq!(
            file_fingerprint(&pck_path).unwrap().size,
            state.patched_size
        );

        // Lossless restore returns exact byte size and SHA-256
        let restored = restore_managed_loader(&pck_dir, &backup_pck, || Ok(())).unwrap();
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
    let mut marker = ensure_loader_installed(dir, &backup, &baseline, || Ok(()))
        .unwrap()
        .unwrap();
    let installed = fs::read(&pck).unwrap();
    marker.dir_field += 1;
    fs::write(sidecar_path(dir), serde_json::to_vec(&marker).unwrap()).unwrap();
    fs::write(&backup, b"incomplete backup").unwrap();
    assert_eq!(
        restore_managed_loader(dir, &backup, || Ok(())).unwrap_err(),
        "restoreVerifyFailed"
    );
    assert_eq!(fs::read(&pck).unwrap(), installed);
    assert_eq!(read_managed_marker(dir).unwrap(), Some(marker));
}

#[test]
fn starting_the_game_before_commit_preserves_live_pck_and_marker() {
    let root = tempfile::tempdir().unwrap();
    let dir = root.path();
    let pck = dir.join("Machine Party.pck");
    fs::write(&pck, build_synthetic_pck_v3(false, true)).unwrap();
    let original = file_fingerprint(&pck).unwrap();
    let baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: original.size,
        sha256: original.sha256.clone(),
    };
    let backup = dir.join("backup.pck");
    let running = || Err("gameRunning".to_owned());
    assert_eq!(
        ensure_loader_installed(dir, &backup, &baseline, running).unwrap_err(),
        "gameRunning"
    );
    assert_eq!(file_fingerprint(&pck).unwrap(), original);
    assert!(!sidecar_path(dir).exists());

    let marker = ensure_loader_installed(dir, &backup, &baseline, || Ok(()))
        .unwrap()
        .unwrap();
    let installed = file_fingerprint(&pck).unwrap();
    assert_eq!(
        restore_managed_loader(dir, &backup, running).unwrap_err(),
        "gameRunning"
    );
    assert_eq!(file_fingerprint(&pck).unwrap(), installed);
    assert_eq!(read_managed_marker(dir).unwrap(), Some(marker));
    assert_eq!(
        restore_managed_loader(dir, &backup, || Ok(())).unwrap(),
        original
    );
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
    ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(())).unwrap();

    fs::write(&pck_path, b"STEAM_UPDATED_PCK").unwrap();
    assert_eq!(
        restore_managed_loader(&pck_dir, &backup_pck, || Ok(())).unwrap_err(),
        "gameUpdatedOrModified"
    );
    assert_eq!(
        ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(())).unwrap_err(),
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
        ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(())).unwrap(),
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
        ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(())).unwrap_err(),
        "fileWriteError"
    );
    assert_eq!(file_fingerprint(&pck_path).unwrap(), old_patched);
    assert_eq!(
        read_managed_marker(&pck_dir).unwrap().as_ref(),
        Some(&old_marker)
    );
    fs::remove_dir(&backup_pck).unwrap();
    let old_bytes = fs::read(&pck_path).unwrap();
    let upgraded = ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(()))
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
    let restored = restore_managed_loader(&pck_dir, &backup_pck, || Ok(())).unwrap();
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

    let state = ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(()))
        .unwrap()
        .expect("managed loader applied to v2.1.2 PCK");
    assert_eq!(state.vanilla_sha256, vanilla_fp.sha256);

    let parsed = PckArchive::open(&pck_path).unwrap();
    let guard: serde_json::Value = serde_json::from_str(include_str!(
        "../../assets/recipes/overtime/vanilla_md5.json"
    ))
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

    let restored = restore_managed_loader(&pck_dir, &backup_pck, || Ok(())).unwrap();
    assert_eq!(restored, vanilla_fp);
    assert!(!sidecar_path(&pck_dir).exists());
}

#[test]
fn inspect_and_reload_managed_loader_handles_upgrade_force_and_external() {
    let tmp = tempfile::tempdir().unwrap();
    let pck_dir = tmp.path().join("game");
    fs::create_dir_all(&pck_dir).unwrap();
    let pck_path = pck_dir.join("Machine Party.pck");
    let backup_pck = tmp.path().join("backup.pck");
    fs::write(&pck_path, build_synthetic_pck_v3(false, true)).unwrap();
    let vanilla_fp = file_fingerprint(&pck_path).unwrap();
    let baseline = BaselineSpec {
        file: "Machine Party.pck".into(),
        size: vanilla_fp.size,
        sha256: vanilla_fp.sha256.clone(),
    };

    // Vanilla copy has no loader and refuses reload.
    let none = inspect_loader(&pck_dir, &vanilla_fp).unwrap();
    assert_eq!(none.kind, "none");
    assert!(!none.needs_upgrade);
    assert!(!none.can_reload);
    assert_eq!(
        reload_managed_loader(&pck_dir, &backup_pck, &baseline, true, || Ok(())).unwrap_err(),
        "loaderNotInstalled"
    );

    // Install managed loader and verify up-to-date status.
    let installed = ensure_loader_installed(&pck_dir, &backup_pck, &baseline, || Ok(()))
        .unwrap()
        .unwrap();
    let patched_fp = file_fingerprint(&pck_path).unwrap();
    let current = inspect_loader(&pck_dir, &patched_fp).unwrap();
    assert_eq!(current.kind, "managed");
    assert_eq!(current.installed_version.as_deref(), Some(LOADER_VERSION));
    assert!(!current.needs_upgrade);
    assert!(current.can_reload);

    // Simulate an older marker version -> needs_upgrade = true, reload upgrades it cleanly.
    let mut old_marker = installed.clone();
    old_marker.loader_version = "4".into();
    fs::write(
        sidecar_path(&pck_dir),
        serde_json::to_vec_pretty(&old_marker).unwrap(),
    )
    .unwrap();
    let outdated = inspect_loader(&pck_dir, &patched_fp).unwrap();
    assert!(outdated.needs_upgrade);
    assert_eq!(outdated.installed_version.as_deref(), Some("4"));
    assert_eq!(outdated.target_version, LOADER_VERSION);

    let upgraded =
        reload_managed_loader(&pck_dir, &backup_pck, &baseline, false, || Ok(())).unwrap();
    assert_eq!(upgraded.loader_version, LOADER_VERSION);
    let after = inspect_loader(&pck_dir, &file_fingerprint(&pck_path).unwrap()).unwrap();
    assert!(!after.needs_upgrade);

    // Forced reload invokes before_write and succeeds even when already up to date.
    let mut called = false;
    reload_managed_loader(&pck_dir, &backup_pck, &baseline, true, || {
        called = true;
        Ok(())
    })
    .unwrap();
    assert!(called);

    // External loader takes precedence and blocks reload.
    fs::write(pck_dir.join(EXTERNAL_LOADER_EXE), b"ext").unwrap();
    let ext = inspect_loader(&pck_dir, &file_fingerprint(&pck_path).unwrap()).unwrap();
    assert_eq!(ext.kind, "external");
    assert!(!ext.can_reload);
    assert_eq!(
        reload_managed_loader(&pck_dir, &backup_pck, &baseline, true, || Ok(())).unwrap_err(),
        "externalLoaderPresent"
    );
}
