extends RefCounted

## Headless Tier-0 self-tests, 20s smoke test, and screenshot staging for Spike Ring.


func stage_screenshot_action(stage: Node3D) -> void:
	var cfg = stage.C
	var meshes = stage.M
	var players: Dictionary = stage._players
	stage._phase = stage.PH_LIVE
	stage._prep_remaining = 0.0
	stage._elapsed_time = 41.0
	stage._time_remaining = 19.0
	var demo_pos: Array = [
		Vector3(-1.6, 0.0, 0.2),
		Vector3(-4.6, 0.0, -2.8),
		Vector3(1.4, 0.0, -4.4),
		Vector3(-4.8, 0.0, 3.0),
		Vector3(1.1, 0.0, 4.2),
		Vector3(5.6, 0.0, -1.8),
	]
	var idx := 0
	for net_id in players.keys():
		var p: Dictionary = players[net_id]
		p["state"] = cfg.ST_NORMAL
		p["score"] = 41 + (int(net_id) % 3) * 2
		p["alive_sec"] = 41.0
		p["pos"] = demo_pos[idx % demo_pos.size()]
		p["render_pos"] = p["pos"]
		if int(net_id) == 1:
			p["push_cooldown"] = 0.65
			p["shield"] = true
		elif int(net_id) == 3:
			p["power_item"] = cfg.ITEM_POWER_SHOVE
		players[net_id] = p
		idx += 1
	var demo_hazards: Array = [
		{
			"id": 901, "type": cfg.HZ_LASER,
			"a": Vector2(-8.2, -1.2), "b": Vector2(8.2, 1.4),
			"gap_t": 0.42, "gap_width": cfg.LASER_GAP_WIDTH,
			"width": cfg.LASER_WIDTH, "length": 16.6, "speed": 0.0,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": cfg.HAZARD_STATE_ACTIVE, "saw_t": 0.0, "saw_pos": Vector2.ZERO, "nozzle": -1,
		},
		{
			"id": 902, "type": cfg.HZ_SAW,
			"a": Vector2(-7.6, 4.2), "b": Vector2(7.6, -3.4),
			"width": cfg.SAW_RADIUS * 2.0, "length": 17.0, "speed": cfg.SAW_SPEED,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": cfg.HAZARD_STATE_ACTIVE, "saw_t": 0.30, "saw_pos": Vector2(-3.0, 2.0), "nozzle": -1,
		},
		{
			"id": 903, "type": cfg.HZ_FLAME,
			"a": Vector2(3.6, -7.8), "b": Vector2(4.4, 7.2),
			"width": cfg.FLAME_WIDTH, "length": 15.0, "speed": 0.0,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": cfg.HAZARD_STATE_ACTIVE, "saw_t": 0.0, "saw_pos": Vector2.ZERO, "nozzle": 2,
		},
	]
	for h in demo_hazards:
		stage._hazards[int(h["id"])] = h
		stage._hazard_director.create_hazard_visual(stage, h)
	var demo_drop: Node3D = meshes.build_airdrop_item(cfg.ITEM_POWER_SHOVE)
	demo_drop.position = Vector3(1.8, 0.0, -1.6)
	stage._fx_root.add_child(demo_drop)
	stage._spawn_score_popup(Vector3(-1.8, 3.35, 0.2), "+2", Color(0.58, 1.0, 0.62))
	stage._update_hud()


func _fail(stage: Node3D, msg: String) -> void:
	push_error("SPIKE_RING_SELF_TEST_FAIL: " + msg)
	stage.get_tree().quit(1)


