# 現行架構

[English](../../en/architecture/README.md) · [简体中文](../../zh-CN/architecture/README.md) · **繁體中文**

本文是唯一的現行架構說明。重大決策記錄在同目錄的 ADR；安裝、切換與恢復仍是設計草案，待實機驗證。

## 元件與邊界

```mermaid
flowchart LR
  ui["apps/desktop/ui"] -->|"bridge.js IPC"| commands["src-tauri commands.rs"]
  commands --> domain["game / inventory / preferences / catalog"]
  ui -->|HTTPS| worker
  worker -->|CATALOG| catalogWorker["services/catalog-worker"]
  catalogWorker --> packages["R2 packages/sha256"]
  catalogData --> catalogWorker
  catalogData["catalog/mods.json"] --> domain
  commands --> updater["app_updates.rs"]
  updater -->|HTTPS| worker["services/update-worker"]
  worker --> r2["R2 app-releases"]
```

| 目錄 | 職責 |
| --- | --- |
| `apps/desktop/src-tauri` | Tauri 2 殼層。`main.rs` 只組裝；`commands.rs` 解碼、驗證 IPC 並轉交；`game.rs` 辨識 Steam 遊戲副本；`installer.rs` 為無 Tauri 相依的交易引擎與適配器工廠；`pck_loader.rs` 透過 `assets/mpm_bootstrap.gd` 與 `Machine Party.pck.modloader.json` 執行管理器自管 Godot PCK 載入器的修補與還原；`inventory.rs` 讀取各副本的安裝紀錄；`preferences.rs` 保存手動選擇；`catalog.rs` 內嵌目錄並限制可開啟的作者與專案首頁（`open_project` 同時允許目錄頂層 `repo` 與各模組 `repo`）；`app_updates.rs` 負責簽章更新。 |
| `apps/desktop/ui` | 無建置步驟的原生 ES 模組。`bridge.js` 是唯一接觸 Tauri 的檔案；`catalog.js` 與 `versions.js` 為純函式；`state.js` 保存介面狀態；各 `*-view.js` 負責繪製。樣式分三層：`tokens.css` 設計 token、`components.css` 共用元件、`style.css` 頁面版面；`dom.js` 與 `icons.js` 建立元件與圖示。 |
| `catalog/mods.json` | 管理器頂層 `repo`、模組收錄 ID、序號、版本、三語文案、別名與宣告式 `adapter` 設定的唯一來源（[ADR-002](ADR-002-catalog-source.md)）。 |
| `mods/<id>/` | 本儲存庫開發的自研 GDScript 玩法模組，由 `scripts/pack-mod.mjs` 確定性封裝為 ZIP 上傳至 R2 並經由 catalog Worker 分發，搭配內建自管載入器一鍵安裝與還原（[ADR-009](ADR-009-bundled-first-party-mods.md)）。 |
| `services/update-worker` | 唯讀 Worker，自 R2 提供穩定清單與按版本固定的安裝包（[ADR-003](ADR-003-desktop-updates.md)）。 |
| `scripts`、`tests` | 發布、部署、驗收與邊界檢查；Node 測試分為 `ui`、`contracts`、`architecture`。Rust 單元測試放在各模組旁。 |

本機資料位於應用程式設定目錄：`game-path.json` 保存玩家選擇的遊戲路徑；`installations.json` 第一層鍵是遊戲路徑，第二層鍵是 `作者/倉庫`，值為管理器安裝的版本。介面語言與已略過提示的管理器版本號（`dismissed-app-update`）存於 WebView 的 `localStorage`。

## 遊戲定位與辨識

Steam 上的 Machine Party（App ID 4108000）僅支援 Windows，不考慮在 macOS 上遊玩。App 由 Steam 安裝位置讀取遊戲庫清單，在各庫查找 App ID 4108000 的安裝清單，並區分已保存的遊戲根目錄（作為 `installations.json` 的鍵）與解析出的實際存放執行檔及 `Machine Party.pck` 的內層目錄（如 `Machine Party_Windows`）。記錄 Steam build、實際路徑及資料檔雜湊；相容性以經實測的組合為準。玩家搬移遊戲後重新檢查，備份按副本和安裝前的檔案指紋保存。

