# ADR-015: Multi-Minigame Coexistence Hub

**English** · [简体中文](../../zh-CN/architecture/ADR-015-multi-minigame-hub.md) · [繁體中文](../../zh-TW/architecture/ADR-015-multi-minigame-hub.md)

Date: 2026-11-20. Status: Proposed; verified in macOS Godot 4.5.2 coexistence tests, pending Windows Steam playtesting.

## Problem

Earlier first-party minigame integration (`roller-carnival` v0.1.5) hardcoded a single unused slot (`ShapeCutter = 6`) directly inside script overrides for `game.gd`, `playlist_handler.gd`, and `intermission_game_picker.gd`. Installing a second custom minigame mod (such as `bubble-blitz`) with independent overrides would overwrite the first mod's playlist and CRT picker registration.

## Decision

1. **Shared runtime registry (`custom_minigames`)**: Each custom minigame mod registers its metadata dictionary (`mod_id`, `slot_id`, `scene_path`, `packed_scene`, `icon_texture`, `default_rounds`, localized `display_name`, `brief_content`, `controls_data`) into `loader.registry("custom_minigames")` (mirrored on `Engine` meta `_mpm_custom_minigames` for override scripts, and cleaned up in `_exit_tree()` to avoid Godot shutdown leaks).
2. **Idempotent hub driver (`custom_minigames_hub`)**: Each custom minigame ships the same versioned hub overrides (`override_game.gd`, `override_local_game.gd`, `override_playlist.gd`, `override_picker.gd`). The first loaded minigame installs them once and records `HUB_VERSION` in `custom_minigames_hub`; subsequent minigames only register their own metadata unless they carry a newer `HUB_VERSION`.
3. **Unbounded slot support**: Unused stock enum slots are preferred first (`ShapeCutter = 6` for `roller-carnival`, `ScavangerChairs = 8` for `bubble-blitz`, `MemorizePath = 15` reserved next), while the hub's `load_minigame` override also supports arbitrary integer slot IDs (`>= 100`) directly from `packed_scene` without relying on `Globals.MinigamePaths`.

## Alternatives

- **Putting playlist/picker overrides inside `mpm_bootstrap.gd`**: Would require every player to upgrade the desktop client and would break compatibility with external `MachinePartyModLoader.exe`.
- **Making custom minigames mutually exclusive in `catalog/mods.json`**: Would prevent players from enjoying multiple first-party minigames in the same session.

## Compatibility

- Compatible with both the built-in loader (`mpm_bootstrap.gd`) and external MPML API v2 without desktop client changes.
- Upgrading `roller-carnival` to `v0.1.6` enables full coexistence with `bubble-blitz` `v0.1.0` and any future minigame mods regardless of load order.

## Evidence

- `tests/mods/multi-minigame-coexistence.test.mjs` verifies in Godot 4.5.2 that `roller-carnival` (slot 6) and `bubble-blitz` (slot 8) register together, install hub overrides exactly once, instantiate both playable scenes, and appear together in Default and Arcade session playlists.
- `tests/mods/roller-registration.test.mjs` and both mods' `--self-test` suites pass with zero script errors or shutdown leaks.
