extends RefCounted

## Bubble Blitz (泡泡爆破) preset configuration, map generator, and scoring rules.
## Zero lobby-settings overhead: tuned presets for fast 75-second party rounds.

const ROUND_DURATION_SEC := 75.0
const HURRY_UP_REMAINING_SEC := 25.0
const CRUSHER_STEP_INTERVAL_SEC := 0.34
const TILE_SIZE := 1.4

const MAX_HP := 3
const INVULN_DURATION_SEC := 1.5
const TRAPPED_DURATION_SEC := 4.0
const NEEDLE_AUTO_SAVE_DELAY_SEC := 1.5
const TRAPPED_MOVE_MULTIPLIER := 0.24

const START_MAX_BUBBLES := 1
const START_POWER := 1
const START_SPEED_LEVEL := 0
const MAX_BUBBLES_CAP := 6
const MAX_POWER_CAP := 6
const MAX_SPEED_LEVEL := 4

const BASE_MOVE_SPEED := 5.1
const SPEED_STEP_BONUS := 0.62
const BUBBLE_FUSE_SEC := 2.4
const BLAST_DURATION_SEC := 0.45
const BUBBLE_SLIDE_SPEED := 8.8
const CONVEYOR_BUBBLE_SPEED := 3.6
const CONVEYOR_PLAYER_PUSH := 1.45

const CRATE_DROP_CHANCE := 0.46
const GOLD_CRATE_DROP_CHANCE := 1.0

const TILE_EMPTY := 0
const TILE_STEEL := 1
const TILE_CRATE := 2
const TILE_GOLD_CRATE := 3
const TILE_CRUSHED := 4

const ITEM_BUBBLE := 1
const ITEM_POWER := 2
const ITEM_SPEED := 3
const ITEM_KICK := 4
const ITEM_NEEDLE := 5

const THEME_CLASSIC := 0
const THEME_CROSS := 1
const THEME_VAULT := 2
const THEME_CONVEYOR := 3
const THEME_COUNT := 4

const THEME_META := {
	THEME_CLASSIC: {
		"id": "classic_grid",
		"en": "CLASSIC GRID",
		"zh-CN": "经典车间",
		"zh-TW": "經典車間",
		"floor_a": Color(0.20, 0.24, 0.29),
		"floor_b": Color(0.16, 0.19, 0.24),
		"accent": Color(0.24, 0.78, 0.96),
		"crate": Color(0.68, 0.45, 0.22),
	},
	THEME_CROSS: {
		"id": "cross_factory",
		"en": "CROSS FACTORY",
		"zh-CN": "十字通道",
		"zh-TW": "十字通道",
		"floor_a": Color(0.24, 0.21, 0.26),
		"floor_b": Color(0.19, 0.17, 0.22),
		"accent": Color(0.98, 0.54, 0.22),
		"crate": Color(0.64, 0.38, 0.24),
	},
	THEME_VAULT: {
		"id": "loot_vault",
		"en": "LOOT VAULT",
		"zh-CN": "中央金库",
		"zh-TW": "中央金庫",
		"floor_a": Color(0.18, 0.23, 0.22),
		"floor_b": Color(0.14, 0.19, 0.18),
		"accent": Color(0.98, 0.80, 0.22),
		"crate": Color(0.58, 0.46, 0.26),
	},
	THEME_CONVEYOR: {
		"id": "conveyor_belt",
		"en": "CONVEYOR BELT",
		"zh-CN": "传送带车间",
		"zh-TW": "傳送帶車間",
		"floor_a": Color(0.21, 0.22, 0.25),
		"floor_b": Color(0.16, 0.17, 0.20),
		"accent": Color(0.32, 0.92, 0.56),
		"crate": Color(0.60, 0.42, 0.24),
	},
}


static func grid_size_for_players(player_count: int) -> Vector2i:
	if player_count <= 4:
		return Vector2i(15, 11)
	if player_count <= 8:
		return Vector2i(17, 13)
	return Vector2i(19, 15)


static func theme_display_name(theme_id: int) -> String:
	var meta: Dictionary = THEME_META.get(theme_id, THEME_META[THEME_CLASSIC])
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return str(meta.get("zh-CN", "经典车间"))
	if loc.begins_with("ZH"):
		return str(meta.get("zh-TW", "經典車間"))
	return str(meta.get("en", "CLASSIC GRID"))


