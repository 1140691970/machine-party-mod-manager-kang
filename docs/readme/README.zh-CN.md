# Machine Party 模组管理器

[![Source checks](https://github.com/JamesGZM/machine-party-mod-manager/actions/workflows/check.yml/badge.svg)](https://github.com/JamesGZM/machine-party-mod-manager/actions/workflows/check.yml)
[![Release](https://img.shields.io/github/v/release/JamesGZM/machine-party-mod-manager)](https://github.com/JamesGZM/machine-party-mod-manager/releases/latest)
[![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-blue)](../../LICENSE)

[English](../../README.md) · **简体中文** · [繁體中文](README.zh-TW.md)

为 [Machine Party](https://store.steampowered.com/app/4108000/Machine_Party/) 打造的免费、非营利桌面工具。玩家可以搜索团队手动收录的模组、查看说明与作者主页，并在通过验证后于同一个窗口完成安装与卸载。首次使用时自动寻找 Steam 游戏目录。

![模组目录](../images/screenshot-catalog.png)

## 项目阶段

基于 Rust 与 Tauri 2 的早期原型。

- 已提供：随包发布的目录，支持简体中文、繁体中文与英文搜索；模组详情；Steam 游戏检测与手动选择目录；按游戏副本比较版本；管理器自身的签名更新。
- Windows 测试版支持在指定的 v2.1.2 游戏副本上测试 Overtime v1.7。点一次「安装」，弹窗会自动下载、校验并安装；已有缓存可直接离线安装。操作前请完全退出游戏。其他模组在取得对应版本的依据之前显示「支持版本待确认」。

## 下载

从 [Releases](https://github.com/JamesGZM/machine-party-mod-manager/releases/latest) 下载最新版本。

- **Windows x64**：运行 `setup.exe`。
- **Apple Silicon Mac**：解压 `MachineParty-aarch64.app.tar.gz`，把 App 移到可写的应用程序目录。此版本使用 ad hoc 签名，未经公证。

安装后可在设置页或启动提示中自动更新。

## 文档

| 文档 | 用途 |
| --- | --- |
| [产品需求](../zh-CN/requirements.md) | 玩家流程、目录顺序、搜索及验收条件 |
| [现行架构](../zh-CN/architecture/README.md) | 组件、Steam 检测、目录、安装与 ADR |
| [开发指南](../zh-CN/development/README.md) | 环境、目录结构、命令与验证 |
| [发布流程](../zh-CN/development/releasing.md) | 签名桌面更新与发布工作流 |
| [候选模组与收录规范](../zh-CN/catalog/mods.md) | 游戏基线、候选清单、授权与验收单 |
| [正式目录交付方案](../zh-CN/catalog/delivery.md) | Worker 目录、所有者批准发布与中国大陆验收（规划中） |
| [界面设计规范](../zh-CN/ui-design.md) | 布局、卡片、状态与规划中的流程 |

全部文档：[docs](../README.md)。

## 参与贡献

推荐模组或提交新版本，请填写[模组投稿表单](https://github.com/JamesGZM/machine-party-mod-manager/issues/new?template=mod-submission.yml)。报告问题、提出功能或贡献代码请阅读[贡献指南](../zh-CN/CONTRIBUTING.md)。编码助手遵循 [AGENTS.md](../../AGENTS.md)。获取帮助见[支持说明](../zh-CN/SUPPORT.md)，安全漏洞请按[安全说明](../zh-CN/SECURITY.md)私下报告。

## 许可证

管理器代码采用 [GNU General Public License v3.0 only](../../LICENSE)（SPDX `GPL-3.0-only`）。官方版本免费提供。

Machine Party 模组管理器是社区项目，与游戏开发者无关。游戏、第三方模组与封面图片属于各自的权利人并适用其授权；作者、版本和来源保留在各条目页面。见[第三方声明](../zh-CN/THIRD_PARTY_NOTICES.md)。
