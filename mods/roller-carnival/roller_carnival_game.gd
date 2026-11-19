extends Node3D

## Roller Carnival (滾筒嘉年華) — 3D Oblique Top-Down Dodge Party Minigame.
##
## Rules:
## - 1-8 players spawn dispersed in the central stage area.
## - Gold High Rollers appear at mid-height on the far right -> hold S (or Down) to crouch under.
## - Silver Low Rollers appear at ground-level on the far right -> press Space to jump over.
## - Rollers keep fixed height and roll left; touching a player applies pure knockback (~1 body width),
##   zero HP loss, cumulative across hits. Being pushed into the left lava pit eliminates immediately.
## - Dodge count increments (+1) per roller safely passed without collision; eliminated players keep
##   their dodge counts for end-of-round ranking & configurable bonus points.
## - Round lasts default 50s; surviving to 0s wins, or ends early if all players are eliminated.

var config = null
var _meshes = null

# Official Machine Party Minigame interface signals (used by res://scripts/scenes/game/game.gd)
@warning_ignore("unused_signal")
signal host_loaded(skip_intro)
@warning_ignore("unused_signal")
signal minigame_loaded(network_id)
@warning_ignore("unused_signal")
signal minigame_ready(network_id)
@warning_ignore("unused_signal")
signal minigame_finished(network_id)
@warning_ignore("unused_signal")
signal player_scored(network_id, score)
@warning_ignore("unused_signal")
signal player_scores_finalized(player_scores)
@warning_ignore("unused_signal")
signal debug_player_specifics_initialized(transform)
@warning_ignore("unused_signal")
signal before_player_marker_show()

var players_loaded: Array[int] = []
var round_number: int = 1
var total_rounds: int = 1
var _hosted_in_official_game: bool = false
var _awaiting_room_setup: bool = false
var _round_roster_network_ids: Array[int] = []

var _rng := RandomNumberGenerator.new()
var _scene_props: Dictionary = {}
var _players: Array[Dictionary] = []
var _rollers: Array[Dictionary] = []
var _decals: Array[Node3D] = []
var _popups: Array[Dictionary] = []
var _particles: Array[Dictionary] = []

var _players_layer: Node3D
var _rollers_layer: Node3D
var _fx_layer: Node3D

var _elapsed: float = 0.0
var _time_left: float = 50.0
var _spawn_timer: float = 1.0
var _last_roller_type: String = ""
var _same_type_streak: int = 0
var _next_roller_id: int = 1
var _match_ended: bool = false
var _end_reason: String = ""
var _beacon_gold_flash: float = 0.0
var _beacon_silver_flash: float = 0.0

# Session cumulative scores per player index (persists across Play Again rounds)
var _session_scores: Dictionary = {}

# UI References
var _ui_layer: CanvasLayer
var _timer_label: Label
var _speed_label: Label
var _hint_panel: PanelContainer
var _results_panel: PanelContainer
var _results_title: Label
var _results_subtitle: Label
var _results_rows: VBoxContainer
var _room_setup_panel: PanelContainer
var _room_setup_inputs: Dictionary = {}
var _curve_option: OptionButton = null
var _tie_option: OptionButton = null
var _preset_players_opt: OptionButton = null
var _preset_pace_opt: OptionButton = null
var _preset_duration_opt: OptionButton = null
var _preset_spawn_opt: OptionButton = null
var _preset_knockback_opt: OptionButton = null
var _adv_toggle_btn: Button = null
var _adv_container: Control = null

var _is_self_test: bool = false
var _screenshot_path: String = ""
var _screenshot_ticks: int = 0
var _sfx_shove: AudioStreamPlayer = null
var _sfx_fall: AudioStreamPlayer = null
var _ambience_player: AudioStreamPlayer = null
var _shader_layer: CanvasLayer = null


func _ready() -> void:
	_load_dependencies()
	_rng.randomize()

	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg == "--self-test":
			_is_self_test = true
		elif arg.begins_with("--capture-screenshot="):
			_screenshot_path = arg.trim_prefix("--capture-screenshot=")

	_players_layer = Node3D.new()
	_players_layer.name = "PlayersLayer"
	add_child(_players_layer)

	_rollers_layer = Node3D.new()
	_rollers_layer.name = "RollersLayer"
	add_child(_rollers_layer)

	_fx_layer = Node3D.new()
	_fx_layer.name = "EffectsLayer"
	add_child(_fx_layer)

	_scene_props = _meshes.build_stage_and_environment(self, config)
	_build_post_fx_and_audio()
	_build_ui()

	_hosted_in_official_game = _detect_official_game_host()

	if _is_self_test:
		_run_self_tests()
		return

	if not _screenshot_path.is_empty():
		config.max_players = 8
		_start_new_round()
		_setup_screenshot_showcase()
		return

	if _hosted_in_official_game:
		_complete_official_handshake()
	else:
		_open_room_creation_setup()


func _detect_official_game_host() -> bool:
	var root := get_tree().root
	if root == null:
		return false
	return root.has_node("GameManager") and root.has_node("PlayerManager") and get_parent() != root


func _complete_official_handshake() -> void:
	var gm := get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.set("can_set_cursor", false)
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			host_loaded.emit(true)
			player_loaded(1)
		else:
			player_loaded.rpc_id(1, multiplayer.get_unique_id())
	else:
		initialize(1, 1, {})


@rpc("any_peer", "call_remote", "reliable")
func player_loaded(network_id: int) -> void:
	if not players_loaded.has(network_id):
		players_loaded.append(network_id)
	if multiplayer != null and multiplayer.is_server():
		var pm := get_tree().root.get_node_or_null("PlayerManager")
		var expected: int = 1
		if pm != null and pm.get("player_presences") is Dictionary:
			expected = maxi(1, (pm.get("player_presences") as Dictionary).size())
		if players_loaded.size() >= expected:
			all_players_loaded()


func all_players_loaded() -> void:
	minigame_ready.emit(1)


func initialize(_round_number: int, _total_rounds: int, _scores: Dictionary = {}) -> void:
	round_number = _round_number
	total_rounds = _total_rounds

	for nid in _scores.keys():
		_session_scores[int(nid)] = int(_scores[nid])

	_load_room_config_from_globals()
	if _hosted_in_official_game and multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var seed_val := int(Time.get_ticks_usec() & 0x7fffffff)
		sync_room_config_rpc.rpc(config.to_dict(), seed_val)
	else:
		_start_new_round()


@rpc("authority", "call_local", "reliable")
func sync_room_config_rpc(cfg_dict: Dictionary, seed_val: int) -> void:
	config.apply_dict(cfg_dict)
	_rng.seed = seed_val
	_start_new_round()


func player_disconnected(_network_id: int) -> void:
	for p in _players:
		if int(p.get("network_id", -1)) == _network_id and bool(p["alive"]):
			_eliminate_player(p)


func cleanup() -> void:
	pass


@rpc("any_peer", "call_local", "reliable")
func cleanup_rpc() -> void:
	cleanup()
	queue_free()


func _load_room_config_from_globals() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return
	var glb := root.get_node_or_null("Globals")
	if glb == null:
		return
	var gs = glb.get("game_settings")
	if gs is Dictionary and gs.has("roller_carnival") and gs["roller_carnival"] is Dictionary:
		config.apply_dict(gs["roller_carnival"])


func _save_room_config_to_globals() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return
	var glb := root.get_node_or_null("Globals")
	if glb == null:
		return
	var gs = glb.get("game_settings")
	if gs is Dictionary:
		gs["roller_carnival"] = config.to_dict()
		if glb.has_method("save_game_settings"):
			glb.call("save_game_settings")


func _load_dependencies() -> void:
	var base_dir: String = (get_script() as Script).resource_path.get_base_dir()
	var cfg_script = load(base_dir.path_join("config.gd"))
	config = cfg_script.new()
	_meshes = load(base_dir.path_join("carnival_meshes.gd"))
	_meshes.ensure_game_pck_mounted()