## 目錄、搜尋與下載

維護者發布固定的模組 ID、收錄序號、作者、README 摘要、別名與首頁。每個可安裝版本另存上游標籤或提交、資產名稱、SHA-256、支援的遊戲指紋、安裝方式、所需載入器版本、已知衝突及下載路徑。App 快取最近一次成功讀取的目錄。

正式列表統一經自訂網域的 Cloudflare Worker 取得。發布時部署已審核快照，GitHub 用於協作與發布；玩家瀏覽列表不依賴對 GitHub 的連線。大陸下載優先走同網域 Worker；允許再散布的已驗證原檔優先存入私有 R2，其他資產依授權與線路測試決定是否串流回源；只允許作者直連的資產另標限制。客戶端啟動時讀取 Worker 快照，快取通過驗證的資料供離線瀏覽。每個版本透過 Release 資產 ID 對應 R2 鍵 `packages/sha256/<sha256>.zip`。僅開放允許鏡像的套件。端點契約、失敗處理、發布與三網驗收見[正式目錄交付方案](../catalog/delivery.md)。

## 安裝、切換與恢復（設計草案）

一鍵安裝先以目錄大小與 SHA-256 核對作者發行 ZIP，再由 Rust 在暫存區準備 MPML 目錄。Overtime 讀取 CLI 包中的 payload 清單，保留上游的載入時序、版本與原版腳本指紋檢查。Broadcast 和 Binary1936 讀取資源樹。MachineParty+、滾筒嘉年華與房間機器人已採載入器格式。

安裝交易記錄來源指紋、轉換規則版本與已安裝檔案指紋。三款八人玩法屬同一互斥群組，切換時可保留其他載入器模組。另行分發轉換包需要維護第二份發行產物，執行各上游安裝器則需維護多套備份與還原程序。

舊版客戶端仍可使用相容目錄與下載網址。既有 Overtime MPML 安裝可繼續使用。舊式受管 PCK 補丁可在模組詳情選擇「切換為載入器安裝」，先驗證新包，再還原已記錄的副本並安裝。手動安裝的 mods/broadcast-8p 須先移出遊戲目錄。檔案出現未知變更時，還原會停止。

## 是否維護 fork

優先復用作者發行的資源，轉換規則隨管理器版本維護。App 可自行承擔偵測、備份及校驗。若遇到無法從外部解決的互動或還原問題，記錄可重現案例，優先向上游提交小改動。授權允許且確有必要時才維護安裝器 fork，保留原作者、來源及版本對照。

## 架構決策紀錄

- [ADR-001：專案邊界，保留 Tauri 與原生 JS](ADR-001-project-boundaries.md)
- [ADR-002：模組目錄的唯一來源](ADR-002-catalog-source.md)
- [ADR-003：簽章的桌面更新](ADR-003-desktop-updates.md)
- [ADR-004：按語言組織文件](ADR-004-language-documentation.md)
- [ADR-005：模組安裝交易與備份（提議）](ADR-005-install-transactions.md)
- [ADR-006 · 線上模組目錄](ADR-006-online-catalog.md)
- [ADR-007：模組適配層與 macOS 模擬驗證（提議）](ADR-007-mod-adapters.md)
- [ADR-008 · 下載快取、啟動偵測與還原校驗](ADR-008-cached-installations.md)
- [ADR-009：自研模組、R2 確定性打包與自管載入器規範（提議）](ADR-009-bundled-first-party-mods.md)
- [ADR-010 · 同倉庫模組的獨立安裝紀錄](ADR-010-shared-repository-mods.md)
- [ADR-011 · 安裝前統一準備 MPML](ADR-011-prepare-mpml.md)
- [ADR-012 · 更新單一已安裝模組](ADR-012-single-mod-updates.md)

- [ADR-013 · 從簽章目錄安裝原生模組](ADR-013-signed-native-installs.md)
- [ADR-014 · Steam 驗證成功後清理受管模組](ADR-014-steam-restore.md)
- [ADR-015 · 多小遊戲共存註冊中心](ADR-015-multi-minigame-hub.md)
- [ADR-016 · 基於 R2 圖床的選用模組封面規範](ADR-016-r2-mod-covers.md)
