extends RefCounted

## Headless self-tests and screenshot staging for Bubble Blitz (FFA + native Team Mode).


func stage_screenshot_action(stage: Node3D) -> void:
	var cfg = stage.C
	var meshes = stage.M
	var map_w: int = int(stage._map_width)
	var map_h: int = int(stage._map_height)
	var players: Dictionary = stage._players
	var tiles: Array = stage._tiles
	var tile_nodes: Dictionary = stage._tile_nodes

	stage._banner_label.text = ""
	stage._time_remaining = 42.0
	stage._update_crt_monitor()
	stage._kill_feed_label.text = ""

	var cx: int = map_w / 2
	var cy: int = map_h / 2
	if players.has(1):
		players[1]["pos"] = cfg.grid_to_world(Vector2i(cx - 2, cy), map_w, map_h)
		players[1]["facing"] = Vector2(1.0, 0.25)
		players[1]["has_needle"] = true
		players[1]["node"].position = players[1]["pos"]
		stage._update_player_hud_3d(players[1])
	if players.has(2):
		players[2]["pos"] = cfg.grid_to_world(Vector2i(cx + 2, cy), map_w, map_h)
		players[2]["hp"] = 0
		players[2]["trapped"] = true
		players[2]["node"].position = players[2]["pos"]
		stage._update_player_hud_3d(players[2])
	if players.has(3):
		players[3]["pos"] = cfg.grid_to_world(Vector2i(cx, cy - 2), map_w, map_h)
		players[3]["hp"] = 2
		players[3]["node"].position = players[3]["pos"]
		stage._update_player_hud_3d(players[3])
	if players.has(4):
		players[4]["pos"] = cfg.grid_to_world(Vector2i(cx, cy + 2), map_w, map_h)
		players[4]["hp"] = 1
		players[4]["node"].position = players[4]["pos"]
		stage._update_player_hud_3d(players[4])

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := Vector2i(cx + dx, cy + dy)
			tiles[c.y][c.x] = cfg.TILE_EMPTY
			if tile_nodes.has(c):
				tile_nodes[c].queue_free()
				tile_nodes.erase(c)

	var b1: Node3D = meshes.build_water_bubble(cfg.TILE_SIZE, players[1]["color"])
	b1.position = cfg.grid_to_world(Vector2i(cx - 1, cy), map_w, map_h)
	stage._arena_root.add_child(b1)

	var b2: Node3D = meshes.build_water_bubble(cfg.TILE_SIZE, players[3]["color"])
	b2.position = cfg.grid_to_world(Vector2i(cx + 1, cy - 2), map_w, map_h)
	stage._arena_root.add_child(b2)

	stage._spawn_blast_visual([
		Vector2i(cx, cy), Vector2i(cx, cy - 1), Vector2i(cx, cy + 1), Vector2i(cx + 1, cy),
	], 1)

	stage._spawn_item(Vector2i(cx - 1, cy - 1), cfg.ITEM_POWER)
	stage._spawn_item(Vector2i(cx + 1, cy + 1), cfg.ITEM_NEEDLE)
	stage._spawn_item(Vector2i(cx - 1, cy + 1), cfg.ITEM_SPEED)
	stage._spawn_item(Vector2i(cx + 1, cy - 1), cfg.ITEM_KICK)
	stage._spawn_item(Vector2i(cx - 2, cy + 1), cfg.ITEM_BUBBLE)


func _fail(stage: Node3D, msg: String) -> void:
	push_error("SELF_TEST_FAIL: " + msg)
	stage.get_tree().quit(1)


