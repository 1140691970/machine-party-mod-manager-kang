# ADR-009：自研模组、R2 确定性打包与自管加载器规范

[English](../../en/architecture/ADR-009-bundled-first-party-mods.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-009-bundled-first-party-mods.md)

日期：2026-11-19。状态：提议中；已在 macOS 完成 L1/L3 模拟验证，尚待 Windows Steam 实机对局验收。

## 问题

在本仓库开发的自研玩法模组（如首个玩法 `mods/roller-carnival/`）应当与第三方模组一样，通过 `catalog/mods.json` 与 Cloudflare Worker / R2（`packages/sha256/<sha256>.zip`）统一分发，使模组更新无需重编桌面端安装包或膨胀应用体积；与此同时，传统加载器类模组需要玩家先手动运行外部 `MachinePartyModLoader.exe`，难以实现一键安装与全部卸载后的自动无损还原。

## 决策

1. **自研模组源码归属（`mods/<id>/`）与确定性 R2 打包（`scripts/pack-mod.mjs`）**：
   - 自研模组源码位于仓库 `mods/<id>/` 下，内含合法 `mod.json`（`id` 匹配 `^[a-z0-9-]+$`）、纯粹 GDScript 实现与 `README.md`。
   - `scripts/pack-mod.mjs` 自动排除本地开发辅助与文档文件（`project.godot`、`*_scene.tscn`、`*.sh`、`*.md`、隐藏项与符号链接），生成固定时间戳、排序一致的 `ZIP_STORED` 归档 `<id>-<version>.zip`，其字节数与 SHA-256 按与其他模组完全相同的格式写入 `catalog/mods.json`。
   - `.github/workflows/catalog-worker.yml` 在部署目录时执行 `node scripts/pack-mod.mjs --all --verify-catalog`，自动将生成的 ZIP 上传至 R2 的 `packages/sha256/<sha256>.zip`，校对所有 `mirrorApproved` 对象后再写入 `catalog/revisions/<revision>.json` 并部署 `services/catalog-worker`。
2. **净室实现内置加载器（`pck_loader.rs` + `assets/mpm_bootstrap.gd`）**：
   - 依仓库 GPL-3.0-only 协议从零净室编写，不打包或再分发第三方可执行文件与上游加载器代码。
   - 当目录条目声明 `adapter.autoLoader: true`（仅允许 `kind: "loader-files"`）时，`installer.rs` 在 `install_from_zip` 解压与校验模组 ZIP 后、复制文件到 `<pckDir>/mods/<id>/` 前调用 `pck_loader::ensure_loader_installed`：
     - 若磁盘已有外部加载器（`MachinePartyModLoader.exe` 或非本管理器写入的 `Machine Party.pck.modloader.json`），则保留玩家原有的外部加载器不覆盖，直接写入当前模组目录。
     - 否则先校验原版 `Machine Party.pck` 指纹并在 `_mpm_loader` 下保留一份校验后的整包备份，以 GDPC Format 3 追加模式写入将 `*res://modloader/bootstrap.gd` 置首的 `project.binary`、`modloader/bootstrap.gd` 与 `.stamp`，读回解析验证后写入带 `"managed_by": "machine-party-mod-manager"` 标记的 `Machine Party.pck.modloader.json`。
   - 当卸载最后一个由管理器安装的 `loader-files` 模组、且不存在外部加载器或残留 `mods/` 子目录时，`installer.rs` 调用 `pck_loader::restore_managed_loader` 将目录指针恢复并截断回原版大小、校验原版 SHA-256、删除侧车标记与 `_mpm_loader` 备份；若期间 Steam 更新过 PCK，则拒绝截断并提示 `gameUpdatedOrModified`。
3. **统一目录与界面展示**：
   - `catalog/mods.json` 使用完全相同的 `package` 字段（`assetId`、`filename`、`size`、`sha256`、`mirrorApproved: true`）与可选 `adapter.autoLoader: true`，不添加特殊角标、特殊文案或独立链接规则。
   - 桌面端与 UI 对所有目录模组使用完全一致的卡片、详情与 `download_mod` -> `verify_package` -> `install_mod` 流程。

## 备选方案

- **编译期直接内嵌进桌面端可执行文件**：每次小修模组都要重新编发桌面客户端，且不符合所有模组经由 Worker + R2 分发的统一架构。
- **直接内嵌第三方 `MachinePartyModLoader.exe` 二进制**：存在跨仓库许可声明与误报/子进程脆弱性问题，不如原生 Rust GDPC v3 追加与截断还原可控。
- **要求玩家自行先安装外部 MPML**：破坏一键安装体验，也无法在卸载后自动还原原版 PCK。

## 相容性

- `catalog/mods.json` 保持 `schema: 1`；省略 `autoLoader` 时默认 `false`。
- `installations.json`、`game-path.json`、Tauri 命令名称与既有第三方 `upstream-cli` / `loader-files` 安装流全部保持兼容。
- 与玩家既有 `MachinePartyModLoader.exe` 和平共存，并与 `overtime` 等直接修改 PCK 的模组严格互斥（`loaderConflict` / `modConflict`）。

## 证据

- `scripts/pack-mod.mjs` 生成的 `roller-carnival-0.1.0.zip` 已通过 `tests/contracts/catalog.test.mjs` 与 `tests/contracts/online-catalog.test.mjs` 字节与哈希契约测试。
- `apps/desktop/src-tauri/assets/mpm_bootstrap.gd` 与 `mods/roller-carnival/` 通过 Godot 4.5.2 headless 语法检查及 `--self-test`。
- Rust `pck_loader` 与 `installer` 单元测试（含 `l1_zip_loader_mod_auto_installs_and_restores_loader_on_last_uninstall`）以及隔离拷贝原版 Steam v2.1.2 `Machine Party.pck`（`634,798,100` 字节）的 L3 实测均通过：写入后可正常读回首选自动加载项与引导脚本，拦截外部篡改/Steam 更新，且卸载还原后与原版 SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e` 逐字节一致。
- Windows + Steam 原版游戏中的 R2 下载、自动配置加载器、大厅弹窗、歌单选择、中场抽签、多人 RPC 联机与卸载还原仍需后续实机验收。
