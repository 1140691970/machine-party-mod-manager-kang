extends Node3D

## Bubble Blitz (泡泡爆破) — 3D Top-Down Party Minigame Stage.
## Reuses authentic Machine Party worker rigs, cosmetics, industrial textures,
## Terminal F4 CRT monitor/UI, vignette+posterization post-FX, gore FX, and SFX.

signal round_finished(scores: Dictionary)

const CONFIG_RES := "res://mods_bubble_blitz/config.gd"
const MESHES_RES := "res://mods_bubble_blitz/arena_meshes.gd"

var C = null
var M = null

var _standalone_mode: bool = false
var _is_server_sim: bool = true
var _round_active: bool = false
var _round_ended: bool = false
var _intro_timer: float = 0.0
var _time_remaining: float = 75.0
var _elapsed_time: float = 0.0
var _crusher_timer: float = 0.0
var _crusher_index: int = 0
var _sync_accum: float = 0.0
var _next_bubble_id: int = 1
var _next_item_id: int = 1
var _last_countdown_sec: int = 4
var _last_beep_sec: int = -1
var _rng := RandomNumberGenerator.new()

var _map_width: int = 11
var _map_height: int = 9
var _theme_id: int = 0
var _map_seed: int = 0
var _tiles: Array = []
var _conveyors: Dictionary = {}
var _crush_order: Array = []

var _players: Dictionary = {} # network_id -> Dictionary
var _bubbles: Dictionary = {} # bubble_id -> Dictionary
var _blasts: Array = [] # Array of Dictionary
var _items: Dictionary = {} # item_id -> Dictionary
var _client_inputs: Dictionary = {} # network_id -> { "dir": Vector2, "drop": bool }

var _arena_root: Node3D = null
var _tile_nodes: Dictionary = {} # Vector2i -> Node3D
var _bubble_nodes: Dictionary = {} # bubble_id -> Node3D
var _item_nodes: Dictionary = {} # item_id -> Node3D
var _blast_root: Node3D = null
var _fx_root: Node3D = null
var _player_root: Node3D = null
var _camera: Camera3D = null

var _monitor_timer: Label3D = null
var _monitor_theme: Label3D = null
var _shader_layer: CanvasLayer = null
var _hud_layer: CanvasLayer = null
var _banner_label: Label = null
var _kill_feed_label: Label = null
var _kill_feed_timer: float = 0.0
var _stats_panel: PanelContainer = null
var _stats_label: Label = null
var _local_net_id: int = 1

var _sfx_shove: AudioStreamPlayer = null
var _sfx_elim: AudioStreamPlayer = null
var _sfx_explosion: AudioStreamPlayer = null
var _sfx_place: AudioStreamPlayer = null
var _sfx_pickup: AudioStreamPlayer = null
var _sfx_countdown: AudioStreamPlayer = null
var _sfx_ding: AudioStreamPlayer = null
var _sfx_beep: AudioStreamPlayer = null
var _ambience_player: AudioStreamPlayer = null
var _fx_hit_blood_scene: PackedScene = null
var _fx_bloodmist_scene: PackedScene = null
var _fx_explosion_scene: PackedScene = null
var _fx_dustplume_scene: PackedScene = null
var _explosion_mark_tex: Texture2D = null
var _blood_tex_01: Texture2D = null
var _blood_tex_02: Texture2D = null

const POOL_EXPLOSION_FX := 4
const POOL_HIT_BLOOD_FX := 3
const POOL_BLOODMIST_FX := 2
const POOL_EXPLOSION_DECALS := 16
const POOL_BLOOD_DECALS := 12
const POOL_BLAST_LIGHTS := 2
const POOL_BLAST_CENTER_CELLS := 12
const POOL_BLAST_ARM_CELLS := 48
const EXPLOSION_SFX_MIN_INTERVAL_MS := 45
const CHAIN_DETONATE_DELAY_SEC := 0.05

var _explosion_fx_pool: Array[Dictionary] = []
var _hit_blood_fx_pool: Array[Dictionary] = []
var _bloodmist_fx_pool: Array[Dictionary] = []
var _explosion_fx_cursor: int = 0
var _hit_blood_fx_cursor: int = 0
var _bloodmist_fx_cursor: int = 0

var _explosion_decals: Array[Decal] = []
var _blood_decals: Array[Decal] = []
var _explosion_decal_cursor: int = 0
var _blood_decal_cursor: int = 0

var _blast_light_pool: Array[Dictionary] = []
var _blast_light_cursor: int = 0

var _blast_center_pool: Array[Node3D] = []
var _blast_arm_pool: Array[Node3D] = []
var _active_blast_visuals: Dictionary = {} # Vector2i -> { "node": Node3D, "is_center": bool, "timer": float }

var _last_explosion_sfx_ms: int = 0
var _prev_drop_pressed: bool = false
var _is_self_test: bool = false

var _screenshot_path: String = ""
var _screenshot_frames: int = 0


func _load_helpers() -> void:
	if C == null:
		if ResourceLoader.exists(CONFIG_RES):
			C = ResourceLoader.load(CONFIG_RES)
		else:
			C = load("res://config.gd")
	if M == null:
		if ResourceLoader.exists(MESHES_RES):
			M = ResourceLoader.load(MESHES_RES)
		else:
			M = load("res://arena_meshes.gd")
	if M != null:
		M.ensure_game_pck_mounted()


func _ready() -> void:
	_load_helpers()
	_setup_environment()
	_setup_post_fx()
	_setup_vanilla_audio_and_fx()
	_setup_hud()

	var args: Array = Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	for raw_a in args:
		var a: String = str(raw_a)
		if a == "--self-test":
			_is_self_test = true
			_run_self_test()
			return
		if a.begins_with("--capture-screenshot="):
			_screenshot_path = a.substr("--capture-screenshot=".length())

	_standalone_mode = (get_parent() == get_tree().root)
	if _standalone_mode:
		_start_standalone_preview()


func _setup_environment() -> void:
	# Authentic Machine Party warm low-saturation industrial atmosphere.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.31, 0.28)
	env.ambient_light_energy = 0.72
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.06
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.86
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.18

	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-56.0, 22.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-32.0, -145.0, 0.0)
	fill.light_color = Color(0.75, 0.86, 1.0)
	fill.light_energy = 0.40
	add_child(fill)

	_camera = Camera3D.new()
	_camera.name = "ArenaCamera"
	_camera.fov = 44.0
	_camera.current = true
	add_child(_camera)

	_arena_root = Node3D.new()
	_arena_root.name = "ArenaRoot"
	add_child(_arena_root)

	_blast_root = Node3D.new()
	_blast_root.name = "BlastRoot"
	add_child(_blast_root)

	_fx_root = Node3D.new()
	_fx_root.name = "FxRoot"
	add_child(_fx_root)

	_player_root = Node3D.new()
	_player_root.name = "PlayerRoot"
	add_child(_player_root)


func _setup_post_fx() -> void:
	# Reuse authentic Machine Party vignette + 8-step posterization shaders.
	var post_shader = M.load_optional("res://shaders/posterization.gdshader")
	var vig_shader = M.load_optional("res://shaders/vignette.gdshader")
	if not (post_shader is Shader or vig_shader is Shader):
		return

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
		vig_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vig_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_root.add_child(vig_holder)

		var vig_copy := BackBufferCopy.new()
		vig_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		vig_holder.add_child(vig_copy)

		var vig_rect := ColorRect.new()
		vig_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vm := ShaderMaterial.new()
		vm.shader = vig_shader as Shader
		vm.set_shader_parameter("radius", 0.92)
		vm.set_shader_parameter("softness", 0.40)
		vm.set_shader_parameter("intensity", 1.75)
		vm.set_shader_parameter("contrast", 1.52)
		vm.set_shader_parameter("vignette_color", Color(0.0, 0.0, 0.0, 1.0))
		vig_rect.material = vm
		vig_holder.add_child(vig_rect)

	if post_shader is Shader:
		var post_holder := Control.new()
		post_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		post_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_root.add_child(post_holder)

		var post_copy := BackBufferCopy.new()
		post_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		post_holder.add_child(post_copy)

		var post_rect := ColorRect.new()
		post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = post_shader as Shader
		pm.set_shader_parameter("SCREEN_WIDTH", 1920.0)
		pm.set_shader_parameter("RED_COMPONENT", 8.0)
		pm.set_shader_parameter("GREEN_COMPONENT", 8.0)
		pm.set_shader_parameter("BLUE_COMPONENT", 8.0)
		post_rect.material = pm
		post_holder.add_child(post_rect)


func _setup_vanilla_audio_and_fx() -> void:
	_sfx_shove = _make_audio_player("res://audio/unique/disco dodge/dd shove.ogg", -4.0)
	_sfx_elim = _make_audio_player("res://audio/unique/disco dodge/dd fall scream impact.ogg", -2.0)
	_sfx_explosion = _make_audio_player("res://audio/sfx/bad_explosion.ogg", -5.0)
	_sfx_place = _make_audio_player("res://audio/unique/exploding collar race/mine_detected.ogg", -6.0)
	_sfx_pickup = _make_audio_player("res://audio/sfx/manufacture_gun_pickup_gear.ogg", -4.0)
	_sfx_countdown = _make_audio_player("res://audio/sfx/countdown_mechanism2.ogg", -3.0)
	_sfx_ding = _make_audio_player("res://audio/sfx/airplane ding.ogg", -2.0)
	_sfx_beep = _make_audio_player("res://audio/sfx/ekg_beep.ogg", -5.0)
	_ambience_player = _make_audio_player("res://audio/unique/dvd roomba/dvd roomba ambience.ogg", -14.0)

	var hit_scene = M.load_optional("res://prefabs/managed_effects/hit_blood.tscn")
	if hit_scene is PackedScene:
		_fx_hit_blood_scene = hit_scene as PackedScene
	var mist_scene = M.load_optional("res://prefabs/managed_effects/bloodmist_01.tscn")
	if mist_scene is PackedScene:
		_fx_bloodmist_scene = mist_scene as PackedScene
	var exp_scene = M.load_optional("res://prefabs/managed_effects/mine_explosion.tscn")
	if exp_scene is PackedScene:
		_fx_explosion_scene = exp_scene as PackedScene
	var dust_scene = M.load_optional("res://prefabs/managed_effects/dustplume.tscn")
	if dust_scene is PackedScene:
		_fx_dustplume_scene = dust_scene as PackedScene
	var mark_tex = M.load_optional("res://textures/decals/explosion_mark.png")
	if mark_tex is Texture2D:
		_explosion_mark_tex = mark_tex as Texture2D
	var bt1 = M.load_optional("res://textures/decals/blood decals/blood_splat_01.png")
	if bt1 is Texture2D:
		_blood_tex_01 = bt1 as Texture2D
	var bt2 = M.load_optional("res://textures/decals/blood decals/blood_splat_02.png")
	if bt2 is Texture2D:
		_blood_tex_02 = bt2 as Texture2D


func _make_audio_player(res_path: String, volume_db: float) -> AudioStreamPlayer:
	var stream = M.load_optional(res_path)
	if not (stream is AudioStream):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream as AudioStream
	p.volume_db = volume_db
	add_child(p)
	return p


