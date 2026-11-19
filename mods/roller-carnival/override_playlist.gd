extends "res://scenes/lobby/components/playlist_handler.gd"

## MPML Override for res://scenes/lobby/components/playlist_handler.gd
## Adds Roller Carnival (ShapeCutter slot = 6) to the Custom Playlist selector.

var _roller_icon_cache: Texture2D = null


static func roller_display_name() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "滚筒嘉年华"
	if loc.begins_with("ZH"):
		return "滾筒嘉年華"
	return "ROLLER CARNIVAL"


static func build_roller_icon_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.11, 0.08, 0.07, 1.0))

	for y in range(64):
		for x in range(64):
			var border: bool = (x < 3 or x >= 61 or y < 3 or y >= 61)
			if border:
				img.set_pixel(x, y, Color(0.95, 0.72, 0.24, 1.0))
			elif y >= 50:
				# Glowing lava strip on left / bottom
				var wave := sin(float(x) * 0.28) * 0.12
				img.set_pixel(x, y, Color(1.0, clampf(0.38 + wave, 0.1, 0.7), 0.06, 1.0))
			elif x <= 12 and y >= 14:
				img.set_pixel(x, y, Color(0.98, 0.34, 0.05, 1.0))

			# Upper gold roller cylinder (rows 15..27)
			if x >= 16 and x <= 55 and y >= 15 and y <= 27:
				var shade := 1.0 - absf(float(y - 21)) / 7.5 * 0.35
				img.set_pixel(x, y, Color(1.0 * shade, 0.78 * shade, 0.18 * shade, 1.0))

			# Lower silver roller cylinder (rows 35..46)
			if x >= 18 and x <= 55 and y >= 35 and y <= 46:
				var shade2 := 1.0 - absf(float(y - 40.5)) / 7.0 * 0.35
				img.set_pixel(x, y, Color(0.84 * shade2, 0.89 * shade2, 0.96 * shade2, 1.0))

	return ImageTexture.create_from_image(img)


func _get_roller_icon() -> Texture2D:
	if _roller_icon_cache == null:
		_roller_icon_cache = build_roller_icon_texture()
	return _roller_icon_cache


func _apply_roller_item_visuals(item: MinigameListItem) -> void:
	if item == null:
		return
	item.name_label.text = roller_display_name()
	item.minigame_icon.texture = _get_roller_icon()


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