func _build_post_fx_and_audio() -> void:
	# Audio cues from Machine Party (skipped during headless self-test)
	if not _is_self_test:
		var shove_stream = _meshes.load_optional("res://audio/unique/disco dodge/dd shove.ogg")
		if shove_stream is AudioStream:
			_sfx_shove = AudioStreamPlayer.new()
			_sfx_shove.stream = shove_stream
			_sfx_shove.volume_db = -3.0
			add_child(_sfx_shove)

		var fall_stream = _meshes.load_optional("res://audio/unique/disco dodge/dd fall scream impact.ogg")
		if fall_stream is AudioStream:
			_sfx_fall = AudioStreamPlayer.new()
			_sfx_fall.stream = fall_stream
			_sfx_fall.volume_db = -2.0
			add_child(_sfx_fall)

		var amb_stream = _meshes.load_optional("res://audio/unique/dvd roomba/dvd roomba ambience.ogg")
		if amb_stream is AudioStream and _screenshot_path.is_empty():
			_ambience_player = AudioStreamPlayer.new()
			_ambience_player.stream = amb_stream
			_ambience_player.volume_db = -10.0
			add_child(_ambience_player)
			_ambience_player.play()

	# Machine Party signature posterization + vignette post-processing on layer 1 (below HUD layer 2)
	var post_shader = _meshes.load_optional("res://shaders/posterization.gdshader")
	var vig_shader = _meshes.load_optional("res://shaders/vignette.gdshader")
	if post_shader is Shader or vig_shader is Shader:
		_shader_layer = CanvasLayer.new()
		_shader_layer.name = "PostFXLayer"
		_shader_layer.layer = 1
		add_child(_shader_layer)

		if post_shader is Shader:
			var post_rect := ColorRect.new()
			post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pm := ShaderMaterial.new()
			pm.shader = post_shader
			pm.set_shader_parameter("SCREEN_WIDTH", 960.0)
			pm.set_shader_parameter("RED_COMPONENT", 18.0)
			pm.set_shader_parameter("GREEN_COMPONENT", 18.0)
			pm.set_shader_parameter("BLUE_COMPONENT", 18.0)
			post_rect.material = pm
			_shader_layer.add_child(post_rect)

		if vig_shader is Shader:
			var vig_rect := ColorRect.new()
			vig_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var vm := ShaderMaterial.new()
			vm.shader = vig_shader
			vm.set_shader_parameter("radius", 0.44)
			vm.set_shader_parameter("softness", 0.44)
			vm.set_shader_parameter("intensity", 0.65)
			vm.set_shader_parameter("contrast", 1.8)
			vig_rect.material = vm
			_shader_layer.add_child(vig_rect)


func _start_new_round() -> void:
	for child in _players_layer.get_children():
		child.queue_free()
	for child in _rollers_layer.get_children():
		child.queue_free()
	for child in _fx_layer.get_children():
		child.queue_free()

	_players.clear()
	_rollers.clear()
	_decals.clear()
	_popups.clear()
	_particles.clear()

	_elapsed = 0.0
	_time_left = config.round_duration
	_spawn_timer = 0.75
	_last_roller_type = ""
	_same_type_streak = 0
	_next_roller_id = 1
	_match_ended = false
	_awaiting_room_setup = false
	_end_reason = ""

	if _results_panel != null:
		_results_panel.visible = false
	if _room_setup_panel != null:
		_room_setup_panel.visible = false
	if _hint_panel != null:
		_hint_panel.visible = true
		_hint_panel.modulate.a = 1.0

	if _meshes != null:
		_meshes.update_starting_line(_scene_props, config)
	_spawn_players()
	_update_hud_labels()


func _resolve_roster_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pm := get_tree().root.get_node_or_null("PlayerManager") if get_tree() != null else null
	if _hosted_in_official_game and pm != null and pm.get("player_presences") is Dictionary:
		var presences: Dictionary = pm.get("player_presences")
		var keys: Array = presences.keys()
		keys.sort()
		for idx in range(mini(keys.size(), 16)):
			var nid: int = int(keys[idx])
			var pres = presences[keys[idx]]
			var nname: String = str(pres.get("network_name")) if pres != null else _meshes.PLAYER_NAMES[idx % _meshes.PLAYER_NAMES.size()]
			if nname.is_empty():
				nname = _meshes.PLAYER_NAMES[idx % _meshes.PLAYER_NAMES.size()]
			entries.append({"id": idx, "network_id": nid, "nickname": nname})
	if entries.is_empty():
		var count: int = clampi(config.max_players, 1, 16)
		for i in range(count):
			entries.append({
				"id": i,
				"network_id": i + 1,
				"nickname": _meshes.PLAYER_NAMES[i % _meshes.PLAYER_NAMES.size()],
			})
	return entries


func _spawn_players() -> void:
	var roster: Array[Dictionary] = _resolve_roster_entries()
	var count: int = roster.size()
	# Option A: All 1-16 players stand shoulder-to-shoulder on the exact same starting line (player_spawn_x)
	var z_span: float = 7.5 if count > 8 else 6.3
	var char_scale: float = 0.76 if count > 12 else (0.86 if count > 8 else 1.0)
	var spawn_x: float = config.player_spawn_x
	for i in range(count):
		var entry: Dictionary = roster[i]
		var frac: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var spawn_z: float = lerpf(-z_span * 0.5, z_span * 0.5, frac)
		var nickname: String = str(entry["nickname"])
		var nid: int = int(entry["network_id"])
		var visual_dict: Dictionary = _meshes.build_cartoon_character(i, nickname)
		var pnode: Node3D = visual_dict["root"]
		pnode.position = Vector3(spawn_x, 0.0, spawn_z)
		pnode.scale = Vector3.ONE * char_scale
		_players_layer.add_child(pnode)

		if not _session_scores.has(nid):
			_session_scores[nid] = 0

		_players.append({
			"id": i,
			"network_id": nid,
			"nickname": nickname,
			"color": _meshes.PLAYER_COLORS[i % _meshes.PLAYER_COLORS.size()],
			"node": pnode,
			"visual": visual_dict["visual"],
			"shadow": visual_dict["shadow"],
			"label": visual_dict["label"],
			"anim_player": visual_dict.get("anim_player", null),
			"x": spawn_x,
			"y": 0.0,
			"z": spawn_z,
			"alive": true,
			"dodges": 0,
			"survival_time": 0.0,
			"crouching": false,
			"jumping": false,
			"jump_timer": 0.0,
			"recovery_timer": 0.0,
			"knockback_remaining": 0.0,
			"knockback_timer": 0.0,
			"knockback_cooldown": 0.0,
			"hit_flash": 0.0,
			"sink_progress": 0.0,
			"ai_target_action": "",
			"ai_reaction_delay": _rng.randf_range(0.03, 0.16),
			"ai_mistake_rate": 0.14 + float(i % 4) * 0.05,
			"ai_decided_roller_id": -1,
		})


func _process(delta: float) -> void:
	if _is_self_test:
		return

	if not _screenshot_path.is_empty():
		_animate_environment(delta)
		_screenshot_ticks += 1
		if _screenshot_ticks >= 4:
			var img: Image = get_viewport().get_texture().get_image()
			var dir_path := _screenshot_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(dir_path)
			img.save_png(_screenshot_path)
			print("SCREENSHOT_SAVED=" + _screenshot_path)
			get_tree().quit(0)
		return

	_animate_environment(delta)
	_update_particles(delta)
	_update_popups(delta)

	if _awaiting_room_setup or _match_ended or _players.is_empty():
		return

	_elapsed += delta
	_time_left = maxf(0.0, _time_left - delta)

	# Fade out opening control hint after 4.5s
	if _elapsed < 3.5:
		_hint_panel.modulate.a = 1.0
	elif _elapsed < 4.8:
		_hint_panel.modulate.a = clampf(1.0 - (_elapsed - 3.5) / 1.3, 0.0, 1.0)
	else:
		_hint_panel.visible = false

	_step_spawner(delta)
	_step_players(delta)
	_step_rollers(delta)
	_resolve_player_spacing(delta)
	_update_hud_labels()
	_check_round_end()


