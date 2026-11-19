# ADR-007：模組適配層與 macOS 模擬驗證

[English](../../en/architecture/ADR-007-mod-adapters.md) · [简体中文](../../zh-CN/architecture/ADR-007-mod-adapters.md) · **繁體中文**

日期：2026-11-18（2026-11-19 更新）。狀態：提議；`upstream-cli`（`exe`、`bundled-python`、`powershell`）與 `loader-files`（支援可選的內建 `bundled` 釋放與 `autoLoader` PCK 載入器自動設定）皆已在 `installer.rs` 實作，並在 `catalog/mods.json` 為全部五個 `v2.1.2` Windows 測試版模組（含內建自研模組 `滾筒嘉年華`）完成設定，待完整 Windows 實機驗收後與 [ADR-005](ADR-005-install-transactions.md) 一併定稿。

## 問題

上游模組皆以未經修改的原版壓縮包發布，安裝方式各有不同：

1. Overtime v1.7：`.NET` 主控台程式（`overtime_install.exe` 搭配 `overtime_payload.zip`），向 `Machine Party.pck` 追加腳本並改寫索引，同時寫入幾 KB 的差量還原紀錄（`overtime_restore.dat`）。
2. Binary1936 八人模組 v1.5：Python 補丁腳本（`install.py`，Windows 包內附 `python/python.exe`），重寫整個 `Machine Party.pck` 且不保留備份。
3. Broadcast 8P Freecam v0.91：PowerShell 補丁腳本（`patcher.ps1`），重寫 `Machine Party.pck` 並保存整包備份（`Machine Party.pck.broadcast_backup`）。
4. MachineParty+ v2.1.0：載入器模組包（`mod.json`、`main.gd`、腳本與翻譯），放入 MPML 的 `mods/` 目錄。

若為每個模組在 Rust 中硬編碼安裝流程，後續收錄成本會越來越高；但若直接執行線上目錄隨附的可執行適配腳本，會帶來遠端程式碼執行風險，也違反 [ADR-005](ADR-005-install-transactions.md)。此外，Steam 上的 Machine Party 僅支援 Windows，在 macOS 上需要分層的模擬策略提前驗證核心邏輯。

## 提議的決策

### 1. 交易引擎 + 內建適配器工廠 + 目錄宣告式 `adapter` 設定

維持 `catalog/mods.json` 作為單一資料來源（[ADR-002](ADR-002-catalog-source.md)），為可安裝模組追加可選的宣告式 `adapter` 物件。設定只是純資料，絕不包含可執行腳本。

無 Tauri 相依的 Rust 交易引擎統一負責跨模組的安全保障：

- **遊戲目錄解析**：將已保存的 Steam 遊戲根目錄（作為 `installations.json` 的鍵，例如 `.../party project`）對應到實際存放 `Machine Party.pck` 的內層目錄（例如 `Machine Party_Windows`）。
- **進程與檔案鎖檢查**：寫入前確認遊戲未執行，並取得獨占檔案鎖。
- **暫存下載與完整校驗**：在 Rust 端從既有 Worker 網域（`https://machineparty.ailaogong.men/v1/downloads/{id}/{version}/{assetId}`）下載到暫存區，對照目錄核對外層 ZIP 位元組數與 SHA-256，原樣解壓後核對內部校驗清單（`SHA256SUMS.txt` 及／或 preflight 命令）。
- **寫入前基線與交易日誌**：為 `Machine Party.pck` 及宣告的 `touches` 檔案計算安裝前 `size` 與 `sha256` 指紋；檢查 `exclusive` 互斥群組（所有直接改包模組共用 `"exclusive": "pck"`，並與 MPML 互斥）；寫入 `pending` 交易日誌；寫入後執行讀回自檢（並檢查遊戲目錄內沒有未宣告檔案遭到改動）；提交 `committed`／`rolled_back` 狀態並在啟動時對帳。

