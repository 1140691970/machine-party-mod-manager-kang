# 正式目錄發布與中國大陸連線驗收

[English](../../en/catalog/delivery.md) · [简体中文](../../zh-CN/catalog/delivery.md) · **繁體中文**

**線上模組目錄**　客戶端啟動時讀取 Worker 快照，快取通過驗證的資料供離線瀏覽。每個版本透過 Release 資產 ID 對應 R2 鍵 `packages/sha256/<sha256>.zip`。僅開放允許鏡像的套件。 [ADR-006](../architecture/ADR-006-online-catalog.md)

## 玩家取得列表的路徑

桌面端向專案 Worker 請求 `GET /v1/catalog.json?inventory=id&prepare=1`。Worker 從 R2 讀取已核准的目錄修訂，舊版用戶端可取得相容快照。搜尋、排序與語言切換均在本機完成。

| 項目 | 目錄行為 |
| --- | --- |
| 快照識別 | 包含格式版本、目錄修訂號與模組清單。修訂號識別整份快照，模組版本沿用上游標籤。 |
| 模組資料 | 穩定 ID、固定收錄序號、作者來源、三語簡介與搜尋別名、封面及已核准的版本資料。安裝版本需有相容條件、固定資產、SHA-256 與客戶端支援的安裝方式。 |
| HTTP 回應 | Worker 為各個目錄變體提供 ETag。請求的 `If-None-Match` 相符時回傳 304。 |
| 客戶端落盤 | 桌面端檢查目錄格式，並驗證簽章以授權線上套件。簽章文件會快取供離線驗證，另存一份瀏覽副本。 |

啟動時顯示有效快取並在背景重新整理。單次請求逾時為 15 秒。逾時、連線失敗或伺服器錯誤（5xx）時自動重試一次。重新整理失敗時，玩家仍可瀏覽快取條目並手動重試。「已安裝」頁也可透過本機紀錄離線解除安裝。

## 大陸玩家下載第三方模組

用戶端透過 `GET /v1/downloads/{modId}/{version}/{assetId}` 取得已核准的套件。Worker 核對目錄映射及鏡像授權，再從邊緣快取或私有 R2 回傳檔案。部署時會在寫入新上游套件前核對大小與 SHA-256，用戶端也會在安裝前校驗下載的套件。

驗收時封鎖 GitHub，下載完整套件及所需載入器，核對雜湊，並測試斷線及下架後的行為。若用戶端支援續傳，還須核對 Content-Range、條件續傳及重組後檔案的雜湊。

上線前需逐包核清授權。Overtime 的 MIT 範圍只涵蓋作者原創部分，補丁中保留遊戲腳本上下文；MachineParty+ 的 MPML 載入器須另測、另行確認可分發範圍。授權未明時僅提供作者入口或經驗收的直連。[Overtime 授權](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ 安裝需求](https://github.com/Ghostx10742/MachineParty-Plus#installation)

### 套件準備與舊版相容性

一鍵安裝先以目錄大小與 SHA-256 核對作者發行 ZIP，再由 Rust 在暫存區準備 MPML 目錄。Overtime 讀取 CLI 包中的 payload 清單，保留上游的載入時序、版本與原版腳本指紋檢查。Broadcast 和 Binary1936 讀取資源樹。MachineParty+、滾筒嘉年華與房間機器人已採載入器格式。 `?inventory=id&prepare=1` · `/v1/downloads/overtime/v1.7/594522625`.

舊版客戶端仍可使用相容目錄與下載網址。既有 Overtime MPML 安裝可繼續使用。舊式受管 PCK 補丁可在模組詳情選擇「切換為載入器安裝」，先驗證新包，再還原已記錄的副本並安裝。手動安裝的 mods/broadcast-8p 須先移出遊戲目錄。檔案出現未知變更時，還原會停止。

## 誰能發布

1. 貢獻者透過 Issue 或 PR 推薦模組。維護者審核發行檔並更新 `catalog/mods.json`。目錄 Worker 位於 `services/catalog-worker/`。詳見[收錄操作手冊](mods.md)。
2. 由倉庫擁有者手動選擇已合併的 main 提交發布。部署工作使用 GitHub 的 `production` environment，限制 main 並指定 JamesGZM 為必要審核人；單人維護時允許其批准自己的部署。審核畫面應能核對提交 SHA、修訂號與變更清單。PR 驗證工作無部署憑證。
3. Cloudflare 部署 Token 存為環境 Secret `CLOUDFLARE_API_TOKEN`，帳號 ID 存為環境變數 `CLOUDFLARE_ACCOUNT_ID`。只授予目標帳號部署所需權限。App 只讀公開端點。[GitHub 部署環境](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [Cloudflare Actions 部署](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
4. 部署後從正式網域讀回 JSON，比對修訂號與快照雜湊，再用上一版客戶端驗證同步。記錄提交、雜湊、部署版本及結果。異常時由擁有者批准重新發布上一份良好資料，配新修訂號並清快取；確認一般客戶端能從壞版恢復。回滾前核對已撤回的模組，避免意外重新開放下載。

## 大陸可達性如何驗收

一般 Worker 加自訂網域提供穩定的服務名稱，可在相同網址調整部署。跨境連線仍受所在地、電信商與時段影響。Cloudflare China Network 屬 Enterprise 客戶另購服務，產品支援範圍需另查；本案首版以一般 Worker 實測，尚未採購中國境內服務。[Cloudflare 中國網路說明](https://developers.cloudflare.com/china-network/) · [可用產品清單](https://developers.cloudflare.com/china-network/reference/available-products/)

| 上線前測項 | 建議首輪通過條件 |
| --- | --- |
| 真實網路冷啟動 | 在中國電信、中國聯通、中國移動的一般用戶網路測正式網域，涵蓋至少兩個省市及日間、晚間尖峰，關閉 VPN／代理。每條線路每個時段冷啟動 10 次。建議每組至少 9 次在 5 秒內顯示正確目錄，其餘在一次自動重試內成功。逐組判定。 |
| 不依賴 GitHub | 封鎖測試機到 GitHub、raw 與其資產網域的連線，清 App 快取後仍可從 Worker 取得最新修訂，搜尋與頁面可用。另測圖片失敗時的標題封面。 |
| 版本與故障 | 測 200、304、下架、回滾、DNS 失敗、TLS 失敗、逾時與損壞 JSON；分別從首次安裝及已有快取開始。確認錯誤不覆寫有效快取，恢復連線後可同步。 |
| 端到端下載 | 每個對大陸開放安裝的版本，用以上三網實際下載完整資產並核對雜湊，另測中斷重試。分開記錄目錄成功與下載成功。 |

記錄日期、城市、電信商、時段、客戶端版本、修訂號、成功次數、首屏耗時及故障階段（DNS、TLS、HTTP、解析或資產下載）。這些是發布方的實測資料。建議正式上線後在相同線路定期複測，變更網域或路由後重跑。測試門檻用於首版驗收，持續服務水準需要長期量測。

**未達標時的決策。** 先定位失敗階段，再評估由獨立線路提供相同已批准快照的備援入口；由客戶端預置可用入口，才能在主站完全不可達時切換。若需要中國境內交付，再核對供應商支援、資格與成本。備援須通過相同的冷啟動、更新、撤回與回滾驗收，才對外宣告覆蓋範圍。