func _setup_hud() -> void:
	# Clean vanilla CRT-style overlay: timer & theme live on the 3D back-wall CRT monitor.
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "BubbleBlitzHUD"
	_hud_layer.layer = 5
	add_child(_hud_layer)

	var hud_root := Control.new()
	hud_root.name = "HudRoot"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(hud_root)

	var term_font: Font = M.load_terminal_font()

	_banner_label = Label.new()
	_banner_label.anchor_left = 0.1
	_banner_label.anchor_right = 0.9
	_banner_label.anchor_top = 0.36
	_banner_label.anchor_bottom = 0.56
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 74)
	_banner_label.add_theme_color_override("font_color", Color(0.68, 1.0, 0.68))
	_banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner_label.add_theme_constant_override("outline_size", 14)
	if term_font != null:
		_banner_label.add_theme_font_override("font", term_font)
	hud_root.add_child(_banner_label)

	_kill_feed_label = Label.new()
	_kill_feed_label.anchor_left = 0.1
	_kill_feed_label.anchor_right = 0.9
	_kill_feed_label.anchor_top = 0.80
	_kill_feed_label.anchor_bottom = 0.87
	_kill_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_feed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kill_feed_label.add_theme_font_size_override("font_size", 22)
	_kill_feed_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.62))
	_kill_feed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_kill_feed_label.add_theme_constant_override("outline_size", 6)
	if term_font != null:
		_kill_feed_label.add_theme_font_override("font", term_font)
	hud_root.add_child(_kill_feed_label)

	# Local-player-only compact CRT status bar, strictly centered across all resolutions & UI scales.
	var stats_center := CenterContainer.new()
	stats_center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stats_center.offset_top = -48.0
	stats_center.offset_bottom = -10.0
	stats_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(stats_center)

	_stats_panel = PanelContainer.new()
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.04, 0.86)
	sb.border_color = Color(0.42, 0.88, 0.48, 0.90)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_stats_panel.add_theme_stylebox_override("panel", sb)
	stats_center.add_child(_stats_panel)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.add_theme_color_override("font_color", Color(0.76, 1.0, 0.76))
	_stats_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats_label.add_theme_constant_override("outline_size", 4)
	if term_font != null:
		_stats_label.add_theme_font_override("font", term_font)
	_stats_panel.add_child(_stats_label)


@rpc("authority", "call_local", "reliable")
func start_round(roster: Array) -> void:
	_load_helpers()
	_standalone_mode = false
	_is_server_sim = multiplayer.is_server()
	_local_net_id = multiplayer.get_unique_id()
	if _is_server_sim:
		_rng.randomize()
		var theme_id: int = _rng.randi_range(0, C.THEME_COUNT - 1)
		var seed_val: int = _rng.randi()
		_rpc_setup_match.rpc(theme_id, seed_val, roster)


@rpc("authority", "call_local", "reliable")
func _rpc_setup_match(theme_id: int, seed_val: int, roster: Array) -> void:
	_setup_match_local(theme_id, seed_val, roster, false)


func _start_standalone_preview() -> void:
	_is_server_sim = true
	_local_net_id = 1
	_rng.randomize()
	var theme_id: int = C.THEME_CONVEYOR if not _screenshot_path.is_empty() else _rng.randi_range(0, C.THEME_COUNT - 1)
	var seed_val: int = 20261120 if not _screenshot_path.is_empty() else _rng.randi()
	var roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "玩家 1 (你)", "customization": ["hard_hat", "sunglasses", "blue"], "is_ai": false},
		{"id": 1, "network_id": 2, "nickname": "發條阿紫", "customization": ["tophat", "", "purple"], "is_ai": true},
		{"id": 2, "network_id": 3, "nickname": "鍋爐綠醬", "customization": ["traffic_cone", "", "green"], "is_ai": true},
		{"id": 3, "network_id": 4, "nickname": "紅心活塞", "customization": ["beer_hat", "", "red"], "is_ai": true},
	]
	_setup_match_local(theme_id, seed_val, roster, true)
	if not _screenshot_path.is_empty():
		_stage_screenshot_action()


func _clear_arena() -> void:
	for child in _arena_root.get_children():
		child.queue_free()
	for child in _blast_root.get_children():
		child.queue_free()
	for child in _fx_root.get_children():
		child.queue_free()
	for child in _player_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_bubble_nodes.clear()
	_item_nodes.clear()
	_players.clear()
	_bubbles.clear()
	_blasts.clear()
	_items.clear()
	_explosion_fx_pool.clear()
	_hit_blood_fx_pool.clear()
	_bloodmist_fx_pool.clear()
	_explosion_fx_cursor = 0
	_hit_blood_fx_cursor = 0
	_bloodmist_fx_cursor = 0
	_explosion_decals.clear()
	_blood_decals.clear()
	_explosion_decal_cursor = 0
	_blood_decal_cursor = 0
	_blast_light_pool.clear()
	_blast_light_cursor = 0
	_blast_center_pool.clear()
	_blast_arm_pool.clear()
	_active_blast_visuals.clear()
	_client_inputs.clear()
	_prev_drop_pressed = false
	_monitor_timer = null
	_monitor_theme = null


func _setup_match_local(theme_id: int, seed_val: int, roster: Array, is_preview: bool) -> void:
	_clear_arena()
	_theme_id = theme_id
	_map_seed = seed_val
	_rng.seed = seed_val
	_round_ended = false
	_round_active = false
	_intro_timer = 0.0 if not _screenshot_path.is_empty() else 2.2
	_last_countdown_sec = 4
	_last_beep_sec = -1
	_time_remaining = C.ROUND_DURATION_SEC
	_elapsed_time = 0.0
	_crusher_timer = 0.0
	_crusher_index = 0
	_next_bubble_id = 1
	_next_item_id = 1

	var map_data: Dictionary = C.generate_map(roster.size(), theme_id, seed_val)
	_map_width = int(map_data["width"])
	_map_height = int(map_data["height"])
	_tiles = map_data["tiles"]
	_conveyors = map_data["conveyors"]
	_crush_order = map_data["crush_order"]
	var spawns: Array = map_data["spawns"]

	var theme_meta: Dictionary = C.THEME_META.get(theme_id, C.THEME_META[C.THEME_CLASSIC])
	var accent: Color = theme_meta.get("accent", Color(0.24, 0.78, 0.96))
	var crate_col: Color = theme_meta.get("crate", Color(0.68, 0.45, 0.22))

	var stage_pack: Dictionary = M.build_floor_and_backdrop(_map_width, _map_height, C.TILE_SIZE, theme_meta)
	_arena_root.add_child(stage_pack["root"])
	_monitor_timer = stage_pack["monitor_timer"] as Label3D
	_monitor_theme = stage_pack["monitor_theme"] as Label3D

	for cell_key in _conveyors.keys():
		var c: Vector2i = cell_key
		var dir: Vector2i = _conveyors[cell_key]
		var conv: Node3D = M.build_conveyor_tile(C.TILE_SIZE, dir, accent)
		conv.position = C.grid_to_world(c, _map_width, _map_height)
		_arena_root.add_child(conv)

	for y in range(_map_height):
		for x in range(_map_width):
			var t: int = int(_tiles[y][x])
			var c := Vector2i(x, y)
			if t == C.TILE_STEEL:
				var p: Node3D = M.build_steel_pillar(C.TILE_SIZE, accent)
				p.position = C.grid_to_world(c, _map_width, _map_height)
				_arena_root.add_child(p)
				_tile_nodes[c] = p
			elif t == C.TILE_CRATE or t == C.TILE_GOLD_CRATE:
				var cr: Node3D = M.build_crate(C.TILE_SIZE, t == C.TILE_GOLD_CRATE, crate_col)
				cr.position = C.grid_to_world(c, _map_width, _map_height)
				_arena_root.add_child(cr)
				_tile_nodes[c] = cr

	# Frame the full arena + back-wall CRT monitor.
	var span_z: float = float(_map_height) * C.TILE_SIZE
	var span_x: float = float(_map_width) * C.TILE_SIZE
	var cam_dist: float = maxf(span_z * 1.18, span_x * 0.80)
	_camera.position = Vector3(0.0, cam_dist * 0.84, cam_dist * 0.64)
	_camera.look_at(Vector3(0.0, 0.25, -0.45), Vector3.UP)

	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var net_id: int = int(entry.get("network_id", i + 1))
		var spawn_cell: Vector2i = spawns[i % spawns.size()]
		var world_pos: Vector3 = C.grid_to_world(spawn_cell, _map_width, _map_height)
		var cust_raw = entry.get("customization", [])
		var cust: Array = cust_raw if cust_raw is Array else []
		var is_local: bool = (net_id == _local_net_id)
		var nick: String = str(entry.get("nickname", "P%d" % (i + 1)))
		var char_pack: Dictionary = M.build_worker_character(i, net_id, nick, cust, is_local)
		var node: Node3D = char_pack["root"]
		node.position = world_pos
		_player_root.add_child(node)

		var is_bot_seat: bool = bool(entry.get("is_ai", false))
		if not is_preview and _is_server_sim:
			var peers: PackedInt32Array = multiplayer.get_peers()
			if net_id != 1 and not peers.has(net_id):
				is_bot_seat = true

		_players[net_id] = {
			"network_id": net_id,
			"nickname": nick,
			"color": char_pack["color"],
			"anim_player": char_pack["anim_player"],
			"is_ai": is_bot_seat,
			"pos": world_pos,
			"facing": Vector2(0.0, 1.0),
			"hp": C.MAX_HP,
			"alive": true,
			"trapped": false,
			"trapped_timer": 0.0,
			"invuln_timer": 0.0,
			"elim_time": 0.0,
			"max_bubbles": C.START_MAX_BUBBLES,
			"active_bubbles": 0,
			"power": C.START_POWER,
			"speed_level": C.START_SPEED_LEVEL,
			"has_kick": false,
			"has_needle": false,
			"pops": 0,
			"traps": 0,
			"last_attacker": 0,
			"pass_bubble_ids": {},
			"ai_cooldown": 0.0,
			"ai_dir": Vector2.ZERO,
			"node": node,
		}
		_update_player_hud_3d(_players[net_id])

	_init_fx_pools()
	_update_crt_monitor()
	_update_local_stats_hud()
	_banner_label.text = "3" if _intro_timer > 0.0 else ""
	_kill_feed_label.text = ""
	if _ambience_player != null and not _ambience_player.playing and _screenshot_path.is_empty():
		_ambience_player.play()
	if _intro_timer <= 0.0:
		_round_active = true


func _update_crt_monitor() -> void:
	if _monitor_timer != null:
		var sec: int = max(0, int(ceil(_time_remaining)))
		var mm: int = sec / 60
		var ss: int = sec % 60
		_monitor_timer.text = "%02d:%02d" % [mm, ss]
		if sec <= 10:
			var flash_on: bool = int(floor(Time.get_ticks_msec() * 0.006)) % 2 == 0
			_monitor_timer.modulate = Color(1.0, 0.28, 0.24) if flash_on else Color(1.0, 0.72, 0.68)
		elif _time_remaining <= C.HURRY_UP_REMAINING_SEC:
			_monitor_timer.modulate = Color(1.0, 0.76, 0.24)
		else:
			_monitor_timer.modulate = Color(0.68, 1.0, 0.68)
	if _monitor_theme != null:
		var phase_tag: String = "HURRY UP!" if _time_remaining <= C.HURRY_UP_REMAINING_SEC else C.theme_display_name(_theme_id)
		_monitor_theme.text = "BUBBLE BLITZ // " + phase_tag


