extends SceneTree

var finalized := []
class Session extends Node:
	signal next_round
	var minigame
	var session_current_minigame_round := 1
	var session_current_minigame_max_rounds := 2
	var session_minigame_list := ["escalator_pit"]
	var session_minigame_index := 0
	var games_played_count := 0
	var totals := {1: 0, 101: 0, 103: 0}
	var totals_by_round := []

	func update_scores(_more_rounds):
		for id in totals:
			totals[id] += minigame.player_scores[id]
		totals_by_round.append(totals.duplicate())

	func load_minigame(identifier, is_round):
		if identifier == "escalator_pit" and is_round:
			next_round.emit()

var session := Session.new()
var bots = preload("res://main.gd").new()
var playing = preload("res://playing.gd").new()
var loaded := []

func _initialize():
	run.call_deferred()

func run():
	root.add_child(session)
	session.add_child(playing)
	playing.owner = session
	playing.state_machine = State.new()
	session.add_child(playing.state_machine)
	root.add_child(bots)
	bots.set_process(false)
	bots.game = session
	bots.bots.assign({101: 1, 103: 3})
	node_added.connect(bots._node_added)
	for id in [1, 101, 103]:
		var presence := Minigame.PlayerPresence.new()
		presence.network_id = id
		playing.PlayerManager.player_presences[id] = presence
	session.next_round.connect(start_round, CONNECT_DEFERRED)
	start_round()
	for frame in 1100:
		await physics_frame
		if session.games_played_count > 0: break
	var points := {1: 0, 101: 3, 103: 1}
	var ok := finalized == [points, points] and loaded == [[1, 101, 103], [1, 101, 103]]
	ok = ok and session.totals_by_round == [points, {1: 0, 101: 6, 103: 2}]
	ok = ok and playing.state_machine.transitions == [&"MinigameEnd"] and session.games_played_count == 1
	if not ok: push_error("Rounds loaded %s, scores %s, totals %s" % [loaded, finalized, session.totals_by_round])
	session.free()
	bots.free()
	if ok: print("Native Escalator Pit settlement passed")
	quit(0 if ok else 1)

func start_round():
	if session.minigame != null: session.minigame.free()
	var arena = preload("res://escalator_pit.gd").new()
	var players := Node3D.new()
	players.name = "Players"
	arena.add_child(players)
	var camera := Node3D.new()
	camera.name = "CameraTarget"
	arena.add_child(camera)
	var lens := Camera3D.new()
	lens.name = "Camera3D"
	camera.add_child(lens)
	var interactive := Node3D.new()
	interactive.name = "Interactive"
	arena.add_child(interactive)
	for area_name in ["KillArea", "FinishArea"]:
		var area := Area3D.new()
		area.name = area_name
		interactive.add_child(area)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(10, 2, 1)
		area.add_child(shape)
		if area_name == "FinishArea": area.position.z = 10
	arena.countdown_state = State.new()
	arena.add_child(arena.countdown_state)
	arena.stair_handler = Minigame.EscalatorPitStairHandler.new()
	arena.add_child(arena.stair_handler)
	arena.state_machine = State.new()
	arena.add_child(arena.state_machine)
	var finish = preload("res://finished_state.gd").new()
	finish.name = "Finish"
	arena.state_machine.add_child(finish)
	finish.owner = arena
	arena.player_scores_finalized.connect(func(scores): finalized.append(scores.duplicate()))
	arena.PlayerManager = playing.PlayerManager
	for i in 3:
		var marker := Node3D.new()
		arena.add_child(marker)
		marker.position.x = i * 2
		arena.player_spawn_positions.append(marker)
	session.minigame = arena
	playing.enter()
	arena.minigame_ready.connect(func(_id):
		arena.initialize(session.session_current_minigame_round, 2, session.totals)
		loaded.append(arena.player_characters.keys())
		arena.player_characters[1].path_follow_3d.progress_ratio = 0.0
	)
	session.add_child(arena)