適配器工廠依 Rust 內建適配器種類派發：

- `upstream-cli`：在已校驗的解壓目錄內，使用白名單允許的直譯器（`exe`、`bundled-python`、`powershell`）執行相對路徑程式或腳本；使用固定的動作參數範本（`preflight`、`status`、`install`、`uninstall`）、僅限引擎提供的佔位符（`{gameDir}`）；`SystemRunner` 寫入單行 `y\n` 確認後即關閉 `stdin`（無需 `--force` 即可通過 Binary1936 `install.py` 等單次目錄確認提示，同時 EOF 會中止非預期警告提示）；強制非互動參數（如 `--no-pause`）；禁用參數守衛（始終拒絕 `--force`）；`run_status_cmd` 在因非零結束代碼報錯前先比對狀態正則（例如 `install.py --verify` 在未修補 `NOT PATCHED` 時回傳結束代碼 `1`）；整包備份卸載時一併清理 `touches` 中宣告的附屬檔案（如 `Machine Party.pck.broadcast_backup`）。
- `loader-files`：將宣告的模組檔案（來自已校驗的 Worker/R2 下載套件）複製到 `mods/<id>` 等載入器目錄中，在交易紀錄保存逐檔 SHA-256 `owned_files` 指紋，卸載時若發現檔案遭竄改則拒絕操作，同時保留 `mods/` 下的其他同級模組目錄，並檢查與 `pck` 直接改包模組及 MPML 載入器標記之間的互斥衝突。啟用 `"autoLoader": true` 時，`pck_loader.rs`（`ensure_loader_installed` / `restore_managed_loader`）會在 `_mpm_loader` 下備份原版 PCK，修補 `res://project.binary` 並內嵌 `assets/mpm_bootstrap.gd`（狀態寫入 `Machine Party.pck.modloader.json`），並在卸載最後一個託管載入器模組時自動還原原版 PCK。

日後新增模組只要符合既有適配器種類，只需在 `catalog/mods.json` 中補上宣告式 `adapter` 設定並通過實機驗收即可，無需修改程式碼；新增適配器種類則需要 Rust 實作與新的 ADR。

```json
"adapter": {
  "kind": "upstream-cli",
  "platforms": ["windows"],
  "target": "pckDir",
  "touches": ["Machine Party.pck", "overtime_restore.dat"],
  "exclusive": "pck",
  "baseline": {"file": "Machine Party.pck", "size": 634798100, "sha256": "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"},
  "verifyFiles": "SHA256SUMS.txt",
  "run": {"interpreter": "exe", "program": "overtime_install.exe", "common": ["--game", "{gameDir}", "--lang", "en", "--no-pause"]},
  "actions": {"preflight": ["--verify-package"], "status": ["--status"], "install": [], "uninstall": ["--uninstall"]},
  "status": {"installed": "^State:\\s+Overtime overtime-1\\.7 installed", "vanilla": "^State:\\s+vanilla", "older": "^State:\\s+Overtime .* installed \\(this program"},
  "forbiddenArgs": ["--force"]
}
```

### 2. 分級且由 App 託管的備份策略

備份不能只交給上游工具，因為各模組的備份行為不同，部分上游甚至完全不留備份。

- 寫入前始終計算並記錄 `Machine Party.pck` 的檔案大小與 SHA-256。
- **支援差量還原的安裝器**（如 Overtime 會產生含原始長度、基線 SHA-256 及新舊索引的 `overtime_restore.dat`）：交易引擎將該還原紀錄與已校驗的卸載程式（`overtime_install.exe`）複製到 App 按副本保存的儲存目錄中，確保即使暫存區或遊戲目錄內的紀錄遺失也能離線卸載。
- **無差量還原的安裝器或後備路徑**（`"upstreamUninstall": false`，如 Binary1936 `install.py`）：修改前由交易引擎在按副本儲存中保存已校驗的完整 `Machine Party.pck` 備份（約 605 MB），卸載時直接還原。
- **偵測到的手動安裝**：若 `status` 回報磁碟已有安裝但 `installations.json` 沒有紀錄，在介面明確提示；僅當還原紀錄的基線 SHA-256 與已知原版 PCK 指紋（v2.1.2 為 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）一致時，才允許接管或卸載。來歷不明的備份絕不當作原版。

