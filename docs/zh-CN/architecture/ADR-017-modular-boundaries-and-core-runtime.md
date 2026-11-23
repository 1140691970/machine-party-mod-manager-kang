# ADR-017 · 模块化边界、核心库模组与分阶段重构方案

[English](../../en/architecture/ADR-017-modular-boundaries-and-core-runtime.md) · **简体中文** · [繁體中文](../../zh-TW/architecture/ADR-017-modular-boundaries-and-core-runtime.md)

日期：2026-11-23。状态：阶段 1–5 已落地并通过自动化与无头测试验收（按阶段 5 条件暂不拆仓；仍待 Windows Steam `v2.1.2` 实机验证）。

## 问题

随着桌面管理器（`apps/desktop/`）与 7 个自研 GDScript 模组（`mods/`，`.gd` 源码合计 20,405 行）以不同节奏快速演进，当前代码结构出现四个影响扩展性与维护成本的瓶颈：

1. **桌面端单文件过胖与架构守卫存在盲区**：
   - `apps/desktop/src-tauri/src/installer.rs` 已膨胀至 6,360 行（将进程与锁抽象、ZIP 解压、交易记录、启停状态、互斥冲突检测、副本校验/扫描、两套适配器实现以及约 3,490 行内联测试混在同一文件中）。
   - `apps/desktop/src-tauri/src/pck_loader.rs` 达 1,443 行（GDPC v3 / ECFG 二进制编解码与安装/还原状态机及测试耦合）。
   - `apps/desktop/ui/catalog-view.js` 达 1,053 行（列表渲染、弹窗、单体安装流程与批次操作混写）。
   - `scripts/check_architecture.mjs` 中的 `tauriFree` 目前仅硬编码检查顶层 6 个 `.rs` 文件，尚未覆盖 `apps/desktop/src-tauri/src/installer/update.rs` 等子模块。
2. **自研模组单文件过胖**：
   - `mods/team-party/main.gd` 单文件达 4,570 行，其中大厅 UI 与 3D 椅子拖拽占约 2,270 行，针对外部自研小游戏的反射包装占约 820 行。
   - 三款自研小游戏主脚本（`mods/roller-carnival/roller_carnival_game.gd` 1,890 行、`mods/bubble-blitz/bubble_blitz_game.gd` 2,260 行、`mods/spike-ring/spike_ring_game.gd` 2,785 行）将玩法循环、特效/贴花池与联机同步混在一起。
3. **多小游戏 Hub 覆写代码逐字重复**：
   - 按 [ADR-015](ADR-015-multi-minigame-hub.md)，`override_game.gd`（150 行）、`override_local_game.gd`（137 行）、`override_picker.gd`（251 行）、`override_playlist.gd`（137 行）共 675 行代码在 `mods/bubble-blitz/`、`mods/roller-carnival/` 与 `mods/spike-ring/` 中完全重复存在。每次修复 Hub 都要同步改动并重发全部小游戏包。
4. **游戏侧适配逻辑与桌面端发版强绑定**：
   - `apps/desktop/src-tauri/assets/mpm_bootstrap.gd`（916 行）中有 447 行是针对游戏大厅 UI 的防重叠排版逻辑。游戏侧布局一旦需要调整，就必须重新签章发布桌面客户端，无法通过目录与 R2 热更新。

## 决策

参考成熟开源模组生态（`GodotModding/godot-mod-loader` + `Brotato-ContentLoader`、`Fabric Loader` + `Fabric API`、`modrinth/code`、`Kesomannen/gale`、`NexusMods.App`），确立四层职责边界，并按五个可独立验收的阶段推进落地：

```text
[ 桌面管理器本体 (Rust + 原生 ES UI) ] ── 下载、交易安装、requires 依赖图、PCK 还原
            │ 仅注入极简引导器
            ▼
[ 极简加载器 (mpm_bootstrap.gd) ]     ── 扫描发现、requires 排序、compile/override/hook 原语
            │ 优先加载前置核心库
            ▼
[ 核心库模组 (mpm-core，走 R2 分发) ]  ── Minigame Hub v2、Lobby UI 协调器、共用 FX 与事件总线
            │ requires: ["mpm-core"]
            ▼
[ 玩法与功能模组 ]                     ── roller-carnival / bubble-blitz / spike-ring / team-party / 后续新模组
```

