# ADR-017: Modular boundaries, core library mod, and phased refactoring

**English** · [简体中文](../../zh-CN/architecture/ADR-017-modular-boundaries-and-core-runtime.md) · [繁體中文](../../zh-TW/architecture/ADR-017-modular-boundaries-and-core-runtime.md)

Date: 2026-11-23. Status: Phases 1–5 implemented & verified in automated/headless checks (repo split intentionally deferred per Phase 5 criteria; Windows Steam `v2.1.2` physical verification pending).

## Problem

Rapid feature growth across two distinct cadences — the desktop manager (`apps/desktop/`) and 7 first-party GDScript mods (`mods/`, totaling 20,405 lines across `.gd` sources) — has created four structural bottlenecks that slow development and raise regression risk:

1. **Oversized desktop monoliths and an architecture check gap**:
   - `apps/desktop/src-tauri/src/installer.rs` has grown to 6,360 lines (mixing runner abstractions, ZIP extraction, transactions, state files, conflict rules, copy inspection, two adapter families, and ~3,490 lines of inline tests).
   - `apps/desktop/src-tauri/src/pck_loader.rs` is 1,443 lines (GDPC v3 / ECFG binary codecs mixed with install/restore orchestration and tests).
   - `apps/desktop/ui/catalog-view.js` is 1,053 lines (list rendering, dialogs, single-mod install flows, and batch toolbar/execution).
   - `scripts/check_architecture.mjs` currently enforces Tauri-free boundaries only on six hardcoded top-level `.rs` files (`tauriFree`), leaving submodules such as `apps/desktop/src-tauri/src/installer/update.rs` unchecked.
2. **Oversized mod scripts**:
   - `mods/team-party/main.gd` is 4,570 lines in one file, including ~2,270 lines of Lobby UI and 3D chair dragging plus ~820 lines of ad-hoc external minigame wrappers.
   - First-party minigame scripts (`mods/roller-carnival/roller_carnival_game.gd` at 1,890 lines, `mods/bubble-blitz/bubble_blitz_game.gd` at 2,260 lines, and `mods/spike-ring/spike_ring_game.gd` at 2,785 lines) bundle gameplay, FX/decal pools, and net sync together.
3. **Byte-for-byte duplicated minigame hub overrides**:
   - Per [ADR-015](ADR-015-multi-minigame-hub.md), `override_game.gd` (150 lines), `override_local_game.gd` (137 lines), `override_picker.gd` (251 lines), and `override_playlist.gd` (137 lines) — 675 lines total — are copied identically into `mods/bubble-blitz/`, `mods/roller-carnival/`, and `mods/spike-ring/`. Every hub update currently forces editing and republishing every minigame package.
4. **Game-specific coordination coupled to desktop releases**:
   - `apps/desktop/src-tauri/assets/mpm_bootstrap.gd` (916 lines) embeds 447 lines of Lobby UI de-conflicting inside the signed desktop app binary. Adjusting game-specific lobby layout requires cutting a new desktop app release instead of shipping a catalog/R2 mod update.

## Decision

Adopt a clean 4-layer manager-and-runtime separation modeled after proven open-source modding ecosystems (`GodotModding/godot-mod-loader` + `Brotato-ContentLoader`, `Fabric Loader` + `Fabric API`, `modrinth/code`, `Kesomannen/gale`, and `NexusMods.App`), executed across five independently verifiable phases:

```text
[ Desktop Manager (Rust + vanilla ES UI) ] ── downloads, transactions, requires graph, PCK restore
            │ injects minimal bootstrap
            ▼
[ Minimal Loader (mpm_bootstrap.gd) ]      ── discovery, requires ordering, compile/override/hook primitives
            │ loads library dependency first
            ▼
[ Core Library Mod (mpm-core via R2) ]     ── Minigame Hub v2, Lobby UI coordinator, shared FX/event bus
            │ requires: ["mpm-core"]
            ▼
[ Gameplay & Feature Mods ]                ── roller-carnival / bubble-blitz / spike-ring / team-party / future mods
```

### Phase 1: Architecture guardrails & desktop manager modularization (zero behavior change)

