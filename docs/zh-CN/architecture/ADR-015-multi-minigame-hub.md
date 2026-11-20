# ADR-015：多小游戏共存注册中心

[English](../../en/architecture/ADR-015-multi-minigame-hub.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-015-multi-minigame-hub.md)

日期：2026-11-20。状态：提议中；已在 macOS Godot 4.5.2 多模组共存回归测试中通过，尚待 Windows Steam 实机对局验收。

## 问题

早期自研小游戏（`roller-carnival` v0.1.5）将单一闲置槽位（`ShapeCutter = 6`）硬编码写入 `game.gd`、`playlist_handler.gd` 与 `intermission_game_picker.gd` 的覆写脚本中。如果玩家同时安装第二个自研小游戏（例如 `bubble-blitz`），各自独立的覆写会互相覆盖，导致先加载的小游戏从歌单与过场 CRT 抽签池中消失。

## 决策

1. **共享运行时注册表（`custom_minigames`）**：每个自研小游戏模组在启动时将自身元数据字典（`mod_id`、`slot_id`、`scene_path`、`packed_scene`、`icon_texture`、`default_rounds`、三语 `display_name`、`brief_content`、`controls_data`）注册至 `loader.registry("custom_minigames")`（同步镜像至 `Engine` 元数据 `_mpm_custom_minigames` 供覆写脚本读取，并在 `_exit_tree()` 中清理以防 Godot 退出期释放泄漏）。
2. **幂等通用驱动（`custom_minigames_hub`）**：每个自研小游戏携带相同版本的通用驱动覆写（`override_game.gd`、`override_local_game.gd`、`override_playlist.gd`、`override_picker.gd`）。首个加载的小游戏安装一次并在 `custom_minigames_hub` 记录 `HUB_VERSION`；后续加载的小游戏只需写入自身元数据，仅在携带更高 `HUB_VERSION` 时升级驱动。
3. **无上限槽位扩展**：优先使用原版未使用的合法枚举槽位（`roller-carnival` 使用 `ShapeCutter = 6`，`bubble-blitz` 使用 `ScavangerChairs = 8`，保留 `MemorizePath = 15` 供后续使用），同时通用驱动的 `load_minigame` 覆写也支持任意高位整数槽位（`>= 100`）直接由 `packed_scene` 实例化，不受 `Globals.MinigamePaths` 数量限制。

## 备选方案

- **将歌单与抽签覆写写入内置加载器 `mpm_bootstrap.gd`**：会强制玩家升级桌面端客户端，且无法兼容外部 `MachinePartyModLoader.exe`。
- **在 `catalog/mods.json` 将自研小游戏设为互斥组**：无法在同一场对局中同时游玩多个自研小游戏。

## 兼容性

- 同时兼容内置加载器（`mpm_bootstrap.gd`）与外部 MPML API v2，无需升级桌面端客户端。
- 将 `roller-carnival` 升级至 `v0.1.6` 后，可与 `bubble-blitz` `v0.1.0` 及未来更多自研小游戏以任意顺序同时加载共存。

## 证据

- `tests/mods/multi-minigame-coexistence.test.mjs` 在 Godot 4.5.2 中验证 `roller-carnival`（槽位 6）与 `bubble-blitz`（槽位 8）同时注册、通用覆写仅安装一次、双场景均可实例化，且同时出现在默认与街机轮换池中。
- `tests/mods/roller-registration.test.mjs` 及两款模组的 `--self-test` 均零错误、零退出泄漏通过。