### 阶段 1：架构守卫硬化与桌面端拆文件（零行为变更）

1. **加固 `scripts/check_architecture.mjs`**：
   - 将 6 文件黑名单改为白名单机制：`apps/desktop/src-tauri/src/` 下（含任意层级子目录）除 `main.rs`、`commands.rs`、`app_updates.rs` 外，其余全部 `.rs` 文件均禁止引用 `tauri::`、`tauri_plugin_*::` 或 `crate::commands`。
   - 在 `tests/architecture/boundaries.test.mjs` 补充子模块违规回归测试。
2. **拆分 `apps/desktop/src-tauri/src/installer.rs` 为 `installer/mod.rs` 及职责子模块**：
   - 在 `installer/mod.rs` 保留全部现有 `pub` 重导出以保持 `commands.rs` 调用零改动，并与现有的 `prepare.rs`、`steam_restore.rs`、`update.rs` 并列：
     - `runner.rs`：`ProcessRunner`、`SystemRunner`、`GameLockCheck`、`SystemGameLockCheck`
     - `zip.rs`：`extract_zip` 与路径穿越校验
     - `transaction.rs`：`FileFingerprint`、`TransactionRecord`、备份路径与 `transactions.json` 读写
     - `state.rs`：`.mpm-state.json` 启停状态管理
     - `conflicts.rs`：互斥群组检查与外部加载器检测
     - `inspect.rs`：`inspect_mod`、`validate_game_mods`、`reconcile_copy`、`adopt_manual_install`、`scan_copy`
     - `adapters/loader.rs`：`normalize_loader_staging`、`install_loader_files`、`resumable_loader_cleanup`
     - `adapters/upstream_cli.rs`：`validate_adapter`、`build_command`、`parse_status`、`parse_mp8r_restore`、`mirror_delta_backup`
     - `tests/`：按领域主题迁出约 3,490 行内联测试。
3. **拆分 `apps/desktop/src-tauri/src/pck_loader.rs`**：
   - 拆出 `pck_loader/gdpc.rs`（GDPC v3 索引与载荷处理、MD5 与 ECFG 编解码）、`pck_loader/mod.rs`（安装/还原/标记状态机）及 `pck_loader/tests.rs`。
4. **拆分 `apps/desktop/ui/catalog-view.js`**：
   - 坚持零构建原生 ES 模块（[ADR-001](ADR-001-project-boundaries.md)），拆分为 `catalog-view.js`（列表与卡片）、`mod-dialogs.js`（详情、更新确认与卸载弹窗）、`mod-install-flow.js`（单体下载、安装、切换与启停流程）及 `batch-view.js`（配合 `batch.js` 承担筛选栏与批次操作界面）。
5. **文件规模约定**：正式源码模块控制在聚焦规模（约 <=700 行），测试按域独立存放。

### 阶段 2：自研模组模块化、共享单一来源与原生组队下沉（已完成）

1. **拆分 `mods/team-party/main.gd` 并退役自研小游戏执行期包装**：
   - 将 `mods/team-party/main.gd`（4,570 行 -> 685 行）拆出 `team_registry.gd`、`lobby_assignment.gd`、`lobby_ui.gd`、`lobby_drag_3d.gd`、`vanilla_ingame.gd` 与 `ingame_hud.gd`，保留入口、RPC 端点与公开/测试门面，确保 `tests/mods/team_party_test.gd` 与 `tests/mods/team_party_sandbox.gd` 完全兼容。
   - 删除 `_wrap_custom_stage` 与约 820 行外部源码重写包装；`team-party` 仅保留房间组队管理、右上角 Squad 状态栏与无法改源码的官方原版小游戏挂接。
2. **消除重复 `override_*.gd` 并建立可选组队共享助手**：
   - 在 `mods/_shared/minigame-hub/` 与 `mods/_shared/team-support/team_support.gd` 建立单一来源（不放 `mod.json`），由 `scripts/pack-mod.mjs --sync-shared` 与 `scripts/check_architecture.mjs`（`checkSharedModParity`）保证跨模组零漂移。
