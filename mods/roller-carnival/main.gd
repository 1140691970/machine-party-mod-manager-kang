extends Node

## MPML API v2 Entry Point for Roller Carnival (滾筒嘉年華).
## Registers overrides so Roller Carnival joins Machine Party's minigame rotation
## (repurposing unused slot Globals.MinigameIdentifier.ShapeCutter = 6) and moves
## configurable match parameters to the Lobby room-creation phase.

const MOD_ID := "roller-carnival"
const TARGET_SLOT_ID := 6 # Globals.MinigameIdentifier.ShapeCutter
const TARGET_SCENE_PATH := "res://minigames/shape_cutter/shape_cutter.tscn"
const SETTINGS_KEY := "roller_carnival"
const REG_RES_DIR := "res://mods_roller_carnival/"

var _loader = null
var _mod_dir: String = ""
var _config_script = null
var _meshes_script = null
var _game_script = null
var _packed_minigame_scene: PackedScene = null
var _roller_icon_texture: Texture2D = null
var _active_stage: Node3D = null
var _room_modal_overlay: CanvasLayer = null


func _mod_init(loader) -> void:
	_loader = loader
	_mod_dir = str(loader.dir_of(MOD_ID))

	_register_mod_scripts(loader)
	_prepare_packed_minigame_scene()

	if loader.has_method("override_script_rel"):
		loader.override_script_rel(MOD_ID, "res://scripts/scenes/game/game.gd", "override_game.gd")
		loader.override_script_rel(MOD_ID, "res://scenes/lobby/components/playlist_handler.gd", "override_playlist.gd")
		loader.override_script_rel(MOD_ID, "res://minigames/intermission_new/components/intermission_game_picker.gd", "override_picker.gd")

	if loader.has_method("on_lobby"):
		loader.on_lobby(_on_lobby_entered)
	if loader.has_method("on_scene_script"):
		loader.on_scene_script("res://scripts/scenes/game/game.gd", _on_game_entered)

	if loader.has_method("has_api") and loader.call("has_api", "registry"):
		var reg = loader.registry("minigames")
		if reg is Dictionary:
			reg[MOD_ID] = REG_RES_DIR + "roller_carnival_game.gd"

	loader.note(MOD_ID + ": initialized (integrated into slot ShapeCutter=6 + lobby config; F7 quick-preview enabled)")


func _mod_ready(loader) -> void:
	_loader = loader
	if _mod_dir.is_empty():
		_mod_dir = str(loader.dir_of(MOD_ID))

	_ensure_globals_settings()
	_ensure_default_playlist_entry()


func _register_mod_scripts(loader) -> void:
	var use_register_api := false
	if loader.has_method("has_api"):
		use_register_api = bool(loader.call("has_api", "register_script"))

	if use_register_api and loader.has_method("register_script"):
		loader.register_script(MOD_ID, "config.gd", REG_RES_DIR + "config.gd")
		loader.register_script(MOD_ID, "carnival_meshes.gd", REG_RES_DIR + "carnival_meshes.gd")
		loader.register_script(MOD_ID, "roller_carnival_game.gd", REG_RES_DIR + "roller_carnival_game.gd")
		_config_script = ResourceLoader.load(REG_RES_DIR + "config.gd")
		_meshes_script = ResourceLoader.load(REG_RES_DIR + "carnival_meshes.gd")
		_game_script = ResourceLoader.load(REG_RES_DIR + "roller_carnival_game.gd")
		return

	if loader.has_method("compile"):
		_config_script = loader.compile(_mod_dir.path_join("config.gd"))
		if _config_script != null:
			_config_script.take_over_path(REG_RES_DIR + "config.gd")
		_meshes_script = loader.compile(_mod_dir.path_join("carnival_meshes.gd"))
		if _meshes_script != null:
			_meshes_script.take_over_path(REG_RES_DIR + "carnival_meshes.gd")
		_game_script = loader.compile(_mod_dir.path_join("roller_carnival_game.gd"))
		if _game_script != null:
			_game_script.take_over_path(REG_RES_DIR + "roller_carnival_game.gd")


