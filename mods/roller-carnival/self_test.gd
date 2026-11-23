extends RefCounted

## Headless self-tests for Roller Carnival (FFA mechanics + wave pacing + native Team Mode).

var _tests_failed: bool = false


func _assert_true(stage: Node3D, cond: bool, msg: String) -> bool:
	if not cond:
		_tests_failed = true
		push_error("SELF_TEST_FAILED: " + msg)
		stage.get_tree().quit(1)
		return false
	return true


func _test_wave_pacing(stage: Node3D) -> bool:
	var cfg = stage.config
	stage._start_new_round()
	stage._players.clear()
	stage._rng.seed = 451
	const STEP := 1.0 / 60.0
	var early_double_frames := 0
	var late_double_frames := 0
	var late_triple_frames := 0
	var previous_arrival := -10.0
	var minimum_gap := INF
	var camera := stage.get_viewport().get_camera_3d()
	for frame in range(3000):
		stage._elapsed = (frame + 1) * STEP
		stage._step_spawner(STEP)
		stage._step_rollers(STEP)
		var visible_rollers := 0
		var approaching := 0
		for roller in stage._rollers:
			if camera.is_position_in_frustum(Vector3(roller.x, 1, 0)):
				visible_rollers += 1
				if roller.x >= cfg.player_spawn_x:
					approaching += 1
			if roller.x < cfg.player_spawn_x and not roller.has("arrival_measured"):
				minimum_gap = minf(minimum_gap, float(stage._elapsed) - previous_arrival)
				previous_arrival = float(stage._elapsed)
				roller.arrival_measured = true
		if float(stage._elapsed) <= 10.0 and approaching >= 2:
			early_double_frames += 1
		if float(stage._elapsed) > 40.0 and visible_rollers >= 2:
			late_double_frames += 1
			if visible_rollers >= 3:
				late_triple_frames += 1
	for x in [cfg.stage_left_lava_x, cfg.player_spawn_x]:
		for z in [-3.75, 3.75]:
			if not _assert_true(stage, camera.is_position_in_frustum(Vector3(x, 1.32, z)), "Players must stay visible up to the lava edge"):
				return false
	print("WAVE_PACING early double frames=%d/600, late doubles=%d/600, late triples=%d/600, min arrival gap=%.3f" % [early_double_frames, late_double_frames, late_triple_frames, minimum_gap])
	return _assert_true(stage, early_double_frames == 0 and late_double_frames > 300 and late_triple_frames >= 15 and minimum_gap >= cfg.safe_interval_floor(), "Late waves must be readable and allow consecutive jumps")