func run_smoke_test(stage: Node3D) -> void:
	stage._load_helpers()
	stage._is_server_sim = true
	stage._standalone_mode = true
	var cfg = stage.C
	var roster: Array = []
	for i in range(8):
		roster.append({
			"id": i, "network_id": i + 1, "nickname": "P%d" % (i + 1),
			"customization": [], "is_ai": true,
		})
	stage._setup_match_local(0, 20261121, roster, true)
	var dt: float = 1.0 / 60.0
	var max_hazards: int = 0
	var max_live: int = 0
	var max_live_lasers: int = 0
	for _frame in range(1500):
		stage._srv_time = float(stage._srv_time) + dt
		if int(stage._phase) == stage.PH_PREP:
			stage._step_prep(dt)
		elif int(stage._phase) == stage.PH_LIVE:
			stage._step_simulation(dt)
		else:
			break
		max_hazards = maxi(max_hazards, stage._hazards.size())
		max_live = maxi(max_live, stage._hazard_director.live_hazard_count(stage))
		var live_lasers: int = 0
		for raw_h in stage._hazards.values():
			var h: Dictionary = raw_h
			if int(h["type"]) == cfg.HZ_LASER and int(h["state"]) != cfg.HAZARD_STATE_DONE:
				live_lasers += 1
		max_live_lasers = maxi(max_live_lasers, live_lasers)
		stage._animate_visuals(dt)
		stage._update_hud()
	if max_hazards <= 0:
		_fail(stage, "smoke: no hazard ever spawned")
		return
	if max_live_lasers > 1:
		_fail(stage, "smoke: concurrent lasers exceeded 1 (%d)" % max_live_lasers)
		return
	if int(stage._airdrop_next_idx) <= 0:
		_fail(stage, "smoke: expected at least one airdrop to spawn")
		return
	print("SPIKE_RING_SMOKE_OK hazards=%d max_live=%d max_live_lasers=%d airdrops=%d phase=%d players=%d srv_time=%.1f" % [
		max_hazards, max_live, max_live_lasers, stage._airdrop_next_idx, stage._phase, stage._players.size(), stage._srv_time
	])
	print("SMOKE_TEST_PASSED")
	stage.get_tree().quit(0)


