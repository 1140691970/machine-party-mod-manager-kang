# ADR-004：按語言組織文件

[English](../../en/architecture/ADR-004-language-documentation.md) · [简体中文](../../zh-CN/architecture/ADR-004-language-documentation.md) · **繁體中文**

日期：2026-11-18。狀態：已接受。

## 問題

文件只有繁體中文，而 App 預設為簡體中文；部分檔案（`ui-design.md`）不斷追加「取代上文」的段落，而非重寫。中文地區以外的貢獻者沒有入口。

## 決策

- 根目錄的 `README.md`、`AGENTS.md`、`CONTRIBUTING.md`、`SECURITY.md`、`SUPPORT.md`、`CHANGELOG.md`、`THIRD_PARTY_NOTICES.md` 以英文為準，GitHub 與打包都需要它們位於根目錄。
- 指南放在 `docs/en`、`docs/zh-CN`、`docs/zh-TW`，三者相對路徑完全一致。翻譯後的專案首頁放在 `docs/readme`，共用圖片放在 `docs/images`。
- 每個翻譯頁面開頭都有語言切換。文件描述目前狀態；過時內容直接重寫，不追加。
- `tests/contracts/documentation.test.mjs` 檢查路徑一致、語言切換與相對連結。

## 替代方案

只保留一種語言維護成本較低，但會排除部分讀者。只翻譯 README 則指南仍不可讀。

## 相容性

`docs/architecture.md` 等舊路徑已刪除，倉庫內連結已更新。模組投稿的 Issue 表單暫時維持繁體中文。

## 證據

文件契約測試通過。
