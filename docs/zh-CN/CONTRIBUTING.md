# 参与 Machine Party 模组管理器

[English](../../CONTRIBUTING.md) · **简体中文** · [繁體中文](../zh-TW/CONTRIBUTING.md)

欢迎提交问题报告、Windows 测试结果、模组推荐、翻译、文档和代码。本指南说明如何准备便于审查的改动。

## 开始之前

- 使用问题请先阅读[支持说明](SUPPORT.md)；安全漏洞请按[安全说明](SECURITY.md)私下报告。
- 先搜索[已有 Issues](https://github.com/JamesGZM/machine-party-mod-manager/issues)，再使用模板提交。
- 推荐模组或模组新版本，请使用[模组投稿表单](https://github.com/JamesGZM/machine-party-mod-manager/issues/new?template=mod-submission.yml)，无需编辑 JSON。
- 大型功能、新的安装方式或架构调整请先开 Issue 讨论。小修复与文档更正可以直接提交 PR。

Issues 和 PR 均欢迎使用英文、简体中文或繁体中文。

## 开发环境

Fork 仓库，从 `main` 建立分支，按照[开发指南](development/README.md)准备依赖并了解目录结构与命令。

每个 PR 聚焦一个问题，避免混入无关的格式调整、生成文件或重构。修复行为问题时增加回归测试；影响用户或贡献者时同步更新三种语言的文档。

## 工程规则

完整规则见 [AGENTS.md](../../AGENTS.md)，要点如下：

- 遵守[现行架构](architecture/README.md)中的边界：`main.rs` 只组装，`commands.rs` 负责校验，领域模块不依赖 Tauri，只有 `ui/bridge.js` 接触 Tauri。
- 新增或修改模组只改 `catalog/mods.json`，并填写三种语言的文案。
- 界面文案集中在 `apps/desktop/ui/languages.js`，三种语言同步更新，并保留键盘操作、进度与错误反馈。
- 没有经过校验的安装包、带指纹的备份和回退办法，绝不写入玩家的游戏文件。不动未知修改和其他模组的文件。
- 添加网络服务、分析或遥测前先提出方案。源码、测试和诊断不得包含凭据、签名密钥或个人数据。

重要的所有权或契约决策需在 `docs/zh-CN/architecture/` 及其他语言目录添加简短 ADR，说明问题、决策、替代方案、兼容性与证据。

## 验证

开发时先运行最小相关检查，提交前运行全部：

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

界面改动请附截图。涉及安装、卸载或更新行为时，请说明 Windows 版本、Steam 游戏版本、模组版本、做了什么以及结果。没有在实机上测试时请明确说明；构建成功不代表游戏已被还原。

仅修改文档时，检查链接、命令和各语言版本的一致性，并说明实际运行了哪些检查。

## PR 内容

1. 用户看到的问题及修正后的行为。
2. 关键实现决策及取舍。
3. 自动测试、手工验证及尚未验证的条件。
4. 关联 Issue、兼容性和文档变化。

不要附加私密日志、凭据、能识别身份的截图或本地备份。构建产物、缓存、编辑器索引与 `.agent` 记录不进入仓库。维护者可能要求修改或拆分 PR。合并不代表立即发版，见[发布流程](development/releasing.md)。

## 社区行为

尊重他人，针对工作给出可执行的反馈，欢迎不同经验水平的参与者。禁止骚扰、歧视、威胁或公开他人的私密信息。维护者可以管理或关闭破坏性讨论；违反 GitHub 条款的行为可以通过 GitHub 的工具举报。

## 许可证与署名

贡献使用项目的 [GPL-3.0-only 许可证](../../LICENSE)。只提交你有权贡献的内容，保留版权声明，并在[第三方声明](THIRD_PARTY_NOTICES.md)中注明改编的第三方代码。不要求签署贡献者许可协议（CLA）。

第三方模组仍属于其作者，并适用各自的许可证。目录条目链接到作者；本仓库不会重新授权或主张对其作品的权利。