func _prepare_packed_minigame_scene() -> void:
	if _game_script == null:
		return
	var dummy_root := Node3D.new()
	dummy_root.name = "RollerCarnival"
	dummy_root.set_script(_game_script)

	var packed := PackedScene.new()
	var err: int = packed.pack(dummy_root)
	dummy_root.free()
	if err != OK:
		if _loader != null:
			_loader.note(MOD_ID + ": failed to pack RollerCarnival scene, err=" + str(err))
		return

	_packed_minigame_scene = packed
	if ResourceLoader.exists(TARGET_SCENE_PATH) or TARGET_SCENE_PATH.begins_with("res://"):
		_packed_minigame_scene.take_over_path(TARGET_SCENE_PATH)


func _get_globals_node() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("Globals")


func _new_config_instance():
	if _config_script == null and not _mod_dir.is_empty():
		_config_script = load(_mod_dir.path_join("config.gd"))
	if _config_script == null:
		return null
	return _config_script.new()


func _ensure_globals_settings() -> void:
	var glb := _get_globals_node()
	if glb == null:
		return
	var gs = glb.get("game_settings")
	if not (gs is Dictionary):
		return
	var cfg = _new_config_instance()
	if cfg == null:
		return
	if not gs.has(SETTINGS_KEY) or not (gs[SETTINGS_KEY] is Dictionary):
		gs[SETTINGS_KEY] = cfg.to_dict()
	else:
		cfg.apply_dict(gs[SETTINGS_KEY])
		gs[SETTINGS_KEY] = cfg.to_dict()


func _ensure_default_playlist_entry() -> void:
	var glb := _get_globals_node()
	if glb == null:
		return

	var default_pl = glb.get("default_playlist")
	if default_pl is Array:
		var has_slot := false
		for item in default_pl:
			if item != null and int(item.get("game_identifier")) == TARGET_SLOT_ID:
				has_slot = true
				break
		if not has_slot and ResourceLoader.exists("res://scripts/resources/minigame_list_resource.gd"):
			var mlr_script = ResourceLoader.load("res://scripts/resources/minigame_list_resource.gd")
			if mlr_script != null:
				var mlr = mlr_script.new()
				mlr.set("game_identifier", TARGET_SLOT_ID)
				mlr.set("total_rounds", 1)
				default_pl.append(mlr)

	var session_pl = glb.get("session_playlist")
	if session_pl is Array and not session_pl.is_empty():
		var has_session_slot := false
		for item in session_pl:
			if item != null and int(item.get("game_identifier")) == TARGET_SLOT_ID:
				has_session_slot = true
				break
		if not has_session_slot and ResourceLoader.exists("res://scripts/resources/minigame_list_resource.gd"):
			var mlr_script2 = ResourceLoader.load("res://scripts/resources/minigame_list_resource.gd")
			if mlr_script2 != null:
				var mlr2 = mlr_script2.new()
				mlr2.set("game_identifier", TARGET_SLOT_ID)
				mlr2.set("total_rounds", 1)
				session_pl.append(mlr2)


func _build_roller_icon_texture() -> Texture2D:
	if _roller_icon_texture != null:
		return _roller_icon_texture
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.08, 0.07, 1.0))
	for y in range(96):
		for x in range(96):
			if x < 4 or x >= 92 or y < 4 or y >= 92:
				img.set_pixel(x, y, Color(0.95, 0.72, 0.24, 1.0))
			elif x <= 18 and y >= 14:
				img.set_pixel(x, y, Color(1.0, 0.36, 0.06, 1.0))
			elif y >= 76:
				img.set_pixel(x, y, Color(0.28, 0.24, 0.26, 1.0))

			if x >= 24 and x <= 84 and y >= 22 and y <= 40:
				var shade := 1.0 - absf(float(y - 31)) / 10.5 * 0.35
				img.set_pixel(x, y, Color(1.0 * shade, 0.78 * shade, 0.18 * shade, 1.0))

			if x >= 28 and x <= 84 and y >= 50 and y <= 68:
				var shade2 := 1.0 - absf(float(y - 59)) / 10.5 * 0.35
				img.set_pixel(x, y, Color(0.84 * shade2, 0.90 * shade2, 0.97 * shade2, 1.0))

	_roller_icon_texture = ImageTexture.create_from_image(img)
	return _roller_icon_texture