func _unhandled_input(event: InputEvent) -> void:
	if _hosted_in_official_game:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and not _awaiting_room_setup:
			_start_new_round()
		elif event.keycode == KEY_C and (_match_ended or _awaiting_room_setup):
			_open_room_creation_setup()


func _animate_environment(delta: float) -> void:
	var gears: Array = _scene_props.get("gears", [])
	for i in range(gears.size()):
		var g: Node3D = gears[i]
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		g.rotation.z += delta * (0.65 + float(i % 2) * 0.35) * dir

	var bubbles: Array = _scene_props.get("lava_bubbles", [])
	for b in bubbles:
		var node: MeshInstance3D = b["node"]
		var phase: float = b["phase"] + _elapsed * 2.6
		var lift: float = maxf(0.0, sin(phase))
		node.position.y = -0.50 + lift * 0.36
		var s: float = 0.65 + lift * 0.65
		node.scale = Vector3(s, s, s)

	var bulbs: Array = _scene_props.get("bulbs", [])
	for i in range(bulbs.size()):
		var bulb: MeshInstance3D = bulbs[i]
		var mat := bulb.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.4 + 0.9 * sin(_elapsed * 4.5 + float(i) * 1.1)

	_beacon_gold_flash = maxf(0.0, _beacon_gold_flash - delta * 2.8)
	_beacon_silver_flash = maxf(0.0, _beacon_silver_flash - delta * 2.8)
	var bg := _scene_props.get("beacon_gold") as MeshInstance3D
	if bg and bg.material_override:
		(bg.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5 + _beacon_gold_flash * 3.0
	var bs := _scene_props.get("beacon_silver") as MeshInstance3D
	if bs and bs.material_override:
		(bs.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5 + _beacon_silver_flash * 3.0


func _current_progress() -> float:
	if config.round_duration <= 0.001:
		return 1.0
	return clampf(_elapsed / config.round_duration, 0.0, 1.0)


func _current_roller_speed() -> float:
	return config.speed_at_progress(_current_progress())


func _step_spawner(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	var r_type: String = _pick_next_roller_type()
	_spawn_roller(r_type, config.roller_spawn_x)

	var rng_range: Vector2 = config.interval_range_at_progress(_current_progress())
	_spawn_timer = _rng.randf_range(rng_range.x, rng_range.y)


func _pick_next_roller_type() -> String:
	var chosen: String = "gold" if _rng.randf() < config.gold_roller_probability else "silver"
	if chosen == _last_roller_type and _same_type_streak >= config.max_same_type_streak:
		chosen = "silver" if chosen == "gold" else "gold"
	if chosen == _last_roller_type:
		_same_type_streak += 1
	else:
		_last_roller_type = chosen
		_same_type_streak = 1
	return chosen


func _spawn_roller(roller_type: String, spawn_x: float) -> Dictionary:
	var is_gold: bool = (roller_type == "gold")
	var center_y: float = config.gold_roller_center_y if is_gold else config.silver_roller_center_y
	var radius: float = config.gold_roller_radius if is_gold else config.silver_roller_radius

	var built: Dictionary = _meshes.build_roller_mesh(roller_type, radius, 8.4)
	var rnode: Node3D = built["root"]
	rnode.position = Vector3(spawn_x, center_y, 0.0)
	_rollers_layer.add_child(rnode)

	if is_gold:
		_beacon_gold_flash = 1.0
	else:
		_beacon_silver_flash = 1.0

	var roller := {
		"id": _next_roller_id,
		"type": roller_type,
		"node": rnode,
		"spin": built["spin"],
		"x": spawn_x,
		"y": center_y,
		"radius": radius,
		"hit_players": {} as Dictionary,
		"passed_players": {} as Dictionary,
	}
	_next_roller_id += 1
	_rollers.append(roller)
	return roller


func _is_key_group_pressed(key_codes: Array[int]) -> bool:
	for code in key_codes:
		if Input.is_key_pressed(code):
			return true
	return false


func _step_players(delta: float) -> void:
	for p in _players:
		if not p["alive"]:
			p["sink_progress"] = minf(1.0, float(p["sink_progress"]) + delta * 1.8)
			var pnode: Node3D = p["node"]
			pnode.position = Vector3(p["x"], -float(p["sink_progress"]) * 1.6, p["z"])
			pnode.rotation_degrees.z = float(p["sink_progress"]) * 48.0
			continue

		p["survival_time"] = float(p["survival_time"]) + delta
		p["knockback_cooldown"] = maxf(0.0, float(p["knockback_cooldown"]) - delta)
		p["recovery_timer"] = maxf(0.0, float(p["recovery_timer"]) - delta)
		p["hit_flash"] = maxf(0.0, float(p["hit_flash"]) - delta * 3.5)

		# Smooth knockback displacement
		if float(p["knockback_timer"]) > 0.0:
			var step_t: float = minf(delta, float(p["knockback_timer"]))
			var frac: float = step_t / maxf(0.01, float(p["knockback_timer"]))
			var dx: float = float(p["knockback_remaining"]) * frac
			p["x"] = float(p["x"]) - dx
			p["knockback_remaining"] = float(p["knockback_remaining"]) - dx
			p["knockback_timer"] = float(p["knockback_timer"]) - step_t

		# Determine player input (P1 = keyboard, P2..8 = autonomous party AI)
		var want_crouch: bool = false
		var want_jump: bool = false
		if int(p["id"]) == 0:
			want_crouch = _is_key_group_pressed(config.crouch_key_codes)
			want_jump = _is_key_group_pressed(config.jump_key_codes)
		else:
			var ai_act: Dictionary = _compute_ai_action(p)
			want_crouch = ai_act["crouch"]
			want_jump = ai_act["jump"]

		# Jump / crouch state machine
		if bool(p["jumping"]):
			p["jump_timer"] = float(p["jump_timer"]) + delta
			var t: float = float(p["jump_timer"]) / maxf(0.1, config.jump_air_time)
			if t >= 1.0:
				p["jumping"] = false
				p["jump_timer"] = 0.0
				p["y"] = 0.0
				p["recovery_timer"] = config.landing_recovery_time
			else:
				p["y"] = 4.0 * config.jump_height * t * (1.0 - t)
			p["crouching"] = false
		else:
			p["y"] = 0.0
			if want_jump and float(p["recovery_timer"]) <= 0.0:
				p["jumping"] = true
				p["jump_timer"] = 0.0
				p["crouching"] = false
			else:
				p["crouching"] = want_crouch

		# Check lava elimination boundary
		if float(p["x"]) <= config.stage_left_lava_x:
			_eliminate_player(p)
			continue

		_update_player_visuals(p)


func _compute_ai_action(p: Dictionary) -> Dictionary:
	var px: float = float(p["x"])
	var speed: float = maxf(1.0, _current_roller_speed())
	var nearest = null
	var best_dist: float = 999.0

	for r in _rollers:
		var rx: float = float(r["x"])
		var dist: float = rx - px
		if dist >= -0.25 and dist < best_dist:
			best_dist = dist
			nearest = r

	if nearest == null:
		return {"crouch": false, "jump": false}

	var rid: int = int(nearest["id"])
	if int(p["ai_decided_roller_id"]) != rid:
		p["ai_decided_roller_id"] = rid
		var rtype: String = str(nearest["type"])
		if _rng.randf() < float(p["ai_mistake_rate"]):
			p["ai_target_action"] = "none" if _rng.randf() < 0.6 else ("jump" if rtype == "gold" else "crouch")
		else:
			p["ai_target_action"] = "crouch" if rtype == "gold" else "jump"

	var time_to_hit: float = best_dist / speed
	var act: String = str(p["ai_target_action"])
	if act == "crouch" and time_to_hit <= 0.36 + float(p["ai_reaction_delay"]) and best_dist >= -0.35:
		return {"crouch": true, "jump": false}
	if act == "jump" and time_to_hit <= config.jump_air_time * 0.45 and time_to_hit >= 0.0:
		return {"crouch": false, "jump": true}
	return {"crouch": false, "jump": false}


func _update_player_visuals(p: Dictionary) -> void:
	var pnode: Node3D = p["node"]
	var visual: Node3D = p["visual"]
	var shadow: Node3D = p["shadow"]
	var lbl: Label3D = p["label"]

	pnode.position = Vector3(float(p["x"]), 0.0, float(p["z"]))
	visual.position.y = float(p["y"])

	var target_scale := Vector3.ONE
	if bool(p["crouching"]):
		var y_ratio: float = config.crouch_height / maxf(0.5, config.standing_height)
		target_scale = Vector3(1.22, y_ratio, 1.22)
	elif bool(p["jumping"]):
		target_scale = Vector3(0.90, 1.14, 0.90)
	else:
		var bob: float = 0.03 * sin(_elapsed * 7.5 + float(p["id"]))
		target_scale = Vector3(1.0 - bob * 0.4, 1.0 + bob, 1.0 - bob * 0.4)

	visual.scale = visual.scale.lerp(target_scale, 0.35)
	var ap: AnimationPlayer = p.get("anim_player", null)
	if float(p["hit_flash"]) > 0.0:
		visual.rotation_degrees.z = 18.0 * float(p["hit_flash"])
	else:
		visual.rotation_degrees.z = lerpf(visual.rotation_degrees.z, 0.0, 0.25)
		if ap != null and ap.has_animation(&"mp_mod/idle") and ap.current_animation == &"mp_mod/shoved":
			ap.play(&"mp_mod/idle")

	var shadow_scale: float = clampf(1.0 - float(p["y"]) * 0.25, 0.45, 1.0)
	shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale)

	lbl.position.y = (1.35 if bool(p["crouching"]) else 1.88) + float(p["y"])
	lbl.text = "%s (%d)" % [str(p["nickname"]), int(p["dodges"])]


func _resolve_player_spacing(_delta: float) -> void:
	# Option A: players stay aligned on their Z lanes; scale separation for up to 16 players
	var min_z_sep: float = minf(0.72, 7.2 / float(maxi(1, _players.size())))
	for i in range(_players.size()):
		if not _players[i]["alive"]:
			continue
		for j in range(i + 1, _players.size()):
			if not _players[j]["alive"]:
				continue
			var dz: float = float(_players[i]["z"]) - float(_players[j]["z"])
			if absf(dz) < min_z_sep:
				var sign_z: float = 1.0 if dz >= 0.0 else -1.0
				var push_z: float = (min_z_sep - absf(dz)) * 0.2
				_players[i]["z"] = clampf(float(_players[i]["z"]) + sign_z * push_z, -3.85, 3.85)
				_players[j]["z"] = clampf(float(_players[j]["z"]) - sign_z * push_z, -3.85, 3.85)


func _step_rollers(delta: float) -> void:
	var speed: float = _current_roller_speed()
	var to_remove: Array[int] = []

	for idx in range(_rollers.size()):
		var r: Dictionary = _rollers[idx]
		r["x"] = float(r["x"]) - speed * delta
		var rnode: Node3D = r["node"]
		rnode.position = Vector3(float(r["x"]), float(r["y"]), 0.0)
		var spin: Node3D = r["spin"]
		spin.rotation.z += (speed * delta) / maxf(0.1, float(r["radius"]))

		_evaluate_roller_interactions(r)

		if float(r["x"]) < config.roller_despawn_x:
			to_remove.append(idx)

	for i in range(to_remove.size() - 1, -1, -1):
		var rm_idx: int = to_remove[i]
		var dead_node: Node3D = _rollers[rm_idx]["node"]
		dead_node.queue_free()
		_rollers.remove_at(rm_idx)


func _evaluate_roller_interactions(r: Dictionary) -> void:
	var rx: float = float(r["x"])
	var ry: float = float(r["y"])
	var rad: float = float(r["radius"])
	var r_bottom: float = ry - rad
	var r_top: float = ry + rad
	var r_left: float = rx - rad
	var r_right: float = rx + rad

	var hit_map: Dictionary = r["hit_players"]
	var pass_map: Dictionary = r["passed_players"]

	for p in _players:
		if not p["alive"]:
			continue
		var pid: int = int(p["id"])
		var px: float = float(p["x"])
		var p_half_w: float = 0.28
		var p_bottom: float = float(p["y"])
		var p_height: float = config.crouch_height if bool(p["crouching"]) else config.standing_height
		var p_top: float = p_bottom + p_height

		var x_overlap: bool = (px + p_half_w >= r_left) and (px - p_half_w <= r_right)
		var y_overlap: bool = (p_top >= r_bottom) and (p_bottom <= r_top)

		if x_overlap and y_overlap:
			if not hit_map.has(pid) and float(p["knockback_cooldown"]) <= 0.0:
				hit_map[pid] = true
				_apply_knockback_to_player(p)
		elif r_right < px - p_half_w:
			if not hit_map.has(pid) and not pass_map.has(pid):
				pass_map[pid] = true
				p["dodges"] = int(p["dodges"]) + 1
				_spawn_popup(Vector3(px, p_top + 0.45, float(p["z"])), "+1", Color(0.35, 1.0, 0.55))


func _apply_knockback_to_player(p: Dictionary) -> void:
	p["knockback_remaining"] = float(p["knockback_remaining"]) + config.knockback_distance
	p["knockback_timer"] = config.knockback_duration
	p["knockback_cooldown"] = config.knockback_cooldown
	p["hit_flash"] = 1.0

	var pos := Vector3(float(p["x"]), 0.02, float(p["z"]))
	_spawn_impact_decal(pos)
	_spawn_burst(Vector3(pos.x, 0.75, pos.z), Color(1.0, 0.65, 0.2), 7)
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null and ap.has_animation(&"mp_mod/shoved"):
		ap.play(&"mp_mod/shoved")
	if _sfx_shove != null and not _is_self_test:
		_sfx_shove.play()

	# In instant/headless step verification or heavy hit, check boundary after knockback applies
	if _is_self_test:
		p["x"] = float(p["x"]) - config.knockback_distance
		p["knockback_remaining"] = 0.0
		p["knockback_timer"] = 0.0
		if float(p["x"]) <= config.stage_left_lava_x:
			_eliminate_player(p)


func _eliminate_player(p: Dictionary) -> void:
	if not p["alive"]:
		return
	p["alive"] = false
	p["sink_progress"] = 0.0
	var lbl: Label3D = p["label"]
	lbl.text = "%s 💀" % str(p["nickname"])
	lbl.modulate = Color(0.55, 0.55, 0.58)
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null and ap.has_animation(&"mp_mod/falling"):
		ap.play(&"mp_mod/falling")
	if _sfx_fall != null and not _is_self_test:
		_sfx_fall.play()
	_spawn_burst(Vector3(config.stage_left_lava_x - 0.3, 0.25, float(p["z"])), Color(1.0, 0.45, 0.08), 16)
	_spawn_popup(Vector3(config.stage_left_lava_x - 0.2, 1.5, float(p["z"])), "淘汰!", Color(1.0, 0.35, 0.25))


func _spawn_impact_decal(pos: Vector3) -> void:
	if _decals.size() >= 24:
		var old: Node3D = _decals.pop_front()
		old.queue_free()
	var mark := MeshInstance3D.new()
	var blood_tex = _meshes.load_optional("res://textures/decals/blood decals/blood_splat_01.png")
	if blood_tex is Texture2D:
		var qm := PlaneMesh.new()
		qm.size = Vector2(0.95, 0.95)
		mark.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = blood_tex
		mat.albedo_color = Color(0.92, 0.14, 0.10, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.6
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mark.material_override = mat
		mark.rotation.y = _rng.randf_range(0.0, TAU)
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34
		cm.bottom_radius = 0.36
		cm.height = 0.015
		mark.mesh = cm
		mark.material_override = _meshes.make_toon_mat(Color(0.55, 0.14, 0.08, 0.65), 0.9, 0.0)
		mark.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.position = pos
	_fx_layer.add_child(mark)
	_decals.append(mark)


func _spawn_burst(origin: Vector3, color: Color, count: int) -> void:
	var mat = _meshes.make_toon_mat(color, 0.3, 0.0, color, 1.8)
	for _i in range(count):
		var part := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.14, 0.14, 0.14)
		part.mesh = sm
		part.material_override = mat
		part.position = origin
		_fx_layer.add_child(part)
		var vel := Vector3(_rng.randf_range(-2.8, 1.8), _rng.randf_range(2.2, 5.2), _rng.randf_range(-2.2, 2.2))
		_particles.append({"node": part, "vel": vel, "life": 0.55})


func _spawn_popup(origin: Vector3, text: String, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 40
	lbl.pixel_size = 0.0085
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = color
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 8
	lbl.position = origin
	_fx_layer.add_child(lbl)
	_popups.append({"node": lbl, "life": 0.75})


func _update_particles(delta: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var pt: Dictionary = _particles[i]
		pt["life"] = float(pt["life"]) - delta
		if float(pt["life"]) <= 0.0:
			(pt["node"] as Node3D).queue_free()
			_particles.remove_at(i)
		else:
			var vel: Vector3 = pt["vel"]
			vel.y -= 11.5 * delta
			pt["vel"] = vel
			var node: Node3D = pt["node"]
			node.position += vel * delta
			node.scale = Vector3.ONE * clampf(float(pt["life"]) * 1.8, 0.1, 1.0)


func _update_popups(delta: float) -> void:
	for i in range(_popups.size() - 1, -1, -1):
		var pp: Dictionary = _popups[i]
		pp["life"] = float(pp["life"]) - delta
		if float(pp["life"]) <= 0.0:
			(pp["node"] as Node3D).queue_free()
			_popups.remove_at(i)
		else:
			var node: Label3D = pp["node"]
			node.position.y += delta * 1.2
			node.modulate.a = clampf(float(pp["life"]) / 0.75, 0.0, 1.0)


func _check_round_end() -> void:
	var alive_count: int = 0
	for p in _players:
		if p["alive"]:
			alive_count += 1

	if alive_count == 0:
		_finish_round("全員落入岩漿淘汰（提前結束）")
	elif _time_left <= 0.0:
		_finish_round("倒計時結束！%d 名存活玩家獲勝" % alive_count)


func _compute_rankings() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for p in _players:
		sorted.append(p)

	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: int = int(a["dodges"])
		var db: int = int(b["dodges"])
		if da != db:
			return da > db
		if config.tie_break_rule == "survival_time":
			if bool(a["alive"]) != bool(b["alive"]):
				return bool(a["alive"])
			if not is_equal_approx(float(a["survival_time"]), float(b["survival_time"])):
				return float(a["survival_time"]) > float(b["survival_time"])
		return int(a["id"]) < int(b["id"])
	)

	var entries: Array[Dictionary] = []
	var prev_dodges: int = -1
	var prev_rank: int = 1
	for idx in range(sorted.size()):
		var p: Dictionary = sorted[idx]
		var d: int = int(p["dodges"])
		var rank: int = idx + 1
		if config.tie_break_rule == "shared_rank" and idx > 0 and d == prev_dodges:
			rank = prev_rank
		prev_dodges = d
		prev_rank = rank
		var bonus: int = config.bonus_for_rank(rank, d)
		entries.append({
			"rank": rank,
			"id": int(p["id"]),
			"network_id": int(p.get("network_id", int(p["id"]) + 1)),
			"nickname": str(p["nickname"]),
			"color": p["color"],
			"alive": bool(p["alive"]),
			"dodges": d,
			"survival_time": float(p["survival_time"]),
			"bonus": bonus,
		})
	return entries


func _finish_round(reason: String) -> void:
	if _match_ended:
		return
	_match_ended = true
	_end_reason = reason

	var rankings: Array[Dictionary] = _compute_rankings()
	var finalized_scores: Dictionary = {}
	for r in rankings:
		var nid: int = int(r["network_id"])
		var bonus: int = int(r["bonus"])
		_session_scores[nid] = int(_session_scores.get(nid, 0)) + bonus
		r["total_score"] = int(_session_scores[nid])
		finalized_scores[nid] = bonus

	player_scores_finalized.emit(finalized_scores)

	if _hosted_in_official_game:
		if multiplayer == null or not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			minigame_finished.emit(1)
		return

	_populate_results_ui(rankings)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "GameHUD"
	_ui_layer.layer = 2
	add_child(_ui_layer)

	var term_font: Font = _meshes.load_terminal_font()
	var hud_theme := Theme.new()
	if term_font != null:
		hud_theme.default_font = term_font
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.theme = hud_theme
	_ui_layer.add_child(root_ctrl)

	# --- Top Bar: Countdown Timer + Speed + Controls ---
	var top_bar := HBoxContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 20.0
	top_bar.offset_right = -20.0
	top_bar.offset_top = 14.0
	top_bar.offset_bottom = 66.0
	root_ctrl.add_child(top_bar)

	var left_badge := _make_panel_box(Color(0.11, 0.08, 0.14, 0.85))
	top_bar.add_child(left_badge)
	_speed_label = Label.new()
	_speed_label.text = "機械嘉年華 · 速度 x1.00"
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
	left_badge.add_child(_speed_label)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(sp1)

	var timer_box := _make_panel_box(Color(0.18, 0.08, 0.10, 0.92))
	top_bar.add_child(timer_box)
	_timer_label = Label.new()
	_timer_label.text = "50.0s"
	_timer_label.add_theme_font_size_override("font_size", 32)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	timer_box.add_child(_timer_label)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(sp2)

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	btn_box.visible = not _hosted_in_official_game
	top_bar.add_child(btn_box)

	var room_btn := Button.new()
	room_btn.text = "開房參數 [C]"
	room_btn.pressed.connect(_open_room_creation_setup)
	btn_box.add_child(room_btn)

	var restart_btn := Button.new()
	restart_btn.text = "重開 [R]"
	restart_btn.pressed.connect(_start_new_round)
	btn_box.add_child(restart_btn)

	# --- Opening Controls Hint Banner ---
	_hint_panel = _make_panel_box(Color(0.12, 0.09, 0.15, 0.88))
	_hint_panel.anchor_left = 0.5
	_hint_panel.anchor_right = 0.5
	_hint_panel.offset_left = -310.0
	_hint_panel.offset_right = 310.0
	_hint_panel.offset_top = 82.0
	_hint_panel.offset_bottom = 128.0
	root_ctrl.add_child(_hint_panel)

	var hint_lbl := Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.text = "按 [S] 下蹲躲避金色高滾筒   ·   按 [空白鍵] 跳躍躲避銀色低滾筒"
	hint_lbl.add_theme_font_size_override("font_size", 19)
	hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	_hint_panel.add_child(hint_lbl)

	# --- End-of-Round Settlement Overlay ---
	_results_panel = _make_panel_box(Color(0.10, 0.07, 0.13, 0.95))
	_results_panel.anchor_left = 0.5
	_results_panel.anchor_right = 0.5
	_results_panel.anchor_top = 0.5
	_results_panel.anchor_bottom = 0.5
	_results_panel.offset_left = -340.0
	_results_panel.offset_right = 340.0
	_results_panel.offset_top = -255.0
	_results_panel.offset_bottom = 250.0
	_results_panel.visible = false
	root_ctrl.add_child(_results_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	_results_panel.add_child(r_vbox)

	_results_title = Label.new()
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_title.text = "本局結算"
	_results_title.add_theme_font_size_override("font_size", 28)
	_results_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	r_vbox.add_child(_results_title)

	_results_subtitle = Label.new()
	_results_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_subtitle.add_theme_font_size_override("font_size", 16)
	_results_subtitle.add_theme_color_override("font_color", Color(0.88, 0.84, 0.92))
	r_vbox.add_child(_results_subtitle)

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(r_scroll)

	_results_rows = VBoxContainer.new()
	_results_rows.add_theme_constant_override("separation", 6)
	_results_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_scroll.add_child(_results_rows)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	r_vbox.add_child(btn_row)

	var again_btn := Button.new()
	again_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again_btn.text = "進入下一局 [R]"
	again_btn.pressed.connect(_start_new_round)
	btn_row.add_child(again_btn)

	var rehost_btn := Button.new()
	rehost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rehost_btn.text = "返回創建房間調參 [C]"
	rehost_btn.pressed.connect(_open_room_creation_setup)
	btn_row.add_child(rehost_btn)

	# --- Room-Creation Unified Parameter Setup Overlay ---
	_build_room_setup_panel(root_ctrl)


func _make_panel_box(bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_left = 8
	st.corner_radius_bottom_right = 8
	st.border_color = Color(0.82, 0.60, 0.24, 0.75)
	st.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", st)
	return panel


func _update_hud_labels() -> void:
	_timer_label.text = "%.1fs" % _time_left
	var ratio: float = _current_roller_speed() / maxf(0.1, config.roller_initial_speed)
	var alive_cnt: int = 0
	for p in _players:
		if bool(p["alive"]):
			alive_cnt += 1
	_speed_label.text = "機械嘉年華 · 存活 %d/%d · 速度 x%.2f" % [alive_cnt, _players.size(), ratio]


func _populate_results_ui(rankings: Array[Dictionary]) -> void:
	for child in _results_rows.get_children():
		child.queue_free()

	_results_title.text = "本局結算 & 玩家總分總覽"
	_results_subtitle.text = _end_reason
	for r in rankings:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var rk := Label.new()
		rk.custom_minimum_size.x = 46
		rk.text = "#%d" % int(r["rank"])
		rk.add_theme_font_size_override("font_size", 17)
		row.add_child(rk)

		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text = str(r["nickname"]) + ("  [存活]" if bool(r["alive"]) else "  [💀 淘汰]")
		nm.add_theme_color_override("font_color", (r["color"] as Color).lightened(0.2))
		nm.add_theme_font_size_override("font_size", 17)
		row.add_child(nm)

		var dg := Label.new()
		dg.custom_minimum_size.x = 110
		dg.text = "躲避 %d 次" % int(r["dodges"])
		dg.add_theme_font_size_override("font_size", 17)
		row.add_child(dg)

		var bn := Label.new()
		bn.custom_minimum_size.x = 155
		bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bn.text = "+%d  (總分 %d)" % [int(r["bonus"]), int(r["total_score"])]
		bn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		bn.add_theme_font_size_override("font_size", 17)
		row.add_child(bn)

		_results_rows.add_child(row)

	_results_panel.visible = true


const PLAYER_PRESET_COUNTS := [4, 8, 12, 16]
const PACE_PRESET_KEYS := ["casual", "standard", "frantic"]
const DURATION_PRESET_KEYS := ["short", "standard", "long"]
const SPAWN_PRESET_KEYS := ["safe", "standard", "extreme"]
const KNOCKBACK_PRESET_KEYS := ["light", "standard", "heavy"]


func _add_preset_option_row(grid: GridContainer, label_text: String, items: Array[String]) -> OptionButton:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	grid.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 34)
	for item_text in items:
		opt.add_item(item_text)
	opt.item_selected.connect(_on_pummel_preset_selected)
	grid.add_child(opt)
	return opt


func _build_room_setup_panel(parent_ctrl: Control) -> void:
	_room_setup_panel = _make_panel_box(Color(0.08, 0.06, 0.12, 0.96))
	_room_setup_panel.anchor_left = 0.5
	_room_setup_panel.anchor_right = 0.5
	_room_setup_panel.anchor_top = 0.5
	_room_setup_panel.anchor_bottom = 0.5
	_room_setup_panel.offset_left = -390.0
	_room_setup_panel.offset_right = 390.0
	_room_setup_panel.offset_top = -270.0
	_room_setup_panel.offset_bottom = 265.0
	_room_setup_panel.visible = false
	parent_ctrl.add_child(_room_setup_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_room_setup_panel.add_child(vb)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "創建房間 · 滾筒嘉年華派對設定"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.36))
	vb.add_child(title)

	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "《揍擊派對》風格快速開房（支援 1–16 人同屏）· 開局後自動鎖定並同步全員"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.84, 0.80, 0.88))
	vb.add_child(sub)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 18)
	preset_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(preset_grid)

	_preset_players_opt = _add_preset_option_row(preset_grid, "1. 同屏玩家人數", ["4 人 (經典四排)", "8 人 (派對標準)", "12 人 (大型同屏)", "16 人 (極限滿場)"])
	_preset_pace_opt = _add_preset_option_row(preset_grid, "2. 滾筒節奏 (難度)", ["休閒 (慢速熱身)", "標準 (推薦)", "狂暴 (高速刺激)"])
	_preset_duration_opt = _add_preset_option_row(preset_grid, "3. 單局時長", ["30 秒 (快節奏)", "50 秒 (標準)", "80 秒 (持久戰)"])
	_preset_spawn_opt = _add_preset_option_row(preset_grid, "4. 起跑線位置 (容錯度)", ["靠前安全 (遠離岩漿・高容錯)", "標準中央 (平衡)", "極限貼邊 (靠近岩漿・高刺激)"])
	_preset_knockback_opt = _add_preset_option_row(preset_grid, "5. 撞擊推擠力道", ["輕推 (0.85 身位)", "標準 (1 身位)", "重擊飛退 (1.5+ 身位)"])

	_adv_toggle_btn = Button.new()
	_adv_toggle_btn.text = "▶ 展開進階微調參數 (速度/高度/加分表)"
	_adv_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_adv_toggle_btn.pressed.connect(func() -> void:
		if _adv_container == null:
			return
		_adv_container.visible = not _adv_container.visible
		_adv_toggle_btn.text = "▼ 收起進階微調參數" if _adv_container.visible else "▶ 展開進階微調參數 (速度/高度/加分表)"
	)
	vb.add_child(_adv_toggle_btn)

	_adv_container = VBoxContainer.new()
	_adv_container.visible = false
	_adv_container.add_theme_constant_override("separation", 6)
	vb.add_child(_adv_container)

	var adv_scroll := ScrollContainer.new()
	adv_scroll.custom_minimum_size = Vector2(720, 175)
	adv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_adv_container.add_child(adv_scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adv_scroll.add_child(grid)

	var fields := [
		["round_duration", "單局時長 (秒)"],
		["max_players", "玩家人數 (1-16)"],
		["player_spawn_x", "初始起跑線 X 座標 (-3.5~6.5)"],
		["roller_initial_speed", "滾筒初始速度"],
		["roller_max_speed", "局末最大速度"],
		["spawn_interval_min", "最小生成間隔 (秒)"],
		["spawn_interval_max", "最大生成間隔 (秒)"],
		["knockback_distance", "推擠距離 (身位)"],
		["knockback_cooldown", "推擠冷卻 (秒)"],
		["jump_height", "跳躍高度"],
		["jump_air_time", "跳躍滯空 (秒)"],
		["crouch_height", "下蹲判定高度"],
		["gold_roller_probability", "金色高滾筒機率 (0-1)"],
		["linear_points_per_dodge", "每躲避線性加分"],
		["rank_bonus_points", "1-8名加分檔位"],
	]
	for pair in fields:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = pair[1]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = 135
		row.add_child(edit)
		grid.add_child(row)
		_room_setup_inputs[pair[0]] = edit

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 18)
	_adv_container.add_child(mode_row)

	var curve_lbl := Label.new()
	curve_lbl.text = "加速曲線:"
	mode_row.add_child(curve_lbl)
	_curve_option = OptionButton.new()
	_curve_option.add_item("linear (線性遞增)")
	_curve_option.add_item("exponential (指數加速)")
	_curve_option.add_item("stepped (分段提速)")
	mode_row.add_child(_curve_option)

	var tie_lbl := Label.new()
	tie_lbl.text = "並列規則:"
	mode_row.add_child(tie_lbl)
	_tie_option = OptionButton.new()
	_tie_option.add_item("shared_rank (同躲避並列)")
	_tie_option.add_item("survival_time (按存活時長)")
	mode_row.add_child(_tie_option)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	vb.add_child(action_row)

	var reset_btn := Button.new()
	reset_btn.text = "恢復預設值"
	reset_btn.custom_minimum_size = Vector2(150, 40)
	reset_btn.pressed.connect(_reset_room_setup_defaults)
	action_row.add_child(reset_btn)

	var start_btn := Button.new()
	start_btn.text = "鎖定房間參數並開始對局"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.custom_minimum_size.y = 40
	start_btn.pressed.connect(_confirm_room_setup)
	action_row.add_child(start_btn)


