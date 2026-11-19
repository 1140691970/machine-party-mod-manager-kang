# 第三方声明

[English](../../THIRD_PARTY_NOTICES.md) · **简体中文** · [繁體中文](../zh-TW/THIRD_PARTY_NOTICES.md)

Machine Party 模组管理器采用 GPL-3.0-only 许可证。以下内容属于他人，并适用其各自的条款。

## 游戏

Machine Party 及其资源属于其开发商与发行商。本项目与其无关，也不分发游戏文件。

## 收录的模组

`catalog/mods.json` 中列出的模组是其作者的作品。管理器显示每位作者并链接到原始仓库；授权摘要见[候选清单](catalog/mods.md)。App 不内置任何第三方模组安装包。仓库 `mods/` 目录下的自研玩法模组（含 `mods/roller-carnival/`）与内置加载引导器（`apps/desktop/src-tauri/assets/mpm_bootstrap.gd` 与 `apps/desktop/src-tauri/src/pck_loader.rs`）均由本仓库按 GPL-3.0-only 编写。

## 封面图片

| 文件 | 来源 | 权利人 |
| --- | --- | --- |
| `apps/desktop/ui/images/overtime.png` | [Overtime 截图](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/images/03_smoke_break_bench.png) | DarkJadeStone，MIT（[授权](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE)），画面中的游戏内容属于游戏开发商 |
| `apps/desktop/ui/images/plus.png` | [MachineParty+ 横幅](https://github.com/Ghostx10742/MachineParty-Plus/blob/main/assets/banner.png) | Ghostx10742，MIT |
| `apps/desktop/ui/images/roller-carnival.png` | `mods/roller-carnival/` 自研玩法预览截图 | 本项目贡献者，GPL-3.0-only（画面中所呈现的原版美术素材属于游戏开发商） |

## 软件依赖

桌面 App 使用 [Tauri](https://tauri.app/) 及 `apps/desktop/src-tauri/Cargo.lock` 中列出的 Rust crate 构建，包括 `serde`、`serde_json`、`rfd`、`steamlocate` 与 `tauri-plugin-updater`。各 crate 按各自的许可证分发，大多为 MIT 或 Apache-2.0。Windows 版本使用 Microsoft WebView2。
