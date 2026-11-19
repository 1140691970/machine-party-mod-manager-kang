# ADR-011 · 安装前统一准备 MPML

[English](../../en/architecture/ADR-011-prepare-mpml.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-011-prepare-mpml.md)

一键安装先用目录大小和 SHA-256 核对作者发布的 ZIP，再由 Rust 在暂存区准备 MPML 目录。Overtime 读取 CLI 包中的 payload 清单，保留上游的加载时序、版本与原版脚本指纹检查。Broadcast 和 Binary1936 读取资源树。MachineParty+、滚筒嘉年华与房间机器人已采用加载器格式。

安装事务记录来源指纹、转换规则版本与已安装文件指纹。三款八人玩法属于同一互斥组，切换时可保留其他加载器模组。单独分发转换包需要维护第二份发布产物，执行各上游安装器则需维护多套备份与还原程序。

旧版客户端仍可使用兼容目录与下载地址。已有的 Overtime MPML 安装可以继续使用。旧式受管 PCK 补丁可在模组详情选择「切换到加载器安装」，先验证新包，再还原已记录的副本并安装。手动安装的 mods/broadcast-8p 须先移出游戏目录。遇到未知文件变更时，还原会停止。

发布包测试逐文件比对 Overtime 的 70 个编译脚本，以及 Broadcast 的 65 个、Binary1936 的 56 个资源。Steam 多人联机仍待实机验收。
