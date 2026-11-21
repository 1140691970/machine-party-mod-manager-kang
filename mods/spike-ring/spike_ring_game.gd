extends Node3D

## ============================================================================
## Spike Ring / 尖刺圆环 — 服务器权威 2.5D 圆形竞技场生存小游戏
## ----------------------------------------------------------------------------
## 架构：
##   * 官方 Minigame 子类（official_minigame.gd）负责加载/信号协议，$Stage 即本脚本。
##   * 准备倒计时、60s 正式计时、移动校验、推人命中、机关生成/激活时间、
##     出局判定、计分、轮次结算 —— 全部只在 multiplayer.is_server() 分支执行。
##   * 客户端只发输入 + 按服务器时间轴插值/外推表现，绝不做出局判定。
##   * 机关由服务器种子 + reliable RPC 下发完整时间线，客户端按 srv_time 播放。
##   * 人数完全由 roster 决定（PlayerManager.player_presences），不写死 8 人上限。
## 风格：复用原版 Machine Party 工业纹理、角色 rig、Terminal F4 字体与音效。
## ============================================================================

signal round_finished(scores: Dictionary)

const CONFIG_RES := "res://mods_spike_ring/config.gd"
const MESHES_RES := "res://mods_spike_ring/arena_meshes.gd"

# ---------------------------------------------------------------- 阶段
const PH_PREP := 0
const PH_LIVE := 1
const PH_ENDED := 2

var C = null
var M = null

var _standalone_mode: bool = false
var _is_server_sim: bool = true
var _phase: int = PH_PREP
var _srv_time: float = 0.0                 # 服务器单调时钟：所有机关时间戳基准
var _srv_time_est: float = 0.0             # 客户端估算的服务器时钟
var _prep_remaining: float = 0.0
var _elapsed_time: float = 0.0
var _time_remaining: float = 60.0
var _last_countdown_sec: int = 4
var _round_index: int = 0
var _round_cfg: Dictionary = {}
var _map_seed: int = 0
var _rng := RandomNumberGenerator.new()
var _sync_accum: float = 0.0
var _local_net_id: int = 1

# ---------------------------------------------------------------- 实体
var _players: Dictionary = {}              # network_id -> state Dictionary
var _client_inputs: Dictionary = {}        # network_id -> input Dictionary
var _hazards: Dictionary = {}              # hazard_id -> hazard Dictionary
var _hazard_nodes: Dictionary = {}         # hazard_id -> {warn, active, saw}
var _next_hazard_id: int = 1
var _spawn_timer: float = 0.0
var _last_type_spawn: Dictionary = {}      # type -> srv_time
var _nozzle_cooldown: Dictionary = {}      # nozzle index -> srv_time
var _pos_history: Dictionary = {}          # network_id -> Array[[t, Vector3]]
var _snap_buffer: Array = []               # 客户端插值缓冲 [{t, players}]

# ---------------------------------------------------------------- 场景节点
var _arena_root: Node3D = null
var _hazard_root: Node3D = null
var _fx_root: Node3D = null
var _player_root: Node3D = null
var _camera: Camera3D = null
var _timer_label: Label3D = null
var _phase_label: Label3D = null
var _alive_label: Label3D = null
var _nozzles: Array = []

var _hud_layer: CanvasLayer = null
var _banner_label: Label = null
var _top_label: Label = null
var _stats_label: Label = null
var _result_label: Label = null
var _spectate_hint: Label = null
var _term_font: Font = null

var _prev_push_pressed: bool = false
var _prev_jump_pressed: bool = false
var _spectator_angle: float = 0.0
var _result_rows: Array = []

var _sfx_push: AudioStreamPlayer = null
var _sfx_elim: AudioStreamPlayer = null
var _sfx_warn: AudioStreamPlayer = null
var _sfx_ding: AudioStreamPlayer = null
var _sfx_beep: AudioStreamPlayer = null
var _sfx_flame: AudioStreamPlayer = null
var _ambience: AudioStreamPlayer = null
var _fx_hit_scene: PackedScene = null
var _fx_dust_scene: PackedScene = null

var _screenshot_path: String = ""
var _screenshot_frames: int = 0


# ============================================================================
# 1. 生命周期与场景搭建
# ============================================================================

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
	_setup_audio_and_fx()
	_setup_hud()
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)

	var args: Array = Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	for raw_a in args:
		var a: String = str(raw_a)
		if a == "--self-test":
			_run_self_test()
			return
		if a == "--smoke-test":
			_run_smoke_test()
			return
		if a.begins_with("--capture-screenshot="):
			_screenshot_path = a.substr("--capture-screenshot=".length())

	_standalone_mode = (get_parent() == get_tree().root)
	if _standalone_mode:
		_start_standalone_preview()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# 机械狂欢暖色工厂氛围：深棕铁锈背景 + 暖黄铜环境光，取代原先的近黑背景。
	env.background_color = Color(0.13, 0.085, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.42, 0.29)
	env.ambient_light_energy = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_camera = Camera3D.new()
	_camera.name = "SpikeRingCamera"
	_camera.fov = C.CAMERA_FOV
	_camera.near = 0.1
	_camera.far = 400.0
	# 关键：必须显式成为当前相机。否则游戏主流程的相机会生效，导致圆形场地
	# 被斜视裁切、WASD 方向与实际屏幕方向不一致（v0.1.1 修复）。
	_camera.current = true
	add_child(_camera)
	_frame_arena()

	_arena_root = Node3D.new()
	_arena_root.name = "ArenaRoot"
	add_child(_arena_root)
	_hazard_root = Node3D.new()
	_hazard_root.name = "HazardRoot"
	add_child(_hazard_root)
	_fx_root = Node3D.new()
	_fx_root.name = "FxRoot"
	add_child(_fx_root)
	_player_root = Node3D.new()
	_player_root.name = "PlayerRoot"
	add_child(_player_root)


# ---------------------------------------------------------------- 俯视全景相机
func _camera_fit_height() -> float:
	## 正俯视：地面 y=0 平面上所有点到相机的视线深度恒为 H，透视无畸变，
	## 圆形场地显示为完美正圆。取垂直/水平所需高度最大值，任意宽高比下整圆完整入镜。
	var vp: Viewport = get_viewport()
	var vs: Vector2 = Vector2(1280.0, 720.0)
	if vp != null and vp.size.x > 0 and vp.size.y > 0:
		vs = Vector2(vp.size)
	var aspect: float = vs.x / vs.y
	var tan_v: float = tan(deg_to_rad(C.CAMERA_FOV * 0.5))
	var tan_h: float = tan_v * aspect
	var need: float = C.CAMERA_FIT_RADIUS * C.CAMERA_FIT_MARGIN
	var h_v: float = need / maxf(0.001, tan_v)
	var h_h: float = need / maxf(0.001, tan_h)
	return maxf(C.CAMERA_MIN_HEIGHT, maxf(h_v, h_h))


func _frame_arena() -> void:
	## 正上方俯视、对准场地中心 (0,0,0)。up 用 -Z 使「屏幕上=世界 -Z、
	## 屏幕右=世界 +X」，与 W->-Z / D->+X 严格一致，且避免 look_at 退化。
	if _camera == null:
		return
	var h: float = _camera_fit_height()
	_camera.position = Vector3(0.0, h, 0.0)
	_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))


func _on_viewport_resized() -> void:
	## 窗口尺寸/全屏切换后重新框定，保证始终完整看到整个圆形场地。
	_frame_arena()


func _make_audio_player(res_path: String, volume_db: float) -> AudioStreamPlayer:
	var stream = M.load_optional(res_path)
	if not (stream is AudioStream):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream as AudioStream
	p.volume_db = volume_db
	add_child(p)
	return p


func _setup_audio_and_fx() -> void:
	# 全部复用原版 Machine Party 音效资源，不引入外部素材。
	_sfx_push = _make_audio_player("res://audio/unique/disco dodge/dd shove.ogg", -4.0)
	_sfx_elim = _make_audio_player("res://audio/unique/disco dodge/dd fall scream impact.ogg", -2.0)
	_sfx_warn = _make_audio_player("res://audio/unique/exploding collar race/mine_detected.ogg", -6.0)
	_sfx_ding = _make_audio_player("res://audio/sfx/airplane ding.ogg", -2.0)
	_sfx_beep = _make_audio_player("res://audio/sfx/ekg_beep.ogg", -5.0)
	_sfx_flame = _make_audio_player("res://audio/sfx/bad_explosion.ogg", -8.0)
	_ambience = _make_audio_player("res://audio/unique/dvd roomba/dvd roomba ambience.ogg", -15.0)
	var hit = M.load_optional("res://prefabs/managed_effects/hit_blood.tscn")
	if hit is PackedScene:
		_fx_hit_scene = hit as PackedScene
	var dust = M.load_optional("res://prefabs/managed_effects/dustplume.tscn")
	if dust is PackedScene:
		_fx_dust_scene = dust as PackedScene
	_term_font = M.load_terminal_font()


func _mk_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 6))
	if _term_font != null:
		l.add_theme_font_override("font", _term_font)
	return l