func _on_pummel_preset_selected(_idx: int) -> void:
	if _preset_players_opt == null or _preset_pace_opt == null:
		return
	var p_cnt: int = PLAYER_PRESET_COUNTS[clampi(_preset_players_opt.selected, 0, PLAYER_PRESET_COUNTS.size() - 1)]
	var pace_k: String = PACE_PRESET_KEYS[clampi(_preset_pace_opt.selected, 0, PACE_PRESET_KEYS.size() - 1)]
	var dur_k: String = DURATION_PRESET_KEYS[clampi(_preset_duration_opt.selected, 0, DURATION_PRESET_KEYS.size() - 1)]
	var spawn_k: String = SPAWN_PRESET_KEYS[clampi(_preset_spawn_opt.selected, 0, SPAWN_PRESET_KEYS.size() - 1)]
	var kb_k: String = KNOCKBACK_PRESET_KEYS[clampi(_preset_knockback_opt.selected, 0, KNOCKBACK_PRESET_KEYS.size() - 1)]

	config.max_players = p_cnt
	config.apply_pummel_presets(pace_k, dur_k, spawn_k, kb_k)
	_apply_dict_to_room_setup_ui(config.to_dict(), false)


func _select_player_count_option(mp: int) -> int:
	if mp <= 4:
		return 0
	if mp <= 8:
		return 1
	if mp <= 12:
		return 2
	return 3


