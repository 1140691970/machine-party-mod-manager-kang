extends RefCounted


class MockLobbyNode extends Control:
	var player_order_by_seat: Array = []


class MockPlayerPresence extends Node:
	var network_id: int = 1
	var network_name: String = "Player"
	var active: bool = true
	var customization: Dictionary = {}


class MockPlayerManager extends Node:
	var player_presences: Dictionary = {}

	func add_player(id: int, display_name: String = "") -> MockPlayerPresence:
		var p := MockPlayerPresence.new()
		p.name = "Player_%d" % id
		p.network_id = id
		p.network_name = display_name if not display_name.is_empty() else ("Player %d" % id)
		p.active = true
		add_child(p)
		player_presences[id] = p
		return p


class MockGameManager extends Node:
	var scores: Dictionary = {}

	func add_score(id: int, delta: int) -> void:
		scores[id] = int(scores.get(id, 0)) + delta


static func setup_viewport(tree: SceneTree, size: Vector2i = Vector2i(1280, 720)) -> void:
	if tree != null and tree.root != null:
		tree.root.size = size


static func cleanup_uids(res_paths: Array) -> void:
	for raw_path in res_paths:
		var path_str := str(raw_path)
		if path_str.is_empty():
			continue
		var uid_res := path_str + ".uid"
		var abs_path := ProjectSettings.globalize_path(uid_res) if uid_res.begins_with("res://") else uid_res
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)


static func make_mock_lobby(seat_ids: Array = [1, 2, 3, 4]) -> Control:
	var lobby := MockLobbyNode.new()
	lobby.name = "Lobby"
	lobby.player_order_by_seat = seat_ids.duplicate()
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	return lobby


static func make_mock_minigame(player_ids: Array = [1, 2, 3, 4]) -> Dictionary:
	var minigame_root := Node.new()
	minigame_root.name = "MockMinigameRoot"

	var players := MockPlayerManager.new()
	players.name = "PlayerManager"
	minigame_root.add_child(players)
	for raw_id in player_ids:
		players.add_player(int(raw_id))

	var game := MockGameManager.new()
	game.name = "GameManager"
	minigame_root.add_child(game)

	return {
		"root": minigame_root,
		"players": players,
		"game": game
	}
