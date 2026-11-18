# ADR-002：模组目录的唯一来源

[English](../../en/architecture/ADR-002-catalog-source.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-002-catalog-source.md)

日期：2026-11-18。状态：已接受。

## 问题

模组条目分散在三处：`ui/app.js` 中的数组、`ui/languages.js` 中的简介与详情、Rust 中用于打开作者页的仓库白名单。新增一个模组要改三处，内容容易不一致。

## 决策

`catalog/mods.json`（schema 1）是唯一来源。每个条目包含稳定的 `id`、固定的 `order`、`repo`、可选的 `image` 和 `version`、`verified`，以及 `zh-CN`、`zh-TW`、`en` 三语的 `name`、`summary`、`detail`，还有搜索用的 `aliases`。

- Rust 在编译期内嵌该文件。`catalog` 命令把它交给界面，`open_project` 只接受其中列出的仓库。
- 界面经 `bridge.js` 加载并按 `order` 排序。在普通浏览器预览时从仓库直接读取。
- `tests/contracts/catalog.test.mjs` 检查 ID、序号与仓库唯一、翻译完整、封面图片随界面发布；Rust 测试检查解析与白名单。

## 替代方案

[目录交付方案](../catalog/delivery.md)中规划的每个模组一个 JSON（`catalog/mods/*.json`）更适合投稿 PR，以后可以通过生成同样的快照引入；目前四个条目还不值得这样做。在线获取目录也属于该方案，届时本 schema 作为离线后备。

## 兼容性

显示文案、顺序与搜索行为不变。安装记录以 `owner/repo` 为键，因此已有条目的 `repo` 不能修改。

## 证据

契约测试与 Rust 测试通过。浏览器对比显示，按名称、别名与其他语言简介搜索的结果完全一致。
