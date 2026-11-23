use std::collections::BTreeMap;

use super::*;
use crate::catalog::ModRequirement;

fn make_loader_mod(
    id: &str,
    order: u32,
    version: &str,
    role: Option<&str>,
    requires: Vec<ModRequirement>,
    zip_bytes: &[u8],
    baseline: &FileFingerprint,
) -> ModEntry {
    ModEntry {
        inventory_by_id: true,
        legacy_inventory_repos: Vec::new(),
        id: id.into(),
        order,
        repo: "JamesGZM/machine-party-mod-manager".into(),
        version: Some(version.into()),
        verified: true,
        package: Some(PackageSpec {
            asset_id: "9999".into(),
            filename: format!("{id}-{version}.zip"),
            size: zip_bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(zip_bytes)),
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
            auto_loader: true,
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
        requires,
        role: role.map(str::to_owned),
    }
}

#[test]
fn resolves_dag_topologically_and_rejects_cycles_missing_and_old_versions() {
    let dummy_fp = FileFingerprint {
        size: 100,
        sha256: "0".repeat(64),
    };
    let zip = b"PK\x03\x04";
    let core = make_loader_mod(
        "mpm-core",
        1,
        "v0.2.0",
        Some("library"),
        vec![],
        zip,
        &dummy_fp,
    );
    assert!(core.is_library());
    let mid = make_loader_mod(
        "mid-lib",
        2,
        "v0.1.0",
        Some("library"),
        vec![ModRequirement {
            id: "mpm-core".into(),
            min_version: Some("v0.1.0".into()),
        }],
        zip,
        &dummy_fp,
    );
    let leaf = make_loader_mod(
        "leaf-mod",
        3,
        "v0.1.0",
        None,
        vec![
            ModRequirement {
                id: "mid-lib".into(),
                min_version: None,
            },
            ModRequirement {
                id: "mpm-core".into(),
                min_version: Some("v0.2.0".into()),
            },
        ],
        zip,
        &dummy_fp,
    );

    let order = deps::resolve_install_order("leaf-mod", &[core.clone(), mid.clone(), leaf.clone()])
        .unwrap();
    let ids: Vec<&str> = order.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(ids, vec!["mpm-core", "mid-lib", "leaf-mod"]);

    let missing_err =
        deps::resolve_install_order("leaf-mod", &[mid.clone(), leaf.clone()]).unwrap_err();
    assert!(missing_err.starts_with("dependencyMissing"));

    let old_core = make_loader_mod(
        "mpm-core",
        1,
        "v0.1.0",
        Some("library"),
        vec![],
        zip,
        &dummy_fp,
    );
    let ver_err = deps::resolve_install_order("leaf-mod", &[old_core, mid, leaf]).unwrap_err();
    assert!(ver_err.starts_with("dependencyVersion"));

    let cyc_a = make_loader_mod(
        "cyc-a",
        4,
        "v0.1.0",
        None,
        vec![ModRequirement {
            id: "cyc-b".into(),
            min_version: None,
        }],
        zip,
        &dummy_fp,
    );
    let cyc_b = make_loader_mod(
        "cyc-b",
        5,
        "v0.1.0",
        None,
        vec![ModRequirement {
            id: "cyc-a".into(),
            min_version: None,
        }],
        zip,
        &dummy_fp,
    );
    assert_eq!(
        deps::resolve_install_order("cyc-a", &[cyc_a, cyc_b]).unwrap_err(),
        "dependencyCycle"
    );
}

#[test]
fn dependency_install_rollback_disable_guard_and_auto_cleanup() {
    let root = test_root("deps-lifecycle");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(true, true);
    let (game_root, pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

    let core_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"mpm-core\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let core_zip = root.join("mpm-core.zip");
    fs::write(&core_zip, &core_zip_bytes).unwrap();

    let game_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"sample-game\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let game_zip = root.join("sample-game.zip");
    fs::write(&game_zip, &game_zip_bytes).unwrap();

    let bad_zip = root.join("bad-game.zip");
    fs::write(&bad_zip, b"not-a-zip").unwrap();

    let core = make_loader_mod(
        "mpm-core",
        1,
        "v0.1.0",
        Some("library"),
        vec![],
        &core_zip_bytes,
        &baseline,
    );
    let sample = make_loader_mod(
        "sample-game",
        2,
        "v0.1.0",
        None,
        vec![ModRequirement {
            id: "mpm-core".into(),
            min_version: Some("v0.1.0".into()),
        }],
        &game_zip_bytes,
        &baseline,
    );
    let all_mods = vec![core.clone(), sample.clone()];
    let config = root.join("config");
    let staging = root.join("staging");
    let runner = FakeCliRunner {
        vanilla_bytes: pck_bytes.clone(),
        vanilla_sha: baseline.sha256.clone(),
        fault: FakeFault::None,
        calls: RefCell::new(Vec::new()),
    };

    // 1. Failure on target rolls back newly auto-installed mpm-core and restores vanilla PCK.
    let mut bad_zips = BTreeMap::new();
    bad_zips.insert("mpm-core".into(), core_zip.clone());
    bad_zips.insert("sample-game".into(), bad_zip);
    let fail = deps::install_with_dependencies(
        &config,
        &game_root,
        &sample,
        &bad_zips,
        &staging,
        &all_mods,
        &runner,
        &UnlockedCheck,
    );
    assert!(fail.is_err());
    assert!(!pck_dir.join("mods/mpm-core").exists());
    assert_eq!(
        file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
        baseline
    );

    // 2. Clean install auto-installs mpm-core with auto_installed = true.
    let mut ok_zips = BTreeMap::new();
    ok_zips.insert("mpm-core".into(), core_zip);
    ok_zips.insert("sample-game".into(), game_zip);
    let installed = deps::install_with_dependencies(
        &config,
        &game_root,
        &sample,
        &ok_zips,
        &staging,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(installed.len(), 2);
    assert!(installed[0].auto_installed);
    assert!(!installed[1].auto_installed);

    // 3. Cannot disable or uninstall mpm-core while sample-game is active/installed.
    let dis_err = deps::check_disable_allowed(&config, &game_root, &["mpm-core".into()], &all_mods)
        .unwrap_err();
    assert!(dis_err.starts_with("dependencyRequiredBy: sample-game"));
    assert!(
        deps::check_disable_allowed(
            &config,
            &game_root,
            &["mpm-core".into(), "sample-game".into()],
            &all_mods
        )
        .is_ok()
    );

    let un_err = deps::uninstall_with_auto_cleanup(
        &config,
        &game_root,
        &core,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap_err();
    assert!(un_err.starts_with("dependencyRequiredBy: sample-game"));

    // 4. Uninstalling last dependent auto-removes auto_installed mpm-core and restores vanilla PCK.
    let removed = deps::uninstall_with_auto_cleanup(
        &config,
        &game_root,
        &sample,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(removed, vec!["sample-game", "mpm-core"]);
    assert!(!pck_dir.join("mods/mpm-core").exists());
    assert_eq!(
        file_fingerprint(&pck_dir.join("Machine Party.pck")).unwrap(),
        baseline
    );

    // 5. Manually installed mpm-core (auto_installed = false) is preserved after dependent uninstall.
    install_from_zip(
        &config,
        &game_root,
        &ok_zips["mpm-core"],
        &staging.join("mpm-core-manual"),
        &core,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    deps::install_with_dependencies(
        &config,
        &game_root,
        &sample,
        &ok_zips,
        &staging,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    let removed_manual = deps::uninstall_with_auto_cleanup(
        &config,
        &game_root,
        &sample,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(removed_manual, vec!["sample-game"]);
    assert!(pck_dir.join("mods/mpm-core").is_dir());
}

#[test]
fn ensure_dependencies_installed_installs_missing_and_skips_existing() {
    let root = test_root("deps-ensure");
    let config = root.join("config");
    let staging = root.join("staging");
    let pck_bytes = pck_loader::build_synthetic_pck_v3(true, true);
    let (game_root, _pck_dir, baseline) = setup_synthetic_game(&root, &pck_bytes);

    let core_zip_bytes = build_test_zip(&[
        (
            "mod.json",
            b"{\"id\":\"mpm-core\",\"entry\":\"main.gd\"}",
            true,
        ),
        ("main.gd", b"extends Node", true),
    ]);
    let core_zip = root.join("mpm-core.zip");
    fs::write(&core_zip, &core_zip_bytes).unwrap();
    let core = make_loader_mod(
        "mpm-core",
        1,
        "v0.1.0",
        Some("library"),
        vec![],
        &core_zip_bytes,
        &baseline,
    );
    let sample = make_loader_mod(
        "sample-game",
        2,
        "v0.2.0",
        None,
        vec![ModRequirement {
            id: "mpm-core".into(),
            min_version: Some("v0.1.0".into()),
        }],
        &core_zip_bytes,
        &baseline,
    );
    let all_mods = vec![core.clone(), sample.clone()];
    let mut zips = BTreeMap::new();
    zips.insert("mpm-core".into(), core_zip);
    let runner = SystemRunner;

    let (newly_installed, recs) = deps::ensure_dependencies_installed(
        &config,
        &game_root,
        &sample,
        &zips,
        &staging,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert_eq!(newly_installed.len(), 1);
    assert_eq!(newly_installed[0].id, "mpm-core");
    assert!(recs[0].auto_installed);

    // Calling again when mpm-core already satisfies min_version is a no-op.
    let (newly_installed_2, recs_2) = deps::ensure_dependencies_installed(
        &config,
        &game_root,
        &sample,
        &BTreeMap::new(),
        &staging,
        &all_mods,
        &runner,
        &UnlockedCheck,
    )
    .unwrap();
    assert!(newly_installed_2.is_empty());
    assert_eq!(recs_2.len(), 1);
}
