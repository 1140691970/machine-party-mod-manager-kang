extends RefCounted

## Hazard spawning, safety BFS/corridor validation, and timeline tracking for Spike Ring.

const MAX_ACTIVE_SAW_LIGHTS := 2


func live_hazard_count(stage: Node3D) -> int:
	var cfg = stage.C
	var hazards: Dictionary = stage._hazards
	var n: int = 0
	for raw in hazards.values():
		var h: Dictionary = raw
		if int(h["state"]) != cfg.HAZARD_STATE_DONE:
			n += 1
	return n


func has_live_laser(stage: Node3D) -> bool:
	var cfg = stage.C
	var hazards: Dictionary = stage._hazards
	for raw in hazards.values():
		var h: Dictionary = raw
		if int(h["type"]) == cfg.HZ_LASER and int(h["state"]) != cfg.HAZARD_STATE_DONE:
			return true
	return false


func pick_weighted_type(stage: Node3D, phase: Dictionary) -> int:
	var cfg = stage.C
	var rng: RandomNumberGenerator = stage._rng
	if cfg.HAZARD_LASER_ONLY:
		return cfg.HZ_LASER
	var weights: Dictionary = phase.get("weights", {"flame": 0.3, "saw": 0.35, "laser": 0.35})
	var allow_laser: bool = not has_live_laser(stage)
	var w_flame: float = float(weights.get("flame", 0.3))
	var w_saw: float = float(weights.get("saw", 0.35))
	var w_laser: float = float(weights.get("laser", 0.35)) if allow_laser else 0.0
	var total: float = w_flame + w_saw + w_laser
	if total <= 0.001:
		return cfg.HZ_SAW
	var r: float = rng.randf() * total
	if r < w_flame:
		return cfg.HZ_FLAME
	if r < w_flame + w_saw:
		return cfg.HZ_SAW
	return cfg.HZ_LASER


func step_spawner(stage: Node3D, delta: float) -> void:
	var cfg = stage.C
	var phase: Dictionary = cfg.difficulty_phase(float(stage._elapsed_time), stage._round_cfg)
	stage._spawn_timer = float(stage._spawn_timer) - delta
	if float(stage._spawn_timer) > 0.0:
		return
	stage._spawn_timer = float(phase["interval"])

	var budget: int = int(phase["max_concurrent"]) - live_hazard_count(stage)
	if budget <= 0:
		return
	var want: int = mini(budget, int(phase.get("burst", 1)))
	var made: int = 0
	for _b in range(want):
		var hz_type: int = pick_weighted_type(stage, phase)
		if hz_type == cfg.HZ_LASER and has_live_laser(stage):
			hz_type = cfg.HZ_SAW
		for _attempt in range(cfg.SAFETY_RETRY_MAX):
			var cand: Dictionary = make_candidate(stage, hz_type, phase, Vector2.ZERO)
			if cand.is_empty():
				continue
			if safety_check(stage, cand, float(phase["interval"])):
				commit_hazard(stage, cand)
				made += 1
				break
	if made == 0:
		stage._spawn_timer = maxf(0.4, float(phase["interval"]) * 0.5)


