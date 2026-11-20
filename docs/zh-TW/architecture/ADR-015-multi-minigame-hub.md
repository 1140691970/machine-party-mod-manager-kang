# ADR-015：多小遊戲共存註冊中心

[English](../../en/architecture/ADR-015-multi-minigame-hub.md) · [简体中文](../../zh-CN/architecture/ADR-015-multi-minigame-hub.md) · **繁體中文**

日期：2026-11-20。狀態：提議中；已在 macOS Godot 4.5.2 多模組共存回歸測試中通過，尚待 Windows Steam 實機對局驗收。

## 問題

早期自研小遊戲（`roller-carnival` v0.1.5）將單一閒置槽位（`ShapeCutter = 6`）硬編碼寫入 `game.gd`、`playlist_handler.gd` 與 `intermission_game_picker.gd` 的覆寫腳本中。如果玩家同時安裝第二個自研小遊戲（例如 `bubble-blitz`），各自獨立的覆寫會互相覆蓋，導致先載入的小遊戲從歌單與過場 CRT 抽籤池中消失。

## 決策

1. **共享執行期註冊表（`custom_minigames`）**：每個自研小遊戲模組在啟動時將自身中繼資料字典（`mod_id`、`slot_id`、`scene_path`、`packed_scene`、`icon_texture`、`default_rounds`、三語 `display_name`、`brief_content`、`controls_data`）註冊至 `loader.registry("custom_minigames")`（同步鏡像至 `Engine` 中繼資料 `_mpm_custom_minigames` 供覆寫腳本讀取，並在 `_exit_tree()` 中清理以防 Godot 結束期釋放洩漏）。
2. **冪等通用驅動（`custom_minigames_hub`）**：每個自研小遊戲攜帶相同版本的通用驅動覆寫（`override_game.gd`、`override_local_game.gd`、`override_playlist.gd`、`override_picker.gd`）。首個載入的小遊戲安裝一次並在 `custom_minigames_hub` 記錄 `HUB_VERSION`；後續載入的小遊戲只需寫入自身中繼資料，僅在攜帶更高 `HUB_VERSION` 時升級驅動。
3. **無上限槽位擴充**：優先使用原版未使用的合法列舉槽位（`roller-carnival` 使用 `ShapeCutter = 6`，`bubble-blitz` 使用 `ScavangerChairs = 8`，保留 `MemorizePath = 15` 供後續使用），同時通用驅動的 `load_minigame` 覆寫也支援任意高位整數槽位（`>= 100`）直接由 `packed_scene` 實例化，不受 `Globals.MinigamePaths` 數量限制。

## 備選方案

- **將歌單與抽籤覆寫寫入內建載入器 `mpm_bootstrap.gd`**：會強制玩家升級桌面端用戶端，且無法相容外部 `MachinePartyModLoader.exe`。
- **在 `catalog/mods.json` 將自研小遊戲設為互斥群組**：無法在同一場對局中同時遊玩多個自研小遊戲。

## 相容性

- 同時相容內建載入器（`mpm_bootstrap.gd`）與外部 MPML API v2，無需升級桌面端用戶端。
- 將 `roller-carnival` 升級至 `v0.1.6` 後，可與 `bubble-blitz` `v0.1.0` 及未來更多自研小遊戲以任意順序同時載入共存。

## 證據

- `tests/mods/multi-minigame-coexistence.test.mjs` 在 Godot 4.5.2 中驗證 `roller-carnival`（槽位 6）與 `bubble-blitz`（槽位 8）同時註冊、通用覆寫僅安裝一次、雙場景皆可實例化，且同時出現在預設與街機輪換池中。
- `tests/mods/roller-registration.test.mjs` 及兩款模組的 `--self-test` 均零錯誤、零結束洩漏通過。
