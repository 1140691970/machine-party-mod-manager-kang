# MPM 模組開發 SDK 與公開執行期契約

[English](../../en/development/mod-sdk.md) · [简体中文](../../zh-CN/development/mod-sdk.md) · **繁體中文**

本參考手冊定義 [`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd)、[`mpm-core`](../../../mods/mpm-core/README.md) 與 [`team-party`](../../../mods/team-party/README.md) 向模組公開的**版本化穩定契約**，以及 [ADR-018](../architecture/ADR-018-mod-development-sdk.md) 規劃中的 SDK 能力。打包規則、效能紅線與目錄准入流程詳見 [mod-development.md](mod-development.md)。

---

## 1. 現行穩定公開契約（已可用）

### 1.1 MPML 引導載入器 API v2（`API_VERSION = 2`）

每個繼承 `Node` 的模組入口（`main.gd`）都會在 `_mod_init(loader)` 與 `_mod_ready(loader)` 收到 `loader` 實例。呼叫前應先以 `loader.has_api("<name>")` 或 `loader.has_method("<name>")` 檢查能力，以同時相容內建載入器與外部 `MachinePartyModLoader.exe`。

| 分類 | 可用方法 | 說明 |
| --- | --- | --- |
| **腳本與資源** | `compile`、`register_script`、`override_script`、`override_script_rel`、`register_autoload`、`register_global_class`、`mount_assets` | 內部子腳本須註冊在專屬前綴 `res://mods_<snake_id>/...` 下，防止跨模組衝突。 |
| **場景與節點掛載** | `on_scene_script`、`on_node_added`、`on_main_menu`、`on_lobby` | 在 `on_node_added` 中優先以 `node.get_script() == null` 快速略過一般節點。 |
| **查詢與共享註冊表** | `dir_of`、`has_mod`、`mod_list`、`open_mods_folder`、`is_local_couch`、`game_mode`、`registry`、`note`、`api_version`、`loader_version`、`has_api` | `registry(name)` 回傳跨模組共享的可變 `Dictionary`。 |

### 1.2 `Engine` Meta 與共享註冊表契約

| 鍵名 | 維護方 | 載荷與用途 |
| --- | --- | --- |
| `&"mpm_core"` | `mpm-core` | `{ version, hub_version, node, event_bus, locale, lobby_ui }`（同時寫入 `loader.registry("mpm_core")`）。 |
| `&"mpm_lobby_ui_coordinator_v2"` | `mpm-core` | 協調器 v2 運作時為 `true`，通知 `mpm_bootstrap.gd` 略過舊版大廳防重疊排布。 |
| `&"mpm_team_party"` | `team-party` | `{ enabled, team_count, team_format, teams, node }`（同時寫入 `loader.registry("team_party")["state"]`）。 |
| `&"mpm_player_spotlight_active"` | `player-spotlight` | 聚光燈啟用時為 `true`，`team-party` 據此保留本地主角名牌顏色。 |
| `&"mpm_local_player"` | 小遊戲關卡 / 角色 | 掛在本地真人 3D 角色節點上，供 `player-spotlight` 自動接管。 |
| `&"mpm_native_team_stage"` | 自研小遊戲 | 由 `team_support.begin_match(stage, roster)` 設定，`team-party` 據此渲染狀態列且不做原始碼重寫包裝。 |
| `&"mpm_custom_team_game"` | 小遊戲父節點 | 原生組隊啟用時為 `true`，關閉 `team-party` 對原版關卡的提前勝出輪詢。 |
| `&"mpm_team_scores_applied"` | 小遊戲父節點 | `team_support.mark_scores_applied` 呼叫後設為 `true`，避免重複同步分數。 |
| `_mpm_custom_minigames` | Hub 模組 / `mpm-core` | 槽位 ID → 小遊戲描述 `{ mod_id, slot_id, scene_path, packed_scene, icon_texture, default_rounds, display_name, brief_content, controls_data }`。 |
| `_mpm_custom_minigames_hub` | Hub 模組 / `mpm-core` | `{ version, installed_paths, cached_overrides, node_hook_installed }`。 |

### 1.3 `mpm-core`（`v0.1.0`）執行期服務

模組可讀取 `Engine.get_meta(&"mpm_core")`（未安裝時應安全降級）：

- **`event_bus`**：`on(topic: String, cb: Callable)`、`once(topic: String, cb: Callable)`、`off(topic: String, cb: Callable)`、`emit_event(topic: String, payload: Dictionary = {})`、`clear()`，自動清理失效回呼。
- **`locale`**：`is_tw_locale(loc = "") -> bool`、`is_cn_locale(loc = "") -> bool`、`pick(en, cn, tw) -> String`。
- **`lobby_ui`**（協調器 v2）：透過 `register_panel(ctrl: Control)` 註冊大廳懸浮面板，在不改動原版按鈕的前提下避免重疊。
- **`minigame_sdk`**：提供 `register_minigame(spec: Dictionary, loader = null)` 與 `unregister_minigame(mod_id: String, loader = null)`，未指定 `slot_id` 時自動分配 Hub v2 動態高位槽位（`>= 1000`）。
- **`create_fx_pool`（`MpmFxPool`）**：提供 `register_pool(kind, parent, factory, capacity)`、`warmup(kind = "")`、`acquire(kind, duration = 0.0, on_release = Callable())`、`release(kind, node)`、`tick(delta)`、`clear()`。
- **`hook_chain`（`HookChain`）**：提供 `add_hook(target, cb, priority = 0) -> id`、`remove_hook(target, id) -> bool`、`hook_count(target) -> int`、`invoke(target, base_fn, args = [])`、`clear()`。
- **Minigame Hub v2（`HUB_VERSION = 2`）**：自動升級並覆蓋既有 `HUB_VERSION = 1` 的 Hub 覆寫腳本。

### 1.4 原生組隊接入契約（`team_support.gd`）

自研小遊戲內建 [`mods/_shared/team-support/team_support.gd`](../../../mods/_shared/team-support/team_support.gd)（透過 `node scripts/pack-mod.mjs --sync-shared` 維持單一來源），讀取 `&"mpm_team_party"` 並在未安裝或停用 `team-party` 時無痕降級為個人混戰。

---

## 2. 穩定性與靜態檢查規範

1. **編譯期安全（對齊 Windows Godot 4.5.2）**：
   - 禁止對無型別 `Dictionary.keys()`、動態 `.call()` 或無型別成員欄位使用 `:=` 推斷（必須明確宣告如 `var ids: Array = ...`）。
   - 禁止在 MPML 動態載入腳本內以 `preload("res://...")` 引用模組內部兄弟腳本；統一使用 `register_script` + `ResourceLoader.load(REG_RES_DIR + rel)` 並保留路徑回退。
2. **執行期效能紅線**：
   - 禁止在 `_process`、`_physics_process` 或 `node_added` 中呼叫 `get_property_list()` 或執行週期性全樹掃描。
   - 高頻特效、貼花與燈光必須使用開局預熱的常駐物件池。
3. **乾淨釋放**：
   - 在 `_exit_tree()` 中清空節點參照、斷開訊號、清理本模組寫入的 `Engine` Meta，並在無頭測試退出時清理產生的 `.gd.uid`。

---

## 3. SDK 工具鏈與路線圖（見 [ADR-018](../architecture/ADR-018-mod-development-sdk.md)）

- **SDK-1（已可用）**：靜態 GDScript 模組 Linter（`scripts/mod-lint.mjs`）已接入 `npm run check:architecture`。
- **SDK-2（已可用）**：提供 `npm run mod -- new|check|catalog-sync` 腳手架 CLI（`scripts/mod-cli.mjs`）及共用 `tests/mods/_harness/`（`mock_loader.gd`、`mock_game_env.gd`）Godot 夾具。
- **SDK-3（已可用）**：在 `mpm-core` 提供 `register_minigame(spec)`（`minigame_sdk.gd`）、`MpmFxPool` 基類（`fx_pool.gd`）及 Hub v2 動態高位槽位（`>= 1000`），取代寫死的 `MinigameIdentifier`。
- **SDK-4（已可用）**：依優先權排序的方法級 `hook_chain`（`hook_chain.gd`）及三款自研小遊戲（`roller-carnival`、`bubble-blitz`、`spike-ring`）接入 `mpm-core` 依賴。