func _apply_dict_to_room_setup_ui(d: Dictionary, sync_presets: bool = true) -> void:
	if sync_presets and _preset_players_opt != null:
		_preset_players_opt.selected = _select_player_count_option(int(d.get("max_players", 8)))
		_preset_pace_opt.selected = maxi(0, PACE_PRESET_KEYS.find(str(d.get("preset_pace", "standard"))))
		_preset_duration_opt.selected = maxi(0, DURATION_PRESET_KEYS.find(str(d.get("preset_duration", "standard"))))
		_preset_spawn_opt.selected = maxi(0, SPAWN_PRESET_KEYS.find(str(d.get("preset_spawn", "standard"))))
		_preset_knockback_opt.selected = maxi(0, KNOCKBACK_PRESET_KEYS.find(str(d.get("preset_knockback", "standard"))))

	for k in _room_setup_inputs:
		if k == "rank_bonus_points":
			var pts: Array = d.get("rank_bonus_points", [])
			var strs: PackedStringArray = PackedStringArray()
			for v in pts:
				strs.append(str(v))
			(_room_setup_inputs[k] as LineEdit).text = ",".join(strs)
		else:
			(_room_setup_inputs[k] as LineEdit).text = str(d.get(k, ""))

	if _curve_option != null:
		var cm := str(d.get("speed_curve_mode", "linear"))
		_curve_option.selected = 1 if cm == "exponential" else (2 if cm == "stepped" else 0)
	if _tie_option != null:
		var tr := str(d.get("tie_break_rule", "shared_rank"))
		_tie_option.selected = 1 if tr == "survival_time" else 0