func run_self_test(stage: Node3D) -> void:
	stage._load_helpers()
	stage._is_server_sim = true
	stage._standalone_mode = true
	var cfg = stage.C
	var chain_delay: float = float(stage.CHAIN_DETONATE_DELAY_SEC)

	for count in [2, 4, 8, 16]:
		for theme in range(cfg.THEME_COUNT):
			var md: Dictionary = cfg.generate_map(count, theme, 1000 + count * 17 + theme)
			var tiles: Array = md["tiles"]
			var safe: Dictionary = md["safe"]
			for sc in safe.keys():
				var cell: Vector2i = sc
				if int(tiles[cell.y][cell.x]) != cfg.TILE_EMPTY:
					_fail(stage, "spawn safe cell blocked for count=%d theme=%d" % [count, theme])
					return
			if theme == cfg.THEME_CONVEYOR and (md["conveyors"] as Dictionary).is_empty():
				_fail(stage, "conveyor theme has no conveyor tiles")
				return

	# 1. FFA combat, needle rescue, bump pop, chain detonation & FX pooling
	var roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "P1", "is_ai": false},
		{"id": 1, "network_id": 2, "nickname": "P2", "is_ai": false},
		{"id": 2, "network_id": 3, "nickname": "P3", "is_ai": false},
	]
	stage._setup_match_local(cfg.THEME_CLASSIC, 4242, roster, true)
	stage._intro_timer = 0.0
	stage._round_active = true
	if stage._team.is_active():
		_fail(stage, "FFA roster must keep native team support inactive")
		return

	var p1: Dictionary = stage._players[1]
	var p2: Dictionary = stage._players[2]

	stage._hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 2 or bool(p2["trapped"]):
		_fail(stage, "expected 2 HP after first hit")
		return
	stage._hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 2:
		_fail(stage, "invulnerability failed to block repeat hit")
		return
	p2["invuln_timer"] = 0.0
	stage._hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 1 or bool(p2["trapped"]):
		_fail(stage, "expected 1 HP after second hit")
		return
	p2["has_needle"] = true
	p2["invuln_timer"] = 0.0
	stage._hit_player_by_blast(p2, 1)
	if not bool(p2["trapped"]) or not bool(p2["alive"]):
		_fail(stage, "expected trapped state on 3rd hit")
		return
	stage._step_players(cfg.NEEDLE_AUTO_SAVE_DELAY_SEC + 0.1)
	if bool(p2["trapped"]) or int(p2["hp"]) != 1 or bool(p2["has_needle"]):
		_fail(stage, "needle auto-rescue failed")
		return
	p2["invuln_timer"] = 0.0
	stage._hit_player_by_blast(p2, 1)
	p1["pos"] = p2["pos"] + Vector3(0.2, 0.0, 0.0)
	stage._step_players(0.05)
	if bool(p2["alive"]) or int(p1["pops"]) != 1:
		_fail(stage, "bump-pop elimination failed")
		return

	p1["max_bubbles"] = 3
	p1["power"] = 3
	p1["pos"] = cfg.grid_to_world(Vector2i(1, 1), stage._map_width, stage._map_height)
	var ok1: bool = stage._try_place_bubble(p1)
	p1["pos"] = cfg.grid_to_world(Vector2i(2, 1), stage._map_width, stage._map_height)
	var ok2: bool = stage._try_place_bubble(p1)
	if not ok1 or not ok2 or stage._bubbles.size() != 2:
		_fail(stage, "bubble placement failed")
		return
	var first_id: int = int(stage._bubbles.keys()[0])
	stage._detonate_bubble(first_id)
	if stage._bubbles.size() != 1:
		_fail(stage, "staggered chain detonation should queue second bubble instead of same-frame recursion")
		return
	var second_id: int = int(stage._bubbles.keys()[0])
	if float(stage._bubbles[second_id]["fuse"]) > chain_delay + 0.001:
		_fail(stage, "chained bubble fuse not shortened")
		return
	stage._step_bubbles(chain_delay + 0.02)
	if not stage._bubbles.is_empty():
		_fail(stage, "chain detonation left residual bubbles")
		return

	var fx = stage._fx_pool
	var pooled_total_before: int = fx.blast_center_pool.size() + fx.blast_arm_pool.size() + fx.active_blast_visuals.size()
	stage._step_blasts(cfg.BLAST_DURATION_SEC + 0.05)
	if not fx.active_blast_visuals.is_empty() or (fx.blast_center_pool.size() + fx.blast_arm_pool.size()) != pooled_total_before:
		_fail(stage, "blast cell pool leak detected")
		return

	var scores: Dictionary = cfg.compute_rank_scores([
		{"network_id": 1, "alive": true, "elim_time": 75.0, "pops": 2, "traps": 2},
		{"network_id": 2, "alive": false, "elim_time": 40.0, "pops": 1, "traps": 1},
		{"network_id": 3, "alive": false, "elim_time": 25.0, "pops": 0, "traps": 0},
	])
	if int(scores[1]) != 3 or int(scores[2]) != 2 or int(scores[3]) != 1:
		_fail(stage, "unexpected rank scores " + str(scores))
		return

	var wall_start: Vector3 = cfg.grid_to_world(Vector2i(1, 1), stage._map_width, stage._map_height)
	wall_start.x -= cfg.TILE_SIZE * 0.19
	p1["pos"] = wall_start
	var diag_dir := Vector2(-1.0, 1.0).normalized()
	var after_slide: Vector3 = stage._move_player_with_collision(p1, wall_start, Vector3(diag_dir.x, 0.0, diag_dir.y) * cfg.BASE_MOVE_SPEED, cfg.BASE_MOVE_SPEED, 0.1)
	if (after_slide.z - wall_start.z) < cfg.BASE_MOVE_SPEED * 0.1 * 0.95:
		_fail(stage, "wall-slide speed drop detected: dz=" + str(after_slide.z - wall_start.z))
		return

	p1["active_bubbles"] = 0
	p1["max_bubbles"] = 2
	p2["alive"] = true
	p2["trapped"] = false
	p2["pass_bubble_ids"] = {}
	var open_pos: Vector3 = cfg.grid_to_world(Vector2i(1, 1), stage._map_width, stage._map_height)
	p1["pos"] = open_pos
	p2["pos"] = open_pos + Vector3(cfg.TILE_SIZE * 0.45, 0.0, 0.0)
	if not stage._try_place_bubble(p1):
		_fail(stage, "face-drop test failed to place bubble")
		return
	var p2_before: Vector3 = p2["pos"]
	var p2_after: Vector3 = stage._move_player_with_collision(p2, p2_before, Vector3(cfg.BASE_MOVE_SPEED, 0.0, 0.0), cfg.BASE_MOVE_SPEED, 0.1)
	if (p2_after.x - p2_before.x) < cfg.BASE_MOVE_SPEED * 0.1 * 0.9:
		_fail(stage, "player trapped by face-dropped bubble: dx=" + str(p2_after.x - p2_before.x))
		return
	p2["pass_bubble_ids"] = {}
	p2["pos"] = p2_before
	var p2_escape: Vector3 = stage._move_player_with_collision(p2, p2_before, Vector3(cfg.BASE_MOVE_SPEED, 0.0, 0.0), cfg.BASE_MOVE_SPEED, 0.1)
	if (p2_escape.x - p2_before.x) < cfg.BASE_MOVE_SPEED * 0.1 * 0.9:
		_fail(stage, "player could not escape bubble overlap: dx=" + str(p2_escape.x - p2_before.x))
		return

	for b_id in stage._bubbles.keys():
		if stage._bubble_nodes.has(b_id) and is_instance_valid(stage._bubble_nodes[b_id]):
			stage._bubble_nodes[b_id].queue_free()
	stage._bubbles.clear()
	stage._bubble_nodes.clear()
	p1["active_bubbles"] = 0
	p1["max_bubbles"] = 3
	p1["pos"] = cfg.grid_to_world(Vector2i(1, 1), stage._map_width, stage._map_height) + Vector3(cfg.TILE_SIZE * 0.45, 0.0, 0.0)
	stage._client_inputs[1] = {"dir": Vector2(1.0, 0.0), "drop": true}
	for _f in range(6):
		stage._step_players(1.0 / 60.0)
	if stage._bubbles.size() != 1:
		_fail(stage, "single drop press spawned %d bubbles instead of 1" % stage._bubbles.size())
		return
	stage._client_inputs.clear()

	# 2. Native Team Mode (without requiring team-party mod loaded)
	var team_roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "Host", "team_id": 1, "is_ai": false},
		{"id": 1, "network_id": 2, "nickname": "Ally", "team_id": 1, "is_ai": false},
		{"id": 2, "network_id": 3, "nickname": "Rival", "team_id": 2, "is_ai": false},
	]
	stage._setup_match_local(cfg.THEME_CLASSIC, 5252, team_roster, true)
	stage._intro_timer = 0.0
	stage._round_active = true
	if not stage._team.is_active() or not bool(stage.get_meta(&"mpm_native_team_stage", false)):
		_fail(stage, "native team support did not activate for 2-team roster")
		return
	var tp1: Dictionary = stage._players[1]
	var tp2: Dictionary = stage._players[2]
	var tp3: Dictionary = stage._players[3]
	if (tp2["node"] as Node3D).get_node_or_null("MpmTeamRing") == null:
		_fail(stage, "native team setup missing MpmTeamRing on teammate")
		return
	stage._hit_player_by_blast(tp2, 1)
	if int(tp2["hp"]) != int(cfg.MAX_HP):
		_fail(stage, "friendly blast must deal 0 damage to teammate")
		return
	stage._hit_player_by_blast(tp3, 1)
	if int(tp3["hp"]) != int(cfg.MAX_HP) - 1:
		_fail(stage, "blast must still damage enemy in team mode")
		return
	tp2["hp"] = 0
	tp2["trapped"] = true
	tp2["trapped_timer"] = 0.0
	tp2["invuln_timer"] = 0.0
	stage._update_player_hud_3d(tp2)
	var hp_lbl := (tp2["node"] as Node3D).get_node_or_null("HpBar") as Label3D
	if hp_lbl == null or not (hp_lbl.text.contains("HELP!") or hp_lbl.text.contains("救命!")):
		_fail(stage, "downed teammate should show SOS prompt on HpBar")
		return
	stage._eliminate_player(tp2, 1, "BUMP POP")
	if not bool(tp2["alive"]) or bool(tp2["trapped"]) or int(tp2["hp"]) != 1 or int(tp1.get("mpm_rescues", 0)) != 1:
		_fail(stage, "teammate BUMP POP should revive ally to 1 HP")
		return
	stage._eliminate_player(tp3, 1, "BLAST POP")
	stage._check_round_end()
	if not bool(stage._round_ended):
		_fail(stage, "team match should end early when only 1 team remains alive")
		return
	var last_scores: Dictionary = stage._mpm_last_scores
	if int(last_scores.get(1, -1)) != int(last_scores.get(2, -2)):
		_fail(stage, "team members must receive synchronized scores")
		return

	print("BUBBLE_BLITZ_THEMES_VERIFIED=4, HYBRID_3HP_NEEDLE_POP_OK, CHAIN_DETONATION_OK, WALL_SLIDE_FULL_SPEED_OK, FACE_BOMB_NO_TRAP_OK, SINGLE_DROP_OK, NATIVE_TEAM_MODE_OK")
	print("SELF_TEST_PASSED")
	stage.get_tree().quit(0)
