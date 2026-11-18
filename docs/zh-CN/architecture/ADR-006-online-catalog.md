# ADR-006 · 在线模组目录

[English](../../en/architecture/ADR-006-online-catalog.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-006-online-catalog.md)

目录需要独立于桌面版本更新。

客户端启动时读取 Worker 快照，缓存通过校验的数据供离线浏览。每个版本通过 Release 资产 ID 对应 R2 键 `packages/sha256/<sha256>.zip`。仅开放允许镜像的安装包。

随包提供列表需要为每次目录更新发布桌面版本。直接列出存储桶会暴露暂存文件。

既有安装记录、IPC 和签名更新沿用原格式。 在线目录契约测试覆盖刷新、缓存、安装包查找和下载权限。

公共入口通过 `CATALOG` 绑定将目录与下载请求交给 `machine-party-catalog`。新环境应先部署目录服务，再绑定公共入口。
