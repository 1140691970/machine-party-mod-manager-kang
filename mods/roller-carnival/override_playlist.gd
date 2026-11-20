extends "res://scenes/lobby/components/playlist_handler.gd"

## Multi-Minigame Coexistence Hub Override for res://scenes/lobby/components/playlist_handler.gd
## Displays all custom minigames registered in Engine meta `_mpm_custom_minigames`
## in the Custom Playlist selector with their localized names and icons.


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


static func _resolve_display_name(spec: Dictionary, fallback: String) -> String:
	var fn = spec.get("display_name", null)
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


func _apply_custom_item_visuals(item: MinigameListItem, custom_map: Dictionary) -> void:
	if item == null:
		return
	var slot_id: int = int(item.minigame_identifier)
	if not custom_map.has(slot_id):
		return
	var spec = custom_map[slot_id]
	if not (spec is Dictionary):
		return
	item.name_label.text = _resolve_display_name(spec as Dictionary, str(spec.get("mod_id", str(slot_id))))
	var tex := _resolve_icon_texture(slot_id, spec as Dictionary)
	if tex != null:
		item.minigame_icon.texture = tex


func _ready() -> void:
	super()

	var custom_map: Dictionary = _get_custom_minigames()
	var custom_slots: Array = _sorted_custom_slots(custom_map)
	for slot_id in custom_slots:
		var has_all_button := false
		for b in all_minigames_list_items:
			if int(b.minigame_identifier) == slot_id:
				has_all_button = true
				_apply_custom_item_visuals(b, custom_map)
				break
		if not has_all_button:
			add_minigame_button(MinigameListItem.BehaviourType.All, slot_id)

	load_current_playlist()


func add_minigame_button(_behaviour, minigame_id, rounds: int = 1):
	super(_behaviour, minigame_id, rounds)
	var custom_map: Dictionary = _get_custom_minigames()
	var slot_id: int = int(minigame_id)
	if not custom_map.has(slot_id):
		return

	if _behaviour == MinigameListItem.BehaviourType.All and not all_minigames_list_items.is_empty():
		_apply_custom_item_visuals(all_minigames_list_items[-1], custom_map)
	elif _behaviour == MinigameListItem.BehaviourType.Selected and not selected_minigames_list_items.is_empty():
		_apply_custom_item_visuals(selected_minigames_list_items[-1], custom_map)


func load_current_playlist() -> void:
	var custom_map: Dictionary = _get_custom_minigames()

	for mli in selected_minigames_list_items:
		if is_instance_valid(mli):
			mli.free()

	selected_minigames_list_items.clear()

	for b in all_minigames_list_items:
		b.set_inactive(false)
		if custom_map.has(int(b.minigame_identifier)):
			_apply_custom_item_visuals(b, custom_map)

	for mlr in Globals.session_playlist:
		var gid: int = int(mlr.game_identifier)
		if not Globals.CustomMinigamesWhitelist.has(mlr.game_identifier) and not custom_map.has(gid):
			continue

		add_minigame_button(
			MinigameListItem.BehaviourType.Selected,
			mlr.game_identifier,
			mlr.total_rounds
		)

		for b in all_minigames_list_items:
			if int(b.minigame_identifier) == gid:
				b.set_inactive(true)
				break


func _on_default_button_pressed() -> void:
	var custom_map: Dictionary = _get_custom_minigames()
	_on_reset_button_pressed()

	for minigame_item in Globals.default_playlist:
		var minigame_identifier: Globals.MinigameIdentifier = minigame_item.game_identifier
		var gid: int = int(minigame_identifier)
		if not Globals.CustomMinigamesWhitelist.has(minigame_identifier) and not custom_map.has(gid):
			continue
		for b in all_minigames_list_items:
			if int(b.minigame_identifier) == gid:
				_on_minigame_add_pressed(b, false)
				break

	for minigame_item in Globals.default_playlist:
		var gid: int = int(minigame_item.game_identifier)
		for selected_minigame in selected_minigames_list_items:
			if int(selected_minigame.minigame_identifier) == gid:
				selected_minigame.set_rounds(minigame_item.total_rounds)
				break
