extends RefCounted

## ============================================================================
## Spike Ring / 尖刺圆环 — 可调参数表、数据驱动轮次配置、安全生成工具与计分规则
## ----------------------------------------------------------------------------
## 本文件是唯一的平衡性入口：新增一"关"只需往 ROUND_CONFIGS 追加一条配置，
## 无需改动玩法脚本。所有数值均为服务器权威值，客户端只读快照做表现。
## 引擎：Godot 4.5.2 / GDScript（Machine Party v2.1.2 的 MPML API v2 模组）。
## ============================================================================

# ---------------------------------------------------------------- 1. 场地 / 玩家
const ARENA_RADIUS := 7.0                   # 场地半径（米，原 12.0 → 7.0 缩小躲避区 ~66%）
const PLAYER_RADIUS := 0.42                 # 玩家碰撞半径（米）
const EDGE_LIMIT_RADIUS := 6.58             # = ARENA_RADIUS - PLAYER_RADIUS，越过即出局
const PLAYER_MOVE_SPEED := 5.2              # 水平移动速度（米/秒）
const PLAYER_JUMP_VELOCITY := 6.4           # 起跳初速（米/秒）
const PLAYER_GRAVITY := 19.0                # 重力加速度
const PLAYER_JUMP_HEIGHT := 1.08            # v^2/(2g)，激光/低焰净空必须小于此值
const SPAWN_CENTER_RADIUS := 2.8            # 中心随机出生区半径（原 4.2 → 2.8）
const SPAWN_MIN_SEPARATION := 1.15          # 出生点最小间距（无重叠）
const SPAWN_MAX_TRIES := 400                # 拒绝采样上限，超限走环形兜底

# ---------------------------------------------------------------- 1b. 相机 / 视角（俯视全景）
const CAMERA_FOV := 60.0                    # 正俯视透视相机垂直 FOV（度，原 50 → 60 视角更广）
const CAMERA_FIT_RADIUS := ARENA_RADIUS + 0.6  # 需完整入镜半径：含边缘尖刺墙
const CAMERA_FIT_MARGIN := 1.02             # 额外留白
const CAMERA_MIN_HEIGHT := 13.5             # 相机高度下限（米，原 22 → 13.5 拉近一倍）
const PLAYER_VISUAL_SCALE := 0.90           # 官方工人 rig 视觉缩放（原 0.44 → 0.90 放大约 2 倍）
const PLAYER_LABEL_HEIGHT := 2.20           # 名牌 / 血条高度随角色放大下移

# ---------------------------------------------------------------- 2. 推人 / 摔倒
const PUSH_RANGE := 1.8                     # 左键扇形检测半径（米，原 2.1 → 1.8 适配小场地）
const PUSH_HALF_ANGLE_COS := 0.7071         # cos(45°)，半角 45° 的扇形
const PUSH_COOLDOWN_SEC := 1.5              # 推人冷却
const PUSH_KNOCKBACK_SPEED := 7.6           # 击退速度
const FALL_DURATION_SEC := 0.30             # 摔倒固定 0.30 秒爬起（硬约束）
const RECOVERY_IMMUNITY_SEC := 0.20         # 爬起后 0.20 秒免推（防锁死）
const PUSH_SCORE := 2                       # 每次成功推倒 +2 分

# ---------------------------------------------------------------- 3. 玩家状态机
const ST_READY := 0                         # 准备倒计时：可移动/跳跃，不可推人，不可出局
const ST_NORMAL := 1
const ST_JUMPING := 2
const ST_FALLEN := 3                        # 被推摔倒
const ST_INVULN := 4                        # 爬起免推窗口（与 ST_NORMAL 行为一致）
const ST_OUT := 5                           # 出局（停止计分）
const ST_SPECTATOR := 6                     # 观战（自由视角）

# ---------------------------------------------------------------- 4. 计时 / 计分 / 同步
const PREP_DURATION_SEC := 3.0              # 3 秒准备倒计时 3-2-1
const ROUND_DURATION_SEC := 60.0            # 正式计时 60 秒
const SCORE_PER_SECOND := 1                 # 每存活 1 秒 +1
const SCORE_SURVIVAL_BONUS := 10            # 60 秒结束仍存活额外 +10
const SNAPSHOT_INTERVAL_SEC := 0.05         # 服务器 20 Hz 快照
const INTERP_DELAY_SEC := 0.10              # 客户端渲染时间回退（插值缓冲）
const LAG_COMPENSATION_SEC := 0.12          # 服务器危险判定回溯窗口
const HIT_FORGIVENESS := 0.12               # 危险带/半径收缩量，宁可漏判不误杀
const HISTORY_WINDOW_SEC := 1.0             # 位置历史保留时长

