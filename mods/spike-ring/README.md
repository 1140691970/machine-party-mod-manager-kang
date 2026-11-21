# 尖刺圆环 / Spike Ring `v0.1.0`（测试版）

> 2–8 人（**不写死上限**）联机 · 俯视 2.5D 圆形机械竞技场 · 服务器权威 60 秒生存赛
> 引擎：**Godot 4.5.2 / GDScript**，作为《Machine Party》`v2.1.2` 的 **MPML API v2 加载器模组**运行。
> 本项目已确定引擎，因此不是"通用伪代码"，而是可直接打包安装、可在 Godot headless 自测的真实模组。
> 风格：黄铜齿轮 / 蒸汽管道 / 霓虹警示灯 / 边缘尖刺 / 激光栅栏 / 外围工厂平台 —— **全部复用游戏内已有素材**。
> 机关（v0.1.4）：**纯激光**，移除喷火与滚动电锯；每次成束 2–4 条线并发；场地四周改为暖色工业环境而非黑底；相机收紧、角色放大。

本模组按 `bubble-blitz` 小游戏模板搭建：`main.gd` 入口、`official_minigame.gd` 官方 `Minigame` 子类、4 个**逐字节相同**的通用覆写脚本、`config.gd` 数据驱动配置、`arena_meshes.gd` 素材构建、`spike_ring_game.gd` 玩法层。**游戏主流程覆写脚本未做任何修改**，仅新增玩法文件。

---

## 1. 一页式玩法设计说明

| 环节 | 规则 |
| --- | --- |
| 进入对局 | 所有玩家在**场地中心区域随机、无重叠**出生；人数完全由 `PlayerManager.player_presences` 决定，2–8 人及更多均可。 |
| 准备倒计时 | **服务器统一计时 3 秒**，UI 显示「准备中 3 / 2 / 1」。期间**不生成任何机关**；玩家可 WASD 移动、Space 跳跃熟悉操作；**不会因边缘尖刺/机关/推人出局**（位置还会被钳制在场内）；**左键推人禁用**。 |
| 正式计时 | 3 秒结束后服务器启动 **60 秒**计时与机关生成器，玩家进入可出局状态，推人解锁。准备与正式倒计时都由服务器广播，客户端只做表现。 |
| 场地 | 圆形平面，边缘为尖刺墙。玩家碰撞体中心到圆心距离 `> 场地半径 − 玩家半径` 即出局。 |
| 操作 | WASD 移动、鼠标控制朝向、鼠标左键推人、Space 跳跃。 |
| 视角 | **正上方俯视全景**：相机对准场地中心并按窗口尺寸自适应高度，任意分辨率下完整看到整个圆形场地（含边缘尖刺墙）；地面无透视畸变，场地显示为完美正圆。v0.1.4 收紧留白（16:9 高度约 28.7 m，原 32.7 m）并把工人 rig 由 0.28 放大到 **0.44**，角色明显变大。 |
| 方向 | WASD 严格按屏幕方向：**W = 屏幕正上方（世界 -Z）、S = 下、A = 左、D = 右**；输入经「当前相机的屏幕基向量」换算为世界 XZ 方向，即使相机角度变化也不会前后左右错位。 |
| 机关 | **纯激光栅栏**（v0.1.4 起移除喷火与滚动电锯）：每次成束生成 **2 / 3 / 4 条**近似平行的激光线（按难度阶段），0.55–0.85 s 红色预警带，激活 1.0–1.6 s，线宽 0.52 m 并带贴地辉光；正常跳跃（净空 0.62 m < 跳跃高度 1.08 m）可越过，也可在多条线之间的走廊横向躲避。同时最多 6 条线；同一束共享基准法向、逐条过安全生成器，绝不形成无解封锁。 |
| 推人 | 左键在 2.1 m / 半角 45° 扇形内检测最近目标；**服务器判定命中**；目标进入**摔倒状态固定 0.30 秒**后爬起，期间不能移动；爬起后 **0.20 秒免推**防锁死；推力方向为施放者→目标；施放者冷却 **1.5 秒**。被推玩家撞到边缘或机关同样出局。 |
| 计分 | 正式计时开始后**每存活 1 秒 +1**（服务器按整秒累计）；出局即停止计分、已得分保留；每次成功推倒**施放者 +2**、被推者不扣分；60 秒结束仍存活额外 **+10**。排名：总分 → 存活时长 → 推人命中 → 受击次数（少者优先）。 |
| 结算 | **必须**满足「所有玩家都已出局」**或**「60 秒倒计时结束」才进入本轮结算；出局玩家进观战、不中途复活、保持全景视角。结算显示总分、存活时长、推人命中、出局原因、本轮排名。 |
| 下一关 | 官方框架按 `total_rounds` 开启下一轮，`initialize(current_round, …)` 的轮次号索引 `ROUND_CONFIGS`，切换生成间隔、每束线数、并发上限、速度倍率与配色；**始终强制"可躲"**。 |
| 公平性 | 机关可随机，但「机关安全生成器」会网格化模拟未来 2 秒危险区、对每个存活玩家做 BFS 可达性与 ≥1.2 m 逃生通道检查、验证安全区连通性；失败则取消/延迟/重随机，**绝不生成无解组合**。随机使用服务器种子，所有客户端方向、时间、位置一致。 |

