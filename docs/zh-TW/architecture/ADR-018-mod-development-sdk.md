# ADR-018 · MPM 模組開發 SDK 與工具鏈架構

[English](../../en/architecture/ADR-018-mod-development-sdk.md) · [简体中文](../../zh-CN/architecture/ADR-018-mod-development-sdk.md) · **繁體中文**

- **狀態**：已落地（無頭測試已驗收；仍待 Windows Steam `v2.1.2` 實機驗證）
- **日期**：2026-11-23
- **關聯決策**：[ADR-001](ADR-001-project-boundaries.md)、[ADR-009](ADR-009-bundled-first-party-mods.md)、[ADR-015](ADR-015-multi-minigame-hub.md)、[ADR-017](ADR-017-modular-boundaries-and-core-runtime.md)、[模組 SDK 參考手冊](../development/mod-sdk.md)

## 背景與問題

完成 [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md) 階段 1–3 後，儲存庫已具備清晰的 Rust/UI 分層、`mods/_shared/` 單一來源校驗、宣告式 `requires` 依賴解析與 [`mpm-core`](../../../mods/mpm-core/README.md)（`v0.1.0`，`priority: -100`）核心運行庫。但在繼續開發第 4、5 款自研小遊戲或開放第三方社群創作時，仍存在 4 類開發體驗瓶頸：

1. **單模組膠水程式碼重複（約 250–350 行）**：每款小遊戲都要重複撰寫 `_register_mod_scripts`、`_register_into_hub`、`_install_hub_overrides`、`_apply_cached_override`、`official_minigame.gd` 與物件池預熱骨架。
2. **新建與維護依賴人工清單**：新增模組需手動建立 7–10 個檔案、人工查詢未佔用的 `order` / `assetId` / `TARGET_SLOT_ID`、回填 `catalog/mods.json` 並同步 4 處 README 表格。
3. **Godot 測試夾具各自重造**：`tests/mods/` 下各測試腳本分別複製了 `MockLoader`、`PlayerManager`、`GameManager`、`Minigame`、`LobbyScene`、`1280×720` 無頭視窗與 `.gd.uid` 清理邏輯。
4. **寫死原版列舉槽位與人工防呆**：目前三款小遊戲借用了原版未使用的 `MinigameIdentifier`（6 / 8 / 17），後續擴充必然衝突；而 [mod-development.md](../development/mod-development.md) 中的效能與編譯紅線尚未接入靜態自動檢查。

## 開源生態參考

我們結合本專案「零額外框架／零打包器」（[ADR-001](ADR-001-project-boundaries.md)）的原則，吸收成熟開源 Mod 生態的工程實踐：

| 參考專案 | 借鑑的設計 | 刻意不引入的部分 |
| --- | --- | --- |
| **GodotModding / `godot-mod-loader`**（Brotato、Dome Keeper） | Godot 4 清單格式、`ModLoaderHookChain` 方法級掛載、結構化日誌（`user://modloader.log`）與模組開發者工具規範 | 笨重的編輯器外掛 UI；本專案桌面端與 headless Godot CLI 已涵蓋打包與校驗 |
| **SMAPI**（`Pathoschild/SMAPI`，星露谷） | 統一的 Mod Helper 門面（Events / i18n / Registry）、明確的版本相容性契約，以及執行前靜態分析器 | C#/.NET 組件重寫；MPML 基於 GDScript `take_over_path` 與 `compile` |
| **Fabric Loader + Fabric API**（`FabricMC/fabric`） | 極簡、極少變動的底層引導器（`mpm_bootstrap.gd`）與獨立升級的核心庫模組（`mpm-core`）解耦，搭配官方範本產生器 | 立即拆出獨立儲存庫（依 ADR-017 階段 5 延後） |
| **Thunderstore CLI (`tcli`)** | 一體化 `new` / `check` / `pack` 命令列工作流與確定性清單／ZIP 校驗 | 外部套件倉庫上傳（本專案直連 R2 + `services/catalog-worker`） |
| **tModLoader** | 宣告式內容註冊搭配自動動態 ID 分配，告別人工搶佔原版列舉槽位 | 二進位資源重編譯管線 |

## 決策方案：四層輕量級 MPM Mod SDK

基於 Node 22 原生腳本、`mpm-core` 與純 GDScript 建置四層 SDK：

1. **第 1 層：執行期 SDK（`mods/mpm-core/`）**：
   - 提供 `MpmMinigamePlugin` / `core.register_minigame(spec)`，讓新小遊戲的 `main.gd` 只需宣告三語資訊、簡報、按鍵與玩法腳本，無需複製 Hub 膠水。
   - 提供可複用的 `MpmFxPool`（常駐物件池 + 視錐預熱）、`MpmTeamSupport` 橋接，以及 `event_bus`、`locale`、`lobby_ui` 協調器 v2。
   - 升級 Hub v2 支援依 `mod_id` 動態分配高位槽位（`>= 1000`），徹底消除原版 `MinigameIdentifier` 槽位衝突。
