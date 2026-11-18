# 第三方聲明

[English](../../THIRD_PARTY_NOTICES.md) · [简体中文](../zh-CN/THIRD_PARTY_NOTICES.md) · **繁體中文**

Machine Party 模組管理器採用 GPL-3.0-only 授權。以下內容屬於他人，並適用其各自的條款。

## 遊戲

Machine Party 及其資源屬於其開發商與發行商。本專案與其無關，也不散布遊戲檔案。

## 收錄的模組

`catalog/mods.json` 中列出的模組是其作者的作品。管理器顯示每位作者並連結到原始倉庫；授權摘要見[候選清單](catalog/mods.md)。App 不內建任何模組套件。

## 封面圖片

| 檔案 | 來源 | 權利人 |
| --- | --- | --- |
| `apps/desktop/ui/images/overtime.png` | [Overtime 實機截圖](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/images/03_smoke_break_bench.png) | DarkJadeStone，MIT（[授權](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE)），畫面中的遊戲內容屬於遊戲開發商 |
| `apps/desktop/ui/images/plus.png` | [MachineParty+ 專案橫幅](https://github.com/Ghostx10742/MachineParty-Plus/blob/main/assets/banner.png) | Ghostx10742，MIT |

## 軟體相依套件

桌面 App 使用 [Tauri](https://tauri.app/) 及 `apps/desktop/src-tauri/Cargo.lock` 中列出的 Rust crate 建置，包括 `serde`、`serde_json`、`rfd`、`steamlocate` 與 `tauri-plugin-updater`。各 crate 依各自的授權散布，多為 MIT 或 Apache-2.0。Windows 版本使用 Microsoft WebView2。
