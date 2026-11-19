extends "res://minigames/junk_platform/scripts/junk_platform.gd"

func spawn_players():
	var bot_mod = get_node("/root/ModLoader/lobby-bots")
	if bot_mod.bots.is_empty() or get_node("/root/GameManager").local_game or not multiplayer.is_server():
		super.spawn_players()
		return

	var presences = get_node("/root/PlayerManager").player_presences
	var roster = bot_mod.seats_for_round(presences)
	player_count = presences.size()
	for seat in roster.size():
		var id: int = roster[seat]
		if id < 0:
			continue
		var spawn: Vector3 = player_spawn_position_node.get_child(seat).global_position
		var rotation := 180.0 if spawn.z < 0.0 else 0.0
		var actor = player_scene.instantiate()
		players_node.add_child(actor, true)
		actor.network_id = id
		junk_handler.add_spawn_point(id, spawn + Vector3.UP * 20.0)
		actor.set_player_presence.rpc(id)
		actor.setup_rpc.rpc(spawn, rotation)
		_orient_camera(id, rotation, bot_mod.bots.has(id))
		actor.emit_died.connect(_on_player_died)
		actor.event_fallen.connect(_on_player_fallen)
		players[id] = actor
		active_players[id] = actor
		player_scores[id] = 0

func _orient_camera(id: int, rotation: float, is_bot: bool) -> void:
	if rotation == 0.0 or is_bot:
		return
	if id == multiplayer.get_unique_id():
		rotate_camera_rpc(rotation)
	else:
		rotate_camera_rpc.rpc_id(id, rotation)