func _update_local_stats_hud() -> void:
	if _stats_label == null or _stats_panel == null:
		return
	if not _players.has(_local_net_id):
		_stats_panel.visible = false
		return
	_stats_panel.visible = true
	var p: Dictionary = _players[_local_net_id]
	var loc: String = TranslationServer.get_locale().to_upper()
	var is_zhs: bool = loc.begins_with("ZHS")
	var is_zh: bool = loc.begins_with("ZH")

	var hp_str: String = ""
	if not bool(p["alive"]):
		hp_str = "已淘汰" if is_zhs else ("已淘汰" if is_zh else "OUT")
	elif bool(p["trapped"]):
		hp_str = "濒死中!" if is_zhs else ("瀕死中!" if is_zh else "CRITICAL!")
	else:
		for i in range(int(p["hp"])):
			hp_str += "♥"

	var avail_bombs: int = max(0, int(p["max_bubbles"]) - int(p["active_bubbles"]))
	var max_bombs: int = int(p["max_bubbles"])
	var rng_val: int = int(p["power"])
	var spd_lv: int = int(p["speed_level"]) + 1
	var kick_on: bool = bool(p["has_kick"])
	var needle_on: bool = bool(p["has_needle"])

	if is_zhs:
		_stats_label.text = "血量 %s | 炸弹 %d/%d | 范围 %d | 移速 Lv.%d | 踢弹:%s | 救命针:%s" % [
			hp_str, avail_bombs, max_bombs, rng_val, spd_lv,
			"有" if kick_on else "无",
			"有" if needle_on else "无",
		]
	elif is_zh:
		_stats_label.text = "血量 %s | 炸彈 %d/%d | 範圍 %d | 移速 Lv.%d | 踢彈:%s | 救命針:%s" % [
			hp_str, avail_bombs, max_bombs, rng_val, spd_lv,
			"有" if kick_on else "無",
			"有" if needle_on else "無",
		]
	else:
		_stats_label.text = "HP %s | BOMB %d/%d | RNG %d | SPD Lv.%d | KICK:%s | NEEDLE:%s" % [
			hp_str, avail_bombs, max_bombs, rng_val, spd_lv,
			"ON" if kick_on else "OFF",
			"YES" if needle_on else "NO",
		]


func _item_pickup_text(item_type: int) -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	var is_zhs: bool = loc.begins_with("ZHS")
	var is_zh: bool = loc.begins_with("ZH")
	if item_type == C.ITEM_BUBBLE:
		return "拾取：可放炸弹数 +1" if is_zhs else ("拾取：可放炸彈數 +1" if is_zh else "PICKUP: MAX BOMBS +1")
	if item_type == C.ITEM_POWER:
		return "拾取：爆炸范围 +1 格" if is_zhs else ("拾取：爆炸範圍 +1 格" if is_zh else "PICKUP: BLAST RANGE +1")
	if item_type == C.ITEM_SPEED:
		return "拾取：移动速度提升" if is_zhs else ("拾取：移動速度提升" if is_zh else "PICKUP: MOVE SPEED UP")
	if item_type == C.ITEM_KICK:
		return "拾取：踢炸弹（撞向炸弹即可踢飞）" if is_zhs else ("拾取：踢炸彈（撞向炸彈即可踢飛）" if is_zh else "PICKUP: KICK BOMBS (WALK INTO BOMB)")
	return "拾取：救命针（重伤倒地 1.5 秒自动自救）" if is_zhs else ("拾取：救命針（重傷倒地 1.5 秒自動自救）" if is_zh else "PICKUP: SYRINGE (AUTO-REVIVE WHEN DOWNED)")


func _update_player_hud_3d(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	if node == null or not is_instance_valid(node):
		return
	node.set_meta(&"mpm_alive", bool(p["alive"]))
	var hp_label: Label3D = node.get_node_or_null("HpBar") as Label3D
	var trap_shell: Node3D = node.get_node_or_null("TrapBubble") as Node3D
	if trap_shell != null:
		trap_shell.visible = bool(p["trapped"]) and bool(p["alive"])
	if hp_label != null:
		if not bool(p["alive"]):
			hp_label.visible = false
		elif bool(p["trapped"]):
			hp_label.visible = true
			var rem: float = maxf(0.0, C.TRAPPED_DURATION_SEC - float(p["trapped_timer"]))
			hp_label.text = "[CRITICAL %.1fs]" % rem if not bool(p["has_needle"]) else "[SYRINGE...]"
			hp_label.modulate = Color(1.0, 0.24, 0.18) if not bool(p["has_needle"]) else Color(1.0, 0.84, 0.28)
		else:
			hp_label.visible = true
			var bars: String = ""
			for i in range(int(p["hp"])):
				bars += "■"
			if bool(p["has_needle"]):
				bars += " +"
			hp_label.text = bars
			hp_label.modulate = Color(0.98, 0.34, 0.28) if int(p["hp"]) > 1 else Color(1.0, 0.80, 0.22)
	node.visible = bool(p["alive"])

	if int(p["network_id"]) == _local_net_id:
		_update_local_stats_hud()
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null:
		if bool(p["trapped"]) and ap.has_animation(&"mp_mod/falling"):
			if ap.current_animation != &"mp_mod/falling":
				ap.play(&"mp_mod/falling")
		elif not bool(p["trapped"]) and ap.has_animation(&"mp_mod/idle"):
			if ap.current_animation != &"mp_mod/idle" and ap.current_animation != &"mp_mod/shoved":
				ap.play(&"mp_mod/idle")


func _collect_particles_recursive(node: Node, out: Array[Node], trim_smoke: bool) -> void:
	if node is GPUParticles3D:
		var gp: GPUParticles3D = node
		gp.emitting = false
		if trim_smoke and (gp.name == "Upsmoke" or gp.name == "CircleSmoke"):
			gp.amount = maxi(4, int(gp.amount / 2))
		out.append(gp)
	elif node is CPUParticles3D:
		var cp: CPUParticles3D = node
		cp.emitting = false
		out.append(cp)
	for child in node.get_children():
		_collect_particles_recursive(child, out, trim_smoke)


func _build_fx_pool(scene: PackedScene, count: int, trim_smoke: bool) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if scene == null or _fx_root == null:
		return pool
	for _i in range(count):
		var inst = scene.instantiate()
		if inst is Node3D:
			var n3: Node3D = inst
			if n3.get_script() != null:
				n3.set_script(null)
			var emitters: Array[Node] = []
			_collect_particles_recursive(n3, emitters, trim_smoke)
			n3.position = Vector3(0.0, -50.0, 0.0)
			n3.visible = false
			_fx_root.add_child(n3)
			pool.append({"node": n3, "emitters": emitters, "timer": 0.0})
		elif inst is Node:
			(inst as Node).queue_free()
	return pool


func _init_fx_pools() -> void:
	if _fx_root == null or _blast_root == null or M == null or C == null:
		return
	for _i in range(POOL_BLAST_CENTER_CELLS):
		var cn: Node3D = M.build_blast_cell(C.TILE_SIZE, true, false)
		cn.position = Vector3(0.0, -50.0, 0.0)
		cn.visible = false
		_blast_root.add_child(cn)
		_blast_center_pool.append(cn)
	for _i in range(POOL_BLAST_ARM_CELLS):
		var an: Node3D = M.build_blast_cell(C.TILE_SIZE, false, false)
		an.position = Vector3(0.0, -50.0, 0.0)
		an.visible = false
		_blast_root.add_child(an)
		_blast_arm_pool.append(an)

	if _is_self_test:
		return

	_explosion_fx_pool = _build_fx_pool(_fx_explosion_scene, POOL_EXPLOSION_FX, true)
	_hit_blood_fx_pool = _build_fx_pool(_fx_hit_blood_scene, POOL_HIT_BLOOD_FX, false)
	_bloodmist_fx_pool = _build_fx_pool(_fx_bloodmist_scene, POOL_BLOODMIST_FX, false)

	if _explosion_mark_tex != null:
		for _i in range(POOL_EXPLOSION_DECALS):
			var dec := Decal.new()
			dec.size = Vector3(C.TILE_SIZE * 1.45, 0.35, C.TILE_SIZE * 1.45)
			dec.texture_albedo = _explosion_mark_tex
			dec.position = Vector3(0.0, -50.0, 0.0)
			dec.visible = false
			_fx_root.add_child(dec)
			_explosion_decals.append(dec)

	if _blood_tex_01 != null or _blood_tex_02 != null:
		for i in range(POOL_BLOOD_DECALS):
			var dec := Decal.new()
			dec.size = Vector3(1.15, 0.35, 1.15)
			dec.texture_albedo = _blood_tex_02 if (i % 2 == 1 and _blood_tex_02 != null) else (_blood_tex_01 if _blood_tex_01 != null else _blood_tex_02)
			dec.position = Vector3(0.0, -50.0, 0.0)
			dec.visible = false
			_fx_root.add_child(dec)
			_blood_decals.append(dec)

	for _i in range(POOL_BLAST_LIGHTS):
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.55, 0.20)
		flash.light_energy = 0.0
		flash.omni_range = C.TILE_SIZE * 3.2
		flash.position = Vector3(0.0, -50.0, 0.0)
		flash.visible = false
		_fx_root.add_child(flash)
		_blast_light_pool.append({"light": flash, "timer": 0.0})

	# Warm up shaders & GPU particle pipelines in camera frustum during intro so first real blast has zero hitch.
	if _screenshot_path.is_empty():
		var warm_pos := Vector3(0.0, 0.2, 0.0)
		for pool in [_explosion_fx_pool, _hit_blood_fx_pool, _bloodmist_fx_pool]:
			if not pool.is_empty():
				_trigger_fx_entry(pool[0], warm_pos, 0.01, 0.08)
		if not _blast_center_pool.is_empty():
			var wc: Node3D = _blast_center_pool[0]
			wc.position = warm_pos
			wc.scale = Vector3(0.01, 0.01, 0.01)
			wc.visible = true
		if not _explosion_decals.is_empty():
			var wd: Decal = _explosion_decals[0]
			wd.position = warm_pos
			wd.size = Vector3(0.05, 0.05, 0.05)
			wd.visible = true
		if not _blast_light_pool.is_empty():
			var wl: OmniLight3D = _blast_light_pool[0]["light"]
			wl.position = warm_pos
			wl.light_energy = 0.05
			wl.visible = true
			_blast_light_pool[0]["timer"] = 0.08
		get_tree().create_timer(0.08).timeout.connect(func():
			if not _blast_center_pool.is_empty() and is_instance_valid(_blast_center_pool[0]):
				_blast_center_pool[0].visible = false
				_blast_center_pool[0].scale = Vector3.ONE
				_blast_center_pool[0].position = Vector3(0.0, -50.0, 0.0)
			if not _explosion_decals.is_empty() and is_instance_valid(_explosion_decals[0]):
				_explosion_decals[0].visible = false
				_explosion_decals[0].position = Vector3(0.0, -50.0, 0.0)
		)


