# ADR-018 · MPM 模组开发 SDK 与工具链架构

[English](../../en/architecture/ADR-018-mod-development-sdk.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-018-mod-development-sdk.md)

- **状态**：已落地（无头测试已验收；仍待 Windows Steam `v2.1.2` 实机验证）
- **日期**：2026-11-23
- **关联决策**：[ADR-001](ADR-001-project-boundaries.md)、[ADR-009](ADR-009-bundled-first-party-mods.md)、[ADR-015](ADR-015-multi-minigame-hub.md)、[ADR-017](ADR-017-modular-boundaries-and-core-runtime.md)、[模组 SDK 参考手册](../development/mod-sdk.md)

## 背景与问题

完成 [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md) 阶段 1–3 后，仓库已具备清晰的 Rust/UI 分层、`mods/_shared/` 单一来源校验、声明式 `requires` 依赖解析与 [`mpm-core`](../../../mods/mpm-core/README.md)（`v0.1.0`，`priority: -100`）核心运行库。但在继续开发第 4、5 款自研小游戏或开放第三方社区创作时，仍存在 4 类开发体验瓶颈：

1. **单模组胶水代码重复（约 250–350 行）**：每款小游戏都要重复编写 `_register_mod_scripts`、`_register_into_hub`、`_install_hub_overrides`、`_apply_cached_override`、`official_minigame.gd` 与对象池预热骨架。
2. **新建与维护依赖人工清单**：新增模组需手动建立 7–10 个文件、人工查未占用的 `order` / `assetId` / `TARGET_SLOT_ID`、回填 `catalog/mods.json` 并同步 4 处 README 表格。
3. **Godot 测试夹具各自为政**：`tests/mods/` 下各测试脚本分别复制了 `MockLoader`、`PlayerManager`、`GameManager`、`Minigame`、`LobbyScene`、`1280×720` 无头视口与 `.gd.uid` 清理逻辑。
4. **硬编码原版枚举槽位与人工防呆**：当前三款小游戏借用了原版未使用的 `MinigameIdentifier`（6 / 8 / 17），后续扩充必然冲突；而 [mod-development.md](../development/mod-development.md) 中的性能与编译红线尚未接入静态自动检查。

## 开源生态参考

我们结合本仓"零额外框架/零打包器"（[ADR-001](ADR-001-project-boundaries.md)）的原则，吸收成熟开源 Mod 生态的工程实践：

| 参考项目 | 借鉴的设计 | 刻意不引入的部分 |
| --- | --- | --- |
| **GodotModding / `godot-mod-loader`**（Brotato、Dome Keeper） | Godot 4 清单格式、`ModLoaderHookChain` 方法级挂载、结构化日志（`user://modloader.log`）与模组开发者工具规范 | 笨重的编辑器插件 UI；本仓桌面端与 headless Godot CLI 已覆盖打包与校验 |
| **SMAPI**（`Pathoschild/SMAPI`，星露谷） | 统一的 Mod Helper 门面（Events / i18n / Registry）、明确的版本兼容性契约，以及运行前静态分析器 | C#/.NET 程序集重写；MPML 基于 GDScript `take_over_path` 与 `compile` |
| **Fabric Loader + Fabric API**（`FabricMC/fabric`） | 极简、极少变动的底层引导器（`mpm_bootstrap.gd`）与独立升级的核心库模组（`mpm-core`）解耦，配合官方模板生成器 | 立即拆出独立仓库（按 ADR-017 阶段 5 延后） |
| **Thunderstore CLI (`tcli`)** | 一体化 `new` / `check` / `pack` 命令行工作流与确定性清单/ZIP 校验 | 外部包仓库上传（本仓直连 R2 + `services/catalog-worker`） |
| **tModLoader** | 声明式内容注册配合自动动态 ID 分配，告别人工抢占原版枚举槽位 | 二进制资源重编译管线 |

## 决策方案：四层轻量级 MPM Mod SDK

基于 Node 22 原生脚本、`mpm-core` 与纯 GDScript 建设四层 SDK：

1. **第 1 层：运行期 SDK（`mods/mpm-core/`）**：
   - 提供 `MpmMinigamePlugin` / `core.register_minigame(spec)`，让新小游戏的 `main.gd` 只需声明三语信息、简报、按键与玩法脚本，无需复制 Hub 胶水。
   - 提供可复用的 `MpmFxPool`（常驻对象池 + 视锥预热）、`MpmTeamSupport` 桥接，以及 `event_bus`、`locale`、`lobby_ui` 协调器 v2。
   - 升级 Hub v2 支持按 `mod_id` 动态分配高位槽位（`>= 1000`），彻底消除原版 `MinigameIdentifier` 槽位冲突。
