<div align="center">

<img src="../../apps/desktop/src-tauri/icons/128x128@2x.png" width="80" alt="Machine Party 模组管理器图标">

# Machine Party 模组管理器

### 为 Machine Party 打造的一键模组管理器。

在同一个窗口浏览 [Machine Party](https://store.steampowered.com/app/4108000/Machine_Party/) 的精选收录模组，按游戏副本对比版本，并在校验与备份保护下完成安装与还原。

<p align="center">
  <a href="https://github.com/JamesGZM/machine-party-mod-manager/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/JamesGZM/machine-party-mod-manager/check.yml?branch=main&amp;style=flat-square&amp;label=checks" height="24" alt="源码检查状态"></a>
  <a href="https://github.com/JamesGZM/machine-party-mod-manager/releases/latest"><img src="https://img.shields.io/github/v/release/JamesGZM/machine-party-mod-manager?style=flat-square&amp;label=release&amp;color=C99A49" height="24" alt="最新版本"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/github/license/JamesGZM/machine-party-mod-manager?style=flat-square&amp;color=64748B" height="24" alt="许可证：GPL-3.0-only"></a>
</p>

<p align="center">
  <a href="#下载"><img src="https://img.shields.io/badge/Windows-x64-D99A24?style=flat-square" height="24" alt="Windows：x64"></a>
  <a href="#下载"><img src="https://img.shields.io/badge/macOS-Apple%20Silicon%20(浏览)-007AFF?style=flat-square" height="24" alt="macOS：Apple Silicon（浏览）"></a>
  <a href="#已收录模组"><img src="https://img.shields.io/badge/Steam-Machine%20Party%20v2.1.2-7A2431?style=flat-square" height="24" alt="Steam：Machine Party v2.1.2"></a>
</p>

**[下载](#下载)** · [开始使用](#开始使用) · [文档](../zh-CN/README.md) · [更新记录](../zh-CN/CHANGELOG.md)

[English](../../README.md) · **简体中文** · [繁體中文](README.zh-TW.md)

</div>

<p align="center">
  <img src="../images/screenshot-catalog.zh-CN.png" width="100%" alt="模组目录与封面右上角的版本及分类标签">
</p>

<p align="center"><sub>模组目录显示各模组的收录版本与分类。</sub></p>

## 一目了然

| 精选收录模组 | 校验备份，安全还原 | 镜像加速与签名更新 |
| --- | --- | --- |
| 支持简体中文、繁体中文与英文名称搜索、联机说明与作者主页入口，覆盖目录内全部模组。 | 修改文件前先检查游戏进程、基线指纹与互斥冲突；按游戏副本保留可校验备份，支持离线卸载还原。 | 目录同步与已授权安装包优先经项目 Cloudflare Worker 获取，不依赖访问 GitHub；应用更新带签名校验与更新说明。 |

Steam 目录自动检测 · 离线缓存与还原 · 简体中文 / 繁體中文 / English 三语界面

## 下载

直接通过下方镜像链接或前往 [GitHub Releases](https://github.com/JamesGZM/machine-party-mod-manager/releases/latest) 下载对应平台安装包。

| 平台 | 架构 | 下载 | 说明 |
| --- | --- | --- | --- |
| Windows | x64 | [正式版 v0.1.1（`setup.exe`）](https://machineparty.ailaogong.men/v1/app-downloads/0.1.1/setup.exe) · [测试版 v0.1.2-12（`setup.exe`）](https://machineparty.ailaogong.men/v1/app-downloads/0.1.2-12/setup.exe) | NSIS 安装包，支持签名应用内更新 |
| macOS | Apple Silicon | [正式版 v0.1.1（`MachineParty-aarch64.app.tar.gz`）](https://machineparty.ailaogong.men/v1/app-downloads/0.1.1/MachineParty-aarch64.app.tar.gz) | 浏览目录与接收应用更新（游戏仅限 Windows） |

Windows 下载后运行 NSIS 安装程序即可；Apple Silicon Mac 解压归档并将 `.app` 移入可写的应用程序目录。

**Steam 上的《机械派对》（Machine Party）仅支持 Windows；当前 `0.1.2-12` 工作区已为目录内全部八个模组接入 `v2.1.2` 适配器，仍待完整 Windows 实机验收。** macOS 构建仅作 ad hoc 签名，未经 Apple 公证；Windows 安装包在未配置代码签名证书时为未签名包。已安装客户端会在启动时静默检查更新，在设置页显示红点，并在发现新版时弹出可延后处理的更新说明弹窗。详见[发布流程与验证说明](../zh-CN/development/releasing.md)。

## 开始使用

1. 启动管理器，应用会自动定位 Steam 中的 *Machine Party*（App ID `4108000`），也可在**设置**手动选择游戏目录。
2. 支持三语搜索与浏览全部已收录模组，点击标题可查看联机要求、冲突规则、兼容游戏版本与作者主页。
3. 点击**安装**。如果游戏正在运行，保存进度后选择**关闭游戏并继续**。管理器会校验套件并备份文件，然后安装。
4. 在**已安装**页面可离线卸载并校验原版还原结果；在**设置**页面可切换界面语言、更换游戏目录或检查管理器更新。

## 桌面应用

| 设置页 | 应用内更新提示 |
| --- | --- |
| ![设置页](../images/screenshot-settings.zh-CN.png) | ![应用内更新提示](../images/screenshot-update.zh-CN.png) |

更新提示截图演示从 0.1.2-11 到 0.1.2-12 的模拟升级。

## 已收录模组

下表列出这份[项目目录](../../catalog/mods.json)的版本。对应的目录修订发布后，管理器才会提供这些版本。

| 模组 | 版本 | 简介 | 适配方式与 `v2.1.2` 状态 |
| --- | --- | --- | --- |
| [Overtime](https://github.com/DarkJadeStone/MachineParty-Overtime) | `v1.7` | 最多 8 人在线或本地同玩 | 作者 CLI 资源清单 → MPML |
| [MachineParty+](https://github.com/Ghostx10742/MachineParty-Plus) | `v2.1.0` | 公开房间、语音与文字聊天 | 原生 MPML |
| [Broadcast 8P Freecam](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher) | `v0.91` | 8 人团播、四队轮换与导播自由镜头 | 作者资源目录 → MPML |
| [八人联机模组](https://github.com/Binary1936/machine-party-8p) | `v1.5` | 将在线游戏扩展至 8 人 | 作者资源目录 → MPML |
| [滚筒嘉年华](https://github.com/JamesGZM/machine-party-mod-manager/tree/main/mods/roller-carnival) | `v0.1.4` | 机械狂欢躲避小游戏 | 原生 MPML |
| [Lobby Bots](https://github.com/JamesGZM/machine-party-mod-manager/tree/main/mods/lobby-bots) | `v0.2.2` | 房主可添加或移除默认就绪的测试机器人。 | 原生 MPML |
| [独立高清](https://github.com/JamesGZM/machine-party-mod-manager/tree/main/mods/standalone-hd) | `v0.1.1` | 提高 3D 渲染清晰度，保留窗口模式和 HUD 布局 | 原生 MPML |
| [玩家聚光灯](https://github.com/JamesGZM/machine-party-mod-manager/tree/main/mods/player-spotlight) | `v0.1.0` | 在所有 3D 小游戏中只为自己点亮头顶工业聚光灯 | 原生 MPML |

验收清单、上游授权边界与互斥组规则详见[候选模组与收录规范](../zh-CN/catalog/mods.md)。

## 更新记录

**v0.1.2-12** · 安装、更新或卸载模组时，管理器会先询问是否关闭所选的游戏副本。应用更新提示会等当前对话框关闭后再显示。 滚筒嘉年华 v0.1.4 更新了场地和倒数效果；玩家聚光灯 v0.1.0 可用 F8 开关本机角色的顶灯；房间机器人 v0.2.2 支持迪斯科躲避玩法。 [完整更新记录](../zh-CN/CHANGELOG.md)。

## 文档

| 文档 | 用途 |
| --- | --- |
| [产品需求](../zh-CN/requirements.md) | 玩家流程、目录顺序、搜索及验收条件 |
| [现行架构](../zh-CN/architecture/README.md) | 组件、Steam 检测、目录、安装与 ADR |
| [开发指南](../zh-CN/development/README.md) | 环境、目录结构、命令与验证 |
| [模组开发与打包规范](../zh-CN/development/mod-development.md) | 模组开发、测试、目录接入与确定性 R2 打包规范 |
| [发布流程](../zh-CN/development/releasing.md) | 签名桌面更新、更新说明与发布工作流 |
| [候选模组与收录规范](../zh-CN/catalog/mods.md) | 游戏基线、候选清单、授权与验收单 |
| [正式目录交付方案](../zh-CN/catalog/delivery.md) | Worker 目录、所有者批准发布与中国大陆验收（规划中） |
| [界面设计规范](../zh-CN/ui-design.md) | 布局、卡片、设置页、弹窗与规划中的流程 |

全部文档：[docs](../README.md)。

## 隐私

管理器不包含任何遥测或统计埋点。游戏路径（`game-path.json`）、副本安装记录（`installations.json`）、下载缓存与备份文件全部保存在本地；仅在获取在线目录、已授权模组包与签名应用更新时连接项目 Worker。分享诊断信息前请阅读[安全说明](../zh-CN/SECURITY.md)。

## 参与贡献

推荐模组或提交新版本，请填写[模组投稿表单](https://github.com/JamesGZM/machine-party-mod-manager/issues/new?template=mod-submission.yml)。报告问题、提出功能或贡献代码请阅读[贡献指南](../zh-CN/CONTRIBUTING.md)。编码助手遵循 [AGENTS.md](../../AGENTS.md)。获取帮助见[支持说明](../zh-CN/SUPPORT.md)，安全漏洞请按[安全说明](../zh-CN/SECURITY.md)私下报告。

## 许可证

管理器代码采用 [GNU General Public License v3.0 only](../../LICENSE)（SPDX `GPL-3.0-only`）。官方版本免费提供。

Machine Party 模组管理器是社区项目，与游戏开发者无关。游戏、第三方模组与封面图片属于各自的权利人并适用其授权；作者、版本和来源保留在各条目页面。见[第三方声明](../zh-CN/THIRD_PARTY_NOTICES.md)。

## 致谢

- 社区模组作者：[DarkJadeStone (Overtime)](https://github.com/DarkJadeStone/MachineParty-Overtime)、[Ghostx10742 (MachineParty+)](https://github.com/Ghostx10742/MachineParty-Plus)、[Lnksoul (Broadcast 8P Freecam)](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher)、[Binary1936 (八人联机模组)](https://github.com/Binary1936/machine-party-8p) 与 [Krunk-theduck (MPML)](https://github.com/Krunk-theduck/MachinePartyModLoader)。
- [Tauri](https://tauri.app/) 以及[第三方声明](../zh-CN/THIRD_PARTY_NOTICES.md)中所列的开源 Rust 与 JavaScript 依赖。
