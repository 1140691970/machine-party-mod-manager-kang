extends "res://minigames/intermission_new/components/intermission_game_picker.gd"

## MPML Override for res://minigames/intermission_new/components/intermission_game_picker.gd
## Includes Roller Carnival (ShapeCutter = 6) among the CRT picker candidates,
## displays its title, and supplies its briefing icon/controls before super()._ready().


static func _roller_display_name() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "滚筒嘉年华"
	if loc.begins_with("ZH"):
		return "滾筒嘉年華"
	return "ROLLER CARNIVAL"


static func _roller_brief_content() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "高处琥珀滚筒：按住 [S / ↓] 下蹲闪避；\n低处冷钢滚筒：按 [空格 / W / ↑] 跳跃越过；\n被撞击只会向左击退，推入左侧粉碎熔炉即淘汰！"
	if loc.begins_with("ZH"):
		return "高處琥珀滾筒：按住 [S / ↓] 下蹲閃避；\n低處冷鋼滾筒：按 [空白鍵 / W / ↑] 跳躍越過；\n被撞擊只會向左擊退，推入左側粉碎熔爐即淘汰！"
	return "HIGH AMBER ROLLER: Hold [S / Down] to crouch under.\nLOW STEEL ROLLER: Press [Space / W / Up] to jump over.\nHits knock you left into the shredder furnace. Rank by total dodges!"


static func _roller_jump_control_text() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "跳跃 [空格 / W]（低处冷钢滚筒）"
	if loc.begins_with("ZH"):
		return "跳躍 [空白鍵 / W]（低處冷鋼滾筒）"
	return "JUMP [SPACE / W] (LOW STEEL ROLLER)"


static func _roller_crouch_control_text() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "按住下蹲 [S / ↓]（高处琥珀滚筒）"
	if loc.begins_with("ZH"):
		return "按住下蹲 [S / ↓]（高處琥珀滾筒）"
	return "HOLD CROUCH [S] (HIGH AMBER ROLLER)"


func _ensure_roller_icon_resource() -> void:
	if intermission_manager == null:
		return
	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	var icon_res: Intermission_IconResource
	for res in intermission_manager.minigame_icon_resource_array:
		if res != null and res.identifier == mod_slot:
			icon_res = res
			break
	if icon_res == null:
		icon_res = Intermission_IconResource.new()
		icon_res.identifier = mod_slot
		intermission_manager.minigame_icon_resource_array.append(icon_res)
	icon_res.icon_texture = load(Globals.MinigameIconPaths[mod_slot])
	icon_res.brief_instructions_header_pages = ["LOC_IM_BRIEFING"]
	icon_res.brief_instructions_content_pages = [_roller_brief_content()]

	var ctrl_jump := IntermissionControlInputLabelData.new()
	ctrl_jump.control_text = _roller_jump_control_text()
	ctrl_jump.controller_text = "JUMP"
	ctrl_jump.keyboard_icons = [InputIconMapping.InputAction.KeyboardW]
	ctrl_jump.controller_icons = [InputIconMapping.InputAction.ControllerFaceSouth]

	var ctrl_crouch := IntermissionControlInputLabelData.new()
	ctrl_crouch.control_text = _roller_crouch_control_text()
	ctrl_crouch.controller_text = "CROUCH"
	ctrl_crouch.keyboard_icons = [InputIconMapping.InputAction.KeyboardS]
	ctrl_crouch.controller_icons = [InputIconMapping.InputAction.ControllerFaceEast]

	icon_res.controls_data = [ctrl_jump, ctrl_crouch]


func _ready() -> void:
	_ensure_roller_icon_resource()
	super()


