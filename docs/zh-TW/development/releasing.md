# 發布管理器更新

[English](../../en/development/releasing.md) · [简体中文](../../zh-CN/development/releasing.md) · **繁體中文**

Windows x64 與 Apple Silicon Mac 客戶端啟動時從 `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json` 檢查更新。玩家也可在設定頁查看目前版本並手動檢查。發現較新版本後，玩家點擊提示確認安裝。客戶端驗證下載套件的簽章與版本。Windows 執行 NSIS 安裝程式，Mac 取代目前的應用程式套件並重新啟動管理器。網路異常時仍可瀏覽本機目錄。設計取捨見 [ADR-003](../architecture/ADR-003-desktop-updates.md)。

## 維護者發布步驟

1. 在 `apps/desktop/src-tauri/Cargo.toml`、`apps/desktop/src-tauri/tauri.conf.json` 與根目錄 `package.json` 寫入相同的穩定版本號，例如 `0.1.2`。在 `apps/desktop/src-tauri` 執行 `cargo check` 更新鎖定檔，在 `CHANGELOG.md` 記錄變更，提交到 main。`npm test` 會檢查三處版本一致。
2. 在 GitHub Actions 開啟 **Release desktop app**，選擇 main 後執行。Windows runner 產生正式安裝程式與驗收用舊版，Mac runner 產生 Apple Silicon 應用程式封存檔。兩個平台共用穩定清單。
3. 檢查提交與建置結果，在 **Review deployments** 核准 production。簽章金鑰與 R2 憑證由該環境提供。
4. 工作流程先上傳版本專屬安裝程式與清單，再安裝舊版測試客戶端，實際經 Worker 下載、更新與重新啟動。它檢查執行中的版本與本機設定，接著建立 GitHub Release，最後切換穩定清單。之後已安裝的客戶端下次檢查即可收到更新。
5. 失敗時先查看失敗步驟。若只是網路問題，選擇 **Re-run failed jobs** 以重用已建置的安裝程式。若需修正發布腳本，可在 main 發起新的執行，在 `build_run` 填入原始建置的執行 ID。工作流程會核對來源與應用程式碼（文件、測試、腳本與工作流程的改動除外），沿用原安裝程式。勾選 `verify_only` 可對已暫存的版本單獨執行 Windows 升級驗收。發布後的安裝程式按版本固定，替換內容需要新版本號。

若以歷史建置重試時 GitHub 在建立 Release 步驟回傳 403，維護者可用具推送權限的帳號先執行 `git push origin <已驗收的完整提交SHA>:refs/tags/v<版本>`，再重跑失敗工作。工作流程會檢查既有標籤與安裝程式來源一致。

## 託管與簽章

Worker（`services/update-worker`）從私有 R2 bucket `machine-party-mods` 的 `app-releases/` 讀取。每個版本目錄包含 setup.exe、MachineParty-aarch64.app.tar.gz 與 manifest.json。穩定清單位於 `stable/latest.json`，停用快取。首次發布前，穩定端點回傳 HTTP 204。

首次部署或修改 Worker 時執行 **Deploy app update Worker**，在 production 核准。腳本使用既有的 Workers 權限綁定專案子網域。若無法自動取得區域 ID，可在 production 新增變數 `CLOUDFLARE_ZONE_ID`。部署使用 `CLOUDFLARE_ACCOUNT_ID` 與 `CLOUDFLARE_API_TOKEN`。發布另使用 `R2_BUCKET_NAME`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` 與 `TAURI_SIGNING_PRIVATE_KEY`。

首次安裝時，Windows 從 Cloudflare 鏡像下載 setup.exe。Apple Silicon Mac 下載 MachineParty-aarch64.app.tar.gz，解壓後將 .app 放到可寫入的應用程式目錄。Mac 套件使用 ad hoc 程式碼簽章，尚未經 Apple Developer ID 公證。早期 Mac 原型缺少更新器，需手動安裝一次支援更新的版本。客戶端內建更新公鑰。請將對應私鑰另存於受保護的離線備份，後續版本須能通過已安裝客戶端的公鑰驗證。Tauri 更新簽章與 Windows Authenticode 無關。

Windows 專用套件的預設程式目錄為 MachinePartyModManager。設定倉庫變數 WINDOWS_SIGNING_RUNNER 與 WINDOWS_SIGNING_THUMBPRINT，使用已在簽署存放區配置程式碼簽署憑證及私鑰的專用 Windows runner，並將其限制於受信任的發布工作。建置時簽署主程式與 NSIS 安裝程式並加時間戳。所有發布建置都需要配置簽署身分。發布新版本號的測試版時，在桌面發布工作流程啟用 publish_preview。GitHub 發布與 Cloudflare 鏡像分別驗證內嵌 Authenticode 簽章、憑證指紋與時間戳。使用 app Worker 工作流程的 preview_tag 同步同一份安裝檔。