func _reset_room_setup_defaults() -> void:
	var base_dir: String = get_script().get_path().get_base_dir()
	var cfg_script = load(base_dir.path_join("config.gd"))
	if cfg_script == null:
		return
	var fresh_cfg = cfg_script.new()
	_apply_dict_to_room_setup_ui(fresh_cfg.to_dict())


func _open_room_creation_setup() -> void:
	_awaiting_room_setup = true
	if _results_panel != null:
		_results_panel.visible = false
	if _hint_panel != null:
		_hint_panel.visible = false
	_load_room_config_from_globals()
	_apply_dict_to_room_setup_ui(config.to_dict())
	_room_setup_panel.visible = true


func _confirm_room_setup() -> void:
	var updated := {}
	for k in _room_setup_inputs:
		updated[k] = (_room_setup_inputs[k] as LineEdit).text
	if _curve_option != null:
		var modes := ["linear", "exponential", "stepped"]
		updated["speed_curve_mode"] = modes[clampi(_curve_option.selected, 0, modes.size() - 1)]
	if _tie_option != null:
		var rules := ["shared_rank", "survival_time"]
		updated["tie_break_rule"] = rules[clampi(_tie_option.selected, 0, rules.size() - 1)]
	if _preset_pace_opt != null:
		updated["preset_pace"] = PACE_PRESET_KEYS[clampi(_preset_pace_opt.selected, 0, PACE_PRESET_KEYS.size() - 1)]
		updated["preset_duration"] = DURATION_PRESET_KEYS[clampi(_preset_duration_opt.selected, 0, DURATION_PRESET_KEYS.size() - 1)]
		updated["preset_spawn"] = SPAWN_PRESET_KEYS[clampi(_preset_spawn_opt.selected, 0, SPAWN_PRESET_KEYS.size() - 1)]
		updated["preset_knockback"] = KNOCKBACK_PRESET_KEYS[clampi(_preset_knockback_opt.selected, 0, KNOCKBACK_PRESET_KEYS.size() - 1)]

	config.apply_dict(updated)
	_save_room_config_to_globals()
	_session_scores.clear()
	_room_setup_panel.visible = false
	_start_new_round()


