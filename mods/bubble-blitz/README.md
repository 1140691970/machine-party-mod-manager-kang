# Bubble Blitz（泡泡爆破）

`bubble-blitz` 是由 `machine-party-mod-manager` 开发维护的第一方原创 3D 泡泡堂×炸弹人结合版派对小游戏模组（通过 R2 + 目录 Worker 发布 ZIP 套件），接入**多小游戏共存注册中心（Multi-Minigame Coexistence Hub）**并占用原版未使用的 `Globals.MinigameIdentifier.ScavangerChairs = 8` 槽位，可与 [`roller-carnival`](../roller-carnival/README.md) 及未来更多自研小游戏同时安装、共同出现在官方默认轮换、自定义歌单、街机模式、本地同屏与过场 15 格 CRT 抽签池中。

![泡泡爆破小游戏图示](../../apps/desktop/ui/images/bubble-blitz.png)

- **模组 ID**：`bubble-blitz`
- **版本**：`0.1.0`（目录清单对应 `v0.1.0`）
- **授权**：`GPL-3.0-only`
- **目标游戏版本**：Steam Windows `v2.1.2`
- **开发与打包规范**：[自研模组开发、测试、接入与打包规范](../../docs/zh-CN/development/mod-development.md) · [ADR-009](../../docs/zh-CN/architecture/ADR-009-bundled-first-party-mods.md) · [ADR-015](../../docs/zh-CN/architecture/ADR-015-multi-minigame-hub.md)

## 核心玩法与预置规则（开箱即玩）

- **3 滴血结合版机制**：
  - 每名玩家开局拥有 **3 HP**。前 2 次被高压水柱击中时扣除 1 HP 并触发 **1.5 秒无敌闪烁**（防连锁水柱瞬秒）。
  - 最后 1 HP 归零时进入经典泡泡堂**水泡困住状态**（持续 **4 秒**，移速大幅降低）：
    - 期间被任意对手撞到即**立刻戳破淘汰**；
    - 若持有稀有被动道具**救命针（Needle）**，进水泡 1.5 秒内未被戳破将**自动扎破脱困并恢复 1 HP**；
    - 超时或再次被水柱波及则爆裂淘汰。
- **4 套随机多变地图（每局不同）**：
  - 房主每局随机抽取主题与种子，四象限对称生成可炸箱子与隐藏道具，并强制保留每位玩家出生点周围的 L 形 3 格逃生安全区：
    1. **经典车间（Classic Grid）**：标准间隔铆钉铁柱与对称木箱。
    2. **十字通道（Cross Factory）**：中央宽阔十字大道，快速交火。
    3. **中央金库（Loot Vault）**：中心 3×3 高价值金箱（必掉强力道具），四周铁柱掩护。
    4. **传送带车间（Conveyor Belt）**：循环工业传送带，放到上面的水泡会顺着轨道自动滑向对面。
- **动态人数自适应（2–16 人）**：
  - 2–4 人使用 `15×11` 竞技场，5–8 人扩展为 `17×13`，9–16 人扩展为 `19×15`。
- **道具池与 25 秒压板缩圈**：
  - 炸开木箱/金箱掉落 5 种道具：`泡泡+1`、`威力+1`、`移速+1`、`踢泡泡`（被动撞击踢飞水泡）、`救命针`（稀有被动脱困）。
  - 单局 75 秒，最后 25 秒外圈螺旋落下重型工业压板缩圈（压板无视血量秒杀）。
- **综合计分**：按存活时间与主动困住/戳破对手次数综合排序，提交官方排名积分。

## 操作按键

| 按键 | 功能 |
| --- | --- |
| `W / A / S / D` 或方向键 | 四方向移动（带拐角辅助对齐；拾取「踢泡泡」后撞向水泡即可踢滑） |
| `Space`（空格） | 放置高压水泡（2.4 秒后十字引爆，支持连锁引爆） |

## 文件结构

| 文件 | 打入 R2 ZIP | 职责 |
| --- | --- | --- |
| `mod.json` | 是 | 模组清单与入口声明 |
| `main.gd` | 是 | MPML API v2 入口：注册至多小游戏共存中心（槽位 `ScavangerChairs = 8`） |
| `config.gd` | 是 | 预置参数、4 套随机对称地图生成、动态尺寸与综合计分 |
| `arena_meshes.gd` | 是 | 程序化 3D 工业舞台、水泡、水柱、传送带、道具、压板与 CRT 图标 |
| `bubble_blitz_game.gd` | 是 | 主游戏模拟、房主权威联机同步、AI 预览、`--self-test` 与封面截图 |
| `official_minigame.gd` | 是 | 官方 `Minigame` 信号、参赛名单与结算入口 |
| `override_game.gd` | 是 | 多小游戏共存中心驱动：联机默认/自定义/街机轮换与场景加载 |
| `override_local_game.gd` | 是 | 多小游戏共存中心驱动：本地同屏轮换与场景加载 |
| `override_playlist.gd` | 是 | 多小游戏共存中心驱动：大厅自定义歌单多模组展示 |
| `override_picker.gd` | 是 | 多小游戏共存中心驱动：过场 15 格 CRT 抽签与三语简报 |
| `README.md` / `project.godot` / `bubble_blitz_scene.tscn` / `run_mac.sh` | 否 | 文档与 macOS 本地开发预览/测试辅助脚本 |

## 本地开发、自测与打包

```sh
# 1. macOS 独立试玩（含 3 名 AI 对手）
./mods/bubble-blitz/run_mac.sh play

# 2. 运行 Godot 4.5.2 headless 自测（输出 SELF_TEST_PASSED）
./mods/bubble-blitz/run_mac.sh --self-test

# 3. 截取 1280x720 封面图
./mods/bubble-blitz/run_mac.sh --screenshot apps/desktop/ui/images/bubble-blitz.png

# 4. 校验打包、多小游戏共存回归测试与全仓契约
node scripts/pack-mod.mjs --all --verify-catalog
npm run check:architecture && npm test
```

## 验证状态

- ✅ macOS Godot 4.5.2 `--self-test`、多小游戏共存回归测试（与 `roller-carnival` 同时加载）及确定性 ZIP 打包校验通过。
- ⏳ Windows + Steam `v2.1.2` 实机联机对局与卸载还原待验收（目录当前保持 `verified: false`）。