func run_self_tests(stage: Node3D) -> void:
	_tests_failed = false
	var cfg = stage.config

	cfg.max_players = 8
	stage._start_new_round()
	var ps: Array = stage._players
	if not _assert_true(stage, ps.size() == 8, "Must spawn 8 players when max_players=8"):
		return
	for i in range(ps.size()):
		if not _assert_true(stage, is_equal_approx(float(ps[i]["x"]), cfg.player_spawn_x), "All players must spawn on exact same starting line X"):
			return
		if i > 0 and not _assert_true(stage, float(ps[i]["z"]) > float(ps[i - 1]["z"]), "Players must be strictly separated along Z lanes"):
			return

	cfg.player_spawn_x = 2.6
	stage._start_new_round()
	for p in stage._players:
		if not _assert_true(stage, is_equal_approx(float(p["x"]), 2.6), "Configured player_spawn_x must move all player spawns"):
			return
	var sl_node := stage._scene_props.get("starting_line", null) as Node3D
	if not _assert_true(stage, sl_node != null and is_equal_approx(sl_node.position.x, 2.6), "Stage StartingLine mesh must sync with configured player_spawn_x"):
		return

	cfg.max_players = 16
	stage._start_new_round()
	if not _assert_true(stage, stage._players.size() == 16, "Must spawn 16 players when max_players=16"):
		return
	for p16 in stage._players:
		if not _assert_true(stage, is_equal_approx(float(p16["x"]), cfg.player_spawn_x), "All 16 players must spawn on exact same starting line X"):
			return
	cfg.max_players = 8
	cfg.player_spawn_x = 1.6

	cfg.max_players = 2
	stage._start_new_round()
	var p_stand: Dictionary = stage._players[0]
	var p_crouch: Dictionary = stage._players[1]
	p_stand["x"] = 0.0
	p_crouch["x"] = 0.0
	p_stand["crouching"] = false
	p_crouch["crouching"] = true

	var gold_r: Dictionary = stage._spawn_roller("gold", 0.1)
	stage._evaluate_roller_interactions(gold_r)
	if not _assert_true(stage, is_equal_approx(float(p_stand["x"]), -cfg.knockback_distance), "Standing player must be knocked back by Gold roller"):
		return
	if not _assert_true(stage, is_equal_approx(float(p_crouch["x"]), 0.0), "Crouching player must avoid Gold roller"):
		return

	gold_r["x"] = -2.8
	stage._evaluate_roller_interactions(gold_r)
	if not _assert_true(stage, int(p_stand["dodges"]) == 0, "Hit player must not gain dodge count"):
		return
	if not _assert_true(stage, int(p_crouch["dodges"]) == 1, "Crouching player must gain +1 dodge after Gold roller passes"):
		return

	p_stand["x"] = 0.0
	p_stand["knockback_cooldown"] = 0.0
	p_stand["crouching"] = true
	p_crouch["x"] = 0.0
	p_crouch["crouching"] = false
	p_crouch["jumping"] = true
	p_crouch["y"] = 1.2

	var silver_r: Dictionary = stage._spawn_roller("silver", 0.1)
	stage._evaluate_roller_interactions(silver_r)
	if not _assert_true(stage, is_equal_approx(float(p_stand["x"]), -cfg.knockback_distance), "Crouching player must be knocked back by Silver roller"):
		return
	if not _assert_true(stage, is_equal_approx(float(p_crouch["x"]), 0.0), "Jumping player must avoid Silver roller"):
		return

	silver_r["x"] = -2.8
	stage._evaluate_roller_interactions(silver_r)
	if not _assert_true(stage, int(p_stand["dodges"]) == 0, "Hit player must not gain dodge count for Silver roller"):
		return
	if not _assert_true(stage, int(p_crouch["dodges"]) == 2, "Jumping player must gain +1 dodge after Silver roller passes"):
		return

	p_stand["x"] = cfg.stage_left_lava_x + 0.5
	p_stand["knockback_cooldown"] = 0.0
	p_stand["crouching"] = false
	var push_r: Dictionary = stage._spawn_roller("gold", float(p_stand["x"]) + 0.1)
	stage._evaluate_roller_interactions(push_r)
	if not _assert_true(stage, not bool(p_stand["alive"]), "Player pushed past stage_left_lava_x must be eliminated"):
		return

	stage._eliminate_player(p_crouch)
	if not _assert_true(stage, not stage._results_panel.visible and not stage._countdown_label.visible, "Play must leave the stage unobstructed"):
		return

	stage._check_round_end()
	if not _assert_true(stage, bool(stage._match_ended), "Match must end immediately when all players are eliminated"):
		return

	var ranks: Array = stage._compute_rankings()
	if not _assert_true(stage, ranks.size() == 2, "Rankings must include both players"):
		return
	if not _assert_true(stage, int(ranks[0]["id"]) == 1 and int(ranks[0]["bonus"]) == 2, "First of two earns 2 raw points"):
		return
	if not _assert_true(stage, int(ranks[1]["id"]) == 0 and int(ranks[1]["bonus"]) == 1, "Second of two earns 1 raw point"):
		return
	stage._players[0].dodges = stage._players[1].dodges
	var tied: Array = stage._compute_rankings()
	if not _assert_true(stage, tied[0].bonus == 2 and tied[1].bonus == 2, "Tied players share raw points"):
		return

	if not _test_wave_pacing(stage):
		return

	stage._hosted_in_official_game = true
	var intro_camera := Camera3D.new()
	stage.add_child(intro_camera)
	intro_camera.make_current()
	stage.start_round([{"id": 0, "network_id": 1, "nickname": "Host"}, {"id": 1, "network_id": 42, "nickname": "Guest"}])
	if not _assert_true(stage, stage.get_viewport().get_camera_3d() == stage.get_node("StageCamera"), "Countdown must take the camera back from the intro"):
		return
	intro_camera.queue_free()
	if not _assert_true(stage, not stage._team.is_active(), "FFA roster must keep native team support inactive"):
		return
	for player in stage._players:
		if not _assert_true(stage, player.visual.position.y > 0 and player.node.position.y == 0, "Entrance raises each visual above its seat"):
			return
	stage._countdown = float(stage._countdown) - float(stage.ENTRANCE_SECONDS)
	stage._update_entrance()
	for player in stage._players:
		if not _assert_true(stage, is_zero_approx(player.visual.position.y), "All players land before GO"):
			return
	var tap := InputEventKey.new()
	tap.keycode = KEY_S
	tap.pressed = true
	stage._input(tap)
	stage._countdown = 0.0
	stage._input(tap)
	if not _assert_true(stage, not stage._players[0].crouching, "Holding through countdown must not trigger"):
		return
	tap.pressed = false
	stage._input(tap)
	tap.pressed = true
	stage._input(tap)
	if not _assert_true(stage, stage._players[0].crouching, "Press starts crouching immediately"):
		return
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	stage._input(down)
	tap.pressed = false
	stage._input(tap)
	if not _assert_true(stage, stage._players[0].crouching, "Second held crouch key keeps player crouched"):
		return
	down.pressed = false
	stage._input(down)
	if not _assert_true(stage, not stage._players[0].crouching, "Final key release ends crouch immediately"):
		return
	stage._tick_crouch(stage._players[0], cfg.crouch_recovery)
	tap.pressed = true
	stage._input(tap)
	if not _assert_true(stage, stage._players[0].crouching, "New press works after short recovery"):
		return
	stage._tick_crouch(stage._players[0], cfg.crouch_duration + cfg.crouch_recovery)
	tap.pressed = true
	tap.echo = true
	stage._input(tap)
	if not _assert_true(stage, not stage._players[0].crouching, "Keyboard repeat must not retrigger"):
		return
	stage._apply_input(42, 1)
	if not _assert_true(stage, stage._players[1].crouching and not stage._players[0].crouching, "Only sender crouches"):
		return
	stage._tick_crouch(stage._players[1], cfg.crouch_duration - 0.01)
	if not _assert_true(stage, stage._players[1].crouching, "Crouch lasts configured duration"):
		return
	stage._tick_crouch(stage._players[1], 0.02)
	if not _assert_true(stage, not stage._players[1].crouching, "Held crouch expires"):
		return
	var captured := {}
	stage.round_finished.connect(func(scores: Dictionary): captured.merge(scores))
	stage._players[0].dodges = 7
	stage._players[1].dodges = 3
	stage._finish_round("test")
	if not _assert_true(stage, captured == {1: 2, 42: 1}, "Scores keyed by real peers"):
		return

	# --- Native Team Mode verification ---
	var team_roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "RedLead", "team_id": 1},
		{"id": 1, "network_id": 2, "nickname": "BlueOne", "team_id": 2},
		{"id": 2, "network_id": 3, "nickname": "RedWing", "team_id": 1},
		{"id": 3, "network_id": 4, "nickname": "BlueTwo", "team_id": 2},
	]
	stage.start_round(team_roster)
	if not _assert_true(stage, stage._team.is_active() and bool(stage.get_meta(&"mpm_native_team_stage", false)), "Native team mode must activate on 2-team roster"):
		return
	var tps: Array = stage._players
	if not _assert_true(stage, int(tps[0]["team_id"]) == 1 and int(tps[1]["team_id"]) == 1 and int(tps[2]["team_id"]) == 2, "Players must be sorted into adjacent team Z lanes"):
		return
	if not _assert_true(stage, (tps[0]["node"] as Node3D).get_node_or_null("MpmTeamRing") != null, "Players must receive MpmTeamRing in team mode"):
		return
	tps[1]["dodges"] = 6
	stage._eliminate_player(tps[0])
	stage._check_round_end()
	if not _assert_true(stage, not bool(stage._match_ended), "Round must continue while teammate survives"):
		return
	stage._eliminate_player(tps[2])
	stage._eliminate_player(tps[3])
	stage._check_round_end()
	if not _assert_true(stage, bool(stage._match_ended), "Round must end early when only 1 team remains alive"):
		return
	var t_scores: Dictionary = stage._mpm_last_scores
	if not _assert_true(stage, int(t_scores.get(1, -1)) == int(t_scores.get(3, -2)) and int(t_scores.get(1, 0)) > 0, "Eliminated teammate must synchronize with winning carry"):
		return

	if not _tests_failed:
		print("NATIVE_TEAM_MODE_OK")
		print("SELF_TEST_PASSED")
		stage.get_tree().quit(0)