func _setup_screenshot_showcase() -> void:
	_elapsed = 8.5
	_time_left = 41.5
	_hint_panel.visible = true
	_hint_panel.modulate.a = 1.0

	# Option A: unhit players stand aligned on the exact starting line (player_spawn_x),
	# while players who took hits visibly step left toward the lava pit (supports up to 16 players).
	for idx in range(_players.size()):
		var p: Dictionary = _players[idx]
		p["x"] = config.player_spawn_x
		p["dodges"] = 3 + ((idx * 3) % 5)
		if idx == _players.size() - 1 and _players.size() >= 4:
			p["x"] = config.stage_left_lava_x - 0.55
			_eliminate_player(p)
			p["dodges"] = 1
			p["sink_progress"] = 0.28
			var pnode := p["node"] as Node3D
			pnode.position = Vector3(float(p["x"]), -0.42, float(p["z"]))
			pnode.rotation_degrees.z = 18.0
		elif idx == 2 or idx == 10:
			p["x"] = config.player_spawn_x - config.knockback_distance
		elif idx == 5 or idx == 13:
			p["x"] = config.player_spawn_x - config.knockback_distance * 2.8
		elif idx % 4 == 0:
			p["crouching"] = true
		elif idx % 4 == 1:
			p["jumping"] = true
			p["y"] = 1.35

	for p in _players:
		if p["alive"]:
			_update_player_visuals(p)

	_spawn_roller("gold", 2.9)
	_spawn_roller("silver", 7.4)
	_spawn_impact_decal(Vector3(-3.3, 0.02, -0.4))
	_update_hud_labels()


