# ADR-004：按语言组织文档

[English](../../en/architecture/ADR-004-language-documentation.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-004-language-documentation.md)

日期：2026-11-18。状态：已接受。

## 问题

文档只有繁体中文，而 App 默认是简体中文；部分文件（`ui-design.md`）不断追加“取代上文”的段落，而不是重写。中文地区以外的贡献者没有入口。

## 决策

- 根目录的 `README.md`、`AGENTS.md`、`CONTRIBUTING.md`、`SECURITY.md`、`SUPPORT.md`、`CHANGELOG.md`、`THIRD_PARTY_NOTICES.md` 以英文为准，GitHub 与打包都需要它们位于根目录。
- 指南放在 `docs/en`、`docs/zh-CN`、`docs/zh-TW`，三者相对路径完全一致。翻译后的项目主页放在 `docs/readme`，共享图片放在 `docs/images`。
- 每个翻译页面开头都有语言切换。文档描述当前状态；过时内容直接重写，不追加。
- `tests/contracts/documentation.test.mjs` 检查路径一致、语言切换与相对链接。

## 替代方案

只保留一种语言维护成本更低，但会排除部分读者。只翻译 README 则指南仍不可读。

## 兼容性

`docs/architecture.md` 等旧路径已删除，仓库内链接已更新。模组投稿的 Issue 表单暂时保持繁体中文。

## 证据

文档契约测试通过。