static func compute_spawn_cells(width: int, height: int, player_count: int) -> Array:
	var candidates: Array = [
		Vector2i(1, 1),
		Vector2i(width - 2, height - 2),
		Vector2i(width - 2, 1),
		Vector2i(1, height - 2),
		Vector2i(width / 2, 1),
		Vector2i(width / 2, height - 2),
		Vector2i(1, height / 2),
		Vector2i(width - 2, height / 2),
	]
	# Additional symmetric perimeter spawns for 9-16 players.
	var qx1: int = max(3, width / 4)
	var qx2: int = min(width - 4, width - 1 - qx1)
	var qy1: int = max(3, height / 4)
	var qy2: int = min(height - 4, height - 1 - qy1)
	var extra: Array = [
		Vector2i(qx1, 1),
		Vector2i(qx2, height - 2),
		Vector2i(qx2, 1),
		Vector2i(qx1, height - 2),
		Vector2i(1, qy1),
		Vector2i(width - 2, qy2),
		Vector2i(width - 2, qy1),
		Vector2i(1, qy2),
	]
	for cell in extra:
		if not candidates.has(cell):
			candidates.append(cell)

	var out: Array = []
	var count: int = max(1, player_count)
	for i in range(count):
		out.append(candidates[i % candidates.size()])
	return out


static func _build_safe_zone(width: int, height: int, spawns: Array) -> Dictionary:
	var safe: Dictionary = {}
	for raw_cell in spawns:
		var c: Vector2i = raw_cell
		safe[c] = true
		# Guarantee an L-shaped 3-tile escape pocket at every spawn.
		var dx: int = 1 if c.x <= width / 2 else -1
		var dy: int = 1 if c.y <= height / 2 else -1
		var nx: Vector2i = Vector2i(clampi(c.x + dx, 1, width - 2), c.y)
		var ny: Vector2i = Vector2i(c.x, clampi(c.y + dy, 1, height - 2))
		safe[nx] = true
		safe[ny] = true
	return safe


static func generate_map(player_count: int, theme_id: int, seed_val: int) -> Dictionary:
	var dims: Vector2i = grid_size_for_players(player_count)
	var w: int = dims.x
	var h: int = dims.y
	var cx: int = w / 2
	var cy: int = h / 2
	var spawns: Array = compute_spawn_cells(w, h, player_count)
	var safe: Dictionary = _build_safe_zone(w, h, spawns)

	var tiles: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				row.append(TILE_STEEL)
			else:
				row.append(TILE_EMPTY)
		tiles.append(row)

	var conveyors: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# 1. Place indestructible pillars & conveyors per theme.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if safe.has(Vector2i(x, y)):
				continue
			if theme_id == THEME_CLASSIC:
				if x % 2 == 0 and y % 2 == 0:
					tiles[y][x] = TILE_STEEL
			elif theme_id == THEME_CROSS:
				# Keep wide central cross clear of steel pillars.
				if abs(x - cx) <= 1 or abs(y - cy) <= 1:
					continue
				if x % 2 == 0 and y % 2 == 0:
					tiles[y][x] = TILE_STEEL
			elif theme_id == THEME_VAULT:
				# Outer pillars + protective vault walls around the 3x3 gold core.
				var dx_c: int = abs(x - cx)
				var dy_c: int = abs(y - cy)
				if dx_c == 2 and dy_c == 2:
					tiles[y][x] = TILE_STEEL
				elif dx_c <= 1 and dy_c <= 1:
					tiles[y][x] = TILE_GOLD_CRATE
				elif x % 2 == 0 and y % 2 == 0 and (dx_c > 2 or dy_c > 2):
					tiles[y][x] = TILE_STEEL
			elif theme_id == THEME_CONVEYOR:
				if x % 2 == 0 and y % 2 == 0:
					# Leave conveyor tracks open on rows 2 and h-3, cols 2 and w-3.
					if y != 2 and y != h - 3 and x != 2 and x != w - 3:
						tiles[y][x] = TILE_STEEL

	if theme_id == THEME_CONVEYOR:
		# Two opposite horizontal industrial conveyor belts + two vertical return belts.
		var top_y: int = 2
		var bot_y: int = h - 3
		for x in range(2, w - 2):
			if not safe.has(Vector2i(x, top_y)) and tiles[top_y][x] == TILE_EMPTY:
				conveyors[Vector2i(x, top_y)] = Vector2i(1, 0)
			if not safe.has(Vector2i(x, bot_y)) and tiles[bot_y][x] == TILE_EMPTY:
				conveyors[Vector2i(x, bot_y)] = Vector2i(-1, 0)
		var left_x: int = 2
		var right_x: int = w - 3
		for y in range(3, h - 3):
			if not safe.has(Vector2i(left_x, y)) and tiles[y][left_x] == TILE_EMPTY:
				conveyors[Vector2i(left_x, y)] = Vector2i(0, -1)
			if not safe.has(Vector2i(right_x, y)) and tiles[y][right_x] == TILE_EMPTY:
				conveyors[Vector2i(right_x, y)] = Vector2i(0, 1)

	# 2. Symmetric 4-quadrant random crate placement.
	var crate_density: float = 0.62
	if theme_id == THEME_CROSS:
		crate_density = 0.52
	elif theme_id == THEME_VAULT:
		crate_density = 0.48
	elif theme_id == THEME_CONVEYOR:
		crate_density = 0.46

	for y in range(1, cy + 1):
		for x in range(1, cx + 1):
			var roll: float = rng.randf()
			if roll > crate_density:
				continue
			var is_gold: bool = (roll < 0.08)
			var mirrors: Array = [
				Vector2i(x, y),
				Vector2i(w - 1 - x, y),
				Vector2i(x, h - 1 - y),
				Vector2i(w - 1 - x, h - 1 - y),
			]
			for m in mirrors:
				var c: Vector2i = m
				if safe.has(c) or conveyors.has(c):
					continue
				if tiles[c.y][c.x] == TILE_EMPTY:
					tiles[c.y][c.x] = TILE_GOLD_CRATE if is_gold else TILE_CRATE

	# 3. Ensure every spawn still has its L-shaped pocket strictly empty.
	for raw_safe in safe.keys():
		var sc: Vector2i = raw_safe
		tiles[sc.y][sc.x] = TILE_EMPTY

	# 4. Build spiral crush order for final 25s Hurry Up.
	var crush_order: Array = _build_spiral_crush_order(w, h)

	return {
		"width": w,
		"height": h,
		"theme_id": theme_id,
		"seed": seed_val,
		"tiles": tiles,
		"conveyors": conveyors,
		"spawns": spawns,
		"safe": safe,
		"crush_order": crush_order,
	}


