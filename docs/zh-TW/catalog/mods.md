# 候選模組與收錄規範

[English](../../en/catalog/mods.md) · [简体中文](../../zh-CN/catalog/mods.md) · **繁體中文**

## 收錄操作手冊

**目前進度**　倉庫已有[投稿表單範本](../../../.github/ISSUE_TEMPLATE/mod-submission.yml)，合入 GitHub 預設分支後才會出現在 New issue。目前由維護者選擇 Release 並上傳 R2，目錄 Worker 發布已審核的快照。

[線上模組目錄](../architecture/ADR-006-online-catalog.md)

| 步驟 | 誰操作 | 做什麼、完成後得到什麼 |
| --- | --- | --- |
| 1. 投稿 | 任何人，含維護者 | 在 Issues → New issue 選「模組收錄或版本更新」，填作者倉庫、指定版本和用途。沒有 Release 仍可作為候選。投稿者無需編輯 Markdown 或 JSON。 |
| 2. 初審與選檔 | 維護者＋自動流程 | 維護者接受推薦後，流程列出指定 Release 的資產名稱、大小與來源，標出重複投稿。維護者選定要整合的檔案及載入器。以 Overtime v1.7 為例，直接改包路徑選 CLI ZIP；普通包和 MPML 包用途不同。 |
| 3. 產生收錄草案 | 自動流程 | 下載選定資產至暫存區計算 SHA-256，記錄上游標籤、資產 ID、長度，建立或更新同一份草案 PR。目前唯一結構化來源是 `catalog/mods.json`；流程接通後擬拆為每個模組一個 `catalog/mods/*.json`，再生成同格式的目錄快照。無發行檔者留在候選。程式僅讀取投稿資料與套件，不執行投稿內容。 |
| 4. 核實能否發布 | 維護者 | 按下方驗收單記錄授權及 Windows 實測，確認遊戲相容、安裝、卸載與離線還原。依賴逐個核對。將結果補入草案，CI 驗證欄位、雜湊、依賴及重複 ID。缺證據時保留候選狀態。 |
| 5. 批准上線 | 倉庫擁有者 | 合併草案後選擇 main 的指定提交，在 production 環境核對本次新增／更新／撤回項目並批准。合併與正式部署分開。 |
| 6. 分發並驗證 | 自動發布工作 | 按已批准的雜湊重新校驗原檔，將允許留存的套件寫入私有 R2（相同雜湊可重用），確認資產可讀後才部署 Worker 目錄，再從正式入口核對修訂號與下載內容。若上游已換檔或資產未備齊，停止發布並保留舊目錄。玩家下次刷新即可看到新版本。 |

**日常維護。** 新版沿用既有模組 ID 與收錄序號，重跑選檔與驗收；原已發布版本在新版通過前繼續生效。撤回版本時走同一個擁有者批准流程，同步撤回目錄資格及舊下載入口，保留本機卸載。部署後驗證失敗依[發布回滾流程](delivery.md)處理。首版可先用表單收件，待流程接通後再啟用自動產生 PR；逐模組的 Markdown 調查用於留存背景，不參與發布。

## 遊戲基線

Machine Party（Steam App ID 4108000）官方標示支援 2–4 人、線上合作、共享／分割畫面與 Remote Play Together。遊戲採用 Godot，社群模組可直接修改 PCK，或透過社群載入器載入外部模組。原版多人能力、模組新增能力及不同聯機安裝要求，應在項目說明中分別寫清楚。[Steam 商店](https://store.steampowered.com/app/4108000/Machine_Party/) · [開發者公告](https://steamcommunity.com/app/4108000/announcements/) · [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader)

## 候選清單

截至 2026-11-18，以下均為文件與上游程式碼調查，等待團隊實機驗證。下載次數為指定 GitHub Release 檔案的歷史快照，供評估需求使用。

| 候選 | 功能與下載觀察 | 整合與授權待辦 |
| --- | --- | --- |
| [Overtime](https://github.com/DarkJadeStone/MachineParty-Overtime) | 八人線上及本機擴充。v1.7 一般包 2,855 次，CLI 包 1,215 次。 | 優先測 Steam 遊戲 v2.1.2 搭配 v1.7 CLI。確認還原紀錄與離線卸載；直接改包與 MPML 路徑互斥。MIT 僅涵蓋作者原創部分。[安裝文件](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/docs/INSTALL.md) · [授權](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) |
| [MachineParty+](https://github.com/Ghostx10742/MachineParty-Plus) | 公開房間、語音及文字聊天。v2.1.0 模組 ZIP 1,917 次。 | 模組採 MIT；另核對 [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader) 的版本、首次安裝流程及中轉授權。測房間代碼與原版玩家加入；語音聊天需雙方安裝。 |
| [Binary1936 八人模組](https://github.com/Binary1936/machine-party-8p) | 線上八人。v1.5 模組 ZIP 5,297 次。 | 上游仰賴 Steam 驗證還原，須測 App 自行備份、還原與辨識未知副本。MIT 適用檔案以作者 [NOTICE](https://github.com/Binary1936/machine-party-8p/blob/main/NOTICE.md) 為準。 |
| [Broadcast 8P Freecam](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher) | 一位導播加八名參賽者，四隊輪換及自由鏡頭。下載量未核實。 | 安裝腳本有 install、verify、uninstall 入口。重點測既有備份；確認具體檔案授權後再決定中轉。公開倉庫首頁未見明確開源授權。[補丁原始碼](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher/blob/main/patcher.ps1) |

## 收錄驗收單（每個版本填寫）

- 模組 ID、作者首頁、固定發行檔、提交或標籤、SHA-256、授權範圍及直連／中轉決定。
- 測試日期、Windows 與 Steam 遊戲版本、原版 PCK 指紋、模組和載入器版本。
- 乾淨安裝、從 Steam 啟動、功能驗證、重啟後辨識、離線卸載及還原驗證結果。
- 支援的聯機組合、已知衝突、遊戲更新、下載失敗、安裝中斷及恢復的結果。
- 維護者確認後才發布可安裝版本；下架時保留既有用戶的本機卸載能力。新增模組才分配收錄序號。
- 上架時附大陸三網下載記錄、測試資產雜湊與最終交付路徑。若只能瀏覽，單獨記錄下載限制。測試方法見[目錄交付方案](delivery.md)。
- 逐一登記主套件與必需載入器的上游 Release、資產 ID、檔名、大小、SHA-256，以及各自允許的直連、中轉或留存方式。同標籤同檔名但內容變更時視為新候選，原雜湊核對失敗即停止安裝，重驗並由擁有者批准後再發布。
