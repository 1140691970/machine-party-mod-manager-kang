# 參與 Machine Party 模組管理器

[English](../../CONTRIBUTING.md) · [简体中文](../zh-CN/CONTRIBUTING.md) · **繁體中文**

歡迎提交問題回報、Windows 測試結果、模組推薦、翻譯、文件與程式碼。本指南說明如何準備便於審查的改動。

## 開始之前

- 使用問題請先閱讀[支援說明](SUPPORT.md)；安全漏洞請依[安全說明](SECURITY.md)私下回報。
- 先搜尋[既有 Issues](https://github.com/JamesGZM/machine-party-mod-manager/issues)，再使用範本提交。
- 推薦模組或模組新版本，請使用[模組投稿表單](https://github.com/JamesGZM/machine-party-mod-manager/issues/new?template=mod-submission.yml)，無需編輯 JSON。
- 大型功能、新的安裝方式或架構調整請先開 Issue 討論。小修正與文件更正可直接提交 PR。

Issues 與 PR 均歡迎使用英文、簡體中文或繁體中文。

## 開發環境

Fork 倉庫，從 `main` 建立分支，依照[開發指南](development/README.md)準備相依項目並了解目錄結構與命令。

每個 PR 聚焦一個問題，避免混入無關的格式調整、生成檔案或重構。修正行為問題時加入回歸測試；影響使用者或貢獻者時同步更新三種語言的文件。

## 工程規則

完整規則見 [AGENTS.md](../../AGENTS.md)，要點如下：

- 遵守[現行架構](architecture/README.md)中的邊界：`main.rs` 只組裝，`commands.rs` 負責驗證，領域模組不依賴 Tauri，只有 `ui/bridge.js` 接觸 Tauri。
- 新增或修改模組只改 `catalog/mods.json`，並填寫三種語言的文案。
- 介面文案集中在 `apps/desktop/ui/languages.js`，三種語言同步更新，並保留鍵盤操作、進度與錯誤回饋。
- 沒有經校驗的套件、帶指紋的備份與退回辦法，絕不寫入玩家的遊戲檔案。不動未知修改與其他模組的檔案。
- 加入網路服務、分析或遙測前先提出方案。原始碼、測試與診斷不得包含憑證、簽章金鑰或個人資料。

重要的所有權或契約決策需在 `docs/zh-TW/architecture/` 及其他語言目錄加入簡短 ADR，說明問題、決策、替代方案、相容性與證據。

## 驗證

開發時先執行最小相關檢查，提交前執行全部：

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

介面改動請附截圖。涉及安裝、卸載或更新行為時，請說明 Windows 版本、Steam 遊戲版本、模組版本、做了什麼以及結果。沒有在實機上測試時請明確說明；建置成功不代表遊戲已被還原。

僅修改文件時，檢查連結、命令與各語言版本的一致性，並說明實際執行了哪些檢查。

## PR 內容

1. 使用者看到的問題及修正後的行為。
2. 關鍵實作決策及取捨。
3. 自動測試、手動驗證及尚未驗證的條件。
4. 關聯 Issue、相容性與文件變化。

不要附上私密日誌、憑證、可辨識身分的截圖或本機備份。建置產物、快取、編輯器索引與 `.agent` 紀錄不進入倉庫。維護者可能要求修改或拆分 PR。合併不代表立即發版，見[發布流程](development/releasing.md)。

## 社群行為

尊重他人，針對工作給出可執行的回饋，歡迎不同經驗程度的參與者。禁止騷擾、歧視、威脅或公開他人的私密資訊。維護者可管理或關閉破壞性的討論；違反 GitHub 條款的行為可透過 GitHub 的工具檢舉。

## 授權與署名

貢獻採用專案的 [GPL-3.0-only 授權](../../LICENSE)。只提交你有權貢獻的內容，保留版權聲明，並在[第三方聲明](THIRD_PARTY_NOTICES.md)註明改編的第三方程式碼。不要求簽署貢獻者授權協議（CLA）。

第三方模組仍屬其作者，並適用各自的授權。目錄條目連結到作者；本倉庫不會重新授權或主張對其作品的權利。
