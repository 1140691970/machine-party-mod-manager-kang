extends "res://scenes/lobby/components/playlist_handler.gd"

## MPML Override for res://scenes/lobby/components/playlist_handler.gd
## Adds Roller Carnival (ShapeCutter slot = 6) to the Custom Playlist selector.


static func roller_display_name() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "滚筒嘉年华"
	if loc.begins_with("ZH"):
		return "滾筒嘉年華"
	return "ROLLER CARNIVAL"


func _apply_roller_item_visuals(item: MinigameListItem) -> void:
	if item == null:
		return
	item.name_label.text = roller_display_name()
	item.minigame_icon.texture = load(Globals.MinigameIconPaths[Globals.MinigameIdentifier.ShapeCutter])


func _ready() -> void:
	super()

	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	var has_all_button := false
	for b in all_minigames_list_items:
		if b.minigame_identifier == mod_slot:
			has_all_button = true
			_apply_roller_item_visuals(b)
			break

	if not has_all_button:
		add_minigame_button(MinigameListItem.BehaviourType.All, mod_slot)

	load_current_playlist()


func add_minigame_button(_behaviour, minigame_id, rounds: int = 1):
	super(_behaviour, minigame_id, rounds)
	if minigame_id != Globals.MinigameIdentifier.ShapeCutter:
		return

	if _behaviour == MinigameListItem.BehaviourType.All and not all_minigames_list_items.is_empty():
		_apply_roller_item_visuals(all_minigames_list_items[-1])
	elif _behaviour == MinigameListItem.BehaviourType.Selected and not selected_minigames_list_items.is_empty():
		_apply_roller_item_visuals(selected_minigames_list_items[-1])


func load_current_playlist() -> void:
	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter

	for mli in selected_minigames_list_items:
		if is_instance_valid(mli):
			mli.free()

	selected_minigames_list_items.clear()

	for b in all_minigames_list_items:
		b.set_inactive(false)
		if b.minigame_identifier == mod_slot:
			_apply_roller_item_visuals(b)

	for mlr in Globals.session_playlist:
		if not Globals.CustomMinigamesWhitelist.has(mlr.game_identifier) and mlr.game_identifier != mod_slot:
			continue

		add_minigame_button(
			MinigameListItem.BehaviourType.Selected,
			mlr.game_identifier,
			mlr.total_rounds
		)

		for b in all_minigames_list_items:
			if b.minigame_identifier == mlr.game_identifier:
				b.set_inactive(true)
				break


func _on_default_button_pressed() -> void:
	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	_on_reset_button_pressed()

	for minigame_item in Globals.default_playlist:
		var minigame_identifier: Globals.MinigameIdentifier = minigame_item.game_identifier
		if not Globals.CustomMinigamesWhitelist.has(minigame_identifier) and minigame_identifier != mod_slot:
			continue
		for b in all_minigames_list_items:
			if b.minigame_identifier == minigame_identifier:
				_on_minigame_add_pressed(b, false)
				break

	for minigame_item in Globals.default_playlist:
		var minigame_identifier: Globals.MinigameIdentifier = minigame_item.game_identifier
		for selected_minigame in selected_minigames_list_items:
			if selected_minigame.minigame_identifier == minigame_identifier:
				selected_minigame.set_rounds(minigame_item.total_rounds)
				break
