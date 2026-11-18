# 候選模組與收錄規範

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
