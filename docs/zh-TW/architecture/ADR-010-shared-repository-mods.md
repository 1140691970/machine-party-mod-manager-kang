# ADR-010 · 同倉庫模組的獨立安裝紀錄

[English](../../en/architecture/ADR-010-shared-repository-mods.md) · [简体中文](../../zh-CN/architecture/ADR-010-shared-repository-mods.md) · **繁體中文**

滾筒嘉年華和房間機器人共用一個 GitHub 倉庫，單靠倉庫名稱無法區分兩個安裝版本。新條目可用 `inventoryById: true` 選用目錄 ID 作為安裝鍵，作者連結仍使用 `repo`。既有紀錄保留原鍵。全面遷移到 ID 需要改寫玩家紀錄。完整線上目錄在原端點使用 `?inventory=id`，舊網址僅回傳可用倉庫鍵區分的條目。目錄測試涵蓋共存、舊版回應與快取標記。