### 3. Windows 目標平台與 macOS 三層模擬驗證

Steam 上的 Machine Party（App ID 4108000）僅支援 Windows，不支援在 macOS 遊玩。macOS 桌面端用於目錄瀏覽、校驗與開發期模擬，正式介面不開放常規 Windows 模組安裝。

在 Windows 實機驗收（P2）前，macOS 開發與測試分為三層：

- **L1（單元與契約測試）**：`FakeRunner` + 合成 Godot PCK 產生器（僅數 KB，含合法 `GDPC` 魔數、檔頭與 `res://` 索引）+ 故障注入（下載中斷、寫入中途崩潰、Steam 更新替換 PCK、未知第三方修改、遊戲進程佔用）。
- **L2（真實子進程測試）**：`ProcessRunner` 啟動跨平台假 CLI 腳本（重現 Overtime 參數與 `State:` 輸出協議），並用真實跨平台上游腳本（`python3` 執行 Binary1936 `install.py`）對合成 PCK 進行實測。
- **L3（本機原版 PCK + Mono 驗證）**：僅限本機開發驗證，不提交遊戲檔案；使用從 Windows 複製的未提交原版 `Machine Party.pck`（v2.1.2，`634,798,100` 位元組，SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）與 Mono 執行真正的 `overtime_install.exe`，跑通 `--verify-package`、`--status`、安裝、安裝後 `--status`、`--uninstall` 與原版 SHA-256 逐位元組還原校驗。

## 替代方案

- **線上目錄隨附可執行適配腳本**：否決，存在遠端程式碼執行風險並違反 [ADR-005](ADR-005-install-transactions.md)。
- **在 Rust 中重寫所有 PCK 補丁器**：否決，重複上游邏輯且一旦上游格式變動就會失效。
- **拆出獨立的 `catalog/adapters/*.json` 檔案**：否決，現階段會過早拆分單一資料來源（[ADR-002](ADR-002-catalog-source.md)）；若日後按模組拆分目錄檔案再一併產生。
- **所有模組一律複製 605 MB 整包備份**：否決其作為 Overtime 的首選方案，因經過校驗的差量還原僅佔數 KB 且能做全包 SHA-256 核驗；但對無差量紀錄的安裝器（如 Binary1936）仍必須使用整包備份。

## 相容性

- `catalog/mods.json` 維持 `schema: 1`；新增的可選 `adapter` 欄位為增量擴充，舊版客戶端會直接忽略。
- `installations.json`、`game-path.json`、既有 Tauri 命令名稱及桌面更新設定（[ADR-003](ADR-003-desktop-updates.md)）均維持不變。

## 所需證據

macOS 上的 L1、L2、L3 單元與整合測試已涵蓋全部四類模組適配器（`loader-files`、`powershell`、`bundled-python`，以及透過 Mono 在未提交的 Windows v2.1.2 原版 `Machine Party.pck` 上完成 Overtime v1.7 實測與逐位元組還原驗證），同時也在原版 v2.1.2 PCK 上本機驗證了 `binary1936-8p/install.py` 與 `broadcast-8p-freecam` 的覆蓋邏輯。仍須完成 Windows Steam v2.1.2 實機驗收：在 Windows 上實測安裝各模組（包含 PowerShell `patcher.ps1`、內建 Windows `python.exe` 搭配 `install.py`、以及 MPML 搭配 `MachineParty+`），從 Steam 啟動運行後斷網單次卸載並核驗遊戲目錄完整還原，詳見[產品需求](../requirements.md)與[開發指南](../development/README.md)。