func make_candidate(stage: Node3D, hz_type: int, phase: Dictionary, bundle_n: Vector2 = Vector2.ZERO) -> Dictionary:
	var cfg = stage.C
	var rng: RandomNumberGenerator = stage._rng
	var srv_time: float = float(stage._srv_time)
	var arena_radius: float = float(stage._arena_radius)
	var nozzle_cd: Dictionary = stage._nozzle_cooldown
	var params: Dictionary = cfg.hazard_params(hz_type, rng, float(phase["speed_scale"]))
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var n := Vector2.ZERO
	var d: float = 0.0
	var nozzle: int = -1

	if hz_type == cfg.HZ_FLAME:
		for _i in range(6):
			var pick: int = rng.randi_range(0, cfg.NOZZLE_COUNT - 1)
			if srv_time - float(nozzle_cd.get(pick, -999.0)) >= cfg.NOZZLE_COOLDOWN_SEC:
				nozzle = pick
				break
		if nozzle < 0:
			return {}
		var na: float = TAU * float(nozzle) / float(cfg.NOZZLE_COUNT)
		a = Vector2(cos(na), sin(na)) * arena_radius
		var inward: Vector2 = -a.normalized()
		var jitter: float = rng.randf_range(-1.0, 1.0)
		var u: Vector2 = inward.rotated(jitter * 0.9).normalized()
		b = a + u * (-2.0 * a.dot(u))
		n = Vector2(-u.y, u.x).normalized()
		d = a.dot(n)
	else:
		if bundle_n != Vector2.ZERO:
			n = bundle_n.rotated(rng.randf_range(-0.14, 0.14)).normalized()
		else:
			var ang: float = rng.randf() * TAU
			n = Vector2(cos(ang), sin(ang))
		d = rng.randf_range(-arena_radius * 0.72, arena_radius * 0.72)
		var ends: Array = cfg.chord_endpoints(n, d, arena_radius)
		a = ends[0]
		b = ends[1]

	var length: float = a.distance_to(b)
	if length < arena_radius * 0.5:
		return {}
	var active: float = float(params["active"])
	if hz_type == cfg.HZ_SAW:
		active = minf(cfg.SAW_ACTIVE_MAX, length / maxf(0.1, float(params["speed"])))
	var sweep_dir: float = (1.0 if d <= 0.0 else -1.0) if hz_type == cfg.HZ_LASER else 0.0
	var sweep_speed: float = cfg.LASER_SWEEP_SPEED * float(phase.get("speed_scale", 1.0)) if hz_type == cfg.HZ_LASER else 0.0
	var gap_t: float = rng.randf_range(0.24, 0.76) if hz_type == cfg.HZ_LASER else 0.5
	return {
		"type": hz_type,
		"n": n,
		"d": d,
		"d_base": d,
		"sweep_dir": sweep_dir,
		"sweep_speed": sweep_speed,
		"gap_t": gap_t,
		"gap_width": cfg.LASER_GAP_WIDTH,
		"a": a,
		"b": b,
		"length": length,
		"width": float(params["width"]),
		"clear_height": float(params["clear_height"]),
		"speed": float(params["speed"]),
		"warn": float(params["warn"]),
		"active": active,
		"nozzle": nozzle,
		"state": cfg.HAZARD_STATE_WARN,
		"saw_t": 0.0,
		"saw_pos": a,
	}


func _mark_chord(cfg, grid: Dictionary, n: Vector2, d: float, half_width: float, mark: int) -> void:
	var dim: int = cfg.grid_dims()
	for gx in range(dim):
		for gy in range(dim):
			var cell := Vector2i(gx, gy)
			if not cfg.grid_in_arena(cell):
				continue
			var center: Vector2 = cfg.grid_center(cell)
			if cfg.point_chord_distance(center, n, d) <= half_width:
				var cur: int = int(grid.get(cell, cfg.GRID_SAFE))
				if mark == cfg.GRID_DANGER or cur != cfg.GRID_DANGER:
					grid[cell] = mark


func _mark_circle(cfg, grid: Dictionary, center: Vector2, radius: float, mark: int) -> void:
	var dim: int = cfg.grid_dims()
	var min_c: Vector2i = cfg.grid_index(center - Vector2(radius, radius))
	var max_c: Vector2i = cfg.grid_index(center + Vector2(radius, radius))
	for gx in range(maxi(0, min_c.x), mini(dim, max_c.x + 2)):
		for gy in range(maxi(0, min_c.y), mini(dim, max_c.y + 2)):
			var cell := Vector2i(gx, gy)
			if not cfg.grid_in_arena(cell):
				continue
			if cfg.grid_center(cell).distance_to(center) <= radius:
				var cur: int = int(grid.get(cell, cfg.GRID_SAFE))
				if mark == cfg.GRID_DANGER or cur != cfg.GRID_DANGER:
					grid[cell] = mark


