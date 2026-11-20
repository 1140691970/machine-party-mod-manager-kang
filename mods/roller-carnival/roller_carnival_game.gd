extends Node3D

## Roller Carnival (滾筒嘉年華) — 3D Oblique Top-Down Dodge Party Minigame.
##
## Rules:
## - 1-8 players spawn dispersed in the central stage area.
## - Gold High Rollers appear at mid-height on the far right -> tap S (or Down) to crouch under.
## - Silver Low Rollers appear at ground-level on the far right -> press Space to jump over.
## - Rollers keep fixed height and roll left; touching a player applies pure knockback (~1 body width),
##   zero HP loss, cumulative across hits. Being pushed into the left lava pit eliminates immediately.
## - Dodge count increments (+1) per roller safely passed without collision; eliminated players keep
##   their dodge counts for end-of-round ranking & configurable bonus points.
## - Round lasts default 50s; surviving to 0s wins, or ends early if all players are eliminated.

var config = null
var _meshes = null

signal round_finished(scores: Dictionary)
var _hosted_in_official_game := false
var _roster: Array = []
const COUNTDOWN_SECONDS := 3.0
const ENTRANCE_SECONDS := 0.75
const ENTRANCE_HEIGHT := 3.0
const RELEASE_CROUCH := 4
const CAM_BASE_POS := Vector3(0.45, 11.8, 11.8)
const CAM_LOOK_TARGET := Vector3(0.35, 0.65, 0.0)
var _held_controls := {}
var _snapshot_timer := 0.0
var _countdown := 0.0

var _rng := RandomNumberGenerator.new()
var _scene_props: Dictionary = {}
var _players: Array[Dictionary] = []
var _rollers: Array[Dictionary] = []
var _decals: Array[Node3D] = []
var _particles: Array[Dictionary] = []

var _players_layer: Node3D
var _rollers_layer: Node3D
var _fx_layer: Node3D

var _elapsed: float = 0.0
var _time_left: float = 50.0
var _spawn_timer: float = 1.0
var _wave_remaining := 0
var _last_roller_type: String = ""
var _same_type_streak: int = 0
var _next_roller_id: int = 1
var _match_ended: bool = false
var _beacon_gold_flash: float = 0.0
var _beacon_silver_flash: float = 0.0
var _camera_shake: float = 0.0
var _cam_sway_time: float = 0.0
var _go_timer: float = 0.0
var _you_marker_timer: float = 0.0
var _you_marker_shown: bool = false
var _last_countdown_ceil: int = 4
var _last_timer_beep_sec: int = -1

# UI References
var _ui_layer: CanvasLayer
var _countdown_label: Label
var _go_label: Label
var _round_banner: Control
var _round_title_label: Label
var _round_tagline_label: Label
var _you_marker: YouMarkerOverlay
var _results_panel: PanelContainer
var _results_title: Label
var _results_subtitle: Label
var _results_rows: VBoxContainer
var _is_self_test: bool = false
var _screenshot_path: String = ""
var _sfx_shove: AudioStreamPlayer = null
var _sfx_fall: AudioStreamPlayer = null
var _sfx_round_show: AudioStreamPlayer = null
var _sfx_ding: AudioStreamPlayer = null
var _sfx_countdown: AudioStreamPlayer = null
var _sfx_timer_beep: AudioStreamPlayer = null
var _ambience_player: AudioStreamPlayer = null
var _shader_layer: CanvasLayer = null
var _fx_hit_blood_scene: PackedScene = null
var _fx_bloodmist_scene: PackedScene = null
var _blood_tex_01: Texture2D = null
var _blood_tex_02: Texture2D = null


