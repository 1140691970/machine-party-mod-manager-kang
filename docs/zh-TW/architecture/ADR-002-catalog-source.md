# ADR-002：模組目錄的唯一來源

[English](../../en/architecture/ADR-002-catalog-source.md) · [简体中文](../../zh-CN/architecture/ADR-002-catalog-source.md) · **繁體中文**

日期：2026-11-18。狀態：已接受。

## 問題

模組條目分散在三處：`ui/app.js` 的陣列、`ui/languages.js` 的簡介與詳情、Rust 中用於開啟作者頁的倉庫白名單。新增一個模組要改三處，內容容易不一致。

## 決策

`catalog/mods.json`（schema 1）是唯一來源。頂層記錄管理器自身的 `repo`，每個模組條目包含穩定的 `id`、固定的 `order`、`repo`、選填的 `image`、`version`、`verified`、`firstParty`、`supportedGameVersions`、`windowsPreview`，以及 `zh-CN`、`zh-TW`、`en` 三語的 `name`、`summary`、`detail`、搜尋用的 `aliases` 和可選的宣告式 `adapter` 設定。

- Rust 在編譯期內嵌該檔案。`catalog` 命令把它交給介面，`open_project` 只接受目錄頂層的管理器 `repo` 或 `mods` 中列出的作者倉庫（其中 `firstParty: true` 條目在 `catalog.rs` 中對應到 `<app_repo>/tree/main/mods/<id>`，並透過 `scripts/pack-mod.mjs` 打包為 R2 壓縮檔）。
- 介面經 `bridge.js` 載入並按 `order` 排序。在一般瀏覽器預覽時從倉庫直接讀取。
- `tests/contracts/catalog.test.mjs` 檢查 ID、序號與倉庫唯一、頂層 `repo`、自研模組清單/README/ZIP 契約、Windows 測試版中繼資料與 `adapter` 設定、翻譯完整以及封面圖片隨介面發布；Rust 測試檢查解析與白名單。

## 替代方案

[目錄交付方案](../catalog/delivery.md)規劃的每個模組一個 JSON（`catalog/mods/*.json`）較適合投稿 PR，之後可透過生成相同快照引入；目前四個條目還不值得這樣做。線上取得目錄也屬於該方案，屆時本 schema 作為離線備援。

## 相容性

顯示文案、順序與搜尋行為不變。安裝紀錄以 `owner/repo` 為鍵，因此既有條目的 `repo` 不可修改。

## 證據

契約測試與 Rust 測試通過。瀏覽器對比顯示，按名稱、別名與其他語言簡介搜尋的結果完全一致。
