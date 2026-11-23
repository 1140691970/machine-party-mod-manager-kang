extends RefCounted

## 4-state tactical co-op AI controller for Core Heist:
## 1. Co-op Escort: stay within 2.0m of same-team Core carrier & shove nearby enemies.
## 2. Carrier: return carried battery to own vault; throw within 2.2m.
## 3. Defender: intercept enemies fleeing own vault with a battery (< 4.5m) & shove.
## 4. Collector / Raider: target unlocked Core > Gold > leading enemy unlocked vault > Standard.


func _steer_around_obstacles(pos2: Vector2, target2: Vector2, cfg, pillars: Array) -> Vector2:
	var to_t: Vector2 = target2 - pos2
	var dist: float = to_t.length()
	if dist < 0.05:
		return Vector2.ZERO
	var dir: Vector2 = to_t / dist
	# Avoid central dispenser
	var d_disp: float = pos2.length()
	if d_disp < float(cfg.DISPENSER_RADIUS) + 1.15 and pos2.dot(dir) < 0.0:
		var perp := Vector2(-pos2.y, pos2.x).normalized()
		if perp.dot(dir) < 0.0:
			perp = -perp
		dir = (dir + perp * 1.4).normalized()
	# Avoid pillars
	for raw_pil in pillars:
		var pil: Vector2 = raw_pil as Vector2
		var away: Vector2 = pos2 - pil
		if away.length() < float(cfg.PILLAR_RADIUS) + 1.05 and away.dot(dir) < 0.0:
			var perp := Vector2(-away.y, away.x).normalized()
			if perp.dot(dir) < 0.0:
				perp = -perp
			dir = (dir + perp * 1.2).normalized()
	return dir


