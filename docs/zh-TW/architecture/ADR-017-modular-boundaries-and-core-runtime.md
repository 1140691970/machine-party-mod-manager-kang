# ADR-017 · 模組化邊界、核心庫模組與分階段重構方案

[English](../../en/architecture/ADR-017-modular-boundaries-and-core-runtime.md) · [简体中文](../../zh-CN/architecture/ADR-017-modular-boundaries-and-core-runtime.md) · **繁體中文**

日期：2026-11-23。狀態：階段 1–5 已落地並通過自動化與無頭測試驗收（依階段 5 條件暫不拆倉；仍待 Windows Steam `v2.1.2` 實機驗證）。

## 問題

隨著桌面管理器（`apps/desktop/`）與 7 個自研 GDScript 模組（`mods/`，`.gd` 原始碼合計 20,405 行）以不同節奏快速演進，目前程式碼結構已浮現四個影響擴展性與維護成本的瓶頸：

1. **桌面端單檔過胖且架構守衛存在盲區**：
   - `apps/desktop/src-tauri/src/installer.rs` 已膨脹至 6,360 行（將程序與鎖抽象、ZIP 解壓、交易紀錄、啟停狀態、互斥衝突檢查、副本校驗/掃描、兩套適配器實作及約 3,490 行內聯測試混在同一檔案）。
   - `apps/desktop/src-tauri/src/pck_loader.rs` 達 1,443 行（GDPC v3 / ECFG 二進位編解碼與安裝/還原狀態機及測試耦合）。
   - `apps/desktop/ui/catalog-view.js` 達 1,053 行（列表渲染、彈窗、單體安裝流程與批次操作混寫）。
   - `scripts/check_architecture.mjs` 中的 `tauriFree` 目前僅硬編碼檢查頂層 6 個 `.rs` 檔，尚未涵蓋 `apps/desktop/src-tauri/src/installer/update.rs` 等子模組。
2. **自研模組單檔過胖**：
   - `mods/team-party/main.gd` 單檔達 4,570 行，其中大廳 UI 與 3D 椅子拖曳佔約 2,270 行，針對外部自研小遊戲的反射包裝佔約 820 行。
   - 三款自研小遊戲主腳本（`mods/roller-carnival/roller_carnival_game.gd` 1,890 行、`mods/bubble-blitz/bubble_blitz_game.gd` 2,260 行、`mods/spike-ring/spike_ring_game.gd` 2,785 行）將玩法迴圈、特效/貼花池與連線同步混在一起。
3. **多小遊戲 Hub 覆寫程式碼逐字重複**：
   - 依 [ADR-015](ADR-015-multi-minigame-hub.md)，`override_game.gd`（150 行）、`override_local_game.gd`（137 行）、`override_picker.gd`（251 行）、`override_playlist.gd`（137 行）共 675 行程式碼在 `mods/bubble-blitz/`、`mods/roller-carnival/` 與 `mods/spike-ring/` 中完全重複存在。每次修復 Hub 都必須同步修改並重發全部小遊戲套件。
4. **遊戲側適配邏輯與桌面端發版強綁定**：
   - `apps/desktop/src-tauri/assets/mpm_bootstrap.gd`（916 行）中有 447 行是針對遊戲大廳 UI 的防重疊排版邏輯。遊戲側版面一旦需要調整，就必須重新簽章發布桌面用戶端，無法透過目錄與 R2 熱更新。

## 決策

參考成熟開源模組生態（`GodotModding/godot-mod-loader` + `Brotato-ContentLoader`、`Fabric Loader` + `Fabric API`、`modrinth/code`、`Kesomannen/gale`、`NexusMods.App`），確立四層職責邊界，並按五個可獨立驗收的階段推進落地：

```text
[ 桌面管理器本體 (Rust + 原生 ES UI) ] ── 下載、交易安裝、requires 依賴圖、PCK 還原
            │ 僅注入極簡引導器
            ▼
[ 極簡載入器 (mpm_bootstrap.gd) ]     ── 掃描發現、requires 排序、compile/override/hook 原語
            │ 優先載入前置核心庫
            ▼
[ 核心庫模組 (mpm-core，走 R2 分發) ]  ── Minigame Hub v2、Lobby UI 協調器、共用 FX 與事件匯流排
            │ requires: ["mpm-core"]
            ▼
[ 玩法與功能模組 ]                     ── roller-carnival / bubble-blitz / spike-ring / team-party / 後續新模組
```

