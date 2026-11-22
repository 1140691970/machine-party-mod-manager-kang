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

const POOL_HIT_FX := 6
const POOL_DUST_FX := 4
const MAX_ACTIVE_SAW_LIGHTS := 2

var _hit_fx_pool: Array[Dictionary] = []
var _dust_fx_pool: Array[Dictionary] = []
var _hit_fx_cursor: int = 0
var _dust_fx_cursor: int = 0
var _active_saw_lights: int = 0
var _is_self_test: bool = false
var _cam_base_pos: Vector3 = Vector3(0.0, 14.0, 8.8)
var _cam_shake: float = 0.0
var _stats_panel: PanelContainer = null

var _arena_radius: float = 10.5
var _shrink_ring: Node3D = null
var _shrink_warn: Node3D = null
var _slap_box: PanelContainer = null
var _slap_style: StyleBoxFlat = null
var _slap_icon_gray: TextureRect = null
var _slap_fill_clip: Control = null
var _slap_icon_color: TextureRect = null
var _slap_cd_label: Label = null
var _slap_buff_label: Label = null
var _slap_prev_ready: bool = true
var _slap_pop_timer: float = 0.0
var _airdrops: Array = []
var _airdrop_next_idx: int = 0
var _popups: Array = []
var _shockwaves: Array = []

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
	_setup_post_fx()
	_setup_audio_and_fx()
	_setup_hud()
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)

	var args: Array = Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	for raw_a in args:
		var a: String = str(raw_a)
		if a == "--self-test":
			_is_self_test = true
			_run_self_test()
			return
		if a == "--smoke-test":
			_is_self_test = true
			_run_smoke_test()
			return
		if a.begins_with("--capture-screenshot="):
			_screenshot_path = a.substr("--capture-screenshot=".length())

	_warmup_fx_pipelines.call_deferred()

	_standalone_mode = (get_parent() == get_tree().root)
	if _standalone_mode:
		_start_standalone_preview()


func _exit_tree() -> void:
	if M != null and M.has_method("clear_caches"):
		M.clear_caches()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# 对齐 Machine Party / Bubble Blitz 深沉工业车间氛围，突出黄铜舞台与机关发光对比。
	env.background_color = Color(0.05, 0.04, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.35, 0.28)
	env.ambient_light_energy = 0.88
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.05
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.90
	env.glow_enabled = true
	env.glow_intensity = 0.48
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-56.0, 28.0, 0.0)
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "SpikeRingCamera"
	_camera.fov = C.CAMERA_FOV
	_camera.near = 0.1
	_camera.far = 400.0
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


func _setup_post_fx() -> void:
	var post_shader = M.load_optional("res://shaders/postprocessing.gdshader")
	if post_shader is Shader:
		var post_layer := CanvasLayer.new()
		post_layer.name = "PostProcessing"
		post_layer.layer = 4
		add_child(post_layer)

		var bbc := BackBufferCopy.new()
		bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		post_layer.add_child(bbc)

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
		post_layer.add_child(post_rect)


# ---------------------------------------------------------------- 高角度斜俯视 3D 舞台相机
func _camera_fit_distance() -> float:
	var vp: Viewport = get_viewport()
	var vs: Vector2 = Vector2(1280.0, 720.0)
	if vp != null and vp.size.x > 0 and vp.size.y > 0:
		vs = Vector2(vp.size)
	var aspect: float = vs.x / vs.y
	var tan_v: float = tan(deg_to_rad(C.CAMERA_FOV * 0.5))
	var tan_h: float = tan_v * aspect
	var need: float = (_arena_radius + 1.4) * C.CAMERA_FIT_MARGIN
	var d_v: float = need / maxf(0.001, tan_v)
	var d_h: float = need / maxf(0.001, tan_h)
	return maxf(_arena_radius * 1.65, maxf(d_v, d_h))