func compute_input(stage: Node3D, p: Dictionary, _delta: float, prep: bool) -> Dictionary:
	if prep or float(p.get("stun_timer", 0.0)) > 0.0:
		return {"move": Vector2.ZERO, "action": false}

	var cfg = stage.C
	var my_id: int = int(p["network_id"])
	var my_team: int = int(p.get("team_id", 0))
	var pos3: Vector3 = p["pos"] as Vector3
	var pos2 := Vector2(pos3.x, pos3.z)
	var vault_by_team: Dictionary = stage._vault_by_team
	var pillars: Array = stage._pillars
	var players: Dictionary = stage._players
	var batteries: Array = stage._batteries
	var team_scores: Dictionary = stage._team_scores

	var own_vault: Vector2 = vault_by_team.get(my_team, Vector2.ZERO) as Vector2

	var want_action: bool = false
	var target2: Vector2 = own_vault

	# State 2: Carrier — return to own vault and throw when within 2.2m
	var carried_idx: int = int(p.get("carried_battery", -1))
	if carried_idx >= 0:
		var dist_vault: float = pos2.distance_to(own_vault)
		if dist_vault <= 2.2:
			var to_v: Vector2 = (own_vault - pos2).normalized()
			var facing: Vector2 = p.get("facing", Vector2(0.0, 1.0)) as Vector2
			if facing.dot(to_v) > 0.65:
				want_action = true
			return {"move": to_v, "action": want_action}
		return {"move": _steer_around_obstacles(pos2, own_vault, cfg, pillars), "action": false}

	# State 1: Co-op Escort — protect & resonate with same-team Core carrier
	var core_carrier_pos := Vector2.ZERO
	var has_core_carrier: bool = false
	for raw_other in players.values():
		var other: Dictionary = raw_other as Dictionary
		if not bool(other.get("connected", true)):
			continue
		var oid: int = int(other["network_id"])
		if oid == my_id or int(other.get("team_id", 0)) != my_team:
			continue
		var ob_idx: int = int(other.get("carried_battery", -1))
		if ob_idx >= 0 and ob_idx < batteries.size():
			var ob: Dictionary = batteries[ob_idx] as Dictionary
			if int(ob.get("type", 0)) == int(cfg.CELL_CORE):
				var op3: Vector3 = other["pos"] as Vector3
				core_carrier_pos = Vector2(op3.x, op3.z)
				has_core_carrier = true
				break

	if has_core_carrier:
		# Check for nearby enemies threatening the core carrier
		var near_enemy_dist: float = 999.0
		var near_enemy_pos := Vector2.ZERO
		for raw_other in players.values():
			var other: Dictionary = raw_other as Dictionary
			if not bool(other.get("connected", true)) or int(other.get("team_id", 0)) == my_team:
				continue
			var op3: Vector3 = other["pos"] as Vector3
			var op2 := Vector2(op3.x, op3.z)
			var d_carrier: float = op2.distance_to(core_carrier_pos)
			if d_carrier < 2.5:
				var d_me: float = pos2.distance_to(op2)
				if d_me < near_enemy_dist:
					near_enemy_dist = d_me
					near_enemy_pos = op2
		if near_enemy_dist < 2.5:
			if near_enemy_dist <= float(cfg.SHOVE_RANGE) * 0.92 and float(p.get("shove_cooldown", 0.0)) <= 0.0:
				want_action = true
			return {"move": (near_enemy_pos - pos2).normalized(), "action": want_action}
		var d_to_carrier: float = pos2.distance_to(core_carrier_pos)
		if d_to_carrier > 1.85:
			return {"move": _steer_around_obstacles(pos2, core_carrier_pos, cfg, pillars), "action": false}
		# Stay close along carrier->vault line
		var escort_pt: Vector2 = core_carrier_pos.lerp(own_vault, 0.25)
		return {"move": _steer_around_obstacles(pos2, escort_pt, cfg, pillars), "action": false}

	# State 4: Defender — intercept enemies fleeing own vault with a battery (< 4.5m from own vault)
	var thief_dist: float = 999.0
	var thief_pos := Vector2.ZERO
	for raw_other in players.values():
		var other: Dictionary = raw_other as Dictionary
		if not bool(other.get("connected", true)) or int(other.get("team_id", 0)) == my_team:
			continue
		if int(other.get("carried_battery", -1)) < 0:
			continue
		var op3: Vector3 = other["pos"] as Vector3
		var op2 := Vector2(op3.x, op3.z)
		if op2.distance_to(own_vault) < 4.5:
			var d_me: float = pos2.distance_to(op2)
			if d_me < thief_dist:
				thief_dist = d_me
				thief_pos = op2
	if thief_dist < 8.0:
		if thief_dist <= float(cfg.SHOVE_RANGE) * 0.92 and float(p.get("shove_cooldown", 0.0)) <= 0.0:
			want_action = true
		return {"move": _steer_around_obstacles(pos2, thief_pos, cfg, pillars), "action": want_action}

	# State 3: Collector / Raider — pick highest weighted available battery
	var leading_team: int = 0
	var leading_score: int = -1
	for tid_raw in team_scores.keys():
		var tid: int = int(tid_raw)
		if tid == my_team:
			continue
		var sc: int = int(team_scores[tid_raw])
		if sc > leading_score:
			leading_score = sc
			leading_team = tid

	var best_weight: float = -9999.0
	var found_bat: bool = false
	for raw_b in batteries:
		var b: Dictionary = raw_b as Dictionary
		if not bool(b.get("active", false)):
			continue
		var st: int = int(b.get("state", -1))
		if st == int(cfg.BAT_CARRIED) or st == int(cfg.BAT_THROWN):
			continue
		if st == int(cfg.BAT_DEPOSITED):
			var v_team: int = int(b.get("vault_team", 0))
			if v_team == my_team or bool(b.get("perm_locked", false)) or float(b.get("lock_timer", 0.0)) > 0.0:
				continue
		var bp3: Vector3 = b["pos"] as Vector3
		var bp2 := Vector2(bp3.x, bp3.z)
		var btype: int = int(b.get("type", 1))
		var base_val: float = 10.0
		if btype == int(cfg.CELL_CORE):
			base_val = 65.0
		elif btype == int(cfg.CELL_GOLD):
			base_val = 32.0
		if st == int(cfg.BAT_DEPOSITED):
			base_val += 8.0
			if int(b.get("vault_team", 0)) == leading_team:
				base_val += 10.0
		var w: float = base_val - pos2.distance_to(bp2) * 1.15
		if w > best_weight:
			best_weight = w
			target2 = bp2
			found_bat = true

	if not found_bat:
		target2 = Vector2(0.0, 3.2)
	return {"move": _steer_around_obstacles(pos2, target2, cfg, pillars), "action": false}