func setup_minigame_pick_host() -> void:
	if not multiplayer.is_server():
		return

	_ensure_roller_icon_resource()

	for child in minigame_icon_spawn_parent.get_children():
		child.queue_free()

	active_icons = []

	await get_tree().create_timer(1, false).timeout
	if not is_inside_tree():
		return

	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	var active_indices: Array[int] = []
	var dictionary_array_to_send: Array[Dictionary] = []

	for identifier in Globals.MinigameIdentifier.values():
		if not Globals.CustomMinigamesWhitelist.has(identifier) and identifier != mod_slot:
			continue
		if Globals.CutsceneMinigameIdentifiers.has(identifier):
			continue
		if Globals.CutsceneGlitchedPickerMinigameIdentifiers.has(identifier):
			continue

		var dict_to_append := {
			"_minigame_identifier": identifier,
			"_is_played_already": false,
			"_is_in_playlist": false,
		}
		dictionary_array_to_send.append(dict_to_append)

	for item in dictionary_array_to_send:
		if item._minigame_identifier != Globals.MinigameIdentifier.EMPTY:
			item._is_in_playlist = item._minigame_identifier in intermission_manager.game.session_minigame_list
			item._is_played_already = item._minigame_identifier in intermission_manager.game.session_minigame_played_list

	dictionary_array_to_send.shuffle()

	var last_minigame_index = intermission_manager.game.session_last_minigame_identifier
	var next_minigame_index: int = 0
	var next_minigame_identifier: Globals.MinigameIdentifier = Globals.MinigameIdentifier.EMPTY

	if !Globals.all_minigames_finished and not intermission_manager.game.session_minigame_list.is_empty():
		if intermission_manager.game.debug_no_shuffle:
			next_minigame_index = 0
		else:
			next_minigame_index = randi_range(0, intermission_manager.game.session_minigame_list.size() - 1)
		next_minigame_identifier = intermission_manager.game.session_minigame_list[next_minigame_index]

	# Keep the drawn game on the CRT when the shuffle puts it beyond the grid.
	_ensure_identifier_in_first_15(dictionary_array_to_send, next_minigame_identifier)

	var grid_limit: int = min(15, dictionary_array_to_send.size())
	for i in grid_limit:
		var minigame_dict: Dictionary = dictionary_array_to_send[i]
		if minigame_dict._is_in_playlist and not minigame_dict._is_played_already:
			active_indices.append(i)

	if active_indices.is_empty():
		active_indices.append(0)

	setup_icons_from_data_rpc.rpc(
		dictionary_array_to_send,
		last_minigame_index,
		next_minigame_identifier,
		active_indices.pick_random()
	)


func _ensure_identifier_in_first_15(
	arr: Array[Dictionary],
	target_id: Globals.MinigameIdentifier
) -> void:
	if arr.size() <= 15 or target_id == Globals.MinigameIdentifier.EMPTY:
		return

	var target_idx := -1
	for i in range(arr.size()):
		if arr[i]._minigame_identifier == target_id:
			target_idx = i
			break

	if target_idx < 0 or target_idx < 15:
		return

	var swap_idx := -1
	for i in range(15):
		var d: Dictionary = arr[i]
		if not d._is_in_playlist or d._is_played_already:
			swap_idx = i
			break
	if swap_idx < 0:
		swap_idx = 14

	var tmp: Dictionary = arr[swap_idx]
	arr[swap_idx] = arr[target_idx]
	arr[target_idx] = tmp


func debug_update() -> void:
	_ensure_roller_icon_resource()
	super()
	if debug_active_identifier == Globals.MinigameIdentifier.ShapeCutter:
		var label_text: String = tr("LOC_IM_NEXT_SIMULATION") % _roller_display_name()
		next_minigame_label.text = label_text
		next_minigame_label_higher.text = label_text


func pick_next_game(index: int, random_active_index_icon_index: int):
	super(index, random_active_index_icon_index)
	if index == Globals.MinigameIdentifier.ShapeCutter:
		var label_text: String = tr("LOC_IM_NEXT_SIMULATION") % _roller_display_name()
		next_minigame_label.text = label_text
		next_minigame_label_higher.text = label_text


func set_viewfinder_for_briefing_screen(minigame_identifier: Globals.MinigameIdentifier):
	_ensure_roller_icon_resource()
	super(minigame_identifier)
	if minigame_identifier == Globals.MinigameIdentifier.ShapeCutter:
		var label_text: String = tr("LOC_IM_NEXT_SIMULATION") % _roller_display_name()
		next_minigame_label.text = label_text
		next_minigame_label_higher.text = label_text