3. **三款自研小游戏原生组队与子模块拆分**：
   - `mods/bubble-blitz/`（`v0.1.5`）：原生实现分队出生、友军火焰免疫、倒地碰触救援、救援倾向 AI、提前胜出与小队同步计分，并拆出 `fx_pool.gd`、`ai_controller.gd`、`self_test.gd`。
   - `mods/spike-ring/`（`v0.1.3`）：原生实现分队出生、友军零推搡、360° 冲击波免伤、3.5m 护盾共振、仅攻击敌队 AI、提前胜出与小队同步计分，并拆出 `hazard_director.gd`、`fx_pool.gd`、`ai_controller.gd`、`self_test.gd`。
   - `mods/roller-carnival/`（`v0.1.11`）：原生实现按队分道、队色底座与名牌、未团灭继续比拼与小队同步计分，并拆出 `fx_pool.gd`、`hud_ui.gd`、`self_test.gd`。
   - 重跑 `scripts/pack-mod.mjs --all` 并同步更新 `catalog/mods.json`（`revision: 2026-11-23.1-mpml1`）。

### 阶段 3：声明式 `requires` 依赖解析与 `mpm-core` 核心库模组（已完成）

1. **在保持 `schema: 1` 下扩展 `catalog/mods.json`**：
   - 新增可选字段 `requires`（如 `[{"id": "mpm-core", "minVersion": "v0.1.0"}]`，默认为空数组）与核心库角色/分类标记，使桌面端在界面上能妥善管理核心依赖，而不干扰玩家浏览玩法模组。
2. **在 Rust 安装引擎实现依赖解析**：
   - **安装与更新**：对依赖有向无环图做递归拓扑排序并拦截循环依赖，在安装目标模组前自动安装或升级缺失/过旧的前置库；任一步失败整笔回滚。
   - **停用与卸载保护**：当仍有其他已安装或已启用的模组依赖该核心库时，拒绝停用/卸载并返回可翻译错误键与依赖方列表；当最后一个依赖方卸载且核心库为自动安装时，一并清理并还原原版 `Machine Party.pck`。
3. **引入 `mods/mpm-core/`（走与所有模组相同的 R2 + `catalog-worker` 管线）**：
   - 以 `priority: -100` 优先加载，集中承载高频演进的游戏侧运行时逻辑：
     1. **Minigame Hub v2（`HUB_VERSION = 2`）**：在混合版本共存期间平滑覆盖旧版 `HUB_VERSION = 1`。
     2. **Lobby UI 协调器 v2**：接管原嵌在 `mpm_bootstrap.gd` 中的游戏大厅防重叠排版，使 `mpm_bootstrap.gd` 瘦身回极少修改的纯加载器。
     3. **共用工具层**：跨模组事件总线、通用 FX/贴花池基类与多语本地化辅助函数。
4. **发布节奏控制**：先发布并实机验收支持 `requires` 的桌面版，再让后续新版本小游戏声明依赖 `mpm-core`。

### 阶段 4：方法级 Hook 链与跨模组事件契约

1. **方法级 Hook 链**：
   - 在加载器/核心层引入类似 `ModLoaderHookChain` 的方法级挂载原语，允许多个系统模组按顺序拦截同一个原版 GDScript 函数，避免整文件 `override_script` 互相覆盖。
2. **统一小游戏与组队事件契约**：
   - 在 `mpm-core` 定义标准小游戏生命周期与事件接口，供未来新模组与官方关卡挂接复用（`team-party` 原有的 ~820 行外部反射包装已于阶段 2 提前退役）。

### 阶段 5：CI 按路径分流与未来拆仓触发条件（暂不拆仓）

1. **CI 按路径分流**：
   - 在桌面、加载器与模组仍高频协同演进期间保持单仓，在 `.github/workflows/check.yml` 中按改动路径分流 PR 检查（`apps/desktop/**` 与 `mods/**` + `catalog/**`），合入与发布前保留全量门禁。
2. **明确的未来拆仓条件**：
   - 仅当（a）桌面管理器与 `mpm-core` API 进入稳定维护期，且（b）自研模组超过约 10–12 个或准备高频接收外部社区模组 PR 时，再将 `mods/` 拆为独立 `machine-party-mods` 仓库。由于 [ADR-009](ADR-009-bundled-first-party-mods.md) 已将第一方与第三方分发统一到 R2 + `catalog-worker`，届时拆仓无需调整分发架构。

## 备选方案

