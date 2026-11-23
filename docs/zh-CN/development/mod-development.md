# 自研模组开发、测试、接入与打包规范

[English](../../en/development/mod-development.md) · **简体中文** · [繁體中文](../../zh-TW/development/mod-development.md)

本规范适用于在本仓库 [`mods/`](../../../mods/README.md) 目录下开发和维护的**第一方自研模组**；公开运行时契约与 SDK 工具链规划见[模组 SDK 参考手册](mod-sdk.md)与 [ADR-018](../architecture/ADR-018-mod-development-sdk.md)。第三方社区模组遵循[候选模组与收录规范](../catalog/mods.md)的上游发布审核流程；两者均通过同一套 Cloudflare R2 与目录 Worker 流水线分发（见[正式目录交付方案](../catalog/delivery.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。

## 1. 适用范围与设计原则

- **纯粹净室代码与 GPL-3.0-only**：所有自研模组（`mods/<id>/`）、确定性 ZIP 打包脚本（[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs)）及内置加载器（[`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd) 与 Rust `pck_loader.rs`）均为仓库原生编写。严禁提交游戏本体文件（`Machine Party.pck`、`.exe`）、第三方加载器二进制文件（`MachinePartyModLoader.exe`）、遥测逻辑或未经许可的网络请求（见 [AGENTS.md](../../../AGENTS.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **统一 R2 + Worker 分发与全自动加载器**：自研模组打成确定性 `.zip` 后存入 R2 `packages/sha256/<sha256>.zip`，经 `services/catalog-worker` 下发，更新模组无需重编桌面客户端。当 `loader-files` 模组声明 `adapter.autoLoader: true` 时，管理器首次安装会自动配置洁净室加载器（若玩家已有外部 `MachinePartyModLoader.exe` 则保留不覆盖），卸载最后一个加载器模组时无损还原为原版 `Machine Party.pck`（见 [ADR-005](../architecture/ADR-005-install-transactions.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。
- **开发辅助与运行文件自动隔离**：供 macOS 本地开发/调试使用的 Godot 工程（`project.godot`、`*_scene.tscn`、`*.sh`）与文档（`README.md`）可直接与模组源码同目录存放，[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) 会在打包 ZIP 时自动排除它们。

## 2. 目录结构、命名与 `mod.json` 规范

每个第一方模组位于 `mods/<id>/`，`<id>` 必须匹配正则 `^[a-z0-9-]+$`（例如 [`mods/roller-carnival/`](../../../mods/roller-carnival/README.md)）：

| 文件/模式 | 是否打入 R2 ZIP | 用途说明 |
| --- | --- | --- |
| `mod.json` | 是 | 模组清单，供加载器读取并与 CI 契约对齐校验 |
| `main.gd`（或 `entry`） | 是 | 继承 `Node` 的入口脚本，负责脚本覆写、Hook 与场景注册 |
| `*.gd` / 运行时资源 | 是 | 玩法逻辑、网格生成或通过 `dir_of(id)` / `mount_assets` 加载的资源 |
| `README.md` | 否（`*.md` 自动跳过） | 必需的模组说明文档：玩法规则、按键、文件清单、测试与安装说明 |
| `project.godot`、`*_scene.tscn` | 否 | 可选的 macOS 独立 Godot 预览工程与测试场景 |
| `*.sh`（如 `run_mac.sh`） | 否（`*.sh` 自动跳过） | 可选的本地启动、`--self-test` 与 `--screenshot` 辅助脚本 |
| `.*` 隐藏项与符号链接 | 否 | 隐藏文件、`.godot/` 缓存及符号链接一律忽略 |

### `mod.json` 清单格式

```json
{
  "id": "roller-carnival",
  "name": "Roller Carnival (滾筒嘉年華)",
  "version": "0.1.0",
  "authors": ["MachineParty Mod Team"],
  "entry": "main.gd",
  "priority": 0,
  "requires": []
}
```

- `id`：必须与目录名 `mods/<id>/` 及 [`catalog/mods.json`](../../../catalog/mods.json) 中的 `id` 完全一致。
- `version`：不带前导 `v` 的语义版本号（如 `"0.1.0"`）；契约测试会强制检查 `"v" + manifest.version === catalogEntry.version`。
- `entry`：指向同目录下存在、且继承自 `Node` 的入口 GDScript 相对路径。
- `priority` / `requires` / 可选 `enabled`：决定 `mpm_bootstrap.gd` 加载顺序（按 `priority` 升序、再按 `id` 字典序，并做依赖拓扑排序）。

## 3. 内置加载器运行时 API 与游戏接入规范

内置引导脚本（`LOADER_VERSION = "6"`、`API_VERSION = 2`）作为首项 `autoload/ModLoader`（`*res://modloader/bootstrap.gd`）在游戏脚本加载前运行，并与外部 `MachinePartyModLoader.exe` 保持 API v2 兼容。桌面管理器在 `mods/.mpm-state.json` 中记录已禁用的模组，加载器会在启动扫描时跳过它们而无需修改 `mod.json`。

### 生命周期回调

1. `_mod_init(loader)`：启动扫描并实例化入口脚本时立即执行，早于游戏主场景脚本编译加载；应在此阶段完成 `register_script`、`override_script_rel`、资源挂载与场景 Hook 注册。
2. `_mod_ready(loader)`：场景树就绪且延迟 autoload 挂载完成后触发；适合初始化 `Globals` 配置与默认游戏列表条目的兜底注册。

### API v2 可用接口

调用前应通过 `loader.has_api("<name>")` 或 `loader.has_method("<name>")` 做能力探测，保证在不同版本加载器下优雅降级：

- **脚本编译与覆写**：`compile`、`override_script`、`override_script_rel`、`register_script`、`register_autoload`、`register_global_class`、`mount_assets`。
- **场景与节点 Hook**：`on_scene_script`、`on_node_added`、`on_main_menu`、`on_lobby`。
- **状态查询与日志**：`dir_of`、`has_mod`、`mod_list`、`open_mods_folder`、`is_local_couch`、`game_mode`、`registry`、`note`、`api_version`、`loader_version`、`has_api`。

### 游戏接入准则

- **隔离虚拟路径**：通过 `register_script` 或 `take_over_path` 暴露的内部脚本统一放在模组专属虚拟前缀下（例如 `res://mods_<snake_id>/...`），避免多模组冲突。
- **开房设置前置到大厅**：将可调平衡参数集中存放在 `Globals.game_settings[SETTINGS_KEY]`，并在 `LobbyScene`（通过 `on_lobby` 识别）提供快速开房配置，局内 HUD 只保留必要状态提示。
- **动态兼容多人人数**：不得写死 4 人上限；站位分布、玩家卡槽与排名积分计算需能随实际参战人数在原版 2–4 人与多人模组 8–16 人间平滑自适应。
- **遵循官方小游戏信号协议**：接入轮换池的场景应完整声明标准信号（`host_loaded`、`minigame_loaded`、`minigame_ready`、`minigame_finished`、`player_scored`、`player_scores_finalized`）。
- **隔离测试快捷功能**：仅用于开发预览的按键（如 `F7` 叠层预览、`--self-test`）需严格隔离条件，不影响 Steam 正常对局。

### 运行时性能指标与红线

所有第一方模组都必须满足以下性能约束（对齐官方 `EffectManager` / `DecalManager` 的常驻对象池架构），避免周期性卡顿、首次特效冻结、多弹/多人并发掉帧与局中越打越卡：

| 维度 | 硬性指标 / 规范 | 原因与实现要求 |
| --- | --- | --- |
| **场景树扫描与属性反射** | `_process`、`_physics_process`、`node_added` 与定时器中 **禁止调用 `get_property_list()`**；对局中 **禁止周期性全树遍历** | `get_property_list()` 每次会分配数十个临时 `Dictionary`。改用 O(1) 的 `prop in obj`，首次绑定时缓存属性名；`node_added` 先用 `node.get_script() == null` 快速过滤；滤镜与状态监听改用信号（如 `visibility_changed`）替代定时全树轮询。 |
| **特效、贴花、灯光与火焰格常驻对象池** | 对局期间高频触发的粒子、贴花、闪光灯与格子爆炸视觉，**禁止运行时 `instantiate()`、`Decal.new()`、`OmniLight3D.new()`、新建 `SceneTreeTimer` 或 `queue_free()`** | 开局在 `_init_fx_pools()` 一次性预创建固定数量常驻节点，剥离 `managed_effect.gd` 并缓存 `GPUParticles3D`/`CPUParticles3D` 发射器数组；触发时只做轮转复用（瞬移 `position` + `visible = true` + `restart()`），在 `_process`/`_animate_visuals` 统一递减计时并隐藏回池。 |
| **视锥内着色器 / 粒子预热** | 开局倒计时阶段将各类池中真实节点各取 1 个放在**相机视锥内**以极小缩放（`0.01`）渲染约 `0.08s` 后归还（`--self-test` 与截图模式跳过） | 放在场下（`y < 0`、`scale = 0.001`）容易被视锥裁剪跳过编译，导致首炸/首撞依然冻结。预热回调必须通过 `self` 访问池数组，禁止闭包直接捕获可能被重开局释放的节点引用。 |
| **网格与材质复用** | 高频生成的实体（炸弹、爆炸格、滚筒、碎屑）**单次生成 0 次新建 `StandardMaterial3D` / `Mesh`** | 按参数键静态缓存共享 `Mesh` 与 `StandardMaterial3D`，减少 GC 抖动并利于 GPU 合批。 |
| **过绘控制、并发上限与连锁错帧** | 同类 `GPUParticles3D` 池 **≤ 4–6**（避免在 `mine_explosion` 上再叠加重复烟雾 `dustplume`，必要时缩减大尺寸烟雾粒子数）；单次爆炸仅在**中心放 1 个**焦痕 `Decal`（池 **≤ 16–24**）；闪光 `OmniLight3D` 池 **≤ 2**；同格重叠火焰直接刷新计时去重；连锁引爆必须**错帧延迟约 `0.05s`**（禁止同帧递归炸完）；连锁音效防抖 **≥ 45 ms** | 防止大面积半透明烟雾把 GPU 填充率打满、避免 Forward+ 灯光/贴花集群频繁重建，并将多弹连锁或 8 人同帧挨撞的 CPU/GPU/RPC 峰值摊平到不同帧。 |
| **显示与帧步调** | 默认开启 `VSYNC_ENABLED`；默认 3D 渲染缩放上限 **≤ 1.5×** 且不超过实际窗口像素高度（`2.0×`、`1440p`、关闭 VSync 均作为可选启动参数） | 避免软限 60 FPS + 关 VSync 引起的画面抖动，并防止小窗口或中低配显卡白跑 4× 像素填充量。 |
| **高并发压测验收** | 涉及特效或高频交互改动时，发布前需挂载真实 `Machine Party.pck` 跑 60 FPS 本地压测（如 8 弹满威力连锁、8 人同帧挨撞或 8 人连续互推） | 确认对局期间 FX/贴花/灯光/火焰格节点**零新增**、结束后池完整归还、无 Godot 闭包释放报错，且单帧最差模拟耗时远低于 `16.6 ms`。 |

## 4. 四级测试与验收规范

| 层级 | 覆盖范围 | 执行命令与通过标准 |
| --- | --- | --- |
| **Tier 0：Godot 本地测试** | 脚本语法、玩法逻辑自测、可选封面截图 | 1. 使用 Godot 4.5.2 headless `--check-only --script` 检查独立脚本语法（继承 `"res://..."` 的覆写脚本标注待游戏运行时加载）。<br>2. 运行 `--self-test` 验证物理移动、碰撞击退、安全间隔底线、预设组合与积分同分逻辑，确认输出 `SELF_TEST_PASSED`。<br>3. 可选生成 `1280×720` 封面截图至 `catalog/covers/<id>.png` 并人工审图。 |
| **Tier 1：打包、契约与 Lint** | 确定性 ZIP、边界隔离、目录契约、文档链路、Rust 规范 | 执行 `node scripts/pack-mod.mjs --all --verify-catalog`、`npm run check:architecture`、`npm test`、`npm run lint:rust`。自动校验 ZIP `size`/`sha256` 完全吻合、`mod.json` 与 `catalog/mods.json` 版本/ID 一致、`mods/<id>/README.md` 非空、`requiredFiles` 完整、R2 Worker 下载测试以及三语文档与相对链接有效。 |
| **Tier 2：Rust L1 与 L3 实包模拟** | ZIP 解压、GDPC v3 注入/还原、事务引擎 | 执行 `npm run test:rust`（覆盖 `pck_loader`、`installer`）。在 macOS 本地可用未提交的原版 Steam v2.1.2 `Machine Party.pck` 隔离副本执行 `MPM_L3_VANILLA_PCK="/path/to/Machine Party.pck" npm run test:rust`，验证写入与原版 SHA-256 无损还原。 |
| **Tier 3：Windows Steam 实机验收** | 正式开放安装前的硬性门禁（**`verified: true` 前置条件**） | 在 Windows + Steam `v2.1.2` 完成：桌面端经 Worker 下载并校验 SHA-256 安装 -> Steam 启动游戏 -> 大厅参数/轮换/多人 RPC 联机对局 -> 离线卸载确认原版 `Machine Party.pck` SHA-256 还原 -> 与外部 MPML 共存及与直接 PCK 补丁模组互斥测试。 |

### 游戏模组的回归测试基准

2026-11-19，Windows 玩家确认滚筒嘉年华 v0.1.3 已恢复正常（目录包 `1011`，修复提交 `64be6cc`）。故障版在启动时编译 `official_minigame.gd`，Godot 4.5.2 无法推断 `ids` 的类型。加载器记录了模组入口已加载，但跳过了播放列表注册。

- **小游戏从列表消失时**，先查 `user://modloader.log` 中的模组版本、第一个编译失败的脚本及注册结果，再对照同一次启动的 `user://logs/godot.log`，找到第一条解析错误和行号。Windows 的两个路径都以 `%APPDATA%\Godot\app_userdata\Machine Party` 为起点。
- **测试游戏实际加载的入口脚本。** 按游戏的自动加载顺序编译随包发布的脚本，包括以场景加载的单例。如果编译器在启动初期无法推断类型，就显式声明。本次修复是 `var ids: Array = PlayerManager.player_presences.keys()`。回归测试覆盖首次编译、创建可玩的场景，以及大厅已预载原脚本时的注册行为。[滚筒注册测试](../../../tests/mods/roller-registration.test.mjs)
- **保留玩家的显示设置。** 画质模组应将分辨率目标用于 3D 渲染。启用前后，对比全屏模式、窗口大小与位置、2D 界面缩放，并覆盖可选启动参数。[独立高清显示测试](../../../tests/mods/standalone-hd.test.mjs)

## 5. 目录接入与桌面端集成

新增自研模组到目录与 R2/Worker 分发体系的步骤：

1. 在 `mods/<id>/` 备齐 `README.md`、`mod.json`、运行时脚本；封面为选填，如需封面请放置于 `catalog/covers/<id>.<ext>`（支持 `.png`、`.webp`、`.jpg`）。
2. 运行 `node scripts/pack-mod.mjs <id>` 获取确定的 `filename`、`size`、`sha256` 与 `files` 列表。
3. 在 [`catalog/mods.json`](../../../catalog/mods.json) 新增条目：
   - 填写唯一的 `id` 和 `order`、来源 `repo`（例如 `"JamesGZM/machine-party-mod-manager"`）与 `"version": "v<mod.json.version>"`。
   - **可选 R2 封面图规范**：若提供 `catalog/covers/<id>.<ext>`，则在条目中声明 `"cover": { "filename": "<id>.<ext>", "contentType": "image/png" | "image/webp" | "image/jpeg", "size": <字节数>, "sha256": "<64位十六进制>" }`（上限 4 MiB，推荐 `1280×720` 16:9）。禁止将模组封面放入 `apps/desktop/ui/images/`（该目录仅保留应用自身图标如 `logo.svg`）。省略 `cover` 完全合法，卡片会自动显示标题占位（[ADR-016](../architecture/ADR-016-r2-mod-covers.md)）。
   - 同一仓库的新增模组使用 `"inventoryById": true` 建立独立安装记录，见 [ADR-010](../architecture/ADR-010-shared-repository-mods.md)。
   - 填写 `"package"`：唯一数字字符串 `assetId`（如 `"1001"`）、`scripts/pack-mod.mjs` 输出的 `filename`、`size`、`sha256`，以及 `"mirrorApproved": true`。
   - 设置 `supportedGameVersions` 与对应桌面预览版号的 `windowsPreview`，通过 Tier 3 前保持 `"verified": false`。
   - 配置 `adapter`：`kind: "loader-files"`、`platforms: ["windows"]`、`target: "pckDir"`、`touches: ["mods"]`、`exclusive: "loader"`、`autoLoader: true`、`upstreamUninstall: false`、原版 `baseline` 指纹以及精确对应的 `requiredFiles` 列表。
   - 补全 `zh-CN`、`zh-TW`、`en` 三语的 `name`、`summary`、`detail` 与 `aliases`。
   - 将 `category` 设为 `expansion`、`game`、`tool` 或 `graphics`。`releaseNotes` 为选填。提供时，将 `version` 设为条目版本，并填写已有的翻译。弹窗只显示玩家当前语言的说明。如果联机需要全员升级，可在说明中提醒。
4. 同步更新 [`mods/README.md`](../../../mods/README.md) 列表。在[英文](../../../README.md)、[简中](../../readme/README.zh-CN.md)、[繁中](../../readme/README.zh-TW.md)首页的模组表中，按目录顺序添加该模组及版本。
5. 无需也不会增加任何特殊界面逻辑：所有模组在卡片角标、详情弹窗与 Worker 下载 -> 校验 -> 安装流程中表现完全一致。

版本信息示例

```json
{
  "version": "v1.2.0",
  "category": "game",
  "releaseNotes": {
    "version": "v1.2.0",
    "zh-CN": "修复第二回合计分重复的问题。",
    "zh-TW": "修正第二回合重複計分的問題。",
    "en": "Fixed scores being counted twice in round two."
  }
}
```

## 6. 确定性 ZIP 打包与 R2 / Worker 发布

- **跨平台确定性打包**：[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) 按字典序收集非排除文件，采用 `ZIP_STORED`（method `0`）与固定 DOS 时间戳（`1980-01-01 00:00:00`）生成 ZIP，确保在 macOS、Linux 与 Windows 下产出的字节与 SHA-256 完全一致。
- **CI 自动上传 R2 并部署 Worker**：运行 `.github/workflows/catalog-worker.yml` 时，流水线会自动执行 `node scripts/pack-mod.mjs --all --verify-catalog --out "$RUNNER_TEMP/packages"`，将缺失的 `packages/sha256/<sha256>.zip` 与可选封面 `covers/sha256/<sha256>.<ext>` 上传至 R2（`machine-party-mods`），校验所有 `mirrorApproved` 包与 `cover` 对象的 `ContentLength`，再上传 `catalog/revisions/<revision>.json`、部署 `services/catalog-worker` 并验证线上 `HEAD /v1/downloads/...` 与 `HEAD /v1/covers/...` 返回 200。
- **更新已有自研模组** — 提升 `mods/<id>/mod.json` 的版本号，运行 `node scripts/pack-mod.mjs <id>` 取得新文件名、大小和 SHA-256。在 `catalog/mods.json` 更新包信息（包括 `assetId`）、目录修订号和模组版本。如有旧版说明，请更新或移除。同步更新模组 README、[模组索引](../../../mods/README.md)及[英文](../../../README.md)、[简中](../../readme/README.zh-CN.md)、[繁中](../../readme/README.zh-TW.md)首页表格的版本。推送到 `main` 后执行 `Deploy mod catalog Worker`。更新桌面客户端时请参阅[发布管理器更新](releasing.md)。

如果管理器已收录这个原生 MPML 模组，可设置 `"updateChannel": "preview"` 将新版提供给 Windows 测试版玩家。目录部署流程会签署本次修订。Windows 测试版 0.1.2-12 在“模组目录”点击“更新至”，核对版本后确认。Windows 预览版 0.1.2-11 的操作步骤见[支持指南](../SUPPORT.md)。通过 Steam 验收后再设置 `"verified": true`。详见 [ADR-012](../architecture/ADR-012-single-mod-updates.md)。

## 相关文档

- [ADR-009：自研模组、R2 确定性打包与自管加载器规范](../architecture/ADR-009-bundled-first-party-mods.md)
- [ADR-016：基于 R2 图床的可选模组封面规范](../architecture/ADR-016-r2-mod-covers.md)
- [ADR-005：安装事务与原版游戏校验恢复](../architecture/ADR-005-install-transactions.md)
- [ADR-007：模组适配器与 macOS 模拟验证层级](../architecture/ADR-007-mod-adapters.md)
- [正式目录交付方案](../catalog/delivery.md) · [开发指南](README.md) · [自研模组目录索引](../../../mods/README.md) · [滚筒嘉年华 README](../../../mods/roller-carnival/README.md)