1. **Harden `scripts/check_architecture.mjs`**:
   - Switch from the 6-file `tauriFree` list to an explicit allowlist: every `.rs` file under `apps/desktop/src-tauri/src/` (including nested submodules at any depth) except `main.rs`, `commands.rs`, and `app_updates.rs` must be free of `tauri::` / `tauri_plugin_*::` / `crate::commands` dependencies.
   - Add regression coverage in `tests/architecture/boundaries.test.mjs`.
2. **Split `apps/desktop/src-tauri/src/installer.rs` into `installer/mod.rs` + focused submodules**:
   - Preserve all existing `pub` re-exports in `installer/mod.rs` so `commands.rs` callers remain unchanged, alongside existing `prepare.rs`, `steam_restore.rs`, and `update.rs`:
     - `runner.rs`: `ProcessRunner`, `SystemRunner`, `GameLockCheck`, `SystemGameLockCheck`
     - `zip.rs`: `extract_zip` and path-traversal validation
     - `transaction.rs`: `FileFingerprint`, `TransactionRecord`, backup paths, and `transactions.json` persistence
     - `state.rs`: `.mpm-state.json` enable/disable state management
     - `conflicts.rs`: conflict-group checks and external loader detection
     - `inspect.rs`: `inspect_mod`, `validate_game_mods`, `reconcile_copy`, `adopt_manual_install`, `scan_copy`
     - `adapters/loader.rs`: `normalize_loader_staging`, `install_loader_files`, `resumable_loader_cleanup`
     - `adapters/upstream_cli.rs`: `validate_adapter`, `build_command`, `parse_status`, `parse_mp8r_restore`, `mirror_delta_backup`
     - `tests/`: relocate the ~3,490 lines of inline tests by domain topic.
3. **Split `apps/desktop/src-tauri/src/pck_loader.rs`**:
   - Extract `pck_loader/gdpc.rs` (GDPC v3 index/payload handling, MD5 helpers, ECFG binary codec), `pck_loader/mod.rs` (install/restore/marker state machine), and `pck_loader/tests.rs`.
4. **Split `apps/desktop/ui/catalog-view.js`**:
   - Keep zero-build native ES modules ([ADR-001](ADR-001-project-boundaries.md)) and split into `catalog-view.js` (list + cards), `mod-dialogs.js` (details, update confirmation, uninstall dialogs), `mod-install-flow.js` (single-mod download/install/switch/toggle), and `batch-view.js` (filters and batch toolbar/execution beside `batch.js`).
5. **Size guideline**: Aim for focused production modules (~<=700 lines) with tests isolated in dedicated test files or submodules.

### Phase 2: First-party mod modularization, single-source hub, and native minigame team logic (completed)

1. **Split `mods/team-party/main.gd` and retire custom-minigame source wrappers**:
   - Split `mods/team-party/main.gd` (4,570 lines -> 685 lines) into `team_registry.gd`, `lobby_assignment.gd`, `lobby_ui.gd`, `lobby_drag_3d.gd`, `vanilla_ingame.gd`, and `ingame_hud.gd`, keeping `main.gd` as the entry, RPC endpoint host, and public/test facade so `tests/mods/team_party_test.gd` and `tests/mods/team_party_sandbox.gd` remain compatible.
   - Removed `_wrap_custom_stage` and all ~820 lines of runtime custom-minigame source-rewriting wrappers; `team-party` now handles only room/lobby team assignment, top-right Squad HUD, and official/vanilla minigame hooks.
2. **Eliminate duplicated hub overrides (`override_*.gd`) & share optional team helper**:
   - Established single sources of truth under `mods/_shared/minigame-hub/` and `mods/_shared/team-support/team_support.gd` (without `mod.json`), synced and verified across `bubble-blitz`, `spike-ring`, and `roller-carnival` via `scripts/pack-mod.mjs --sync-shared` and `scripts/check_architecture.mjs` (`checkSharedModParity`).
