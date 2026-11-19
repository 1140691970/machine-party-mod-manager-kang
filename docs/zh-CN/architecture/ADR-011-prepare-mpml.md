# ADR-011 · 安装前统一准备 MPML

[English](../../en/architecture/ADR-011-prepare-mpml.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-011-prepare-mpml.md)

一键安装先用目录大小和 SHA-256 核对作者发布的 ZIP，再由 Rust 在暂存区准备 MPML 目录。Overtime 读取 CLI 包中的 payload 清单，保留上游的加载时序、版本与原版脚本指纹检查。Broadcast 和 Binary1936 读取资源树。MachineParty+、滚筒嘉年华与房间机器人已采用加载器格式。

Binary1936 和 Broadcast 共用 `apps/desktop/src-tauri/` 下的资源目录转换器 `src/installer/prepare.rs` 和 MPML 入口模板 `assets/recipes/resource_tree.gd`。转换 Binary1936 v1.5 时，管理器将 40 个脚本、16 个场景及其映射打入 `overlay.zip`，并用目录中的模组 ID 生成 `main.gd`。

安装事务记录来源指纹、转换规则版本与已安装文件指纹。三款八人玩法属于同一互斥组，切换时可保留其他加载器模组。单独分发转换包需要维护第二份发布产物，执行各上游安装器则需维护多套备份与还原程序。

旧版客户端仍可使用兼容目录与下载地址。已有的 Overtime MPML 安装可以继续使用。旧式受管 PCK 补丁可在模组详情选择「切换到加载器安装」，先验证新包，再还原已记录的副本并安装。手动安装的 mods/broadcast-8p 须先移出游戏目录。遇到未知文件变更时，还原会停止。

安装、升级或移除内置加载器时，管理器先在游戏所在磁盘准备并校验临时 PCK，再替换游戏文件。除备份外，游戏磁盘还需预留一份 PCK 的空间（v2.1.2 约 606 MiB）。升级加载器时会记录新旧两份指纹，以便中断后识别实际生效的版本。

卸载最后一个受管模组时，管理器会先校验还原后的 PCK，再删除模组文件，并记录还原指纹以便中断后继续清理。如果还有其他模组目录或目录链接，管理器会保留共用加载器。

发布包测试逐文件比对 Overtime 的 70 个编译脚本，以及 Broadcast 的 65 个、Binary1936 的 56 个资源。Steam 多人联机仍待实机验收。
