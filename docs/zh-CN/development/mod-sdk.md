# MPM 模组开发 SDK 与公开运行时契约

[English](../../en/development/mod-sdk.md) · **简体中文** · [繁體中文](../../zh-TW/development/mod-sdk.md)

本参考手册定义 [`mpm_bootstrap.gd`](../../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd)、[`mpm-core`](../../../mods/mpm-core/README.md) 与 [`team-party`](../../../mods/team-party/README.md) 向模组公开的**版本化稳定契约**，以及 [ADR-018](../architecture/ADR-018-mod-development-sdk.md) 规划中的 SDK 能力。打包规则、性能红线与目录准入流程详见 [mod-development.md](mod-development.md)。

---

## 1. 现行稳定公开契约（已可用）

### 1.1 MPML 引导加载器 API v2（`API_VERSION = 2`）

每个继承 `Node` 的模组入口（`main.gd`）都会在 `_mod_init(loader)` 与 `_mod_ready(loader)` 收到 `loader` 实例。调用前应先用 `loader.has_api("<name>")` 或 `loader.has_method("<name>")` 检查能力，以同时兼容内置加载器与外部 `MachinePartyModLoader.exe`。

| 分类 | 可用方法 | 说明 |
| --- | --- | --- |
| **脚本与资源** | `compile`、`register_script`、`override_script`、`override_script_rel`、`register_autoload`、`register_global_class`、`mount_assets` | 内部子脚本须注册在专属前缀 `res://mods_<snake_id>/...` 下，防止跨模组冲突。 |
| **场景与节点挂载** | `on_scene_script`、`on_node_added`、`on_main_menu`、`on_lobby` | 在 `on_node_added` 中优先以 `node.get_script() == null` 快速跳过普通节点。 |
| **查询与共享注册表** | `dir_of`、`has_mod`、`mod_list`、`open_mods_folder`、`is_local_couch`、`game_mode`、`registry`、`note`、`api_version`、`loader_version`、`has_api` | `registry(name)` 返回跨模组共享的可变 `Dictionary`。 |

### 1.2 `Engine` Meta 与共享注册表契约

| 键名 | 维护方 | 载荷与用途 |
| --- | --- | --- |
| `&"mpm_core"` | `mpm-core` | `{ version, hub_version, node, event_bus, locale, lobby_ui }`（同时写入 `loader.registry("mpm_core")`）。 |
| `&"mpm_lobby_ui_coordinator_v2"` | `mpm-core` | 协调器 v2 运行时为 `true`，通知 `mpm_bootstrap.gd` 跳过旧版大厅防重叠排布。 |
| `&"mpm_team_party"` | `team-party` | `{ enabled, team_count, team_format, teams, node }`（同时写入 `loader.registry("team_party")["state"]`）。 |
| `&"mpm_player_spotlight_active"` | `player-spotlight` | 聚光灯启用时为 `true`，`team-party` 据此保留本地主角名牌颜色。 |
| `&"mpm_local_player"` | 小游戏关卡 / 角色 | 挂在本地真人 3D 角色节点上，供 `player-spotlight` 自动接管。 |
| `&"mpm_native_team_stage"` | 自研小游戏 | 由 `team_support.begin_match(stage, roster)` 设置，`team-party` 据此渲染状态栏且不做源码重写包装。 |
| `&"mpm_custom_team_game"` | 小游戏父节点 | 原生组队激活时为 `true`，关闭 `team-party` 对原版关卡的提前胜出轮询。 |
| `&"mpm_team_scores_applied"` | 小游戏父节点 | `team_support.mark_scores_applied` 调用后置为 `true`，避免重复同步分数。 |
| `_mpm_custom_minigames` | Hub 模组 / `mpm-core` | 槽位 ID → 小游戏描述 `{ mod_id, slot_id, scene_path, packed_scene, icon_texture, default_rounds, display_name, brief_content, controls_data }`。 |
| `_mpm_custom_minigames_hub` | Hub 模组 / `mpm-core` | `{ version, installed_paths, cached_overrides, node_hook_installed }`。 |

### 1.3 `mpm-core`（`v0.1.0`）运行时服务

