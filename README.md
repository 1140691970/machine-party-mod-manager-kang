# Machine Party 模組管理器

免費、非營利的 Windows 桌面工具。玩家可以搜尋團隊手動收錄的模組，查看作者首頁，在同一個介面完成安裝與卸載。首次使用時自動尋找 Steam 遊戲目錄。

**專案階段**　Rust / Tauri 桌面原型。以 `cargo run` 啟動、`cargo test` 執行目錄辨識測試。首頁目前使用隨包候選目錄，可離線瀏覽、搜尋與查看詳情；首次開啟偵測 Steam 目錄，設定頁可重新選擇。四個候選均待 Windows 驗收，安裝與還原尚未開放。[介面參考圖](docs/ui-reference.png)。首個驗收目標是讓玩家從乾淨的遊戲副本安裝 Overtime、透過 Steam 開局，離線卸載後驗證遊戲資料已還原。

| 文件 | 用途 |
| --- | --- |
| [產品需求](docs/requirements.md) | 玩家流程、首頁順序、搜尋及驗收條件 |
| [正式目錄交付方案](docs/catalog-delivery.md) | Worker 列表、擁有者批准發布、大陸三網驗收與離線行為（規劃中） |
| [技術設計](docs/architecture.md) | Steam 偵測、模組依賴、交易恢復及下載中轉 |
| [候選模組與收錄規範](docs/mod-catalog.md) | 遊戲能力、上游來源、授權及實測清單 |
| [介面設計規範](docs/ui-design.md) | 暗黑工業風首頁佈局、簡體中文文案與卡片狀態 |

Machine Party Mod Manager 是社群整合專案。遊戲與各模組的作者、版本和來源會保留在個別項目頁面。

推薦模組或提交新版，請依[收錄操作手冊](docs/mod-catalog.md)填寫 GitHub Issue 表單。

## 授權

本專案的管理器程式碼採 [GNU General Public License v3.0 only](LICENSE)（SPDX `GPL-3.0-only`）。官方版本免費提供。

遊戲、第三方模組與專案封面各自適用原權利人的授權。目錄中的圖片來源為 [Overtime 實機截圖](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/images/03_smoke_break_bench.png) 與 [MachineParty+ 專案橫幅](https://github.com/Ghostx10742/MachineParty-Plus/blob/main/assets/banner.png)。