---

## 2. 可调参数表

全部集中在 `config.gd`，改这一个文件即可调平衡；新增一关只需往 `ROUND_CONFIGS` 追加一条。

| 分类 | 参数 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 场地 | `ARENA_RADIUS` | `12.0 m` | 圆形场地半径 |
| | `PLAYER_RADIUS` | `0.42 m` | 玩家碰撞半径 |
| | `EDGE_LIMIT_RADIUS` | `11.58 m` | 出局阈值 = 半径 − 玩家半径 |
| | `SPAWN_CENTER_RADIUS` | `4.2 m` | 中心随机出生区 |
| | `SPAWN_MIN_SEPARATION` | `1.35 m` | 出生点最小间距 |
| 相机 | `CAMERA_FOV` | `50.0°` | 正俯视透视相机垂直 FOV |
| | `CAMERA_FIT_RADIUS` | `13.0 m` | 需完整入镜半径 = 场地半径 + 1.0 m（收紧留白） |
| | `CAMERA_FIT_MARGIN` | `1.03` | 额外留白（原 1.12） |
| | `CAMERA_MIN_HEIGHT` | `22.0 m` | 高度下限；实测 16:9 约 28.7 m（原 32.7 m） |
| 角色 | `PLAYER_VISUAL_SCALE` | `0.44` | 官方工人 rig 视觉缩放（原 0.28，放大 1.57×） |
| | `PLAYER_LABEL_HEIGHT` | `2.55 m` | 名牌 / 血条高度随角色上移 |
| 环境 | `build_surroundings()` | — | 外围工厂平台：重锈 / 螺纹板地板、霓虹环、16 条管道、8 组静态齿轮、12 盏警示灯与暖色点光；背景色深棕 `0.13/0.085/0.065` |
| 移动 | `PLAYER_MOVE_SPEED` | `5.2 m/s` | 水平速度 |
| | `PLAYER_JUMP_VELOCITY` / `PLAYER_GRAVITY` | `6.4` / `19.0` | 跳跃初速 / 重力 |
| | `PLAYER_JUMP_HEIGHT` | `1.08 m` | `v²/2g`，激光高度必须小于它 |
| 推人 | `PUSH_RANGE` | `2.1 m` | 扇形检测半径 |
| | `PUSH_HALF_ANGLE_COS` | `0.7071` | 半角 45° |
| | `PUSH_COOLDOWN_SEC` | `1.5 s` | 推人冷却 |
| | `PUSH_KNOCKBACK_SPEED` | `7.6 m/s` | 击退速度 |
| | `FALL_DURATION_SEC` | **`0.30 s`** | 摔倒固定时长（硬约束） |
| | `RECOVERY_IMMUNITY_SEC` | **`0.20 s`** | 爬起免推（防锁死） |
| | `PUSH_SCORE` | `+2` | 每次命中奖励 |
| 计时 | `PREP_DURATION_SEC` | `3.0 s` | 3-2-1 准备 |
| | `ROUND_DURATION_SEC` | `60.0 s` | 正式计时 |
| | `SCORE_PER_SECOND` / `SCORE_SURVIVAL_BONUS` | `+1` / `+10` | 计分参数 |
| 激光（唯一机关） | `HAZARD_LASER_ONLY` | `true` | 移除喷火与滚动电锯，全部机关为激光 |
| | `LASER_WARN_MIN/MAX` | `0.55 / 0.85 s` | 预警区间（缩短以提高难度） |
| | `LASER_ACTIVE_MIN/MAX` | `1.0 / 1.6 s` | 激活区间（延长以形成激光网） |
| | `LASER_WIDTH` / `LASER_CLEAR_HEIGHT` | `0.52 m` / `0.62 m` | 扫描线宽 / 可跳净空 |
| 生成 | `HAZARD_MAX_CONCURRENT` | `6` | 同时激活激光线上限（原 2） |
| | `LASER_BURST_MIN/MAX` | `2 / 4` | 每次成束生成线数的下限 / 上限 |
| | `HAZARD_TYPE_COOLDOWN_SEC` | `0.0 s` | 单一类型不自冷却，避免多线束被节流 |
| | `HAZARD_MIN_PLAYER_DISTANCE` | `1.5 m` | 玩家近身禁止立即生成 |
| | `SAFETY_HORIZON_SEC` | `2.0 s` | 危险区模拟时长 |
| | `SAFETY_RETRY_MAX` | `8` | 失败重随机次数 |
| | `GRID_CELL` | `0.6 m` | 安全网格边长 |
| | `SAFE_CORRIDOR_MIN_WIDTH` | `1.2 m` | 逃生通道最小宽度 |
| 同步 | `SNAPSHOT_INTERVAL_SEC` | `0.05 s` | 20 Hz 快照 |
| | `INTERP_DELAY_SEC` | `0.10 s` | 客户端插值缓冲 |
| | `LAG_COMPENSATION_SEC` | `0.12 s` | 服务器危险判定回溯窗口 |
| | `HIT_FORGIVENESS` | `0.12 m` | 危险带收缩，宁可漏判不误杀 |