func _on_game_entered(game_node: Node) -> void:
	if game_node == null:
		return
	_ensure_globals_settings()
	_ensure_default_playlist_entry()
	_prepare_packed_minigame_scene()

	var im = game_node.get("intermission_manager")
	if im == null:
		return
	var arr = im.get("minigame_icon_resource_array")
	if not (arr is Array):
		return
	for item in arr:
		if item != null and int(item.get("identifier")) == TARGET_SLOT_ID:
			return

	if not ResourceLoader.exists("res://minigames/intermission_new/components/intermission_icon_resource.gd"):
		return
	var icon_res_script = ResourceLoader.load("res://minigames/intermission_new/components/intermission_icon_resource.gd")
	if icon_res_script == null:
		return
	var icon_res = icon_res_script.new()
	icon_res.set("identifier", TARGET_SLOT_ID)
	icon_res.set("icon_texture", _build_roller_icon_texture())
	icon_res.set("brief_instructions_header_pages", ["ROLLER CARNIVAL"])
	icon_res.set("brief_instructions_content_pages", [
		"金色高滾筒：按 [S] 下蹲躲過；\n銀色低滾筒：按 [空白鍵] 跳躍越過；\n被撞擊只會向左推擠，掉入岩漿即淘汰！"
	])

	if ResourceLoader.exists("res://modules/user_interface/intermission_control_input_label/intermission_control_input_label_data.gd"):
		var ctrl_script = ResourceLoader.load("res://modules/user_interface/intermission_control_input_label/intermission_control_input_label_data.gd")
		if ctrl_script != null:
			var ctrl_jump = ctrl_script.new()
			ctrl_jump.set("control_text", "JUMP / 跳躍 (銀色低滾筒)")
			ctrl_jump.set("controller_text", "JUMP")
			ctrl_jump.set("keyboard_icons", [7]) # KeyboardW
			ctrl_jump.set("controller_icons", [17]) # ControllerFaceSouth

			var ctrl_crouch = ctrl_script.new()
			ctrl_crouch.set("control_text", "CROUCH / 下蹲 (金色高滾筒)")
			ctrl_crouch.set("controller_text", "CROUCH")
			ctrl_crouch.set("keyboard_icons", [8]) # KeyboardS
			ctrl_crouch.set("controller_icons", [16]) # ControllerFaceEast

			icon_res.set("controls_data", [ctrl_jump, ctrl_crouch])

	arr.append(icon_res)


func _on_lobby_entered(lobby_node: Node) -> void:
	if lobby_node == null:
		return
	_ensure_globals_settings()
	_ensure_default_playlist_entry()

	# on_lobby also invokes for MainMenu; only attach the room config button inside LobbyScene.
	var hflow: Control = lobby_node.get_node_or_null("Lobby/Control/HFlowContainer2")
	if hflow == null:
		return
	if hflow.get_node_or_null("RollerCarnivalSettingsBtn") != null:
		return

	var btn := Button.new()
	btn.name = "RollerCarnivalSettingsBtn"
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.text = _localized_lobby_btn_text()

	var playlist_btn: Button = hflow.get_node_or_null("PlaylistButton")
	if playlist_btn != null and playlist_btn.theme != null:
		btn.theme = playlist_btn.theme

	var is_host := true
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		is_host = multiplayer.is_server()
	btn.visible = is_host

	btn.pressed.connect(_open_room_settings_modal.bind(lobby_node))
	hflow.add_child(btn)
	hflow.move_child(btn, 0)


func _localized_lobby_btn_text() -> String:
	var loc := TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "滚筒嘉年华参数"
	if loc.begins_with("ZH"):
		return "滾筒嘉年華參數"
	return "ROLLER PARAMS"