3. **Native team mode & internal splits across first-party minigames**:
   - `mods/bubble-blitz/` (`v0.1.5`): native team spawns, friendly flame immunity, downed-ally touch rescue, rescue-seeking AI, early team win, and Squads sync, plus extracted `fx_pool.gd`, `ai_controller.gd`, and `self_test.gd`.
   - `mods/spike-ring/` (`v0.1.3`): native team spawns, zero friendly shove, 360° shockwave immunity, 3.5m shield link, enemy-only AI targeting, early team win, and Squads sync, plus extracted `hazard_director.gd`, `fx_pool.gd`, `ai_controller.gd`, and `self_test.gd`.
   - `mods/roller-carnival/` (`v0.1.11`): native team-grouped Z lanes, team rings/nameplates, team-survival early win, and Squads sync, plus extracted `fx_pool.gd`, `hud_ui.gd`, and `self_test.gd`.
   - Re-ran `scripts/pack-mod.mjs --all` and updated `catalog/mods.json` (`revision: 2026-11-23.1-mpml1`).

### Phase 3: Declarative `requires` dependency resolution & `mpm-core` library mod (completed)

1. **Extend `catalog/mods.json` while preserving `schema: 1`**:
   - Add optional per-entry `requires` metadata (e.g., `[{"id": "mpm-core", "minVersion": "v0.1.0"}]`, defaulting to `[]`) and an optional role/category marker for library/core mods so the UI can manage core dependencies cleanly without cluttering gameplay browsing.
2. **Implement dependency resolution in Rust**:
   - **Install / update**: Recursively resolve the dependency DAG in topological order, reject cycles, and install or upgrade missing/outdated prerequisites before the target mod; roll back cleanly on failure.
   - **Disable / uninstall protection**: Reject disabling or uninstalling a library mod while other installed/enabled mods still require it, returning a translatable error key with dependent IDs; automatically clean up auto-installed library mods and restore vanilla `Machine Party.pck` when the last dependent mod is uninstalled.
3. **Introduce `mods/mpm-core/` (delivered through R2 + `catalog-worker`)**:
   - Loads early (`priority: -100`) and consolidates fast-evolving game-side runtime code:
     1. **Minigame Hub v2 (`HUB_VERSION = 2`)**: Cleanly supersedes legacy `HUB_VERSION = 1` overrides during mixed-version transitions.
     2. **Lobby UI coordinator v2**: Absorbs the game-specific Lobby UI de-conflictor from `mpm_bootstrap.gd`, leaving `mpm_bootstrap.gd` as a minimal, infrequently updated loader.
     3. **Shared utilities**: Cross-mod event bus, reusable FX/decal pool primitives, and localization helpers.
4. **Rollout order**: Ship desktop `requires` support and verify on Windows Steam first; only then publish minigame updates declaring `requires: ["mpm-core"]`.

### Phase 4: Method-level hook chain & cross-mod event contracts

1. **Method-level hook chain**:
   - Add a `ModLoaderHookChain`-style method hook primitive in the loader/core layer so multiple system mods can wrap the same vanilla GDScript function in order without whole-script `override_script` collisions.
2. **Standard minigame/team contracts**:
   - Define standard lifecycle hooks and team/scoring signals inside `mpm-core` for future mods and official hooks (Phase 2 already retired the ~820 lines of ad-hoc custom-minigame wrappers in `team-party`).

### Phase 5: Path-scoped CI & repository split criteria (defer repo split)

1. **Path-scoped CI**:
   - Keep a single repository while desktop, loader, and mods co-evolve, scoping PR checks by changed paths (`apps/desktop/**` vs. `mods/**` + `catalog/**`) while preserving full validation before release/merge.
2. **Explicit trigger for splitting `mods/` later**:
   - Defer splitting out a separate `machine-party-mods` repository until: (a) the desktop manager and `mpm-core` APIs stabilize into maintenance cadence, and (b) first-party mods grow beyond ~10–12 entries or accept regular external community PRs. Because [ADR-009](ADR-009-bundled-first-party-mods.md) already unifies first-party and third-party distribution through R2 + `catalog-worker`, a future split will require no distribution redesign.

## Alternatives considered