### 难度曲线（三段，`DIFFICULTY_PHASES`）

| 时段 | 阶段 | 生成间隔 | 每束线数 | 并发上限 | 速度倍率 | 权重（激光） |
| --- | --- | --- | --- | --- | --- | --- |
| 0–15 s | `WARMUP` | 2.4 s | 2 | 2 | 0.90 | 1.0 |
| 15–35 s | `MIXED` | 1.5 s | 3 | 4 | 1.00 | 1.0 |
| 35–60 s | `FRENZY` | 1.0 s | 4 | 6 | 1.15 | 1.0 |

`DIFFICULTY_PHASES.weights` 恒为 `{flame:0, saw:0, laser:1}`；`difficulty_phase()` 在 `HAZARD_LASER_ONLY` 下再次强制归零 flame/saw，关卡 `weights_bias` 也全为 0 —— 无论怎么调配置都不会再冒出喷火/电锯。

### 关卡配置（`ROUND_CONFIGS`，数据驱动）

| 关卡 | id | 间隔倍率 | 速度倍率 | 每束线数加成 | 主题色 |
| --- | --- | --- | --- | --- | --- |
| 1 | `brass_foundry` 黄铜铸造厂 | 1.00 | 1.00 | +0 | 琥珀黄铜 |
| 2 | `sawmill` 棱镜车间 | 0.88 | 1.08 | +1 | 警示红 |
| 3 | `laser_vault` 激光熔炉 | 0.76 | 1.18 | +1 | 霓虹金 |

超过 3 关按 `(round-1) % 3` 循环；`default_rounds = 2`（可在自定义歌单里调大）。

---

## 3. 玩家状态机

```
                ┌────────────────────── 3s 准备结束（服务器广播） ──────────────────────┐
                │                                                                        ▼
            [ READY 准备 ] ───────────────────────────────────────────────────► [ NORMAL 正常 ]
            可移动 / 可跳跃                                                          ▲   │
            推人禁用 / 不出局                                                        │   │ Space
            不生成机关                                                              │   ▼
                                                                             [ JUMPING 跳跃 ]
                                                                                  │   │ 落地
                                                                                  │   ▼
   命中← 左键服务器判定 ──► [ FALLEN 摔倒 0.30s ] ──爬起──► [ INVULN 无敌 0.20s ] ──► [ NORMAL ]
     （期间不能移动，仅被击退）      （免推窗口，防锁死）

     [ READY / NORMAL / JUMPING / FALLEN / INVULN ]
        └─ 边缘尖刺 / 激活中的激光线 ──► [ OUT 出局 ] ──► [ SPECTATOR 观战 ]
                                                     停止计分、不复活、全景观战
```