模组可读取 `Engine.get_meta(&"mpm_core")`（未安装时应安全降级）：

- **`event_bus`**：`on(topic: String, cb: Callable)`、`once(topic: String, cb: Callable)`、`off(topic: String, cb: Callable)`、`emit_event(topic: String, payload: Dictionary = {})`、`clear()`，自动清理失效回调。
- **`locale`**：`is_tw_locale(loc = "") -> bool`、`is_cn_locale(loc = "") -> bool`、`pick(en, cn, tw) -> String`。
- **`lobby_ui`**（协调器 v2）：通过 `register_panel(ctrl: Control)` 注册大厅悬浮面板，在不改动原版按钮的前提下避免重叠加叠。
- **`minigame_sdk`**：提供 `register_minigame(spec: Dictionary, loader = null)` 与 `unregister_minigame(mod_id: String, loader = null)`，未指定 `slot_id` 时自动分配 Hub v2 动态高位槽位（`>= 1000`）。
- **`create_fx_pool`（`MpmFxPool`）**：提供 `register_pool(kind, parent, factory, capacity)`、`warmup(kind = "")`、`acquire(kind, duration = 0.0, on_release = Callable())`、`release(kind, node)`、`tick(delta)`、`clear()`。
- **`hook_chain`（`HookChain`）**：提供 `add_hook(target, cb, priority = 0) -> id`、`remove_hook(target, id) -> bool`、`hook_count(target) -> int`、`invoke(target, base_fn, args = [])`、`clear()`。
- **Minigame Hub v2（`HUB_VERSION = 2`）**：自动升级并覆盖既有 `HUB_VERSION = 1` 的 Hub 覆写脚本。

### 1.4 原生组队接入契约（`team_support.gd`）

自研小游戏内置 [`mods/_shared/team-support/team_support.gd`](../../../mods/_shared/team-support/team_support.gd)（通过 `node scripts/pack-mod.mjs --sync-shared` 保持单一来源），读取 `&"mpm_team_party"` 并在未安装或关闭 `team-party` 时无痕降级为个人混战。

---

## 2. 稳定性与静态检查规范

1. **编译期安全（对齐 Windows Godot 4.5.2）**：
   - 禁止对无类型 `Dictionary.keys()`、动态 `.call()` 或无类型成员字段使用 `:=` 推断（必须显式声明如 `var ids: Array = ...`）。
   - 禁止在 MPML 动态加载脚本内用 `preload("res://...")` 引用模组内部兄弟脚本；统一使用 `register_script` + `ResourceLoader.load(REG_RES_DIR + rel)` 并保留路径回退。
2. **运行时性能红线**：
   - 禁止在 `_process`、`_physics_process` 或 `node_added` 中调用 `get_property_list()` 或执行周期性全树扫描。
   - 高频特效、贴花与灯光必须使用开局预热的常驻对象池。
3. **干净释放**：
   - 在 `_exit_tree()` 中清空节点引用、断开信号、清理本模组写入的 `Engine` Meta，并在无头测试退出时清理生成的 `.gd.uid`。

---

## 3. SDK 工具链与路线图（见 [ADR-018](../architecture/ADR-018-mod-development-sdk.md)）

- **SDK-1（已可用）**：静态 GDScript 模组 Linter（`scripts/mod-lint.mjs`）已接入 `npm run check:architecture`。
- **SDK-2（已可用）**：提供 `npm run mod -- new|check|catalog-sync` 脚手架 CLI（`scripts/mod-cli.mjs`）及共用 `tests/mods/_harness/`（`mock_loader.gd`、`mock_game_env.gd`）Godot 夹具。
- **SDK-3（已可用）**：在 `mpm-core` 提供 `register_minigame(spec)`（`minigame_sdk.gd`）、`MpmFxPool` 基类（`fx_pool.gd`）及 Hub v2 动态高位槽位（`>= 1000`），替代硬编码 `MinigameIdentifier`。
- **SDK-4（已可用）**：按优先级排序的方法级 `hook_chain`（`hook_chain.gd`）及三款自研小游戏（`roller-carnival`、`bubble-blitz`、`spike-ring`）接入 `mpm-core` 依赖。
