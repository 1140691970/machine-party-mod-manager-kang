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


func _get_sdk():
	if not Engine.has_meta(&"mpm_core"):
		return null
	var core_raw = Engine.get_meta(&"mpm_core")
	if core_raw is Dictionary:
		return (core_raw as Dictionary).get("minigame_sdk", null)
	return null


func _get_event_bus():
	if not Engine.has_meta(&"mpm_core"):
		return null
	var core_raw = Engine.get_meta(&"mpm_core")
	if core_raw is Dictionary:
		return (core_raw as Dictionary).get("event_bus", null)
	return null


func _evaluate_slot(slot_id: int, custom_map: Dictionary) -> Dictionary:
	if not custom_map.has(slot_id):
		return {"eligible": true, "hard_blocked": false, "soft_warning": false, "reason_key": ""}
	var spec_raw = custom_map[slot_id]
	if not (spec_raw is Dictionary):
		return {"eligible": true, "hard_blocked": false, "soft_warning": false, "reason_key": ""}
	var sdk = _get_sdk()
	if sdk == null or not sdk.has_method("evaluate_minigame_eligibility"):
		return {"eligible": true, "hard_blocked": false, "soft_warning": false, "reason_key": ""}
	var res = sdk.evaluate_minigame_eligibility(spec_raw as Dictionary, {})
	if res is Dictionary:
		return res as Dictionary
	return {"eligible": true, "hard_blocked": false, "soft_warning": false, "reason_key": ""}


func _format_tag(res: Dictionary, spec: Dictionary) -> String:
	var sdk = _get_sdk()
	if sdk == null or not sdk.has_method("format_admission_tag"):
		return ""
	return str(sdk.format_admission_tag(res, spec))


func _apply_custom_item_visuals(item: MinigameListItem, custom_map: Dictionary, is_selected: bool = false) -> void:
	if item == null:
		return
	var slot_id: int = int(item.minigame_identifier)
	if not custom_map.has(slot_id):
		return
	var spec_raw = custom_map[slot_id]
	if not (spec_raw is Dictionary):
		return
	var spec: Dictionary = spec_raw as Dictionary
	var display_title: String = _resolve_display_name(spec, str(spec.get("mod_id", str(slot_id))))
	var res: Dictionary = _evaluate_slot(slot_id, custom_map)
	var tag: String = _format_tag(res, spec)
	item.name_label.text = display_title if tag.is_empty() else "%s %s" % [display_title, tag]
	var tex := _resolve_icon_texture(slot_id, spec)
	if tex != null:
		item.minigame_icon.texture = tex
	var hard_blocked: bool = bool(res.get("hard_blocked", false))
	item.set_meta(&"_mpm_hard_blocked", hard_blocked)
	if is_selected:
		item.modulate = Color(0.68, 0.68, 0.68, 0.78) if hard_blocked else Color.WHITE
	elif hard_blocked:
		item.set_inactive(true)


func _refresh_admission_states() -> void:
	var custom_map: Dictionary = _get_custom_minigames()
	var selected_ids: Dictionary = {}
	for sel in selected_minigames_list_items:
		if is_instance_valid(sel):
			var sid: int = int(sel.minigame_identifier)
			selected_ids[sid] = true
			if custom_map.has(sid):
				_apply_custom_item_visuals(sel, custom_map, true)
	for b in all_minigames_list_items:
		if not is_instance_valid(b):
			continue
		var gid: int = int(b.minigame_identifier)
		b.set_inactive(selected_ids.has(gid))
		if custom_map.has(gid):
			_apply_custom_item_visuals(b, custom_map, false)


func _on_team_state_changed(_payload: Dictionary = {}) -> void:
	_refresh_admission_states()


func _ready() -> void:
	super()

	var custom_map: Dictionary = _get_custom_minigames()
	var custom_slots: Array = _sorted_custom_slots(custom_map)
	for slot_id in custom_slots:
		var has_all_button := false
		for b in all_minigames_list_items:
			if int(b.minigame_identifier) == slot_id:
				has_all_button = true
				_apply_custom_item_visuals(b, custom_map, false)
				break
		if not has_all_button:
			add_minigame_button(MinigameListItem.BehaviourType.All, slot_id)

	load_current_playlist()
	var bus = _get_event_bus()
	if bus != null and bus.has_method("on"):
		bus.on("team_party.state_changed", Callable(self, "_on_team_state_changed"))


func _exit_tree() -> void:
	var bus = _get_event_bus()
	if bus != null and bus.has_method("off"):
		bus.off("team_party.state_changed", Callable(self, "_on_team_state_changed"))


func add_minigame_button(_behaviour, minigame_id, rounds: int = 1):
	super(_behaviour, minigame_id, rounds)
	var custom_map: Dictionary = _get_custom_minigames()
	var slot_id: int = int(minigame_id)
	if not custom_map.has(slot_id):
		return

	if _behaviour == MinigameListItem.BehaviourType.All and not all_minigames_list_items.is_empty():
		_apply_custom_item_visuals(all_minigames_list_items[-1], custom_map, false)
	elif _behaviour == MinigameListItem.BehaviourType.Selected and not selected_minigames_list_items.is_empty():
		_apply_custom_item_visuals(selected_minigames_list_items[-1], custom_map, true)


func _on_minigame_add_pressed(minigame_list_item, save_playlist: bool = true):
	if minigame_list_item != null and bool(minigame_list_item.get_meta(&"_mpm_hard_blocked", false)):
		return
	super(minigame_list_item, save_playlist)


func load_current_playlist() -> void:
	var custom_map: Dictionary = _get_custom_minigames()

	for mli in selected_minigames_list_items:
		if is_instance_valid(mli):
			mli.free()

	selected_minigames_list_items.clear()

	for b in all_minigames_list_items:
		b.set_inactive(false)
		if custom_map.has(int(b.minigame_identifier)):
			_apply_custom_item_visuals(b, custom_map, false)

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


func _on_reset_button_pressed() -> void:
	super()
	_refresh_admission_states()


func _on_default_button_pressed() -> void:
	var custom_map: Dictionary = _get_custom_minigames()
	_on_reset_button_pressed()

	for minigame_item in Globals.default_playlist:
		var minigame_identifier: Globals.MinigameIdentifier = minigame_item.game_identifier
		var gid: int = int(minigame_identifier)
		if not Globals.CustomMinigamesWhitelist.has(minigame_identifier) and not custom_map.has(gid):
			continue
		if custom_map.has(gid) and bool(_evaluate_slot(gid, custom_map).get("hard_blocked", false)):
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
