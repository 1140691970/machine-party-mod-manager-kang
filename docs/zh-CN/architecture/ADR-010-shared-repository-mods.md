# ADR-010 · 同仓库模组的独立安装记录

[English](../../en/architecture/ADR-010-shared-repository-mods.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-010-shared-repository-mods.md)

滚筒嘉年华和房间机器人共用一个 GitHub 仓库，单靠仓库名无法区分两个安装版本。新条目可用 `inventoryById: true` 选用目录 ID 作为安装键，作者链接仍使用 `repo`。现有记录保留原键。全面迁移到 ID 需要改写玩家记录。完整在线目录在原端点使用 `?inventory=id`，旧网址仅返回可用仓库键区分的条目。目录测试覆盖共存、旧版响应与缓存标记。
