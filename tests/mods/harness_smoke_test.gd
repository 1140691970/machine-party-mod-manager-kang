extends SceneTree


func _init() -> void:
	var script_dir := (get_script() as Script).resource_path.get_base_dir()
	var loader_path := script_dir.path_join("_harness/mock_loader.gd")
	var env_path := script_dir.path_join("_harness/mock_game_env.gd")

	var MockLoader := ResourceLoader.load(loader_path) as Script
	var MockGameEnv := ResourceLoader.load(env_path) as Script
	assert(MockLoader != null, "MockLoader failed to load")
	assert(MockGameEnv != null, "MockGameEnv failed to load")

	MockGameEnv.setup_viewport(self)
	assert(root.size == Vector2i(1280, 720), "Viewport size should be 1280x720")

	var loader = MockLoader.new(script_dir)
	assert(loader.has_api(2), "MockLoader must support API v2")
	assert(not loader.has_api(99), "MockLoader must reject future API versions")

	var scene_calls: Array = []
	loader.on_scene_script("res://scenes/lobby/lobby.gd", func(n: Node) -> void:
		scene_calls.append(str(n.name))
	)
	var lobby: Control = MockGameEnv.make_mock_lobby([1, 2, -1, -1])
	root.add_child(lobby)
	loader.trigger_scene("res://scenes/lobby/lobby.gd", lobby)
	assert(scene_calls.size() == 1 and scene_calls[0] == "Lobby", "on_scene_script hook should fire")

	var added_calls: Array = []
	loader.on_node_added(func(n: Node) -> void:
		added_calls.append(str(n.name))
	)
	var marker := Node.new()
	marker.name = "TestMarker"
	lobby.add_child(marker)
	loader.trigger_node_added(marker)
	assert(added_calls.size() == 1 and added_calls[0] == "TestMarker", "on_node_added hook should fire")

	loader.note("harness smoke ok")
	assert(loader.notes.size() == 1, "note should be recorded")

	var env: Dictionary = MockGameEnv.make_mock_minigame([1, 2, 3])
	var mg_root: Node = env["root"] as Node
	var players = env["players"]
	var game = env["game"]
	root.add_child(mg_root)
	assert(players.player_presences.size() == 3, "MockPlayerManager should populate 3 presences")
	game.add_score(1, 5)
	assert(int(game.scores.get(1, 0)) == 5, "MockGameManager should track scores")
	mg_root.queue_free()

	lobby.queue_free()
	MockGameEnv.cleanup_uids([loader_path, env_path, (get_script() as Script).resource_path])
	print("Harness smoke checks passed")
	quit(0)