func _build_danger_grid(stage: Node3D, extra: Array, horizon: float) -> Dictionary:
	var cfg = stage.C
	var grid: Dictionary = {}
	var now: float = float(stage._srv_time)
	var steps: int = 6
	for raw in extra:
		var h: Dictionary = raw
		var t0: float = maxf(now, float(h["active_start"]))
		var t1: float = minf(now + horizon, float(h["end_time"]))
		if t1 <= t0:
			continue
		var hz_type: int = int(h["type"])
		var hard: bool = (hz_type == cfg.HZ_SAW)
		var mark: int = cfg.GRID_DANGER if hard else cfg.GRID_JUMPABLE
		if hz_type == cfg.HZ_SAW:
			for s in range(steps + 1):
				var t: float = lerpf(t0, t1, float(s) / float(steps))
				var prog: float = clampf(
					(t - float(h["active_start"])) * float(h["speed"]) / maxf(0.001, float(h["length"])),
					0.0, 1.0
				)
				var center: Vector2 = (h["a"] as Vector2).lerp(h["b"] as Vector2, prog)
				_mark_circle(cfg, grid, center, float(h["width"]) * 0.5 + cfg.PLAYER_RADIUS, mark)
		else:
			_mark_chord(cfg, grid, h["n"], float(h["d"]), float(h["width"]) * 0.5 + cfg.PLAYER_RADIUS, mark)
	return grid


func _min_distance_to_hazard(cfg, p: Vector2, h: Dictionary) -> float:
	if int(h["type"]) == cfg.HZ_SAW:
		var best: float = 1e9
		for s in range(9):
			var q: Vector2 = (h["a"] as Vector2).lerp(h["b"] as Vector2, float(s) / 8.0)
			best = minf(best, p.distance_to(q))
		return best - float(h["width"]) * 0.5
	return cfg.point_chord_distance(p, h["n"], float(h["d"])) - float(h["width"]) * 0.5


func _bfs_reachable(cfg, grid: Dictionary, start: Vector2i, max_steps: int) -> Array:
	var out: Array = []
	var visited: Dictionary = {}
	var queue: Array = [[start, 0]]
	visited[start] = true
	var head: int = 0
	while head < queue.size():
		var item: Array = queue[head]
		head += 1
		var cell: Vector2i = item[0]
		var depth: int = int(item[1])
		out.append(cell)
		if depth >= max_steps:
			continue
		for raw_off in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var off: Vector2i = raw_off
			var nxt: Vector2i = cell + off
			if visited.has(nxt) or not cfg.grid_in_arena(nxt):
				continue
			if int(grid.get(nxt, cfg.GRID_SAFE)) == cfg.GRID_DANGER:
				continue
			visited[nxt] = true
			queue.append([nxt, depth + 1])
	return out


func _has_safe_corridor(cfg, grid: Dictionary, cell: Vector2i) -> bool:
	for ox in range(cfg.SAFE_CORRIDOR_MIN_CELLS):
		for oy in range(cfg.SAFE_CORRIDOR_MIN_CELLS):
			var ok: bool = true
			for dx in range(cfg.SAFE_CORRIDOR_MIN_CELLS):
				for dy in range(cfg.SAFE_CORRIDOR_MIN_CELLS):
					var c: Vector2i = Vector2i(cell.x - ox + dx, cell.y - oy + dy)
					if not cfg.grid_in_arena(c) or int(grid.get(c, cfg.GRID_SAFE)) != cfg.GRID_SAFE:
						ok = false
			if ok:
				return true
	return false


func _safety_region_connected(cfg, grid: Dictionary) -> bool:
	var dim: int = cfg.grid_dims()
	var passable: Dictionary = {}
	var first := Vector2i(-1, -1)
	for gx in range(dim):
		for gy in range(dim):
			var cell := Vector2i(gx, gy)
			if not cfg.grid_in_arena(cell):
				continue
			if int(grid.get(cell, cfg.GRID_SAFE)) == cfg.GRID_DANGER:
				continue
			passable[cell] = true
			if first.x < 0:
				first = cell
	if first.x < 0:
		return false
	var seen: Dictionary = {}
	var queue: Array = [first]
	seen[first] = true
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for raw_off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var off: Vector2i = raw_off
			var nxt: Vector2i = cell + off
			if seen.has(nxt) or not passable.has(nxt):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return seen.size() >= passable.size()