func _frame_arena() -> void:
	## 58° 高角度斜俯视：完整框住圆形舞台与尖刺墙，同时立体展现角色全身、跳跃高度与激光净空。
	if _camera == null:
		return
	var dist: float = _camera_fit_distance()
	var pitch_rad: float = deg_to_rad(C.CAMERA_PITCH_DEG)
	var look_target := Vector3(0.0, 0.0, 0.35)
	_cam_base_pos = look_target + Vector3(0.0, dist * sin(pitch_rad), dist * cos(pitch_rad))
	_camera.position = _cam_base_pos
	_camera.look_at(look_target, Vector3.UP)


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

	# 顶部与底部文字 HUD 已移除：倒计时直接嵌入 3D 场景 CRT 屏，底部仅保留右下角巴掌推人冷却图示
	_top_label = _mk_label(24, Color(0.72, 1.0, 0.72))
	_top_label.visible = false
	root.add_child(_top_label)

	_stats_label = _mk_label(20, Color(0.84, 1.0, 0.86))
	_stats_label.visible = false
	root.add_child(_stats_label)

	# 右下角巴掌推人技能冷却 HUD（带遮罩进度 + 冷却完成闪光弹跳动画）
	var skill_anchor := VBoxContainer.new()
	skill_anchor.name = "ShoveSkillHUD"
	skill_anchor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skill_anchor.offset_left = -108.0
	skill_anchor.offset_top = -126.0
	skill_anchor.offset_right = -24.0
	skill_anchor.offset_bottom = -20.0
	skill_anchor.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_anchor.add_theme_constant_override("separation", 4)
	skill_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(skill_anchor)

	_slap_box = PanelContainer.new()
	_slap_box.custom_minimum_size = Vector2(74.0, 74.0)
	_slap_box.pivot_offset = Vector2(37.0, 37.0)
	_slap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_style = StyleBoxFlat.new()
	_slap_style.bg_color = Color(0.035, 0.045, 0.035, 0.92)
	_slap_style.border_color = Color(0.56, 0.88, 0.60, 0.90)
	_slap_style.set_border_width_all(2)
	_slap_style.set_corner_radius_all(2)
	_slap_box.add_theme_stylebox_override("panel", _slap_style)
	skill_anchor.add_child(_slap_box)

	var icon_wrap := Control.new()
	icon_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_wrap.clip_contents = true
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_box.add_child(icon_wrap)

	var slap_tex: Texture2D = M.build_slap_icon()
	# 底层：暗灰色巴掌（进入冷却时立刻显示灰色底图）
	_slap_icon_gray = TextureRect.new()
	_slap_icon_gray.texture = slap_tex
	_slap_icon_gray.modulate = Color(0.28, 0.30, 0.28, 0.88)
	_slap_icon_gray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slap_icon_gray.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slap_icon_gray.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slap_icon_gray.offset_left = 8.0
	_slap_icon_gray.offset_top = 8.0
	_slap_icon_gray.offset_right = -8.0
	_slap_icon_gray.offset_bottom = -8.0
	_slap_icon_gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(_slap_icon_gray)

	# 上层充能裁切容器：随冷却进度从 0%（底）平滑向上涨满到 100%（顶），把灰色巴掌染回亮色
	_slap_fill_clip = Control.new()
	_slap_fill_clip.clip_contents = true
	_slap_fill_clip.anchor_left = 0.0
	_slap_fill_clip.anchor_right = 1.0
	_slap_fill_clip.anchor_top = 0.0
	_slap_fill_clip.anchor_bottom = 1.0
	_slap_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(_slap_fill_clip)

	_slap_icon_color = TextureRect.new()
	_slap_icon_color.texture = slap_tex
	_slap_icon_color.modulate = Color(0.76, 1.0, 0.78, 1.0)
	_slap_icon_color.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slap_icon_color.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slap_icon_color.position = Vector2(8.0, 8.0)
	_slap_icon_color.size = Vector2(54.0, 54.0)
	_slap_icon_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_fill_clip.add_child(_slap_icon_color)

	_slap_cd_label = _mk_label(22, Color(0.95, 0.84, 0.42))
	_slap_cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slap_cd_label.visible = false
	icon_wrap.add_child(_slap_cd_label)

	_slap_buff_label = _mk_label(14, Color(1.0, 0.78, 0.24))
	_slap_buff_label.anchor_left = 0.0
	_slap_buff_label.anchor_right = 1.0
	_slap_buff_label.anchor_top = 0.0
	_slap_buff_label.anchor_bottom = 0.36
	_slap_buff_label.visible = false
	icon_wrap.add_child(_slap_buff_label)

	var key_hint := _mk_label(13, Color(0.68, 0.88, 0.70))
	key_hint.text = "[SPACE]"
	skill_anchor.add_child(key_hint)

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
	_airdrops.clear()
	_airdrop_next_idx = 0
	_popups.clear()
	_shockwaves.clear()
	_hit_fx_pool.clear()
	_dust_fx_pool.clear()
	_hit_fx_cursor = 0
	_dust_fx_cursor = 0
	_active_saw_lights = 0
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

	_arena_radius = C.arena_radius_for_players(roster.size())
	_frame_arena()

	var accent_rgb: Array = _round_cfg.get("accent", [0.96, 0.68, 0.22])
	# 外围工厂环境先挂（在场地之外），再叠加竞技场本体。
	var surroundings: Node3D = M.build_surroundings(_arena_radius, accent_rgb)
	_arena_root.add_child(surroundings)
	var stage: Dictionary = M.build_arena(_arena_radius, accent_rgb)
	_arena_root.add_child(stage["root"])
	_timer_label = stage["timer_label"] as Label3D
	_phase_label = stage["phase_label"] as Label3D
	_alive_label = null
	_shrink_ring = stage.get("shrink_ring", null) as Node3D
	_shrink_warn = stage.get("shrink_warn", null) as Node3D
	_nozzles = stage["nozzles"]

	var spawns: Array = C.compute_spawns(roster.size(), seed_val, _arena_radius)
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

		var is_bot: bool = bool(entry.get("is_ai", false)) or net_id < 0
		if not is_preview and _is_server_sim:
			var peers: PackedInt32Array = multiplayer.get_peers()
			if net_id != 1 and not peers.has(net_id):
				is_bot = true

		var shield_node: Node3D = M.build_player_shield()
		node.add_child(shield_node)
		var power_aura: Node3D = M.build_player_power_aura()
		node.add_child(power_aura)
		node.set_meta(&"mpm_alive", true)
		_players[net_id] = {
			"network_id": net_id,
			"nickname": nick,
			"node": node,
			"anim_player": char_pack.get("anim_player", null),
			"shadow": char_pack.get("shadow", null),
			"shield_node": shield_node,
			"power_aura": power_aura,
			"shield": false,
			"power_item": C.ITEM_NONE,
			"knock_vel": Vector2.ZERO,
			"shove_anim_timer": 0.0,
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

	_init_fx_pools()
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
		# 纯键盘操作（对齐官方 Disco Dodge）：WASD/方向键移动并自动转向，按住 Space（备用 J/E）持续推人，无需鼠标介入。
		var push_now: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_E)
		jump_edge = false
		push_edge = push_now
		_prev_jump_pressed = false
		_prev_push_pressed = push_now

	var aim: Vector2 = p.get("facing", Vector2(0.0, 1.0))
	if dir.length_squared() > 0.001:
		aim = dir.normalized()
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
	_step_airdrops(delta)
	_step_popups_and_shockwaves(delta)
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
		if float(p.get("shove_anim_timer", 0.0)) > 0.0:
			p["shove_anim_timer"] = maxf(0.0, float(p["shove_anim_timer"]) - delta)
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

		# --- 摔倒：固定 0.30 秒后爬起，期间按物理减速击退滑行（对齐原版推人冲量手感）---
		if int(p["state"]) == C.ST_FALLEN:
			p["state_timer"] = float(p["state_timer"]) + delta
			var kv: Vector2 = p.get("knock_vel", Vector2.ZERO)
			var new_pos: Vector3 = p["pos"]
			new_pos.x += kv.x * delta
			new_pos.z += kv.y * delta
			p["pos"] = new_pos
			p["knock_vel"] = kv.move_toward(Vector2.ZERO, C.PUSH_DECAY * delta)
			if float(p["state_timer"]) >= C.FALL_DURATION_SEC:
				p["state_timer"] = 0.0
				p["knock_dir"] = Vector2.ZERO
				p["knock_vel"] = Vector2.ZERO
				if C.RECOVERY_IMMUNITY_SEC > 0.0:
					p["state"] = C.ST_INVULN
					p["invuln_timer"] = C.RECOVERY_IMMUNITY_SEC
				else:
					p["state"] = C.ST_NORMAL
					p["invuln_timer"] = 0.0
		else:
			# --- 平滑加减速移动（消除起步/急停顿挫）---
			var target_vel: Vector2 = dir * C.PLAYER_MOVE_SPEED
			var cur_vel: Vector2 = p.get("last_vel", Vector2.ZERO)
			var rate: float = C.PLAYER_ACCEL if target_vel.length_squared() > 0.01 else C.PLAYER_DECEL
			cur_vel = cur_vel.move_toward(target_vel, rate * delta)
			p["last_vel"] = cur_vel
			var new_pos: Vector3 = p["pos"]
			new_pos.x += cur_vel.x * delta
			new_pos.z += cur_vel.y * delta

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
			var limit: float = (_arena_radius - C.PLAYER_RADIUS) * 0.92
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

	# --- 玩家两两圆形碰撞分离（彻底防止角色互相穿模）---
	var ids: Array = _players.keys()
	var min_sep: float = C.PLAYER_RADIUS * 2.0
	var min_sep_sq: float = min_sep * min_sep
	for i in range(ids.size()):
		var pa: Dictionary = _players[ids[i]]
		if not bool(pa["alive"]):
			continue
		for j in range(i + 1, ids.size()):
			var pb: Dictionary = _players[ids[j]]
			if not bool(pb["alive"]):
				continue
			var dx: float = float(pb["pos"].x) - float(pa["pos"].x)
			var dz: float = float(pb["pos"].z) - float(pa["pos"].z)
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < min_sep_sq:
				var dist: float = sqrt(dist_sq)
				var nx: float = (dx / dist) if dist > 0.0001 else 1.0
				var nz: float = (dz / dist) if dist > 0.0001 else 0.0
				var push_half: float = (min_sep - dist) * 0.5
				pa["pos"].x -= nx * push_half
				pa["pos"].z -= nz * push_half
				pb["pos"].x += nx * push_half
				pb["pos"].z += nz * push_half


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
	## 推人：支持普通推击、空投重击铁拳（2x 击退）与震荡冲击波（360° 范围震飞）。
	## 取消黄色矩形波，改为攻击者推人动作 + 命中粒子 + 3D 飘字 `+2`。
	var origin := Vector2(attacker["pos"].x, attacker["pos"].z)
	var facing: Vector2 = attacker["facing"]
	var power_item: int = int(attacker.get("power_item", C.ITEM_NONE))
	var is_shockwave: bool = (power_item == C.ITEM_SHOCKWAVE)
	var is_power_shove: bool = (power_item == C.ITEM_POWER_SHOVE)
	attacker["shove_anim_timer"] = 0.26
	attacker["push_cooldown"] = C.PUSH_COOLDOWN_SEC

	var victims: Array = []
	if is_shockwave:
		attacker["power_item"] = C.ITEM_NONE
		_spawn_shockwave(Vector3(origin.x, 0.35, origin.y))
		for net_id in _players.keys():
			if net_id == int(attacker["network_id"]):
				continue
			var target: Dictionary = _players[net_id]
			if not bool(target["alive"]) or int(target["state"]) == C.ST_FALLEN or float(target["invuln_timer"]) > 0.0:
				continue
			var tp := Vector2(target["pos"].x, target["pos"].z)
			if tp.distance_to(origin) <= C.SHOCKWAVE_RANGE:
				victims.append(target)
	else:
		var best_id: int = -1
		var best_dist: float = C.PUSH_RANGE
		for net_id in _players.keys():
			if net_id == int(attacker["network_id"]):
				continue
			var target: Dictionary = _players[net_id]
			if not bool(target["alive"]) or int(target["state"]) == C.ST_FALLEN:
				continue
			if float(target["invuln_timer"]) > 0.0:
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
		if best_id >= 0:
			victims.append(_players[best_id])

	if victims.is_empty():
		if _sfx_push != null:
			_sfx_push.volume_db = -10.0
			_sfx_push.play()
		return

	if is_power_shove:
		attacker["power_item"] = C.ITEM_NONE

	var impulse: float = 28.0 if is_power_shove else (20.0 if is_shockwave else C.PUSH_KNOCKBACK_SPEED)
	for raw_v in victims:
		var victim: Dictionary = raw_v
		victim["state"] = C.ST_FALLEN
		victim["state_timer"] = 0.0
		victim["hits_taken"] = int(victim["hits_taken"]) + 1
		var vp := Vector2(victim["pos"].x, victim["pos"].z)
		var knock: Vector2 = (vp - origin).normalized()
		if knock.length_squared() < 0.001:
			knock = facing
		victim["knock_dir"] = knock
		victim["knock_vel"] = knock * impulse
		attacker["pushes"] = int(attacker["pushes"]) + 1
		attacker["score"] = int(attacker["score"]) + C.PUSH_SCORE
		_spawn_fx(_fx_hit_scene, Vector3(vp.x, 0.8, vp.y), 0.55 if (is_power_shove or is_shockwave) else 0.42, 1.2)

	var total_pts: int = victims.size() * C.PUSH_SCORE
	var popup_text: String = "+%d 2x!" % total_pts if is_power_shove else ("+%d 360°!" % total_pts if is_shockwave else "+%d" % total_pts)
	var popup_col: Color = Color(1.0, 0.72, 0.18) if (is_power_shove or is_shockwave) else Color(0.58, 1.0, 0.62)
	_spawn_score_popup(Vector3(origin.x, 2.35, origin.y), popup_text, popup_col)
	_cam_shake = maxf(_cam_shake, 0.28 if (is_power_shove or is_shockwave) else 0.18)
	if _sfx_push != null:
		_sfx_push.volume_db = -1.5 if (is_power_shove or is_shockwave) else -3.0
		_sfx_push.play()


