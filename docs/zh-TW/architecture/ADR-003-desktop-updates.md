# ADR-003：簽章的桌面更新

[English](../../en/architecture/ADR-003-desktop-updates.md) · [简体中文](../../zh-CN/architecture/ADR-003-desktop-updates.md) · **繁體中文**

日期：2026-11-18。狀態：已接受；記錄 v0.1.1 已上線的鏈路。

## 問題

玩家需要在不連 GitHub 的情況下收到管理器更新（包括中國大陸玩家），且更新絕不能安裝未簽章或非預期的程式。

## 決策

- Windows x64 與 Apple Silicon 客戶端使用 `tauri-plugin-updater`，開啟 `requireSignedVersion` 並內建公鑰，輪詢 `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json`。
- `services/update-worker` 唯讀，只從私有 R2 bucket 提供穩定清單與 `app-downloads/{version}/{setup.exe|MachineParty-aarch64.app.tar.gz|manifest.json}`。按版本存放的物件不可變。
- **Release desktop app** 工作流程建置雙平台，在 `production` 環境簽章，暫存版本物件，安裝舊版 Windows 客戶端並經 Worker 升級，發布 GitHub Release，最後才切換穩定清單。

維護者操作步驟見[發布流程](../development/releasing.md)。

## 替代方案

直接以 GitHub Releases 作為更新端點，許多中國大陸玩家無法連線。在端到端驗收前就更新穩定清單，可能發出壞版本。

## 相容性

已安裝的客戶端信任目前的公鑰、identifier 與端點。改動任何一項都會讓現有安裝收不到更新，因此由 `tests/contracts/release-config.test.mjs` 固定。簽章私鑰必須存於離線備份。

## 證據

發布執行 44264743654 發布了含 darwin-aarch64 與 windows-x86_64 的 v0.1.1。一台 Apple Silicon Mac 經介面從 0.1.0 升級到 0.1.1，執行檔與 GitHub 產物逐位元組一致；Windows 升級驗收在 CI 中通過。