class YouMarkerOverlay extends Control:
	var top_left: Vector2 = Vector2.ZERO
	var bound_size: Vector2 = Vector2.ZERO
	var marker_font: Font = null
	var marker_text: String = "YOU"
	var shake_offset: Vector2 = Vector2.ZERO
	var active: bool = false

	func _draw() -> void:
		if not active or bound_size.x <= 1.0 or bound_size.y <= 1.0:
			return
		var font_to_use: Font = marker_font if marker_font != null else ThemeDB.fallback_font
		var viewport_rect := get_viewport_rect()
		var bounds_center := top_left + bound_size * 0.5
		var viewport_center := viewport_rect.size * 0.5
		var dir := Vector2(1.0 if bounds_center.x < viewport_center.x else -1.0, 1.0 if bounds_center.y < viewport_center.y else -1.0)
		var start_point := Vector2(
			top_left.x + maxf(bound_size.x * dir.x, 0.0),
			top_left.y + maxf(bound_size.y * dir.y, 0.0)
		) - dir
		var text_size := font_to_use.get_string_size(marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		var text_point := start_point + dir * 32.0 + Vector2(minf(dir.x, 0.0) * text_size.x, 0.0)
		var line_pts := PackedVector2Array([
			start_point,
			start_point + dir * 32.0,
			start_point + dir * 32.0 + Vector2(dir.x * text_size.x, 0.0),
		])
		var corner := 16.0
		var shadow := Vector2(2.0, 2.0)
		for pass_idx in range(2):
			var off := (shadow if pass_idx == 0 else Vector2.ZERO) + shake_offset
			var col := Color.BLACK if pass_idx == 0 else Color.WHITE
			var p0 := top_left + off
			var p1 := top_left + Vector2(bound_size.x, 0.0) + off
			var p2 := top_left + bound_size + off
			var p3 := top_left + Vector2(0.0, bound_size.y) + off
			draw_line(p0, p0 + Vector2.RIGHT * corner, col, 2.0)
			draw_line(p0, p0 + Vector2.DOWN * corner, col, 2.0)
			draw_line(p1, p1 + Vector2.LEFT * corner, col, 2.0)
			draw_line(p1, p1 + Vector2.DOWN * corner, col, 2.0)
			draw_line(p2, p2 + Vector2.UP * corner, col, 2.0)
			draw_line(p2, p2 + Vector2.LEFT * corner, col, 2.0)
			draw_line(p3, p3 + Vector2.UP * corner, col, 2.0)
			draw_line(p3, p3 + Vector2.RIGHT * corner, col, 2.0)
			var s_pts := PackedVector2Array([line_pts[0] + off, line_pts[1] + off, line_pts[2] + off])
			draw_polyline(s_pts, col, 2.0, false)
			draw_string(font_to_use, text_point + Vector2(0.0, -4.0) + off, marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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
	_hosted_in_official_game = get_parent().has_method("all_players_loaded")
	_build_ui()

	if _is_self_test:
		_run_self_tests()
		return

	if not _hosted_in_official_game:
		if DisplayServer.get_name() != "headless":
			DisplayServer.set_icon(_meshes.build_roller_icon().get_image())
		start_round([])
		if not _screenshot_path.is_empty():
			await get_tree().create_timer(4.7).timeout
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(_screenshot_path.get_base_dir())
			var error := image.save_png(_screenshot_path)
			if error == OK:
				print("SCREENSHOT_SAVED=" + _screenshot_path)
			get_tree().quit(error)


func _loc_or(key: String, fallback: String) -> String:
	var translated := tr(key)
	return fallback if (translated.is_empty() or translated == key) else translated


@rpc("authority", "call_local", "reliable")
func start_round(roster: Array) -> void:
	_roster = roster
	_start_new_round()
	# The briefing and the stage share a viewport in the official game.
	$StageCamera.make_current()
	_countdown = COUNTDOWN_SECONDS
	_update_entrance()
	_countdown_label.text = str(ceili(_countdown))
	_countdown_label.show()

	if not _is_self_test and _round_banner != null:
		var round_num := 1
		var total_num := 1
		if not _roster.is_empty() and _roster[0] is Dictionary:
			round_num = int((_roster[0] as Dictionary).get("round_number", 1))
			total_num = int((_roster[0] as Dictionary).get("total_rounds", 1))
		_round_title_label.text = _loc_or("LOC_IM_ROUND", "Round %s/%s") % [round_num, total_num]
		_round_tagline_label.text = _loc_or("LOC_MG_TAGLINE_11", "SURVIVAL IS UNLIKELY.")
		_round_tagline_label.visible_ratio = 0.0
		_round_banner.modulate.a = 1.0
		_round_banner.visible = true
		_countdown_label.modulate.a = 0.0
		if _sfx_round_show != null and _screenshot_path.is_empty():
			_sfx_round_show.play()


func _update_entrance() -> void:
	var progress := clampf((COUNTDOWN_SECONDS - _countdown) / ENTRANCE_SECONDS, 0.0, 1.0)
	for player in _players:
		var visual: Node3D = player["visual"]
		visual.position.y = ENTRANCE_HEIGHT * (1.0 - progress * progress)


func player_disconnected(_network_id: int) -> void:
	for p in _players:
		if int(p.get("network_id", -1)) == _network_id and bool(p["alive"]):
			_eliminate_player(p)


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

		var round_stream = _meshes.load_optional("res://audio/unique/intermission/intermission show round1.ogg")
		if round_stream is AudioStream:
			_sfx_round_show = AudioStreamPlayer.new()
			_sfx_round_show.stream = round_stream
			_sfx_round_show.pitch_scale = 0.6
			_sfx_round_show.volume_db = -3.0
			add_child(_sfx_round_show)

		var ding_stream = _meshes.load_optional("res://audio/sfx/airplane ding.ogg")
		if ding_stream is AudioStream:
			_sfx_ding = AudioStreamPlayer.new()
			_sfx_ding.stream = ding_stream
			_sfx_ding.volume_db = -4.0
			add_child(_sfx_ding)

		var cd_stream = _meshes.load_optional("res://audio/sfx/countdown_mechanism2.ogg")
		if cd_stream is AudioStream:
			_sfx_countdown = AudioStreamPlayer.new()
			_sfx_countdown.stream = cd_stream
			_sfx_countdown.volume_db = -4.0
			add_child(_sfx_countdown)

		var beep_stream = _meshes.load_optional("res://audio/sfx/ekg_beep.ogg")
		if beep_stream is AudioStream:
			_sfx_timer_beep = AudioStreamPlayer.new()
			_sfx_timer_beep.stream = beep_stream
			_sfx_timer_beep.volume_db = -9.0
			add_child(_sfx_timer_beep)

		var amb_stream = _meshes.load_optional("res://audio/unique/dvd roomba/dvd roomba ambience.ogg")
		if amb_stream is AudioStream and _screenshot_path.is_empty():
			_ambience_player = AudioStreamPlayer.new()
			_ambience_player.stream = amb_stream
			_ambience_player.volume_db = -10.0
			add_child(_ambience_player)
			_ambience_player.play()

		var hit_scene = _meshes.load_optional("res://prefabs/managed_effects/hit_blood.tscn")
		if hit_scene is PackedScene:
			_fx_hit_blood_scene = hit_scene as PackedScene
		var mist_scene = _meshes.load_optional("res://prefabs/managed_effects/bloodmist_01.tscn")
		if mist_scene is PackedScene:
			_fx_bloodmist_scene = mist_scene as PackedScene
		var bt1 = _meshes.load_optional("res://textures/decals/blood decals/blood_splat_01.png")
		if bt1 is Texture2D:
			_blood_tex_01 = bt1 as Texture2D
		var bt2 = _meshes.load_optional("res://textures/decals/blood decals/blood_splat_02.png")
		if bt2 is Texture2D:
			_blood_tex_02 = bt2 as Texture2D
		_warmup_fx_pipelines.call_deferred()

	# Machine Party signature vignette + 8-step posterization with BackBufferCopy on layer 1 (below HUD layer 2)
	var post_shader = _meshes.load_optional("res://shaders/posterization.gdshader")
	var vig_shader = _meshes.load_optional("res://shaders/vignette.gdshader")
	if post_shader is Shader or vig_shader is Shader:
		_shader_layer = CanvasLayer.new()
		_shader_layer.name = "PostFXLayer"
		_shader_layer.layer = 1
		add_child(_shader_layer)

		var fx_root := Control.new()
		fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shader_layer.add_child(fx_root)

		if vig_shader is Shader:
			var vig_holder := Control.new()
			vig_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
			vig_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fx_root.add_child(vig_holder)

			var vig_copy := BackBufferCopy.new()
			vig_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			vig_holder.add_child(vig_copy)

			var vig_rect := ColorRect.new()
			vig_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var vm := ShaderMaterial.new()
			vm.shader = vig_shader
			vm.set_shader_parameter("radius", 0.90)
			vm.set_shader_parameter("softness", 0.38)
			vm.set_shader_parameter("intensity", 1.85)
			vm.set_shader_parameter("contrast", 1.57)
			vm.set_shader_parameter("vignette_color", Color(0.0, 0.0, 0.0, 1.0))
			vig_rect.material = vm
			vig_holder.add_child(vig_rect)

		if post_shader is Shader:
			var post_holder := Control.new()
			post_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
			post_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fx_root.add_child(post_holder)

			var post_copy := BackBufferCopy.new()
			post_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			post_holder.add_child(post_copy)

			var post_rect := ColorRect.new()
			post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pm := ShaderMaterial.new()
			pm.shader = post_shader
			pm.set_shader_parameter("SCREEN_WIDTH", 1920.0)
			pm.set_shader_parameter("RED_COMPONENT", 8.0)
			pm.set_shader_parameter("GREEN_COMPONENT", 8.0)
			pm.set_shader_parameter("BLUE_COMPONENT", 8.0)
			post_rect.material = pm
			post_holder.add_child(post_rect)


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
	_particles.clear()

	_elapsed = 0.0
	_time_left = config.round_duration
	_wave_remaining = 0
	_spawn_timer = 0.75
	_last_roller_type = ""
	_same_type_streak = 0
	_next_roller_id = 1
	_match_ended = false
	_snapshot_timer = 0.0
	_camera_shake = 0.0
	_go_timer = 0.0
	_you_marker_timer = 0.0
	_you_marker_shown = false
	_last_countdown_ceil = 4
	_last_timer_beep_sec = -1

	if _results_panel != null:
		_results_panel.visible = false
	if _go_label != null:
		_go_label.visible = false
	if _round_banner != null:
		_round_banner.visible = false
	if _you_marker != null:
		_you_marker.active = false
		_you_marker.visible = false

	if _meshes != null:
		_meshes.update_starting_line(_scene_props, config)
	_spawn_players()


func _resolve_roster_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _hosted_in_official_game:
		entries.assign(_roster)
	else:
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
	var local_nid := multiplayer.get_unique_id() if _hosted_in_official_game else 1
	for i in range(count):
		var entry: Dictionary = roster[i]
		var frac: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var spawn_z: float = lerpf(-z_span * 0.5, z_span * 0.5, frac)
		var nickname: String = str(entry["nickname"])
		var nid: int = int(entry["network_id"])
		var is_local: bool = (nid == local_nid)
		var cust_raw = entry.get("customization", [])
		var cust: Array = cust_raw if cust_raw is Array else []
		var visual_dict: Dictionary = _meshes.build_cartoon_character(i, nickname, cust, is_local)
		var pnode: Node3D = visual_dict["root"]
		pnode.position = Vector3(spawn_x, 0.0, spawn_z)
		pnode.scale = Vector3.ONE * char_scale
		_players_layer.add_child(pnode)

		_players.append({
			"id": i,
			"network_id": nid,
			"is_local": is_local,
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
			"crouch_remaining": 0.0,
			"crouch_ready_in": 0.0,
			"ai_held": 0,
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

	_update_camera(delta)
	_animate_environment(delta)
	_update_particles(delta)
	_update_you_marker(delta)

	if _go_timer > 0.0 and _go_label != null:
		_go_timer = maxf(0.0, _go_timer - delta)
		if _go_timer <= 0.0:
			_go_label.visible = false
		else:
			var t_go := 1.0 - clampf(_go_timer / 0.55, 0.0, 1.0)
			_go_label.position.y = lerpf(28.0, 0.0, clampf(t_go * 3.5, 0.0, 1.0))
			_go_label.modulate.a = clampf(_go_timer / 0.35, 0.0, 1.0)

	if _match_ended or _players.is_empty():
		return

	if _countdown > 0:
		_countdown = maxf(0.0, _countdown - delta)
		_update_entrance()
		_step_countdown_overlay()
		return

	if _hosted_in_official_game and not multiplayer.is_server():
		_step_rollers(delta)
		return

	_elapsed += delta
	_time_left = maxf(0.0, _time_left - delta)

	_step_spawner(delta)
	_step_players(delta)
	_step_rollers(delta)
	_resolve_player_spacing(delta)
	if _hosted_in_official_game:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0:
			_snapshot_timer = 0.05
			_send_snapshot()
	_check_round_end()


func _step_countdown_overlay() -> void:
	if _round_banner != null and _round_banner.visible:
		if _countdown > 2.4:
			_round_banner.modulate.a = 1.0
			_round_tagline_label.visible_ratio = clampf((COUNTDOWN_SECONDS - _countdown) / 0.50, 0.0, 1.0)
		elif _countdown > 1.9:
			_round_tagline_label.visible_ratio = 1.0
			_round_banner.modulate.a = clampf((_countdown - 1.9) / 0.50, 0.0, 1.0)
		else:
			_round_banner.visible = false

	if _countdown <= 2.3 and not _you_marker_shown:
		_you_marker_shown = true
		_you_marker_timer = 3.15
		if _sfx_ding != null and _screenshot_path.is_empty():
			_sfx_ding.play()

	if _countdown > 0.0:
		var cur_ceil := ceili(_countdown)
		_countdown_label.text = str(cur_ceil)
		_countdown_label.visible = true
		_countdown_label.modulate.a = 0.0 if _countdown > 2.0 else 1.0
		if cur_ceil != _last_countdown_ceil and cur_ceil > 0:
			_last_countdown_ceil = cur_ceil
			if cur_ceil <= 2 and _sfx_countdown != null and _screenshot_path.is_empty():
				_sfx_countdown.pitch_scale = 0.6
				_sfx_countdown.play()
	else:
		_countdown_label.visible = false
		if _go_label != null:
			_go_label.text = _loc_or("LOC_IM_GO", "GO!")
			_go_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_go_label.position.y = 28.0
			_go_label.show()
			_go_timer = 0.55
		if _sfx_countdown != null and _screenshot_path.is_empty():
			_sfx_countdown.pitch_scale = 0.8
			_sfx_countdown.play()


func _find_local_player() -> Dictionary:
	var local_nid := multiplayer.get_unique_id() if _hosted_in_official_game else 1
	for p in _players:
		if int(p.get("network_id", -1)) == local_nid:
			return p
	return _players[0] if not _players.is_empty() else {}


func _update_you_marker(delta: float) -> void:
	if _you_marker == null:
		return
	if _you_marker_timer <= 0.0:
		if _you_marker.active:
			_you_marker.active = false
			_you_marker.visible = false
		return
	_you_marker_timer = maxf(0.0, _you_marker_timer - delta)
	var lp := _find_local_player()
	var cam := get_node_or_null("StageCamera") as Camera3D
	if lp.is_empty() or not bool(lp.get("alive", false)) or cam == null or _match_ended or _countdown > 2.3:
		_you_marker.active = false
		_you_marker.visible = false
		return
	var px := float(lp["x"])
	var py := float(lp["y"]) + (lp["visual"] as Node3D).position.y
	var pz := float(lp["z"])
	var h := 0.85 if bool(lp["crouching"]) else 1.55
	var center := Vector3(px, py + h * 0.5, pz)
	var half := Vector3(0.40, h * 0.52, 0.40)
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var wp := center + Vector3(sx * half.x, sy * half.y, sz * half.z)
				if cam.is_position_behind(wp):
					_you_marker.visible = false
					return
				var sp := cam.unproject_position(wp)
				min_pt.x = minf(min_pt.x, sp.x)
				min_pt.y = minf(min_pt.y, sp.y)
				max_pt.x = maxf(max_pt.x, sp.x)
				max_pt.y = maxf(max_pt.y, sp.y)
	_you_marker.top_left = min_pt
	_you_marker.bound_size = max_pt - min_pt
	var jitter_step := int(floor(_cam_sway_time * 15.0)) % 4
	var jitters := [Vector2(0.5, 0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5)]
	_you_marker.shake_offset = jitters[jitter_step]
	_you_marker.active = true
	_you_marker.visible = true
	_you_marker.queue_redraw()


func _update_camera(delta: float) -> void:
	if _is_self_test:
		return
	var cam := get_node_or_null("StageCamera") as Camera3D
	if cam == null:
		return
	_cam_sway_time += delta
	_camera_shake = maxf(0.0, _camera_shake - delta * 2.6)
	var sway := Vector3(
		sin(_cam_sway_time * 0.55) * 0.07,
		cos(_cam_sway_time * 0.42) * 0.05,
		sin(_cam_sway_time * 0.35) * 0.04
	)
	var mag := 0.28 * _camera_shake * _camera_shake
	var shake := Vector3(
		_rng.randf_range(-1.0, 1.0) * mag,
		_rng.randf_range(-1.0, 1.0) * mag,
		_rng.randf_range(-1.0, 1.0) * mag
	) if _camera_shake > 0.001 else Vector3.ZERO
	cam.look_at_from_position(CAM_BASE_POS + sway + shake, CAM_LOOK_TARGET + shake * 0.35, Vector3.UP)


func _animate_environment(delta: float) -> void:
	var gears: Array = _scene_props.get("gears", [])
	for i in range(gears.size()):
		var g: Node3D = gears[i]
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		g.rotation.z += delta * (0.65 + float(i % 2) * 0.35) * dir

	var shredders: Array = _scene_props.get("pit_shredders", [])
	for i in range(shredders.size()):
		var sh := shredders[i] as Node3D
		if sh != null:
			sh.rotation.z += delta * (-2.8 if i % 2 == 0 else 2.8)

	var bubbles: Array = _scene_props.get("lava_bubbles", [])
	for b in bubbles:
		var node: MeshInstance3D = b["node"]
		var phase: float = b["phase"] + _cam_sway_time * 2.1
		var rise: float = fposmod(phase, TAU) / TAU
		node.position.y = -0.72 + rise * 0.72
		node.rotation.y += delta * 1.4
		var s: float = 1.0 - absf(rise * 2.0 - 1.0) * 0.65
		node.scale = Vector3(s, s, s)

	var bulbs: Array = _scene_props.get("bulbs", [])
	for i in range(bulbs.size()):
		var entry = bulbs[i]
		var mat: StandardMaterial3D = null
		if entry is StandardMaterial3D:
			mat = entry as StandardMaterial3D
		elif entry is MeshInstance3D:
			mat = (entry as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.25 + 0.30 * sin(_cam_sway_time * 5.2 + float(i) * 1.7)

	_beacon_gold_flash = maxf(0.0, _beacon_gold_flash - delta * 2.8)
	_beacon_silver_flash = maxf(0.0, _beacon_silver_flash - delta * 2.8)
	var bg := _scene_props.get("beacon_gold") as MeshInstance3D
	if bg and bg.material_override:
		(bg.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5 + _beacon_gold_flash * 3.0
	var bs := _scene_props.get("beacon_silver") as MeshInstance3D
	if bs and bs.material_override:
		(bs.material_override as StandardMaterial3D).emission_energy_multiplier = 0.5 + _beacon_silver_flash * 3.0

	var timer_lbl := _scene_props.get("monitor_timer_label") as Label3D
	var phase_lbl := _scene_props.get("monitor_phase_label") as Label3D
	if timer_lbl != null:
		var secs_left := ceili(maxf(0.0, _time_left))
		timer_lbl.text = "00:%02d" % secs_left
		if _countdown <= 0.0 and not _match_ended and _time_left <= 10.0 and _time_left > 0.0:
			var pulse := 0.75 + 0.25 * sin(_cam_sway_time * 12.0)
			timer_lbl.modulate = Color(1.0, 0.32 * pulse, 0.22 * pulse)
			if secs_left != _last_timer_beep_sec:
				_last_timer_beep_sec = secs_left
				if _sfx_timer_beep != null and _screenshot_path.is_empty():
					_sfx_timer_beep.play()
		else:
			timer_lbl.modulate = Color(0.53, 0.83, 0.50)
	if phase_lbl != null:
		if _elapsed < config.pair_start_time:
			phase_lbl.text = "WAVE 01 // SINGLE"
		elif _elapsed < config.triple_start_time:
			phase_lbl.text = "WAVE 02 // DOUBLE"
		else:
			phase_lbl.text = "WAVE 03 // OVERDRIVE"


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

	if _wave_remaining == 0:
		_wave_remaining = config.wave_size(_elapsed)
	_spawn_roller(_pick_next_roller_type(), config.roller_spawn_x)
	_wave_remaining -= 1
	_spawn_timer = config.spawn_interval(_elapsed, _wave_remaining > 0, _rng)


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

	var built: Dictionary = _meshes.build_roller_mesh(roller_type, radius, 9.0)
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


func _input(event: InputEvent) -> void:
	var action: int
	var control: Vector2i
	if event is InputEventKey:
		if event.echo:
			return
		match event.keycode:
			KEY_S, KEY_DOWN: action = 1
			KEY_SPACE, KEY_W, KEY_UP: action = 2
			_: return
		control = Vector2i(-1, event.keycode)
	elif event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_B: action = 1
			JOY_BUTTON_A: action = 2
			_: return
		control = Vector2i(event.device, event.button_index)
	else:
		return

	if not event.is_pressed():
		_release_control(control)
		return
	var already_held := action in _held_controls.values()
	_held_controls[control] = action
	if not already_held:
		_dispatch_action(action)


func _release_control(control: Vector2i) -> void:
	var was_crouch := int(_held_controls.get(control, 0)) == 1
	_held_controls.erase(control)
	if was_crouch and not 1 in _held_controls.values():
		_dispatch_action(RELEASE_CROUCH)


func _dispatch_action(action: int) -> void:
	if _countdown > 0 or _match_ended or _players.is_empty():
		return
	if _hosted_in_official_game and not multiplayer.is_server():
		submit_action.rpc_id(1, action)
	else:
		var peer := multiplayer.get_unique_id() if _hosted_in_official_game else 1
		_apply_input(peer, action)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		for control in _held_controls.keys():
			if control.x == device:
				_release_control(control)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for control in _held_controls.keys():
			_release_control(control)


@rpc("any_peer", "call_remote", "reliable")
func submit_action(pressed: int) -> void:
	if multiplayer.is_server() and _countdown <= 0 and not _match_ended:
		_apply_input(multiplayer.get_remote_sender_id(), pressed)


func _apply_input(peer: int, pressed: int) -> void:
	for p in _players:
		if p.network_id == peer:
			_begin_action(p, pressed)
			return


func _begin_action(p: Dictionary, pressed: int) -> void:
	if pressed == RELEASE_CROUCH:
		if p.crouching:
			p.crouching = false
			p.crouch_remaining = 0.0
			p.crouch_ready_in = config.crouch_recovery
		return
	if not p.alive or p.jumping or p.crouch_ready_in > 0 or p.recovery_timer > 0:
		return
	if pressed & 2:
		p.jumping = true
		p.jump_timer = 0.0
	elif pressed & 1:
		p.crouching = true
		p.crouch_remaining = config.crouch_duration
		p.crouch_ready_in = config.crouch_duration + config.crouch_recovery


func _tick_crouch(p: Dictionary, delta: float) -> void:
	p.crouch_remaining = maxf(0.0, p.crouch_remaining - delta)
	p.crouch_ready_in = maxf(0.0, p.crouch_ready_in - delta)
	p.crouching = p.crouch_remaining > 0


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

		var is_ai_seat: bool = (not _hosted_in_official_game and int(p["id"]) > 0)
		if not is_ai_seat and _hosted_in_official_game and multiplayer.is_server():
			var nid: int = int(p["network_id"])
			if nid != 1 and not multiplayer.get_peers().has(nid):
				is_ai_seat = true
		if is_ai_seat:
			var ai := _compute_ai_action(p)
			var held := int(ai.crouch) | (int(ai.jump) << 1)
			_begin_action(p, held & ~int(p.ai_held))
			p.ai_held = held
		_tick_crouch(p, delta)
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


# Only the host evaluates collisions. Each packet contains all visible rollers
# so a lost spawn or removal is repaired by the next packet.
func _send_snapshot() -> void:
	var poses := PackedFloat32Array()
	for p in _players:
		poses.append_array(PackedFloat32Array([p.x, p.y, int(p.crouching), int(p.jumping),
			int(p.alive), p.dodges, p.hit_flash, p.sink_progress]))
	var rollers := PackedFloat32Array()
	for r in _rollers:
		rollers.append_array(PackedFloat32Array([r.id, int(r.type == "gold"), r.x]))
	_show_snapshot.rpc(_elapsed, poses, rollers)


@rpc("authority", "call_remote", "unreliable_ordered")
func _show_snapshot(elapsed: float, poses: PackedFloat32Array, rollers: PackedFloat32Array) -> void:
	if _match_ended or poses.size() != _players.size() * 8:
		return
	_elapsed = elapsed
	_time_left = maxf(0, config.round_duration - elapsed)
	for i in range(_players.size()):
		var p := _players[i]
		var offset := i * 8
		p.x = poses[offset]
		p.y = poses[offset + 1]
		p.crouching = bool(poses[offset + 2])
		p.jumping = bool(poses[offset + 3])
		if p.alive and not bool(poses[offset + 4]):
			_eliminate_player(p)
		p.dodges = int(poses[offset + 5])
		var new_flash: float = poses[offset + 6]
		if new_flash > 0.85 and float(p.hit_flash) <= 0.4:
			_play_hit_feedback(p)
		p.hit_flash = new_flash
		_update_player_visuals(p)
		if not p.alive:
			p.node.position.y = -poses[offset + 7] * 1.6
			p.node.rotation_degrees.z = poses[offset + 7] * 48.0
	var existing := {}
	for r in _rollers:
		existing[r.id] = r
	for offset in range(0, rollers.size(), 3):
		var id := int(rollers[offset])
		var r: Dictionary
		if existing.has(id):
			r = existing[id]
			existing.erase(id)
		else:
			r = _spawn_roller("gold" if rollers[offset + 1] else "silver", rollers[offset + 2])
			r.id = id
		r.x = rollers[offset + 2]
		r.node.position.x = r.x
	for r in existing.values():
		_rollers.erase(r)
		r.node.queue_free()


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

		if not _hosted_in_official_game or multiplayer.is_server():
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


func _play_hit_feedback(p: Dictionary) -> void:
	if not _is_self_test:
		_camera_shake = maxf(_camera_shake, 0.55)
	var pos := Vector3(float(p["x"]), 0.02, float(p["z"]))
	_spawn_impact_decal(pos, 1.0)
	if not _spawn_vanilla_effect("res://prefabs/managed_effects/hit_blood.tscn", Vector3(pos.x, 0.72, pos.z), 0.38, 1.2):
		_spawn_burst(Vector3(pos.x, 0.75, pos.z), Color(0.42, 0.02, 0.01), 6)
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null and ap.has_animation(&"mp_mod/shoved"):
		ap.play(&"mp_mod/shoved")
	if _sfx_shove != null and not _is_self_test:
		_sfx_shove.play()


func _apply_knockback_to_player(p: Dictionary) -> void:
	p["knockback_remaining"] = float(p["knockback_remaining"]) + config.knockback_distance
	p["knockback_timer"] = config.knockback_duration
	p["knockback_cooldown"] = config.knockback_cooldown
	p["hit_flash"] = 1.0
	_play_hit_feedback(p)

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
	if not _is_self_test:
		_camera_shake = 1.0
	var lbl: Label3D = p["label"]
	lbl.visible = false
	var pnode = p.get("node", null)
	if pnode is Node:
		(pnode as Node).set_meta(&"mpm_alive", false)
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null and ap.has_animation(&"mp_mod/falling"):
		ap.play(&"mp_mod/falling")
	if _sfx_fall != null and not _is_self_test:
		_sfx_fall.play()
	_spawn_impact_decal(Vector3(config.stage_left_lava_x + 0.35, 0.02, float(p["z"])), 1.35)
	var pit_pos := Vector3(config.stage_left_lava_x - 0.35, 0.35, float(p["z"]))
	if not _spawn_vanilla_effect("res://prefabs/managed_effects/bloodmist_01.tscn", pit_pos, 0.42, 3.2):
		_spawn_burst(pit_pos, Color(0.38, 0.02, 0.01), 14)


func _warmup_fx_pipelines() -> void:
	if _is_self_test or not is_inside_tree() or _fx_layer == null:
		return
	var warmup_nodes: Array[Node] = []
	var hidden_pos := Vector3(0.0, -3.5, 0.0)
	if _blood_tex_02 != null or _blood_tex_01 != null:
		var dec := Decal.new()
		dec.size = Vector3(0.05, 0.05, 0.05)
		dec.texture_albedo = _blood_tex_02 if _blood_tex_02 != null else _blood_tex_01
		dec.modulate = Color(0.3809, 0.0189, 0.0, 1.0)
		dec.position = hidden_pos
		_fx_layer.add_child(dec)
		warmup_nodes.append(dec)
	for packed in [_fx_hit_blood_scene, _fx_bloodmist_scene]:
		if packed == null:
			continue
		var inst = packed.instantiate()
		if inst is Node3D:
			inst.set_script(null)
			var n3 := inst as Node3D
			n3.position = hidden_pos
			n3.scale = Vector3(0.001, 0.001, 0.001)
			_fx_layer.add_child(n3)
			for child in n3.get_children():
				if child is GPUParticles3D:
					var gp := child as GPUParticles3D
					gp.one_shot = true
					gp.emitting = true
			warmup_nodes.append(n3)
		elif inst is Node:
			(inst as Node).queue_free()
	if warmup_nodes.is_empty():
		return
	var timer := get_tree().create_timer(0.25)
	timer.timeout.connect(func():
		for n in warmup_nodes:
			if is_instance_valid(n):
				n.queue_free()
	)


func _spawn_vanilla_effect(scene_path: String, origin: Vector3, eff_scale: float, lifetime: float) -> bool:
	if _is_self_test:
		return true
	var packed: PackedScene = null
	if scene_path.ends_with("hit_blood.tscn"):
		packed = _fx_hit_blood_scene
	elif scene_path.ends_with("bloodmist_01.tscn"):
		packed = _fx_bloodmist_scene
	if packed == null:
		var loaded = _meshes.load_optional(scene_path)
		if loaded is PackedScene:
			packed = loaded as PackedScene
	if packed == null:
		return false
	var inst = packed.instantiate()
	if not (inst is Node3D):
		if inst is Node:
			(inst as Node).queue_free()
		return false
	inst.set_script(null)
	var node3d := inst as Node3D
	node3d.position = origin
	node3d.scale = Vector3.ONE * eff_scale
	_fx_layer.add_child(node3d)
	for child in node3d.get_children():
		if child is GPUParticles3D:
			var gp := child as GPUParticles3D
			gp.one_shot = true
			gp.restart()
			gp.emitting = true
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(func():
		if is_instance_valid(node3d):
			node3d.queue_free()
	)
	return true


func _spawn_impact_decal(pos: Vector3, scale_mul: float = 1.0) -> void:
	if _decals.size() >= 28:
		var old: Node3D = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var blood_tex: Texture2D = _blood_tex_02 if (_rng.randf() < 0.7 and _blood_tex_02 != null) else _blood_tex_01
	if blood_tex == null:
		var tex_path := "res://textures/decals/blood decals/blood_splat_02.png" if _rng.randf() < 0.7 else "res://textures/decals/blood decals/blood_splat_01.png"
		var loaded = _meshes.load_optional(tex_path)
		if loaded is Texture2D:
			blood_tex = loaded as Texture2D
	if blood_tex != null:
		var dec := Decal.new()
		var sz := _rng.randf_range(1.25, 1.75) * scale_mul
		dec.size = Vector3(sz, 0.42, sz)
		dec.texture_albedo = blood_tex
		dec.modulate = Color(0.3809, 0.0189, 0.0, 1.0)
		dec.upper_fade = 0.3
		dec.lower_fade = 0.3
		dec.position = Vector3(pos.x, 0.04, pos.z)
		dec.rotation.y = _rng.randf_range(0.0, TAU)
		_fx_layer.add_child(dec)
		_decals.append(dec)
	else:
		var mark := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34 * scale_mul
		cm.bottom_radius = 0.36 * scale_mul
		cm.height = 0.015
		mark.mesh = cm
		mark.material_override = _meshes.make_toon_mat(Color(0.38, 0.02, 0.01, 0.80), 0.9, 0.0)
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


func _check_round_end() -> void:
	var alive_count: int = 0
	for p in _players:
		if p["alive"]:
			alive_count += 1

	if alive_count == 0:
		_finish_round("全員落入粉碎熔爐淘汰（提前結束）")
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
		var bonus: int = config.bonus_for_rank(rank, sorted.size())
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

	var rankings: Array[Dictionary] = _compute_rankings()
	var finalized_scores: Dictionary = {}
	for r in rankings:
		var nid: int = int(r["network_id"])
		var bonus: int = int(r["bonus"])
		finalized_scores[nid] = bonus

	if _hosted_in_official_game and not _is_self_test:
		show_round_result.rpc(rankings, reason)
	else:
		show_round_result(rankings, reason)
	if _hosted_in_official_game:
		round_finished.emit(finalized_scores)


@rpc("authority", "call_local", "reliable")
func show_round_result(rankings: Array, reason: String) -> void:
	_match_ended = true
	_countdown_label.hide()
	if not _hosted_in_official_game:
		_populate_results_ui(rankings, reason)


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

	_you_marker = YouMarkerOverlay.new()
	_you_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_you_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_you_marker.marker_font = term_font
	_you_marker.marker_text = _loc_or("LOC_CONTROL_YOU", "YOU")
	_you_marker.visible = false
	root_ctrl.add_child(_you_marker)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 68)
	_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown_label.add_theme_constant_override("outline_size", 8)
	root_ctrl.add_child(_countdown_label)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.hide()

	_go_label = Label.new()
	_go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_go_label.add_theme_font_size_override("font_size", 68)
	_go_label.add_theme_color_override("font_color", Color.WHITE)
	_go_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_go_label.add_theme_constant_override("outline_size", 8)
	root_ctrl.add_child(_go_label)
	_go_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_go_label.hide()

	_round_banner = Control.new()
	_round_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_round_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_banner.visible = false
	root_ctrl.add_child(_round_banner)

	var banner_bg := ColorRect.new()
	banner_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	_round_banner.add_child(banner_bg)

	var grunge_tex = _meshes.load_optional("res://minigames/intermission_new/textures/intermission grunge overlay4.png")
	if grunge_tex is Texture2D:
		var grunge := TextureRect.new()
		grunge.set_anchors_preset(Control.PRESET_FULL_RECT)
		grunge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grunge.texture = grunge_tex
		grunge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grunge.stretch_mode = TextureRect.STRETCH_SCALE
		var g_mat := CanvasItemMaterial.new()
		g_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		grunge.material = g_mat
		grunge.modulate = Color(1.0, 1.0, 1.0, 0.25)
		_round_banner.add_child(grunge)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_vbox.add_theme_constant_override("separation", 18)
	banner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_banner.add_child(banner_vbox)

	_round_title_label = Label.new()
	_round_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_title_label.add_theme_font_size_override("font_size", 60)
	_round_title_label.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	banner_vbox.add_child(_round_title_label)

	_round_tagline_label = Label.new()
	_round_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_tagline_label.add_theme_font_size_override("font_size", 24)
	_round_tagline_label.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	_round_tagline_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	banner_vbox.add_child(_round_tagline_label)

	if _hosted_in_official_game:
		return

	# --- End-of-Round Settlement Overlay (CRT Terminal) ---
	_results_panel = _make_panel_box(Color(0.03, 0.04, 0.03, 0.96))
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
	_results_title.text = "ROUND SUMMARY"
	_results_title.add_theme_font_size_override("font_size", 28)
	_results_title.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	r_vbox.add_child(_results_title)

	_results_subtitle = Label.new()
	_results_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_subtitle.add_theme_font_size_override("font_size", 16)
	_results_subtitle.add_theme_color_override("font_color", Color(0.76, 0.86, 0.74))
	r_vbox.add_child(_results_subtitle)

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(r_scroll)

	_results_rows = VBoxContainer.new()
	_results_rows.add_theme_constant_override("separation", 6)
	_results_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_scroll.add_child(_results_rows)



func _make_panel_box(bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	st.corner_radius_top_left = 0
	st.corner_radius_top_right = 0
	st.corner_radius_bottom_left = 0
	st.corner_radius_bottom_right = 0
	st.border_color = Color(0.53, 0.83, 0.50, 0.85)
	st.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", st)
	return panel


func _populate_results_ui(rankings: Array, reason: String) -> void:
	for child in _results_rows.get_children():
		child.queue_free()

	_results_title.text = "ROUND SUMMARY // 本局排名"
	_results_subtitle.text = reason
	for r in rankings:
		var is_alive := bool(r["alive"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var rk := Label.new()
		rk.custom_minimum_size.x = 46
		rk.text = "#%d" % int(r["rank"])
		rk.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
		rk.add_theme_font_size_override("font_size", 17)
		row.add_child(rk)

		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text = str(r["nickname"]) + ("  [存活]" if is_alive else "  [淘汰]")
		nm.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90) if is_alive else Color(0.66, 0.44, 0.44))
		nm.add_theme_font_size_override("font_size", 17)
		row.add_child(nm)

		var dg := Label.new()
		dg.custom_minimum_size.x = 110
		dg.text = "躲避 %d 次" % int(r["dodges"])
		dg.add_theme_color_override("font_color", Color(0.84, 0.90, 0.82))
		dg.add_theme_font_size_override("font_size", 17)
		row.add_child(dg)

		var bn := Label.new()
		bn.custom_minimum_size.x = 155
		bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bn.text = "原始分 +%d" % int(r["bonus"])
		bn.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
		bn.add_theme_font_size_override("font_size", 17)
		row.add_child(bn)

		_results_rows.add_child(row)

	_results_panel.visible = true


var _tests_failed: bool = false


func _assert_true(cond: bool, msg: String) -> bool:
	if not cond:
		_tests_failed = true
		push_error("SELF_TEST_FAILED: " + msg)
		get_tree().quit(1)
		return false
	return true


func _test_wave_pacing() -> bool:
	_start_new_round()
	_players.clear() # Follow an unobstructed lane for a full round.
	_rng.seed = 451
	const STEP := 1.0 / 60.0
	var early_double_frames := 0
	var late_double_frames := 0
	var late_triple_frames := 0
	var previous_arrival := -10.0
	var minimum_gap := INF
	var camera := get_viewport().get_camera_3d()
	for frame in range(3000):
		_elapsed = (frame + 1) * STEP
		_step_spawner(STEP)
		_step_rollers(STEP)
		var visible_rollers := 0
		var approaching := 0
		for roller in _rollers:
			if camera.is_position_in_frustum(Vector3(roller.x, 1, 0)):
				visible_rollers += 1
				if roller.x >= config.player_spawn_x:
					approaching += 1
			if roller.x < config.player_spawn_x and not roller.has("arrival_measured"):
				minimum_gap = minf(minimum_gap, _elapsed - previous_arrival)
				previous_arrival = _elapsed
				roller.arrival_measured = true
		if _elapsed <= 10 and approaching >= 2:
			early_double_frames += 1
		if _elapsed > 40 and visible_rollers >= 2:
			late_double_frames += 1
			if visible_rollers >= 3:
				late_triple_frames += 1
	for x in [config.stage_left_lava_x, config.player_spawn_x]:
		for z in [-3.75, 3.75]:
			if not _assert_true(camera.is_position_in_frustum(Vector3(x, 1.32, z)), "Players must stay visible up to the lava edge"):
				return false
	print("WAVE_PACING early double frames=%d/600, late doubles=%d/600, late triples=%d/600, min arrival gap=%.3f" % [early_double_frames, late_double_frames, late_triple_frames, minimum_gap])
	return _assert_true(early_double_frames == 0 and late_double_frames > 300 and late_triple_frames >= 15 and minimum_gap >= config.safe_interval_floor(), "Late waves must be readable and allow consecutive jumps")


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

	config.player_spawn_x = 2.6
	_start_new_round()
	for p in _players:
		if not _assert_true(is_equal_approx(float(p["x"]), 2.6), "Configured player_spawn_x must move all player spawns"):
			return
	var sl_node := _scene_props.get("starting_line", null) as Node3D
	if not _assert_true(sl_node != null and is_equal_approx(sl_node.position.x, 2.6), "Stage StartingLine mesh must sync with configured player_spawn_x"):
		return

	# Check large preview rosters.
	config.max_players = 16
	_start_new_round()
	if not _assert_true(_players.size() == 16, "Must spawn 16 players when max_players=16"):
		return
	for p16 in _players:
		if not _assert_true(is_equal_approx(float(p16["x"]), config.player_spawn_x), "All 16 players must spawn on exact same starting line X"):
			return
	config.max_players = 8
	config.player_spawn_x = 1.6

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
	if not _assert_true(not _results_panel.visible and not _countdown_label.visible, "Play must leave the stage unobstructed"):
		return

	_check_round_end()
	if not _assert_true(_match_ended, "Match must end immediately when all players are eliminated"):
		return

	# 4. Raw points are based on the actual roster and shared rank.
	var ranks := _compute_rankings()
	if not _assert_true(ranks.size() == 2, "Rankings must include both players"):
		return
	if not _assert_true(int(ranks[0]["id"]) == 1 and int(ranks[0]["bonus"]) == 2, "First of two earns 2 raw points"):
		return
	if not _assert_true(int(ranks[1]["id"]) == 0 and int(ranks[1]["bonus"]) == 1, "Second of two earns 1 raw point"):
		return
	_players[0].dodges = _players[1].dodges
	var tied := _compute_rankings()
	if not _assert_true(tied[0].bonus == 2 and tied[1].bonus == 2, "Tied players share raw points"):
		return

	if not _test_wave_pacing():
		return

	_hosted_in_official_game = true
	var intro_camera := Camera3D.new()
	add_child(intro_camera)
	intro_camera.make_current()
	start_round([{"id":0, "network_id":1, "nickname":"Host"}, {"id":1, "network_id":42, "nickname":"Guest"}])
	if not _assert_true(get_viewport().get_camera_3d() == $StageCamera, "Countdown must take the camera back from the intro"):
		return
	intro_camera.queue_free()
	for player in _players:
		if not _assert_true(player.visual.position.y > 0 and player.node.position.y == 0, "Entrance raises each visual above its seat"):
			return
	_countdown -= ENTRANCE_SECONDS
	_update_entrance()
	for player in _players:
		if not _assert_true(is_zero_approx(player.visual.position.y), "All players land before GO"):
			return
	var tap := InputEventKey.new()
	tap.keycode = KEY_S
	tap.pressed = true
	_input(tap)
	_countdown = 0
	_input(tap)
	if not _assert_true(not _players[0].crouching, "Holding through countdown must not trigger"):
		return
	tap.pressed = false
	_input(tap)
	tap.pressed = true
	_input(tap)
	if not _assert_true(_players[0].crouching, "Press starts crouching immediately"):
		return
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	_input(down)
	tap.pressed = false
	_input(tap)
	if not _assert_true(_players[0].crouching, "Second held crouch key keeps player crouched"):
		return
	down.pressed = false
	_input(down)
	if not _assert_true(not _players[0].crouching, "Final key release ends crouch immediately"):
		return
	_tick_crouch(_players[0], config.crouch_recovery)
	tap.pressed = true
	_input(tap)
	if not _assert_true(_players[0].crouching, "New press works after short recovery"):
		return
	_tick_crouch(_players[0], config.crouch_duration + config.crouch_recovery)
	tap.pressed = true
	tap.echo = true
	_input(tap)
	if not _assert_true(not _players[0].crouching, "Keyboard repeat must not retrigger"):
		return
	_apply_input(42, 1)
	if not _assert_true(_players[1].crouching and not _players[0].crouching, "Only sender crouches"):
		return
	_tick_crouch(_players[1], 0.74)
	if not _assert_true(_players[1].crouching, "Crouch lasts 0.75 seconds"):
		return
	_tick_crouch(_players[1], 0.02)
	if not _assert_true(not _players[1].crouching, "Held crouch expires"):
		return
	var captured := {}
	round_finished.connect(func(scores: Dictionary): captured.merge(scores))
	_players[0].dodges = 7
	_players[1].dodges = 3
	_finish_round("test")
	if not _assert_true(captured == {1:2, 42:1}, "Scores keyed by real peers"):
		return

	if not _tests_failed:
		print("SELF_TEST_PASSED")
		get_tree().quit(0)
