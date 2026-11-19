# ADR-006 · 線上模組目錄

[English](../../en/architecture/ADR-006-online-catalog.md) · [简体中文](../../zh-CN/architecture/ADR-006-online-catalog.md) · **繁體中文**

目錄需要獨立於桌面版本更新。

客戶端啟動時讀取 Worker 快照，快取通過驗證的資料供離線瀏覽。每個版本透過 Release 資產 ID 對應 R2 鍵 `packages/sha256/<sha256>.zip`。僅開放允許鏡像的套件。 Worker 從 R2 的 `catalog/revisions/<revision>.json` 讀取已發布目錄。部署流程先讀回核對，再切換 Worker 的目錄修訂號。

隨包提供列表需要為每次目錄更新發布桌面版本。直接列出儲存桶會暴露暫存檔案。

既有安裝紀錄、IPC 和簽章更新沿用原格式。 線上目錄契約測試涵蓋刷新、快取、套件查找與下載權限。

公開入口透過 `CATALOG` 綁定將目錄與下載請求交給 `machine-party-catalog`。新環境應先部署目錄服務，再綁定公開入口。