# ---------------------------------------------------------------- 5. 机关通用参数
const HZ_FLAME := 0
const HZ_SAW := 1
const HZ_LASER := 2
const HZ_COUNT := 3

const HAZARD_LASER_ONLY := true             # 去掉喷火与滚动电锯，全部机关为激光
const HAZARD_MAX_CONCURRENT := 6            # 同时激活激光线上限（多线并发）
const HAZARD_TYPE_COOLDOWN_SEC := 0.0       # 单一类型不自冷却，否则多线束被节流
const LASER_BURST_MIN := 2                  # 每次生成的最少激光线数
const LASER_BURST_MAX := 4                  # 每次生成的最多激光线数
const HAZARD_MIN_PLAYER_DISTANCE := 1.1     # 禁止在玩家 1.1 米内立即生成致命机关
const SAFETY_HORIZON_SEC := 2.0             # 未来 2 秒危险区模拟
const SAFETY_RETRY_MAX := 8                 # 失败后重新随机方向的最大次数
const GRID_CELL := 0.6                      # 安全网格边长（米）
const SAFE_CORRIDOR_MIN_WIDTH := 1.0        # 逃生通道最小宽度（米）
const SAFE_CORRIDOR_MIN_CELLS := 2          # = ceil(1.0 / 0.6)
const NOZZLE_COUNT := 12                    # 圆周喷火口数量
const NOZZLE_COOLDOWN_SEC := 4.0            # 同一喷火口冷却

const GRID_SAFE := 0
const GRID_DANGER := 1                      # 硬危险（电锯，不可跳）
const GRID_JUMPABLE := 2                    # 可跳跃越过（火焰 / 激光）

const HAZARD_STATE_WARN := 0
const HAZARD_STATE_ACTIVE := 1
const HAZARD_STATE_DONE := 2

# 喷火：低焰长条，可跳跃越过，也可绕开
const FLAME_WARN_MIN := 0.8
const FLAME_WARN_MAX := 1.2
const FLAME_ACTIVE_MIN := 1.2
const FLAME_ACTIVE_MAX := 1.8
const FLAME_WIDTH := 1.5
const FLAME_CLEAR_HEIGHT := 0.55
# 电锯：贴地沿弦线跑，不可跳越，只能横向躲避
const SAW_WARN := 0.8
const SAW_ACTIVE_MAX := 4.0
const SAW_RADIUS := 0.62
const SAW_SPEED := 7.0
const SAW_CLEAR_HEIGHT := 99.0
# 激光：低空扫描线，正常跳跃可越过；v0.1.5 起改为"从一端扫到另一端"
const LASER_WARN_MIN := 0.65
const LASER_WARN_MAX := 0.95
const LASER_ACTIVE_MIN := 0.9               # 仅作为兜底（扫掠模式下由 active_duration 决定）
const LASER_ACTIVE_MAX := 1.4
const LASER_WIDTH := 0.60                   # 加粗，扫掠中的线更醒目
const LASER_CLEAR_HEIGHT := 0.62            # 仍可跳跃越过（PLAYER_JUMP_HEIGHT=1.08）

## 扫掠激光参数（v0.1.5 新增）
const LASER_SWEEP_SPEED := 4.2              # 扫掠平移速度（米/秒，略低于玩家 5.2 → 可躲需预判）
const LASER_SWEEP_ENTRY_PAD := 0.6          # 入场点在场地外多远处开始（保证完全从画面外扫进来）

# ---------------------------------------------------------------- 6. 难度曲线（三段）
## 0-15s 低频简单 / 15-35s 中频混合 / 35-60s 高频但强制可躲。
## weights 为三类机关的生成权重；interval 为生成间隔；speed_scale 作用于机关速度。
const DIFFICULTY_PHASES := [
	{
		"until": 15.0,
		"name": "WARMUP",
		"interval": 2.4,
		"max_concurrent": 2,
		"burst": 2,
		"speed_scale": 0.90,
		"weights": {"flame": 0.0, "saw": 0.0, "laser": 1.0},
	},
	{
		"until": 35.0,
		"name": "MIXED",
		"interval": 1.5,
		"max_concurrent": 4,
		"burst": 3,
		"speed_scale": 1.00,
		"weights": {"flame": 0.0, "saw": 0.0, "laser": 1.0},
	},
	{
		"until": 60.0,
		"name": "FRENZY",
		"interval": 1.0,
		"max_concurrent": 6,
		"burst": 4,
		"speed_scale": 1.15,
		"weights": {"flame": 0.0, "saw": 0.0, "laser": 1.0},
	},
]

