# ADR-005: Mod install transactions and backups

**English** · [简体中文](../../zh-CN/architecture/ADR-005-install-transactions.md) · [繁體中文](../../zh-TW/architecture/ADR-005-install-transactions.md)

Date: 2026-11-18. Status: proposed; to be finalised after the Overtime acceptance on Windows (P2).

## Problem

Mods either patch the game PCK directly or add files for a loader such as MPML. A failed or interrupted write, a Steam update or an unknown manual modification must never leave the player without a working original game.

## Proposed decision

1. Lock the target game copy. Resolve the Steam game root (used as the key in `installations.json`) to the directory that actually contains `Machine Party.pck` (such as `Machine Party_Windows`), check the game process, game version, disk space, dependencies and existing mods. Distinguish manual installs, clean copies and unknown modifications; an unmanaged installation detected on disk may be adopted or uninstalled only when its restore record's baseline SHA-256 matches the known vanilla PCK fingerprint, and a backup of unknown origin is never treated as original.
2. Download required packages in Rust from the Worker endpoint into staging and verify outer archive byte size and SHA-256, then extract unmodified upstream files and check inner manifests (`SHA256SUMS.txt` and/or preflight check). Only install methods implemented in the app are allowed ([ADR-007](ADR-007-mod-adapters.md)); catalog data selects an ID and fixed declarative parameters.
3. Compute and record the pre-change baseline SHA-256 and byte size in the install record, using a tiered backup: mirror delta restore data (`overtime_restore.dat`) and any offline uninstall tool (`overtime_install.exe`) into the app's per-copy storage when supported, and store an app-managed full PCK backup for patchers without verified restore data or for the built-in loader (`_mpm_loader`). When switching between conflicting modes (`switch_from_zip`), stage and preflight-verify the target package first, uninstall all conflicting manager-owned mods, verify `Machine Party.pck` matches the vanilla baseline, and only then apply the new mod. Direct PCK patching and loader modes cannot share the same PCK because loader setup alters `project.binary` and the GDPC index (breaking PCK patcher vanilla SHA-256 checks) while PCK patchers alter script `.gdc` hashes (breaking loader MD5 gates and `autoload/ModLoader`).
4. Run the upstream CLI, a verified script, or add the mod to the loader directory through the built-in adapter ([ADR-007](ADR-007-mod-adapters.md)). Keep the exit status, read back target files and confirm no undeclared files changed, and only then record mod version, post-install fingerprints, owned files and dependencies.
5. After interruption, use the record and the real disk state to tell original, installed or needs-repair. Restore from the same copy's backup when safe. If Steam updated the game or the player changed files, stop overwriting and explain the next step.

Partial downloads stay in staging or are removed. A retry resumes only when the same asset is confirmed and the server supports range requests; otherwise it downloads again. Nothing in the old version is touched until every dependency verifies. If an update write fails, the disk state is read back and the effective version or a repair entry is shown.

Before uninstalling, fingerprints are checked again. PCK patches verify the restored PCK; loader mods remove only the files they own. Loaders installed earlier by the player, or still needed by other mods, stay. A transaction's backup is cleaned only after a successful uninstall.

## Alternatives

Relying on Steam "verify integrity" to restore files is simple but needs network access, discards other mods and cannot prove which state is current. Shipping forks of every installer gives full control but multiplies maintenance and licensing work.

## Compatibility

`installations.json` keeps the current keys for reading. The transaction record will be additive and must keep reading existing files.

## Evidence needed

Clean install of Overtime v1.7 on Steam game v2.1.2, launch from Steam, offline uninstall with matching original PCK SHA-256, plus simulated download failure, interrupted write and Steam update, as listed in the [requirements](../requirements.md).