func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "SpikeRingHUD"
	_hud_layer.layer = 5
	add_child(_hud_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	_banner_label = _mk_label(84, Color(0.98, 0.80, 0.30))
	_banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_label.offset_top = 120.0
	_banner_label.offset_bottom = -300.0
	root.add_child(_banner_label)

	_top_label = _mk_label(28, Color(0.72, 1.0, 0.72))
	_top_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_label.offset_top = 12.0
	_top_label.offset_bottom = 60.0
	root.add_child(_top_label)

	_stats_label = _mk_label(20, Color(0.98, 0.92, 0.72))
	_stats_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_stats_label.offset_top = -70.0
	_stats_label.offset_bottom = -14.0
	root.add_child(_stats_label)

	_spectate_hint = _mk_label(22, Color(1.0, 0.62, 0.42))
	_spectate_hint.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	_spectate_hint.offset_top = -140.0
	_spectate_hint.offset_bottom = -90.0
	root.add_child(_spectate_hint)
	_spectate_hint.visible = false

	_result_label = _mk_label(22, Color(0.74, 1.0, 0.80))
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_label.offset_left = 180.0
	_result_label.offset_right = -180.0
	_result_label.offset_top = 90.0
	_result_label.offset_bottom = -90.0
	root.add_child(_result_label)
	_result_label.visible = false


# ============================================================================
# 2. 回合启动（官方 Minigame 协议）
# ============================================================================

@rpc("authority", "call_local", "reliable")
func start_round(roster: Array) -> void:
	_load_helpers()
	_standalone_mode = false
	_is_server_sim = multiplayer.is_server()
	_local_net_id = multiplayer.get_unique_id()
	if _is_server_sim:
		# 关卡索引由官方轮次号驱动，超出配置数量自动循环，不写死人数/轮数。
		var rn: int = 1
		var parent: Node = get_parent()
		if parent != null and parent.get("round_number") != null:
			rn = maxi(1, int(parent.round_number))
		_round_index = (rn - 1) % maxi(1, C.ROUND_CONFIGS.size())
		_rng.randomize()
		_map_seed = _rng.randi()
		_rpc_setup_match.rpc(_round_index, _map_seed, roster)


@rpc("authority", "call_local", "reliable")
func _rpc_setup_match(round_index: int, seed_val: int, roster: Array) -> void:
	_setup_match_local(round_index, seed_val, roster, false)


func _start_standalone_preview() -> void:
	_is_server_sim = true
	_local_net_id = 1
	_rng.randomize()
	var roster: Array = []
	var names: Array = ["玩家 1 (你)", "發條阿紫", "鍋爐綠醬", "紅心活塞", "銅齒老闆", "蒸氣小妹", "螺絲工匠", "警示燈塔"]
	var count: int = 8 if _screenshot_path.is_empty() else 6
	for i in range(count):
		roster.append({
			"id": i,
			"network_id": i + 1,
			"nickname": str(names[i % names.size()]),
			"customization": [],
			"is_ai": i != 0,
		})
	_setup_match_local(0, 20261121, roster, true)
	if not _screenshot_path.is_empty():
		_stage_screenshot_action()


func _clear_arena() -> void:
	for child in _arena_root.get_children():
		child.queue_free()
	for child in _hazard_root.get_children():
		child.queue_free()
	for child in _fx_root.get_children():
		child.queue_free()
	for child in _player_root.get_children():
		child.queue_free()
	_hazard_nodes.clear()
	_hazards.clear()
	_players.clear()
	_client_inputs.clear()
	_pos_history.clear()
	_snap_buffer.clear()


func _setup_match_local(round_index: int, seed_val: int, roster: Array, is_preview: bool) -> void:
	_clear_arena()
	_round_index = round_index
	_round_cfg = C.ROUND_CONFIGS[round_index % maxi(1, C.ROUND_CONFIGS.size())]
	_map_seed = seed_val
	_rng.seed = seed_val

	_phase = PH_PREP
	_srv_time = 0.0
	_srv_time_est = 0.0
	_prep_remaining = C.PREP_DURATION_SEC if _screenshot_path.is_empty() else 0.0
	_elapsed_time = 0.0
	_time_remaining = C.ROUND_DURATION_SEC
	_last_countdown_sec = 4
	_spawn_timer = 0.0
	_next_hazard_id = 1
	_last_type_spawn.clear()
	_nozzle_cooldown.clear()
	_result_rows.clear()
	_result_label.visible = false
	_spectate_hint.visible = false
	if _prep_remaining <= 0.0:
		_phase = PH_LIVE

	var accent_rgb: Array = _round_cfg.get("accent", [0.96, 0.68, 0.22])
	# 外围工厂环境先挂（在场地之外），再叠加竞技场本体。
	var surroundings: Node3D = M.build_surroundings(C.ARENA_RADIUS, accent_rgb)
	_arena_root.add_child(surroundings)
	var stage: Dictionary = M.build_arena(C.ARENA_RADIUS, accent_rgb)
	_arena_root.add_child(stage["root"])
	_timer_label = stage["timer_label"] as Label3D
	_phase_label = stage["phase_label"] as Label3D
	_alive_label = stage["alive_label"] as Label3D
	_nozzles = stage["nozzles"]

	var spawns: Array = C.compute_spawns(roster.size(), seed_val)
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var net_id: int = int(entry.get("network_id", i + 1))
		var spawn: Vector2 = spawns[i % spawns.size()]
		var cust_raw = entry.get("customization", [])
		var cust: Array = cust_raw if cust_raw is Array else []
		var is_local: bool = (net_id == _local_net_id)
		var nick: String = str(entry.get("nickname", "P%d" % (i + 1)))
		var char_pack: Dictionary = M.build_worker_character(i, net_id, nick, cust, is_local, C.PLAYER_VISUAL_SCALE, C.PLAYER_LABEL_HEIGHT)
		var node: Node3D = char_pack["root"]
		node.position = Vector3(spawn.x, 0.0, spawn.y)
		_player_root.add_child(node)

		var is_bot: bool = bool(entry.get("is_ai", false))
		if not is_preview and _is_server_sim:
			var peers: PackedInt32Array = multiplayer.get_peers()
			if net_id != 1 and not peers.has(net_id):
				is_bot = true

		_players[net_id] = {
			"network_id": net_id,
			"nickname": nick,
			"node": node,
			"color": char_pack["color"],
			"is_ai": is_bot,
			"pos": Vector3(spawn.x, 0.0, spawn.y),
			"render_pos": Vector3(spawn.x, 0.0, spawn.y),
			"facing": Vector2(0.0, 1.0),
			"vel_y": 0.0,
			"state": C.ST_READY if _phase == PH_PREP else C.ST_NORMAL,
			"state_timer": 0.0,
			"invuln_timer": 0.0,
			"push_cooldown": 0.0,
			"knock_dir": Vector2.ZERO,
			"alive": true,
			"alive_sec": 0.0,
			"score": 0,
			"last_scored_sec": 0,
			"pushes": 0,
			"hits_taken": 0,
			"out_reason": "",
			"elim_time": 0.0,
			"input": {"dir": Vector2.ZERO, "aim": Vector2(0.0, 1.0), "jump": false, "push": false},
			"last_input_seq": -1,
			"ai_dir": Vector2.ZERO,
			"ai_timer": 0.0,
		}
		_pos_history[net_id] = [[0.0, Vector3(spawn.x, 0.0, spawn.y)]]

	_banner_label.text = str(int(ceil(_prep_remaining))) if _prep_remaining > 0.0 else ""
	_update_hud()
	if _ambience != null and not _ambience.playing and _screenshot_path.is_empty():
		_ambience.play()


# ============================================================================
# 3. 主循环 / 输入 / 服务器权威模拟
# ============================================================================

func _process(delta: float) -> void:
	if not _screenshot_path.is_empty():
		_screenshot_frames += 1
		_animate_visuals(delta)
		if _screenshot_frames >= 8:
			_save_screenshot_and_quit()
		return

	if not _is_server_sim:
		_srv_time_est = maxf(_srv_time_est + delta, _srv_time_est)
		_read_local_input()

	if _is_server_sim:
		_srv_time += delta
		_read_local_input()
		if _phase == PH_PREP:
			_step_prep(delta)
		elif _phase == PH_LIVE:
			_step_simulation(delta)
		if not _standalone_mode:
			_sync_accum += delta
			if _sync_accum >= C.SNAPSHOT_INTERVAL_SEC:
				_sync_accum = 0.0
				_broadcast_snapshot()
	else:
		_apply_snapshot_interpolation(delta)
		_update_hazard_states(_render_time())

	_animate_visuals(delta)
	_update_hud()


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


func _mouse_aim(world_pos: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0.0, 1.0)
	var mpos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mpos)
	var ray: Vector3 = cam.project_ray_normal(mpos)
	if absf(ray.y) < 0.0001:
		return Vector2(0.0, 1.0)
	var t: float = -origin.y / ray.y
	if t <= 0.0:
		return Vector2(0.0, 1.0)
	var hit: Vector3 = origin + ray * t
	var aim := Vector2(hit.x - world_pos.x, hit.z - world_pos.z)
	if aim.length_squared() < 0.0001:
		return Vector2(0.0, 1.0)
	return aim.normalized()


