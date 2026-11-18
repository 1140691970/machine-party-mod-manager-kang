# ADR-001：專案邊界，保留 Tauri 與原生 JS

[English](../../en/architecture/ADR-001-project-boundaries.md) · [简体中文](../../zh-CN/architecture/ADR-001-project-boundaries.md) · **繁體中文**

日期：2026-11-18。狀態：已接受。

## 問題

原型把 Cargo 專案、前端與 Worker 都放在倉庫根目錄。所有 Tauri 命令、Steam 偵測、偏好與安裝紀錄程式碼都在 `main.rs`；模組清單寫死在 `ui/app.js`，Rust 又另寫一份白名單；介面在任意位置呼叫 `window.__TAURI__`；CSS 是手工壓縮的。沒有每次提交都執行的檢查，邊界無法約束。

## 決策

- 保留 Tauri 2、Rust 與不使用打包工具的原生 ES 模組。按歸屬劃分目錄：`apps/desktop/src-tauri`、`apps/desktop/ui`、`services/update-worker`、`catalog`、`scripts`、`tests`、`docs`。
- `main.rs` 只負責組裝；`commands.rs` 驗證 IPC 並解析平台路徑；`game`、`inventory`、`preferences`、`catalog` 只接收一般路徑，不依賴 Tauri，方便單元測試。
- `ui/bridge.js` 是唯一接觸 Tauri 的 JavaScript。純函式模組（`catalog.js`、`versions.js`）在 Node 下測試。
- `scripts/check_architecture.mjs` 與 Source checks 工作流程執行這些規則，並執行 `cargo fmt`、`clippy` 與測試。
- 給貢獻者與程式助手的規則寫在 `AGENTS.md`。

## 參考

目錄組織參考同一維護者的 [miband-agent-buddy](https://github.com/JamesGZM/miband-agent-buddy)（apps/services 拆分、`AGENTS.md`、分語言 ADR、邊界檢查腳本）。它的多執行環境結構、共用協定套件與生成式建置在本專案不需要。

## 替代方案

維持平鋪結構、只拆分 `main.rs` 成本較低，但隨服務增加，發布腳本與測試會持續耦合根目錄路徑。前端框架或打包工具對之後的重新設計有幫助，但屬於技術棧變更，應在那一輪再決定。

## 相容性

命令名稱、`installations.json`、`game-path.json`、更新器 identifier、公鑰與穩定端點均未改變。發布工作流程改在 `apps/desktop/src-tauri` 中建置，並把產物寫到根目錄 `dist/`。本機建置輸出位於 `apps/desktop/src-tauri/target`。

## 證據

`cargo test`、`clippy -D warnings`、`npm test`、`npm run check:architecture` 均通過。在瀏覽器並排載入新舊介面，截圖、搜尋結果、詳情彈窗、設定頁與已安裝頁一致。macOS 桌面建置可以啟動。發布工作流程尚未以新路徑實際執行。
