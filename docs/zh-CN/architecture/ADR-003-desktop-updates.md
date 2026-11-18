# ADR-003：签名的桌面更新

[English](../../en/architecture/ADR-003-desktop-updates.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-003-desktop-updates.md)

日期：2026-11-18。状态：已接受；记录 v0.1.1 已上线的链路。

## 问题

玩家需要在不访问 GitHub 的情况下收到管理器更新（包括中国大陆玩家），而且更新绝不能安装未签名或非预期的程序。

## 决策

- Windows x64 与 Apple Silicon 客户端使用 `tauri-plugin-updater`，开启 `requireSignedVersion` 并内置公钥，轮询 `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json`。
- `services/update-worker` 只读，只从私有 R2 桶提供稳定清单与 `app-downloads/{version}/{setup.exe|MachineParty-aarch64.app.tar.gz|manifest.json}`。按版本存放的对象不可变。
- **Release desktop app** 工作流构建双平台，在 `production` 环境签名，暂存版本对象，安装旧版 Windows 客户端并经 Worker 升级，发布 GitHub Release，最后才切换稳定清单。

维护者操作步骤见[发布流程](../development/releasing.md)。

## 替代方案

直接用 GitHub Releases 作为更新端点，许多中国大陆玩家无法访问。在端到端验收前就更新稳定清单，可能发出坏版本。

## 兼容性

已安装的客户端信任当前的公钥、identifier 与端点。改动任何一项都会让现有安装收不到更新，因此由 `tests/contracts/release-config.test.mjs` 固定。签名私钥必须保存在离线备份中。

## 证据

发布运行 44264743654 发布了含 darwin-aarch64 与 windows-x86_64 的 v0.1.1。一台 Apple Silicon Mac 经界面从 0.1.0 升级到 0.1.1，可执行文件与 GitHub 产物逐字节一致；Windows 升级验收在 CI 中通过。
