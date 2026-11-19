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
| `mods/<id>/` | 透過 `scripts/pack-mod.mjs` 打包為 `.zip` 並經 R2 與目錄 Worker 分發的自研 GDScript 模組 |
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

## 在 macOS 上模擬模組安裝

Steam 上的 Machine Party 僅支援 Windows，不考慮在 macOS 上遊玩。在進入 Windows 實機驗收（P2）之前，macOS 開發期透過三層模擬驗證安裝邏輯（[ADR-007](../architecture/ADR-007-mod-adapters.md)）：

- **L1（單元與契約測試）**：`FakeRunner` 搭配合成的 Godot PCK（僅數 KB，含合法 `GDPC` 檔頭與 `res://` 索引）及故障注入，驗證下載中斷、寫入崩潰、Steam 更新、未知修改與檔案佔用。
- **L2（真實子進程測試）**：`ProcessRunner` 執行重現 Overtime 參數與 `State:` 輸出協議的跨平台假 CLI 腳本，並在 `python3` 下使用跨平台上游腳本（如 `install.py`）操作合成 PCK。
- **L3（本機原版 PCK + Mono）**：僅限本機驗證，使用 Mono 執行 `overtime_install.exe` 操作未提交的 Windows 原版 `Machine Party.pck`（v2.1.2，SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`）。切勿將遊戲檔案（`Machine Party.pck`）提交到儲存庫。

## 常見改動

- **新增或修改模組**：只改 `catalog/mods.json`。三種語言的 `name`、`summary`、`detail` 都要填寫，維持 `id` 與 `repo` 不變；若設定了 `image`，在 `apps/desktop/ui/images/{image}.png` 加入封面。收錄流程見[模組目錄指南](../catalog/mods.md)。
- **新增儲存庫自研模組**：依循[自研模組開發、測試、接入與打包規範](mod-development.md)（在 `mods/<id>/` 提供 `README.md`、`mod.json` 與 GDScript 腳本），執行 `node scripts/pack-mod.mjs <id>`（自動排除 `project.godot`、`*_scene.tscn`、`*.sh` 與 `*.md`），依與其他模組完全相同的格式在 `catalog/mods.json` 新增 `package` 與 `adapter.kind: "loader-files"`（`autoLoader: true`）條目，並執行 Godot 檢查、`npm run test:rust` 與 `npm test`（[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **新增介面文案**：在 `apps/desktop/ui/languages.js` 增加一個鍵，同時填寫簡體中文、繁體中文與英文。
- **新增命令**：在不依賴 Tauri 的模組實作邏輯並撰寫單元測試，在 `commands.rs` 公開，在 `main.rs` 註冊，且只從 `bridge.js` 呼叫。
- **調整架構**：在 `docs/en`、`docs/zh-CN`、`docs/zh-TW` 各新增一份 ADR，並更新現行架構頁面。

發布流程見[發布](releasing.md)。