func safety_check(stage: Node3D, cand: Dictionary, _interval: float) -> bool:
	var cfg = stage.C
	var players: Dictionary = stage._players
	var hazards: Dictionary = stage._hazards
	var srv_time: float = float(stage._srv_time)

	var alive_players: Array = []
	for net_id in players.keys():
		var p: Dictionary = players[net_id]
		if bool(p["alive"]):
			alive_players.append(p)
	if alive_players.is_empty():
		return false

	for raw in alive_players:
		var p: Dictionary = raw
		var flat := Vector2(p["pos"].x, p["pos"].z)
		if _min_distance_to_hazard(cfg, flat, cand) < cfg.HAZARD_MIN_PLAYER_DISTANCE:
			return false

	var probe: Dictionary = cand.duplicate(true)
	probe["active_start"] = srv_time + float(cand["warn"])
	probe["end_time"] = srv_time + float(cand["warn"]) + float(cand["active"])
	var existing: Array = []
	for raw in hazards.values():
		var h: Dictionary = raw
		if int(h["state"]) != cfg.HAZARD_STATE_DONE:
			existing.append(h)
	existing.append(probe)
	var grid: Dictionary = _build_danger_grid(stage, existing, cfg.SAFETY_HORIZON_SEC)

	var reach: int = int(floor(float(cand["warn"]) * cfg.PLAYER_MOVE_SPEED / cfg.GRID_CELL))
	for raw in alive_players:
		var p: Dictionary = raw
		var flat := Vector2(p["pos"].x, p["pos"].z)
		var cells: Array = _bfs_reachable(cfg, grid, cfg.grid_index(flat), maxi(2, reach))
		var found: bool = false
		for raw_cell in cells:
			var cell: Vector2i = raw_cell
			if int(grid.get(cell, cfg.GRID_SAFE)) != cfg.GRID_SAFE:
				continue
			if _has_safe_corridor(cfg, grid, cell):
				found = true
				break
		if not found:
			return false

	return _safety_region_connected(cfg, grid)


func commit_hazard(stage: Node3D, cand: Dictionary) -> void:
	var cfg = stage.C
	var srv_time: float = float(stage._srv_time)
	var h: Dictionary = cand.duplicate(true)
	h["id"] = int(stage._next_hazard_id)
	stage._next_hazard_id = int(stage._next_hazard_id) + 1
	h["warn_start"] = srv_time
	h["active_start"] = srv_time + float(cand["warn"])
	h["end_time"] = h["active_start"] + float(cand["active"])
	h["state"] = cfg.HAZARD_STATE_WARN
	stage._hazards[int(h["id"])] = h
	stage._last_type_spawn[int(h["type"])] = srv_time
	if int(h["type"]) == cfg.HZ_FLAME and int(h["nozzle"]) >= 0:
		stage._nozzle_cooldown[int(h["nozzle"])] = srv_time
	create_hazard_visual(stage, h)
	if stage._sfx_warn != null:
		stage._sfx_warn.play()
	if not bool(stage._standalone_mode) and stage.multiplayer.is_server():
		stage._rpc_hazard_spawn.rpc(h)


func apply_remote_spawn(stage: Node3D, h: Dictionary) -> void:
	if stage._hazards.has(int(h["id"])):
		return
	stage._hazards[int(h["id"])] = h
	create_hazard_visual(stage, h)
	if stage._sfx_warn != null:
		stage._sfx_warn.play()


