# 自研模組開發、測試、接入與打包規範

[English](../../en/development/mod-development.md) · [简体中文](../../zh-CN/development/mod-development.md) · **繁體中文**

本規範適用於在本儲存庫 [`mods/`](../../../mods/README.md) 目錄下開發與維護的**第一方自研模組**。第三方社群模組依循[候選模組與收錄規範](../catalog/mods.md)的上游發布審核流程；兩者共用同一套 Cloudflare R2 與目錄 Worker 分發管線（見[正式目錄交付方案](../catalog/delivery.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。

## 1. 適用範圍與設計原則

- **純淨潔淨室原始碼與 GPL-3.0-only**：所有自研模組（`mods/<id>/`）、確定性 ZIP 打包腳本（[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs)）與內建載入器（[`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd) 及 Rust `pck_loader.rs`）皆由本專案從零編寫。嚴禁提交遊戲本體檔案（`Machine Party.pck`、`.exe`）、第三方載入器執行檔（`MachinePartyModLoader.exe`）、遙測程式碼或未經許可的網路端點（見 [AGENTS.md](../../../AGENTS.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **統一 R2 + Worker 分發與全自動載入器**：自研模組封裝為確定性 `.zip` 後存放於 R2 的 `packages/sha256/<sha256>.zip`，由 `services/catalog-worker` 提供下載；日後更新模組只需重新打包並部署目錄與 R2，不需重編桌面安裝檔。當 `loader-files` 模組宣告 `adapter.autoLoader: true` 時，管理器於首次安裝自動配置潔淨室載入器（若偵測到玩家既有的外部 `MachinePartyModLoader.exe` 則保留不覆蓋），解除安裝最後一個受管載入器模組時無損還原為原版 `Machine Party.pck`（見 [ADR-005](../architecture/ADR-005-install-transactions.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **開發輔助檔案與執行檔案自動隔離**：供 macOS 本機開發除錯使用的 Godot 專案（`project.godot`、`*_scene.tscn`、`*.sh`）與模組文件（`README.md`）可直接放在 `mods/<id>/` 內，[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) 會在打包 ZIP 時自動略過，不進入分發封存檔。

## 2. 目錄結構、命名與 `mod.json` 規範

每個第一方模組置於 `mods/<id>/`，`<id>` 必須符合正規表示式 `^[a-z0-9-]+$`（例如 [`mods/roller-carnival/`](../../../mods/roller-carnival/README.md)）：

| 檔案／模式 | 是否打包至 R2 ZIP | 用途說明 |
| --- | --- | --- |
| `mod.json` | 是 | 模組資訊清單，供載入器讀取並由 CI 契約檢查一致性 |
| `main.gd`（或 `entry`） | 是 | 繼承 `Node` 的進入點腳本，負責腳本覆寫、Hook 與場景註冊 |
| `*.gd`／執行期資源 | 是 | 玩法邏輯、3D 網格建構或透過 `dir_of(id)`／`mount_assets` 載入的資源 |
| `README.md` | 否（自動略過 `*.md`） | 必備模組說明文件：玩法規則、按鍵、檔案結構、測試與安裝狀態 |
| `project.godot`、`*_scene.tscn` | 否 | 選用的 macOS 獨立 Godot 預覽專案與測試場景 |
| `*.sh`（如 `run_mac.sh`） | 否（自動略過 `*.sh`） | 選用的本機執行、`--self-test` 與 `--screenshot` 輔助腳本 |
| `.*` 隱藏項目與符號連結 | 否 | 隱藏檔案、`.godot/` 快取與符號連結一律忽略 |

### `mod.json` 清單格式

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

- `id`：必須與目錄名稱 `mods/<id>/` 及 [`catalog/mods.json`](../../../catalog/mods.json) 的 `id` 完全相同。
- `version`：不含前導 `v` 的語意化版本（例如 `"0.1.0"`）；契約測試會強制檢查 `"v" + manifest.version === catalogEntry.version`。
- `entry`：指向同目錄內存在、且繼承自 `Node` 的進入點 GDScript 相對路徑。
- `priority`／`requires`／選用 `enabled`：控制 `mpm_bootstrap.gd` 載入順序（依 `priority` 升冪、同優先權依 `id` 字典序，並進行相依拓樸排序）。

## 3. 內建載入器執行期 API 與遊戲接入規範

內建引導腳本（`LOADER_VERSION = "4"`、`API_VERSION = 2`）作為首項 `autoload/ModLoader`（`*res://modloader/bootstrap.gd`）在遊戲腳本載入前啟動，並與外部 `MachinePartyModLoader.exe` 共用相同的 API v2 介面。

### 生命週期回呼

1. `_mod_init(loader)`：於啟動探索階段實例化 `main.gd` 時立即呼叫，早於遊戲場景腳本載入；應在此階段執行 `register_script`、`override_script_rel`、資源包掛載與場景 Hook 註冊。
2. `_mod_ready(loader)`：於場景樹就緒且待掛載 autoload 完成後延遲呼叫；適合在 `Globals` 寫入預設設定與安全註冊預設遊戲輪換清單。

### API v2 可用方法

呼叫前應先透過 `loader.has_api("<name>")` 或 `loader.has_method("<name>")` 進行能力檢查，確保在不同版本的載入器下都能安全降級：

- **腳本編譯與覆寫**：`compile`、`override_script`、`override_script_rel`、`register_script`、`register_autoload`、`register_global_class`、`mount_assets`。
- **場景與節點掛鉤**：`on_scene_script`、`on_node_added`、`on_main_menu`、`on_lobby`。
- **資訊查詢與紀錄**：`dir_of`、`has_mod`、`mod_list`、`open_mods_folder`、`is_local_couch`、`game_mode`、`registry`、`note`、`api_version`、`loader_version`、`has_api`。

### 遊戲接入準則

- **隔離虛擬資源路徑**：透過 `register_script` 或 `take_over_path` 公開的內部腳本，須放在模組專屬虛擬前綴（例如 `res://mods_<snake_id>/...`）之下，避免多個模組互相衝突。
- **將開房參數整合至大廳階段**：平衡設定集中存放於 `Globals.game_settings[SETTINGS_KEY]`，並於 `LobbyScene`（透過 `on_lobby` 辨識）提供房主快速預設與進階設定，局內 HUD 保持極簡無遮擋。
- **動態相容多人上限**：不可假設場上永遠只有 4 名玩家；出生點排列、角色陣列與積分階梯必須能根據實際參戰名單在原版 2–4 人與多人擴充模組 8–16 人之間平滑適配。
- **實作官方小遊戲訊號介面**：接入官方輪換池的場景應提供標準訊號（`host_loaded`、`minigame_loaded`、`minigame_ready`、`minigame_finished`、`player_scored`、`player_scores_finalized`）。
- **隔離本地開發捷徑**：預覽或除錯用輸入（例如 `F7` 疊層試玩、`--self-test`）必須明確隔離條件，不得影響 Steam 正常連線對戰。

## 4. 四級測試與驗收規範

| 層級 | 驗證範圍 | 執行方式與通過標準 |
| --- | --- | --- |
| **Tier 0：Godot 本機測試** | 腳本語法、玩法邏輯自測、封面截圖 | 1. 使用 Godot 4.5.2 headless `--check-only --script` 檢查獨立腳本語法（繼承 `"res://..."` 的覆寫腳本標註需完整遊戲執行環境）。<br>2. 執行 `--self-test` 驗證移動、擊退、安全間隔底線、預設組合與排名同分規則，確認輸出 `SELF_TEST_PASSED`。<br>3. 擷取 `1280×720` 封面圖至 `apps/desktop/ui/images/<id>.png` 並實際檢視截圖效果。 |
| **Tier 1：打包、契約與 Lint** | 確定性 ZIP、架構邊界、目錄契約、文件與 Rust Lint | 執行 `node scripts/pack-mod.mjs --all --verify-catalog`、`npm run check:architecture`、`npm test`、`npm run lint:rust`。自動驗證 ZIP `size`／`sha256` 吻合、`mod.json` 與 `catalog/mods.json` 的版本與 ID 相符、`mods/<id>/README.md` 非空白、`requiredFiles` 全數存在、Worker R2 下載測試與三語文件相對連結皆正確。 |
| **Tier 2：Rust L1 與 L3 實包模擬** | ZIP 解壓、GDPC v3 寫入與截斷還原、交易安全 | 執行 `npm run test:rust`（覆蓋 `pck_loader`、`installer`）。於 macOS 本機可使用未提交的原版 Steam v2.1.2 `Machine Party.pck` 隔離複本執行 `MPM_L3_VANILLA_PCK="/path/to/Machine Party.pck" npm run test:rust`，確認寫入與原版 SHA-256 逐位元組還原。 |
| **Tier 3：Windows Steam 實機驗收** | 開放正式安裝前的必要門禁（**`verified: true` 前置條件**） | 於 Windows + Steam `v2.1.2` 完成：桌面端經 Worker 下載並校驗 SHA-256 安裝 → Steam 啟動遊戲 → 大廳預設、輪換池、多人 RPC 聯機對局 → 離線解除安裝並核對原版 `Machine Party.pck` SHA-256 還原；另須確認與外部 MPML 和平共存，以及與直接修補 PCK 模組的互斥保護。 |

### 遊戲模組的回歸測試基準

2026-11-19，Windows 玩家確認滾筒嘉年華 v0.1.3 已恢復正常（目錄套件 `1011`，修正提交 `64be6cc`）。故障版在啟動時編譯 `official_minigame.gd`，Godot 4.5.2 無法推斷 `ids` 的型別。載入器記錄了模組入口已載入，但略過了播放清單註冊。

- **小遊戲從列表消失時**，先查 `user://modloader.log` 的模組版本、第一個編譯失敗的腳本及註冊結果，再對照同一次啟動的 `user://logs/godot.log`，找出第一條解析錯誤與行號。Windows 的兩個路徑都以 `%APPDATA%\Godot\app_userdata\Machine Party` 為起點。
- **測試遊戲實際載入的入口腳本。** 按遊戲的自動載入順序編譯隨包出貨的腳本，包含以場景載入的單例。若編譯器在啟動初期無法推斷型別，就明確宣告。本次修正是 `var ids: Array = PlayerManager.player_presences.keys()`。回歸測試涵蓋首次編譯、建立可玩的場景，以及大廳已預載原腳本時的註冊行為。[滾筒註冊測試](../../../tests/mods/roller-registration.test.mjs)
- **保留玩家的顯示設定。** 畫質模組應將解析度目標套用於 3D 渲染。啟用前後，比對全螢幕模式、視窗尺寸與位置、2D 介面縮放，並涵蓋選用的啟動參數。[獨立高清顯示測試](../../../tests/mods/standalone-hd.test.mjs)

## 5. 目錄接入與桌面端整合

將第一方自研模組接入目錄與 R2／Worker 管線的標準流程：

1. 在 `mods/<id>/` 備妥 `README.md`、`mod.json`、執行期 GDScript 檔案，以及封面圖片 `apps/desktop/ui/images/<id>.png`。
2. 執行 `node scripts/pack-mod.mjs <id>` 取得確定性的 `filename`、`size`、`sha256` 與 `files` 清單。
3. 於 [`catalog/mods.json`](../../../catalog/mods.json) 新增對應條目：
   - 填寫唯一的 `id` 與 `order`、來源 `repo`（例如 `"JamesGZM/machine-party-mod-manager"`）、`image` 與 `"version": "v<mod.json.version>"`。
   - 同一倉庫的新增模組使用 `"inventoryById": true` 建立獨立安裝紀錄，見 [ADR-010](../architecture/ADR-010-shared-repository-mods.md)。
   - 填寫 `"package"`：唯一數字字串 `assetId`（例如 `"1001"`）、`scripts/pack-mod.mjs` 輸出的 `filename`、`size`、`sha256`，以及 `"mirrorApproved": true`。
   - 填寫 `supportedGameVersions` 與對應桌面版號的 `windowsPreview`，在通過 Tier 3 前一律保持 `"verified": false`。
   - 設定 `adapter`：`kind: "loader-files"`、`platforms: ["windows"]`、`target: "pckDir"`、`touches: ["mods"]`、`exclusive: "loader"`、`autoLoader: true`、`upstreamUninstall: false`、原版 `baseline` 指紋與逐一對應打包檔案的 `requiredFiles`。
   - 提供完整的 `zh-CN`、`zh-TW`、`en` 三語 `name`、`summary`、`detail` 與搜尋 `aliases`。
   - 將 `category` 設為 `expansion`、`game`、`tool` 或 `graphics`。`releaseNotes` 為選填。提供時，將 `version` 設為條目版本，並填寫已有的翻譯。彈窗只顯示玩家目前語言的說明。若連線需要全員升級，可在說明中提醒。
4. 同步更新 [`mods/README.md`](../../../mods/README.md) 索引表。在[英文](../../../README.md)、[簡中](../../readme/README.zh-CN.md)、[繁中](../../readme/README.zh-TW.md)首頁的模組表中，依目錄順序加入該模組與版本。
5. 不會有任何介面特例：所有目錄模組使用完全相同的卡片樣式、詳情版面與 Worker 下載 → 校驗 → 安裝彈窗流程。

版本資料範例

```json
{
  "version": "v1.2.0",
  "category": "game",
  "releaseNotes": {
    "version": "v1.2.0",
    "zh-CN": "修复第二回合计分重复的问题。",
    "zh-TW": "修正第二回合重複計分的問題。",
    "en": "Fixed scores being counted twice in round two."
  }
}
```

## 6. 確定性 ZIP 打包與 R2 / Worker 部署流程

- **跨平台確定性打包**：[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) 依字典序收集非排除檔案，採用 `ZIP_STORED`（method `0`）與固定 DOS 時間戳記（`1980-01-01 00:00:00`）產生封存檔，確保 macOS、Linux 與 Windows 產生完全相同的位元組與 SHA-256。
- **CI 自動上傳 R2 與部署 Worker**：執行 `.github/workflows/catalog-worker.yml` 時，會自動跑 `node scripts/pack-mod.mjs --all --verify-catalog --out "$RUNNER_TEMP/packages"`、將缺少的 `packages/sha256/<sha256>.zip` 上傳至 R2（`machine-party-mods`）、驗證全部 `mirrorApproved` 套件的 R2 `ContentLength`，接著上傳 `catalog/revisions/<revision>.json`、部署 `services/catalog-worker` 並以 `HEAD /v1/downloads/...` 確認線上端點回傳 200。
- **更新既有自研模組** — 調升 `mods/<id>/mod.json` 的版本號，執行 `node scripts/pack-mod.mjs <id>` 取得新檔名、大小與 SHA-256。在 `catalog/mods.json` 更新套件資料（含 `assetId`）、目錄修訂號與模組版本。若有舊版說明，請更新或移除。同步更新模組 README、[模組索引](../../../mods/README.md)及[英文](../../../README.md)、[簡中](../../readme/README.zh-CN.md)、[繁中](../../readme/README.zh-TW.md)首頁表格的版本。推送至 `main` 後執行 `Deploy mod catalog Worker`。更新桌面用戶端時請參閱[發布管理器更新](releasing.md)。

若管理器已收錄這個原生 MPML 模組，可設 `"updateChannel": "preview"` 將新版提供給 Windows 測試版玩家。目錄部署流程會簽署這次修訂。Windows 測試版 0.1.2-12 在「模組目錄」點選「更新至」，核對版本後確認。Windows 預覽版 0.1.2-11 的操作步驟見[支援指南](../SUPPORT.md)。通過 Steam 驗收後再設 `"verified": true`。詳見 [ADR-012](../architecture/ADR-012-single-mod-updates.md)。

## 延伸閱讀

- [ADR-009：自研模組、R2 確定性打包與自管載入器規範](../architecture/ADR-009-bundled-first-party-mods.md)
- [ADR-005：安裝交易與原版遊戲驗證還原](../architecture/ADR-005-install-transactions.md)
- [ADR-007：模組轉接器與 macOS 模擬驗證層級](../architecture/ADR-007-mod-adapters.md)
- [正式目錄交付方案](../catalog/delivery.md) · [開發指南](README.md) · [自研模組目錄索引](../../../mods/README.md) · [滾筒嘉年華 README](../../../mods/roller-carnival/README.md)
