# ADR-009: First-party mods, deterministic R2 packaging, and self-managed loader

**English** · [简体中文](../../zh-CN/architecture/ADR-009-bundled-first-party-mods.md) · [繁體中文](../../zh-TW/architecture/ADR-009-bundled-first-party-mods.md)

Date: 2026-11-19. Status: proposed; verified through L1/L3 simulation on macOS and awaiting physical Windows Steam runtime testing.

## Problem

First-party gameplay mods authored inside this repository (starting with `mods/roller-carnival/`) should ship through the same catalog Worker and Cloudflare R2 download pipeline as third-party mods (`packages/sha256/<sha256>.zip`) so mod updates can be deployed dynamically via the catalog without rebuilding desktop installers or inflating app binaries. At the same time, loader-based mods traditionally forced players to download and run an external `MachinePartyModLoader.exe` manually, preventing single-click setup and automatic restoration when uninstalling the last loader mod.

## Decision

1. **Repository-owned first-party mod source (`mods/<id>/`) and deterministic R2 ZIP packaging (`scripts/pack-mod.mjs`)**:
   - First-party mods live under `mods/<id>/` with a `mod.json` (`"id"` matching `^[a-z0-9-]+$`), clean GDScript sources, and `README.md`.
   - `scripts/pack-mod.mjs` excludes macOS standalone development and documentation entries (`project.godot`, `*_scene.tscn`, `*.sh`, `*.md`, hidden entries, and symlinks) and builds a deterministic `ZIP_STORED` archive named `<id>-<version>.zip` whose size and SHA-256 are pinned in `catalog/mods.json` identically to every other catalog entry.
   - `.github/workflows/catalog-worker.yml` runs `node scripts/pack-mod.mjs --all --verify-catalog`, stages each `packages/sha256/<sha256>.zip` object into Cloudflare R2, verifies every `mirrorApproved` package in R2 before publishing `catalog/revisions/<revision>.json`, and deploys `services/catalog-worker`.
2. **Built-in clean-room loader (`pck_loader.rs` + `assets/mpm_bootstrap.gd`)**:
   - Written from scratch under GPL-3.0-only without redistributing third-party binaries or upstream loader code.
   - When a `loader-files` catalog entry sets `adapter.autoLoader: true`, `installer.rs` invokes `pck_loader::ensure_loader_installed` during `install_from_zip` before extracting staged mod files into `<pckDir>/mods/<id>/`:
     - If an external loader (`MachinePartyModLoader.exe` or an unmanaged `Machine Party.pck.modloader.json`) is present, it leaves that external loader untouched and installs `<pckDir>/mods/<id>/` beside existing mods.
     - Otherwise, it verifies the vanilla PCK baseline size/SHA-256, stores a verified per-copy vanilla backup under `_mpm_loader`, appends patched `project.binary` (`autoload/ModLoader = "*res://modloader/bootstrap.gd"` first) and `modloader/bootstrap.gd` to the GDPC Format 3 archive, reads back and verifies both entries, and records offsets and hashes in `Machine Party.pck.modloader.json` with `"managed_by": "machine-party-mod-manager"`.
   - When the last `loader-files` mod is uninstalled and no external loader or leftover `mods/` subdirectories remain, `installer.rs` invokes `pck_loader::restore_managed_loader` to restore the original `dir_offset`, truncate the PCK back to its exact vanilla size, verify the vanilla SHA-256, remove `Machine Party.pck.modloader.json`, and clean `_mpm_loader`. If Steam updated the PCK in between, restoration stops with `gameUpdatedOrModified`.
3. **Uniform catalog and UI presentation**:
   - `catalog/mods.json` uses the exact same `package` metadata (`assetId`, `filename`, `size`, `sha256`, `mirrorApproved: true`) and optional `adapter.autoLoader: true` (allowed only on `kind: "loader-files"`) without special UI badges, special repo overrides, or extra notes.
   - The UI downloads, caches, verifies, installs, and displays repo-authored mods identically to every other catalog entry.

## Alternatives

- **Embedding `mods/<id>/` directly inside desktop installers at compile time**: forces an app binary rebuild/release for every mod update instead of serving mods through R2 and the catalog Worker.
- **Embedding third-party `MachinePartyModLoader.exe` binaries**: rejected for GPL-3.0-only notice hygiene and antivirus/subprocess fragility compared to native Rust GDPC v3 append/truncate logic.
- **Requiring manual upstream MPML installation**: prevents one-click installation and prevents clean automatic vanilla restoration on uninstall.

## Compatibility

- `catalog/mods.json` stays `schema: 1`; `autoLoader` defaults to `false` when omitted.
- `installations.json`, `game-path.json`, Tauri IPC command names, and existing `upstream-cli` / `loader-files` third-party mods remain unchanged.
- Coexists safely with external `MachinePartyModLoader.exe` and allows all `loader-files` mods (`Overtime` MPML, `MachineParty+`, `Roller Carnival`) to share one managed loader, while strictly distinguishing manager-owned `modConflict` (switchable in one click) from external `loaderConflict` against direct PCK patchers such as `Broadcast 8P Freecam` and `Binary1936 8P`.
- `mpm_bootstrap.gd` initializes mods in `_init()` (before subsequent autoloads such as `NetworkManager` are cached) and adds mod nodes + runs `_mod_ready` in `_ready()`, while `ensure_loader_installed` transparently upgrades older manager-owned bootstraps.
- Both loading mechanisms cannot run simultaneously on one `Machine Party.pck`: `autoLoader` alters `project.binary` and the GDPC index (triggering `baselineMismatch` in PCK patchers), whereas PCK patchers alter `.gdc` hashes and rebuild the PCK (breaking MPML `vanilla_md5.json` gates and stripping `autoload/ModLoader`).

## Evidence

- `scripts/pack-mod.mjs` produces a deterministic `roller-carnival-0.1.0.zip` verified by `tests/contracts/catalog.test.mjs` and `tests/contracts/online-catalog.test.mjs`.
- `apps/desktop/src-tauri/assets/mpm_bootstrap.gd` and `mods/roller-carnival/` pass Godot 4.5.2 headless script verification and `--self-test` on macOS.
- Rust `pck_loader` and `installer` L1 unit tests (including `l1_zip_loader_mod_auto_installs_and_restores_loader_on_last_uninstall`) and L3 verification on an isolated copy of Steam v2.1.2 `Machine Party.pck` (`634,798,100` bytes) confirm idempotent patching, read-back verification, Steam-update tamper rejection, and byte-for-byte restoration of vanilla SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`.
- Physical Windows Steam runtime testing (`LobbyScene`, playlist selection, intermission picker, multiplayer RPC, R2 download + install + uninstall restore) remains pending Windows acceptance.