func create_hazard_visual(stage: Node3D, h: Dictionary) -> void:
	var cfg = stage.C
	var meshes = stage.M
	var hazard_root: Node3D = stage._hazard_root
	var pack := Node3D.new()
	pack.name = "Hazard_%d" % int(h["id"])
	hazard_root.add_child(pack)
	var hz_type: int = int(h["type"])
	if hz_type == cfg.HZ_LASER:
		var rig: Node3D = meshes.build_laser_rig(
			h["a"], h["b"], float(h["width"]),
			float(h.get("gap_t", 0.5)), float(h.get("gap_width", cfg.LASER_GAP_WIDTH))
		)
		pack.add_child(rig)
		stage._hazard_nodes[int(h["id"])] = {
			"warn": null,
			"active": rig,
			"saw": null,
			"root": pack,
			"has_light": false,
			"is_laser_rig": true,
		}
		return

	var warn_node: Node3D = meshes.build_hazard_warning(hz_type, h["a"], h["b"], float(h["width"]))
	pack.add_child(warn_node)
	var active_node: Node3D = meshes.build_hazard_active(hz_type, h["a"], h["b"], float(h["width"]))
	pack.add_child(active_node)
	var saw_node: Node3D = null
	var has_light: bool = false
	if hz_type == cfg.HZ_SAW:
		has_light = int(stage._active_saw_lights) < MAX_ACTIVE_SAW_LIGHTS
		if has_light:
			stage._active_saw_lights = int(stage._active_saw_lights) + 1
		saw_node = meshes.build_saw_body(cfg.SAW_RADIUS, has_light)
		pack.add_child(saw_node)
	active_node.visible = false
	stage._hazard_nodes[int(h["id"])] = {
		"warn": warn_node,
		"active": active_node,
		"saw": saw_node,
		"root": pack,
		"has_light": has_light,
		"is_laser_rig": false,
	}


func update_hazard_states(stage: Node3D, t: float) -> void:
	var cfg = stage.C
	var arena_radius: float = float(stage._arena_radius)
	var hazards: Dictionary = stage._hazards
	for hid in hazards.keys():
		var h: Dictionary = hazards[hid]
		var state: int = cfg.HAZARD_STATE_WARN
		if t >= float(h["end_time"]):
			state = cfg.HAZARD_STATE_DONE
		elif t >= float(h["active_start"]):
			state = cfg.HAZARD_STATE_ACTIVE
		h["state"] = state
		if int(h["type"]) == cfg.HZ_SAW:
			var prog: float = 0.0
			if state == cfg.HAZARD_STATE_ACTIVE:
				prog = clampf(
					(t - float(h["active_start"])) * float(h["speed"]) / maxf(0.001, float(h["length"])),
					0.0, 1.0
				)
			h["saw_t"] = prog
			h["saw_pos"] = (h["a"] as Vector2).lerp(h["b"] as Vector2, prog)
		elif int(h["type"]) == cfg.HZ_LASER and state == cfg.HAZARD_STATE_ACTIVE:
			var s_speed: float = float(h.get("sweep_speed", 0.0))
			if s_speed > 0.01:
				var dt_act: float = maxf(0.0, t - float(h["active_start"]))
				var d_now: float = clampf(
					float(h.get("d_base", h["d"])) + float(h.get("sweep_dir", 1.0)) * s_speed * dt_act,
					-arena_radius + 0.4,
					arena_radius - 0.4
				)
				var ends: Array = cfg.chord_endpoints(h["n"], d_now, arena_radius)
				h["d"] = d_now
				h["a"] = ends[0]
				h["b"] = ends[1]
		hazards[hid] = h


func step_hazards(stage: Node3D, _delta: float) -> void:
	var cfg = stage.C
	update_hazard_states(stage, float(stage._srv_time))
	var hazards: Dictionary = stage._hazards
	var hazard_nodes: Dictionary = stage._hazard_nodes
	if hazards.size() > 16:
		var done_ids: Array = []
		for hid in hazards.keys():
			if int(hazards[hid]["state"]) == cfg.HAZARD_STATE_DONE:
				done_ids.append(hid)
		for hid in done_ids:
			hazards.erase(hid)
			if hazard_nodes.has(hid):
				var pack: Dictionary = hazard_nodes[hid]
				if bool(pack.get("has_light", false)):
					stage._active_saw_lights = maxi(0, int(stage._active_saw_lights) - 1)
				var rnode = pack.get("root", null)
				if is_instance_valid(rnode):
					(rnode as Node3D).queue_free()
				hazard_nodes.erase(hid)
