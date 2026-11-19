# ADR-011 · 安裝前統一準備 MPML

[English](../../en/architecture/ADR-011-prepare-mpml.md) · [简体中文](../../zh-CN/architecture/ADR-011-prepare-mpml.md) · **繁體中文**

一鍵安裝先以目錄大小與 SHA-256 核對作者發行 ZIP，再由 Rust 在暫存區準備 MPML 目錄。Overtime 讀取 CLI 包中的 payload 清單，保留上游的載入時序、版本與原版腳本指紋檢查。Broadcast 和 Binary1936 讀取資源樹。MachineParty+、滾筒嘉年華與房間機器人已採載入器格式。

Binary1936 和 Broadcast 共用 `apps/desktop/src-tauri/` 下的資源目錄轉換器 `src/installer/prepare.rs` 和 MPML 入口範本 `assets/recipes/resource_tree.gd`。轉換 Binary1936 v1.5 時，管理器將 40 個腳本、16 個場景及其映射打入 `overlay.zip`，並用目錄中的模組 ID 產生 `main.gd`。

安裝交易記錄來源指紋、轉換規則版本與已安裝檔案指紋。三款八人玩法屬同一互斥群組，切換時可保留其他載入器模組。另行分發轉換包需要維護第二份發行產物，執行各上游安裝器則需維護多套備份與還原程序。

舊版客戶端仍可使用相容目錄與下載網址。既有 Overtime MPML 安裝可繼續使用。舊式受管 PCK 補丁可在模組詳情選擇「切換為載入器安裝」，先驗證新包，再還原已記錄的副本並安裝。手動安裝的 mods/broadcast-8p 須先移出遊戲目錄。檔案出現未知變更時，還原會停止。

安裝、升級或移除內建載入器時，管理器先在遊戲所在磁碟準備並驗證暫存 PCK，再替換遊戲檔案。除備份外，遊戲磁碟還需預留一份 PCK 的空間（v2.1.2 約 606 MiB）。升級載入器時會記錄新舊兩份指紋，以便中斷後辨識實際生效的版本。

解除安裝最後一個受管模組時，管理器會先驗證還原後的 PCK，再刪除模組檔案，並記錄還原指紋以便中斷後繼續清理。如果還有其他模組目錄或目錄連結，管理器會保留共用載入器。

發行包測試逐檔比對 Overtime 的 70 個編譯腳本，以及 Broadcast 的 65 個、Binary1936 的 56 個資源。Steam 多人連線仍待實機驗收。
