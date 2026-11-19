# 自研模组开发、测试、接入与打包规范

[English](../../en/development/mod-development.md) · **简体中文** · [繁體中文](../../zh-TW/development/mod-development.md)

本规范适用于在本仓库 [`mods/`](../../../mods/README.md) 目录下开发和维护的**第一方自研模组**。第三方社区模组遵循[候选模组与收录规范](../catalog/mods.md)的上游发布审核流程；两者均通过同一套 Cloudflare R2 与目录 Worker 流水线分发（见[正式目录交付方案](../catalog/delivery.md)、[ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)）。

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

内置引导脚本（`LOADER_VERSION = "3"`、`API_VERSION = 2`）作为首项 `autoload/ModLoader`（`*res://modloader/bootstrap.gd`）在游戏脚本加载前运行，并与外部 `MachinePartyModLoader.exe` 保持 API v2 兼容。

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

## 4. 四级测试与验收规范

| 层级 | 覆盖范围 | 执行命令与通过标准 |
| --- | --- | --- |
| **Tier 0：Godot 本地测试** | 脚本语法、玩法逻辑自测、UI 封面截图 | 1. 使用 Godot 4.5.2 headless `--check-only --script` 检查独立脚本语法（继承 `"res://..."` 的覆写脚本标注待游戏运行时加载）。<br>2. 运行 `--self-test` 验证物理移动、碰撞击退、安全间隔底线、预设组合与积分同分逻辑，确认输出 `SELF_TEST_PASSED`。<br>3. 生成 `1280×720` 封面截图至 `apps/desktop/ui/images/<id>.png` 并人工审图。 |
| **Tier 1：打包、契约与 Lint** | 确定性 ZIP、边界隔离、目录契约、文档链路、Rust 规范 | 执行 `node scripts/pack-mod.mjs --all --verify-catalog`、`npm run check:architecture`、`npm test`、`npm run lint:rust`。自动校验 ZIP `size`/`sha256` 完全吻合、`mod.json` 与 `catalog/mods.json` 版本/ID 一致、`mods/<id>/README.md` 非空、`requiredFiles` 完整、R2 Worker 下载测试以及三语文档与相对链接有效。 |
| **Tier 2：Rust L1 与 L3 实包模拟** | ZIP 解压、GDPC v3 注入/还原、事务引擎 | 执行 `npm run test:rust`（覆盖 `pck_loader`、`installer`）。在 macOS 本地可用未提交的原版 Steam v2.1.2 `Machine Party.pck` 隔离副本执行 `MPM_L3_VANILLA_PCK="/path/to/Machine Party.pck" npm run test:rust`，验证写入与原版 SHA-256 无损还原。 |
| **Tier 3：Windows Steam 实机验收** | 正式开放安装前的硬性门禁（**`verified: true` 前置条件**） | 在 Windows + Steam `v2.1.2` 完成：桌面端经 Worker 下载并校验 SHA-256 安装 -> Steam 启动游戏 -> 大厅参数/轮换/多人 RPC 联机对局 -> 离线卸载确认原版 `Machine Party.pck` SHA-256 还原 -> 与外部 MPML 共存及与直接 PCK 补丁模组互斥测试。 |

## 5. 目录接入与桌面端集成

新增自研模组到目录与 R2/Worker 分发体系的步骤：

1. 在 `mods/<id>/` 备齐 `README.md`、`mod.json`、运行时脚本，并在 `apps/desktop/ui/images/<id>.png` 放置封面图。
2. 运行 `node scripts/pack-mod.mjs <id>` 获取确定的 `filename`、`size`、`sha256` 与 `files` 列表。
3. 在 [`catalog/mods.json`](../../../catalog/mods.json) 新增条目：
   - 填写唯一的 `id` 和 `order`、来源 `repo`（例如 `"JamesGZM/machine-party-mod-manager"`）、`image` 与 `"version": "v<mod.json.version>"`。
   - 同一仓库的新增模组使用 `"inventoryById": true` 建立独立安装记录，见 [ADR-010](../architecture/ADR-010-shared-repository-mods.md)。
   - 填写 `"package"`：唯一数字字符串 `assetId`（如 `"1001"`）、`scripts/pack-mod.mjs` 输出的 `filename`、`size`、`sha256`，以及 `"mirrorApproved": true`。
   - 设置 `supportedGameVersions` 与对应桌面预览版号的 `windowsPreview`，通过 Tier 3 前保持 `"verified": false`。
   - 配置 `adapter`：`kind: "loader-files"`、`platforms: ["windows"]`、`target: "pckDir"`、`touches: ["mods"]`、`exclusive: "loader"`、`autoLoader: true`、`upstreamUninstall: false`、原版 `baseline` 指纹以及精确对应的 `requiredFiles` 列表。
   - 补全 `zh-CN`、`zh-TW`、`en` 三语的 `name`、`summary`、`detail` 与 `aliases`。
4. 同步更新 [`mods/README.md`](../../../mods/README.md) 列表。
5. 无需也不会增加任何特殊界面逻辑：所有模组在卡片角标、详情弹窗与 Worker 下载 -> 校验 -> 安装流程中表现完全一致。

## 6. 确定性 ZIP 打包与 R2 / Worker 发布

- **跨平台确定性打包**：[`scripts/pack-mod.mjs`](../../../scripts/pack-mod.mjs) 按字典序收集非排除文件，采用 `ZIP_STORED`（method `0`）与固定 DOS 时间戳（`1980-01-01 00:00:00`）生成 ZIP，确保在 macOS、Linux 与 Windows 下产出的字节与 SHA-256 完全一致。
- **CI 自动上传 R2 并部署 Worker**：运行 `.github/workflows/catalog-worker.yml` 时，流水线会自动执行 `node scripts/pack-mod.mjs --all --verify-catalog --out "$RUNNER_TEMP/packages"`，将缺失的 `packages/sha256/<sha256>.zip` 上传至 R2（`machine-party-mods`），校验所有 `mirrorApproved` 对象的 `ContentLength`，再上传 `catalog/revisions/<revision>.json`、部署 `services/catalog-worker` 并验证线上 `HEAD /v1/downloads/...` 返回 200。
- **更新已发布自研模组**：提升 `mods/<id>/mod.json` 版本号后，重新执行 `node scripts/pack-mod.mjs <id>`，同步更新 `catalog/mods.json`（`revision`、`version`、`package.assetId`/`filename`/`size`/`sha256`）与 `mods/<id>/README.md`，推送到 `main` 后重新触发 `Deploy mod catalog Worker` 即可（仅更新桌面客户端本体时再走[发布管理器更新](releasing.md)）。

## 相关文档

- [ADR-009：自研模组、R2 确定性打包与自管加载器规范](../architecture/ADR-009-bundled-first-party-mods.md)
- [ADR-005：安装事务与原版游戏校验恢复](../architecture/ADR-005-install-transactions.md)
- [ADR-007：模组适配器与 macOS 模拟验证层级](../architecture/ADR-007-mod-adapters.md)
- [正式目录交付方案](../catalog/delivery.md) · [开发指南](README.md) · [自研模组目录索引](../../../mods/README.md) · [滚筒嘉年华 README](../../../mods/roller-carnival/README.md)
