# ADR-011 · 安裝前統一準備 MPML

[English](../../en/architecture/ADR-011-prepare-mpml.md) · [简体中文](../../zh-CN/architecture/ADR-011-prepare-mpml.md) · **繁體中文**

一鍵安裝先以目錄大小與 SHA-256 核對作者發行 ZIP，再由 Rust 在暫存區準備 MPML 目錄。Overtime 讀取 CLI 包中的 payload 清單，保留上游的載入時序、版本與原版腳本指紋檢查。Broadcast 和 Binary1936 讀取資源樹。MachineParty+、滾筒嘉年華與房間機器人已採載入器格式。

安裝交易記錄來源指紋、轉換規則版本與已安裝檔案指紋。三款八人玩法屬同一互斥群組，切換時可保留其他載入器模組。另行分發轉換包需要維護第二份發行產物，執行各上游安裝器則需維護多套備份與還原程序。

舊版客戶端仍可使用相容目錄與下載網址。既有 Overtime MPML 安裝可繼續使用。舊式受管 PCK 補丁可在模組詳情選擇「切換為載入器安裝」，先驗證新包，再還原已記錄的副本並安裝。手動安裝的 mods/broadcast-8p 須先移出遊戲目錄。檔案出現未知變更時，還原會停止。

發行包測試逐檔比對 Overtime 的 70 個編譯腳本，以及 Broadcast 的 65 個、Binary1936 的 56 個資源。Steam 多人連線仍待實機驗收。