func _open_room_settings_modal(lobby_node: Node) -> void:
	if _room_modal_overlay != null and is_instance_valid(_room_modal_overlay):
		_room_modal_overlay.queue_free()
		_room_modal_overlay = null

	_ensure_globals_settings()
	var cfg = _new_config_instance()
	if cfg == null:
		return
	var glb := _get_globals_node()
	if glb != null:
		var gs = glb.get("game_settings")
		if gs is Dictionary and gs.has(SETTINGS_KEY) and gs[SETTINGS_KEY] is Dictionary:
			cfg.apply_dict(gs[SETTINGS_KEY])
	var data: Dictionary = cfg.to_dict()

	var layer := CanvasLayer.new()
	layer.name = "RollerCarnivalLobbyConfigModal"
	layer.layer = 45
	lobby_node.add_child(layer)
	_room_modal_overlay = layer

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.02, 0.04, 0.72)
	layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.08, 0.96)
	style.border_color = Color(0.95, 0.72, 0.22, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	panel.add_child(root_box)

	var title := Label.new()
	title.text = "滾筒嘉年華 · 《揍擊派對》風格快速開房設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	root_box.add_child(title)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_grid.add_theme_constant_override("h_separation", 18)
	preset_grid.add_theme_constant_override("v_separation", 8)
	root_box.add_child(preset_grid)

	var pace_keys: Array[String] = ["casual", "standard", "frantic"]
	var dur_keys: Array[String] = ["short", "standard", "long"]
	var spawn_keys: Array[String] = ["safe", "standard", "extreme"]
	var kb_keys: Array[String] = ["light", "standard", "heavy"]

	var pace_opt := _add_lobby_preset_opt(preset_grid, "1. 滾筒節奏 (難度)", ["休閒 (慢速熱身)", "標準 (推薦)", "狂暴 (高速刺激)"], pace_keys.find(str(data.get("preset_pace", "standard"))))
	var dur_opt := _add_lobby_preset_opt(preset_grid, "2. 單局時長", ["30 秒 (快節奏)", "50 秒 (標準)", "80 秒 (持久戰)"], dur_keys.find(str(data.get("preset_duration", "standard"))))
	var spawn_opt := _add_lobby_preset_opt(preset_grid, "3. 起跑線位置 (容錯度)", ["靠前安全 (遠離岩漿)", "標準中央 (平衡)", "極限貼邊 (靠近岩漿)"], spawn_keys.find(str(data.get("preset_spawn", "standard"))))
	var kb_opt := _add_lobby_preset_opt(preset_grid, "4. 撞擊推擠力道", ["輕推 (0.85 身位)", "標準 (1 身位)", "重擊飛退 (2.1 身位)"], kb_keys.find(str(data.get("preset_knockback", "standard"))))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 230)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false

	var adv_btn := Button.new()
	adv_btn.text = "▶ 展開進階微調參數 (速度/高度/加分表)"
	adv_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	adv_btn.pressed.connect(func():
		scroll.visible = not scroll.visible
		adv_btn.text = "▼ 收起進階微調參數" if scroll.visible else "▶ 展開進階微調參數 (速度/高度/加分表)"
	)
	root_box.add_child(adv_btn)
	root_box.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	var editors: Dictionary = {}
	editors["round_duration"] = _add_spin_row(grid, "單局時長 (秒)", float(data.get("round_duration", 50.0)), 15.0, 180.0, 5.0)
	editors["max_players"] = _add_spin_row(grid, "最大玩家人數 (1-16)", float(data.get("max_players", 8)), 1.0, 16.0, 1.0)
	editors["player_spawn_x"] = _add_spin_row(grid, "齊排起跑線 X 座標", float(data.get("player_spawn_x", 1.60)), -3.5, 6.5, 0.1)
	editors["roller_initial_speed"] = _add_spin_row(grid, "滾筒初始速度", float(data.get("roller_initial_speed", 6.2)), 2.0, 15.0, 0.2)
	editors["roller_max_speed"] = _add_spin_row(grid, "滾筒最大速度", float(data.get("roller_max_speed", 13.8)), 4.0, 28.0, 0.2)
	editors["roller_acceleration_exponent"] = _add_spin_row(grid, "加速曲線指數", float(data.get("roller_acceleration_exponent", 1.15)), 0.3, 3.0, 0.05)

	var curve_opt := OptionButton.new()
	curve_opt.add_item("線性遞增 (linear)", 0)
	curve_opt.add_item("指數提速 (exponential)", 1)
	curve_opt.add_item("分段提速 (stepped)", 2)
	var cm := str(data.get("speed_curve_mode", "linear"))
	curve_opt.selected = 1 if cm == "exponential" else (2 if cm == "stepped" else 0)
	_add_custom_row(grid, "速度曲線模式", curve_opt)
	editors["speed_curve_mode"] = curve_opt

	editors["spawn_interval_min"] = _add_spin_row(grid, "生成間隔下限 (秒)", float(data.get("spawn_interval_min", 0.92)), 0.5, 5.0, 0.05)
	editors["spawn_interval_max"] = _add_spin_row(grid, "生成間隔上限 (秒)", float(data.get("spawn_interval_max", 1.90)), 0.6, 6.0, 0.05)
	editors["min_safe_reaction_time"] = _add_spin_row(grid, "最短安全反應時間 (秒)", float(data.get("min_safe_reaction_time", 0.26)), 0.12, 0.80, 0.02)
	editors["gold_roller_probability"] = _add_spin_row(grid, "金色高滾筒出現機率", float(data.get("gold_roller_probability", 0.50)), 0.10, 0.90, 0.05)
	editors["max_same_type_streak"] = _add_spin_row(grid, "同色滾筒最大連發數", float(data.get("max_same_type_streak", 3)), 1.0, 8.0, 1.0)
	editors["knockback_distance"] = _add_spin_row(grid, "碰撞推擠距離 (身位)", float(data.get("knockback_distance", 1.35)), 0.3, 3.5, 0.05)
	editors["knockback_cooldown"] = _add_spin_row(grid, "推擠防重觸冷卻 (秒)", float(data.get("knockback_cooldown", 0.40)), 0.10, 1.50, 0.05)
	editors["jump_height"] = _add_spin_row(grid, "跳躍高度", float(data.get("jump_height", 1.65)), 0.80, 3.20, 0.05)
	editors["jump_air_time"] = _add_spin_row(grid, "跳躍滯空時間 (秒)", float(data.get("jump_air_time", 0.58)), 0.25, 1.20, 0.02)
	editors["crouch_height"] = _add_spin_row(grid, "下蹲判定高度", float(data.get("crouch_height", 0.72)), 0.35, 1.20, 0.02)
	editors["linear_points_per_dodge"] = _add_spin_row(grid, "每次躲避線性加分", float(data.get("linear_points_per_dodge", 0)), 0.0, 100.0, 1.0)

	var tie_opt := OptionButton.new()
	tie_opt.add_item("同躲避數並列名次 (shared_rank)", 0)
	tie_opt.add_item("依存活狀態/時長區分 (survival_time)", 1)
	var tr_rule := str(data.get("tie_break_rule", "shared_rank"))
	tie_opt.selected = 1 if tr_rule == "survival_time" else 0
	_add_custom_row(grid, "同分並列規則", tie_opt)
	editors["tie_break_rule"] = tie_opt

	var bonus_edit := LineEdit.new()
	var pts: Array = data.get("rank_bonus_points", [100, 80, 60, 40, 40, 40, 20, 20])
	var strs: PackedStringArray = []
	for p in pts:
		strs.append(str(p))
	bonus_edit.text = ",".join(strs)
	_add_custom_row(grid, "名次加分表 (第1~8名)", bonus_edit)
	editors["rank_bonus_points"] = bonus_edit

	var sync_adv_from_presets := func(_sel_idx: int) -> void:
		cfg.apply_pummel_presets(
			pace_keys[clampi(pace_opt.selected, 0, pace_keys.size() - 1)],
			dur_keys[clampi(dur_opt.selected, 0, dur_keys.size() - 1)],
			spawn_keys[clampi(spawn_opt.selected, 0, spawn_keys.size() - 1)],
			kb_keys[clampi(kb_opt.selected, 0, kb_keys.size() - 1)]
		)
		var synced: Dictionary = cfg.to_dict()
		for k in editors.keys():
			var ed = editors[k]
			if ed is SpinBox and synced.has(k):
				ed.value = float(synced[k])
		var scm := str(synced.get("speed_curve_mode", "linear"))
		curve_opt.selected = 1 if scm == "exponential" else (2 if scm == "stepped" else 0)

	pace_opt.item_selected.connect(sync_adv_from_presets)
	dur_opt.item_selected.connect(sync_adv_from_presets)
	spawn_opt.item_selected.connect(sync_adv_from_presets)
	kb_opt.item_selected.connect(sync_adv_from_presets)

	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	btn_bar.add_theme_constant_override("separation", 12)
	root_box.add_child(btn_bar)

	var reset_btn := Button.new()
	reset_btn.text = "恢復預設值"
	reset_btn.pressed.connect(func():
		var def_cfg = _new_config_instance()
		if def_cfg == null:
			return
		var def_dict: Dictionary = def_cfg.to_dict()
		if glb != null:
			var gs_reset = glb.get("game_settings")
			if gs_reset is Dictionary:
				gs_reset[SETTINGS_KEY] = def_dict
				if glb.has_method("save_game_settings"):
					glb.call("save_game_settings")
		layer.queue_free()
		_room_modal_overlay = null
		_open_room_settings_modal(lobby_node)
	)
	btn_bar.add_child(reset_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func():
		layer.queue_free()
		_room_modal_overlay = null
	)
	btn_bar.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "確定儲存至本房間"
	save_btn.pressed.connect(func():
		var out: Dictionary = cfg.to_dict()
		for k in editors.keys():
			var ed = editors[k]
			if ed is SpinBox:
				out[k] = ed.value
			elif ed is LineEdit:
				out[k] = ed.text
		var modes := ["linear", "exponential", "stepped"]
		out["speed_curve_mode"] = modes[clampi(curve_opt.selected, 0, modes.size() - 1)]
		var rules := ["shared_rank", "survival_time"]
		out["tie_break_rule"] = rules[clampi(tie_opt.selected, 0, rules.size() - 1)]
		out["preset_pace"] = pace_keys[clampi(pace_opt.selected, 0, pace_keys.size() - 1)]
		out["preset_duration"] = dur_keys[clampi(dur_opt.selected, 0, dur_keys.size() - 1)]
		out["preset_spawn"] = spawn_keys[clampi(spawn_opt.selected, 0, spawn_keys.size() - 1)]
		out["preset_knockback"] = kb_keys[clampi(kb_opt.selected, 0, kb_keys.size() - 1)]

		cfg.apply_dict(out)
		if glb != null:
			var gs_save = glb.get("game_settings")
			if gs_save is Dictionary:
				gs_save[SETTINGS_KEY] = cfg.to_dict()
				if glb.has_method("save_game_settings"):
					glb.call("save_game_settings")
		if _loader != null:
			_loader.note(MOD_ID + ": updated lobby room parameters")
		layer.queue_free()
		_room_modal_overlay = null
	)
	btn_bar.add_child(save_btn)