static func _build_spiral_crush_order(w: int, h: int) -> Array:
	var order: Array = []
	var left: int = 1
	var right: int = w - 2
	var top: int = 1
	var bottom: int = h - 2
	while left <= right and top <= bottom:
		# Leave a tiny 1x1 or 3x1 center core until the very end.
		if right - left <= 1 and bottom - top <= 1:
			break
		for x in range(left, right + 1):
			order.append(Vector2i(x, top))
		top += 1
		for y in range(top, bottom + 1):
			order.append(Vector2i(right, y))
		right -= 1
		if top <= bottom:
			for x in range(right, left - 1, -1):
				order.append(Vector2i(x, bottom))
			bottom -= 1
		if left <= right:
			for y in range(bottom, top - 1, -1):
				order.append(Vector2i(left, y))
			left += 1
	return order


static func roll_item_type(rng: RandomNumberGenerator, is_gold: bool) -> int:
	var roll: float = rng.randf()
	if is_gold:
		if roll < 0.28:
			return ITEM_KICK
		if roll < 0.50:
			return ITEM_NEEDLE
		if roll < 0.72:
			return ITEM_POWER
		if roll < 0.88:
			return ITEM_BUBBLE
		return ITEM_SPEED
	if roll < 0.30:
		return ITEM_BUBBLE
	if roll < 0.60:
		return ITEM_POWER
	if roll < 0.80:
		return ITEM_SPEED
	if roll < 0.93:
		return ITEM_KICK
	return ITEM_NEEDLE


static func grid_to_world(cell: Vector2i, width: int, height: int) -> Vector3:
	var ox: float = (float(width) - 1.0) * 0.5
	var oz: float = (float(height) - 1.0) * 0.5
	return Vector3((float(cell.x) - ox) * TILE_SIZE, 0.0, (float(cell.y) - oz) * TILE_SIZE)


static func world_to_grid(pos: Vector3, width: int, height: int) -> Vector2i:
	var ox: float = (float(width) - 1.0) * 0.5
	var oz: float = (float(height) - 1.0) * 0.5
	var gx: int = int(round(pos.x / TILE_SIZE + ox))
	var gy: int = int(round(pos.z / TILE_SIZE + oz))
	return Vector2i(clampi(gx, 0, width - 1), clampi(gy, 0, height - 1))


static func compute_rank_scores(entries: Array) -> Dictionary:
	## Combines survival rank + pop/knockout bonus into final rank-tiered official scores.
	## Each entry: { "network_id": int, "alive": bool, "elim_time": float, "pops": int, "traps": int }
	var total: int = entries.size()
	if total == 0:
		return {}

	var scored: Array = []
	for raw in entries:
		var e: Dictionary = raw
		var alive: bool = bool(e.get("alive", false))
		var elim_t: float = float(e.get("elim_time", ROUND_DURATION_SEC if alive else 0.0))
		var pops: int = int(e.get("pops", 0))
		var traps: int = int(e.get("traps", 0))
		# Survival dominates base order; pops (+18s equivalent) and traps (+6s equivalent) reward aggression.
		var composite: float = (1000.0 if alive else elim_t * 10.0) + float(pops) * 180.0 + float(traps) * 60.0
		scored.append({
			"network_id": int(e.get("network_id", 0)),
			"composite": composite,
		})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["composite"]) > float(b["composite"])
	)

	var out: Dictionary = {}
	var current_rank: int = 1
	for i in range(total):
		if i > 0 and absf(float(scored[i]["composite"]) - float(scored[i - 1]["composite"])) > 0.01:
			current_rank = i + 1
		var pts: int = max(1, total - current_rank + 1)
		out[int(scored[i]["network_id"])] = pts
	return out