# ---------------------------------------------------------------- 7. 轮次 / 关卡配置（数据驱动）
## 每关一条：间隔倍率、速度倍率、并发加成、机关权重偏置、场地配色。
## round_number 从官方 Minigame.initialize 传入，按 (round-1) % size 取用，超出自动循环。
## 配色为 [r, g, b]，运行时由 arena_meshes.gd 构造 Color，避免 const 构造内置对象。
const ROUND_CONFIGS := [
	{
		"id": "brass_foundry",
		"name_zh": "黄铜铸造厂",
		"name_en": "BRASS FOUNDRY",
		"interval_scale": 1.00,
		"speed_scale": 1.00,
		"max_concurrent_bonus": 0,
		"burst_bonus": 0,
		"weights_bias": {"flame": 0.0, "saw": 0.0, "laser": 0.0},
		"accent": [0.96, 0.68, 0.22],
	},
	{
		"id": "sawmill",
		"name_zh": "棱镜车间",
		"name_en": "PRISM WORKS",
		"interval_scale": 0.88,
		"speed_scale": 1.08,
		"max_concurrent_bonus": 0,
		"burst_bonus": 1,
		"weights_bias": {"flame": 0.0, "saw": 0.0, "laser": 0.0},
		"accent": [0.94, 0.36, 0.26],
	},
	{
		"id": "laser_vault",
		"name_zh": "激光熔炉",
		"name_en": "LASER VAULT",
		"interval_scale": 0.76,
		"speed_scale": 1.18,
		"max_concurrent_bonus": 0,
		"burst_bonus": 1,
		"weights_bias": {"flame": 0.0, "saw": 0.0, "laser": 0.0},
		"accent": [0.98, 0.86, 0.28],
	},
]


# ============================================================================
# 工具：难度 / 机关类型选择
# ============================================================================

static func difficulty_phase(elapsed: float, round_cfg: Dictionary) -> Dictionary:
	## 返回当前生效的难度阶段（已叠加本关配置倍率）。
	var base: Dictionary = DIFFICULTY_PHASES[DIFFICULTY_PHASES.size() - 1]
	for raw in DIFFICULTY_PHASES:
		var phase: Dictionary = raw
		if elapsed < float(phase["until"]):
			base = phase
			break
	var interval_scale: float = float(round_cfg.get("interval_scale", 1.0))
	var speed_scale: float = float(round_cfg.get("speed_scale", 1.0))
	var bias: Dictionary = round_cfg.get("weights_bias", {})
	var raw_weights: Dictionary = base["weights"]
	var weights: Dictionary = {
		"flame": maxf(0.0, float(raw_weights["flame"]) + float(bias.get("flame", 0.0))),
		"saw": maxf(0.0, float(raw_weights["saw"]) + float(bias.get("saw", 0.0))),
		"laser": maxf(0.0, float(raw_weights["laser"]) + float(bias.get("laser", 0.0))),
	}
	if HAZARD_LASER_ONLY:
		weights = {"flame": 0.0, "saw": 0.0, "laser": 1.0}
	var active_limit: int = mini(
		HAZARD_MAX_CONCURRENT,
		int(base["max_concurrent"]) + int(round_cfg.get("max_concurrent_bonus", 0))
	)
	return {
		"name": str(base["name"]),
		"interval": maxf(0.6, float(base["interval"]) * interval_scale),
		"max_concurrent": maxi(1, active_limit),
		"burst": clampi(int(base["burst"]) + int(round_cfg.get("burst_bonus", 0)), LASER_BURST_MIN, LASER_BURST_MAX),
		"speed_scale": speed_scale,
		"weights": weights,
	}


static func pick_hazard_type(rng: RandomNumberGenerator, phase: Dictionary) -> int:
	## 服务器种子驱动的轮盘赌；HAZARD_LASER_ONLY 时恒为激光。
	if HAZARD_LASER_ONLY:
		return HZ_LASER
	var w: Dictionary = phase["weights"]
	var total: float = float(w["flame"]) + float(w["saw"]) + float(w["laser"])
	if total <= 0.0:
		return HZ_FLAME
	var roll: float = rng.randf() * total
	if roll < float(w["flame"]):
		return HZ_FLAME
	roll -= float(w["flame"])
	if roll < float(w["saw"]):
		return HZ_SAW
	return HZ_LASER


