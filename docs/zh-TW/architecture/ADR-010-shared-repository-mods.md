# ADR-010 · 同倉庫模組的獨立安裝紀錄

[English](../../en/architecture/ADR-010-shared-repository-mods.md) · [简体中文](../../zh-CN/architecture/ADR-010-shared-repository-mods.md) · **繁體中文**

滾筒嘉年華和房間機器人共用一個 GitHub 倉庫，單靠倉庫名稱無法區分兩個安裝版本。新條目可用 `inventoryById: true` 選用目錄 ID 作為安裝鍵，作者連結仍使用 `repo`。全面遷移到 ID 需要改寫玩家紀錄。完整線上目錄在原端點使用 `?inventory=id`，舊網址僅回傳可用倉庫鍵區分的條目。目錄測試涵蓋共存、舊版回應與快取標記。

滾筒嘉年華的本機安裝紀錄改用目錄 ID。內建目錄的 `legacyInventoryRepos` 由新到舊列出測試版 5 和 6–8 使用過的倉庫鍵。讀取一份遊戲副本時，管理器將這些鍵合併到同一個 ID，優先採用已有的 ID 紀錄，掃描驗證成功後以交易中的版本為準。卸載會逐檔核對，並移除該副本的相關紀錄。舊客戶端仍可按 Worker 原有的 `inventoryById` 欄位讀取目錄。同倉庫後續新增的模組各自指定唯一的目錄 ID，並設定 `inventoryById: true`。