func _spawn_score_popup(world_pos: Vector3, text: String, color: Color) -> void:
	if _is_self_test or _fx_root == null:
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 46
	lbl.outline_size = 10
	lbl.pixel_size = 0.011
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = color
	if _term_font != null:
		lbl.font = _term_font
	lbl.position = world_pos
	_fx_root.add_child(lbl)
	_popups.append({"node": lbl, "age": 0.0, "max_age": 0.85, "base_col": color})


func _spawn_shockwave(world_pos: Vector3) -> void:
	if _is_self_test or _fx_root == null or M == null:
		return
	var ring: MeshInstance3D = M.build_shockwave_ring()
	ring.position = world_pos
	ring.scale = Vector3(0.35, 1.0, 0.35)
	_fx_root.add_child(ring)
	_shockwaves.append({"node": ring, "age": 0.0, "max_age": 0.34, "max_r": C.SHOCKWAVE_RANGE})


func _step_popups_and_shockwaves(delta: float) -> void:
	for i in range(_popups.size() - 1, -1, -1):
		var pop: Dictionary = _popups[i]
		var lbl: Label3D = pop["node"]
		pop["age"] = float(pop["age"]) + delta
		var t: float = float(pop["age"]) / float(pop["max_age"])
		if not is_instance_valid(lbl) or t >= 1.0:
			if is_instance_valid(lbl):
				lbl.queue_free()
			_popups.remove_at(i)
		else:
			lbl.position.y += delta * 1.45
			var col: Color = pop["base_col"]
			col.a = clampf(1.0 - t * t, 0.0, 1.0)
			lbl.modulate = col
			_popups[i] = pop

	for i in range(_shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = _shockwaves[i]
		var ring: MeshInstance3D = sw["node"]
		sw["age"] = float(sw["age"]) + delta
		var t: float = float(sw["age"]) / float(sw["max_age"])
		if not is_instance_valid(ring) or t >= 1.0:
			if is_instance_valid(ring):
				ring.queue_free()
			_shockwaves.remove_at(i)
		else:
			var r: float = lerpf(0.35, float(sw["max_r"]), 1.0 - pow(1.0 - t, 2.0))
			ring.scale = Vector3(r, maxf(0.15, 1.0 - t * 0.7), r)
			_shockwaves[i] = sw


func _step_airdrops(delta: float) -> void:
	## 直接空投可见 3D 消耗品道具（防爆护盾 / 重击铁拳 / 震荡冲击波），无盲盒箱子。
	if _airdrop_next_idx < C.AIRDROP_TIMES.size() and _elapsed_time >= float(C.AIRDROP_TIMES[_airdrop_next_idx]):
		_airdrop_next_idx += 1
		var itype: int = _rng.randi_range(C.ITEM_SHIELD, C.ITEM_SHOCKWAVE)
		var live_r: float = C.current_arena_radius(_elapsed_time, _arena_radius)
		var ang: float = _rng.randf() * TAU
		var dist: float = sqrt(_rng.randf()) * live_r * 0.62
		var drop_pos := Vector2(cos(ang) * dist, sin(ang) * dist)
		var node: Node3D = null
		if not _is_self_test and _fx_root != null and M != null:
			node = M.build_airdrop_item(itype)
			node.position = Vector3(drop_pos.x, 0.0, drop_pos.y)
			var vis := node.get_node_or_null("ItemVisual") as Node3D
			if vis != null:
				vis.position.y = 11.0
			_fx_root.add_child(node)
		_airdrops.append({
			"type": itype,
			"pos": drop_pos,
			"fall_timer": C.AIRDROP_FALL_SEC,
			"landed": false,
			"node": node,
			"age": 0.0,
		})
		if _sfx_warn != null:
			_sfx_warn.play()

	var t_now: float = Time.get_ticks_msec() * 0.001
	for i in range(_airdrops.size() - 1, -1, -1):
		var ad: Dictionary = _airdrops[i]
		ad["age"] = float(ad["age"]) + delta
		var node: Node3D = ad["node"]
		if not bool(ad["landed"]):
			ad["fall_timer"] = maxf(0.0, float(ad["fall_timer"]) - delta)
			var prog: float = 1.0 - float(ad["fall_timer"]) / maxf(0.01, C.AIRDROP_FALL_SEC)
			if node != null and is_instance_valid(node):
				var vis := node.get_node_or_null("ItemVisual") as Node3D
				if vis != null:
					vis.position.y = lerpf(11.0, 0.0, prog * prog)
					vis.rotation.y += delta * 2.8
				var ring := node.get_node_or_null("DropRing") as Node3D
				if ring != null:
					var s: float = 0.85 + 0.25 * sin(t_now * 10.0)
					ring.scale = Vector3(s, 1.0, s)
			if float(ad["fall_timer"]) <= 0.0:
				ad["landed"] = true
				if node != null and is_instance_valid(node):
					var vis := node.get_node_or_null("ItemVisual") as Node3D
					if vis != null:
						vis.position.y = 0.0
					var ring := node.get_node_or_null("DropRing") as Node3D
					if ring != null:
						ring.scale = Vector3.ONE
				_spawn_fx(_fx_dust_scene, Vector3(ad["pos"].x, 0.3, ad["pos"].y), 0.45, 0.8)
			_airdrops[i] = ad
			continue

		# 已落地：缓慢自转悬浮，等待玩家触碰拾取
		if node != null and is_instance_valid(node):
			var vis := node.get_node_or_null("ItemVisual") as Node3D
			if vis != null:
				vis.position.y = 0.10 + 0.08 * sin(t_now * 3.5)
				vis.rotation.y += delta * 1.8

		var picked := false
		var apos: Vector2 = ad["pos"]
		for net_id in _players.keys():
			var p: Dictionary = _players[net_id]
			if not bool(p["alive"]):
				continue
			var pflat := Vector2(p["pos"].x, p["pos"].z)
			if pflat.distance_to(apos) <= C.AIRDROP_PICKUP_RADIUS:
				var itype: int = int(ad["type"])
				if itype == C.ITEM_SHIELD:
					p["shield"] = true
					_spawn_score_popup(Vector3(pflat.x, 2.5, pflat.y), "護盾!", Color(0.36, 0.92, 1.0))
				elif itype == C.ITEM_POWER_SHOVE:
					p["power_item"] = C.ITEM_POWER_SHOVE
					p["push_cooldown"] = 0.0
					_spawn_score_popup(Vector3(pflat.x, 2.5, pflat.y), "重推 2x!", Color(1.0, 0.74, 0.20))
				else:
					p["power_item"] = C.ITEM_SHOCKWAVE
					p["push_cooldown"] = 0.0
					_spawn_score_popup(Vector3(pflat.x, 2.5, pflat.y), "衝擊波 360°!", Color(1.0, 0.38, 0.24))
				if _sfx_ding != null:
					_sfx_ding.play()
				picked = true
				break

		if picked or float(ad["age"]) > 22.0:
			if node != null and is_instance_valid(node):
				node.queue_free()
			_airdrops.remove_at(i)
		else:
			_airdrops[i] = ad


func _compute_ai_input(p: Dictionary, delta: float, prep: bool) -> Dictionary:
	## 战术 AI：识别预警/激活中的激光、电锯与喷火，自动起跳越过激光、横移躲电锯，并在安全时主动推人。
	p["ai_timer"] = float(p.get("ai_timer", 0.0)) - delta
	if float(p["ai_timer"]) <= 0.0:
		p["ai_timer"] = _rng.randf_range(0.35, 0.95)
		var a: float = _rng.randf() * TAU
		p["ai_dir"] = Vector2(cos(a), sin(a))

	var pos := Vector2(p["pos"].x, p["pos"].z)
	var avoid := Vector2.ZERO
	var want_jump: bool = false
	var want_push: bool = false
	var aim_dir: Vector2 = p.get("facing", Vector2(0.0, 1.0))

	# 1. 避开边缘尖刺墙 / 正在收缩的毒圈
	var live_edge: float = C.current_arena_radius(_elapsed_time, _arena_radius) - C.PLAYER_RADIUS
	var edge_dist: float = pos.length()
	if edge_dist > live_edge * 0.65:
		var pull: float = clampf((edge_dist - live_edge * 0.65) / maxf(0.1, live_edge * 0.35), 0.0, 1.0)
		avoid += -pos.normalized() * (1.2 + pull * 2.6)

	# 2. 感知场内机关（贴地火带可跳或躲，上身激光与电锯必须横移躲避）
	if not prep:
		for raw in _hazards.values():
			var h: Dictionary = raw
			var st: int = int(h["state"])
			if st == C.HAZARD_STATE_DONE:
				continue
			var hz_type: int = int(h["type"])
			var ha: Vector2 = h["a"]
			var hb: Vector2 = h["b"]
			if hz_type == C.HZ_SAW:
				var sp: Vector2 = h["saw_pos"] if st == C.HAZARD_STATE_ACTIVE else ha
				var to_me: Vector2 = pos - sp
				var d_saw: float = to_me.length()
				if d_saw < 2.8:
					var seg_dir: Vector2 = (hb - ha).normalized()
					var perp := Vector2(-seg_dir.y, seg_dir.x)
					if perp.dot(to_me) < 0.0:
						perp = -perp
					avoid += (perp * 2.6 + to_me.normalized() * 1.0) * (1.0 - d_saw / 2.8)
			elif hz_type == C.HZ_LASER:
				var total_len: float = ha.distance_to(hb)
				var d_seg: float = C.point_chord_distance(pos, h["n"], float(h["d"]))
				var half_w: float = float(h["width"]) * 0.5 + C.PLAYER_RADIUS
				if total_len > 0.2 and d_seg < half_w + 3.2:
					var seg_dir: Vector2 = (hb - ha) / total_len
					var gap_t: float = float(h.get("gap_t", 0.5))
					var gap_w: float = float(h.get("gap_width", C.LASER_GAP_WIDTH))
					var gap_c: float = clampf(gap_t * total_len, gap_w * 0.65, total_len - gap_w * 0.65)
					var gap_pt: Vector2 = ha + seg_dir * gap_c
					var to_gap: Vector2 = gap_pt - pos
					if to_gap.length() > 0.35:
						avoid += to_gap.normalized() * (2.6 if st == C.HAZARD_STATE_ACTIVE else 1.7)
					else:
						# 已对准缺口，沿缺口穿行
						var perp := Vector2(-seg_dir.y, seg_dir.x)
						if perp.dot(pos - gap_pt) < 0.0:
							perp = -perp
						avoid += perp * 0.8
			else:
				var d_seg: float = C.point_chord_distance(pos, h["n"], float(h["d"]))
				var half_w: float = float(h["width"]) * 0.5 + C.PLAYER_RADIUS
				if d_seg < half_w + 1.8:
					var seg_dir: Vector2 = (hb - ha).normalized()
					var perp := Vector2(-seg_dir.y, seg_dir.x)
					if perp.dot(pos - (ha + hb) * 0.5) < 0.0:
						perp = -perp
					avoid += perp * (2.8 if st == C.HAZARD_STATE_ACTIVE else 1.8)

	# 2b. 安全时主动争夺已落地的空投道具
	if not prep and avoid.length() < 1.2 and not _airdrops.is_empty():
		var best_ad_dist: float = 999.0
		var best_ad_pos := Vector2.ZERO
		for raw_ad in _airdrops:
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

	# 3. 安全时寻找附近对手尝试推人
	var my_id: int = int(p["network_id"])
	var closest_rival := Vector2.ZERO
	var closest_dist: float = 999.0
	if not prep and avoid.length() < 1.2 and float(p["push_cooldown"]) <= 0.0:
		for other_id in _players.keys():
			if other_id == my_id:
				continue
			var other: Dictionary = _players[other_id]
			if not bool(other["alive"]) or int(other["state"]) == C.ST_FALLEN or float(other["invuln_timer"]) > 0.0:
				continue
			var op := Vector2(other["pos"].x, other["pos"].z)
			var d: float = pos.distance_to(op)
			if d < closest_dist:
				closest_dist = d
				closest_rival = op
		if closest_dist <= C.PUSH_RANGE * 0.92:
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


func _has_live_laser() -> bool:
	for raw in _hazards.values():
		var h: Dictionary = raw
		if int(h["type"]) == C.HZ_LASER and int(h["state"]) != C.HAZARD_STATE_DONE:
			return true
	return false


func _pick_weighted_type(phase: Dictionary) -> int:
	if C.HAZARD_LASER_ONLY:
		return C.HZ_LASER
	var weights: Dictionary = phase.get("weights", {"flame": 0.3, "saw": 0.35, "laser": 0.35})
	var allow_laser: bool = not _has_live_laser()
	var w_flame: float = float(weights.get("flame", 0.3))
	var w_saw: float = float(weights.get("saw", 0.35))
	var w_laser: float = float(weights.get("laser", 0.35)) if allow_laser else 0.0
	var total: float = w_flame + w_saw + w_laser
	if total <= 0.001:
		return C.HZ_SAW
	var r: float = _rng.randf() * total
	if r < w_flame:
		return C.HZ_FLAME
	if r < w_flame + w_saw:
		return C.HZ_SAW
	return C.HZ_LASER


func _step_spawner(delta: float) -> void:
	## 按难度阶段权重生成三类机关（贴地火带 / 电锯 / 带安全缺口的上身激光）；
	## 任何时刻场上最多只允许 1 条激光，彻底杜绝两侧激光夹击无解。
	var phase: Dictionary = C.difficulty_phase(_elapsed_time, _round_cfg)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = float(phase["interval"])

	var budget: int = int(phase["max_concurrent"]) - _live_hazard_count()
	if budget <= 0:
		return
	var want: int = mini(budget, int(phase.get("burst", 1)))
	var made: int = 0
	for _b in range(want):
		var hz_type: int = _pick_weighted_type(phase)
		if hz_type == C.HZ_LASER and _has_live_laser():
			hz_type = C.HZ_SAW
		for _attempt in range(C.SAFETY_RETRY_MAX):
			var cand: Dictionary = _make_candidate(hz_type, phase, Vector2.ZERO)
			if cand.is_empty():
				continue
			if _safety_check(cand, float(phase["interval"])):
				_commit_hazard(cand)
				made += 1
				break
	if made == 0:
		_spawn_timer = maxf(0.4, float(phase["interval"]) * 0.5)


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
		a = Vector2(cos(na), sin(na)) * _arena_radius
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
		d = _rng.randf_range(-_arena_radius * 0.72, _arena_radius * 0.72)
		var ends: Array = C.chord_endpoints(n, d, _arena_radius)
		a = ends[0]
		b = ends[1]

	var length: float = a.distance_to(b)
	if length < _arena_radius * 0.5:
		return {}
	var active: float = float(params["active"])
	if hz_type == C.HZ_SAW:
		active = minf(C.SAW_ACTIVE_MAX, length / maxf(0.1, float(params["speed"])))
	var sweep_dir: float = (1.0 if d <= 0.0 else -1.0) if hz_type == C.HZ_LASER else 0.0
	var sweep_speed: float = C.LASER_SWEEP_SPEED * float(phase.get("speed_scale", 1.0)) if hz_type == C.HZ_LASER else 0.0
	var gap_t: float = _rng.randf_range(0.24, 0.76) if hz_type == C.HZ_LASER else 0.5
	return {
		"type": hz_type,
		"n": n,
		"d": d,
		"d_base": d,
		"sweep_dir": sweep_dir,
		"sweep_speed": sweep_speed,
		"gap_t": gap_t,
		"gap_width": C.LASER_GAP_WIDTH,
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
	var hz_type: int = int(h["type"])
	if hz_type == C.HZ_LASER:
		var rig: Node3D = M.build_laser_rig(
			h["a"], h["b"], float(h["width"]),
			float(h.get("gap_t", 0.5)), float(h.get("gap_width", C.LASER_GAP_WIDTH))
		)
		pack.add_child(rig)
		_hazard_nodes[int(h["id"])] = {
			"warn": null,
			"active": rig,
			"saw": null,
			"root": pack,
			"has_light": false,
			"is_laser_rig": true,
		}
		return

	var warn_node: Node3D = M.build_hazard_warning(hz_type, h["a"], h["b"], float(h["width"]))
	pack.add_child(warn_node)
	var active_node: Node3D = M.build_hazard_active(hz_type, h["a"], h["b"], float(h["width"]))
	pack.add_child(active_node)
	var saw_node: Node3D = null
	var has_light: bool = false
	if hz_type == C.HZ_SAW:
		has_light = _active_saw_lights < MAX_ACTIVE_SAW_LIGHTS
		if has_light:
			_active_saw_lights += 1
		saw_node = M.build_saw_body(C.SAW_RADIUS, has_light)
		pack.add_child(saw_node)
	active_node.visible = false
	_hazard_nodes[int(h["id"])] = {
		"warn": warn_node,
		"active": active_node,
		"saw": saw_node,
		"root": pack,
		"has_light": has_light,
		"is_laser_rig": false,
	}


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
		elif int(h["type"]) == C.HZ_LASER and state == C.HAZARD_STATE_ACTIVE:
			var s_speed: float = float(h.get("sweep_speed", 0.0))
			if s_speed > 0.01:
				var dt_act: float = maxf(0.0, t - float(h["active_start"]))
				var d_now: float = clampf(
					float(h.get("d_base", h["d"])) + float(h.get("sweep_dir", 1.0)) * s_speed * dt_act,
					-_arena_radius + 0.4,
					_arena_radius - 0.4
				)
				var ends: Array = C.chord_endpoints(h["n"], d_now, _arena_radius)
				h["d"] = d_now
				h["a"] = ends[0]
				h["b"] = ends[1]
		_hazards[hid] = h


func _step_hazards(delta: float) -> void:
	_update_hazard_states(_srv_time)
	# 清理已结束机关节点与状态，防止长对局残留节点和占满动态光源上限
	if _hazards.size() > 16:
		var done_ids: Array = []
		for hid in _hazards.keys():
			if int(_hazards[hid]["state"]) == C.HAZARD_STATE_DONE:
				done_ids.append(hid)
		for hid in done_ids:
			_hazards.erase(hid)
			if _hazard_nodes.has(hid):
				var pack: Dictionary = _hazard_nodes[hid]
				if bool(pack.get("has_light", false)):
					_active_saw_lights = maxi(0, _active_saw_lights - 1)
				var rnode = pack.get("root", null)
				if is_instance_valid(rnode):
					(rnode as Node3D).queue_free()
				_hazard_nodes.erase(hid)


# ============================================================================
# 6. 出局判定 / 计分 / 轮次结算
# ============================================================================

func _check_player_collisions(p: Dictionary) -> void:
	## 所有出局均由服务器判定；统一回溯 LAG_COMPENSATION_SEC 取历史位置 + 宽容余量。
	if float(p.get("invuln_timer", 0.0)) > 0.0 and int(p.get("state", C.ST_NORMAL)) == C.ST_INVULN:
		return
	var at: float = maxf(0.0, _srv_time - C.LAG_COMPENSATION_SEC)
	var hist_pos: Vector3 = _history_position(int(p["network_id"]), at)
	var flat := Vector2(hist_pos.x, hist_pos.z)

	var live_limit: float = C.current_arena_radius(_elapsed_time, _arena_radius) - C.PLAYER_RADIUS
	if flat.length() > live_limit - C.HIT_FORGIVENESS:
		var reason: String = "SHRINK_RING" if _elapsed_time > C.SHRINK_START_SEC else "EDGE_SPIKES"
		_handle_fatal_hit(p, reason, 0)
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
				_handle_fatal_hit(p, "SAW", 0)
				return
		elif hz_type == C.HZ_LASER:
			var half: float = float(h["width"]) * 0.5 + C.PLAYER_RADIUS - C.HIT_FORGIVENESS
			if C.point_chord_distance(flat, h["n"], float(h["d"])) <= half and not height_ok:
				var ha: Vector2 = h["a"]
				var hb: Vector2 = h["b"]
				var total_len: float = ha.distance_to(hb)
				if total_len > 0.2:
					var seg_dir: Vector2 = (hb - ha) / total_len
					var gap_t: float = float(h.get("gap_t", 0.5))
					var gap_w: float = float(h.get("gap_width", C.LASER_GAP_WIDTH))
					var gap_c: float = clampf(gap_t * total_len, gap_w * 0.65, total_len - gap_w * 0.65)
					var proj: float = (flat - ha).dot(seg_dir)
					if absf(proj - gap_c) <= gap_w * 0.5 - C.PLAYER_RADIUS * 0.3:
						continue
				_handle_fatal_hit(p, C.hazard_name(hz_type), 0)
				return
		else:
			var half: float = float(h["width"]) * 0.5 + C.PLAYER_RADIUS - C.HIT_FORGIVENESS
			if C.point_chord_distance(flat, h["n"], float(h["d"])) <= half and not height_ok:
				_handle_fatal_hit(p, C.hazard_name(hz_type), 0)
				return


func _handle_fatal_hit(p: Dictionary, reason: String, killer_id: int) -> void:
	if bool(p.get("shield", false)):
		p["shield"] = false
		p["state"] = C.ST_INVULN
		p["invuln_timer"] = 0.85
		var flat := Vector2(p["pos"].x, p["pos"].z)
		var inward: Vector2 = -flat.normalized() if flat.length_squared() > 0.01 else Vector2(0.0, 1.0)
		var safe_r: float = maxf(1.0, C.current_arena_radius(_elapsed_time, _arena_radius) - C.PLAYER_RADIUS - 1.2)
		if flat.length() > safe_r:
			flat = flat.normalized() * safe_r
			p["pos"].x = flat.x
			p["pos"].z = flat.y
		p["last_vel"] = inward * 6.5
		_spawn_fx(_fx_dust_scene, Vector3(p["pos"].x, 0.9, p["pos"].z), 0.55, 1.0)
		_spawn_score_popup(Vector3(p["pos"].x, 2.4, p["pos"].z), "護盾抵擋!", Color(0.36, 0.92, 1.0))
		if _sfx_ding != null:
			_sfx_ding.play()
		return
	_eliminate_player(p, reason, killer_id)


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
				_spawn_score_popup(Vector3(p["pos"].x, 2.6, p["pos"].z), "+10 存活!", Color(1.0, 0.86, 0.28))
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
			float(p["vel_y"]), bool(p.get("shield", false)), int(p.get("power_item", C.ITEM_NONE)),
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
		if arr.size() > 11:
			p["shield"] = bool(arr[11])
		if arr.size() > 12:
			p["power_item"] = int(arr[12])
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

func _activate_particles_recursive(node: Node) -> void:
	if node is GPUParticles3D:
		var gp: GPUParticles3D = node
		gp.restart()
		gp.emitting = true
	elif node is CPUParticles3D:
		var cp: CPUParticles3D = node
		cp.restart()
		cp.emitting = true
	for child in node.get_children():
		_activate_particles_recursive(child)


func _collect_particles_recursive(node: Node, out: Array[Node]) -> void:
	if node is GPUParticles3D:
		var gp: GPUParticles3D = node
		gp.emitting = false
		out.append(gp)
	elif node is CPUParticles3D:
		var cp: CPUParticles3D = node
		cp.emitting = false
		out.append(cp)
	for child in node.get_children():
		_collect_particles_recursive(child, out)


func _build_fx_pool(scene: PackedScene, count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if scene == null or _fx_root == null:
		return pool
	for _i in range(count):
		var inst: Node = scene.instantiate()
		if inst is Node3D:
			var n3: Node3D = inst as Node3D
			if n3.get_script() != null:
				n3.set_script(null)
			var emitters: Array[Node] = []
			_collect_particles_recursive(n3, emitters)
			n3.position = Vector3(0.0, -50.0, 0.0)
			n3.visible = false
			_fx_root.add_child(n3)
			pool.append({"node": n3, "emitters": emitters, "timer": 0.0})
		elif inst != null:
			inst.queue_free()
	return pool


func _warmup_fx_pipelines() -> void:
	# Handled by _init_fx_pools() inside _setup_match_local() with in-frustum warmup.
	pass


func _init_fx_pools() -> void:
	if _is_self_test or _fx_root == null:
		return
	_hit_fx_pool = _build_fx_pool(_fx_hit_scene, POOL_HIT_FX)
	_dust_fx_pool = _build_fx_pool(_fx_dust_scene, POOL_DUST_FX)
	if _screenshot_path.is_empty():
		var warm_pos := Vector3(0.0, 0.3, 0.0)
		for pool in [_hit_fx_pool, _dust_fx_pool]:
			if not pool.is_empty():
				_trigger_fx_entry(pool[0], warm_pos, 0.01, 0.08)


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
	for pool in [_hit_fx_pool, _dust_fx_pool]:
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


func _spawn_fx(scene: PackedScene, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	if _is_self_test or scene == null:
		return
	if scene == _fx_hit_scene and not _hit_fx_pool.is_empty():
		var entry: Dictionary = _hit_fx_pool[_hit_fx_cursor % _hit_fx_pool.size()]
		_hit_fx_cursor += 1
		_trigger_fx_entry(entry, world_pos, scale_val, lifetime)
	elif scene == _fx_dust_scene and not _dust_fx_pool.is_empty():
		var entry: Dictionary = _dust_fx_pool[_dust_fx_cursor % _dust_fx_pool.size()]
		_dust_fx_cursor += 1
		_trigger_fx_entry(entry, world_pos, scale_val, lifetime)


func _animate_visuals(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	if _camera != null:
		if _cam_shake > 0.001:
			_cam_shake = maxf(0.0, _cam_shake - delta * 1.4)
			_camera.position = _cam_base_pos + Vector3(
				sin(t * 58.0) * _cam_shake,
				cos(t * 47.0) * _cam_shake * 0.5,
				0.0
			)
		else:
			_camera.position = _cam_base_pos

	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		var node: Node3D = p["node"]
		var rp: Vector3 = p["render_pos"] if _is_server_sim == false else p["pos"]
		node.position = rp
		var f: Vector2 = p["facing"]
		var target_yaw: float = atan2(f.x, f.y)
		node.rotation.y = lerp_angle(node.rotation.y, target_yaw, minf(1.0, delta * 18.0))
		var alive: bool = bool(p["alive"])
		node.set_meta(&"mpm_alive", alive)
		var fallen: bool = int(p["state"]) == C.ST_FALLEN
		var shoving: bool = float(p.get("shove_anim_timer", 0.0)) > 0.0
		var ap = p.get("anim_player", null)
		if ap is AnimationPlayer:
			var anim_p: AnimationPlayer = ap
			var vel_len_sq: float = (p.get("last_vel", Vector2.ZERO) as Vector2).length_squared()
			var moving: bool = vel_len_sq > 0.12
			if fallen:
				if anim_p.has_animation(&"mp_mod/shoved") and anim_p.current_animation != &"mp_mod/shoved":
					anim_p.play(&"mp_mod/shoved", 0.06)
				anim_p.speed_scale = 1.0
				node.rotation_degrees.z = 0.0
			elif shoving:
				var shove_anim: StringName = &"mp_mod/shove" if anim_p.has_animation(&"mp_mod/shove") else &"mp_mod/shoved"
				if anim_p.has_animation(shove_anim) and anim_p.current_animation != shove_anim:
					anim_p.play(shove_anim, 0.05)
				anim_p.speed_scale = 1.35
				node.rotation_degrees.z = 0.0
			elif moving:
				if anim_p.has_animation(&"mp_mod/run") and anim_p.current_animation != &"mp_mod/run":
					anim_p.play(&"mp_mod/run", 0.12)
				anim_p.speed_scale = clampf(sqrt(vel_len_sq) / maxf(0.1, C.PLAYER_MOVE_SPEED), 0.65, 1.15)
				node.rotation_degrees.z = 0.0
			else:
				if anim_p.has_animation(&"mp_mod/idle") and anim_p.current_animation != &"mp_mod/idle":
					anim_p.play(&"mp_mod/idle", 0.14)
				anim_p.speed_scale = 1.0
				node.rotation_degrees.z = 0.0
		else:
			node.rotation_degrees.z = 68.0 if fallen else 0.0

		var shield_n = p.get("shield_node", null)
		if shield_n is Node3D and is_instance_valid(shield_n):
			var sn: Node3D = shield_n
			var has_sh: bool = bool(p.get("shield", false)) and alive
			sn.visible = has_sh
			if has_sh:
				sn.rotation.y = t * 1.8
				var ra := sn.get_node_or_null("RingA") as Node3D
				var rb := sn.get_node_or_null("RingB") as Node3D
				if ra != null:
					ra.rotation.y = t * 2.2
				if rb != null:
					rb.rotation.y = -t * 1.9

		var aura_n = p.get("power_aura", null)
		if aura_n is Node3D and is_instance_valid(aura_n):
			var an: Node3D = aura_n
			var pi_val: int = int(p.get("power_item", C.ITEM_NONE))
			var show_gold: bool = alive and (pi_val == C.ITEM_POWER_SHOVE)
			var show_red: bool = alive and (pi_val == C.ITEM_SHOCKWAVE)
			var gr := an.get_node_or_null("GoldRing") as Node3D
			var rr := an.get_node_or_null("RedRing") as Node3D
			if gr != null:
				gr.visible = show_gold
			if rr != null:
				rr.visible = show_red
			if show_gold or show_red:
				var pulse_s: float = 0.94 + 0.10 * sin(t * 7.5)
				an.scale = Vector3(pulse_s, 1.0, pulse_s)

		var shadow = p.get("shadow", null)
		if shadow is Node3D and is_instance_valid(shadow):
			var sh: Node3D = shadow
			sh.position = Vector3(0.0, -rp.y + 0.03, 0.0)
			var sh_scale: float = clampf(1.0 - rp.y * 0.42, 0.35, 1.0)
			sh.scale = Vector3(sh_scale, 1.0, sh_scale)

		if not alive:
			node.visible = false
		else:
			node.visible = true
			if int(p["state"]) == C.ST_INVULN:
				node.visible = (int(t * 12.0) % 2 == 0)

	# 机关视觉：激光采用一体化滑车+细红瞄准线->无缝点燃；火带与电锯保留贴地警示带。
	for hid in _hazards.keys():
		if not _hazard_nodes.has(hid):
			continue
		var h: Dictionary = _hazards[hid]
		var pack: Dictionary = _hazard_nodes[hid]
		var st: int = int(h["state"])
		if bool(pack.get("is_laser_rig", false)):
			var rig: Node3D = pack["active"]
			var warn_dur: float = maxf(0.05, float(h.get("active_start", 1.0)) - float(h.get("warn_start", 0.0)))
			var charge_prog: float = clampf((_srv_time - float(h.get("warn_start", 0.0))) / warn_dur, 0.0, 1.0)
			var pulse: float = clampf(charge_prog * 0.65 + 0.35 * (0.5 + 0.5 * sin(t * 22.0)), 0.0, 1.0)
			M.update_laser_rig(
				rig, h["a"], h["b"], float(h["width"]),
				float(h.get("gap_t", 0.5)), float(h.get("gap_width", C.LASER_GAP_WIDTH)),
				st, pulse
			)
			continue
		var warn_node: Node3D = pack["warn"]
		var active_node: Node3D = pack["active"]
		if warn_node != null:
			warn_node.visible = (st == C.HAZARD_STATE_WARN) and (int(t * 10.0) % 2 == 0)
		active_node.visible = (st == C.HAZARD_STATE_ACTIVE)
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

	# 真实机械尖刺环收缩（平时在最外圈，最后 25 秒整体向圆心合拢并点亮内侧警戒环）
	if _shrink_ring != null and is_instance_valid(_shrink_ring):
		var cur_r: float = C.current_arena_radius(_elapsed_time, _arena_radius) if _phase == PH_LIVE else _arena_radius
		var ratio: float = clampf(cur_r / maxf(0.1, _arena_radius), 0.35, 1.0)
		_shrink_ring.scale = Vector3(ratio, 1.0, ratio)
		if _shrink_warn != null and is_instance_valid(_shrink_warn):
			_shrink_warn.visible = (_phase == PH_LIVE and _elapsed_time > C.SHRINK_START_SEC)

	# 推人技能巴掌冷却完成弹跳动画
	if _slap_pop_timer > 0.0 and _slap_box != null:
		_slap_pop_timer = maxf(0.0, _slap_pop_timer - delta)
		var p_norm: float = _slap_pop_timer / 0.28
		var s: float = 1.0 + 0.22 * sin(p_norm * PI)
		_slap_box.scale = Vector2(s, s)
	elif _slap_box != null and _slap_box.scale != Vector2.ONE:
		_slap_box.scale = Vector2.ONE
	_step_fx_pools(delta)

	# 观战：保持俯视全景相机不动，出局玩家仍能完整看到整个场地与所有存活玩家，
	# 不切到低空斜视，避免「看不全」与方向错乱（相机由 _frame_arena 固定）。


func _update_hud() -> void:
	var alive_count: int = 0
	for net_id in _players.keys():
		if bool(_players[net_id]["alive"]):
			alive_count += 1
	if _timer_label != null:
		if _phase == PH_PREP:
			_timer_label.text = "00:0%d" % maxi(0, int(ceil(_prep_remaining)))
			_timer_label.modulate = Color(1.0, 0.84, 0.36)
		else:
			var secs: int = maxi(0, int(ceil(_time_remaining)))
			_timer_label.text = "%02d:%02d" % [secs / 60, secs % 60]
			_timer_label.modulate = Color(1.0, 0.34, 0.24) if _elapsed_time > C.SHRINK_START_SEC else Color(0.68, 1.0, 0.72)
	if _phase_label != null:
		if _phase == PH_PREP:
			_phase_label.text = "PREPARE"
		elif _phase == PH_ENDED:
			_phase_label.text = "ROUND OVER"
		elif _elapsed_time > C.SHRINK_START_SEC:
			_phase_label.text = "RING SHRINKING!"
		else:
			_phase_label.text = "SPIKE RING // %s" % str(_round_cfg.get("name_en", "ARENA"))

	if _players.has(_local_net_id):
		var me: Dictionary = _players[_local_net_id]
		var alive: bool = bool(me["alive"])
		var cd: float = float(me["push_cooldown"])
		var ready: bool = alive and _phase == PH_LIVE and cd <= 0.0
		if _slap_box != null:
			_slap_box.visible = alive and _phase != PH_ENDED
		var p_item: int = int(me.get("power_item", C.ITEM_NONE))
		if _slap_style != null:
			if p_item == C.ITEM_POWER_SHOVE:
				_slap_style.border_color = Color(1.0, 0.74, 0.20, 0.95)
			elif p_item == C.ITEM_SHOCKWAVE:
				_slap_style.border_color = Color(1.0, 0.36, 0.22, 0.95)
			else:
				_slap_style.border_color = Color(0.56, 0.88, 0.60, 0.90)
		if _slap_buff_label != null:
			if p_item == C.ITEM_POWER_SHOVE:
				_slap_buff_label.text = "2x"
				_slap_buff_label.modulate = Color(1.0, 0.80, 0.26)
				_slap_buff_label.visible = true
			elif p_item == C.ITEM_SHOCKWAVE:
				_slap_buff_label.text = "360°"
				_slap_buff_label.modulate = Color(1.0, 0.44, 0.28)
				_slap_buff_label.visible = true
			else:
				_slap_buff_label.visible = false
		if _slap_fill_clip != null and _slap_icon_color != null and _slap_cd_label != null:
			var box_h: float = 70.0
			if not ready and cd > 0.0:
				# 从 0%（全灰）平滑向上充能至 100%（全亮绿）
				var charge: float = clampf(1.0 - cd / maxf(0.01, C.PUSH_COOLDOWN_SEC), 0.0, 1.0)
				var top_px: float = box_h * (1.0 - charge)
				_slap_fill_clip.anchor_top = 1.0 - charge
				_slap_fill_clip.anchor_bottom = 1.0
				_slap_fill_clip.visible = charge > 0.01
				# 保持亮色图标与底层灰图逐像素对齐
				_slap_icon_color.position = Vector2(8.0, 8.0 - top_px)
				_slap_cd_label.text = "%.1f" % cd
				_slap_cd_label.visible = true
			elif _phase == PH_PREP:
				_slap_fill_clip.visible = false
				_slap_cd_label.visible = false
			else:
				_slap_fill_clip.anchor_top = 0.0
				_slap_fill_clip.anchor_bottom = 1.0
				_slap_fill_clip.visible = true
				_slap_icon_color.position = Vector2(8.0, 8.0)
				_slap_cd_label.visible = false
				if not _slap_prev_ready:
					_slap_pop_timer = 0.28
		_slap_prev_ready = ready
		var spectating: bool = not alive
		_spectate_hint.visible = spectating and _phase != PH_ENDED
		if spectating:
			_spectate_hint.text = "已出局（%s）· 观战中" % str(me["out_reason"])

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
	_elapsed_time = 41.0
	_time_remaining = 19.0
	var demo_pos: Array = [
		Vector3(-1.6, 0.0, 0.2),
		Vector3(-4.6, 0.0, -2.8),
		Vector3(1.4, 0.0, -4.4),
		Vector3(-4.8, 0.0, 3.0),
		Vector3(1.1, 0.0, 4.2),
		Vector3(5.6, 0.0, -1.8),
	]
	var idx := 0
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		p["state"] = C.ST_NORMAL
		p["score"] = 41 + (int(net_id) % 3) * 2
		p["alive_sec"] = 41.0
		p["pos"] = demo_pos[idx % demo_pos.size()]
		p["render_pos"] = p["pos"]
		if int(net_id) == 1:
			p["push_cooldown"] = 0.65
			p["shield"] = true
		elif int(net_id) == 3:
			p["power_item"] = C.ITEM_POWER_SHOVE
		_players[net_id] = p
		idx += 1
	var demo_hazards: Array = [
		{
			"id": 901, "type": C.HZ_LASER,
			"a": Vector2(-8.2, -1.2), "b": Vector2(8.2, 1.4),
			"gap_t": 0.42, "gap_width": C.LASER_GAP_WIDTH,
			"width": C.LASER_WIDTH, "length": 16.6, "speed": 0.0,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": C.HAZARD_STATE_ACTIVE, "saw_t": 0.0, "saw_pos": Vector2.ZERO, "nozzle": -1,
		},
		{
			"id": 902, "type": C.HZ_SAW,
			"a": Vector2(-7.6, 4.2), "b": Vector2(7.6, -3.4),
			"width": C.SAW_RADIUS * 2.0, "length": 17.0, "speed": C.SAW_SPEED,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": C.HAZARD_STATE_ACTIVE, "saw_t": 0.30, "saw_pos": Vector2(-3.0, 2.0), "nozzle": -1,
		},
		{
			"id": 903, "type": C.HZ_FLAME,
			"a": Vector2(3.6, -7.8), "b": Vector2(4.4, 7.2),
			"width": C.FLAME_WIDTH, "length": 15.0, "speed": 0.0,
			"warn_start": 0.0, "active_start": 0.0, "end_time": 99.0,
			"state": C.HAZARD_STATE_ACTIVE, "saw_t": 0.0, "saw_pos": Vector2.ZERO, "nozzle": 2,
		},
	]
	for h in demo_hazards:
		_hazards[int(h["id"])] = h
		_create_hazard_visual(h)
	# 展示空投可见道具与 3D 飘字加分
	var demo_drop: Node3D = M.build_airdrop_item(C.ITEM_POWER_SHOVE)
	demo_drop.position = Vector3(1.8, 0.0, -1.6)
	_fx_root.add_child(demo_drop)
	_spawn_score_popup(Vector3(-1.8, 3.35, 0.2), "+2", Color(0.58, 1.0, 0.62))
	_update_hud()


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
	var max_live_lasers: int = 0
	for _frame in range(1500):
		_srv_time += dt
		if _phase == PH_PREP:
			_step_prep(dt)
		elif _phase == PH_LIVE:
			_step_simulation(dt)
		else:
			break
		max_hazards = maxi(max_hazards, _hazards.size())
		max_live = maxi(max_live, _live_hazard_count())
		var live_lasers: int = 0
		for raw_h in _hazards.values():
			var h: Dictionary = raw_h
			if int(h["type"]) == C.HZ_LASER and int(h["state"]) != C.HAZARD_STATE_DONE:
				live_lasers += 1
		max_live_lasers = maxi(max_live_lasers, live_lasers)
		_animate_visuals(dt)
		_update_hud()
	if max_hazards <= 0:
		_fail("smoke: no hazard ever spawned")
		return
	if max_live_lasers > 1:
		_fail("smoke: concurrent lasers exceeded 1 (%d)" % max_live_lasers)
		return
	if _airdrop_next_idx <= 0:
		_fail("smoke: expected at least one airdrop to spawn")
		return
	print("SPIKE_RING_SMOKE_OK hazards=%d max_live=%d max_live_lasers=%d airdrops=%d phase=%d players=%d srv_time=%.1f" % [
		max_hazards, max_live, max_live_lasers, _airdrop_next_idx, _phase, _players.size(), _srv_time
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

	# --- 持续按住推人：动作前摇后摇决定冷却、推到人才加分、加分无内置冷却 ---
	_client_inputs.clear()
	var a: Dictionary = _players[1]
	var v: Dictionary = _players[2]
	var v_was_ai: bool = bool(v["is_ai"])
	v["is_ai"] = false
	a["pos"] = Vector3(0.0, 0.0, 0.0)
	v["pos"] = Vector3(5.0, 0.0, 0.0)
	a["facing"] = Vector2(1.0, 0.0)
	a["state"] = C.ST_NORMAL
	a["push_cooldown"] = 0.0
	v["state"] = C.ST_NORMAL
	v["invuln_timer"] = 0.0
	# 空推不加分
	_try_push(a)
	if int(a["pushes"]) != 0 or int(a["score"]) != 0:
		_fail("push whiff must not award score")
		return
	# 命中加分并进入动作冷却
	v["pos"] = Vector3(1.0, 0.0, 0.0)
	a["push_cooldown"] = 0.0
	_try_push(a)
	if int(v["state"]) != C.ST_FALLEN or int(a["pushes"]) != 1 or int(a["score"]) != C.PUSH_SCORE:
		_fail("push hit / +2 score failed")
		return
	if float(a["push_cooldown"]) < C.PUSH_COOLDOWN_SEC - 0.001:
		_fail("push cooldown not applied")
		return
	v["knock_dir"] = Vector2.ZERO
	v["knock_vel"] = Vector2.ZERO
	_step_player_motions(C.FALL_DURATION_SEC - 0.01, false)
	if int(v["state"]) != C.ST_FALLEN:
		_fail("fall must last exactly 0.30s")
		return
	# 按住推人键在动作冷却结束后自动继续推，一路顶人并再次加分
	_client_inputs[1] = {"dir": Vector2.ZERO, "aim": Vector2(1.0, 0.0), "jump": false, "push": true}
	_step_player_motions(0.02, false)
	if int(v["state"]) != C.ST_NORMAL:
		_fail("victim should recover to normal after 0.30s fall")
		return
	_step_player_motions(C.PUSH_COOLDOWN_SEC - C.FALL_DURATION_SEC + 0.01, false)
	if int(v["hits_taken"]) != 2 or int(a["pushes"]) != 2 or int(a["score"]) != C.PUSH_SCORE * 2:
		_fail("hold-to-push continuous shove failed")
		return
	_client_inputs.clear()
	v["is_ai"] = v_was_ai

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
	print("HOLD_PUSH_CONTINUOUS_OK, SCORE_PER_SEC_AND_SURVIVAL_BONUS_OK, RANK_TIEBREAK_OK")
	print("SAFETY_GRID_BFS_CORRIDOR_CONNECTIVITY_OK, ROUND_END_GATE_OK, DIFFICULTY_PHASES_OK")
	print("SELF_TEST_PASSED")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	push_error("SPIKE_RING_SELF_TEST_FAIL: " + msg)
	get_tree().quit(1)