### 階段 1：架構守衛硬化與桌面端拆檔（零行為變更）

1. **加固 `scripts/check_architecture.mjs`**：
   - 將 6 檔黑名單改為白名單機制：`apps/desktop/src-tauri/src/` 下（含任意層級子目錄）除 `main.rs`、`commands.rs`、`app_updates.rs` 外，其餘全部 `.rs` 檔皆禁止依賴 `tauri::`、`tauri_plugin_*::` 或 `crate::commands`。
   - 在 `tests/architecture/boundaries.test.mjs` 補充子模組違規回歸測試。
2. **拆分 `apps/desktop/src-tauri/src/installer.rs` 為 `installer/mod.rs` 及職責子模組**：
   - 在 `installer/mod.rs` 保留全部既有 `pub` 匯出以維持 `commands.rs` 呼叫零改動，並與既有的 `prepare.rs`、`steam_restore.rs`、`update.rs` 並列：
     - `runner.rs`：`ProcessRunner`、`SystemRunner`、`GameLockCheck`、`SystemGameLockCheck`
     - `zip.rs`：`extract_zip` 與路徑穿越校驗
     - `transaction.rs`：`FileFingerprint`、`TransactionRecord`、備份路徑與 `transactions.json` 讀寫
     - `state.rs`：`.mpm-state.json` 啟停狀態管理
     - `conflicts.rs`：互斥群組檢查與外部載入器偵測
     - `inspect.rs`：`inspect_mod`、`validate_game_mods`、`reconcile_copy`、`adopt_manual_install`、`scan_copy`
     - `adapters/loader.rs`：`normalize_loader_staging`、`install_loader_files`、`resumable_loader_cleanup`
     - `adapters/upstream_cli.rs`：`validate_adapter`、`build_command`、`parse_status`、`parse_mp8r_restore`、`mirror_delta_backup`
     - `tests/`：按領域主題遷出約 3,490 行內聯測試。
3. **拆分 `apps/desktop/src-tauri/src/pck_loader.rs`**：
   - 拆出 `pck_loader/gdpc.rs`（GDPC v3 索引與載荷處理、MD5 與 ECFG 編解碼）、`pck_loader/mod.rs`（安裝/還原/標記狀態機）及 `pck_loader/tests.rs`。
4. **拆分 `apps/desktop/ui/catalog-view.js`**：
   - 堅持零建置原生 ES 模組（[ADR-001](ADR-001-project-boundaries.md)），拆分為 `catalog-view.js`（列表與卡片）、`mod-dialogs.js`（詳情、更新確認與卸載彈窗）、`mod-install-flow.js`（單體下載、安裝、切換與啟停流程）及 `batch-view.js`（搭配 `batch.js` 承擔篩選列與批次操作介面）。
5. **檔案規模約定**：正式原始碼模組控制在聚焦規模（約 <=700 行），測試按域獨立存放。

### 階段 2：自研模組模組化、共享單一來源與原生組隊下沉（已完成）

1. **拆分 `mods/team-party/main.gd` 並退役自研小遊戲執行期包裝**：
   - 將 `mods/team-party/main.gd`（4,570 行 -> 685 行）拆出 `team_registry.gd`、`lobby_assignment.gd`、`lobby_ui.gd`、`lobby_drag_3d.gd`、`vanilla_ingame.gd` 與 `ingame_hud.gd`，保留入口、RPC 端點與公開/測試門面，確保 `tests/mods/team_party_test.gd` 與 `tests/mods/team_party_sandbox.gd` 完全相容。
   - 移除 `_wrap_custom_stage` 與約 820 行外部原始碼重寫包裝；`team-party` 僅保留房間組隊管理、右上角 Squad 狀態列與無法修改原始碼的官方原版小遊戲掛接。
2. **消除重複 `override_*.gd` 並建立可選組隊共享助手**：
   - 在 `mods/_shared/minigame-hub/` 與 `mods/_shared/team-support/team_support.gd` 建立單一來源（不放 `mod.json`），由 `scripts/pack-mod.mjs --sync-shared` 與 `scripts/check_architecture.mjs`（`checkSharedModParity`）保證跨模組零漂移。
