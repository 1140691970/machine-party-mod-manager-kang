# 正式目錄發布與中國大陸連線驗收

**狀態**　首版設計。現有客戶端仍使用隨包候選資料。正式網域、Worker、發布工作流與三網驗收結果均待落地。

## 玩家取得列表的路徑

Windows App 經 HTTPS 向自有網域的 Worker 請求 `GET /v1/catalog.json`。網域在部署時決定。首版將已批准的完整 JSON 快照隨 Worker 一次部署，讀取列表時無須回源 GitHub，也無須資料庫、玩家帳號或 API Token。搜尋、排序與三語切換均在本機完成。封面讀取失敗就顯示標題封面，避免圖片拖慢目錄。作者專案連結只在玩家主動點擊時開啟。

| 契約 | 首版設計 |
| --- | --- |
| 快照識別 | 包含格式版本、目錄修訂號、發布時間及模組清單。修訂號識別整份快照，模組版本沿用上游標籤。 |
| 模組資料 | 穩定 ID、固定收錄序號、作者來源、三語簡介與搜尋別名、封面及已核准的版本資料。安裝版本需有相容條件、固定資產、SHA-256 與客戶端支援的安裝方式。 |
| HTTP 回應 | 成功回傳 JSON 與對應內容的 ETag；相同內容且客戶端帶有匹配的 If-None-Match 時回傳 304。最新版快取建議上限 5 分鐘，緊急下架時清除該路徑快取。 |
| 客戶端落盤 | 收到 200 後先驗證格式版本、必要欄位、唯一 ID 和資產資料，再以暫存檔原子替換本機快照及 ETag。304 沿用有效快照；本機缺檔或損壞時改發無條件請求。錯誤頁、截斷內容與不支援的格式均保留上一份有效快照。 |

**啟動與刷新。** 有快取時立即顯示，背景檢查新版。首次安裝無快取時請求 Worker，建議單次逾時 4 秒，短暫網路錯誤最多再試一次，之後提供手動重試。首次同步失敗時顯示「尚未取得線上目錄」及重試入口，設定與本機安裝紀錄仍可開啟。已有快取則標示「使用快取」和上次成功同步時間。已安裝頁合併本機紀錄與目錄，下架後仍可查看及離線卸載。安裝或更新前重新確認發布狀態，無法確認時保留原安裝。

## 大陸玩家下載第三方模組

首版為允許中轉的已驗證套件提供同網域下載入口。建議路徑為 `GET /v1/downloads/{modId}/{version}/{assetId}`。App 只向此網址取檔；Worker 依此次核准發布的快照查找資產，在服務端向作者固定的 Release 檔案取回內容。GitHub 若將請求轉到發行資產主機，由 Worker 處理重新導向，確認最終主機屬於允許的上游，再把回應主體串流給 App。直接將 302 或作者下載網址交給玩家仍要求其連上 GitHub。下載端點只接受已收錄的識別碼。[Workers 串流文件](https://developers.cloudflare.com/workers/runtime-apis/streams/)

| 每個發行檔的條件 | 交付方式 |
| --- | --- |
| 已驗證，授權允許中轉 | App 統一從 Worker 下載；能中轉但不能留存時才採串流回源，並核實適用方案條款。下載成功後用已發布的大小和 SHA-256 校驗，再進入安裝。 |
| 已批准固定版本且允許留存與再散布 | 建議首版即使用私有 R2 套件庫。發布時上傳已校驗的原檔，以 SHA-256 識別物件，Worker 經 binding 讀出。玩家沿用同一下載入口。 |
| 僅允許作者直連，或再散布授權待確認 | 顯示作者來源與直連限制；經大陸三網實測後才標示直連可用。不得透過中轉或鏡像改變授權條件。 |

下架時先撤回下載對應並清除該檔公開快取，新請求查核發布狀態後才讀取快取或 R2。上游缺檔時回報套件暫不可用。首版驗收須在測試機阻斷 GitHub 與其 Release 資產網域後，從正式 Worker 網域下載完整套件及所有必需的載入器，確認無外站跳轉並核對雜湊；另測上游失效、斷線及下架後再次請求。測試覆蓋三網，目錄和各套件分開記錄結果。

### 2026-11-18 交付路徑調研

從 [Overtime v1.7](https://github.com/DarkJadeStone/MachineParty-Overtime/releases/tag/v1.7) 取得 CLI ZIP。GitHub 回應 302 至 release-assets.githubusercontent.com；下載 854,623 bytes，SHA-256 為 `f98b51526c9ba38167adc0578f24d2d998f6d2f4df51e6146580df27b589245c`，與 Release API 的資產摘要相同。包內含安裝器與 payload ZIP。本次只檢查位元組與封裝。

| 本機 Miniflare / workerd 測試 | 完整 GET | Range: bytes=0-1023 |
| --- | --- | --- |
| Worker 串流真實 GitHub Release | 200，854,623 bytes，雜湊相同 | 206，1,024 bytes，逐位元組相同 |
| Worker 讀取模擬私有 R2 的同一物件 | 200，854,623 bytes，雜湊相同 | 206，1,024 bytes，逐位元組相同 |

部分讀取僅證實範圍資料正確；正式端點仍須測 Content-Range、條件續傳、完整重組及中斷恢復。上述測試不含正式 Cloudflare 邊緣、Windows 遊戲安裝和大陸線路。

另外兩個候選在 GitHub Release API 的套件大小分別為 [MachineParty+ v2.1.0](https://github.com/Ghostx10742/MachineParty-Plus/releases/tag/v2.1.0) 的 94,946 bytes 與 [Binary1936 v1.5](https://github.com/Binary1936/machine-party-8p/releases/tag/v1.5) 的 32,387,456 bytes。三包合計約 33.34 MB，尚未計入載入器與多版本。對准許再散布的原檔，此規模可優先選私有 R2，以固定快照解除玩家下載對上游在線狀態的依賴。R2 Standard 的每月免費額度為 10 GB-month 儲存、100 萬次 A 類及 1,000 萬次 B 類操作，直接從 R2 的外送流量免費；Worker 請求另計。Cloudflare CDN 對大檔傳輸有服務條款，應依實際帳號方案核實，不能將橙雲視為無限制的檔案分發服務。[R2 計費](https://developers.cloudflare.com/r2/pricing/) · [Workers 計費](https://developers.cloudflare.com/workers/platform/pricing/) · [CDN 服務條款](https://www.cloudflare.com/service-specific-terms-application-services/)

上線前需逐包核清授權。Overtime 的 MIT 範圍只涵蓋作者原創部分，補丁中保留遊戲腳本上下文；MachineParty+ 的 MPML 載入器須另測、另行確認可分發範圍。授權未明時僅提供作者入口或經驗收的直連。[Overtime 授權](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ 安裝需求](https://github.com/Ghostx10742/MachineParty-Plus#installation)

## 誰能發布

1. 社群透過同倉庫 Issue 表單推薦模組，維護者選定資產後由流程產生草案 PR；熟悉資料格式的貢獻者也可直接提 PR。完整步驟見[收錄操作手冊](mod-catalog.md)。擬將收錄資料置於 `catalog/`、Worker 置於 `worker/`。PR CI 檢查格式、重複 ID、版本與資產資料，並建立可預覽快照。合併只更新倉庫。
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

## 實作順序

先在倉庫定義快照格式與驗證樣本；再完成 Worker、部署審核與正式網域，驗證擁有者可以發布、撤回和回滾。接著讓 Rust 客戶端讀取、快取與刷新目錄，執行三網冷啟動驗收。最後配合 Overtime 的 Windows 安裝與還原測試，驗證第一個可下載版本。
