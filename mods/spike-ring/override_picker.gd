extends "res://minigames/intermission_new/components/intermission_game_picker.gd"

## Multi-Minigame Coexistence Hub Override for
## res://minigames/intermission_new/components/intermission_game_picker.gd
## Includes every custom minigame registered in Engine meta `_mpm_custom_minigames`
## in the 15-slot CRT picker, briefing screen, and localized title banners.


static func _get_custom_minigames() -> Dictionary:
	var raw = Engine.get_meta("_mpm_custom_minigames", {})
	if raw is Dictionary:
		return raw
	return {}


static func _sorted_custom_slots(custom_map: Dictionary) -> Array:
	var slots: Array = []
	for raw_key in custom_map.keys():
		slots.append(int(raw_key))
	slots.sort()
	return slots


static func _resolve_callable_string(spec: Dictionary, key: String, fallback: String) -> String:
	var fn = spec.get(key, null)
	if fn is Callable and (fn as Callable).is_valid():
		return str((fn as Callable).call())
	if fn is String and not (fn as String).is_empty():
		return fn as String
	return fallback


static func _resolve_icon_texture(slot_id: int, spec: Dictionary) -> Texture2D:
	var tex = spec.get("icon_texture", null)
	if tex is Texture2D:
		return tex as Texture2D
	if Globals.MinigameIconPaths.has(slot_id):
		return load(Globals.MinigameIconPaths[slot_id]) as Texture2D
	return null


func _ensure_custom_icon_resources() -> void:
	if intermission_manager == null:
		return
	var custom_map: Dictionary = _get_custom_minigames()
	var custom_slots: Array = _sorted_custom_slots(custom_map)
	for slot_id in custom_slots:
		var spec_raw = custom_map[slot_id]
		if not (spec_raw is Dictionary):
			continue
		var spec: Dictionary = spec_raw
		var icon_res: Intermission_IconResource = null
		for res in intermission_manager.minigame_icon_resource_array:
			if res != null and int(res.identifier) == slot_id:
				icon_res = res
				break
		if icon_res == null:
			icon_res = Intermission_IconResource.new()
			icon_res.identifier = slot_id
			intermission_manager.minigame_icon_resource_array.append(icon_res)
		var tex := _resolve_icon_texture(slot_id, spec)
		if tex != null:
			icon_res.icon_texture = tex
		icon_res.brief_instructions_header_pages = ["LOC_IM_BRIEFING"]
		icon_res.brief_instructions_content_pages = [_resolve_callable_string(spec, "brief_content", "")]

		var controls: Array[IntermissionControlInputLabelData] = []
		var ctrl_fn = spec.get("controls_data", null)
		var raw_controls: Array = []
		if ctrl_fn is Callable and (ctrl_fn as Callable).is_valid():
			var produced = (ctrl_fn as Callable).call()
			if produced is Array:
				raw_controls = produced
		elif ctrl_fn is Array:
			raw_controls = ctrl_fn
		for entry in raw_controls:
			if entry is IntermissionControlInputLabelData:
				controls.append(entry)
			elif entry is Dictionary:
				var d: Dictionary = entry
				var ctrl := IntermissionControlInputLabelData.new()
				ctrl.control_text = str(d.get("control_text", ""))
				ctrl.controller_text = str(d.get("controller_text", ""))
				var kb_icons: Array[InputIconMapping.InputAction] = []
				var raw_kb = d.get("keyboard_icons", [])
				if raw_kb is Array:
					for k in raw_kb:
						if k is String and InputIconMapping.InputAction.has(k):
							kb_icons.append(int(InputIconMapping.InputAction[k]))
						else:
							kb_icons.append(int(k))
				ctrl.keyboard_icons = kb_icons
				var pad_icons: Array[InputIconMapping.InputAction] = []
				var raw_pad = d.get("controller_icons", [])
				if raw_pad is Array:
					for p in raw_pad:
						if p is String and InputIconMapping.InputAction.has(p):
							pad_icons.append(int(InputIconMapping.InputAction[p]))
						else:
							pad_icons.append(int(p))
				ctrl.controller_icons = pad_icons
				controls.append(ctrl)
		icon_res.controls_data = controls


func _apply_custom_title(slot_id: int) -> void:
	var custom_map: Dictionary = _get_custom_minigames()
	if not custom_map.has(slot_id):
		return
	var spec = custom_map[slot_id]
	if not (spec is Dictionary):
		return
	var title: String = _resolve_callable_string(spec as Dictionary, "display_name", str(spec.get("mod_id", str(slot_id))))
	var label_text: String = tr("LOC_IM_NEXT_SIMULATION") % title
	next_minigame_label.text = label_text
	next_minigame_label_higher.text = label_text


func _ready() -> void:
	_ensure_custom_icon_resources()
	super()


func setup_minigame_pick_host() -> void:
	if not multiplayer.is_server():
		return

	_ensure_custom_icon_resources()

	for child in minigame_icon_spawn_parent.get_children():
		child.queue_free()

	active_icons = []

	await get_tree().create_timer(1, false).timeout
	if not is_inside_tree():
		return

	var custom_map: Dictionary = _get_custom_minigames()
	var custom_slots: Array = _sorted_custom_slots(custom_map)
	var active_indices: Array[int] = []
	var dictionary_array_to_send: Array[Dictionary] = []
	var seen_ids: Dictionary = {}

	var candidate_ids: Array = []
	for identifier in Globals.MinigameIdentifier.values():
		candidate_ids.append(int(identifier))
	for slot_id in custom_slots:
		if not candidate_ids.has(slot_id):
			candidate_ids.append(slot_id)

	for raw_id in candidate_ids:
		var identifier: int = int(raw_id)
		if seen_ids.has(identifier):
			continue
		if not Globals.CustomMinigamesWhitelist.has(identifier) and not custom_map.has(identifier):
			continue
		if Globals.CutsceneMinigameIdentifiers.has(identifier):
			continue
		if Globals.CutsceneGlitchedPickerMinigameIdentifiers.has(identifier):
			continue
		seen_ids[identifier] = true
		dictionary_array_to_send.append({
			"_minigame_identifier": identifier,
			"_is_played_already": false,
			"_is_in_playlist": false,
		})

	for item in dictionary_array_to_send:
		if int(item._minigame_identifier) != int(Globals.MinigameIdentifier.EMPTY):
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

	# Keep the drawn game on the CRT when the shuffle puts it beyond the 15-slot grid.
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
		if int(arr[i]._minigame_identifier) == int(target_id):
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
	_ensure_custom_icon_resources()
	super()
	_apply_custom_title(int(debug_active_identifier))


func pick_next_game(index: int, random_active_index_icon_index: int):
	super(index, random_active_index_icon_index)
	_apply_custom_title(int(index))


func set_viewfinder_for_briefing_screen(minigame_identifier: Globals.MinigameIdentifier):
	_ensure_custom_icon_resources()
	super(minigame_identifier)
	_apply_custom_title(int(minigame_identifier))
