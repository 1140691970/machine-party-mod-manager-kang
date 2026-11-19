# ADR-011 · Prepare MPML before installation

**English** · [简体中文](../../zh-CN/architecture/ADR-011-prepare-mpml.md) · [繁體中文](../../zh-TW/architecture/ADR-011-prepare-mpml.md)

The one-click installer verifies the original release ZIP against its catalog size and SHA-256. Rust prepares the MPML directory in staging. Overtime uses its CLI payload manifest and retains the upstream load-order, version and vanilla-script checks. Broadcast and Binary1936 use their resource trees. MachineParty+, Roller Carnival and Lobby Bots already ship in loader format.

Binary1936 and Broadcast share the resource-tree converter in `src/installer/prepare.rs` and the MPML entry template in `assets/recipes/resource_tree.gd` under `apps/desktop/src-tauri/`. For Binary1936 v1.5 it packages 40 scripts and 16 scenes in `overlay.zip`, writes their remaps, and generates `main.gd` with the catalog mod ID.

The installer records the source digest, recipe revision and installed file fingerprints. The three eight-player conversions share an exclusive gameplay group. Other loader mods can stay installed when a group member changes. A separate converted download would add a second release artifact to maintain; executing each upstream installer would keep different backup and recovery procedures.

Older clients receive their compatible catalog and download URLs. Existing Overtime MPML installations keep working. Select the migration action in the details of a managed legacy PCK patch to verify the replacement, restore the recorded copy, and install through the loader. Move a manual mods/broadcast-8p folder out of the game first. Unknown file changes stop recovery.

Installing, upgrading or removing the built-in loader prepares and verifies a temporary PCK on the game drive before replacing the live file. Allow space for an extra PCK (about 606 MiB for v2.1.2) in addition to backups. During a loader upgrade the manager records both loader fingerprints so it can identify the active version after an interruption.

Release-fixture checks compare 70 compiled Overtime scripts and the resource trees of 65 Broadcast and 56 Binary1936 files. Steam multiplayer acceptance remains pending.
