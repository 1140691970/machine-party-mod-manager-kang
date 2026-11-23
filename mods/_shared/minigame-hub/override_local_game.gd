extends "res://scenes/local_game/script/local_game.gd"

## Multi-Minigame Coexistence Hub Override for res://scenes/local_game/script/local_game.gd
## Integrates all mods registered in Engine meta `_mpm_custom_minigames` into local couch play.


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


static func _slot_debug_name(slot_id: int, custom_map: Dictionary) -> String:
	var enum_keys: Array = Globals.MinigameIdentifier.keys()
	if slot_id >= 0 and slot_id < enum_keys.size():
		return str(enum_keys[slot_id])
	if custom_map.has(slot_id):
		var spec = custom_map[slot_id]
		if spec is Dictionary:
			return str(spec.get("mod_id", str(slot_id)))
	return str(slot_id)


func generate_session_playlist() -> void:
	var custom_map: Dictionary = _get_custom_minigames()
	var custom_slots: Array = _sorted_custom_slots(custom_map)
	var minigames_shuffled: Array[Globals.MinigameIdentifier] = []
	session_minigame_rounds.clear()

	if GameManager.custom_game:
		if Globals.session_playlist.is_empty():
			for mlr in Globals.default_playlist:
				Globals.session_playlist.append(mlr)

		if GameManager.arcade_game:
			var arcade_games_count: int = 10
			var all_allowed_minigame_identifiers: Array = Globals.CustomMinigamesWhitelist.duplicate(true)
			for slot_id in custom_slots:
				if not all_allowed_minigame_identifiers.has(slot_id):
					all_allowed_minigame_identifiers.append(slot_id)
			all_allowed_minigame_identifiers.shuffle()

			var count: int = min(arcade_games_count, all_allowed_minigame_identifiers.size())
			for i in count:
				var identifier: Globals.MinigameIdentifier = all_allowed_minigame_identifiers[i]
				minigames_shuffled.append(identifier)
				session_minigame_rounds[identifier] = randi_range(1, 2)
		else:
			for game in Globals.session_playlist:
				var gid: int = int(game.game_identifier)
				if not Globals.CustomMinigamesWhitelist.has(game.game_identifier) and not custom_map.has(gid):
					continue
				minigames_shuffled.append(game.game_identifier)
				session_minigame_rounds[game.game_identifier] = max(game.total_rounds, 1)

			if GameManager.custom_shuffled:
				minigames_shuffled.shuffle()
	else:
		Globals.session_playlist.clear()
		var present_slots: Dictionary = {}
		for mlr in Globals.default_playlist:
			Globals.session_playlist.append(mlr)
			present_slots[int(mlr.game_identifier)] = true

		for slot_id in custom_slots:
			if not present_slots.has(slot_id):
				var spec = custom_map[slot_id]
				var default_rounds: int = 1
				if spec is Dictionary:
					default_rounds = max(1, int(spec.get("default_rounds", 1)))
				var fallback_mlr := MinigameListResource.create(slot_id, default_rounds)
				Globals.session_playlist.append(fallback_mlr)
				present_slots[slot_id] = true

		for game in Globals.session_playlist:
			minigames_shuffled.append(game.game_identifier)
			session_minigame_rounds[game.game_identifier] = max(game.total_rounds, 1)

	if not debug_no_shuffle:
		minigames_shuffled.shuffle()

	total_games_count = minigames_shuffled.size()

	for game in minigames_shuffled:
		print("Generating session playlist with: ", _slot_debug_name(int(game), custom_map))

	session_minigame_list = minigames_shuffled


func load_minigame(minigame_identifier: Globals.MinigameIdentifier, _is_round: bool, _total_rounds: int = -1):
	var custom_map: Dictionary = _get_custom_minigames()
	var slot_id: int = int(minigame_identifier)
	if not custom_map.has(slot_id) or Globals.MinigamePaths.has(minigame_identifier):
		return await super(minigame_identifier, _is_round, _total_rounds)

	var spec: Dictionary = custom_map[slot_id]
	var minigame_scene: PackedScene = spec.get("packed_scene", null) as PackedScene
	if minigame_scene == null:
		var scene_path: String = str(spec.get("scene_path", ""))
		if not scene_path.is_empty():
			minigame_scene = load(scene_path) as PackedScene
	if minigame_scene == null:
		return await super(minigame_identifier, _is_round, _total_rounds)

	Globals.current_minigame_identifier = minigame_identifier
	if multiplayer.is_server():
		if _total_rounds >= 0:
			session_current_minigame_round = 1
			session_current_minigame_max_rounds = _total_rounds
		DecalManager.clear_rpc.rpc()
		PropManager.clear_rpc.rpc()

	if minigame != null:
		minigame.minigame_loaded.disconnect(_on_minigame_loaded)
		minigame.minigame_ready.disconnect(_on_minigame_ready)
		minigame.cleanup_rpc()
		await get_tree().create_timer(1.0).timeout

	var minigame_instance = minigame_scene.instantiate()
	minigame = minigame_instance

	minigame.minigame_loaded.connect(_on_minigame_loaded)
	minigame.minigame_ready.connect(_on_minigame_ready)
	minigame.player_scored.connect(_on_minigame_player_scored)
	minigame.player_scores_finalized.connect(_on_minigame_player_score_finalized)

	GameManager.current_minigame_identifier = minigame_identifier
	minigame_parent.add_child(minigame_instance, true)
