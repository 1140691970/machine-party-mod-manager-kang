extends RefCounted

## Tactical AI controller for Spike Ring (hazard dodging, airdrop pickup, enemy-only shoving).


func compute_input(stage: Node3D, p: Dictionary, delta: float, prep: bool) -> Dictionary:
	var cfg = stage.C
	var rng: RandomNumberGenerator = stage._rng
	var elapsed: float = float(stage._elapsed_time)
	var arena_r: float = float(stage._arena_radius)
	var hazards: Dictionary = stage._hazards
	var airdrops: Array = stage._airdrops
	var players: Dictionary = stage._players
	var team = stage._team

	p["ai_timer"] = float(p.get("ai_timer", 0.0)) - delta
	if float(p["ai_timer"]) <= 0.0:
		p["ai_timer"] = rng.randf_range(0.35, 0.95)
		var a: float = rng.randf() * TAU
		p["ai_dir"] = Vector2(cos(a), sin(a))

	var pos := Vector2(p["pos"].x, p["pos"].z)
	var avoid := Vector2.ZERO
	var want_jump: bool = false
	var want_push: bool = false
	var aim_dir: Vector2 = p.get("facing", Vector2(0.0, 1.0))

	# 1. Stay inside the shrinking spike perimeter.
	var live_edge: float = float(cfg.current_arena_radius(elapsed, arena_r)) - float(cfg.PLAYER_RADIUS)
	var edge_dist: float = pos.length()
	if edge_dist > live_edge * 0.65:
		var pull: float = clampf((edge_dist - live_edge * 0.65) / maxf(0.1, live_edge * 0.35), 0.0, 1.0)
		avoid += -pos.normalized() * (1.2 + pull * 2.6)

	# 2. Steer away from active/warning hazards.
	if not prep:
		for raw in hazards.values():
			var h: Dictionary = raw
			var st: int = int(h["state"])
			if st == cfg.HAZARD_STATE_DONE:
				continue
			var hz_type: int = int(h["type"])
			var ha: Vector2 = h["a"]
			var hb: Vector2 = h["b"]
			if hz_type == cfg.HZ_SAW:
				var sp: Vector2 = h["saw_pos"] if st == cfg.HAZARD_STATE_ACTIVE else ha
				var to_me: Vector2 = pos - sp
				var d_saw: float = to_me.length()
				if d_saw < 2.8:
					var seg_dir: Vector2 = (hb - ha).normalized()
					var perp := Vector2(-seg_dir.y, seg_dir.x)
					if perp.dot(to_me) < 0.0:
						perp = -perp
					avoid += (perp * 2.6 + to_me.normalized() * 1.0) * (1.0 - d_saw / 2.8)
			elif hz_type == cfg.HZ_LASER:
				var total_len: float = ha.distance_to(hb)
				var d_seg: float = cfg.point_chord_distance(pos, h["n"], float(h["d"]))
				var half_w: float = float(h["width"]) * 0.5 + float(cfg.PLAYER_RADIUS)
				if total_len > 0.2 and d_seg < half_w + 3.2:
					var seg_dir: Vector2 = (hb - ha) / total_len
					var gap_t: float = float(h.get("gap_t", 0.5))
					var gap_w: float = float(h.get("gap_width", cfg.LASER_GAP_WIDTH))
					var gap_c: float = clampf(gap_t * total_len, gap_w * 0.65, total_len - gap_w * 0.65)
					var gap_pt: Vector2 = ha + seg_dir * gap_c
					var to_gap: Vector2 = gap_pt - pos
					if to_gap.length() > 0.35:
						avoid += to_gap.normalized() * (2.6 if st == cfg.HAZARD_STATE_ACTIVE else 1.7)
					else:
						var perp := Vector2(-seg_dir.y, seg_dir.x)
						if perp.dot(pos - gap_pt) < 0.0:
							perp = -perp
						avoid += perp * 0.8
			else:
				var d_seg: float = cfg.point_chord_distance(pos, h["n"], float(h["d"]))
				var half_w: float = float(h["width"]) * 0.5 + float(cfg.PLAYER_RADIUS)
				if d_seg < half_w + 1.8:
					var seg_dir: Vector2 = (hb - ha).normalized()
					var perp := Vector2(-seg_dir.y, seg_dir.x)
					if perp.dot(pos - (ha + hb) * 0.5) < 0.0:
						perp = -perp
					avoid += perp * (2.8 if st == cfg.HAZARD_STATE_ACTIVE else 1.8)

	# 2b. Seek nearby landed airdrops when safe.
	if not prep and avoid.length() < 1.2 and not airdrops.is_empty():
		var best_ad_dist: float = 999.0
		var best_ad_pos := Vector2.ZERO
		for raw_ad in airdrops:
			var ad: Dictionary = raw_ad
			if not bool(ad["landed"]):
				continue
			var adp: Vector2 = ad["pos"]
			var d_ad: float = pos.distance_to(adp)
			if d_ad < best_ad_dist:
				best_ad_dist = d_ad
				best_ad_pos = adp
		if best_ad_dist < 7.5:
			avoid += (best_ad_pos - pos).normalized() * 1.15

	# 3. Shove nearby opponents (excluding teammates in team mode).
	var my_id: int = int(p["network_id"])
	var closest_rival := Vector2.ZERO
	var closest_dist: float = 999.0
	if not prep and avoid.length() < 1.2 and float(p["push_cooldown"]) <= 0.0:
		for other_id in players.keys():
			var oid: int = int(other_id)
			if oid == my_id:
				continue
			if team != null and team.is_active() and team.are_teammates(my_id, oid):
				continue
			var other: Dictionary = players[other_id]
			if not bool(other["alive"]) or int(other["state"]) == cfg.ST_FALLEN or float(other["invuln_timer"]) > 0.0:
				continue
			var op := Vector2(other["pos"].x, other["pos"].z)
			var d: float = pos.distance_to(op)
			if d < closest_dist:
				closest_dist = d
				closest_rival = op
		if closest_dist <= float(cfg.PUSH_RANGE) * 0.92:
			aim_dir = (closest_rival - pos).normalized()
			want_push = true
		elif closest_dist < 4.0:
			avoid += (closest_rival - pos).normalized() * 0.65

	var dir: Vector2 = (p.get("ai_dir", Vector2.ZERO) * 0.45 + avoid).limit_length(1.0)
	if not want_push and dir.length_squared() > 0.01:
		aim_dir = dir.normalized()
	return {
		"dir": dir,
		"aim": aim_dir,
		"jump": want_jump,
		"push": want_push,
	}