状态常量：`ST_READY / ST_NORMAL / ST_JUMPING / ST_FALLEN / ST_INVULN / ST_OUT / ST_SPECTATOR`。
`INVULN` 与 `NORMAL` 行为一致，只多一个 `invuln_timer` 标记免推。
出局判定统一在 `_check_player_collisions()`，只在服务器执行。

---

## 4. 机关安全生成算法（伪代码）

```
FUNC try_spawn(phase):                          # 纯激光：一次成束生成多条线
    budget = phase.max_concurrent - live_hazard_count()
    IF budget <= 0: RETURN DELAY
    want = MIN(budget, phase.burst)             # 2 / 3 / 4 条
    bundle_n = random_unit_vector()             # 整束共享基准法向（±0.14 rad 抖动）
    made = 0
    FOR b IN 1..want:
        FOR attempt IN 1..SAFETY_RETRY_MAX:
            cand = make_candidate(LASER, phase, bundle_n)
            IF safety_check(cand):              # 已提交的线已计入危险网格
                commit(cand); made += 1; BREAK
    IF made == 0: RETURN DELAY                  # 绝不生成无解组合
    RETURN OK

FUNC safety_check(cand):
    # (1) 禁止在玩家 1.5m 内立即生成致命机关
    FOR p IN alive_players:
        IF min_distance(p.pos, cand.future_sweep) < 1.5: RETURN FALSE

    # (2) 网格化 + 未来 2 秒危险区模拟（合并现有机关 + 候选机关）
    grid = {}                                   # cell -> SAFE / DANGER / JUMPABLE
    existing = [h FOR h IN hazards IF h.state != DONE]
    probe = cand with active_start = now + cand.warn, end_time = active_start + cand.active
    FOR h IN existing + [probe]:
        FOR t IN sample(now .. now + 2.0):
            # 纯激光：固定弦带标 JUMPABLE（可跳穿越）；SAW 分支仅为兼容保留，不会触发
            IF h.type == SAW:
                mark_circle(grid, saw_pos(h, t), h.width/2 + player_radius, DANGER)
            ELSE:
                mark_chord(grid, h.n, h.d, h.width/2 + player_radius, JUMPABLE)

    # (3) 每个存活玩家：可达性 BFS + 可站立安全格 + >=1.2m 逃生通道
    reach_steps = floor(cand.warn * move_speed / GRID_CELL)
    FOR p IN alive_players:
        cells = BFS(start = grid_index(p.pos), max_steps = reach_steps,
                    passable = cell != DANGER)        # JUMPABLE 可穿越（跳跃）
        found = ANY c IN cells WHERE grid[c] == SAFE AND has_safe_corridor(grid, c)
        IF NOT found: RETURN FALSE
    # has_safe_corridor: 存在 2x2 全 SAFE 块（0.6m * 2 = 1.2m）

    # (4) 安全区连通性：禁止十字封锁 / 无路可走
    IF NOT connected(grid, passable = cell != DANGER): RETURN FALSE
    RETURN TRUE

FUNC commit(cand):
    h.id = next_id++
    h.warn_start   = srv_time                       # 服务器单调时钟
    h.active_start = srv_time + cand.warn
    h.end_time     = h.active_start + cand.active
    last_type_spawn[h.type] = srv_time
    IF h.type == FLAME: nozzle_cooldown[h.nozzle] = srv_time
    rpc_reliable("_rpc_hazard_spawn", h)            # 全客户端同一条时间线
```

要点：**机关可以随机，但绝不能生成无解组合**。激光线标为 `JUMPABLE`（可跳穿越），单条线不会把场地判成"被切两半"；成束 2–4 条线近似平行、彼此留出走廊，且每提交一条就重做一次 BFS 可达性 + ≥1.2 m 逃生通道 + 连通性检查，任何导致无解的组合都会被拒绝。`DANGER` 硬阻断分支仅为兼容保留，纯激光模式下不会触发。

---

## 5. 联机同步架构说明

**服务器 = 房主（`multiplayer.is_server()`）**，权威项：准备倒计时、正式计时、移动校验、推人命中与击退、机关生成/激活时刻、出局判定、计分、轮次结算。客户端只发输入、只做表现。