- **Splitting `mods/` into a separate repository immediately**: Rejected while `mpm_bootstrap.gd`, first-party mods, and cross-mod coexistence tests (`tests/mods/`) still evolve together in single PRs; splitting now adds cross-repo version-locking overhead for no player benefit.
- **Introducing a JS bundler/framework or Cargo workspace**: Rejected per [ADR-001](ADR-001-project-boundaries.md); native ES module splitting and Rust submodules fix monolith sizing without extra toolchains.
- **Migrating local JSON records (`installations.json`, `transactions.json`) to SQLite**: Rejected per [ADR-003](ADR-003-desktop-updates.md); at tens of mods, JSON transactions remain inspectable, simple, and backward-compatible.
- **Keeping all shared runtime UI/hub logic inside `mpm_bootstrap.gd`**: Rejected because every game-side adjustment forces a signed desktop release.

## Compatibility

- Preserves `installations.json`, `game-path.json`, `transactions.json`, `.mpm-state.json`, Tauri IPC command names, updater endpoints/keys, and `catalog/mods.json` `schema: 1` ([ADR-003](ADR-003-desktop-updates.md)).
- Phases 1 and 2 are strictly internal refactors with zero user-facing behavior or storage changes.
- Phase 3 preserves compatibility with older desktop clients (which ignore unknown optional catalog fields) and external `MachinePartyModLoader.exe` setups, and maintains mixed-version safety (`HUB_VERSION = 2` superseding `HUB_VERSION = 1`).

## Evidence and verification gates

- **Phase 1 & Phase 2 completed**:
  - Phase 1: `scripts/check_architecture.mjs` (allowlist covering nested Rust submodules + regression tests in `tests/architecture/boundaries.test.mjs`), `pck_loader/`, `installer/` (preserving all 29 installer tests), and `apps/desktop/ui/` (`mod-helpers.js`, `mod-install-flow.js`, `mod-dialogs.js`, `batch-view.js`, `catalog-view.js`) pass `npm run check:architecture`, `npm test`, `npm run lint:rust`, and `npm run test:rust`.
  - Phase 2: `mods/_shared/{minigame-hub,team-support}/` parity checks, `mods/team-party/` 6-module split, and native team logic + module splits in `mods/bubble-blitz/` (`v0.1.5`), `mods/spike-ring/` (`v0.1.3`), and `mods/roller-carnival/` (`v0.1.11`) pass `node scripts/pack-mod.mjs --all --verify-catalog`, standalone Godot `--self-test` (`SELF_TEST_PASSED`) on all 3 minigames, `npm run check:architecture`, and `npm test` (including `tests/mods/team-party.test.mjs`).
  - Phase 3: `catalog.rs` (`ModRequirement`, `role`, `compare_numeric_versions`), `installer/deps.rs` (DAG resolution, cycle/version rejection, rollback, disable/uninstall guards, and last-dependent auto-cleanup), `ui/` (`resolveDependencies`, `dependentsOf`, `isLibraryMod`, auto-downloading prerequisites in `mod-install-flow.js`), `mods/mpm-core/` (`v0.1.0`, `HUB_VERSION = 2`, `event_bus.gd`, `locale_utils.gd`, `lobby_ui_coordinator.gd`), and the `mpm_bootstrap.gd` yield guard pass `deps_tests`, `tests/ui/dependencies.test.mjs`, and `tests/mods/mpm-core.test.mjs`. Published minigames defer declaring `requires: ["mpm-core"]` until Windows Steam verification completes. Phases 4–5 remain planned.
- **Gate for Phase 1**: `npm run check:architecture` (covering submodules), `npm test`, `npm run lint:rust`, and `npm run test:rust` (plus `MPM_L3_VANILLA_PCK` simulation when run locally).
- **Gate for Phase 2**: `node scripts/pack-mod.mjs --all --verify-catalog`, `npm test` (including `tests/mods/*.test.mjs`), and standalone Godot `--self-test` (`SELF_TEST_PASSED`).
- **Gate for Phase 3**: Rust L1 dependency DAG, cycle-rejection, rollback, and last-dependent cleanup tests; UI dependency prompts and uninstall guard tests; Godot `mpm-core` coexistence + mixed `HUB_VERSION` tests; and physical Windows Steam verification before enabling `requires` in the live catalog.
- **Gate for Phase 4**: Multi-mod hook-chain coexistence tests in Godot 4.5.2 and `team-party` integration tests.