3. **三款自研小遊戲原生組隊與子模組拆分**：
   - `mods/bubble-blitz/`（`v0.1.5`）：原生實作分隊出生、友軍火焰免疫、倒地碰觸救援、救援傾向 AI、提前勝出與小隊同步計分，並拆出 `fx_pool.gd`、`ai_controller.gd`、`self_test.gd`。
   - `mods/spike-ring/`（`v0.1.3`）：原生實作分隊出生、友軍零推搡、360° 衝擊波免傷、3.5m 護盾共振、僅攻擊敵隊 AI、提前勝出與小隊同步計分，並拆出 `hazard_director.gd`、`fx_pool.gd`、`ai_controller.gd`、`self_test.gd`。
   - `mods/roller-carnival/`（`v0.1.11`）：原生實作依隊分道、隊色底座與名牌、未團滅繼續比拼與小隊同步計分，並拆出 `fx_pool.gd`、`hud_ui.gd`、`self_test.gd`。
   - 重跑 `scripts/pack-mod.mjs --all` 並同步更新 `catalog/mods.json`（`revision: 2026-11-23.1-mpml1`）。

### 階段 3：宣告式 `requires` 依賴解析與 `mpm-core` 核心庫模組（已完成）

1. **在維持 `schema: 1` 下擴充 `catalog/mods.json`**：
   - 新增選用欄位 `requires`（如 `[{"id": "mpm-core", "minVersion": "v0.1.0"}]`，預設為空陣列）與核心庫角色/分類標記，讓桌面端在介面上妥善管理核心依賴，而不干擾玩家瀏覽玩法模組。
2. **在 Rust 安裝引擎實作依賴解析**：
   - **安裝與更新**：對依賴有向無環圖做遞迴拓樸排序並攔截循環依賴，在安裝目標模組前自動安裝或升級缺失/過舊的前置庫；任一步失敗整筆回滾。
   - **停用與卸載保護**：當仍有其他已安裝或已啟用的模組依賴該核心庫時，拒絕停用/卸載並回傳可翻譯錯誤鍵與依賴方清單；當最後一個依賴方卸載且核心庫為自動安裝時，一併清理並還原原版 `Machine Party.pck`。
3. **引入 `mods/mpm-core/`（走與所有模組相同的 R2 + `catalog-worker` 管線）**：
   - 以 `priority: -100` 優先載入，集中承載高頻演進的遊戲側執行期邏輯：
     1. **Minigame Hub v2（`HUB_VERSION = 2`）**：在混合版本共存期間平滑覆蓋舊版 `HUB_VERSION = 1`。
     2. **Lobby UI 協調器 v2**：接管原嵌在 `mpm_bootstrap.gd` 中的遊戲大廳防重疊排版，使 `mpm_bootstrap.gd` 瘦身回極少修改的純載入器。
     3. **共用工具層**：跨模組事件匯流排、通用 FX/貼花池基類與多語在地化輔助函式。
4. **發布節奏控制**：先發布並實機驗收支援 `requires` 的桌面版，再讓後續新版本小遊戲宣告依賴 `mpm-core`。

### 階段 4：方法級 Hook 鏈與跨模組事件契約

1. **方法級 Hook 鏈**：
   - 在載入器/核心層引入類似 `ModLoaderHookChain` 的方法級掛載原語，允許多個系統模組按順序攔截同一個原版 GDScript 函式，避免整檔 `override_script` 互相覆蓋。
2. **統一小遊戲與組隊事件契約**：
   - 在 `mpm-core` 定義標準小遊戲生命週期與事件介面，供未來新模組與官方關卡掛接複用（`team-party` 原有的 ~820 行外部反射包裝已於階段 2 提前退役）。

### 階段 5：CI 按路徑分流與未來拆倉觸發條件（暫不拆倉）

1. **CI 按路徑分流**：
   - 在桌面、載入器與模組仍高頻協同演進期間維持單倉，在 `.github/workflows/check.yml` 中按改動路徑分流 PR 檢查（`apps/desktop/**` 與 `mods/**` + `catalog/**`），合入與發布前保留全量把關。
2. **明確的未來拆倉條件**：
   - 僅當（a）桌面管理器與 `mpm-core` API 進入穩定維護期，且（b）自研模組超過約 10–12 個或準備高頻接收外部社群模組 PR 時，再將 `mods/` 拆為獨立 `machine-party-mods` 儲存庫。由於 [ADR-009](ADR-009-bundled-first-party-mods.md) 已將第一方與第三方分發統一到 R2 + `catalog-worker`，屆時拆倉無需調整分發架構。

## 備選方案