2. **第 2 层：零依赖开发脚手架 CLI（`scripts/mod-cli.mjs`，`npm run mod -- <cmd>`）**：
   - `mod new <id> --template minigame|tool|graphics`：一键生成 `mod.json`、`main.gd`、`README.md`、`project.godot`、`run_mac.sh` 与基础 `--self-test`。
   - `mod check <id>`：串联 Godot `--check-only`、`--self-test`、静态红线 Linter 与 `pack-mod` 校验。
   - `mod catalog-sync <id>`：将确定性 `filename`、`size`、`sha256` 与 `requiredFiles` 自动回写至 `catalog/mods.json`。
3. **第 3 层：共用 Godot 测试沙盒（`tests/mods/_harness/`）**：
   - 沉淀统一的 `MockLoader`（完整 API v2）、`MockGameEnv`（`PlayerManager`、`GameManager`、`Minigame`、`LobbyScene`、`1280×720` 无头窗口与 `.gd.uid` 自动清理）以及参数化小游戏契约测试（冷启动编译 → 预加载场景注册 → FFA → 原生 `team-party` → 多模组共存 → 无泄漏退出）。
4. **第 4 层：静态红线 Linter 与正式 API 契约文档**：
   - 在 `check_architecture.mjs` / `mod check` 中加入 GDScript 静态规则：拦截 `_process` / `_physics_process` 中调用 `get_property_list()`、对动态 `keys()` / `.call()` 使用 `:=`、在 MPML 脚本中使用硬编码 `preload("res://...")`、重复 `TARGET_SLOT_ID` 以及遗漏 `mpm_local_player` 标记。
   - 在[模组 SDK 参考手册](../development/mod-sdk.md)中明确划分"稳定公开契约"与"内部实现细节"。

## 分期落地路线

| 阶段 | 范围 | 风险与前置条件 |
| --- | --- | --- |
| **SDK-1** | 正式 API 契约文档（`mod-sdk.md`）+ 静态模组 Linter（`scripts/mod-lint.mjs`，已接入 `check:architecture`） | **已完成并验收**（`tests/architecture/mod-lint.test.mjs`、`npm run check:architecture`） |
| **SDK-2** | 共用 Godot 测试 Harness（`tests/mods/_harness/`）+ `scripts/mod-cli.mjs`（`new` / `check` / `catalog-sync`） | **已完成并验收**（`tests/contracts/mod-cli.test.mjs`、`tests/mods/harness.test.mjs`） |
| **SDK-3** | `mpm-core` 运行期 SDK（`register_minigame(spec)`、`MpmFxPool`、Hub v2 动态高位槽位 `>= 1000`） | **已完成并验收**（`tests/mods/mpm-core.test.mjs`；仍待 Windows Steam `v2.1.2` 实机验收） |
| **SDK-4** | 方法级 Hook 链（`mods/mpm-core/hook_chain.gd`）+ 三款自研小游戏接入 `mpm-core` | **已完成并无头验收**（`tests/mods/mpm-core.test.mjs`，三款小游戏已声明 `requires: ["mpm-core"]`） |

## 备选方案

- **引入外部 JS/TS CLI 框架**：违背 [ADR-001](ADR-001-project-boundaries.md)，Node 22 原生脚本即可零依赖完成。
- **将全部 SDK 塞入 `mpm_bootstrap.gd`**：违背 [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md)，会导致每次微调 SDK 都必须重签发桌面客户端。
- **立即强行迁移三款既有小游戏**：延后至 `mpm-core` 通过 Windows 实机验证后按版本自然演进。

## 兼容性

- 完全保留 `catalog/mods.json` `schema: 1`、MPML API v2（`API_VERSION = 2`）、外部 `MachinePartyModLoader.exe` 共存与既有 `mods/<id>/` 目录结构。
- Hub v2 动态槽位（`>= 1000`）与既有的 Hub v1 槽位（6 / 8 / 17）可同时并存。

## 验收门禁

- **SDK-1**：`node --test tests/contracts/documentation.test.mjs`、`npm run check:architecture` 与 Linter 单元测试通过。
- **SDK-2**：CLI 脚手架生成的新模组可直接通过 `mod check`、`pack-mod --verify-catalog` 与契约测试。
- **SDK-3 / SDK-4**：Godot 4.5.2 全模组共存与 `team-party` 套件通过，并完成 Windows Steam `v2.1.2` 实机验收。