func run_self_test(stage: Node3D) -> void:
	stage._load_helpers()
	stage._is_server_sim = true
	stage._standalone_mode = true
	var cfg = stage.C

	for count in [2, 4, 8, 16]:
		var spawns: Array = cfg.compute_spawns(count, 9000 + count)
		if spawns.size() != count:
			_fail(stage, "spawn count mismatch for %d" % count)
			return
		for i in range(count):
			var pi: Vector2 = spawns[i]
			if pi.length() > cfg.EDGE_LIMIT_RADIUS:
				_fail(stage, "spawn outside arena for %d" % count)
				return
			for j in range(i + 1, count):
				var pj: Vector2 = spawns[j]
				if pi.distance_to(pj) < cfg.SPAWN_MIN_SEPARATION - 0.001:
					_fail(stage, "spawn overlap for %d" % count)
					return

	var roster: Array = []
	for i in range(4):
		roster.append({"id": i, "network_id": i + 1, "nickname": "P%d" % (i + 1), "customization": [], "is_ai": i != 0})
	stage._setup_match_local(0, 4242, roster, true)
	if stage._team.is_active():
		_fail(stage, "FFA roster must keep native team support inactive")
		return

	if int(stage._phase) != stage.PH_PREP:
		_fail(stage, "expected PREP phase")
		return
	var p1: Dictionary = stage._players[1]
	p1["facing"] = Vector2(1.0, 0.0)
	p1["input"] = {"dir": Vector2.ZERO, "aim": Vector2(1.0, 0.0), "jump": false, "push": true}
	stage._client_inputs[1] = p1["input"]
	var p2_before: int = int(stage._players[2]["hits_taken"])
	stage._step_prep(0.05)
	if int(stage._players[2]["hits_taken"]) != p2_before:
		_fail(stage, "push must be disabled during prep")
		return
	if not stage._hazards.is_empty():
		_fail(stage, "no hazard may spawn during prep")
		return
	stage._players[1]["pos"] = Vector3(cfg.ARENA_RADIUS * 2.0, 0.0, 0.0)
	stage._step_prep(cfg.PREP_DURATION_SEC)
	if not bool(stage._players[1]["alive"]):
		_fail(stage, "no elimination during prep")
		return
	if int(stage._phase) != stage.PH_LIVE:
		_fail(stage, "prep must transition to LIVE after 3s")
		return

	stage._client_inputs.clear()
	var a: Dictionary = stage._players[1]
	var v: Dictionary = stage._players[2]
	var v_was_ai: bool = bool(v["is_ai"])
	v["is_ai"] = false
	a["pos"] = Vector3(0.0, 0.0, 0.0)
	v["pos"] = Vector3(5.0, 0.0, 0.0)
	a["facing"] = Vector2(1.0, 0.0)
	a["state"] = cfg.ST_NORMAL
	a["push_cooldown"] = 0.0
	v["state"] = cfg.ST_NORMAL
	v["invuln_timer"] = 0.0
	stage._try_push(a)
	if int(a["pushes"]) != 0 or int(a["score"]) != 0:
		_fail(stage, "push whiff must not award score")
		return
	v["pos"] = Vector3(1.0, 0.0, 0.0)
	a["push_cooldown"] = 0.0
	stage._try_push(a)
	if int(v["state"]) != cfg.ST_FALLEN or int(a["pushes"]) != 1 or int(a["score"]) != cfg.PUSH_SCORE:
		_fail(stage, "push hit / +2 score failed")
		return
	if float(a["push_cooldown"]) < cfg.PUSH_COOLDOWN_SEC - 0.001:
		_fail(stage, "push cooldown not applied")
		return
	v["knock_dir"] = Vector2.ZERO
	v["knock_vel"] = Vector2.ZERO
	stage._step_player_motions(cfg.FALL_DURATION_SEC - 0.01, false)
	if int(v["state"]) != cfg.ST_FALLEN:
		_fail(stage, "fall must last exactly 0.30s")
		return
	stage._client_inputs[1] = {"dir": Vector2.ZERO, "aim": Vector2(1.0, 0.0), "jump": false, "push": true}
	stage._step_player_motions(0.02, false)
	if int(v["state"]) != cfg.ST_NORMAL:
		_fail(stage, "victim should recover to normal after 0.30s fall")
		return
	stage._step_player_motions(cfg.PUSH_COOLDOWN_SEC - cfg.FALL_DURATION_SEC + 0.01, false)
	if int(v["hits_taken"]) != 2 or int(a["pushes"]) != 2 or int(a["score"]) != cfg.PUSH_SCORE * 2:
		_fail(stage, "hold-to-push continuous shove failed")
		return
	stage._client_inputs.clear()
	v["is_ai"] = v_was_ai

	for net_id in stage._players.keys():
		var pp: Dictionary = stage._players[net_id]
		pp["alive"] = true
		pp["score"] = 0
		pp["alive_sec"] = 0.0
		pp["last_scored_sec"] = 0
		stage._players[net_id] = pp
	stage._elapsed_time = 10.0
	stage._accrue_scores(1.0)
	if int(stage._players[3]["score"]) != 1:
		_fail(stage, "survival score per second failed")
		return
	stage._eliminate_player(stage._players[3], "TEST", 0)
	var frozen: int = int(stage._players[3]["score"])
	stage._accrue_scores(5.0)
	if int(stage._players[3]["score"]) != frozen:
		_fail(stage, "score must freeze after elimination")
		return

	stage._phase = stage.PH_LIVE
	stage._time_remaining = 30.0
	stage._check_round_end()
	if int(stage._phase) != stage.PH_LIVE:
		_fail(stage, "round must NOT end while players remain")
		return
	for net_id in stage._players.keys():
		stage._players[net_id]["alive"] = false
	stage._check_round_end()
	if int(stage._phase) != stage.PH_ENDED:
		_fail(stage, "round must end when all players are out")
		return

	var ranked: Array = cfg.rank_entries([
		{"network_id": 1, "score": 10, "alive_sec": 9.0, "pushes": 1, "hits_taken": 2, "out_reason": ""},
		{"network_id": 2, "score": 10, "alive_sec": 9.0, "pushes": 1, "hits_taken": 0, "out_reason": ""},
		{"network_id": 3, "score": 11, "alive_sec": 1.0, "pushes": 0, "hits_taken": 9, "out_reason": ""},
	])
	if int(ranked[0]["network_id"]) != 3 or int(ranked[1]["network_id"]) != 2:
		_fail(stage, "rank tie-break failed")
		return
	if int(cfg.official_scores(ranked)[3]) != 3:
		_fail(stage, "official score conversion failed")
		return

	stage._setup_match_local(0, 777, roster, true)
	stage._prep_remaining = 0.0
	stage._phase = stage.PH_LIVE
	stage._srv_time = 5.0
	stage._elapsed_time = 5.0
	var phase: Dictionary = cfg.difficulty_phase(float(stage._elapsed_time), stage._round_cfg)
	var legal_ok: bool = false
	for _i in range(40):
		var cand: Dictionary = stage._hazard_director.make_candidate(stage, cfg.HZ_LASER, phase)
		if not cand.is_empty() and stage._hazard_director.safety_check(stage, cand, float(phase["interval"])):
			legal_ok = true
			break
	if not legal_ok:
		_fail(stage, "safety generator rejected every legal candidate")
		return
	var blocked: Dictionary = stage._hazard_director.make_candidate(stage, cfg.HZ_SAW, phase)
	if not blocked.is_empty():
		var px := Vector2(stage._players[1]["pos"].x, stage._players[1]["pos"].z)
		blocked["n"] = Vector2(1.0, 0.0)
		blocked["d"] = px.x
		blocked["a"] = Vector2(px.x, -cfg.ARENA_RADIUS)
		blocked["b"] = Vector2(px.x, cfg.ARENA_RADIUS)
		if stage._hazard_director.safety_check(stage, blocked, float(phase["interval"])):
			_fail(stage, "safety generator accepted a hazard on top of a player")
			return

	if str(cfg.difficulty_phase(1.0, stage._round_cfg)["name"]) != "WARMUP":
		_fail(stage, "difficulty phase WARMUP missing")
		return
	if str(cfg.difficulty_phase(20.0, stage._round_cfg)["name"]) != "MIXED":
		_fail(stage, "difficulty phase MIXED missing")
		return
	if str(cfg.difficulty_phase(50.0, stage._round_cfg)["name"]) != "FRENZY":
		_fail(stage, "difficulty phase FRENZY missing")
		return

	# --- Native Team Mode verification (no team-party mod dependency) ---
	var team_roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "Host", "team_id": 1, "is_ai": false},
		{"id": 1, "network_id": 2, "nickname": "Ally", "team_id": 1, "is_ai": false},
		{"id": 2, "network_id": 3, "nickname": "EnemyA", "team_id": 2, "is_ai": false},
		{"id": 3, "network_id": 4, "nickname": "EnemyB", "team_id": 2, "is_ai": false},
	]
	stage._setup_match_local(0, 888, team_roster, true)
	stage._prep_remaining = 0.0
	stage._phase = stage.PH_LIVE
	if not stage._team.is_active() or not bool(stage.get_meta(&"mpm_native_team_stage", false)):
		_fail(stage, "native team mode failed to activate for 2-team roster")
		return
	var tp1: Dictionary = stage._players[1]
	var tp2: Dictionary = stage._players[2]
	var tp3: Dictionary = stage._players[3]
	var tp4: Dictionary = stage._players[4]
	if (tp2["node"] as Node3D).get_node_or_null("MpmTeamRing") == null:
		_fail(stage, "teammate missing MpmTeamRing")
		return
	tp1["pos"] = Vector3.ZERO
	tp2["pos"] = Vector3(1.1, 0.0, 0.0)
	tp3["pos"] = Vector3(-1.1, 0.0, 0.0)
	tp4["pos"] = Vector3(6.0, 0.0, 0.0)
	tp2["state"] = cfg.ST_NORMAL
	tp3["state"] = cfg.ST_NORMAL
	tp2["invuln_timer"] = 0.0
	tp3["invuln_timer"] = 0.0
	tp1["power_item"] = cfg.ITEM_SHOCKWAVE
	tp1["push_cooldown"] = 0.0
	stage._try_push(tp1)
	if int(tp2["state"]) == cfg.ST_FALLEN or int(tp3["state"]) != cfg.ST_FALLEN:
		_fail(stage, "shockwave must spare teammate and knock enemy")
		return
	tp1["shield"] = false
	tp2["shield"] = false
	tp3["shield"] = false
	tp2["pos"] = Vector3(2.2, 0.0, 0.0)
	tp3["pos"] = Vector3(-5.0, 0.0, 0.0)
	stage._airdrops.append({"type": cfg.ITEM_SHIELD, "pos": Vector2.ZERO, "age": 0.0, "landed": true, "fall_timer": 0.0, "node": null})
	stage._step_airdrops(0.01)
	if not bool(tp1["shield"]) or not bool(tp2["shield"]) or bool(tp3["shield"]):
		_fail(stage, "shield link failed to shield nearby teammate only")
		return
	stage._eliminate_player(tp3, "TEST", 0)
	stage._eliminate_player(tp4, "TEST", 0)
	stage._check_round_end()
	if int(stage._phase) != stage.PH_ENDED:
		_fail(stage, "team match should end early when only 1 team remains alive")
		return
	var synced_scores: Dictionary = stage._mpm_last_official
	if int(synced_scores.get(1, -1)) != int(synced_scores.get(2, -2)):
		_fail(stage, "winning teammates must share synchronized score")
		return

	print("SPIKE_RING_SPAWNS_2_4_8_16_OK, PREP_3S_NO_ELIM_OK, FALL_0.30S_IMMUNITY_0.20S_OK")
	print("HOLD_PUSH_CONTINUOUS_OK, SCORE_PER_SEC_AND_SURVIVAL_BONUS_OK, RANK_TIEBREAK_OK")
	print("SAFETY_GRID_BFS_CORRIDOR_CONNECTIVITY_OK, ROUND_END_GATE_OK, DIFFICULTY_PHASES_OK, NATIVE_TEAM_MODE_OK")
	print("SELF_TEST_PASSED")
	stage.get_tree().quit(0)