2. **第 2 層：零相依開發腳手架 CLI（`scripts/mod-cli.mjs`，`npm run mod -- <cmd>`）**：
   - `mod new <id> --template minigame|tool|graphics`：一鍵產生 `mod.json`、`main.gd`、`README.md`、`project.godot`、`run_mac.sh` 與基礎 `--self-test`。
   - `mod check <id>`：串聯 Godot `--check-only`、`--self-test`、靜態紅線 Linter 與 `pack-mod` 校驗。
   - `mod catalog-sync <id>`：將確定性 `filename`、`size`、`sha256` 與 `requiredFiles` 自動回寫至 `catalog/mods.json`。
3. **第 3 層：共用 Godot 測試沙盒（`tests/mods/_harness/`）**：
   - 沉澱統一的 `MockLoader`（完整 API v2）、`MockGameEnv`（`PlayerManager`、`GameManager`、`Minigame`、`LobbyScene`、`1280×720` 無頭視窗與 `.gd.uid` 自動清理）以及參數化小遊戲契約測試（冷啟動編譯 → 預載場景註冊 → FFA → 原生 `team-party` → 多模組共存 → 無洩漏退出）。
4. **第 4 層：靜態紅線 Linter 與正式 API 契約文件**：
   - 在 `check_architecture.mjs` / `mod check` 中加入 GDScript 靜態規則：攔截 `_process` / `_physics_process` 中呼叫 `get_property_list()`、對動態 `keys()` / `.call()` 使用 `:=`、在 MPML 腳本中使用寫死的 `preload("res://...")`、重複 `TARGET_SLOT_ID` 以及遺漏 `mpm_local_player` 標記。
   - 在[模組 SDK 參考手冊](../development/mod-sdk.md)中明確劃分「穩定公開契約」與「內部實作細節」。

## 分期落地路線

| 階段 | 範圍 | 風險與前置條件 |
| --- | --- | --- |
| **SDK-1** | 正式 API 契約文件（`mod-sdk.md`）+ 靜態模組 Linter（`scripts/mod-lint.mjs`，已接入 `check:architecture`） | **已完成並驗收**（`tests/architecture/mod-lint.test.mjs`、`npm run check:architecture`） |
| **SDK-2** | 共用 Godot 測試 Harness（`tests/mods/_harness/`）+ `scripts/mod-cli.mjs`（`new` / `check` / `catalog-sync`） | **已完成並驗收**（`tests/contracts/mod-cli.test.mjs`、`tests/mods/harness.test.mjs`） |
| **SDK-3** | `mpm-core` 執行期 SDK（`register_minigame(spec)`、`MpmFxPool`、Hub v2 動態高位槽位 `>= 1000`） | **已完成並驗收**（`tests/mods/mpm-core.test.mjs`；仍待 Windows Steam `v2.1.2` 實機驗收） |
| **SDK-4** | 方法級 Hook 鏈（`mods/mpm-core/hook_chain.gd`）+ 三款自研小遊戲接入 `mpm-core` | **已完成並無頭驗收**（`tests/mods/mpm-core.test.mjs`，三款小遊戲已宣告 `requires: ["mpm-core"]`） |

## 備選方案

- **引入外部 JS/TS CLI 框架**：違背 [ADR-001](ADR-001-project-boundaries.md)，Node 22 原生腳本即可零相依完成。
- **將全部 SDK 塞入 `mpm_bootstrap.gd`**：違背 [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md)，會導致每次微調 SDK 都必須重簽發桌面用戶端。
- **立即強行遷移三款既有小遊戲**：延後至 `mpm-core` 通過 Windows 實機驗證後依版本自然演進。

## 相容性

- 完全保留 `catalog/mods.json` `schema: 1`、MPML API v2（`API_VERSION = 2`）、外部 `MachinePartyModLoader.exe` 共存與既有 `mods/<id>/` 目錄結構。
- Hub v2 動態槽位（`>= 1000`）與既有的 Hub v1 槽位（6 / 8 / 17）可同時並存。

## 驗收門禁

- **SDK-1**：`node --test tests/contracts/documentation.test.mjs`、`npm run check:architecture` 與 Linter 單元測試通過。
- **SDK-2**：CLI 腳手架產生的新模組可直接通過 `mod check`、`pack-mod --verify-catalog` 與契約測試。
- **SDK-3 / SDK-4**：Godot 4.5.2 全模組共存與 `team-party` 套件通過，並完成 Windows Steam `v2.1.2` 實機驗收。