| 通道 | 方向 | 可靠性 | 内容 |
| --- | --- | --- | --- |
| `_rpc_client_input` | 客户端 → 服务器（每帧） | `unreliable_ordered` | `dir`、`aim`、`jump` 边沿、`push` 边沿、`seq`；服务器丢弃乱序包 |
| `_rpc_snapshot` | 服务器 → 客户端（20 Hz） | `unreliable_ordered` | `srv_time`、阶段、准备/正式倒计时、每个玩家位置/朝向/状态/分数/存活时长/推倒/受击/冷却/出局原因 |
| `_rpc_hazard_spawn` | 服务器 → 客户端 | **`reliable`** | 机关完整时间线（类型、弦线 `n/d/a/b`、宽度、净空、速度、`warn_start/active_start/end_time`、喷口） |
| `_rpc_elimination` | 服务器 → 客户端 | `reliable` | 出局事件（兜底，快照也会带 `alive=false`） |
| `_rpc_round_result` | 服务器 → 客户端 | `reliable` | 结算排名明细 |

**同步内容覆盖**：玩家位置、朝向、状态、跳跃、推人冷却、机关预警、机关激活、准备倒计时、正式倒计时、分数、出局观战、轮次结算。

**表现层**：客户端维护 `_snap_buffer`（最近 8 个快照），按 `render_time = srv_time_est − 0.10s` 在相邻两帧间插值，本地玩家额外用最后速度做**限幅外推**（最多 0.12 s），再用指数平滑趋近，避免抖动。客户端 `_srv_time_est` 由每次快照的 `srv_time` 前推，机关阶段与玩家共用**同一条服务器时间轴**。

**为什么不会出现「客户端看到已躲开但服务器判出局」**：

1. 客户端**完全不做碰撞/出局判定**，`alive` 只来自服务器快照/可靠 RPC；本地看到的只是插值表现。
2. 机关的预警与激活时刻是**服务器绝对时间**，由 reliable RPC 一次下发；客户端不启动自己的计时器，不会因为掉包而"提前/延后"看到激活。
3. 服务器判定危险时统一回溯 `LAG_COMPENSATION_SEC = 0.12s`，从 `_pos_history` 取玩家**历史位置**做线性插值，而不是用最新位置；相当于给高延迟玩家更多反应余量。
4. 危险带/碰撞半径收缩 `HIT_FORGIVENESS = 0.12m`，**宁可漏判不误杀**。
5. 客户端输入带 `seq`，服务器丢弃乱序包；AI/掉线席位由服务器按 `multiplayer.get_peers()` 判定；`player_disconnected()` 立即置为出局并停止计分，不中途复活。
6. 随机源只在服务器：`_rng.seed = map_seed` + 可靠 RPC 下发完整机关参数，客户端不自行 roll，保证所有客户端机关方向、时间、位置一致。

**人数不写死**：roster 来自 `PlayerManager.player_presences.keys()`，所有循环用 `_players.keys()` / `.size()`；出生点 `compute_spawns(count, seed)` 支持任意人数（自测覆盖 2/4/8/16）。

---

## 6. 代码文件清单

| 文件 | 打包 | 来源 / 作用 |
| --- | --- | --- |
| `mod.json` | ✅ | 模组清单 `spike-ring` / `0.1.0` / `main.gd` |
| `main.gd` | ✅ | 入口：hub 注册（**真实槽位 BurnRecycle = 17**）、场景/图标替换原版资源、三语文案、脚本注册、场景打包、默认歌单条目 |
| `official_minigame.gd` | ✅ | 原样复用模板：官方 `Minigame` 子类，`initialize` / `player_loaded` / `host_loaded` / `_finish` |
| `override_game.gd` | ✅ | **原样复制**（与 `bubble-blitz`、`roller-carnival` 字节一致）通用 hub 驱动 |
| `override_local_game.gd` | ✅ | 同上 |
| `override_playlist.gd` | ✅ | 同上 |
| `override_picker.gd` | ✅ | 同上 |
| `config.gd` | ✅ | **新写**：参数表、难度曲线、轮次配置、几何/网格/计分工具 |
| `arena_meshes.gd` | ✅ | 复制模板 1084 行（角色 rig、材质、字体、动画、PCK 挂载）+ **追加**圆形场地/机关/图标/外围工厂环境函数；角色缩放与名牌高度参数化 |
| `spike_ring_game.gd` | ✅ | **新写**：状态机、3s 准备、60s 计时、推人、机关生成器 + 安全生成器、出局、计分、结算、RPC 同步、HUD、`--self-test` |
| `README.md` | ❌ | 本文档（打包脚本自动排除 `*.md`） |
| `project.godot` | ❌ | 本地 Godot 预览工程 |
| `spike_ring_scene.tscn` | ❌ | 本地预览主场景（`*_scene.tscn` 自动排除） |