- **立即將 `mods/` 拆分為獨立儲存庫**：目前 `mpm_bootstrap.gd`、自研模組與跨模組共存測試（`tests/mods/`）經常在同一 PR 中聯動修改；過早拆倉只會增加跨倉對版號的摩擦。
- **引入 JS 打包框架或拆分 Cargo workspace**：違背 [ADR-001](ADR-001-project-boundaries.md) 的輕量化邊界，原生 ES 模組分檔與 Rust 子模組目錄即可零工具鏈開銷解決問題。
- **將本機 JSON 狀態（`installations.json`、`transactions.json`）遷往 SQLite**：依 [ADR-003](ADR-003-desktop-updates.md)，在幾十個模組規模下，人類可讀的 JSON 交易紀錄更簡單、易審計且完全向後相容。
- **繼續把遊戲側協調邏輯堆在 `mpm_bootstrap.gd` 中**：每次遊戲 UI 或 Hub 調整都會被迫發布新版簽章桌面用戶端。

## 相容性

- 保留 `installations.json`、`game-path.json`、`transactions.json`、`.mpm-state.json`、Tauri IPC 命令名、更新器設定及 `catalog/mods.json` `schema: 1`（[ADR-003](ADR-003-desktop-updates.md)）。
- 階段 1 與階段 2 皆為純內部重構，不改變任何使用者側行為與儲存格式。
- 階段 3 向後相容舊版桌面用戶端（舊版本會安全忽略未知選用目錄欄位）與外部 `MachinePartyModLoader.exe` 環境，並在版本過渡期透過 `HUB_VERSION = 2` 平滑覆蓋舊版 `HUB_VERSION = 1`。

## 驗證證據與各階段門禁

- **階段 1 與階段 2 已完成**：
  - 階段 1：`scripts/check_architecture.mjs`（涵蓋 Rust 子模組的白名單機制與 `tests/architecture/boundaries.test.mjs` 回歸測試）、`pck_loader/`、`installer/`（保留全部 29 項測試）與 `apps/desktop/ui/` 拆分均已通過 `npm run check:architecture`、`npm test`、`npm run lint:rust` 與 `npm run test:rust`。
  - 階段 2：`mods/_shared/{minigame-hub,team-support}/` 一致性校驗、`mods/team-party/` 6 模組拆分，以及 `mods/bubble-blitz/`（`v0.1.5`）、`mods/spike-ring/`（`v0.1.3`）、`mods/roller-carnival/`（`v0.1.11`）原生組隊下沉與子模組拆分均已通過 `node scripts/pack-mod.mjs --all --verify-catalog`、三款小遊戲獨立 Godot `--self-test`（`SELF_TEST_PASSED`）、`npm run check:architecture` 與 `npm test`（含 `tests/mods/team-party.test.mjs`）。
  - 階段 3：`catalog.rs`（`ModRequirement`、`role`、`compare_numeric_versions`）、`installer/deps.rs`（DAG 解析、循環/版本攔截、失敗回滾、停用與卸載保護、末依賴自動清理）、`ui/` 依賴預下載與詳情提示、`mods/mpm-core/`（`v0.1.0`、`HUB_VERSION = 2`、`event_bus.gd`、`locale_utils.gd`、`lobby_ui_coordinator.gd`）及 `mpm_bootstrap.gd` 讓步邏輯已通過 `deps_tests`、`tests/ui/dependencies.test.mjs` 與 `tests/mods/mpm-core.test.mjs`。依發布節奏，既有小遊戲將於 Windows Steam 實機驗收後再啟用 `requires: ["mpm-core"]`。階段 4–5 仍按規劃推進。
- **階段 1 驗收門禁**：`npm run check:architecture`（含子模組）、`npm test`、`npm run lint:rust`、`npm run test:rust`（本機具備原版包時加跑 `MPM_L3_VANILLA_PCK` 模擬測試）。
- **階段 2 驗收門禁**：`node scripts/pack-mod.mjs --all --verify-catalog`、`npm test`（含 `tests/mods/*.test.mjs`）以及各小遊戲獨立 Godot `--self-test`（`SELF_TEST_PASSED`）。
- **階段 3 驗收門禁**：Rust L1 依賴圖/循環攔截/回滾/末依賴自動清理測試、UI 依賴提示與卸載攔截測試、Godot `mpm-core` 共存與混裝 `HUB_VERSION` 測試，以及在正式目錄啟用 `requires` 前的 Windows Steam 實機驗收。
- **階段 4 驗收門禁**：Godot 4.5.2 多模組 Hook 鏈共存測試與 `team-party` 整合測試。
