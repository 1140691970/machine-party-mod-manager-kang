extends Minigame

## The official Game owns loading and the scoreboard. Stage owns the simulation.
func _enter_tree() -> void:
	# Minigame resolves $StateMachine before _ready, even for a single-state game.
	var machine := StateMachine.new()
	machine.name = "StateMachine"
	var play := State.new()
	play.name = "Play"
	machine.add_child(play)
	machine.initial_state = ^"Play"
	add_child(machine)
	machine.owner = self


func _ready() -> void:
	$Stage.round_finished.connect(_finish)
	GameManager.can_set_cursor = false
	if multiplayer.is_server():
		# The game's handler takes no argument, as in the stock Minigame.
		host_loaded.emit()
		player_loaded(1)
	else:
		player_loaded.rpc_id(1, multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func player_loaded(network_id: int):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if network_id != (1 if sender == 0 else sender):
		return
	if not players_loaded.has(network_id):
		players_loaded.append(network_id)
	all_players_loaded()


func all_players_loaded():
	if is_all_player_loaded or not multiplayer.is_server():
		return
	for id in PlayerManager.player_presences:
		if not players_loaded.has(id):
			return
	is_all_player_loaded = true
	minigame_ready.emit(1)


func initialize(current_round: int, rounds: int, _scores: Dictionary = {}):
	round_number = current_round
	total_rounds = rounds
	var roster := []
	var ids: Array = PlayerManager.player_presences.keys()
	ids.sort()
	for id in ids:
		var presence = PlayerManager.player_presences[id]
		var cust = presence.get("customization")
		roster.append({
			"id": roster.size(),
			"network_id": id,
			"nickname": presence.network_name,
			"customization": cust.duplicate() if cust is Array else [],
			"round_number": current_round,
			"total_rounds": rounds,
		})
	$Stage.start_round.rpc(roster)


func player_disconnected(network_id: int):
	if multiplayer.is_server():
		$Stage.player_disconnected(network_id)
		all_players_loaded.call_deferred()


func _finish(scores: Dictionary) -> void:
	player_scores_finalized.emit(scores)
	minigame_finished.emit(1)
