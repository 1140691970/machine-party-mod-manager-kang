# ADR-010 · 同仓库模组的独立安装记录

[English](../../en/architecture/ADR-010-shared-repository-mods.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-010-shared-repository-mods.md)

滚筒嘉年华和房间机器人共用一个 GitHub 仓库，单靠仓库名无法区分两个安装版本。新条目可用 `inventoryById: true` 选用目录 ID 作为安装键，作者链接仍使用 `repo`。全面迁移到 ID 需要改写玩家记录。完整在线目录在原端点使用 `?inventory=id`，旧网址仅返回可用仓库键区分的条目。目录测试覆盖共存、旧版响应与缓存标记。

滚筒嘉年华的本地安装记录改用目录 ID。内置目录的 `legacyInventoryRepos` 由新到旧列出测试版 5 和 6–8 使用过的仓库键。读取一份游戏副本时，管理器将这些键合并到同一个 ID，优先采用已有的 ID 记录，扫描验证成功后以交易中的版本为准。卸载会逐个文件核对，并移除该副本的相关记录。旧客户端仍可按 Worker 原有的 `inventoryById` 字段读取目录。同仓库后续添加的模组各自指定唯一的目录 ID，并设置 `inventoryById: true`。