static func hazard_params(type: int, rng: RandomNumberGenerator, speed_scale: float) -> Dictionary:
	## 生成单个机关的时长/宽度/速度；预警与激活均由服务器绝对时间定义。
	var out: Dictionary = {
		"type": type,
		"warn": 0.8,
		"active": 1.2,
		"width": 1.0,
		"clear_height": 0.0,
		"speed": 0.0,
	}
	match type:
		HZ_FLAME:
			out["warn"] = rng.randf_range(FLAME_WARN_MIN, FLAME_WARN_MAX)
			out["active"] = rng.randf_range(FLAME_ACTIVE_MIN, FLAME_ACTIVE_MAX)
			out["width"] = FLAME_WIDTH
			out["clear_height"] = FLAME_CLEAR_HEIGHT
		HZ_SAW:
			out["warn"] = SAW_WARN
			out["width"] = SAW_RADIUS * 2.0
			out["clear_height"] = SAW_CLEAR_HEIGHT
			out["speed"] = SAW_SPEED * speed_scale
		HZ_LASER:
			out["warn"] = rng.randf_range(LASER_WARN_MIN, LASER_WARN_MAX)
			out["active"] = rng.randf_range(LASER_ACTIVE_MIN, LASER_ACTIVE_MAX)
			out["width"] = LASER_WIDTH
			out["clear_height"] = LASER_CLEAR_HEIGHT
	return out


# ============================================================================
# 工具：出生点（中心区域随机、无重叠、人数无关）
# ============================================================================

static func compute_spawns(player_count: int, seed_val: int) -> Array:
	## 不写死人数：任意 2..N 人均在中心圆内做拒绝采样，失败则环形兜底。
	var count: int = maxi(1, player_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var out: Array = []
	var tries: int = 0
	while out.size() < count and tries < SPAWN_MAX_TRIES:
		tries += 1
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * SPAWN_CENTER_RADIUS
		var cand := Vector2(cos(ang) * rad, sin(ang) * rad)
		var ok: bool = true
		for raw in out:
			var existing: Vector2 = raw
			if cand.distance_to(existing) < SPAWN_MIN_SEPARATION:
				ok = false
				break
		if ok:
			out.append(cand)
	# 兜底：按人数计算能容纳所有人的最小环半径，保证严格无重叠。
	# 用精确弦长公式 sep/(2*sin(pi/n))；原 count*sep/TAU 是周长近似，人数多时会低估导致相邻点略微重叠。
	if out.size() < count:
		out.clear()
		var ring_r: float = maxf(
			SPAWN_CENTER_RADIUS * 0.72,
			SPAWN_MIN_SEPARATION / (2.0 * sin(TAU / (2.0 * float(maxi(2, count)))))
		)
		ring_r = minf(ring_r, EDGE_LIMIT_RADIUS * 0.75)
		# 抖动只能整环统一旋转；若每点独立抖动会破坏等角分布，相邻点可能低于最小间距。
		var base_a: float = rng.randf() * 0.04
		for i in range(count):
			var a: float = TAU * float(i) / float(count) + base_a
			out.append(Vector2(cos(a) * ring_r, sin(a) * ring_r))
	return out


# ============================================================================
# 工具：弦线几何 / 安全网格
# ============================================================================

static func chord_endpoints(n: Vector2, d: float, radius: float) -> Array:
	## 直线 dot(p, n) = d 与圆的交点（弦）。n 必须为单位向量。
	var half: float = sqrt(maxf(0.0, radius * radius - d * d))
	var center: Vector2 = n * d
	var tangent := Vector2(-n.y, n.x)
	return [center - tangent * half, center + tangent * half]


static func point_chord_distance(p: Vector2, n: Vector2, d: float) -> float:
	return absf(p.dot(n) - d)


static func grid_dims() -> int:
	return int(ceil(2.0 * ARENA_RADIUS / GRID_CELL)) + 2


static func grid_index(world: Vector2) -> Vector2i:
	return Vector2i(
		int(floor((world.x + ARENA_RADIUS) / GRID_CELL)),
		int(floor((world.y + ARENA_RADIUS) / GRID_CELL))
	)


static func grid_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * GRID_CELL - ARENA_RADIUS,
		(float(cell.y) + 0.5) * GRID_CELL - ARENA_RADIUS
	)


static func grid_in_arena(cell: Vector2i) -> bool:
	## 格子中心必须完全落在有效站立区内（留出半格余量）。
	var p: Vector2 = grid_center(cell)
	return p.length() <= EDGE_LIMIT_RADIUS - GRID_CELL * 0.5


# ============================================================================
# 工具：扫掠激光（v0.1.5 新增 — 从场地一端沿法线扫到另一端）
# ============================================================================

