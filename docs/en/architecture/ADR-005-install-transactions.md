# ADR-005: Mod install transactions and backups

**English** · [简体中文](../../zh-CN/architecture/ADR-005-install-transactions.md) · [繁體中文](../../zh-TW/architecture/ADR-005-install-transactions.md)

Date: 2026-11-18. Status: proposed; to be finalised after the Overtime acceptance on Windows (P2).

## Problem

Mods either patch the game PCK directly or add files for a loader such as MPML. A failed or interrupted write, a Steam update or an unknown manual modification must never leave the player without a working original game.

## Proposed decision

1. Lock the target game copy. Check the game process, game version, disk space, dependencies and existing mods. Distinguish manual installs, clean copies and unknown modifications; a backup of unknown origin is never treated as original.
2. Prepare and verify every required package in staging. Only install methods implemented in the app are allowed; catalog data selects an ID and fixed parameters.
3. Write the install record with pre-change fingerprints, the backup and any offline uninstall tool. When switching between conflicting mods, verify restoration before applying the new one.
4. Run the upstream CLI, a verified script, or add the mod to the loader directory. Keep the exit status, read back target files, and only then record mod version, post-install fingerprints, owned files and dependencies.
5. After interruption, use the record and the real disk state to tell original, installed or needs-repair. Restore from the same copy's backup when safe. If Steam updated the game or the player changed files, stop overwriting and explain the next step.

Partial downloads stay in staging or are removed. A retry resumes only when the same asset is confirmed and the server supports range requests; otherwise it downloads again. Nothing in the old version is touched until every dependency verifies. If an update write fails, the disk state is read back and the effective version or a repair entry is shown.

Before uninstalling, fingerprints are checked again. PCK patches verify the restored PCK; loader mods remove only the files they own. Loaders installed earlier by the player, or still needed by other mods, stay. A transaction's backup is cleaned only after a successful uninstall.

## Alternatives

Relying on Steam "verify integrity" to restore files is simple but needs network access, discards other mods and cannot prove which state is current. Shipping forks of every installer gives full control but multiplies maintenance and licensing work.

## Compatibility

`installations.json` keeps the current keys for reading. The transaction record will be additive and must keep reading existing files.

## Evidence needed

Clean install of Overtime v1.7 on Steam game v2.1.2, launch from Steam, offline uninstall with matching original PCK SHA-256, plus simulated download failure, interrupted write and Steam update, as listed in the [requirements](../requirements.md).
