# First-party mod development, testing, integration & packaging specification

**English** · [简体中文](../../zh-CN/development/mod-development.md) · [繁體中文](../../zh-TW/development/mod-development.md)

This specification governs **first-party mods** authored in this repository under [`mods/`](../../../mods/README.md). Third-party community mods follow the upstream Release approval process described in [Candidate mods and inclusion rules](../catalog/mods.md). Both share the same Cloudflare R2 + catalog Worker delivery pipeline ([Catalog delivery](../catalog/delivery.md), [ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)).

## 1. Scope and design principles

- **Single clean-room codebase (GPL-3.0-only)**: All first-party mods (`mods/<id>/`), the deterministic ZIP packager ([`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs)), and the built-in loader ([`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd) and Rust `pck_loader.rs`) are original repository code. Never commit Steam game files (`Machine Party.pck`, `.exe`), third-party loader executables (`MachinePartyModLoader.exe`), telemetry, or unapproved network calls ([AGENTS.md](../../../AGENTS.md), [ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)).
- **Unified R2 + Worker delivery with automatic loader setup**: First-party mods package into deterministic ZIP archives stored under `packages/sha256/<sha256>.zip` in R2 and served through `services/catalog-worker`. Players can update mods dynamically via the catalog without reinstalling the desktop app. When `adapter.autoLoader: true` is declared on a `loader-files` mod, the manager configures its clean-room loader automatically on first install (while leaving any pre-existing external `MachinePartyModLoader.exe` untouched) and restores the exact vanilla `Machine Party.pck` when the last loader mod is uninstalled ([ADR-005](../architecture/ADR-005-install-transactions.md), [ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)).
- **Shared dev/runtime isolation**: Standalone Godot preview files for local macOS development (`project.godot`, `*_scene.tscn`, `*.sh`) and documentation (`README.md`) live beside runtime GDScript sources under `mods/<id>/` and are automatically excluded from release ZIP archives by [`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs).

## 2. Directory layout, naming and `mod.json`

Every first-party mod lives in `mods/<id>/`, where `<id>` matches `^[a-z0-9-]+$` (for example [`mods/roller-carnival/`](../../../mods/roller-carnival/README.md)):

| File pattern | Packed into R2 ZIP? | Purpose |
| --- | --- | --- |
| `mod.json` | Yes | Runtime manifest read by the loader and verified by CI contracts |
| `main.gd` (or `entry`) | Yes | Entry script extending `Node`; registers overrides, hooks, and scenes |
| `*.gd` / runtime assets | Yes | Gameplay scripts, shaders, or packs loaded via `dir_of(id)` / `mount_assets` |
| `README.md` | No (`*.md` skipped) | Required mod documentation: gameplay, controls, file map, test & install notes |
| `project.godot`, `*_scene.tscn` | No | Optional standalone Godot preview project & test harness scene |
| `*.sh` (e.g. `run_mac.sh`) | No (`*.sh` skipped) | Optional local run / `--self-test` / `--screenshot` helper scripts |
| `.*` entries & symlinks | No | Hidden IDE files, `.godot/` cache, and symlinks are always ignored |

### `mod.json` schema

```json
{
  "id": "roller-carnival",
  "name": "Roller Carnival (滾筒嘉年華)",
  "version": "0.1.0",
  "authors": ["MachineParty Mod Team"],
  "entry": "main.gd",
  "priority": 0,
  "requires": []
}
```

- `id`: Must equal the folder name `mods/<id>/` and match the `id` in [`catalog/mods.json`](../../../catalog/mods.json).
- `version`: Semantic version **without** a leading `v` (e.g. `"0.1.0"`). Contract tests enforce `"v" + manifest.version === catalogEntry.version`.
- `entry`: Relative POSIX path to an existing GDScript file in `mods/<id>/` extending `Node`.
- `priority` / `requires` / optional `enabled`: Control dependency ordering when `mpm_bootstrap.gd` loads mods (`priority` ascending, then alphabetical `id`, topological `requires` sort).

## 3. Built-in loader API and game-integration rules

The built-in bootstrap (`LOADER_VERSION = "3"`, `API_VERSION = 2`) mounts as `autoload/ModLoader` (`*res://modloader/bootstrap.gd`) before game scripts execute. External `MachinePartyModLoader.exe` shares the same API v2 surface.

### Lifecycle

1. `_mod_init(loader)`: Called immediately when `main.gd` is instantiated during startup discovery, **before** game scenes load. Perform `register_script`, `override_script_rel`, resource-pack mounting, and scene/lobby hook registration here.
2. `_mod_ready(loader)`: Called deferred once the scene tree is ready and pending autoloads have flushed. Initialize safe defaults in `Globals` or default playlists here.

### Available Loader API v2 methods

Check capability defensively with `loader.has_api("<name>")` or `loader.has_method("<name>")` before calling newer v2 helpers so your mod degrades gracefully on older loaders:

- **Script compilation & overrides**: `compile(abs_path)`, `override_script(res_path, abs_path)`, `override_script_rel(id, res_path, rel)`, `register_script(id, rel, res_id)`, `register_autoload(singleton_name, id, rel)`, `register_global_class(cls_name, id, rel)`, `mount_assets(id, rel_zip)`.
- **Scene & tree hooks**: `on_scene_script(res_path, cb)`, `on_node_added(cb)`, `on_main_menu(cb)`, `on_lobby(cb)`.
- **Discovery, state & logging**: `dir_of(id)`, `has_mod(id)`, `mod_list()`, `open_mods_folder()`, `is_local_couch()`, `game_mode()`, `registry(reg_name)`, `note(text)`, `api_version()`, `loader_version()`, `has_api(name_or_ver)`.

### Integration conventions

- **Isolate virtual paths**: Register internal helper scripts under a mod-unique virtual prefix such as `res://mods_<snake_id>/...` so multiple mods never collide via `take_over_path`.
- **Separate Lobby configuration from active gameplay**: Host match parameters in `Globals.game_settings[SETTINGS_KEY]` and expose room-creation controls in `LobbyScene` (detected inside `on_lobby`), keeping in-game HUD uncluttered.
- **Scale dynamically across player counts**: Never assume a fixed 4-player lobby. Support vanilla 2–4 players and community 8–16 player mods seamlessly by adapting spawns and scoring tiers dynamically to the incoming roster.
- **Emit standard minigame contract signals** when joining Machine Party's rotation: `host_loaded`, `minigame_loaded`, `minigame_ready`, `minigame_finished`, `player_scored`, `player_scores_finalized`.
- **Clean up standalone preview code**: Guard any dev-only input (e.g. `F7` overlay test key, local `--self-test` args) cleanly so normal Steam sessions are unaffected.

## 4. Testing and verification tiers

Every mod change must pass all tiers feasible in the developer's environment before release:

| Tier | Scope | Commands & pass criteria |
| --- | --- | --- |
| **Tier 0: Godot standalone** | GDScript syntax, gameplay self-tests, UI/cover screenshot | 1. Headless syntax check (`Godot --headless --check-only --script`) on every standalone script (`override_*.gd` files using `extends "res://..."` are noted as game-runtime-only).<br>2. Headless `--self-test` covering movement, collision, safety bounds, presets, and score/tie-break rules -> exits `0` printing `SELF_TEST_PASSED`.<br>3. `1280×720` cover capture (`--capture-screenshot=apps/desktop/ui/images/<id>.png`) visually inspected via screenshot review. |
| **Tier 1: Packaging, contracts & lint** | Deterministic ZIP, boundaries, catalog schema, docs, Rust lint | Run `node scripts/pack-mod.mjs --all --verify-catalog`, `npm run check:architecture`, `npm test`, and `npm run lint:rust`. Enforces exact deterministic ZIP `size` & `sha256` match, `mod.json` ID/version parity, non-empty `mods/<id>/README.md`, non-excluded `requiredFiles`, R2/Worker contract checks, 3-language docs/links, and valid cover images. |
| **Tier 2: Rust L1 & L3 simulation** | ZIP extraction, GDPC v3 patch/restore, install/uninstall transactions | Run `npm run test:rust` (`pck_loader`, `installer`). Locally on macOS with an uncommitted copy of vanilla Steam v2.1.2 `Machine Party.pck`, run `MPM_L3_VANILLA_PCK="/path/to/Machine Party.pck" npm run test:rust` to verify exact append and lossless SHA-256 restore. |
| **Tier 3: Windows Steam physical** | End-to-end Windows acceptance (**required before `verified: true`**) | On Windows + Steam `v2.1.2`: Worker download + SHA-256 verify + install in desktop manager -> launch via Steam -> gameplay, presets, rotation, multiplayer RPC -> offline uninstall -> confirm vanilla `Machine Party.pck` SHA-256 restored; also verify external MPML coexistence and `overtime` conflict checks. |

## 5. Catalog and desktop UI integration

To publish a first-party mod into the catalog and R2/Worker pipeline:

1. Create `mods/<id>/README.md`, `mods/<id>/mod.json`, runtime scripts, and cover image `apps/desktop/ui/images/<id>.png`.
2. Run `node scripts/pack-mod.mjs <id>` to inspect the exact deterministic `filename`, `size`, `sha256`, and `files` list.
3. Add an entry to [`catalog/mods.json`](../../../catalog/mods.json):
   - Set `"id"` (`<id>`), unique `"order"`, unique `"repo"` (for example `"JamesGZM/machine-party-mod-manager"`), `"image": "<id>"`, and `"version": "v<mod.json.version>"`.
   - Set `"package"`: unique numeric string `"assetId"` (e.g. `"1001"`), exact `"filename"`, `"size"`, `"sha256"` from `scripts/pack-mod.mjs`, and `"mirrorApproved": true`.
   - Set `"supportedGameVersions"`, `"windowsPreview"` matching the current app preview build, and `"verified": false` until Tier 3 passes.
   - Configure `"adapter"`: `"kind": "loader-files"`, `"platforms": ["windows"]`, `"target": "pckDir"`, `"touches": ["mods"]`, `"exclusive": "loader"`, `"autoLoader": true`, `"upstreamUninstall": false`, verified `"baseline"` (`Machine Party.pck` size + SHA-256), and exact `"requiredFiles"` matching `pack-mod.mjs` output.
   - Provide complete `zh-CN`, `zh-TW`, and `en` text for `name`, `summary`, and `detail`, plus `aliases`.
4. Update [`mods/README.md`](../../../mods/README.md) with the new mod row.
5. No UI special-casing is needed or used: every catalog mod displays the exact same cards, badges, details dialog, and Worker download -> verify -> install workflow.

## 6. Packaging and R2 / Worker deployment

- **Deterministic ZIP build**: [`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) packs non-excluded runtime files in sorted lexicographical order using `ZIP_STORED` (method `0`) with fixed DOS timestamps (`1980-01-01 00:00:00`), guaranteeing identical SHA-256 hashes across macOS, Linux, and Windows.
- **Automated Worker + R2 staging**: Dispatching `.github/workflows/catalog-worker.yml` runs `node scripts/pack-mod.mjs --all --verify-catalog --out "$RUNNER_TEMP/packages"`, uploads missing `packages/sha256/<sha256>.zip` objects to Cloudflare R2 (`machine-party-mods`), verifies every `mirrorApproved` package object size in R2, stages `catalog/revisions/<revision>.json`, deploys `services/catalog-worker`, and checks every live `/v1/downloads/<id>/<version>/<assetId>` HEAD response.
- **Updating an existing mod**: Bump `version` in `mods/<id>/mod.json`, re-run `node scripts/pack-mod.mjs <id>` to update `catalog/mods.json` (`version`, `revision`, `package.assetId`/`filename`/`size`/`sha256`), update `mods/<id>/README.md`, push to `main`, and dispatch `Deploy mod catalog Worker`. Keep `"verified": false` during `windowsPreview` testing and set `"verified": true` only after Tier 3 passes; for desktop manager updates see [Releasing manager updates](releasing.md).

## References

- [ADR-009: First-party mods, deterministic R2 packaging, and self-managed loader](../architecture/ADR-009-bundled-first-party-mods.md)
- [ADR-005: Install transactions and verified game restoration](../architecture/ADR-005-install-transactions.md)
- [ADR-007: Mod adapters and macOS simulation tiers](../architecture/ADR-007-mod-adapters.md)
- [Production catalog delivery](../catalog/delivery.md) · [Development guide](README.md) · [Mods directory index](../../../mods/README.md) · [Roller Carnival README](../../../mods/roller-carnival/README.md)