**复用游戏内已有素材**（`arena_meshes.gd` / `spike_ring_game.gd` 里的 `res://` 路径）：
- 纹理：`chisel gauntlet art2` 螺纹板 / 桶、`dvd roomba` 金属板 / 地板 / 格栅 / 墙面、`escalator pit` 粉碎机、`junk platform` 重锈、`forklift certified` 管道与箱子、`smoke break` 木箱、`scorch_01` 焦痕、`explosion_mark` 等
- 角色：`res://minigames/exploding_collar_race/models/main character2/main character2.glb` 官方工人 rig + 站立/爬行/被推/摔倒动画
- 字体：`res://fonts/Terminal F4.ttf`（CRT 监视器、名牌、HUD）
- 音效：`disco dodge` 推人/坠落、`exploding collar race` 预警、`airplane ding`、`ekg_beep`、`bad_explosion`、`dvd roomba ambience`
- 粒子：`res://prefabs/managed_effects/` 的 `hit_blood` / `dustplume`

---

## 7. 关键代码索引

| 需求 | 位置 |
| --- | --- |
| 3 秒准备倒计时（不生成机关/不推人/不出局） | `spike_ring_game.gd` → `_step_prep()`；`_step_player_motions(delta, prep=true)` 里钳制位置并跳过推人与碰撞 |
| 60 秒服务器计时与阶段切换 | `_step_simulation()` / `_step_prep()` → `PH_PREP → PH_LIVE → PH_ENDED` |
| 玩家控制与状态机 | `_read_local_input()`（WASD / 鼠标反投影朝向 / 左键边沿 / Space 边沿）、`_step_player_motions()`、`_state_allows_push()` |
| 俯视全景相机（完整入镜 / resize 重框定） | `_camera_fit_height()` / `_frame_arena()` / `_on_viewport_resized()`；`_setup_environment()` 里 `current = true` |
| 角色放大 / 外围暖色工厂环境 | `config.gd:PLAYER_VISUAL_SCALE / PLAYER_LABEL_HEIGHT` → `arena_meshes.gd:build_worker_character()` / `build_surroundings()`；`_setup_environment()` 暖色 `Environment`；`_setup_match_local()` 挂载 |
| WASD 屏幕方向对齐 | `_screen_dir_to_world()` + `_read_local_input()`；`_mouse_aim()` 用当前相机反投影朝向 |
| 推人（命中 / 0.3s 摔倒 / 0.2s 免推 / 1.5s 冷却 / +2） | `_try_push()` + `_step_player_motions()` 的 `ST_FALLEN` 分支 |
| 机关生成器（纯激光 / 每束 2–4 条 / 逐条安全检查） | `_step_spawner()`（成束 + 共享法向）/ `_make_candidate(bundle_n)` / `_commit_hazard()`；`config.gd:HAZARD_LASER_ONLY` / `LASER_BURST_*` / `DIFFICULTY_PHASES.burst` |
| 机关时间线同步 | `config.gd:hazard_params()` → `@rpc _rpc_hazard_spawn(h)` → `_update_hazard_states(t)` |
| 机关安全生成器 | `_build_danger_grid()` / `_bfs_reachable()` / `_has_safe_corridor()` / `_safety_region_connected()` / `_safety_check()` |
| 出局判定（边缘 / 激光线 + 延迟补偿） | `_check_player_collisions()` / `_history_position()` / `_eliminate_player()` |
| 计分与排名 | `_accrue_scores()` / `_finish_round()` / `config.gd:rank_entries()` / `official_scores()` |
| 轮次结算门槛 | `_check_round_end()`：`alive_count == 0` 或 `time_remaining <= 0` 才调用 `_finish_round()` |
| 联机同步与插值 | `_broadcast_snapshot()` / `@rpc _rpc_snapshot()` / `_apply_snapshot_interpolation()` |
| 掉线清理 | `player_disconnected()` |
| 观战 | `_update_hud()` 出局提示 + 保持 `_frame_arena()` 的俯视全景相机（不切斜视，仍可看全场） |
| HUD | `_setup_hud()` / `_update_hud()`（准备 3-2-1、60s 倒计时、存活人数、分数、推人冷却、结算排名） |
| 自测 | `_run_self_test()`（输出 `SELF_TEST_PASSED`） |