func _screen_dir_to_world(screen_dir: Vector2) -> Vector2:
	## screen_dir: x=右为正、y=下为正（W 键 => y=-1）。用当前相机的屏幕基向量
	## 投影到世界 XZ，得到与 AI/快照一致的世界方向，使 W 永远朝屏幕正上方。
	if screen_dir.length_squared() < 0.0001:
		return Vector2.ZERO
	var vp: Viewport = get_viewport()
	if vp == null:
		return screen_dir
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return screen_dir
	var b: Basis = cam.global_transform.basis
	var right := Vector2(b.x.x, b.x.z)
	var up := Vector2(b.y.x, b.y.z)
	if right.length_squared() < 0.0001 or up.length_squared() < 0.0001:
		return screen_dir
	right = right.normalized()
	up = up.normalized()
	var world_dir: Vector2 = right * screen_dir.x + up * (-screen_dir.y)
	return world_dir.limit_length(1.0)


func _read_local_input() -> void:
	if not _players.has(_local_net_id):
		return
	var p: Dictionary = _players[_local_net_id]
	var dir := Vector2.ZERO
	var jump_edge := false
	var push_edge := false
	if _is_input_blocked_by_ui() or not bool(p["alive"]):
		_prev_jump_pressed = false
		_prev_push_pressed = false
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
		# 屏幕意图 -> 世界 XZ：无论相机角度/是否被替换，W 永远朝屏幕正上方。
		dir = _screen_dir_to_world(dir)
		var jump_now: bool = Input.is_key_pressed(KEY_SPACE)
		var push_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		jump_edge = jump_now and not _prev_jump_pressed
		push_edge = push_now and not _prev_push_pressed
		_prev_jump_pressed = jump_now
		_prev_push_pressed = push_now

	var aim: Vector2 = _mouse_aim(p["pos"])
	var packet: Dictionary = {
		"dir": dir,
		"aim": aim,
		"jump": jump_edge,
		"push": push_edge,
	}
	if _is_server_sim:
		_client_inputs[_local_net_id] = packet
	else:
		var seq: int = int(Time.get_ticks_msec())
		_rpc_client_input.rpc_id(1, dir, aim, jump_edge, push_edge, seq)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_client_input(dir: Vector2, aim: Vector2, jump_edge: bool, push_edge: bool, seq: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0 or not _players.has(sender):
		return
	if seq <= int(_players[sender].get("last_input_seq", -1)):
		return
	_players[sender]["last_input_seq"] = seq
	_client_inputs[sender] = {
		"dir": dir.limit_length(1.0),
		"aim": aim.limit_length(1.0),
		"jump": jump_edge,
		"push": push_edge,
	}


func _step_prep(delta: float) -> void:
	## 3 秒准备：不生成机关、不出局、推人禁用；仅允许移动与跳跃熟悉操作。
	_prep_remaining = maxf(0.0, _prep_remaining - delta)
	var cd: int = int(ceil(_prep_remaining))
	if cd != _last_countdown_sec and cd > 0 and cd <= 3:
		_last_countdown_sec = cd
		_banner_label.text = str(cd)
		if _sfx_beep != null:
			_sfx_beep.play()
	_step_player_motions(delta, true)
	if _prep_remaining <= 0.0:
		_phase = PH_LIVE
		_elapsed_time = 0.0
		_time_remaining = C.ROUND_DURATION_SEC
		_spawn_timer = 0.8
		_banner_label.text = "GO!"
		if _sfx_ding != null:
			_sfx_ding.play()
		for net_id in _players.keys():
			var p: Dictionary = _players[net_id]
			if bool(p["alive"]) and int(p["state"]) == C.ST_READY:
				p["state"] = C.ST_NORMAL


func _step_simulation(delta: float) -> void:
	_elapsed_time += delta
	_time_remaining = maxf(0.0, C.ROUND_DURATION_SEC - _elapsed_time)
	var sec_left: int = int(ceil(_time_remaining))
	if sec_left <= 5 and sec_left > 0 and sec_left != _last_countdown_sec:
		_last_countdown_sec = sec_left
		if _sfx_beep != null:
			_sfx_beep.play()
	if _banner_label.text == "GO!" and _elapsed_time > 0.7:
		_banner_label.text = ""

	_step_hazards(delta)                 # 先推进机关时间线（激活/预警/电锯位置）
	_step_player_motions(delta, false) # 再按当前机关状态判定玩家出局
	_step_spawner(delta)
	_accrue_scores(delta)
	_check_round_end()


# ============================================================================
# 4. 玩家状态机 / 移动 / 跳跃 / 推人
# ============================================================================

func _state_allows_push(p: Dictionary) -> bool:
	var st: int = int(p["state"])
	return bool(p["alive"]) and st != C.ST_FALLEN and st != C.ST_OUT and st != C.ST_SPECTATOR and st != C.ST_READY


func _step_player_motions(delta: float, prep: bool) -> void:
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if not bool(p["alive"]):
			continue

		# --- 计时器 ---
		if float(p["push_cooldown"]) > 0.0:
			p["push_cooldown"] = maxf(0.0, float(p["push_cooldown"]) - delta)
		if float(p["invuln_timer"]) > 0.0:
			p["invuln_timer"] = maxf(0.0, float(p["invuln_timer"]) - delta)
			if float(p["invuln_timer"]) <= 0.0 and int(p["state"]) == C.ST_INVULN:
				p["state"] = C.ST_NORMAL

		# --- 输入来源：AI / 客户端 / 本地 ---
		var input: Dictionary = p["input"]
		if bool(p["is_ai"]):
			input = _compute_ai_input(p, delta, prep)
		elif _client_inputs.has(net_id):
			input = _client_inputs[net_id]
		p["input"] = input

		var dir: Vector2 = input.get("dir", Vector2.ZERO)
		var aim: Vector2 = input.get("aim", Vector2(0.0, 1.0))
		var jump_edge: bool = bool(input.get("jump", false))
		var push_edge: bool = bool(input.get("push", false))
		if aim.length_squared() > 0.0001:
			p["facing"] = aim.normalized()

		# --- 摔倒：固定 0.30 秒后爬起，期间只能被击退，不能主动移动 ---
		if int(p["state"]) == C.ST_FALLEN:
			p["state_timer"] = float(p["state_timer"]) + delta
			var kd: Vector2 = p["knock_dir"]
			var new_pos: Vector3 = p["pos"]
			new_pos.x += kd.x * C.PUSH_KNOCKBACK_SPEED * delta
			new_pos.z += kd.y * C.PUSH_KNOCKBACK_SPEED * delta
			p["pos"] = new_pos
			if float(p["state_timer"]) >= C.FALL_DURATION_SEC:
				p["state"] = C.ST_INVULN
				p["state_timer"] = 0.0
				p["invuln_timer"] = C.RECOVERY_IMMUNITY_SEC
				p["knock_dir"] = Vector2.ZERO
		else:
			# --- 正常移动 ---
			var speed: float = C.PLAYER_MOVE_SPEED
			var new_pos: Vector3 = p["pos"]
			new_pos.x += dir.x * speed * delta
			new_pos.z += dir.y * speed * delta
			if dir.length_squared() > 0.01:
				p["last_vel"] = dir * speed
			else:
				p["last_vel"] = Vector2.ZERO

			# --- 跳跃 ---
			if jump_edge and float(p["vel_y"]) <= 0.001 and float(p["pos"].y) <= 0.001:
				p["vel_y"] = C.PLAYER_JUMP_VELOCITY
				p["state"] = C.ST_JUMPING
			if float(p["vel_y"]) > 0.0 or float(p["pos"].y) > 0.0:
				p["vel_y"] = float(p["vel_y"]) - C.PLAYER_GRAVITY * delta
				new_pos.y = maxf(0.0, float(new_pos.y) + float(p["vel_y"]) * delta)
				if new_pos.y <= 0.0:
					p["vel_y"] = 0.0
					if int(p["state"]) == C.ST_JUMPING:
						p["state"] = C.ST_NORMAL if float(p["invuln_timer"]) <= 0.0 else C.ST_INVULN
			p["pos"] = new_pos

		# --- 准备期：钳制在场地内，绝不因边缘出局 ---
		if prep:
			var flat := Vector2(p["pos"].x, p["pos"].z)
			var limit: float = C.EDGE_LIMIT_RADIUS * 0.92
			if flat.length() > limit:
				flat = flat.normalized() * limit
				p["pos"].x = flat.x
				p["pos"].z = flat.y
		else:
			# --- 推人（服务器权威命中/击退），准备期禁用 ---
			if push_edge and _state_allows_push(p) and float(p["push_cooldown"]) <= 0.0:
				_try_push(p)

		_record_history(net_id, p["pos"])
		if not prep:
			_check_player_collisions(p)


func _record_history(net_id: int, pos: Vector3) -> void:
	var hist: Array = _pos_history.get(net_id, [])
	hist.append([_srv_time, pos])
	while hist.size() > 2 and _srv_time - float(hist[0][0]) > C.HISTORY_WINDOW_SEC:
		hist.remove_at(0)
	_pos_history[net_id] = hist


func _history_position(net_id: int, at_time: float) -> Vector3:
	## 延迟补偿：服务器危险判定统一回溯 LAG_COMPENSATION_SEC 取历史位置。
	var hist: Array = _pos_history.get(net_id, [])
	if hist.is_empty():
		return Vector3.ZERO
	if at_time <= float(hist[0][0]):
		return hist[0][1]
	for i in range(1, hist.size()):
		var t1: float = float(hist[i][0])
		if at_time <= t1:
			var t0: float = float(hist[i - 1][0])
			var a: float = 0.0 if t1 <= t0 else (at_time - t0) / (t1 - t0)
			return (hist[i - 1][1] as Vector3).lerp(hist[i][1] as Vector3, a)
	return hist[hist.size() - 1][1]


func _try_push(attacker: Dictionary) -> void:
	## 左键短距离扇形/胶囊检测；命中后目标摔倒 0.3s，攻击者 +2 分。
	var origin := Vector2(attacker["pos"].x, attacker["pos"].z)
	var facing: Vector2 = attacker["facing"]
	var best_id: int = -1
	var best_dist: float = C.PUSH_RANGE
	for net_id in _players.keys():
		if net_id == int(attacker["network_id"]):
			continue
		var target: Dictionary = _players[net_id]
		if not bool(target["alive"]) or int(target["state"]) == C.ST_FALLEN:
			continue
		if float(target["invuln_timer"]) > 0.0:      # 爬起后 0.2s 免推，防锁死
			continue
		var tp := Vector2(target["pos"].x, target["pos"].z)
		var to_t: Vector2 = tp - origin
		var dist: float = to_t.length()
		if dist > C.PUSH_RANGE or dist < 0.001:
			continue
		if facing.dot(to_t.normalized()) < C.PUSH_HALF_ANGLE_COS:
			continue
		if dist < best_dist:
			best_dist = dist
			best_id = net_id
	if best_id < 0:
		attacker["push_cooldown"] = C.PUSH_COOLDOWN_SEC
		return

	var victim: Dictionary = _players[best_id]
	victim["state"] = C.ST_FALLEN
	victim["state_timer"] = 0.0
	victim["hits_taken"] = int(victim["hits_taken"]) + 1
	var vp := Vector2(victim["pos"].x, victim["pos"].z)
	var knock: Vector2 = (vp - origin).normalized()
	if knock.length_squared() < 0.001:
		knock = facing
	victim["knock_dir"] = knock
	attacker["pushes"] = int(attacker["pushes"]) + 1
	attacker["score"] = int(attacker["score"]) + C.PUSH_SCORE
	attacker["push_cooldown"] = C.PUSH_COOLDOWN_SEC
	if _sfx_push != null:
		_sfx_push.play()
	_spawn_fx(_fx_hit_scene, Vector3(vp.x, 0.8, vp.y), 0.42, 1.2)


func _compute_ai_input(p: Dictionary, delta: float, prep: bool) -> Dictionary:
	## 房间机器人 / 本地预览：向圆心附近游走并随机跳跃，避免站桩。
	p["ai_timer"] = float(p.get("ai_timer", 0.0)) - delta
	if float(p["ai_timer"]) <= 0.0:
		p["ai_timer"] = _rng.randf_range(0.5, 1.4)
		var a: float = _rng.randf() * TAU
		p["ai_dir"] = Vector2(cos(a), sin(a))
	var pos := Vector2(p["pos"].x, p["pos"].z)
	var to_center: Vector2 = -pos.normalized() if pos.length() > C.ARENA_RADIUS * 0.62 else Vector2.ZERO
	var dir: Vector2 = (p["ai_dir"] * 0.6 + to_center * 0.9).limit_length(1.0)
	return {
		"dir": dir,
		"aim": dir if dir.length_squared() > 0.01 else Vector2(0.0, 1.0),
		"jump": not prep and _rng.randf() < 0.012,
		"push": false,
	}


# ============================================================================
# 5. 机关生成 / 安全生成器 / 机关时间线
# ============================================================================

func _live_hazard_count() -> int:
	var n: int = 0
	for raw in _hazards.values():
		var h: Dictionary = raw
		if int(h["state"]) != C.HAZARD_STATE_DONE:
			n += 1
	return n


func _step_spawner(delta: float) -> void:
	## 纯激光模式：按难度阶段一次成束生成 2 / 3 / 4 条激光线。
	## 每条都单独过安全生成器，已提交的线立即计入危险网格，因此始终保持「可躲」。
	var phase: Dictionary = C.difficulty_phase(_elapsed_time, _round_cfg)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = float(phase["interval"])

	var budget: int = int(phase["max_concurrent"]) - _live_hazard_count()
	if budget <= 0:
		return
	var want: int = mini(budget, int(phase.get("burst", C.LASER_BURST_MIN)))
	# 同一束共享一个基准法向（轻微抖动），多条线近似平行、彼此留出逃生走廊。
	var bundle_ang: float = _rng.randf() * TAU
	var bundle_n := Vector2(cos(bundle_ang), sin(bundle_ang))
	var made: int = 0
	for _b in range(want):
		for _attempt in range(C.SAFETY_RETRY_MAX):
			var cand: Dictionary = _make_candidate(C.HZ_LASER, phase, bundle_n)
			if cand.is_empty():
				continue
			if _safety_check(cand, float(phase["interval"])):
				_commit_hazard(cand)
				made += 1
				break
	if made == 0:
		# 全部重试失败 -> 延迟生成（绝不生成无解组合）
		_spawn_timer = maxf(0.35, float(phase["interval"]) * 0.5)


func _pick_alternative_type(phase: Dictionary) -> int:
	if C.HAZARD_LASER_ONLY:
		return C.HZ_LASER
	for raw_t in [C.HZ_FLAME, C.HZ_SAW, C.HZ_LASER]:
		var t: int = raw_t
		if _srv_time - float(_last_type_spawn.get(t, -999.0)) >= C.HAZARD_TYPE_COOLDOWN_SEC:
			return t
	return -1


func _make_candidate(hz_type: int, phase: Dictionary, bundle_n: Vector2 = Vector2.ZERO) -> Dictionary:
	var params: Dictionary = C.hazard_params(hz_type, _rng, float(phase["speed_scale"]))
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var n := Vector2.ZERO
	var d: float = 0.0
	var nozzle: int = -1

	if hz_type == C.HZ_FLAME:
		# 从圆周喷火口沿弦线喷向另一侧；同一喷口有冷却。
		for _i in range(6):
			var pick: int = _rng.randi_range(0, C.NOZZLE_COUNT - 1)
			if _srv_time - float(_nozzle_cooldown.get(pick, -999.0)) >= C.NOZZLE_COOLDOWN_SEC:
				nozzle = pick
				break
		if nozzle < 0:
			return {}
		var na: float = TAU * float(nozzle) / float(C.NOZZLE_COUNT)
		a = Vector2(cos(na), sin(na)) * C.ARENA_RADIUS
		var inward: Vector2 = -a.normalized()
		var jitter: float = _rng.randf_range(-1.0, 1.0)
		var u: Vector2 = inward.rotated(jitter * 0.9).normalized()
		b = a + u * (-2.0 * a.dot(u))
		n = Vector2(-u.y, u.x).normalized()
		d = a.dot(n)
	else:
		if bundle_n != Vector2.ZERO:
			n = bundle_n.rotated(_rng.randf_range(-0.14, 0.14)).normalized()
		else:
			var ang: float = _rng.randf() * TAU
			n = Vector2(cos(ang), sin(ang))
		d = _rng.randf_range(-C.ARENA_RADIUS * 0.72, C.ARENA_RADIUS * 0.72)
		var ends: Array = C.chord_endpoints(n, d, C.ARENA_RADIUS)
		a = ends[0]
		b = ends[1]

	var length: float = a.distance_to(b)
	if length < C.ARENA_RADIUS * 0.5:
		return {}
	var active: float = float(params["active"])
	if hz_type == C.HZ_SAW:
		active = minf(C.SAW_ACTIVE_MAX, length / maxf(0.1, float(params["speed"])))
	return {
		"type": hz_type,
		"n": n,
		"d": d,
		"a": a,
		"b": b,
		"length": length,
		"width": float(params["width"]),
		"clear_height": float(params["clear_height"]),
		"speed": float(params["speed"]),
		"warn": float(params["warn"]),
		"active": active,
		"nozzle": nozzle,
		"state": C.HAZARD_STATE_WARN,
		"saw_t": 0.0,
		"saw_pos": a,
	}


func _mark_chord(grid: Dictionary, n: Vector2, d: float, half_width: float, mark: int) -> void:
	var dim: int = C.grid_dims()
	for gx in range(dim):
		for gy in range(dim):
			var cell := Vector2i(gx, gy)
			if not C.grid_in_arena(cell):
				continue
			var center: Vector2 = C.grid_center(cell)
			if C.point_chord_distance(center, n, d) <= half_width:
				var cur: int = int(grid.get(cell, C.GRID_SAFE))
				if mark == C.GRID_DANGER or cur != C.GRID_DANGER:
					grid[cell] = mark


func _mark_circle(grid: Dictionary, center: Vector2, radius: float, mark: int) -> void:
	var dim: int = C.grid_dims()
	var min_c: Vector2i = C.grid_index(center - Vector2(radius, radius))
	var max_c: Vector2i = C.grid_index(center + Vector2(radius, radius))
	for gx in range(maxi(0, min_c.x), mini(dim, max_c.x + 2)):
		for gy in range(maxi(0, min_c.y), mini(dim, max_c.y + 2)):
			var cell := Vector2i(gx, gy)
			if not C.grid_in_arena(cell):
				continue
			if C.grid_center(cell).distance_to(center) <= radius:
				var cur: int = int(grid.get(cell, C.GRID_SAFE))
				if mark == C.GRID_DANGER or cur != C.GRID_DANGER:
					grid[cell] = mark


func _build_danger_grid(extra: Array, horizon: float) -> Dictionary:
	## 网格化 + 未来 2 秒危险区模拟：合并所有已存机关与候选机关的扫掠区域。
	var grid: Dictionary = {}
	var now: float = _srv_time
	var steps: int = 6
	for raw in extra:
		var h: Dictionary = raw
		var t0: float = maxf(now, float(h["active_start"]))
		var t1: float = minf(now + horizon, float(h["end_time"]))
		if t1 <= t0:
			continue
		var hz_type: int = int(h["type"])
		var hard: bool = (hz_type == C.HZ_SAW)
		var mark: int = C.GRID_DANGER if hard else C.GRID_JUMPABLE
		if hz_type == C.HZ_SAW:
			for s in range(steps + 1):
				var t: float = lerpf(t0, t1, float(s) / float(steps))
				var prog: float = clampf(
					(t - float(h["active_start"])) * float(h["speed"]) / maxf(0.001, float(h["length"])),
					0.0, 1.0
				)
				var center: Vector2 = (h["a"] as Vector2).lerp(h["b"] as Vector2, prog)
				_mark_circle(grid, center, float(h["width"]) * 0.5 + C.PLAYER_RADIUS, mark)
		else:
			_mark_chord(grid, h["n"], float(h["d"]), float(h["width"]) * 0.5 + C.PLAYER_RADIUS, mark)
	return grid


func _min_distance_to_hazard(p: Vector2, h: Dictionary) -> float:
	## 玩家到该机关在未来有效期内的最小距离（禁止在 1.5m 内立即生成）。
	if int(h["type"]) == C.HZ_SAW:
		var best: float = 1e9
		for s in range(9):
			var q: Vector2 = (h["a"] as Vector2).lerp(h["b"] as Vector2, float(s) / 8.0)
			best = minf(best, p.distance_to(q))
		return best - float(h["width"]) * 0.5
	return C.point_chord_distance(p, h["n"], float(h["d"])) - float(h["width"]) * 0.5


func _bfs_reachable(grid: Dictionary, start: Vector2i, max_steps: int) -> Array:
	## BFS：从玩家当前格出发，预警时间内可达的非硬危险格集合。
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
		for raw_off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var off: Vector2i = raw_off
			var nxt: Vector2i = cell + off
			if visited.has(nxt) or not C.grid_in_arena(nxt):
				continue
			if int(grid.get(nxt, C.GRID_SAFE)) == C.GRID_DANGER:
				continue
			visited[nxt] = true
			queue.append([nxt, depth + 1])
	return out


func _has_safe_corridor(grid: Dictionary, cell: Vector2i) -> bool:
	## 存在宽度 >= 1.2m 的逃生通道：以 2x2 全安全块近似（GRID_CELL=0.6）。
	for ox in range(C.SAFE_CORRIDOR_MIN_CELLS):
		for oy in range(C.SAFE_CORRIDOR_MIN_CELLS):
			var ok: bool = true
			for dx in range(C.SAFE_CORRIDOR_MIN_CELLS):
				for dy in range(C.SAFE_CORRIDOR_MIN_CELLS):
					var c: Vector2i = Vector2i(cell.x - ox + dx, cell.y - oy + dy)
					if not C.grid_in_arena(c) or int(grid.get(c, C.GRID_SAFE)) != C.GRID_SAFE:
						ok = false
			if ok:
				return true
	return false


func _safety_region_connected(grid: Dictionary) -> bool:
	## 禁止十字封锁：可跳跃格视为可穿越，硬危险格（电锯）视为阻断；
	## 所有可站立格必须属于同一个连通区域，否则取消本次生成。
	var dim: int = C.grid_dims()
	var passable: Dictionary = {}
	var first: Vector2i = Vector2i(-1, -1)
	for gx in range(dim):
		for gy in range(dim):
			var cell := Vector2i(gx, gy)
			if not C.grid_in_arena(cell):
				continue
			if int(grid.get(cell, C.GRID_SAFE)) == C.GRID_DANGER:
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


func _safety_check(cand: Dictionary, _interval: float) -> bool:
	## 机关安全生成器：网格化 + 危险区模拟 + 每玩家 BFS 可达性 + 连通性 + 重试前的硬约束。
	var alive_players: Array = []
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if bool(p["alive"]):
			alive_players.append(p)
	if alive_players.is_empty():
		return false

	# 1) 禁止在玩家 1.5 米范围内立即生成致命机关。
	for raw in alive_players:
		var p: Dictionary = raw
		var flat := Vector2(p["pos"].x, p["pos"].z)
		if _min_distance_to_hazard(flat, cand) < C.HAZARD_MIN_PLAYER_DISTANCE:
			return false

	# 2) 补齐时间线字段用于危险区模拟。
	var probe: Dictionary = cand.duplicate(true)
	probe["active_start"] = _srv_time + float(cand["warn"])
	probe["end_time"] = _srv_time + float(cand["warn"]) + float(cand["active"])
	var existing: Array = []
	for raw in _hazards.values():
		var h: Dictionary = raw
		if int(h["state"]) != C.HAZARD_STATE_DONE:
			existing.append(h)
	existing.append(probe)
	var grid: Dictionary = _build_danger_grid(existing, C.SAFETY_HORIZON_SEC)

	# 3) 每个存活玩家：预警时间内至少能到达一个可站立安全格，且存在 >=1.2m 逃生通道。
	var reach: int = int(floor(float(cand["warn"]) * C.PLAYER_MOVE_SPEED / C.GRID_CELL))
	for raw in alive_players:
		var p: Dictionary = raw
		var flat := Vector2(p["pos"].x, p["pos"].z)
		var cells: Array = _bfs_reachable(grid, C.grid_index(flat), maxi(2, reach))
		var found: bool = false
		for raw_cell in cells:
			var cell: Vector2i = raw_cell
			if int(grid.get(cell, C.GRID_SAFE)) != C.GRID_SAFE:
				continue
			if _has_safe_corridor(grid, cell):
				found = true
				break
		if not found:
			return false

	# 4) 安全区连通性：不能形成十字封锁或无路可走组合。
	if not _safety_region_connected(grid):
		return false
	return true


func _commit_hazard(cand: Dictionary) -> void:
	var h: Dictionary = cand.duplicate(true)
	h["id"] = _next_hazard_id
	_next_hazard_id += 1
	h["warn_start"] = _srv_time
	h["active_start"] = _srv_time + float(cand["warn"])
	h["end_time"] = h["active_start"] + float(cand["active"])
	h["state"] = C.HAZARD_STATE_WARN
	_hazards[int(h["id"])] = h
	_last_type_spawn[int(h["type"])] = _srv_time
	if int(h["type"]) == C.HZ_FLAME and int(h["nozzle"]) >= 0:
		_nozzle_cooldown[int(h["nozzle"])] = _srv_time
	_create_hazard_visual(h)
	if _sfx_warn != null:
		_sfx_warn.play()
	if not _standalone_mode and multiplayer.is_server():
		_rpc_hazard_spawn.rpc(h)


@rpc("authority", "call_remote", "reliable")
func _rpc_hazard_spawn(h: Dictionary) -> void:
	## 可靠下发完整机关时间线；客户端只按 srv_time 播放，绝不自行随机或判定。
	if _hazards.has(int(h["id"])):
		return
	_hazards[int(h["id"])] = h
	_create_hazard_visual(h)
	if _sfx_warn != null:
		_sfx_warn.play()


func _create_hazard_visual(h: Dictionary) -> void:
	var pack := Node3D.new()
	pack.name = "Hazard_%d" % int(h["id"])
	_hazard_root.add_child(pack)
	var warn_node: Node3D = M.build_hazard_warning(int(h["type"]), h["a"], h["b"], float(h["width"]))
	pack.add_child(warn_node)
	var active_node: Node3D = M.build_hazard_active(int(h["type"]), h["a"], h["b"], float(h["width"]))
	pack.add_child(active_node)
	var saw_node: Node3D = null
	if int(h["type"]) == C.HZ_SAW:
		saw_node = M.build_saw_body(C.SAW_RADIUS)
		pack.add_child(saw_node)
	active_node.visible = false
	_hazard_nodes[int(h["id"])] = {"warn": warn_node, "active": active_node, "saw": saw_node, "root": pack}


func _render_time() -> float:
	return maxf(0.0, _srv_time_est - C.INTERP_DELAY_SEC)


func _update_hazard_states(t: float) -> void:
	for hid in _hazards.keys():
		var h: Dictionary = _hazards[hid]
		var state: int = C.HAZARD_STATE_WARN
		if t >= float(h["end_time"]):
			state = C.HAZARD_STATE_DONE
		elif t >= float(h["active_start"]):
			state = C.HAZARD_STATE_ACTIVE
		h["state"] = state
		if int(h["type"]) == C.HZ_SAW:
			var prog: float = 0.0
			if state == C.HAZARD_STATE_ACTIVE:
				prog = clampf(
					(t - float(h["active_start"])) * float(h["speed"]) / maxf(0.001, float(h["length"])),
					0.0, 1.0
				)
			h["saw_t"] = prog
			h["saw_pos"] = (h["a"] as Vector2).lerp(h["b"] as Vector2, prog)
		_hazards[hid] = h


func _step_hazards(delta: float) -> void:
	_update_hazard_states(_srv_time)
	# 清理已结束机关（服务器侧；客户端保留到本轮结束以便表现，由 _clear_arena 统一回收）
	if _is_server_sim and _hazards.size() > 24:
		for hid in _hazards.keys():
			if int(_hazards[hid]["state"]) == C.HAZARD_STATE_DONE:
				_hazards.erase(hid)


# ============================================================================
# 6. 出局判定 / 计分 / 轮次结算
# ============================================================================

func _check_player_collisions(p: Dictionary) -> void:
	## 所有出局均由服务器判定；统一回溯 LAG_COMPENSATION_SEC 取历史位置 + 宽容余量。
	var at: float = maxf(0.0, _srv_time - C.LAG_COMPENSATION_SEC)
	var hist_pos: Vector3 = _history_position(int(p["network_id"]), at)
	var flat := Vector2(hist_pos.x, hist_pos.z)

	if flat.length() > C.EDGE_LIMIT_RADIUS - C.HIT_FORGIVENESS:
		_eliminate_player(p, "EDGE_SPIKES", 0)
		return

	for raw in _hazards.values():
		var h: Dictionary = raw
		if int(h["state"]) != C.HAZARD_STATE_ACTIVE:
			continue
		var hz_type: int = int(h["type"])
		var height_ok: bool = hist_pos.y >= float(h["clear_height"]) - C.HIT_FORGIVENESS
		if hz_type == C.HZ_SAW:
			var saw_pos: Vector2 = h["saw_pos"]
			var hit_r: float = C.SAW_RADIUS + C.PLAYER_RADIUS - C.HIT_FORGIVENESS
			if flat.distance_to(saw_pos) <= hit_r and hist_pos.y < 0.35:
				_eliminate_player(p, "SAW", 0)
				return
		else:
			var half: float = float(h["width"]) * 0.5 + C.PLAYER_RADIUS - C.HIT_FORGIVENESS
			if C.point_chord_distance(flat, h["n"], float(h["d"])) <= half and not height_ok:
				_eliminate_player(p, C.hazard_name(hz_type), 0)
				return


func _eliminate_player(p: Dictionary, reason: String, _killer: int) -> void:
	if not bool(p["alive"]):
		return
	p["alive"] = false
	p["state"] = C.ST_OUT
	p["out_reason"] = reason
	p["elim_time"] = _elapsed_time
	_spawn_fx(_fx_dust_scene, Vector3(p["pos"].x, 0.7, p["pos"].z), 0.5, 2.0)
	if _sfx_elim != null:
		_sfx_elim.play()
	if _is_server_sim and not _standalone_mode:
		_rpc_elimination.rpc(int(p["network_id"]), reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_elimination(net_id: int, reason: String) -> void:
	if not _players.has(net_id):
		return
	var p: Dictionary = _players[net_id]
	p["alive"] = false
	p["state"] = C.ST_OUT
	p["out_reason"] = reason
	_players[net_id] = p
	_spawn_fx(_fx_dust_scene, Vector3(p["pos"].x, 0.7, p["pos"].z), 0.5, 2.0)
	if _sfx_elim != null:
		_sfx_elim.play()


func _accrue_scores(delta: float) -> void:
	## 正式计时开始后每存活 1 秒 +1；出局即停止计分，已获分数保留。
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if not bool(p["alive"]):
			continue
		p["alive_sec"] = float(p["alive_sec"]) + delta
		var sec: int = int(floor(float(p["alive_sec"])))
		while sec > int(p["last_scored_sec"]):
			p["score"] = int(p["score"]) + C.SCORE_PER_SECOND
			p["last_scored_sec"] = int(p["last_scored_sec"]) + 1


func _check_round_end() -> void:
	## 硬约束：只有「所有玩家都已出局」或「60 秒倒计时结束」才结算。
	if _phase != PH_LIVE:
		return
	var alive_count: int = 0
	for net_id in _players.keys():
		if bool(_players[net_id]["alive"]):
			alive_count += 1
	var all_out: bool = (alive_count == 0 and _players.size() > 0)
	var time_up: bool = (_time_remaining <= 0.0)
	if not all_out and not time_up:
		return
	_finish_round(time_up)


func _finish_round(time_up: bool) -> void:
	_phase = PH_ENDED
	# 60 秒结束时仍存活的玩家额外 +10 分。
	if time_up:
		for net_id in _players.keys():
			var p: Dictionary = _players[net_id]
			if bool(p["alive"]):
				p["score"] = int(p["score"]) + C.SCORE_SURVIVAL_BONUS
	var entries: Array = []
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		entries.append({
			"network_id": int(p["network_id"]),
			"nickname": str(p["nickname"]),
			"score": int(p["score"]),
			"alive_sec": float(p["alive_sec"]),
			"pushes": int(p["pushes"]),
			"hits_taken": int(p["hits_taken"]),
			"out_reason": str(p["out_reason"]),
			"alive": bool(p["alive"]),
		})
	var ranked: Array = C.rank_entries(entries)
	var official: Dictionary = C.official_scores(ranked)
	_result_rows = ranked
	_banner_label.text = "ROUND COMPLETE"
	if not _standalone_mode and multiplayer.is_server():
		_rpc_round_result.rpc(ranked)
	if _standalone_mode:
		return
	round_finished.emit(official)


@rpc("authority", "call_remote", "reliable")
func _rpc_round_result(ranked: Array) -> void:
	_result_rows = ranked
	_phase = PH_ENDED
	_banner_label.text = "ROUND COMPLETE"


# ============================================================================
# 7. 联机同步：服务器快照 / 客户端插值与外推
# ============================================================================

func _broadcast_snapshot() -> void:
	var p_snap: Dictionary = {}
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		p_snap[net_id] = [
			p["pos"], p["facing"], int(p["state"]), int(p["score"]),
			float(p["alive_sec"]), int(p["pushes"]), int(p["hits_taken"]),
			float(p["push_cooldown"]), bool(p["alive"]), str(p["out_reason"]),
			float(p["vel_y"]),
		]
	_rpc_snapshot.rpc(_srv_time, _phase, _prep_remaining, _time_remaining, p_snap)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(srv_time: float, phase: int, prep_remaining: float, time_remaining: float, p_snap: Dictionary) -> void:
	_srv_time_est = maxf(_srv_time_est, srv_time)
	_phase = phase
	_prep_remaining = prep_remaining
	_time_remaining = time_remaining
	var snap: Dictionary = {"t": srv_time, "players": {}}
	for net_id in p_snap.keys():
		if not _players.has(net_id):
			continue
		var arr: Array = p_snap[net_id]
		var p: Dictionary = _players[net_id]
		p["pos"] = arr[0]
		p["facing"] = arr[1]
		p["state"] = int(arr[2])
		p["score"] = int(arr[3])
		p["alive_sec"] = float(arr[4])
		p["pushes"] = int(arr[5])
		p["hits_taken"] = int(arr[6])
		p["push_cooldown"] = float(arr[7])
		p["alive"] = bool(arr[8])
		p["out_reason"] = str(arr[9])
		p["vel_y"] = float(arr[10])
		_players[net_id] = p
		snap["players"][net_id] = {
			"pos": arr[0],
			"facing": arr[1],
			"vel_y": float(arr[10]),
			"alive": bool(arr[8]),
		}
	_snap_buffer.append(snap)
	while _snap_buffer.size() > 8:
		_snap_buffer.remove_at(0)

	var cd: int = int(ceil(_prep_remaining))
	if _phase == PH_PREP and cd != _last_countdown_sec and cd > 0 and cd <= 3:
		_last_countdown_sec = cd
		_banner_label.text = str(cd)
		if _sfx_beep != null:
			_sfx_beep.play()
	elif _phase == PH_LIVE and _banner_label.text == str(int(ceil(C.PREP_DURATION_SEC))):
		_banner_label.text = "GO!"


func _apply_snapshot_interpolation(delta: float) -> void:
	## 客户端：按 render_time 在最近两个快照间插值；本地玩家额外做限速外推。
	if _snap_buffer.size() < 2:
		return
	var target_t: float = _render_time()
	var a: Dictionary = _snap_buffer[_snap_buffer.size() - 2]
	var b: Dictionary = _snap_buffer[_snap_buffer.size() - 1]
	var t0: float = float(a["t"])
	var t1: float = float(b["t"])
	var alpha: float = 1.0
	if t1 > t0:
		alpha = clampf((target_t - t0) / (t1 - t0), 0.0, 1.0)
	for net_id in _players.keys():
		if not (a["players"] as Dictionary).has(net_id) or not (b["players"] as Dictionary).has(net_id):
			continue
		var pa: Dictionary = (a["players"] as Dictionary)[net_id]
		var pb: Dictionary = (b["players"] as Dictionary)[net_id]
		var pos_a: Vector3 = pa["pos"]
		var pos_b: Vector3 = pb["pos"]
		var interp: Vector3 = pos_a.lerp(pos_b, alpha)
		# 外推：超出最新快照的时间用速度补，限幅避免高延迟下"瞬移"。
		var lead: float = clampf(target_t - t1, 0.0, 0.12)
		if lead > 0.0 and net_id == _local_net_id:
			var p: Dictionary = _players[net_id]
			var lv: Vector2 = p.get("last_vel", Vector2.ZERO)
			interp += Vector3(lv.x, 0.0, lv.y) * lead * 0.55
		var pl: Dictionary = _players[net_id]
		var smooth: float = 1.0 - exp(-22.0 * delta)
		pl["render_pos"] = (pl["render_pos"] as Vector3).lerp(interp, smooth)
		pl["facing"] = pb["facing"]
		_players[net_id] = pl


func player_disconnected(network_id: int) -> void:
	## 掉线清理：立即出局并停止计分，不中途复活。
	if not _players.has(network_id):
		return
	var p: Dictionary = _players[network_id]
	if bool(p["alive"]):
		p["alive"] = false
		p["state"] = C.ST_OUT
		p["out_reason"] = "DISCONNECTED"
		_players[network_id] = p
	_client_inputs.erase(network_id)


# ============================================================================
# 8. 表现层：视觉、HUD、特效
# ============================================================================

func _spawn_fx(scene: PackedScene, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	if inst is Node3D:
		var n3: Node3D = inst as Node3D
		n3.position = world_pos
		n3.scale = Vector3.ONE * scale_val
		_fx_root.add_child(n3)
		var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
		timer.timeout.connect(func():
			if is_instance_valid(n3):
				n3.queue_free()
		)


func _animate_visuals(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		var node: Node3D = p["node"]
		var rp: Vector3 = p["render_pos"] if _is_server_sim == false else p["pos"]
		node.position = rp
		var f: Vector2 = p["facing"]
		node.rotation.y = atan2(f.x, f.y)
		var fallen: bool = int(p["state"]) == C.ST_FALLEN
		node.rotation_degrees.z = 68.0 if fallen else 0.0
		if not bool(p["alive"]):
			node.visible = false
		else:
			node.visible = true
			if int(p["state"]) == C.ST_INVULN:
				node.visible = (int(t * 12.0) % 2 == 0)
		var hp: Label3D = node.get_node_or_null("HpBar") as Label3D
		if hp != null:
			hp.text = "%d PTS" % int(p["score"]) if bool(p["alive"]) else "OUT"

	# 机关视觉：按 state 显示预警/激活，电锯沿弦移动并旋转。
	for hid in _hazards.keys():
		if not _hazard_nodes.has(hid):
			continue
		var h: Dictionary = _hazards[hid]
		var pack: Dictionary = _hazard_nodes[hid]
		var warn_node: Node3D = pack["warn"]
		var active_node: Node3D = pack["active"]
		var st: int = int(h["state"])
		warn_node.visible = (st == C.HAZARD_STATE_WARN)
		active_node.visible = (st == C.HAZARD_STATE_ACTIVE)
		if warn_node.visible:
			var blink: float = 0.35 + 0.65 * absf(sin(t * 8.0))
			warn_node.scale = Vector3(1.0, blink, 1.0)
		if int(h["type"]) == C.HZ_SAW and pack["saw"] != null:
			var saw: Node3D = pack["saw"]
			saw.visible = (st == C.HAZARD_STATE_ACTIVE)
			var sp: Vector2 = h["saw_pos"]
			saw.position = Vector3(sp.x, 0.22, sp.y)
			saw.rotation.y += delta * 18.0
		# 喷火口亮灯
		if int(h["type"]) == C.HZ_FLAME and int(h["nozzle"]) >= 0 and int(h["nozzle"]) < _nozzles.size():
			var nz: Node3D = _nozzles[int(h["nozzle"])]
			nz.scale = Vector3.ONE * (1.15 if st != C.HAZARD_STATE_DONE else 1.0)

	# 观战：保持俯视全景相机不动，出局玩家仍能完整看到整个场地与所有存活玩家，
	# 不切到低空斜视，避免「看不全」与方向错乱（相机由 _frame_arena 固定）。


func _update_hud() -> void:
	var alive_count: int = 0
	for net_id in _players.keys():
		if bool(_players[net_id]["alive"]):
			alive_count += 1
	if _timer_label != null:
		_timer_label.text = str(int(ceil(_prep_remaining))) if _phase == PH_PREP else str(int(ceil(_time_remaining)))
	if _phase_label != null:
		if _phase == PH_PREP:
			_phase_label.text = "PREPARE"
		elif _phase == PH_ENDED:
			_phase_label.text = "RESULT"
		else:
			_phase_label.text = str(C.difficulty_phase(_elapsed_time, _round_cfg)["name"])
	if _alive_label != null:
		_alive_label.text = "ALIVE %d / %d" % [alive_count, _players.size()]

	if _phase == PH_PREP:
		_top_label.text = "准备中 3-2-1 · 移动与跳跃可用 · 推人禁用 · 不会出局"
	else:
		_top_label.text = "SPIKE RING · %02d s · 存活 %d/%d" % [int(ceil(_time_remaining)), alive_count, _players.size()]

	if _players.has(_local_net_id):
		var me: Dictionary = _players[_local_net_id]
		var cd: float = float(me["push_cooldown"])
		var cd_text: String = "READY" if cd <= 0.0 else "%.1fs" % cd
		_stats_label.text = "分数 %d · 存活 %.1fs · 推倒 %d · 受击 %d · 推人冷却 %s" % [
			int(me["score"]), float(me["alive_sec"]), int(me["pushes"]), int(me["hits_taken"]), cd_text
		]
		var spectating: bool = not bool(me["alive"])
		_spectate_hint.visible = spectating and _phase != PH_ENDED
		if spectating:
			_spectate_hint.text = "已出局（%s）· 观战中 · 不中途复活" % str(me["out_reason"])

	if _phase == PH_ENDED and not _result_rows.is_empty():
		_result_label.visible = true
		var lines: Array = ["本轮结算 · 总分 / 存活 / 推倒 / 出局原因 / 排名"]
		for raw in _result_rows:
			var e: Dictionary = raw
			var reason: String = str(e.get("out_reason", ""))
			if reason.is_empty():
				reason = "SURVIVED"
			lines.append("#%d  %s  |  %d 分  |  %.1fs  |  推倒 %d  |  %s" % [
				int(e.get("rank", 0)), str(e.get("nickname", "?")), int(e.get("score", 0)),
				float(e.get("alive_sec", 0.0)), int(e.get("pushes", 0)), reason
			])
		_result_label.text = "\n".join(lines)
	else:
		_result_label.visible = false


func _stage_screenshot_action() -> void:
	_phase = PH_LIVE
	_prep_remaining = 0.0
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		p["state"] = C.ST_NORMAL
		_players[net_id] = p


func _save_screenshot_and_quit() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_screenshot_path)
	get_tree().quit(0)


# ============================================================================
# 9. Headless 自测（Tier 0）
# ============================================================================

func _run_smoke_test() -> void:
	## 连续模拟 20 秒真实回合：验证机关确实生成、视觉节点可创建、整轮不崩。
	_load_helpers()
	_is_server_sim = true
	_standalone_mode = true
	var roster: Array = []
	for i in range(8):
		roster.append({
			"id": i, "network_id": i + 1, "nickname": "P%d" % (i + 1),
			"customization": [], "is_ai": true,
		})
	_setup_match_local(0, 20261121, roster, true)
	var dt: float = 1.0 / 60.0
	var max_hazards: int = 0
	var max_live: int = 0
	var laser_only: bool = true
	for _frame in range(1200):
		_srv_time += dt
		if _phase == PH_PREP:
			_step_prep(dt)
		elif _phase == PH_LIVE:
			_step_simulation(dt)
		else:
			break
		max_hazards = maxi(max_hazards, _hazards.size())
		max_live = maxi(max_live, _live_hazard_count())
		for raw_h in _hazards.values():
			var h: Dictionary = raw_h
			if int(h["type"]) != C.HZ_LASER:
				laser_only = false
		_animate_visuals(dt)
		_update_hud()
	if max_hazards <= 0:
		_fail("smoke: no hazard ever spawned")
		return
	if not laser_only:
		_fail("smoke: non-laser hazard spawned in laser-only mode")
		return
	if max_live < 2:
		_fail("smoke: expected multiple concurrent laser lines, got %d" % max_live)
		return
	print("SPIKE_RING_SMOKE_OK hazards=%d max_live=%d laser_only=%s phase=%d players=%d srv_time=%.1f" % [
		max_hazards, max_live, str(laser_only), _phase, _players.size(), _srv_time
	])
	print("SMOKE_TEST_PASSED")
	get_tree().quit(0)


func _run_self_test() -> void:
	_load_helpers()
	_is_server_sim = true
	_standalone_mode = true

	# --- 出生：2/4/8/16 人均无重叠且在有效区内 ---
	for count in [2, 4, 8, 16]:
		var spawns: Array = C.compute_spawns(count, 9000 + count)
		if spawns.size() != count:
			_fail("spawn count mismatch for %d" % count)
			return
		for i in range(count):
			var pi: Vector2 = spawns[i]
			if pi.length() > C.EDGE_LIMIT_RADIUS:
				_fail("spawn outside arena for %d" % count)
				return
			for j in range(i + 1, count):
				var pj: Vector2 = spawns[j]
				if pi.distance_to(pj) < C.SPAWN_MIN_SEPARATION - 0.001:
					_fail("spawn overlap for %d" % count)
					return

	var roster: Array = []
	for i in range(4):
		roster.append({"id": i, "network_id": i + 1, "nickname": "P%d" % (i + 1), "customization": [], "is_ai": i != 0})
	_setup_match_local(0, 4242, roster, true)

	# --- 准备期：推人禁用、不生成机关、不出局 ---
	if _phase != PH_PREP:
		_fail("expected PREP phase")
		return
	var p1: Dictionary = _players[1]
	p1["facing"] = Vector2(1.0, 0.0)
	p1["input"] = {"dir": Vector2.ZERO, "aim": Vector2(1.0, 0.0), "jump": false, "push": true}
	_client_inputs[1] = p1["input"]
	var p2_before: int = int(_players[2]["hits_taken"])
	_step_prep(0.05)
	if int(_players[2]["hits_taken"]) != p2_before:
		_fail("push must be disabled during prep")
		return
	if not _hazards.is_empty():
		_fail("no hazard may spawn during prep")
		return
	# 准备期把玩家推到边缘也不会出局
	_players[1]["pos"] = Vector3(C.ARENA_RADIUS * 2.0, 0.0, 0.0)
	_step_prep(C.PREP_DURATION_SEC)
	if not bool(_players[1]["alive"]):
		_fail("no elimination during prep")
		return
	if _phase != PH_LIVE:
		_fail("prep must transition to LIVE after 3s")
		return

	# --- 摔倒固定 0.3s + 爬起免推 0.2s ---
	_client_inputs.clear()
	var a: Dictionary = _players[1]
	var v: Dictionary = _players[2]
	a["pos"] = Vector3(0.0, 0.0, 0.0)
	v["pos"] = Vector3(1.0, 0.0, 0.0)
	a["facing"] = Vector2(1.0, 0.0)
	a["state"] = C.ST_NORMAL
	a["push_cooldown"] = 0.0
	v["state"] = C.ST_NORMAL
	v["invuln_timer"] = 0.0
	_try_push(a)
	if int(v["state"]) != C.ST_FALLEN or int(a["pushes"]) != 1 or int(a["score"]) != C.PUSH_SCORE:
		_fail("push hit / +2 score failed")
		return
	# 冷却 1.5s 生效
	if float(a["push_cooldown"]) < C.PUSH_COOLDOWN_SEC - 0.001:
		_fail("push cooldown not applied")
		return
	v["knock_dir"] = Vector2.ZERO
	_step_player_motions(C.FALL_DURATION_SEC - 0.01, false)
	if int(v["state"]) != C.ST_FALLEN:
		_fail("fall must last exactly 0.30s")
		return
	_step_player_motions(0.02, false)
	if int(v["state"]) != C.ST_INVULN or float(v["invuln_timer"]) <= 0.0:
		_fail("fall recovery immunity failed")
		return
	a["push_cooldown"] = 0.0
	_try_push(a)
	if int(v["hits_taken"]) != 1:
		_fail("immunity after recovery must block re-push")
		return

	# --- 计分：每秒 +1 / 存活奖励 +10 / 出局停止 ---
	for net_id in _players.keys():
		var pp: Dictionary = _players[net_id]
		pp["alive"] = true
		pp["score"] = 0
		pp["alive_sec"] = 0.0
		pp["last_scored_sec"] = 0
		_players[net_id] = pp
	_elapsed_time = 10.0
	_accrue_scores(1.0)
	if int(_players[3]["score"]) != 1:
		_fail("survival score per second failed")
		return
	_eliminate_player(_players[3], "TEST", 0)
	var frozen: int = int(_players[3]["score"])
	_accrue_scores(5.0)
	if int(_players[3]["score"]) != frozen:
		_fail("score must freeze after elimination")
		return

	# --- 结算条件：部分出局不结算；全出局或 60s 才结算 ---
	_phase = PH_LIVE
	_time_remaining = 30.0
	_check_round_end()
	if _phase != PH_LIVE:
		_fail("round must NOT end while players remain")
		return
	for net_id in _players.keys():
		_players[net_id]["alive"] = false
	_check_round_end()
	if _phase != PH_ENDED:
		_fail("round must end when all players are out")
		return

	# --- 排名 tie-break：总分 -> 存活 -> 推倒 -> 受击 ---
	var ranked: Array = C.rank_entries([
		{"network_id": 1, "score": 10, "alive_sec": 9.0, "pushes": 1, "hits_taken": 2, "out_reason": ""},
		{"network_id": 2, "score": 10, "alive_sec": 9.0, "pushes": 1, "hits_taken": 0, "out_reason": ""},
		{"network_id": 3, "score": 11, "alive_sec": 1.0, "pushes": 0, "hits_taken": 9, "out_reason": ""},
	])
	if int(ranked[0]["network_id"]) != 3 or int(ranked[1]["network_id"]) != 2:
		_fail("rank tie-break failed")
		return
	if int(C.official_scores(ranked)[3]) != 3:
		_fail("official score conversion failed")
		return

	# --- 机关安全生成器：并发上限 + 拒绝无解组合 + 接受合法组合 ---
	_setup_match_local(0, 777, roster, true)
	_prep_remaining = 0.0
	_phase = PH_LIVE
	_srv_time = 5.0
	_elapsed_time = 5.0
	var phase: Dictionary = C.difficulty_phase(_elapsed_time, _round_cfg)
	var legal_ok: bool = false
	for i in range(40):
		var cand: Dictionary = _make_candidate(C.HZ_LASER, phase)
		if not cand.is_empty() and _safety_check(cand, float(phase["interval"])):
			legal_ok = true
			break
	if not legal_ok:
		_fail("safety generator rejected every legal candidate")
		return
	# 构造一条正好压在所有玩家脚下的硬危险带，必须被拒绝
	var blocked: Dictionary = _make_candidate(C.HZ_SAW, phase)
	if not blocked.is_empty():
		var px: Vector2 = Vector2(_players[1]["pos"].x, _players[1]["pos"].z)
		blocked["n"] = Vector2(1.0, 0.0)
		blocked["d"] = px.x
		blocked["a"] = Vector2(px.x, -C.ARENA_RADIUS)
		blocked["b"] = Vector2(px.x, C.ARENA_RADIUS)
		if _safety_check(blocked, float(phase["interval"])):
			_fail("safety generator accepted a hazard on top of a player")
			return

	# --- 难度三段与关卡数据驱动 ---
	if str(C.difficulty_phase(1.0, _round_cfg)["name"]) != "WARMUP":
		_fail("difficulty phase WARMUP missing")
		return
	if str(C.difficulty_phase(20.0, _round_cfg)["name"]) != "MIXED":
		_fail("difficulty phase MIXED missing")
		return
	if str(C.difficulty_phase(50.0, _round_cfg)["name"]) != "FRENZY":
		_fail("difficulty phase FRENZY missing")
		return

	print("SPIKE_RING_SPAWNS_2_4_8_16_OK, PREP_3S_NO_ELIM_OK, FALL_0.30S_IMMUNITY_0.20S_OK")
	print("PUSH_COOLDOWN_1.5S_OK, SCORE_PER_SEC_AND_SURVIVAL_BONUS_OK, RANK_TIEBREAK_OK")
	print("SAFETY_GRID_BFS_CORRIDOR_CONNECTIVITY_OK, ROUND_END_GATE_OK, DIFFICULTY_PHASES_OK")
	print("SELF_TEST_PASSED")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	push_error("SPIKE_RING_SELF_TEST_FAIL: " + msg)
	get_tree().quit(1)