- **立即将 `mods/` 拆分为独立仓库**：目前 `mpm_bootstrap.gd`、自研模组与跨模组共存测试（`tests/mods/`）经常在同一 PR 中联动修改；过早拆仓只会增加跨仓对版本号的摩擦。
- **引入 JS 打包框架或拆分 Cargo workspace**：违背 [ADR-001](ADR-001-project-boundaries.md) 的轻量化边界，原生 ES 模块分文件与 Rust 子模块目录即可零工具链开销解决问题。
- **将本地 JSON 状态（`installations.json`、`transactions.json`）迁往 SQLite**：按 [ADR-003](ADR-003-desktop-updates.md)，在几十个模组规模下，人类可读的 JSON 交易记录更简单、易审计且完全向后兼容。
- **继续把游戏侧协调逻辑堆在 `mpm_bootstrap.gd` 中**：每次游戏 UI 或 Hub 调整都会被迫发布新版签章桌面客户端。

## 兼容性

- 保留 `installations.json`、`game-path.json`、`transactions.json`、`.mpm-state.json`、Tauri IPC 命令名、更新器配置及 `catalog/mods.json` `schema: 1`（[ADR-003](ADR-003-desktop-updates.md)）。
- 阶段 1 与阶段 2 均为纯内部重构，不改变任何用户侧行为与存储格式。
- 阶段 3 向后兼容旧版桌面客户端（旧版本会安全忽略未知可选目录字段）与外部 `MachinePartyModLoader.exe` 环境，并在版本过渡期通过 `HUB_VERSION = 2` 平滑覆盖旧版 `HUB_VERSION = 1`。

## 验证证据与各阶段门禁

- **阶段 1 与阶段 2 已完成**：
  - 阶段 1：`scripts/check_architecture.mjs`（覆盖 Rust 子模块的白名单机制与 `tests/architecture/boundaries.test.mjs` 回归测试）、`pck_loader/`、`installer/`（保留全部 29 项测试）与 `apps/desktop/ui/` 拆分均已通过 `npm run check:architecture`、`npm test`、`npm run lint:rust` 与 `npm run test:rust`。
  - 阶段 2：`mods/_shared/{minigame-hub,team-support}/` 一致性校验、`mods/team-party/` 6 模块拆分，以及 `mods/bubble-blitz/`（`v0.1.5`）、`mods/spike-ring/`（`v0.1.3`）、`mods/roller-carnival/`（`v0.1.11`）原生组队下沉与子模块拆分均已通过 `node scripts/pack-mod.mjs --all --verify-catalog`、三款小游戏独立 Godot `--self-test`（`SELF_TEST_PASSED`）、`npm run check:architecture` 与 `npm test`（含 `tests/mods/team-party.test.mjs`）。
  - 阶段 3：`catalog.rs`（`ModRequirement`、`role`、`compare_numeric_versions`）、`installer/deps.rs`（DAG 解析、循环/版本拦截、失败回滚、禁用与卸载保护、末依赖自动清理）、`ui/` 依赖预下载与详情提示、`mods/mpm-core/`（`v0.1.0`、`HUB_VERSION = 2`、`event_bus.gd`、`locale_utils.gd`、`lobby_ui_coordinator.gd`）及 `mpm_bootstrap.gd` 让步逻辑已通过 `deps_tests`、`tests/ui/dependencies.test.mjs` 与 `tests/mods/mpm-core.test.mjs`。按发布节奏，既有小游戏将在 Windows Steam 实机验收后再启用 `requires: ["mpm-core"]`。阶段 4–5 仍按规划推进。
- **阶段 1 验收门禁**：`npm run check:architecture`（含子模块）、`npm test`、`npm run lint:rust`、`npm run test:rust`（本地具备原版包时加跑 `MPM_L3_VANILLA_PCK` 模拟测试）。
- **阶段 2 验收门禁**：`node scripts/pack-mod.mjs --all --verify-catalog`、`npm test`（含 `tests/mods/*.test.mjs`）以及各小游戏独立 Godot `--self-test`（`SELF_TEST_PASSED`）。
- **阶段 3 验收门禁**：Rust L1 依赖图/循环拦截/回滚/末依赖自动清理测试、UI 依赖提示与卸载拦截测试、Godot `mpm-core` 共存与混装 `HUB_VERSION` 测试，以及在正式目录启用 `requires` 前的 Windows Steam 实机验收。
- **阶段 4 验收门禁**：Godot 4.5.2 多模组 Hook 链共存测试与 `team-party` 集成测试。