var _tests_failed: bool = false


func _assert_true(cond: bool, msg: String) -> bool:
	if not cond:
		_tests_failed = true
		push_error("SELF_TEST_FAILED: " + msg)
		get_tree().quit(1)
		return false
	return true


func _run_self_tests() -> void:
	_tests_failed = false
	# 0. Test Option A: all 8 players spawn aligned on the exact same starting line (player_spawn_x)
	config.max_players = 8
	_start_new_round()
	if not _assert_true(_players.size() == 8, "Must spawn 8 players when max_players=8"):
		return
	for i in range(_players.size()):
		if not _assert_true(is_equal_approx(float(_players[i]["x"]), config.player_spawn_x), "All players must spawn on exact same starting line X"):
			return
		if i > 0 and not _assert_true(float(_players[i]["z"]) > float(_players[i - 1]["z"]), "Players must be strictly separated along Z lanes"):
			return

	config.apply_dict({"player_spawn_x": 2.6, "max_players": 8})
	_start_new_round()
	for p in _players:
		if not _assert_true(is_equal_approx(float(p["x"]), 2.6), "Configured player_spawn_x must move all player spawns"):
			return
	var sl_node := _scene_props.get("starting_line", null) as Node3D
	if not _assert_true(sl_node != null and is_equal_approx(sl_node.position.x, 2.6), "Stage StartingLine mesh must sync with configured player_spawn_x"):
		return

	# 0b. Test Pummel Party presets and 16-player scaling
	config.apply_pummel_presets("frantic", "short", "safe", "heavy")
	if not _assert_true(is_equal_approx(config.round_duration, 30.0) and is_equal_approx(config.player_spawn_x, 3.0) and is_equal_approx(config.knockback_distance, 2.10) and is_equal_approx(config.roller_initial_speed, 7.6), "Pummel Party presets must set linked rule fields"):
		return
	config.max_players = 16
	_start_new_round()
	if not _assert_true(_players.size() == 16, "Must spawn 16 players when max_players=16"):
		return
	for p16 in _players:
		if not _assert_true(is_equal_approx(float(p16["x"]), config.player_spawn_x), "All 16 players must spawn on exact same starting line X"):
			return
	config.max_players = 8
	config.apply_pummel_presets("standard", "standard", "standard", "standard")

	# 1. Test Gold High Roller: standing player hit (knockback, +0) vs crouching player dodges (+1)
	config.max_players = 2
	_start_new_round()
	var p_stand: Dictionary = _players[0]
	var p_crouch: Dictionary = _players[1]
	p_stand["x"] = 0.0
	p_crouch["x"] = 0.0
	p_stand["crouching"] = false
	p_crouch["crouching"] = true

	var gold_r := _spawn_roller("gold", 0.1)
	_evaluate_roller_interactions(gold_r)
	if not _assert_true(is_equal_approx(float(p_stand["x"]), -config.knockback_distance), "Standing player must be knocked back by Gold roller"):
		return
	if not _assert_true(is_equal_approx(float(p_crouch["x"]), 0.0), "Crouching player must avoid Gold roller"):
		return

	gold_r["x"] = -2.8
	_evaluate_roller_interactions(gold_r)
	if not _assert_true(int(p_stand["dodges"]) == 0, "Hit player must not gain dodge count"):
		return
	if not _assert_true(int(p_crouch["dodges"]) == 1, "Crouching player must gain +1 dodge after Gold roller passes"):
		return

	# 2. Test Silver Low Roller: crouching player hit (knockback, +0) vs jumping player dodges (+1)
	p_stand["x"] = 0.0
	p_stand["knockback_cooldown"] = 0.0
	p_stand["crouching"] = true
	p_crouch["x"] = 0.0
	p_crouch["crouching"] = false
	p_crouch["jumping"] = true
	p_crouch["y"] = 1.2

	var silver_r := _spawn_roller("silver", 0.1)
	_evaluate_roller_interactions(silver_r)
	if not _assert_true(is_equal_approx(float(p_stand["x"]), -config.knockback_distance), "Crouching player must be knocked back by Silver roller"):
		return
	if not _assert_true(is_equal_approx(float(p_crouch["x"]), 0.0), "Jumping player must avoid Silver roller"):
		return

	silver_r["x"] = -2.8
	_evaluate_roller_interactions(silver_r)
	if not _assert_true(int(p_stand["dodges"]) == 0, "Hit player must not gain dodge count for Silver roller"):
		return
	if not _assert_true(int(p_crouch["dodges"]) == 2, "Jumping player must gain +1 dodge after Silver roller passes"):
		return

	# 3. Test cumulative knockback -> lava elimination -> early match termination
	p_stand["x"] = config.stage_left_lava_x + 0.5
	p_stand["knockback_cooldown"] = 0.0
	p_stand["crouching"] = false
	var push_r := _spawn_roller("gold", float(p_stand["x"]) + 0.1)
	_evaluate_roller_interactions(push_r)
	if not _assert_true(not bool(p_stand["alive"]), "Player pushed past stage_left_lava_x must be eliminated"):
		return

	_eliminate_player(p_crouch)
	_update_hud_labels()
	if not _assert_true("存活 0/2" in _speed_label.text, "HUD must show alive count 0/2 when both players eliminated"):
		return

	_check_round_end()
	if not _assert_true(_match_ended, "Match must end immediately when all players are eliminated"):
		return

	# 4. Test ranking & bonus table [100, 80, 60, 40, 40, 40, 20, 20]
	var ranks := _compute_rankings()
	if not _assert_true(ranks.size() == 2, "Rankings must include both players"):
		return
	if not _assert_true(int(ranks[0]["id"]) == 1 and int(ranks[0]["bonus"]) == 100, "Top dodger gets rank 1 (+100)"):
		return
	if not _assert_true(int(ranks[1]["id"]) == 0 and int(ranks[1]["bonus"]) == 80, "Second place gets rank 2 (+80)"):
		return
	if not _assert_true(config.bonus_for_rank(3, 5) == 60, "Rank 3 bonus is 60"):
		return
	if not _assert_true(config.bonus_for_rank(6, 5) == 40, "Rank 6 bonus is 40"):
		return
	if not _assert_true(config.bonus_for_rank(8, 5) == 20, "Rank 8 bonus is 20"):
		return

	# 5. Test spawn safety floor invariant
	var iv: Vector2 = config.interval_range_at_progress(1.0)
	if not _assert_true(iv.x >= config.safe_interval_floor(), "Spawn interval min must respect safe reaction floor"):
		return

	# 6. Test official Machine Party Minigame contract signals & initialize()
	var captured := {"scores": {}, "finished": false}
	player_scores_finalized.connect(func(s: Dictionary) -> void:
		captured["scores"] = s
	)
	minigame_finished.connect(func(_nid: int) -> void:
		captured["finished"] = true
	)
	_hosted_in_official_game = true
	initialize(1, 2, {})
	_players[0]["dodges"] = 7
	_players[1]["dodges"] = 3
	_finish_round("test")
	var got_scores: Dictionary = captured["scores"]
	if not _assert_true(int(got_scores.get(1, -1)) == 100 and int(got_scores.get(2, -1)) == 80, "player_scores_finalized must emit bonus points by network_id"):
		return
	if not _assert_true(bool(captured["finished"]), "minigame_finished must emit when hosted in official Game"):
		return

	if not _tests_failed:
		print("SELF_TEST_PASSED")
		get_tree().quit(0)
