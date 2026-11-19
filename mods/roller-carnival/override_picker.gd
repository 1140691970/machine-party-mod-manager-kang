extends "res://minigames/intermission_new/components/intermission_game_picker.gd"

## MPML Override for res://minigames/intermission_new/components/intermission_game_picker.gd
## Ensures Roller Carnival (ShapeCutter = 6) appears on the 15-icon CRT picker grid,
## displays its title, and supplies its briefing icon/controls before super()._ready().


static func _roller_display_name() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "滚筒嘉年华"
	if loc.begins_with("ZH"):
		return "滾筒嘉年華"
	return "ROLLER CARNIVAL"


static func _build_picker_icon() -> Texture2D:
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
	return ImageTexture.create_from_image(img)


func _ensure_roller_icon_resource() -> void:
	if intermission_manager == null:
		return
	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	for res in intermission_manager.minigame_icon_resource_array:
		if res != null and res.identifier == mod_slot:
			if res.icon_texture == null:
				res.icon_texture = _build_picker_icon()
			return

	var icon_res := Intermission_IconResource.new()
	icon_res.identifier = mod_slot
	icon_res.icon_texture = _build_picker_icon()
	icon_res.brief_instructions_header_pages = ["ROLLER CARNIVAL"]
	icon_res.brief_instructions_content_pages = [
		"金色高滾筒：按 [S] 下蹲躲過；\n銀色低滾筒：按 [空白鍵] 跳躍越過；\n被撞擊只會向左推擠，掉入岩漿即淘汰！"
	]

	var ctrl_jump := IntermissionControlInputLabelData.new()
	ctrl_jump.control_text = "JUMP / 跳躍 (銀色低滾筒)"
	ctrl_jump.controller_text = "JUMP"
	ctrl_jump.keyboard_icons = [InputIconMapping.InputAction.KeyboardW]
	ctrl_jump.controller_icons = [InputIconMapping.InputAction.ControllerFaceSouth]

	var ctrl_crouch := IntermissionControlInputLabelData.new()
	ctrl_crouch.control_text = "CROUCH / 下蹲 (金色高滾筒)"
	ctrl_crouch.controller_text = "CROUCH"
	ctrl_crouch.keyboard_icons = [InputIconMapping.InputAction.KeyboardS]
	ctrl_crouch.controller_icons = [InputIconMapping.InputAction.ControllerFaceEast]

	icon_res.controls_data = [ctrl_jump, ctrl_crouch]
	intermission_manager.minigame_icon_resource_array.append(icon_res)


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

	# The CRT grid displays 15 icons (indices 0..14); with 16 candidates, ensure
	# the picked game (and ideally mod_slot if still unplayed) fits within 0..14.
	_ensure_identifier_in_first_15(dictionary_array_to_send, next_minigame_identifier, next_minigame_identifier)
	if mod_slot in intermission_manager.game.session_minigame_list and not (mod_slot in intermission_manager.game.session_minigame_played_list):
		_ensure_identifier_in_first_15(dictionary_array_to_send, mod_slot, next_minigame_identifier)

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
	target_id: Globals.MinigameIdentifier,
	protected_id: Globals.MinigameIdentifier
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
		if d._minigame_identifier != protected_id and (not d._is_in_playlist or d._is_played_already):
			swap_idx = i
			break
	if swap_idx < 0:
		for i in range(15):
			if arr[i]._minigame_identifier != protected_id:
				swap_idx = i
				break
	if swap_idx < 0:
		swap_idx = 14

	var tmp: Dictionary = arr[swap_idx]
	arr[swap_idx] = arr[target_idx]
	arr[target_idx] = tmp


func debug_update() -> void:
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
	super(minigame_identifier)
	if minigame_identifier == Globals.MinigameIdentifier.ShapeCutter:
		var label_text: String = tr("LOC_IM_NEXT_SIMULATION") % _roller_display_name()
		next_minigame_label.text = label_text
		next_minigame_label_higher.text = label_text
