extends "res://scripts/scenes/game/game.gd"

## MPML Override for res://scripts/scenes/game/game.gd
## Integrates Roller Carnival (slot Globals.MinigameIdentifier.ShapeCutter = 6)
## into Official Default, Custom Playlist, and Arcade random minigame pools.


func generate_session_playlist() -> void:
	var minigames_shuffled: Array[Globals.MinigameIdentifier] = []
	var mod_slot: Globals.MinigameIdentifier = Globals.MinigameIdentifier.ShapeCutter
	session_minigame_rounds.clear()

	if GameManager.custom_game:
		if Globals.session_playlist.is_empty():
			for mlr in Globals.default_playlist:
				Globals.session_playlist.append(mlr)

		if GameManager.arcade_game:
			var arcade_games_count: int = 10
			var all_allowed_minigame_identifiers: Array = Globals.CustomMinigamesWhitelist.duplicate(true)
			if not all_allowed_minigame_identifiers.has(mod_slot):
				all_allowed_minigame_identifiers.append(mod_slot)
			all_allowed_minigame_identifiers.shuffle()

			var count: int = min(arcade_games_count, all_allowed_minigame_identifiers.size())
			for i in count:
				var identifier: Globals.MinigameIdentifier = all_allowed_minigame_identifiers[i]
				minigames_shuffled.append(identifier)
				session_minigame_rounds[identifier] = randi_range(1, 2)
		else:
			for game in Globals.session_playlist:
				if not Globals.CustomMinigamesWhitelist.has(game.game_identifier) and game.game_identifier != mod_slot:
					continue
				minigames_shuffled.append(game.game_identifier)
				session_minigame_rounds[game.game_identifier] = max(game.total_rounds, 1)

			if GameManager.custom_shuffled:
				minigames_shuffled.shuffle()
	else:
		Globals.session_playlist.clear()
		var has_mod_in_default := false
		for mlr in Globals.default_playlist:
			Globals.session_playlist.append(mlr)
			if mlr.game_identifier == mod_slot:
				has_mod_in_default = true

		if not has_mod_in_default:
			var fallback_mlr := MinigameListResource.create(mod_slot, 1)
			Globals.session_playlist.append(fallback_mlr)

		for game in Globals.session_playlist:
			minigames_shuffled.append(game.game_identifier)
			session_minigame_rounds[game.game_identifier] = max(game.total_rounds, 1)

	if not debug_no_shuffle:
		minigames_shuffled.shuffle()

	total_games_count = minigames_shuffled.size()

	for game in minigames_shuffled:
		print("Generating session playlist with: ", Globals.MinigameIdentifier.keys()[game])

	session_minigame_list = minigames_shuffled
