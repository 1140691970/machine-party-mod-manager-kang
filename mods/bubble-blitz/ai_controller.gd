extends RefCounted

## Tactical AI controller for Bubble Blitz (danger avoidance, rescues, crates, pickups).

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func compute_input(stage: Node3D, p: Dictionary, delta: float) -> Dictionary:
	var cfg = stage.C
	var map_w: int = int(stage._map_width)
	var map_h: int = int(stage._map_height)
	var bubbles: Dictionary = stage._bubbles
	var players: Dictionary = stage._players
	var items: Dictionary = stage._items
	var tiles: Array = stage._tiles
	var team = stage._team

	var cell: Vector2i = cfg.world_to_grid(p["pos"], map_w, map_h)
	var danger: Dictionary = {}
	for b_id in bubbles.keys():
		var b: Dictionary = bubbles[b_id]
		var orig: Vector2i = b["cell"]
		danger[orig] = true
		for d in DIRS:
			for step in range(1, int(b["power"]) + 1):
				var c: Vector2i = orig + d * step
				if stage._is_tile_blocked(c):
					break
				danger[c] = true

	if danger.has(cell):
		for d in DIRS:
			var nc: Vector2i = cell + d
			if not stage._is_tile_blocked(nc) and stage._bubble_at_cell(nc) == -1 and not danger.has(nc):
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}

	var my_id: int = int(p["network_id"])

	# Rush adjacent downed players (finish rivals or rescue teammates) or adjacent pickups if safe.
	for d in DIRS:
		var nc: Vector2i = cell + d
		if stage._is_tile_blocked(nc) or stage._bubble_at_cell(nc) != -1 or danger.has(nc):
			continue
		for other_id in players.keys():
			if int(other_id) == my_id:
				continue
			var op: Dictionary = players[other_id]
			if bool(op["alive"]) and bool(op["trapped"]) and cfg.world_to_grid(op["pos"], map_w, map_h) == nc:
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}
		for item_id in items.keys():
			if items[item_id]["cell"] == nc:
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}

	# In team mode, seek downed teammates within 5 cells when standing on a safe tile.
	if team != null and team.is_active() and not danger.has(cell):
		var best_dir := Vector2.ZERO
		var best_dist: int = 5
		for other_id in players.keys():
			var oid: int = int(other_id)
			if oid == my_id or not team.are_teammates(my_id, oid):
				continue
			var op: Dictionary = players[other_id]
			if not bool(op["alive"]) or not bool(op["trapped"]):
				continue
			var mate_cell: Vector2i = cfg.world_to_grid(op["pos"], map_w, map_h)
			var dist_cells: int = absi(mate_cell.x - cell.x) + absi(mate_cell.y - cell.y)
			if dist_cells < best_dist:
				for d in DIRS:
					var nc: Vector2i = cell + d
					if stage._is_tile_blocked(nc) or stage._bubble_at_cell(nc) != -1 or danger.has(nc):
						continue
					if absi(mate_cell.x - nc.x) + absi(mate_cell.y - nc.y) < dist_cells:
						best_dist = dist_cells
						best_dir = Vector2(float(d.x), float(d.y))
		if best_dir.length_squared() > 0.1:
			return {"dir": best_dir, "drop": false}

	p["ai_cooldown"] = float(p["ai_cooldown"]) - delta
	var drop := false
	if float(p["ai_cooldown"]) <= 0.0:
		p["ai_cooldown"] = 0.55
		var open_dirs: Array = []
		var near_crate := false
		for d in DIRS:
			var nc: Vector2i = cell + d
			if nc.x >= 0 and nc.y >= 0 and nc.x < map_w and nc.y < map_h:
				var t: int = int(tiles[nc.y][nc.x])
				if t == cfg.TILE_CRATE or t == cfg.TILE_GOLD_CRATE:
					near_crate = true
				elif t == cfg.TILE_EMPTY and stage._bubble_at_cell(nc) == -1 and not danger.has(nc):
					open_dirs.append(d)
		if near_crate and open_dirs.size() >= 1 and int(p["active_bubbles"]) == 0:
			drop = true
		if not open_dirs.is_empty():
			var rng: RandomNumberGenerator = stage._rng
			var pick: Vector2i = open_dirs[rng.randi_range(0, open_dirs.size() - 1)]
			p["ai_dir"] = Vector2(float(pick.x), float(pick.y))
		else:
			p["ai_dir"] = Vector2.ZERO

	return {"dir": p["ai_dir"], "drop": drop}
