# ADR-016 · 基於 R2 圖床的選用模組封面規範

[English](../../en/architecture/ADR-016-r2-mod-covers.md) · [简体中文](../../zh-CN/architecture/ADR-016-r2-mod-covers.md) · **繁體中文**

## 問題

先前桌面端管理器直接從打包進用戶端前端的 `apps/desktop/ui/images/<image>.png` 讀取卡片封面，帶來三個問題：

1. 新增模組或更換封面圖必須重新發布桌面用戶端，即使目錄與模組壓縮包已透過 Cloudflare R2 與 `services/catalog-worker` 動態更新。
2. 內建高解析度 PNG 截圖使桌面安裝包膨脹約 5.8 MB，且會隨模組數量線性成長。
3. 封面圖缺乏明確的目錄與模組開發規範。

## 決策

1. **移除內建模組封面圖**：刪除 `apps/desktop/ui/images/` 中所有模組封面檔案，僅保留應用程式自身圖示（`logo.svg`）。契約測試強制禁止再將模組封面內建至 `apps/desktop/ui/images/`。
2. **選用 `cover` 規範**：模組封面為選填項目。若提供封面，原始圖檔統一存放於 `catalog/covers/<id>.<ext>`（支援 `.png`、`.webp`、`.jpg`，建議 `1280×720` 16:9，上限 4 MiB），並於 `catalog/mods.json` 宣告：
   ```json
   "cover": {
     "filename": "spike-ring.png",
     "contentType": "image/png",
     "size": 832988,
     "sha256": "<64位十六進位>"
   }
   ```
   省略 `cover` 完全合法，介面會自動渲染卡片標題佔位（`cover-title`）。
3. **內容尋址 R2 儲存與 Worker 分發**：
   - CI（`.github/workflows/catalog-worker.yml`）校驗每個宣告封面的本機大小與 SHA-256，並以不可變物件鍵 `covers/sha256/<sha256>.<ext>` 上傳至 R2。
   - `services/update-worker` 閘道將 `/v1/covers/*` 轉發至 `services/catalog-worker`。
   - `services/catalog-worker` 僅對外提供已發布目錄中宣告的封面 `GET|HEAD /v1/covers/<modId>/<sha256>.<ext>`，校驗 R2 物件大小，回傳 `Cache-Control: public, max-age=86400, s-maxage=604800, immutable`、`X-Content-Type-Options: nosniff` 並啟用邊緣快取。
4. **桌面 UI 與 CSP**：
   - `tauri.conf.json` 在 `img-src` 放行 `https://machineparty.ailaogong.men`。
   - `online-catalog.js` 校驗 `cover` 中繼資料並產生 `coverUrl(mod)`；`catalog-view.js` 延遲載入封面圖，於離線或載入失敗時平滑回退至標題佔位。

## 備選方案

- **繼續內建於桌面前端**：離線最簡單，但無法隨線上目錄動態更新，且持續膨脹安裝包體積。
- **公開 R2 儲存貯體或 GitHub raw 直連**：GitHub 直連在中國大陸不可靠；公開 R2 儲存貯體會繞過目錄白名單與大小／類型校驗。

## 相容性

- 舊版桌面用戶端（v0.2.3 及更早）會忽略未知欄位 `cover` 並允許省略 `image`，在自動更新至 v0.2.4 前平滑顯示標題佔位。
- `online-catalog.js` 仍容忍舊本機快取中的 `image` 欄位，確保升級過程不中斷。

## 驗證證據

- `tests/contracts/catalog.test.mjs` 驗證 `apps/desktop/ui/images/` 僅含 `logo.svg`、目錄不再使用舊 `image` 欄位，且所有 `cover` 與 `catalog/covers/<filename>` 的大小、SHA-256、類型與 4 MiB 上限完全相符。
- `tests/contracts/online-catalog.test.mjs` 驗證閘道轉發、Worker R2 鍵解析、邊緣快取、回應標頭、錯誤碼及非法 `cover` 拒絕邏輯。
- `.github/workflows/catalog-worker.yml` 於發布時自動上傳封面至 R2 並驗證線上每條 `HEAD /v1/covers/<modId>/<sha256>.<ext>`。