static func compute_laser_sweep(rng: RandomNumberGenerator, speed_scale: float) -> Dictionary:
	## 生成一条扫掠激光的全部参数。
	## normal：弦线法线方向（单位向量）
	## d_start / d_end：dot(p, normal) 的起止偏移（由 -R-pad 扫到 +R+pad 或反向）
	## speed：扫掠速度
	## warn_duration / active_duration：预警时长 / 全程扫掠时长
	var ang: float = rng.randf() * TAU
	var n := Vector2(cos(ang), sin(ang))
	var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
	var r_pad: float = EDGE_LIMIT_RADIUS + LASER_SWEEP_ENTRY_PAD
	var d_start: float = -r_pad * dir
	var d_end: float = r_pad * dir
	var speed: float = maxf(0.1, LASER_SWEEP_SPEED * speed_scale)
	var full: float = absf(d_end - d_start)
	return {
		"normal": n,
		"d_start": d_start,
		"d_end": d_end,
		"speed": speed,
		"warn_duration": rng.randf_range(LASER_WARN_MIN, LASER_WARN_MAX),
		"active_duration": full / speed,
	}


static func laser_sweep_chord_at(
	normal: Vector2, d_start: float, d_end: float, speed: float, t: float
) -> Array:
	## 激活 t 秒后激光当前的弦端点 [a, b]；若尚未入场或已完全离场返回空数组。
	## 注意：t 是"激活阶段开始时"经过的秒数（不含预警阶段）。
	var dir: float = signf(d_end - d_start)
	if dir == 0.0:
		return []
	var d_now: float = d_start + dir * speed * t
	# 已经扫出场地范围
	if dir > 0.0 and d_now >= d_end:
		return []
	if dir < 0.0 and d_now <= d_end:
		return []
	# 尚未进入圆形区域（完全在场地外）
	if absf(d_now) >= ARENA_RADIUS:
		return []
	return chord_endpoints(normal, d_now, ARENA_RADIUS)


static func laser_sweep_initial_chord(sweep: Dictionary) -> Array:
	## 预警阶段 / 初始可见弦（把入场点裁剪到场地内，避免退化成长度为 0 的点）。
	var n: Vector2 = sweep["normal"]
	var d_start: float = sweep["d_start"]
	var d_end: float = sweep["d_end"]
	var dir: float = signf(d_end - d_start)
	var d_clip: float
	if dir > 0.0:
		d_clip = maxf(d_start, -ARENA_RADIUS + 0.1)
	else:
		d_clip = minf(d_start, ARENA_RADIUS - 0.1)
	return chord_endpoints(n, d_clip, ARENA_RADIUS)


# ============================================================================
# 工具：计分与排名
# ============================================================================

static func score_for_survival(alive_seconds: float) -> int:
	## 服务器按整秒累计，出局后不再调用。
	return int(floor(maxf(0.0, alive_seconds))) * SCORE_PER_SECOND


static func rank_entries(entries: Array) -> Array:
	## entry: {network_id, score, alive_sec, pushes, hits_taken, out_reason, alive}
	## 排名：总分 -> 存活时长 -> 推人命中 -> 受击次数（少者优先）。
	var ranked: Array = entries.duplicate(true)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a["score"]) > int(b["score"])
		if absf(float(a.get("alive_sec", 0.0)) - float(b.get("alive_sec", 0.0))) > 0.001:
			return float(a["alive_sec"]) > float(b["alive_sec"])
		if int(a.get("pushes", 0)) != int(b.get("pushes", 0)):
			return int(a["pushes"]) > int(b["pushes"])
		return int(a.get("hits_taken", 0)) < int(b.get("hits_taken", 0))
	)
	for i in range(ranked.size()):
		var e: Dictionary = ranked[i]
		e["rank"] = i + 1
		ranked[i] = e
	return ranked


static func official_scores(ranked: Array) -> Dictionary:
	## 换算成官方跨小游戏累计积分（第 1 名 N 分，依次递减，最低 1 分）。
	var out: Dictionary = {}
	var total: int = ranked.size()
	for raw in ranked:
		var e: Dictionary = raw
		var rank: int = int(e.get("rank", 1))
		out[int(e.get("network_id", 0))] = maxi(1, total - rank + 1)
	return out


static func state_name(state: int) -> String:
	match state:
		ST_READY: return "READY"
		ST_NORMAL: return "NORMAL"
		ST_JUMPING: return "JUMPING"
		ST_FALLEN: return "FALLEN"
		ST_INVULN: return "INVULN"
		ST_OUT: return "OUT"
		ST_SPECTATOR: return "SPECTATOR"
	return "UNKNOWN"


static func hazard_name(type: int) -> String:
	match type:
		HZ_FLAME: return "FLAME"
		HZ_SAW: return "SAW"
		HZ_LASER: return "LASER"
	return "UNKNOWN"