---

## 8. 验收测试用例

### Tier 0 — Godot headless 自测（本机可跑）

```powershell
$GODOT = "F:\gitee\machine-party-mod-manager-kang\machine-party-mod-manager-kang\.agent\mod-dev\tools\godot\Godot_v4.5.2-stable_win64.exe"
& $GODOT --headless --path "mods/spike-ring" -- --self-test
# 期望：SPIKE_RING_*_OK ... SELF_TEST_PASSED，exit code 0
& $GODOT --headless --path "mods/spike-ring" -- --smoke-test
# 期望：SPIKE_RING_SMOKE_OK hazards>=1 max_live>=2 laser_only=true ... SMOKE_TEST_PASSED（20 秒连续模拟）
```

覆盖：`2/4/8/16` 人出生无重叠且都在场内；准备期推人禁用/无机关/不出局；3 秒后进入 LIVE；摔倒恰好 0.30 s、爬起 0.20 s 免推、推人冷却 1.5 s、命中 +2；每秒 +1、出局后冻结分数；**部分玩家出局不结算**、全出局才结算；排名四项 tie-break；安全生成器接受合法组合、拒绝压在玩家脚下的危险带；三段难度曲线。smoke-test 额外断言「全部为激光」且「至少 2 条线同时激活」。

### Tier 0 补充 — 语法检查与封面审图

```powershell
& $GODOT --headless --path "mods/spike-ring" --check-only --script "res://spike_ring_game.gd"
& $GODOT --path "mods/spike-ring" --windowed --resolution 1280x720 -- "--capture-screenshot=.agent/mod-dev/dist/spike_ring_preview.png"
```

### Tier 1 — 仓库契约

```bash
node scripts/pack-mod.mjs --all --verify-catalog
npm run check:architecture
npm test
```

### 实机（Steam `v2.1.2`，需全员安装同版模组）

