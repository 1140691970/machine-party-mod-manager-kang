# 開發指南

[English](../../en/development/README.md) · [简体中文](../../zh-CN/development/README.md) · **繁體中文**

## 環境準備

- Rust stable 1.88 或更新版本（edition 2024，使用 let-chains），並安裝 `rustfmt` 與 `clippy`。
- Node.js 22 或更新版本。不安裝任何 npm 相依套件，Node 只用於執行測試與腳本。
- Windows：Microsoft C++ Build Tools 與 WebView2（Windows 11 已預裝）。macOS：Xcode Command Line Tools。
- 打包安裝程式另會使用 `npx @tauri-apps/cli@2.12.5`，與發布工作流程一致。

## 目錄結構

| 路徑 | 內容 |
| --- | --- |
| `apps/desktop/src-tauri` | Rust 專案、`tauri.conf.json`、capabilities 與圖示 |
| `apps/desktop/ui` | 由 WebView 直接載入的 HTML、CSS 與 ES 模組 |
| `catalog/mods.json` | 隨 App 發布的模組目錄 |
| `services/update-worker` | 負責應用程式更新的 Cloudflare Worker |
| `scripts` | 發布、部署、升級驗收與 `check_architecture.mjs` |
| `tests` | Node 測試：`ui`、`contracts`、`architecture` |

各部分職責見[現行架構](../architecture/README.md)，所有改動都需遵守的規則見 [AGENTS.md](../../../AGENTS.md)。

## 執行

```sh
npm run dev
```

此命令對桌面端執行 `cargo run`。Steam 偵測與遊戲目錄操作在各平台皆可執行，安裝功能以 Windows 為目標。

不經 Tauri、在瀏覽器預覽介面時，從倉庫根目錄啟動靜態伺服器並開啟介面頁面，僅桌面端可用的操作會隱藏。

```sh
python3 -m http.server 8000
# 開啟 http://127.0.0.1:8000/apps/desktop/ui/index.html
```

## 驗證

先執行最小相關檢查，送出 PR 前執行全部：

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

**Source checks** 工作流程在每次 push 與 PR 時執行相同命令。介面改動需附截圖。建置成功不代表 Windows 安裝、遊戲還原或更新已驗證，請說明實際做過的實機測試。

## 常見改動

- **新增或修改模組**：只改 `catalog/mods.json`。三種語言的 `name`、`summary`、`detail` 都要填寫，維持 `id` 與 `repo` 不變；若設定了 `image`，在 `apps/desktop/ui/images/{image}.png` 加入封面。收錄流程見[模組目錄指南](../catalog/mods.md)。
- **新增介面文案**：在 `apps/desktop/ui/languages.js` 增加一個鍵，同時填寫簡體中文、繁體中文與英文。
- **新增命令**：在不依賴 Tauri 的模組實作邏輯並撰寫單元測試，在 `commands.rs` 公開，在 `main.rs` 註冊，且只從 `bridge.js` 呼叫。
- **調整架構**：在 `docs/en`、`docs/zh-CN`、`docs/zh-TW` 各新增一份 ADR，並更新現行架構頁面。

發布流程見[發布](releasing.md)。
