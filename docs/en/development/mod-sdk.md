# MPM Mod Development SDK & Public Runtime Contract

**English** · [简体中文](../../zh-CN/development/mod-sdk.md) · [繁體中文](../../zh-TW/development/mod-sdk.md)

This reference defines the **versioned public contracts** exposed to mods by [`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd), [`mpm-core`](../../../mods/mpm-core/README.md), and [`team-party`](../../../mods/team-party/README.md), plus the planned SDK capabilities designed in [ADR-018](../architecture/ADR-018-mod-development-sdk.md). For packaging rules, red lines, and catalog onboarding, see [mod-development.md](mod-development.md).

---

## 1. Stable Public Contracts (Live Today)

### 1.1 MPML Bootstrap API v2 (`API_VERSION = 2`)

Every mod entry (`main.gd` extending `Node`) receives `loader` in `_mod_init(loader)` and `_mod_ready(loader)`. Always guard capability checks with `loader.has_api("<name>")` or `loader.has_method("<name>")` so mods degrade cleanly across both the built-in loader and external `MachinePartyModLoader.exe`.

| Category | Methods | Notes |
| --- | --- | --- |
| **Scripts & Assets** | `compile`, `register_script`, `override_script`, `override_script_rel`, `register_autoload`, `register_global_class`, `mount_assets` | Register helper scripts under `res://mods_<snake_id>/...` to avoid cross-mod path collisions. |
| **Scene & Node Hooks** | `on_scene_script`, `on_node_added`, `on_main_menu`, `on_lobby` | Prefer `node.get_script() == null` fast-skip inside `on_node_added`. |
| **Inspection & Registries** | `dir_of`, `has_mod`, `mod_list`, `open_mods_folder`, `is_local_couch`, `game_mode`, `registry`, `note`, `api_version`, `loader_version`, `has_api` | `registry(name)` returns a shared `Dictionary` preserved across mods. |

### 1.2 `Engine` Meta & Shared Registry Contracts

| Key | Owner | Payload / Purpose |
| --- | --- | --- |
| `&"mpm_core"` | `mpm-core` | `{ version, hub_version, node, event_bus, locale, lobby_ui }` (also in `loader.registry("mpm_core")`). |
| `&"mpm_lobby_ui_coordinator_v2"` | `mpm-core` | `true` while Lobby UI Coordinator v2 is active; causes `mpm_bootstrap.gd` legacy layout to yield. |
| `&"mpm_team_party"` | `team-party` | `{ enabled, team_count, team_format, teams, node }` (also in `loader.registry("team_party")["state"]`). |
| `&"mpm_player_spotlight_active"` | `player-spotlight` | `true` while spotlight mod is active; `team-party` preserves local nameplate color when true. |
| `&"mpm_local_player"` | Minigame stage / actor | Set on the local human 3D actor node so `player-spotlight` attaches automatically. |
| `&"mpm_native_team_stage"` | First-party minigame | Set via `team_support.begin_match(stage, roster)` so `team-party` renders HUD without source wrapping. |
| `&"mpm_custom_team_game"` | Minigame parent | `true` when native team mode is active; suppresses vanilla early-win polling in `team-party`. |
| `&"mpm_team_scores_applied"` | Minigame parent | `true` once `team_support.mark_scores_applied` runs; prevents double score synchronization. |
| `_mpm_custom_minigames` | Hub mods / `mpm-core` | Slot ID → minigame descriptor `{ mod_id, slot_id, scene_path, packed_scene, icon_texture, default_rounds, display_name, brief_content, controls_data }`. |
| `_mpm_custom_minigames_hub` | Hub mods / `mpm-core` | `{ version, installed_paths, cached_overrides, node_hook_installed }`. |

### 1.3 `mpm-core` (`v0.1.0`) Runtime Services

Mods may read `Engine.get_meta(&"mpm_core")` (or fall back cleanly when absent):

- **`event_bus`**: `on(topic: String, cb: Callable)`, `once(topic: String, cb: Callable)`, `off(topic: String, cb: Callable)`, `emit_event(topic: String, payload: Dictionary = {})`, `clear()`. Dead callables are pruned automatically.
- **`locale`**: `is_tw_locale(loc = "") -> bool`, `is_cn_locale(loc = "") -> bool`, `pick(en, cn, tw) -> String`.
- **`lobby_ui`** (Coordinator v2): `register_panel(ctrl: Control)` registers lobby overlay panels for overlap-free stacking without modifying vanilla lobby buttons.
- **`minigame_sdk`**: `register_minigame(spec: Dictionary, loader = null)` and `unregister_minigame(mod_id: String, loader = null)` manage `_mpm_custom_minigames` with automatic dynamic Hub v2 slot allocation (`>= 1000`) when `slot_id` is omitted.
- **`create_fx_pool` (`MpmFxPool`)**: `register_pool(kind, parent, factory, capacity)`, `warmup(kind = "")`, `acquire(kind, duration = 0.0, on_release = Callable())`, `release(kind, node)`, `tick(delta)`, `clear()`.
- **`hook_chain` (`HookChain`)**: `add_hook(target, cb, priority = 0) -> id`, `remove_hook(target, id) -> bool`, `hook_count(target) -> int`, `invoke(target, base_fn, args = [])`, `clear()`.
- **Minigame Hub v2 (`HUB_VERSION = 2`)**: Automatically upgrades any legacy `HUB_VERSION = 1` override installation.

### 1.4 Native Team Mode Contract (`team_support.gd`)

First-party minigames embed [`mods/_shared/team-support/team_support.gd`](../../../mods/_shared/team-support/team_support.gd) (synced via `node scripts/pack-mod.mjs --sync-shared`), which reads `&"mpm_team_party"` and degrades transparently to FFA when `team-party` is not installed or disabled.

---

## 2. Stability & Static Linter Rules

1. **Compile-time safety (Godot 4.5.2 Windows parity)**:
   - Never rely on `:=` type inference from untyped `Dictionary.keys()`, dynamic `.call()`, or untyped helper fields; always annotate (`var ids: Array = ...`).
   - Never hardcode `preload("res://...")` inside MPML-compiled scripts for mod-internal siblings; use `register_script` + `ResourceLoader.load(REG_RES_DIR + rel)` with fallback.
2. **Runtime performance red lines**:
   - No `get_property_list()` or periodic full-tree scans inside `_process`, `_physics_process`, or `node_added`.
   - Use persistent pre-warmed FX/decal/light pools (no per-hit `instantiate()` / `queue_free()`).
3. **Clean teardown**:
   - Release node references, disconnect signals, clear registries/meta owned by your mod in `_exit_tree()`, and remove any temporary `.gd.uid` files in headless tests.

---

## 3. SDK Tooling & Roadmap ([ADR-018](../architecture/ADR-018-mod-development-sdk.md))

- **SDK-1 (Live)**: Automated static GDScript mod linter (`scripts/mod-lint.mjs`) integrated into `npm run check:architecture`.
- **SDK-2 (Live)**: `npm run mod -- new|check|catalog-sync` Node CLI (`scripts/mod-cli.mjs`) and shared `tests/mods/_harness/` (`mock_loader.gd`, `mock_game_env.gd`) Godot fixture.
- **SDK-3 (Live)**: `mpm-core` `register_minigame(spec)` plugin factory (`minigame_sdk.gd`), shared `MpmFxPool` (`fx_pool.gd`), and dynamic high-ID Hub v2 slots (`>= 1000`) replacing hardcoded `MinigameIdentifier` integers.
- **SDK-4 (Live)**: Priority-ordered method-level `hook_chain` (`hook_chain.gd`) and `mpm-core` `requires` dependency integration across all three first-party minigames (`roller-carnival`, `bubble-blitz`, `spike-ring`).