func _trigger_fx_entry(entry: Dictionary, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	var n3: Node3D = entry["node"]
	if not is_instance_valid(n3):
		return
	n3.position = world_pos
	n3.scale = Vector3.ONE * scale_val
	n3.visible = true
	entry["timer"] = lifetime
	for em in entry["emitters"]:
		if em is GPUParticles3D:
			var gp: GPUParticles3D = em
			gp.restart()
			gp.emitting = true
		elif em is CPUParticles3D:
			var cp: CPUParticles3D = em
			cp.restart()
			cp.emitting = true


func _step_fx_pools(delta: float) -> void:
	for pool in [_explosion_fx_pool, _hit_blood_fx_pool, _bloodmist_fx_pool]:
		for entry in pool:
			var rem: float = float(entry["timer"])
			if rem > 0.0:
				rem -= delta
				entry["timer"] = rem
				if rem <= 0.0:
					var n3: Node3D = entry["node"]
					if is_instance_valid(n3):
						n3.visible = false
						n3.position = Vector3(0.0, -50.0, 0.0)
	for entry in _blast_light_pool:
		var rem: float = float(entry["timer"])
		if rem > 0.0:
			rem -= delta
			entry["timer"] = rem
			var fl: OmniLight3D = entry["light"]
			if is_instance_valid(fl):
				if rem <= 0.0:
					fl.light_energy = 0.0
					fl.visible = false
				else:
					fl.light_energy = 4.5 * clampf(rem / maxf(0.05, C.BLAST_DURATION_SEC), 0.0, 1.0)


func _trigger_blast_light(world_pos: Vector3) -> void:
	if _is_self_test or _blast_light_pool.is_empty():
		return
	var entry: Dictionary = _blast_light_pool[_blast_light_cursor % _blast_light_pool.size()]
	_blast_light_cursor += 1
	var fl: OmniLight3D = entry["light"]
	if is_instance_valid(fl):
		fl.position = Vector3(world_pos.x, 0.65, world_pos.z)
		fl.light_energy = 4.5
		fl.visible = true
		entry["timer"] = C.BLAST_DURATION_SEC


func _spawn_vanilla_fx(scene: PackedScene, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	if _is_self_test or scene == null:
		return
	if scene == _fx_explosion_scene and not _explosion_fx_pool.is_empty():
		var entry: Dictionary = _explosion_fx_pool[_explosion_fx_cursor % _explosion_fx_pool.size()]
		_explosion_fx_cursor += 1
		_trigger_fx_entry(entry, world_pos, scale_val, lifetime)
	elif scene == _fx_hit_blood_scene and not _hit_blood_fx_pool.is_empty():
		var entry: Dictionary = _hit_blood_fx_pool[_hit_blood_fx_cursor % _hit_blood_fx_pool.size()]
		_hit_blood_fx_cursor += 1
		_trigger_fx_entry(entry, world_pos, scale_val, lifetime)
	elif scene == _fx_bloodmist_scene and not _bloodmist_fx_pool.is_empty():
		var entry: Dictionary = _bloodmist_fx_pool[_bloodmist_fx_cursor % _bloodmist_fx_pool.size()]
		_bloodmist_fx_cursor += 1
		_trigger_fx_entry(entry, world_pos, scale_val, lifetime)


func _spawn_explosion_mark(world_pos: Vector3, size_val: float) -> void:
	if _is_self_test or _explosion_decals.is_empty():
		return
	var dec: Decal = _explosion_decals[_explosion_decal_cursor % _explosion_decals.size()]
	_explosion_decal_cursor += 1
	if is_instance_valid(dec):
		dec.size = Vector3(size_val, 0.35, size_val)
		dec.position = Vector3(world_pos.x, 0.04, world_pos.z)
		dec.rotation_degrees.y = _rng.randf_range(0.0, 360.0)
		dec.visible = true


func _spawn_blood_decal(world_pos: Vector3) -> void:
	if _is_self_test or _blood_decals.is_empty():
		return
	var dec: Decal = _blood_decals[_blood_decal_cursor % _blood_decals.size()]
	_blood_decal_cursor += 1
	if is_instance_valid(dec):
		dec.size = Vector3(1.15, 0.35, 1.15)
		dec.position = Vector3(world_pos.x, 0.04, world_pos.z)
		dec.rotation_degrees.y = _rng.randf_range(0.0, 360.0)
		dec.visible = true


func _process(delta: float) -> void:
	if not _screenshot_path.is_empty():
		_screenshot_frames += 1
		_animate_visuals(delta)
		if _screenshot_frames >= 6:
			_save_screenshot_and_quit()
		return

	if _kill_feed_timer > 0.0:
		_kill_feed_timer = maxf(0.0, _kill_feed_timer - delta)
		if _kill_feed_timer <= 0.0:
			_kill_feed_label.text = ""

	if _round_ended:
		_animate_visuals(delta)
		return

	if _intro_timer > 0.0:
		_intro_timer -= delta
		var cd_sec: int = int(ceil(_intro_timer / 0.72))
		if cd_sec != _last_countdown_sec and cd_sec > 0 and cd_sec <= 3:
			_last_countdown_sec = cd_sec
			_banner_label.text = str(cd_sec)
			if _sfx_countdown != null:
				_sfx_countdown.play()
		if _intro_timer <= 0.0:
			_banner_label.text = "GO!"
			if _sfx_ding != null:
				_sfx_ding.play()
			_round_active = true
		_animate_visuals(delta)
		return
	elif _banner_label.text == "GO!" and _elapsed_time > 0.65:
		_banner_label.text = ""

	if not _round_active:
		return

	_read_local_input()

	if _is_server_sim:
		_step_simulation(delta)
		if not _standalone_mode:
			_sync_accum += delta
			if _sync_accum >= 0.05:
				_sync_accum = 0.0
				_broadcast_snapshot()
	_update_crt_monitor()
	_animate_visuals(delta)


func _is_input_blocked_by_ui() -> bool:
	if get_tree() == null or get_tree().root == null:
		return false
	var pause_menu: Node = get_tree().root.get_node_or_null("PauseMenu")
	if pause_menu != null and bool(pause_menu.get("active")):
		return true
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null and gm.get("game_focused") == false:
		return true
	return false


func _read_local_input() -> void:
	var dir := Vector2.ZERO
	var drop_edge := false
	if _is_input_blocked_by_ui():
		_prev_drop_pressed = false
	else:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if dir.length_squared() > 0.0:
			dir = dir.normalized()
		var drop_now: bool = Input.is_key_pressed(KEY_SPACE)
		drop_edge = drop_now and not _prev_drop_pressed
		_prev_drop_pressed = drop_now

	if _is_server_sim:
		var prev_drop: bool = false
		if _client_inputs.has(_local_net_id):
			prev_drop = bool(_client_inputs[_local_net_id].get("drop", false))
		_client_inputs[_local_net_id] = {"dir": dir, "drop": prev_drop or drop_edge}
	else:
		_rpc_client_input.rpc_id(1, dir, false)
		if drop_edge:
			_rpc_request_drop.rpc_id(1)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_client_input(dir: Vector2, drop: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var prev_drop: bool = false
	if _client_inputs.has(sender):
		prev_drop = bool(_client_inputs[sender].get("drop", false))
	_client_inputs[sender] = {"dir": dir.limit_length(1.0), "drop": prev_drop or drop}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_drop() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var prev_dir: Vector2 = Vector2.ZERO
	if _client_inputs.has(sender):
		prev_dir = _client_inputs[sender].get("dir", Vector2.ZERO)
	_client_inputs[sender] = {"dir": prev_dir, "drop": true}


func _step_simulation(delta: float) -> void:
	_elapsed_time += delta
	_time_remaining = maxf(0.0, C.ROUND_DURATION_SEC - _elapsed_time)
	var sec_left: int = int(ceil(_time_remaining))
	if sec_left <= 10 and sec_left > 0 and sec_left != _last_beep_sec:
		_last_beep_sec = sec_left
		if _sfx_beep != null:
			_sfx_beep.play()
	if _time_remaining <= C.HURRY_UP_REMAINING_SEC:
		_step_crusher_shrink(delta)

	_step_bubbles(delta)
	_step_blasts(delta)
	_step_players(delta)
	_check_round_end()


func _step_crusher_shrink(delta: float) -> void:
	_crusher_timer += delta
	while _crusher_timer >= C.CRUSHER_STEP_INTERVAL_SEC and _crusher_index < _crush_order.size():
		_crusher_timer -= C.CRUSHER_STEP_INTERVAL_SEC
		var cell: Vector2i = _crush_order[_crusher_index]
		_crusher_index += 1
		_crush_tile(cell)


func _crush_tile(cell: Vector2i) -> void:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= _map_width - 1 or cell.y >= _map_height - 1:
		return
	_tiles[cell.y][cell.x] = C.TILE_CRUSHED
	if _tile_nodes.has(cell):
		var old_n: Node3D = _tile_nodes[cell]
		if is_instance_valid(old_n):
			old_n.queue_free()
		_tile_nodes.erase(cell)
	var block: Node3D = M.build_crusher_block(C.TILE_SIZE)
	block.position = C.grid_to_world(cell, _map_width, _map_height)
	_arena_root.add_child(block)
	_tile_nodes[cell] = block

	for item_id in _items.keys():
		if _items[item_id]["cell"] == cell:
			_remove_item(item_id)
	for b_id in _bubbles.keys():
		if _bubbles[b_id]["cell"] == cell:
			_detonate_bubble(b_id)

	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if not bool(p["alive"]):
			continue
		var p_cell: Vector2i = C.world_to_grid(p["pos"], _map_width, _map_height)
		if p_cell == cell:
			_eliminate_player(p, 0, "CRUSHED")

	if not _standalone_mode and multiplayer.is_server():
		_rpc_crush_tile.rpc(cell)


@rpc("authority", "call_remote", "reliable")
func _rpc_crush_tile(cell: Vector2i) -> void:
	_tiles[cell.y][cell.x] = C.TILE_CRUSHED
	if _tile_nodes.has(cell):
		var old_n: Node3D = _tile_nodes[cell]
		if is_instance_valid(old_n):
			old_n.queue_free()
		_tile_nodes.erase(cell)
	var block: Node3D = M.build_crusher_block(C.TILE_SIZE)
	block.position = C.grid_to_world(cell, _map_width, _map_height)
	_arena_root.add_child(block)
	_tile_nodes[cell] = block


func _is_tile_blocked(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _map_width or cell.y >= _map_height:
		return true
	return int(_tiles[cell.y][cell.x]) != C.TILE_EMPTY


func _bubble_at_cell(cell: Vector2i, ignore_id: int = -1) -> int:
	for b_id in _bubbles.keys():
		if int(b_id) == ignore_id:
			continue
		if _bubbles[b_id]["cell"] == cell:
			return int(b_id)
	return -1


func _step_players(delta: float) -> void:
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if not bool(p["alive"]):
			continue

		if float(p["invuln_timer"]) > 0.0:
			p["invuln_timer"] = maxf(0.0, float(p["invuln_timer"]) - delta)

		if bool(p["trapped"]):
			p["trapped_timer"] = float(p["trapped_timer"]) + delta
			_update_player_hud_3d(p)
			if bool(p["has_needle"]) and float(p["trapped_timer"]) >= C.NEEDLE_AUTO_SAVE_DELAY_SEC:
				p["has_needle"] = false
				p["trapped"] = false
				p["trapped_timer"] = 0.0
				p["hp"] = 1
				p["invuln_timer"] = C.INVULN_DURATION_SEC
				_show_kill_feed(str(p["nickname"]) + " NEEDLE ESCAPE!")
				_update_player_hud_3d(p)
				continue
			if float(p["trapped_timer"]) >= C.TRAPPED_DURATION_SEC:
				_eliminate_player(p, int(p["last_attacker"]), "POPPED")
				continue

		var input_dir := Vector2.ZERO
		var want_drop := false
		if bool(p["is_ai"]):
			var ai_act: Dictionary = _compute_ai_input(p, delta)
			input_dir = ai_act["dir"]
			want_drop = bool(ai_act["drop"])
		elif _client_inputs.has(net_id):
			var ci: Dictionary = _client_inputs[net_id]
			input_dir = ci["dir"]
			want_drop = bool(ci["drop"])
			ci["drop"] = false

		var speed: float = C.BASE_MOVE_SPEED + float(p["speed_level"]) * C.SPEED_STEP_BONUS
		if bool(p["trapped"]):
			speed *= C.TRAPPED_MOVE_MULTIPLIER

		var cur_pos: Vector3 = p["pos"]
		var cur_cell: Vector2i = C.world_to_grid(cur_pos, _map_width, _map_height)

		var conv_vel := Vector3.ZERO
		if _conveyors.has(cur_cell):
			var cdir: Vector2i = _conveyors[cur_cell]
			conv_vel = Vector3(float(cdir.x), 0.0, float(cdir.y)) * C.CONVEYOR_PLAYER_PUSH

		var move_vec := Vector3(input_dir.x, 0.0, input_dir.y) * speed + conv_vel
		if input_dir.length_squared() > 0.01:
			p["facing"] = input_dir.normalized()

		var next_pos: Vector3 = _move_player_with_collision(p, cur_pos, move_vec, speed, delta)
		p["pos"] = next_pos

		var pass_ids: Dictionary = p["pass_bubble_ids"]
		for b_id in pass_ids.keys():
			if not _bubbles.has(b_id):
				pass_ids.erase(b_id)
				continue
			var b_pos: Vector3 = _bubbles[b_id]["pos"]
			if Vector2(next_pos.x - b_pos.x, next_pos.z - b_pos.z).length() > C.TILE_SIZE * 0.72:
				pass_ids.erase(b_id)

		if want_drop and not bool(p["trapped"]):
			_try_place_bubble(p)

		if not bool(p["trapped"]):
			var new_cell: Vector2i = C.world_to_grid(next_pos, _map_width, _map_height)
			for item_id in _items.keys():
				if _items[item_id]["cell"] == new_cell:
					_apply_item(p, int(_items[item_id]["type"]))
					_remove_item(item_id)
					break

	var ids: Array = _players.keys()
	for i in range(ids.size()):
		var a: Dictionary = _players[ids[i]]
		if not bool(a["alive"]) or not bool(a["trapped"]):
			continue
		for j in range(ids.size()):
			if i == j:
				continue
			var b: Dictionary = _players[ids[j]]
			if not bool(b["alive"]) or bool(b["trapped"]):
				continue
			var dist: float = Vector2(a["pos"].x - b["pos"].x, a["pos"].z - b["pos"].z).length()
			if dist <= C.TILE_SIZE * 0.62:
				_eliminate_player(a, int(b["network_id"]), "BUMP POP")
				break


func _move_player_with_collision(p: Dictionary, start_pos: Vector3, move_vec: Vector3, max_speed: float, delta: float) -> Vector3:
	var radius: float = C.TILE_SIZE * 0.30
	var pos := start_pos
	var dx: float = move_vec.x * delta
	var dz: float = move_vec.z * delta
	var want_x: bool = absf(dx) > 0.0001
	var want_z: bool = absf(dz) > 0.0001
	var blocked_x: bool = false
	var blocked_z: bool = false

	# 1. Try X axis first.
	if want_x:
		var cand_x := Vector3(pos.x + dx, 0.0, pos.z)
		if not _collides_world(p, cand_x, radius, Vector2(signf(dx), 0.0)):
			pos.x = cand_x.x
		else:
			blocked_x = true

	# 2. Try Z axis. If X was blocked while moving diagonally, preserve full wall-slide speed on Z!
	if want_z:
		var eff_dz: float = dz
		if blocked_x:
			eff_dz = signf(dz) * maxf(absf(dz), max_speed * delta)
		var cand_z := Vector3(pos.x, 0.0, pos.z + eff_dz)
		if not _collides_world(p, cand_z, radius, Vector2(0.0, signf(eff_dz))):
			pos.z = cand_z.z
		else:
			blocked_z = true

	# 3. If Z was blocked while moving diagonally and X succeeded, preserve full wall-slide speed on X!
	if want_x and blocked_z and not blocked_x:
		var full_dx: float = signf(dx) * maxf(absf(dx), max_speed * delta)
		var extra_dx: float = full_dx - dx
		if absf(extra_dx) > 0.0001:
			var cand_x2 := Vector3(pos.x + extra_dx, 0.0, pos.z)
			if not _collides_world(p, cand_x2, radius, Vector2(signf(dx), 0.0)):
				pos.x = cand_x2.x

	# 4. Corner assist ONLY for pure single-axis input clipping a pillar corner into an open lane.
	if blocked_x and not want_z:
		var cell: Vector2i = C.world_to_grid(pos, _map_width, _map_height)
		var ahead_cell := Vector2i(cell.x + (1 if dx > 0.0 else -1), cell.y)
		if not _is_tile_blocked(ahead_cell) and _bubble_at_cell(ahead_cell) == -1:
			var row_center: float = C.grid_to_world(cell, _map_width, _map_height).z
			var diff_z: float = row_center - pos.z
			if absf(diff_z) > 0.01 and absf(diff_z) < C.TILE_SIZE * 0.48:
				var nudge: float = signf(diff_z) * minf(absf(diff_z), absf(dx))
				var assist_pos := Vector3(pos.x, 0.0, pos.z + nudge)
				if not _collides_world(p, assist_pos, radius, Vector2.ZERO):
					pos.z = assist_pos.z
	elif blocked_z and not want_x:
		var cell: Vector2i = C.world_to_grid(pos, _map_width, _map_height)
		var ahead_cell := Vector2i(cell.x, cell.y + (1 if dz > 0.0 else -1))
		if not _is_tile_blocked(ahead_cell) and _bubble_at_cell(ahead_cell) == -1:
			var col_center: float = C.grid_to_world(cell, _map_width, _map_height).x
			var diff_x: float = col_center - pos.x
			if absf(diff_x) > 0.01 and absf(diff_x) < C.TILE_SIZE * 0.48:
				var nudge: float = signf(diff_x) * minf(absf(diff_x), absf(dz))
				var assist_pos := Vector3(pos.x + nudge, 0.0, pos.z)
				if not _collides_world(p, assist_pos, radius, Vector2.ZERO):
					pos.x = assist_pos.x

	return pos


func _collides_world(p: Dictionary, test_pos: Vector3, radius: float, push_dir: Vector2) -> bool:
	var half: float = C.TILE_SIZE * 0.5
	var center_cell: Vector2i = C.world_to_grid(test_pos, _map_width, _map_height)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not _is_tile_blocked(c):
				continue
			var tile_w: Vector3 = C.grid_to_world(c, _map_width, _map_height)
			var cx: float = clampf(test_pos.x, tile_w.x - half, tile_w.x + half)
			var cz: float = clampf(test_pos.z, tile_w.z - half, tile_w.z + half)
			if Vector2(test_pos.x - cx, test_pos.z - cz).length_squared() < radius * radius:
				return true

	var pass_ids: Dictionary = p["pass_bubble_ids"]
	var cur_p: Vector3 = p["pos"]
	var min_bubble_dist: float = radius + C.TILE_SIZE * 0.34
	for b_id in _bubbles.keys():
		if pass_ids.has(b_id):
			continue
		var b: Dictionary = _bubbles[b_id]
		var bp: Vector3 = b["pos"]
		var d: float = Vector2(test_pos.x - bp.x, test_pos.z - bp.z).length()
		if d < min_bubble_dist:
			var cur_d: float = Vector2(cur_p.x - bp.x, cur_p.z - bp.z).length()
			# If already overlapping a bubble (e.g. placed or slid into the player),
			# allow any movement that increases separation so players can never be stuck.
			if cur_d < min_bubble_dist and d > cur_d + 0.0001:
				continue
			if bool(p["has_kick"]) and not bool(p["trapped"]) and push_dir.length_squared() > 0.5:
				var kdir := Vector2i(int(round(push_dir.x)), int(round(push_dir.y)))
				b["slide_dir"] = kdir
				b["slide_speed"] = C.BUBBLE_SLIDE_SPEED
			return true
	return false


func _try_place_bubble(p: Dictionary) -> bool:
	if int(p["active_bubbles"]) >= int(p["max_bubbles"]):
		return false
	var cell: Vector2i = C.world_to_grid(p["pos"], _map_width, _map_height)
	if _is_tile_blocked(cell) or _bubble_at_cell(cell) != -1:
		return false

	var b_id: int = _next_bubble_id
	_next_bubble_id += 1
	var world_pos: Vector3 = C.grid_to_world(cell, _map_width, _map_height)
	_bubbles[b_id] = {
		"id": b_id,
		"owner_id": int(p["network_id"]),
		"cell": cell,
		"pos": world_pos,
		"power": int(p["power"]),
		"fuse": C.BUBBLE_FUSE_SEC,
		"slide_dir": Vector2i.ZERO,
		"slide_speed": 0.0,
	}
	p["active_bubbles"] = int(p["active_bubbles"]) + 1
	(p["pass_bubble_ids"] as Dictionary)[b_id] = true
	# Grant pass-through to any alive player currently overlapping the new bubble so
	# dropping a bomb in someone's face on open ground cannot trap them in place.
	for other_id in _players.keys():
		var other: Dictionary = _players[other_id]
		if not bool(other["alive"]):
			continue
		var op: Vector3 = other["pos"]
		if Vector2(op.x - world_pos.x, op.z - world_pos.z).length() <= C.TILE_SIZE * 0.72:
			(other["pass_bubble_ids"] as Dictionary)[b_id] = true
	if int(p["network_id"]) == _local_net_id:
		_update_local_stats_hud()

	var node: Node3D = M.build_water_bubble(C.TILE_SIZE, p["color"])
	node.position = world_pos
	_arena_root.add_child(node)
	_bubble_nodes[b_id] = node
	if _sfx_place != null:
		_sfx_place.play()

	if not _standalone_mode and multiplayer.is_server():
		_rpc_spawn_bubble.rpc(b_id, int(p["network_id"]), cell, p["color"])
	return true


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_bubble(b_id: int, owner_id: int, cell: Vector2i, color: Color) -> void:
	var world_pos: Vector3 = C.grid_to_world(cell, _map_width, _map_height)
	_bubbles[b_id] = {
		"id": b_id,
		"owner_id": owner_id,
		"cell": cell,
		"pos": world_pos,
		"fuse": C.BUBBLE_FUSE_SEC,
	}
	var node: Node3D = M.build_water_bubble(C.TILE_SIZE, color)
	node.position = world_pos
	_arena_root.add_child(node)
	_bubble_nodes[b_id] = node


func _step_bubbles(delta: float) -> void:
	var to_detonate: Array = []
	for b_id in _bubbles.keys():
		var b: Dictionary = _bubbles[b_id]
		b["fuse"] = float(b["fuse"]) - delta

		var sdir: Vector2i = b["slide_dir"]
		var sspeed: float = float(b["slide_speed"])
		var cur_cell: Vector2i = b["cell"]
		if sdir == Vector2i.ZERO and _conveyors.has(cur_cell):
			sdir = _conveyors[cur_cell]
			sspeed = C.CONVEYOR_BUBBLE_SPEED

		if sdir != Vector2i.ZERO and sspeed > 0.0:
			var next_pos: Vector3 = b["pos"] + Vector3(float(sdir.x), 0.0, float(sdir.y)) * sspeed * delta
			var ahead_pos: Vector3 = next_pos + Vector3(float(sdir.x), 0.0, float(sdir.y)) * (C.TILE_SIZE * 0.42)
			var ahead_cell: Vector2i = C.world_to_grid(ahead_pos, _map_width, _map_height)
			var blocked: bool = _is_tile_blocked(ahead_cell) or _bubble_at_cell(ahead_cell, int(b_id)) != -1
			if not blocked:
				for net_id in _players.keys():
					var p: Dictionary = _players[net_id]
					if not bool(p["alive"]):
						continue
					if (p["pass_bubble_ids"] as Dictionary).has(b_id):
						continue
					if Vector2(next_pos.x - p["pos"].x, next_pos.z - p["pos"].z).length() < C.TILE_SIZE * 0.56:
						blocked = true
						break
			if blocked:
				var snap: Vector2i = C.world_to_grid(b["pos"], _map_width, _map_height)
				b["cell"] = snap
				b["pos"] = C.grid_to_world(snap, _map_width, _map_height)
				b["slide_dir"] = Vector2i.ZERO
				b["slide_speed"] = 0.0
			else:
				b["pos"] = next_pos
				b["cell"] = C.world_to_grid(next_pos, _map_width, _map_height)

		if _bubble_nodes.has(b_id):
			var bn: Node3D = _bubble_nodes[b_id]
			if is_instance_valid(bn):
				bn.position = b["pos"]

		if float(b["fuse"]) <= 0.0:
			to_detonate.append(int(b_id))

	for b_id in to_detonate:
		if _bubbles.has(b_id):
			_detonate_bubble(b_id)


func _detonate_bubble(b_id: int) -> void:
	if not _bubbles.has(b_id):
		return
	var b: Dictionary = _bubbles[b_id]
	_bubbles.erase(b_id)
	if _bubble_nodes.has(b_id):
		var bn: Node3D = _bubble_nodes[b_id]
		if is_instance_valid(bn):
			bn.queue_free()
		_bubble_nodes.erase(b_id)

	var owner_id: int = int(b["owner_id"])
	if _players.has(owner_id):
		var owner_p: Dictionary = _players[owner_id]
		owner_p["active_bubbles"] = max(0, int(owner_p["active_bubbles"]) - 1)
		if owner_id == _local_net_id:
			_update_local_stats_hud()

	var origin: Vector2i = b["cell"]
	var power: int = int(b["power"])
	var cells: Array = [origin]
	var destroyed_crates: Array = []
	var chain_ids: Array = []

	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for raw_dir in dirs:
		var d: Vector2i = raw_dir
		for step in range(1, power + 1):
			var c: Vector2i = origin + d * step
			if c.x < 0 or c.y < 0 or c.x >= _map_width or c.y >= _map_height:
				break
			var t: int = int(_tiles[c.y][c.x])
			if t == C.TILE_STEEL or t == C.TILE_CRUSHED:
				break
			cells.append(c)
			if t == C.TILE_CRATE or t == C.TILE_GOLD_CRATE:
				destroyed_crates.append({"cell": c, "gold": t == C.TILE_GOLD_CRATE})
				break
			var hit_b: int = _bubble_at_cell(c)
			if hit_b != -1 and not chain_ids.has(hit_b):
				chain_ids.append(hit_b)

	for cr in destroyed_crates:
		var c: Vector2i = cr["cell"]
		var is_gold: bool = bool(cr["gold"])
		_tiles[c.y][c.x] = C.TILE_EMPTY
		if _tile_nodes.has(c):
			var cn: Node3D = _tile_nodes[c]
			if is_instance_valid(cn):
				cn.queue_free()
			_tile_nodes.erase(c)
		var drop_chance: float = C.GOLD_CRATE_DROP_CHANCE if is_gold else C.CRATE_DROP_CHANCE
		if _rng.randf() <= drop_chance:
			var itype: int = C.roll_item_type(_rng, is_gold)
			_spawn_item(c, itype)

	_spawn_blast_visual(cells, owner_id)
	if not _standalone_mode and multiplayer.is_server():
		_rpc_detonate.rpc(b_id, cells, destroyed_crates)

	for cid in chain_ids:
		if _bubbles.has(cid):
			# Stagger chain detonations across frames to prevent single-frame spikes and create a chain ripple.
			_bubbles[cid]["fuse"] = minf(float(_bubbles[cid]["fuse"]), CHAIN_DETONATE_DELAY_SEC)


@rpc("authority", "call_remote", "reliable")
func _rpc_detonate(b_id: int, cells: Array, destroyed_crates: Array) -> void:
	_bubbles.erase(b_id)
	if _bubble_nodes.has(b_id):
		var bn: Node3D = _bubble_nodes[b_id]
		if is_instance_valid(bn):
			bn.queue_free()
		_bubble_nodes.erase(b_id)
	for cr in destroyed_crates:
		var c: Vector2i = cr["cell"]
		_tiles[c.y][c.x] = C.TILE_EMPTY
		if _tile_nodes.has(c):
			var cn: Node3D = _tile_nodes[c]
			if is_instance_valid(cn):
				cn.queue_free()
			_tile_nodes.erase(c)
	_spawn_blast_visual(cells, 0)


func _spawn_blast_visual(cells: Array, owner_id: int) -> void:
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		var wpos: Vector3 = C.grid_to_world(c, _map_width, _map_height)
		var is_center: bool = (i == 0)
		if _active_blast_visuals.has(c):
			var existing: Dictionary = _active_blast_visuals[c]
			existing["timer"] = maxf(float(existing["timer"]), C.BLAST_DURATION_SEC)
		else:
			var pool: Array[Node3D] = _blast_center_pool if is_center else _blast_arm_pool
			if not pool.is_empty():
				var n: Node3D = pool.pop_back()
				if is_instance_valid(n):
					n.position = wpos
					n.scale = Vector3.ONE
					n.visible = true
					_active_blast_visuals[c] = {
						"node": n,
						"is_center": is_center,
						"timer": C.BLAST_DURATION_SEC,
					}
		if is_center:
			_spawn_vanilla_fx(_fx_explosion_scene, Vector3(wpos.x, 0.25, wpos.z), 0.22, 1.8)
			_spawn_explosion_mark(wpos, C.TILE_SIZE * 1.45)
			_trigger_blast_light(wpos)
	if _sfx_explosion != null and _screenshot_path.is_empty():
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_explosion_sfx_ms >= EXPLOSION_SFX_MIN_INTERVAL_MS:
			_last_explosion_sfx_ms = now_ms
			_sfx_explosion.play()
	_blasts.append({
		"cells": cells,
		"owner_id": owner_id,
		"timer": C.BLAST_DURATION_SEC,
	})


func _step_blasts(delta: float) -> void:
	var kept: Array = []
	for b in _blasts:
		b["timer"] = float(b["timer"]) - delta
		var cells: Array = b["cells"]
		var owner_id: int = int(b["owner_id"])

		if _is_server_sim:
			for net_id in _players.keys():
				var p: Dictionary = _players[net_id]
				if not bool(p["alive"]):
					continue
				var p_cell: Vector2i = C.world_to_grid(p["pos"], _map_width, _map_height)
				if cells.has(p_cell):
					_hit_player_by_blast(p, owner_id)

		if float(b["timer"]) > 0.0:
			kept.append(b)
	_blasts = kept

	var expired_cells: Array[Vector2i] = []
	for cell_key in _active_blast_visuals.keys():
		var entry: Dictionary = _active_blast_visuals[cell_key]
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) <= 0.0:
			expired_cells.append(cell_key)
	for c in expired_cells:
		var entry: Dictionary = _active_blast_visuals[c]
		_active_blast_visuals.erase(c)
		var n: Node3D = entry["node"]
		if is_instance_valid(n):
			n.visible = false
			n.position = Vector3(0.0, -50.0, 0.0)
			if bool(entry["is_center"]):
				_blast_center_pool.append(n)
			else:
				_blast_arm_pool.append(n)


func _hit_player_by_blast(p: Dictionary, attacker_id: int) -> void:
	if not bool(p["alive"]):
		return
	if float(p["invuln_timer"]) > 0.0:
		return

	if bool(p["trapped"]):
		var credit: int = attacker_id if attacker_id != int(p["network_id"]) and attacker_id > 0 else int(p["last_attacker"])
		_eliminate_player(p, credit, "BLAST POP")
		return

	p["hp"] = int(p["hp"]) - 1
	if attacker_id > 0 and attacker_id != int(p["network_id"]):
		p["last_attacker"] = attacker_id

	var hit_pos: Vector3 = p["pos"]
	_spawn_vanilla_fx(_fx_hit_blood_scene, Vector3(hit_pos.x, 0.72, hit_pos.z), 0.36, 1.1)
	_spawn_blood_decal(hit_pos)
	if _sfx_shove != null:
		_sfx_shove.play()
	if int(p["network_id"]) == _local_net_id:
		_update_local_stats_hud()
	var ap: AnimationPlayer = p.get("anim_player", null)
	if ap != null and ap.has_animation(&"mp_mod/shoved"):
		ap.play(&"mp_mod/shoved")

	if int(p["hp"]) <= 0:
		p["hp"] = 0
		p["trapped"] = true
		p["trapped_timer"] = 0.0
		p["invuln_timer"] = 0.45
		if attacker_id > 0 and attacker_id != int(p["network_id"]) and _players.has(attacker_id):
			_players[attacker_id]["traps"] = int(_players[attacker_id]["traps"]) + 1
		_show_kill_feed(str(p["nickname"]) + " DOWNED! BUMP TO FINISH!")
	else:
		p["invuln_timer"] = C.INVULN_DURATION_SEC
	_update_player_hud_3d(p)


func _eliminate_player(p: Dictionary, killer_id: int, reason: String) -> void:
	if not bool(p["alive"]):
		return
	p["alive"] = false
	p["trapped"] = false
	p["elim_time"] = _elapsed_time
	var pos: Vector3 = p["pos"]
	_spawn_vanilla_fx(_fx_bloodmist_scene, Vector3(pos.x, 0.65, pos.z), 0.42, 2.8)
	_spawn_blood_decal(pos)
	if _sfx_elim != null:
		_sfx_elim.play()
	if killer_id > 0 and killer_id != int(p["network_id"]) and _players.has(killer_id):
		_players[killer_id]["pops"] = int(_players[killer_id]["pops"]) + 1
		_show_kill_feed(str(_players[killer_id]["nickname"]) + " POPPED " + str(p["nickname"]) + "!")
	else:
		_show_kill_feed(str(p["nickname"]) + " OUT (" + reason + ")")
	_update_player_hud_3d(p)


func _spawn_item(cell: Vector2i, item_type: int) -> void:
	var item_id: int = _next_item_id
	_next_item_id += 1
	_items[item_id] = {"id": item_id, "cell": cell, "type": item_type}
	var node: Node3D = M.build_powerup_node(C.TILE_SIZE, item_type)
	node.position = C.grid_to_world(cell, _map_width, _map_height)
	_arena_root.add_child(node)
	_item_nodes[item_id] = node
	if not _standalone_mode and multiplayer.is_server():
		_rpc_spawn_item.rpc(item_id, cell, item_type)


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_item(item_id: int, cell: Vector2i, item_type: int) -> void:
	_items[item_id] = {"id": item_id, "cell": cell, "type": item_type}
	var node: Node3D = M.build_powerup_node(C.TILE_SIZE, item_type)
	node.position = C.grid_to_world(cell, _map_width, _map_height)
	_arena_root.add_child(node)
	_item_nodes[item_id] = node


func _remove_item(item_id: int) -> void:
	_items.erase(item_id)
	if _item_nodes.has(item_id):
		var n: Node3D = _item_nodes[item_id]
		if is_instance_valid(n):
			n.queue_free()
		_item_nodes.erase(item_id)
	if not _standalone_mode and multiplayer.is_server():
		_rpc_remove_item.rpc(item_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_remove_item(item_id: int) -> void:
	_items.erase(item_id)
	if _item_nodes.has(item_id):
		var n: Node3D = _item_nodes[item_id]
		if is_instance_valid(n):
			n.queue_free()
		_item_nodes.erase(item_id)


func _apply_item(p: Dictionary, item_type: int) -> void:
	if item_type == C.ITEM_BUBBLE:
		p["max_bubbles"] = min(C.MAX_BUBBLES_CAP, int(p["max_bubbles"]) + 1)
	elif item_type == C.ITEM_POWER:
		p["power"] = min(C.MAX_POWER_CAP, int(p["power"]) + 1)
	elif item_type == C.ITEM_SPEED:
		p["speed_level"] = min(C.MAX_SPEED_LEVEL, int(p["speed_level"]) + 1)
	elif item_type == C.ITEM_KICK:
		p["has_kick"] = true
	elif item_type == C.ITEM_NEEDLE:
		p["has_needle"] = true
	if _sfx_pickup != null:
		_sfx_pickup.play()
	if int(p["network_id"]) == _local_net_id:
		_show_kill_feed(_item_pickup_text(item_type))
	_update_player_hud_3d(p)


func _show_kill_feed(msg: String) -> void:
	if _kill_feed_label != null:
		_kill_feed_label.text = msg
		_kill_feed_timer = 2.4


func _check_round_end() -> void:
	if _round_ended:
		return
	var alive_count: int = 0
	for net_id in _players.keys():
		if bool(_players[net_id]["alive"]):
			alive_count += 1

	var should_end: bool = (_time_remaining <= 0.0) or (_players.size() > 1 and alive_count <= 1) or (_players.size() == 1 and alive_count == 0)
	if not should_end:
		return

	_round_ended = true
	_round_active = false
	var entries: Array = []
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		entries.append({
			"network_id": int(p["network_id"]),
			"alive": bool(p["alive"]),
			"elim_time": float(p["elim_time"]),
			"pops": int(p["pops"]),
			"traps": int(p["traps"]),
		})
	var scores: Dictionary = C.compute_rank_scores(entries)
	_banner_label.text = "ROUND COMPLETE!"
	if _standalone_mode:
		await get_tree().create_timer(1.8).timeout
		if is_inside_tree():
			get_tree().quit()
	else:
		_rpc_round_banner.rpc("ROUND COMPLETE!")
		await get_tree().create_timer(1.4).timeout
		if is_inside_tree():
			round_finished.emit(scores)


@rpc("authority", "call_remote", "reliable")
func _rpc_round_banner(text: String) -> void:
	if _banner_label != null:
		_banner_label.text = text


func _broadcast_snapshot() -> void:
	var p_snap: Dictionary = {}
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		p_snap[net_id] = [
			p["pos"],
			p["facing"],
			int(p["hp"]),
			bool(p["alive"]),
			bool(p["trapped"]),
			float(p["invuln_timer"]),
			bool(p["has_needle"]),
			int(p["max_bubbles"]),
			int(p["active_bubbles"]),
			int(p["power"]),
			int(p["speed_level"]),
			bool(p["has_kick"]),
			float(p["trapped_timer"]),
		]
	var b_snap: Dictionary = {}
	for b_id in _bubbles.keys():
		b_snap[b_id] = _bubbles[b_id]["pos"]
	_rpc_snapshot.rpc(_time_remaining, p_snap, b_snap)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(rem_time: float, p_snap: Dictionary, b_snap: Dictionary) -> void:
	_time_remaining = rem_time
	for net_id in p_snap.keys():
		if not _players.has(net_id):
			continue
		var arr: Array = p_snap[net_id]
		var p: Dictionary = _players[net_id]
		var prev_hp: int = int(p["hp"])
		var prev_alive: bool = bool(p["alive"])
		p["pos"] = arr[0]
		p["facing"] = arr[1]
		p["hp"] = int(arr[2])
		p["alive"] = bool(arr[3])
		p["trapped"] = bool(arr[4])
		p["invuln_timer"] = float(arr[5])
		p["has_needle"] = bool(arr[6])
		if arr.size() >= 12:
			p["max_bubbles"] = int(arr[7])
			p["active_bubbles"] = int(arr[8])
			p["power"] = int(arr[9])
			p["speed_level"] = int(arr[10])
			p["has_kick"] = bool(arr[11])
		if arr.size() >= 13:
			p["trapped_timer"] = float(arr[12])
		if prev_alive and not bool(p["alive"]):
			var pos: Vector3 = p["pos"]
			_spawn_vanilla_fx(_fx_bloodmist_scene, Vector3(pos.x, 0.65, pos.z), 0.42, 2.8)
			_spawn_blood_decal(pos)
			if _sfx_elim != null:
				_sfx_elim.play()
		elif int(p["hp"]) < prev_hp:
			var pos: Vector3 = p["pos"]
			_spawn_vanilla_fx(_fx_hit_blood_scene, Vector3(pos.x, 0.72, pos.z), 0.36, 1.1)
			_spawn_blood_decal(pos)
			if _sfx_shove != null:
				_sfx_shove.play()
		_update_player_hud_3d(p)
	for b_id in b_snap.keys():
		if _bubbles.has(b_id):
			_bubbles[b_id]["pos"] = b_snap[b_id]


func _animate_visuals(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		var node: Node3D = p["node"]
		if node == null or not is_instance_valid(node):
			continue
		var target_pos: Vector3 = p["pos"]
		var prev_pos: Vector3 = node.position
		node.position = node.position.lerp(target_pos, clampf(delta * 18.0, 0.0, 1.0))
		var move_speed_vis: float = Vector2(node.position.x - prev_pos.x, node.position.z - prev_pos.z).length() / maxf(delta, 0.001)

		var f: Vector2 = p["facing"]
		var avatar: Node3D = node.get_node_or_null("Avatar") as Node3D
		if avatar != null:
			if f.length_squared() > 0.01:
				var target_yaw: float = atan2(f.x, f.y)
				avatar.rotation.y = lerp_angle(avatar.rotation.y, target_yaw, clampf(delta * 16.0, 0.0, 1.0))
			if float(p["invuln_timer"]) > 0.0 and not bool(p["trapped"]):
				avatar.visible = int(floor(t * 16.0)) % 2 == 0
			else:
				avatar.visible = true

		# Drive vanilla run / idle / falling skeletal animations cleanly on both host and clients.
		var ap: AnimationPlayer = p.get("anim_player", null)
		if ap != null and bool(p["alive"]):
			if bool(p["trapped"]):
				ap.speed_scale = 1.0
				if ap.has_animation(&"mp_mod/falling") and ap.current_animation != &"mp_mod/falling":
					ap.play(&"mp_mod/falling")
			elif ap.current_animation == &"mp_mod/shoved" and ap.is_playing():
				ap.speed_scale = 1.0
			elif move_speed_vis > 0.35 and ap.has_animation(&"mp_mod/run"):
				ap.speed_scale = 1.15 + float(p["speed_level"]) * 0.14
				if ap.current_animation != &"mp_mod/run":
					ap.play(&"mp_mod/run", 0.10)
			elif ap.has_animation(&"mp_mod/idle"):
				ap.speed_scale = 1.0
				if ap.current_animation != &"mp_mod/idle":
					ap.play(&"mp_mod/idle", 0.12)

	for b_id in _bubble_nodes.keys():
		var bn: Node3D = _bubble_nodes[b_id]
		if is_instance_valid(bn):
			var progress: float = 0.0
			if _bubbles.has(b_id):
				var b: Dictionary = _bubbles[b_id]
				if not _is_server_sim:
					b["fuse"] = maxf(0.0, float(b["fuse"]) - delta)
				var base_pos: Vector3 = b["pos"]
				progress = clampf(1.0 - float(b["fuse"]) / C.BUBBLE_FUSE_SEC, 0.0, 1.0)
				var target_bpos: Vector3 = base_pos
				# High-frequency pressure tremor in the final 35% before detonation.
				if progress > 0.65:
					var shake: float = (progress - 0.65) * 0.14
					target_bpos += Vector3(sin(t * 62.0 + float(b_id)) * shake, 0.0, cos(t * 58.0 + float(b_id) * 1.7) * shake)
				bn.position = bn.position.lerp(target_bpos, clampf(delta * 22.0, 0.0, 1.0))

			# Escalating pressure swell + accelerating squash-and-stretch heartbeat (no numeric timer needed).
			var freq: float = lerpf(6.0, 26.0, progress * progress)
			var amp: float = lerpf(0.04, 0.16, progress)
			var swell: float = 1.0 + progress * progress * 0.22
			var wave: float = sin(t * freq + float(b_id))
			var sx: float = swell * (1.0 + wave * amp)
			var sy: float = swell * (1.0 - wave * amp * 0.85)
			bn.scale = Vector3(sx, sy, sx)

			# Accelerating warning beacon strobe & canister overheat glow.
			var blink_on: bool = sin(t * lerpf(8.0, 38.0, progress * progress)) > (0.15 - progress * 0.35)
			var beacon: MeshInstance3D = bn.get_node_or_null("FuseBeacon") as MeshInstance3D
			if beacon != null and beacon.material_override is StandardMaterial3D:
				var bmat: StandardMaterial3D = beacon.material_override
				bmat.emission_energy_multiplier = (4.2 if progress > 0.7 else 2.4) if blink_on else 0.15
				bmat.emission = Color(1.0, 0.72, 0.25) if (progress > 0.75 and blink_on) else Color(1.0, 0.16, 0.08)
			var body_m: MeshInstance3D = bn.get_node_or_null("CanisterBody") as MeshInstance3D
			if body_m != null and body_m.material_override is StandardMaterial3D:
				var cmat: StandardMaterial3D = body_m.material_override
				if progress > 0.55 and blink_on:
					cmat.emission_energy_multiplier = (progress - 0.55) * 2.4
				else:
					cmat.emission_energy_multiplier = 0.0

	for item_id in _item_nodes.keys():
		var inode: Node3D = _item_nodes[item_id]
		if is_instance_valid(inode):
			var spin: Node3D = inode.get_node_or_null("SpinMesh") as Node3D
			if spin != null:
				spin.rotation.y += delta * 2.6
				spin.position.y = C.TILE_SIZE * 0.42 + sin(t * 4.5 + float(item_id)) * 0.08
	_step_fx_pools(delta)


func player_disconnected(network_id: int) -> void:
	if _players.has(network_id):
		_eliminate_player(_players[network_id], 0, "DISCONNECTED")


func _compute_ai_input(p: Dictionary, delta: float) -> Dictionary:
	var cell: Vector2i = C.world_to_grid(p["pos"], _map_width, _map_height)
	var danger: Dictionary = {}
	for b_id in _bubbles.keys():
		var b: Dictionary = _bubbles[b_id]
		var orig: Vector2i = b["cell"]
		danger[orig] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for step in range(1, int(b["power"]) + 1):
				var c: Vector2i = orig + d * step
				if _is_tile_blocked(c):
					break
				danger[c] = true

	if danger.has(cell):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = cell + d
			if not _is_tile_blocked(nc) and _bubble_at_cell(nc) == -1 and not danger.has(nc):
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}

	# Rush adjacent downed rivals or adjacent pickups if safe.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = cell + d
		if _is_tile_blocked(nc) or _bubble_at_cell(nc) != -1 or danger.has(nc):
			continue
		for other_id in _players.keys():
			if int(other_id) == int(p["network_id"]):
				continue
			var op: Dictionary = _players[other_id]
			if bool(op["alive"]) and bool(op["trapped"]) and C.world_to_grid(op["pos"], _map_width, _map_height) == nc:
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}
		for item_id in _items.keys():
			if _items[item_id]["cell"] == nc:
				return {"dir": Vector2(float(d.x), float(d.y)), "drop": false}

	p["ai_cooldown"] = float(p["ai_cooldown"]) - delta
	var drop := false
	if float(p["ai_cooldown"]) <= 0.0:
		p["ai_cooldown"] = 0.55
		var open_dirs: Array = []
		var near_crate := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = cell + d
			if nc.x >= 0 and nc.y >= 0 and nc.x < _map_width and nc.y < _map_height:
				var t: int = int(_tiles[nc.y][nc.x])
				if t == C.TILE_CRATE or t == C.TILE_GOLD_CRATE:
					near_crate = true
				elif t == C.TILE_EMPTY and _bubble_at_cell(nc) == -1 and not danger.has(nc):
					open_dirs.append(d)
		if near_crate and open_dirs.size() >= 1 and int(p["active_bubbles"]) == 0:
			drop = true
		if not open_dirs.is_empty():
			var pick: Vector2i = open_dirs[_rng.randi_range(0, open_dirs.size() - 1)]
			p["ai_dir"] = Vector2(float(pick.x), float(pick.y))
		else:
			p["ai_dir"] = Vector2.ZERO

	return {"dir": p["ai_dir"], "drop": drop}


func _stage_screenshot_action() -> void:
	_banner_label.text = ""
	_time_remaining = 42.0
	_update_crt_monitor()
	_kill_feed_label.text = ""

	var cx: int = _map_width / 2
	var cy: int = _map_height / 2
	if _players.has(1):
		_players[1]["pos"] = C.grid_to_world(Vector2i(cx - 2, cy), _map_width, _map_height)
		_players[1]["facing"] = Vector2(1.0, 0.25)
		_players[1]["has_needle"] = true
		_players[1]["node"].position = _players[1]["pos"]
		_update_player_hud_3d(_players[1])
	if _players.has(2):
		_players[2]["pos"] = C.grid_to_world(Vector2i(cx + 2, cy), _map_width, _map_height)
		_players[2]["hp"] = 0
		_players[2]["trapped"] = true
		_players[2]["node"].position = _players[2]["pos"]
		_update_player_hud_3d(_players[2])
	if _players.has(3):
		_players[3]["pos"] = C.grid_to_world(Vector2i(cx, cy - 2), _map_width, _map_height)
		_players[3]["hp"] = 2
		_players[3]["node"].position = _players[3]["pos"]
		_update_player_hud_3d(_players[3])
	if _players.has(4):
		_players[4]["pos"] = C.grid_to_world(Vector2i(cx, cy + 2), _map_width, _map_height)
		_players[4]["hp"] = 1
		_players[4]["node"].position = _players[4]["pos"]
		_update_player_hud_3d(_players[4])

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := Vector2i(cx + dx, cy + dy)
			_tiles[c.y][c.x] = C.TILE_EMPTY
			if _tile_nodes.has(c):
				_tile_nodes[c].queue_free()
				_tile_nodes.erase(c)

	var b1: Node3D = M.build_water_bubble(C.TILE_SIZE, _players[1]["color"])
	b1.position = C.grid_to_world(Vector2i(cx - 1, cy), _map_width, _map_height)
	_arena_root.add_child(b1)

	var b2: Node3D = M.build_water_bubble(C.TILE_SIZE, _players[3]["color"])
	b2.position = C.grid_to_world(Vector2i(cx + 1, cy - 2), _map_width, _map_height)
	_arena_root.add_child(b2)

	_spawn_blast_visual([
		Vector2i(cx, cy), Vector2i(cx, cy - 1), Vector2i(cx, cy + 1), Vector2i(cx + 1, cy),
	], 1)

	# Showcase all 5 authentic Machine Party 3D pickups on the arena floor.
	_spawn_item(Vector2i(cx - 1, cy - 1), C.ITEM_POWER)
	_spawn_item(Vector2i(cx + 1, cy + 1), C.ITEM_NEEDLE)
	_spawn_item(Vector2i(cx - 1, cy + 1), C.ITEM_SPEED)
	_spawn_item(Vector2i(cx + 1, cy - 1), C.ITEM_KICK)
	_spawn_item(Vector2i(cx - 2, cy + 1), C.ITEM_BUBBLE)


func _save_screenshot_and_quit() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		var err: int = img.save_png(_screenshot_path)
		if err == OK:
			print("SCREENSHOT_SAVED: " + _screenshot_path)
		else:
			push_error("Failed to save screenshot: err=" + str(err))
	get_tree().quit()


func _run_self_test() -> void:
	_load_helpers()
	_is_server_sim = true
	_standalone_mode = true

	for count in [2, 4, 8, 16]:
		for theme in range(C.THEME_COUNT):
			var md: Dictionary = C.generate_map(count, theme, 1000 + count * 17 + theme)
			var tiles: Array = md["tiles"]
			var safe: Dictionary = md["safe"]
			for sc in safe.keys():
				var cell: Vector2i = sc
				if int(tiles[cell.y][cell.x]) != C.TILE_EMPTY:
					push_error("SELF_TEST_FAIL: spawn safe cell blocked for count=%d theme=%d" % [count, theme])
					get_tree().quit(1)
					return
			if theme == C.THEME_CONVEYOR and (md["conveyors"] as Dictionary).is_empty():
				push_error("SELF_TEST_FAIL: conveyor theme has no conveyor tiles")
				get_tree().quit(1)
				return

	var roster: Array = [
		{"id": 0, "network_id": 1, "nickname": "P1", "is_ai": false},
		{"id": 1, "network_id": 2, "nickname": "P2", "is_ai": false},
		{"id": 2, "network_id": 3, "nickname": "P3", "is_ai": false},
	]
	_setup_match_local(C.THEME_CLASSIC, 4242, roster, true)
	_intro_timer = 0.0
	_round_active = true

	var p1: Dictionary = _players[1]
	var p2: Dictionary = _players[2]

	_hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 2 or bool(p2["trapped"]):
		push_error("SELF_TEST_FAIL: expected 2 HP after first hit")
		get_tree().quit(1)
		return
	_hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 2:
		push_error("SELF_TEST_FAIL: invulnerability failed to block repeat hit")
		get_tree().quit(1)
		return
	p2["invuln_timer"] = 0.0
	_hit_player_by_blast(p2, 1)
	if int(p2["hp"]) != 1 or bool(p2["trapped"]):
		push_error("SELF_TEST_FAIL: expected 1 HP after second hit")
		get_tree().quit(1)
		return
	p2["has_needle"] = true
	p2["invuln_timer"] = 0.0
	_hit_player_by_blast(p2, 1)
	if not bool(p2["trapped"]) or not bool(p2["alive"]):
		push_error("SELF_TEST_FAIL: expected trapped state on 3rd hit")
		get_tree().quit(1)
		return
	_step_players(C.NEEDLE_AUTO_SAVE_DELAY_SEC + 0.1)
	if bool(p2["trapped"]) or int(p2["hp"]) != 1 or bool(p2["has_needle"]):
		push_error("SELF_TEST_FAIL: needle auto-rescue failed")
		get_tree().quit(1)
		return
	p2["invuln_timer"] = 0.0
	_hit_player_by_blast(p2, 1)
	p1["pos"] = p2["pos"] + Vector3(0.2, 0.0, 0.0)
	_step_players(0.05)
	if bool(p2["alive"]) or int(p1["pops"]) != 1:
		push_error("SELF_TEST_FAIL: bump-pop elimination failed")
		get_tree().quit(1)
		return

	p1["max_bubbles"] = 3
	p1["power"] = 3
	p1["pos"] = C.grid_to_world(Vector2i(1, 1), _map_width, _map_height)
	var ok1: bool = _try_place_bubble(p1)
	p1["pos"] = C.grid_to_world(Vector2i(2, 1), _map_width, _map_height)
	var ok2: bool = _try_place_bubble(p1)
	if not ok1 or not ok2 or _bubbles.size() != 2:
		push_error("SELF_TEST_FAIL: bubble placement failed")
		get_tree().quit(1)
		return
	var first_id: int = int(_bubbles.keys()[0])
	_detonate_bubble(first_id)
	if _bubbles.size() != 1:
		push_error("SELF_TEST_FAIL: staggered chain detonation should queue second bubble instead of same-frame recursion")
		get_tree().quit(1)
		return
	var second_id: int = int(_bubbles.keys()[0])
	if float(_bubbles[second_id]["fuse"]) > CHAIN_DETONATE_DELAY_SEC + 0.001:
		push_error("SELF_TEST_FAIL: chained bubble fuse not shortened")
		get_tree().quit(1)
		return
	_step_bubbles(CHAIN_DETONATE_DELAY_SEC + 0.02)
	if not _bubbles.is_empty():
		push_error("SELF_TEST_FAIL: chain detonation left residual bubbles")
		get_tree().quit(1)
		return
	# Verify blast cell visuals are pooled and returned cleanly after blast duration.
	var pooled_total_before: int = _blast_center_pool.size() + _blast_arm_pool.size() + _active_blast_visuals.size()
	_step_blasts(C.BLAST_DURATION_SEC + 0.05)
	if not _active_blast_visuals.is_empty() or (_blast_center_pool.size() + _blast_arm_pool.size()) != pooled_total_before:
		push_error("SELF_TEST_FAIL: blast cell pool leak detected")
		get_tree().quit(1)
		return

	var scores: Dictionary = C.compute_rank_scores([
		{"network_id": 1, "alive": true, "elim_time": 75.0, "pops": 2, "traps": 2},
		{"network_id": 2, "alive": false, "elim_time": 40.0, "pops": 1, "traps": 1},
		{"network_id": 3, "alive": false, "elim_time": 25.0, "pops": 0, "traps": 0},
	])
	if int(scores[1]) != 3 or int(scores[2]) != 2 or int(scores[3]) != 1:
		push_error("SELF_TEST_FAIL: unexpected rank scores " + str(scores))
		get_tree().quit(1)
		return

	# Verify diagonal wall-sliding keeps full speed without sticky slowdown.
	var wall_start: Vector3 = C.grid_to_world(Vector2i(1, 1), _map_width, _map_height)
	wall_start.x -= C.TILE_SIZE * 0.19 # Flush against left border wall at x=0
	p1["pos"] = wall_start
	var diag_dir := Vector2(-1.0, 1.0).normalized()
	var after_slide: Vector3 = _move_player_with_collision(p1, wall_start, Vector3(diag_dir.x, 0.0, diag_dir.y) * C.BASE_MOVE_SPEED, C.BASE_MOVE_SPEED, 0.1)
	if (after_slide.z - wall_start.z) < C.BASE_MOVE_SPEED * 0.1 * 0.95:
		push_error("SELF_TEST_FAIL: wall-slide speed drop detected: dz=" + str(after_slide.z - wall_start.z))
		get_tree().quit(1)
		return

	# Verify placing a bomb right in another player's face on open ground does not trap them.
	p1["active_bubbles"] = 0
	p1["max_bubbles"] = 2
	p2["alive"] = true
	p2["trapped"] = false
	p2["pass_bubble_ids"] = {}
	var open_cell := Vector2i(1, 1)
	var open_pos: Vector3 = C.grid_to_world(open_cell, _map_width, _map_height)
	p1["pos"] = open_pos
	p2["pos"] = open_pos + Vector3(C.TILE_SIZE * 0.45, 0.0, 0.0)
	if not _try_place_bubble(p1):
		push_error("SELF_TEST_FAIL: face-drop test failed to place bubble")
		get_tree().quit(1)
		return
	var p2_before: Vector3 = p2["pos"]
	var p2_after: Vector3 = _move_player_with_collision(p2, p2_before, Vector3(C.BASE_MOVE_SPEED, 0.0, 0.0), C.BASE_MOVE_SPEED, 0.1)
	if (p2_after.x - p2_before.x) < C.BASE_MOVE_SPEED * 0.1 * 0.9:
		push_error("SELF_TEST_FAIL: player trapped by face-dropped bubble: dx=" + str(p2_after.x - p2_before.x))
		get_tree().quit(1)
		return
	# Also verify defensive escape when already inside collision radius without pass-through.
	p2["pass_bubble_ids"] = {}
	p2["pos"] = p2_before
	var p2_escape: Vector3 = _move_player_with_collision(p2, p2_before, Vector3(C.BASE_MOVE_SPEED, 0.0, 0.0), C.BASE_MOVE_SPEED, 0.1)
	if (p2_escape.x - p2_before.x) < C.BASE_MOVE_SPEED * 0.1 * 0.9:
		push_error("SELF_TEST_FAIL: player could not escape bubble overlap: dx=" + str(p2_escape.x - p2_before.x))
		get_tree().quit(1)
		return

	# Verify single drop press while crossing tile boundary places only 1 bomb (never double-drops).
	for b_id in _bubbles.keys():
		if _bubble_nodes.has(b_id) and is_instance_valid(_bubble_nodes[b_id]):
			_bubble_nodes[b_id].queue_free()
	_bubbles.clear()
	_bubble_nodes.clear()
	p1["active_bubbles"] = 0
	p1["max_bubbles"] = 3
	p1["pos"] = C.grid_to_world(Vector2i(1, 1), _map_width, _map_height) + Vector3(C.TILE_SIZE * 0.45, 0.0, 0.0)
	_client_inputs[1] = {"dir": Vector2(1.0, 0.0), "drop": true}
	for _f in range(6):
		_step_players(1.0 / 60.0)
	if _bubbles.size() != 1:
		push_error("SELF_TEST_FAIL: single drop press spawned %d bubbles instead of 1" % _bubbles.size())
		get_tree().quit(1)
		return
	_client_inputs.clear()

	print("BUBBLE_BLITZ_THEMES_VERIFIED=4, HYBRID_3HP_NEEDLE_POP_OK, CHAIN_DETONATION_OK, WALL_SLIDE_FULL_SPEED_OK, FACE_BOMB_NO_TRAP_OK, SINGLE_DROP_OK")
	print("SELF_TEST_PASSED")
	get_tree().quit(0)