func _add_lobby_preset_opt(grid: GridContainer, label_text: String, items: Array, selected_idx: int) -> OptionButton:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(260, 32)
	for item_text in items:
		opt.add_item(str(item_text))
	opt.selected = selected_idx if selected_idx >= 0 else 1
	grid.add_child(opt)
	return opt


func _add_spin_row(grid: GridContainer, label_text: String, val: float, min_v: float, max_v: float, step_v: float) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)

	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step_v
	sb.value = val
	sb.custom_minimum_size = Vector2(180, 0)
	grid.add_child(sb)
	return sb


func _add_custom_row(grid: GridContainer, label_text: String, ctrl: Control) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)

	ctrl.custom_minimum_size = Vector2(220, 0)
	grid.add_child(ctrl)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		_toggle_roller_carnival_stage()


func _toggle_roller_carnival_stage() -> void:
	if _active_stage != null and is_instance_valid(_active_stage):
		_active_stage.queue_free()
		_active_stage = null
		if _loader != null:
			_loader.note(MOD_ID + ": closed Roller Carnival overlay stage")
		return

	var script_to_load = _game_script
	if script_to_load == null and not _mod_dir.is_empty():
		script_to_load = load(_mod_dir.path_join("roller_carnival_game.gd"))
	if script_to_load == null:
		if _loader != null:
			_loader.note(MOD_ID + ": failed to load roller_carnival_game.gd")
		return

	var stage: Node3D = Node3D.new()
	stage.set_script(script_to_load)
	get_tree().root.add_child(stage)
	_active_stage = stage
	if _loader != null:
		_loader.note(MOD_ID + ": launched Roller Carnival stage")
