# MPM Core（核心運行庫）

`mpm-core` 是為第一方《Machine Party》模組提供共用執行期基礎設施的核心函式庫模組（`priority: -100`），透過與一般模組相同的 Cloudflare R2 與 `catalog-worker` 管線分發。

- **模組 ID**：`mpm-core`
- **版本**：`0.1.0`（目錄清單對應 `v0.1.0`，`role: "library"`）
- **授權**：`GPL-3.0-only`
- **目標遊戲版本**：Steam Windows `v2.1.2`
- **載入優先權**：`-100`

## 提供功能（繁體中文 / 简体中文 / English）

### 繁體中文
- **Minigame Hub v2（`HUB_VERSION = 2`）**：以較高版本號平滑接管並升級舊版 `HUB_VERSION = 1` 的小遊戲輪換、歌單與過場抽籤覆寫。
- **Lobby UI Coordinator v2**：透過 `Engine` Meta `&"mpm_lobby_ui_coordinator_v2"` 讓 `mpm_bootstrap.gd` 內建的舊版大廳 UI 防重疊排版自動退讓，改由 `mpm-core` 統一協調已註冊的大廳介面面板。
- **跨模組共用工具**：透過 `Engine` Meta `&"mpm_core"` 與 `loader.registry("mpm_core")` 公開 `event_bus`、`locale`、`minigame_sdk`（`register_minigame` / `unregister_minigame` 與 `>= 1000` 動態高位槽位）及 `create_fx_pool`（`MpmFxPool` 常駐物件池）。

### 简体中文
- **Minigame Hub v2（`HUB_VERSION = 2`）**：在版本混装期间平滑接管并覆盖旧版 `HUB_VERSION = 1` 的小游戏 hub 覆写。
- **Lobby UI 协调器 v2**：接管大厅模组面板防重叠排布并自动通知 `mpm_bootstrap.gd` 让步。
- **跨模组共用工具**：提供 `event_bus` 事件总线、`locale` 本地化辅助、`minigame_sdk`（`register_minigame` 与 `>= 1000` 动态高位槽位）以及 `create_fx_pool`（`MpmFxPool` 对象池）。

### English
- **Minigame Hub v2 (`HUB_VERSION = 2`)**: Cleanly supersedes legacy `HUB_VERSION = 1` hub overrides during mixed-version transitions.
- **Lobby UI Coordinator v2**: Coordinates registered lobby mod panels via `Engine` meta `&"mpm_lobby_ui_coordinator_v2"`, causing `mpm_bootstrap.gd`'s legacy layout pass to yield cleanly.
- **Shared Utilities**: Exposes `event_bus`, `locale`, `minigame_sdk` (`register_minigame` / `unregister_minigame` with dynamic `>= 1000` slots), and `create_fx_pool` (`MpmFxPool`) via `Engine` meta `&"mpm_core"` and `loader.registry("mpm_core")`.

## 檔案結構

| 檔案 | 打入 R2 ZIP | 職責 |
| --- | --- | --- |
| `mod.json` | 是 | 模組清單、`priority: -100` 與入口聲明 |
| `main.gd` | 是 | MPML API v2 入口、Hub v2 註冊與共用 Meta 發佈 |
| `event_bus.gd` | 是 | 跨模組事件匯流排 |
| `locale_utils.gd` | 是 | 繁／簡／英語系判斷與本地化輔助 |
| `lobby_ui_coordinator.gd` | 是 | Lobby UI 協調器 v2（防重疊排布） |
| `minigame_sdk.gd` | 是 | 宣告式小遊戲註冊與動態高位槽位分配（`>= 1000`） |
| `fx_pool.gd` | 是 | 可複用常駐特效／貼花物件池（`MpmFxPool`） |
| `hook_chain.gd` | 是 | 依優先權排序的方法級 Hook 鏈（`HookChain`） |
| `override_*.gd` | 是 | 來自 `mods/_shared/minigame-hub/` 的小遊戲中心覆寫腳本 |
| `README.md` | 否 | 本說明文件（`*.md` 自動跳過） |