> **手动解压的目标目录（测试期唯一方式）**
> `E:\Program Files (x86)\Steam\steamapps\common\party project\Machine Party_Windows\mods\spike-ring\`
>
> ZIP 内是 **10 个平铺文件**（`mod.json` + 9 个 `.gd`），**没有**顶层 `spike-ring/` 文件夹。
> 因此不要直接「解压到 `mods/`」——文件会散落在 `mods/` 根目录，加载器找不到模组。
> 必须先建好 `mods\spike-ring` 子目录，再把 ZIP 内容解压进去：
> ```powershell
> $game = "E:\Program Files (x86)\Steam\steamapps\common\party project\Machine Party_Windows"
> $zip  = "F:\gitee\machine-party-mod-manager-kang\machine-party-mod-manager-kang\.agent\mod-dev\dist\spike-ring-0.1.0.zip"
> Expand-Archive -Path $zip -DestinationPath "$game\mods\spike-ring" -Force
> ```
> 也可以直接把已展开好的 `.agent/mod-dev/dist/spike-ring-0.1.0/` 整个复制成 `mods\spike-ring`（内容与 ZIP 一致，已做 SHA-256 校验）。
> 最终结构应为 `mods\spike-ring\mod.json` + 9 个 `.gd`，与 `mods\bubble-blitz\`、`mods\roller-carnival\` 同级。
> 加载器注入（loader v5）此前已完成，解压后**不需要**再动 `Machine Party.pck`。

1. 先**完全退出游戏**；用管理器安装 `spike-ring`（或按上面的方式手动解压）。
2. Steam 启动 → 自定义歌单/街机/默认轮换里应出现「尖刺圆环」；查 `%APPDATA%\Godot\app_userdata\Machine Party\modloader.log` 确认 `spike-ring: initialized via multi-minigame hub (slot BurnRecycle=17)`。
3. **2 人房**：确认 3-2-1 期间推人无效、无机关、走到边缘不出局；3 秒后开始 60 秒计时并出机关。
4. **8 人房**（可用 Lobby Bots 补位）：确认全部玩家中心无重叠出生、存活人数/分数 HUD 正确、机关预警灯与红色警示带先于激活出现。
5. **推人**：确认命中目标摔倒 0.3 s、期间不能移动、爬起后 0.2 s 内再推无效、施放者冷却 1.5 s、+2 分。
6. **机关（纯激光）**：确认每束同时出现 2–4 条红色预警带与激光线、可用 Space 跳过或在走廊横向躲；同时激光线不超过 6；不再有喷火与滚动电锯；观察是否出现"无路可走"（应永不出现）。
7. **出局与观战**：出局后停止计分、进入全景观战、不复活；**只剩 1 人时本轮仍继续**（必须等 60 秒或全灭）。
8. **结算**：核对总分 = 存活秒数 + 2×推倒 + (存活到终局 ? 10 : 0)；排名按四项 tie-break；显示存活时长、推人命中、出局原因、排名。
9. **下一关**：第 2 轮应切换到 `sawmill`「棱镜车间」配置（间隔更短、每束线数 +1）。
10. **一致性**：主机与客户端机关方向/时刻一致；高延迟下不应出现"客户端已躲开却被判出局"。
11. **视角完整**：任意窗口尺寸 / 全屏下，圆形场地（含边缘尖刺墙）完整入镜、不被裁切，且显示为无畸变正圆；改变窗口大小后仍完整。
12. **方向正确**：W / A / S / D 分别对应屏幕的上 / 左 / 下 / 右，斜向组合（如 W+D）方向也正确；相机角度变化时 WASD 仍与屏幕对齐。
13. **角色大小**：角色明显比旧版大、名牌不遮挡头部，圆形场地仍完整入镜无裁切。
14. **四周环境**：场地外不再是纯黑，可见重锈 / 螺纹板地板、霓虹环、径向管道、静态齿轮与红色警示灯；暖色氛围与机械狂欢一致。
15. **离线卸载**：关闭游戏后用管理器卸载，校验 `Machine Party.pck` 还原为原版 SHA-256。

---

## 9. 测试版已知限制（供你试玩后提修改意见）

- 槽位占用原版 `BurnRecycle = 17`（会替换该原版小游戏），与滚筒嘉年华 6、泡泡爆破 8 共存。场景与图标通过 `take_over_path` 挂到原版 `res://minigames/burn_recycle/burn_recycle.tscn` 与 `minigame icon_burn recycle.png`，因此歌单、CRT 选择器与 Overtime 等覆盖包都走官方流程。早期版本用的高位槽 100 会被 Overtime 判为无效并回退到凿刻考验，已弃用。
- 观战为固定俯视全景（可看全场），暂未提供手动切换/自由旋转视角按键。
- 机关视觉是几何 + 发光材质 + 贴地辉光 + 原版焦痕/烟雾纹理，未使用原版激光粒子场景（游戏内是否存在对应 prefab 待实机确认）。
- 摔倒反馈目前是角色倾斜 + 名牌变化，未播放原版 `shoved_main.res`（动画名需实机核对）。
- `default_rounds = 2`，第一版方便体验两关难度变化；正式发布时可改回 1。
- 出局原因目前只会是 `EDGE_SPIKES` / `LASER` / `DISCONNECTED`（`FLAME` / `SAW` 常量保留但纯激光模式不再产生），UI 未做三语映射。
- 桌面端管理器目录：v0.1.4 起 `app.js` 会把 exe 内置目录（含本模组）合并进远程签名目录，因此即使线上 Worker 尚未发布也能显示；若点卡片「安装」会走远程下载（Worker 未发布时 404），测试期请继续按第 8 节的说明手动解压 ZIP 到 `E:\Program Files (x86)\Steam\steamapps\common\party project\Machine Party_Windows\mods\spike-ring\`。

---

## 10. 安装与本地调试

```powershell
# 打包（确定性 ZIP，输出 JSON 摘要）
node scripts/pack-mod.mjs spike-ring
# 落盘到指定目录
node scripts/pack-mod.mjs spike-ring --out .agent/mod-dev/dist

# 本地预览（8 人 AI 混战，无需进游戏）
& $GODOT --path "mods/spike-ring" --windowed --resolution 1280x720
```

`project.godot` 可设 `MP_PCK_PATH` 指向本机 `Machine Party.pck` 以加载原版素材；不设时自动退化为纯色几何，玩法逻辑不受影响。

按 `AGENTS.md`：`catalog/mods.json` 中本条目保持 `"verified": false`，通过 Tier 3 Windows Steam 实机验收后才改为 `true`。
