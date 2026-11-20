extends SceneTree

class LoaderFixture:
	var result
	var notes := []
	func _init(value): result = value
	func override_script_rel(_id, _target, _file): return result
	func note(message): notes.append(message)

class SteamRoom:
	var members := 1
	var limit := 4
	func getNumLobbyMembers(_room): return members
	func getLobbyMemberLimit(_room): return limit
	func setLobbyMemberLimit(_room, value):
		if value < members: return false
		limit = value
		return true

class Bots extends "res://main.gd":
	var steam := SteamRoom.new()
	func _steam(): return steam

class Network extends Node:
	signal on_peer_connected(id)
	var active_backend := {"lobby_id": 123, "connected_players": {1: {}}, "self_data": {"customization": ["tophat", "sunglasses", "blue"]}}
	var max_player_count := 4

class GlobalsFixture extends Node:
	const suit_colors = ["red", "blue", "green", "yellow", "purple"]
	var allow_singleplayer := false
	var local_game := false

class OutfitAssigner:
	var outfit := ["", "", ""]
	func assign_hat(value): outfit[0] = value
	func assign_glasses(value): outfit[1] = value
	func assign_suit_color(value): outfit[2] = value

class Handler extends Control:
	signal start_pressed
	signal back_pressed
	var active := true
	var root: Control = self
	var players: Array[Node3D] = []
	var nametags: Array[Label3D] = []
	var customization_assigners := []

class Lobby extends Node:
	var lobby_handler := Handler.new()
	var loading := false
	var player_order_by_seat := {0: 1, 1: -1, 2: -1, 3: -1}
	func update_player_list(): pass

class Presence extends Node:
	var network_id := 0
	var network_name := ""
	var customization := []
	var active := false

class Players extends Node:
	var player_presences := {}
	func add_player(id, _outfit):
		var p := Presence.new()
		add_child(p, true)
		player_presences[id] = p
		return p

class Brief extends Node:
	var active := true
	var all_ready := false
	var players_ready := {}
	@rpc("any_peer", "call_local", "reliable")
	func set_ready_rpc(id, value): players_ready[id] = value

class Game extends Node:
	signal player_game_ready(id)
	var minigame: Node
	var total_score_by_network_id := {1: 0}
	var game_score_by_network_id := {1: 0}
	var round_score_by_network_id := {1: 0}
	var intermission_manager := {"screen_briefing": Brief.new()}
	func load_minigame(): pass

class Round extends Node:
	signal minigame_ready
	var players_loaded: Array[int] = []
	func player_loaded(_id): pass

class DiscoArena extends Node:
	var active_players := {}

var junk_override := GDScript.new()
var failed := false

func expect(value: bool, message: String):
	if not value:
		failed = true
		push_error(message)

func _initialize():
	run.call_deferred()

func run():
	var net := Network.new()
	net.name = "NetworkManager"
	var globals := GlobalsFixture.new()
	globals.name = "Globals"
	root.add_child(globals)
	var players := Players.new()
	players.name = "PlayerManager"
	root.add_child(players)
	var loader := Node.new()
	loader.name = "ModLoader"
	root.add_child(loader)
	var bots := Bots.new()
	bots.name = "lobby-bots"
	loader.add_child(bots)
	var gm := GlobalsFixture.new()
	gm.name = "GameManager"
	root.add_child(gm)
	bots._mod_ready(null)
	root.add_child(net)
	await process_frame
	expect(net.on_peer_connected.is_connected(bots._peer_connected), "external MPML starts before NetworkManager")
	await check_failed_override()
	bots._mod_init(LoaderFixture.new(true))
	bots._mod_ready(null)
	var lobby := Lobby.new()
	for i in 4:
		var model := Node3D.new()
		var tag := Label3D.new()
		model.add_child(tag)
		lobby.add_child(model)
		lobby.lobby_handler.players.append(model)
		lobby.lobby_handler.nametags.append(tag)
		lobby.lobby_handler.customization_assigners.append(OutfitAssigner.new())
	lobby.add_child(lobby.lobby_handler)
	lobby.lobby_handler.size = Vector2(640, 360)
	lobby.loading = true
	lobby.lobby_handler.hide()
	bots._enter_lobby(lobby)
	root.add_child(lobby)
	await process_frame
	await process_frame
	lobby.loading = false
	lobby.lobby_handler.show()
	await process_frame
	await process_frame
	check_button_position(bots, "empty room")
	if OS.get_cmdline_user_args().size() > 2:
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[2]) == OK, "capture empty room")
	bots.add_button.pressed.emit()
	await process_frame
	await process_frame
	check_button_position(bots, "after adding first bot")
	lobby.lobby_handler.size.x = 480
	await process_frame
	await process_frame
	check_button_position(bots, "resized room")
	lobby.lobby_handler.size.x = 640
	for i in 3:
		bots.add_button.pressed.emit()
	expect(bots.bots.size() == 3 and bots.steam.limit == 1, "host plus three bots fills room")
	var ids := bots.bots.keys()
	var original_outfits := bots.outfits.duplicate(true)
	var seen := [net.active_backend.self_data.customization]
	for id in ids:
		var outfit: Array = bots.outfits[id]
		expect(not seen.has(outfit) and GlobalsFixture.suit_colors.has(outfit[2]), "bot has a distinct native outfit")
		expect(outfit[0] != "maska_helmet" or outfit[1] == "", "full-face helmet excludes glasses")
		seen.append(outfit)
	bots.rows.get_child(1).get_child(1).pressed.emit()
	expect(bots.bots.keys() == [ids[0], ids[2]] and bots.steam.limit == 2, "remove just selected seat")
	expect(not bots.outfits.has(ids[1]), "removed bot releases its outfit")
	bots.steam.members = 2
	bots._process(0)
	expect(bots.add_button.disabled, "Steam member occupies last seat before game handshake")
	bots._add()
	expect(bots.bots.size() == 2, "pending Steam join prevents add")
	bots.steam.members = 1
	bots._process(0)
	expect(not bots.add_button.disabled, "cancelled handshake releases seat")
	net.active_backend.connected_players[77] = {}
	lobby.player_order_by_seat[1] = 77
	bots.steam.members = 2
	bots._add()
	expect(bots.bots.size() == 2, "human reserves freed seat")
	bots._remove(77)
	expect(net.active_backend.connected_players.has(77), "human cannot be removed as bot")
	bots._process(0)
	expect(lobby.lobby_handler.nametags[2].text == "Bot 1" and lobby.lobby_handler.nametags[3].text == "Bot 3", "native preview retains the selected bot identity")
	expect(lobby.lobby_handler.customization_assigners[2].outfit == original_outfits[ids[0]] and lobby.lobby_handler.customization_assigners[3].outfit == original_outfits[ids[2]], "outfits follow bots when their seats move")
	if OS.get_cmdline_user_args().size() > 0:
		await process_frame
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]) == OK, "capture controls")
	bots._lock_for_game()
	bots._remove(ids[0])
	expect(bots.bots.size() == 2, "roster locked at start")
	lobby.free()
	var game := Game.new()
	game.add_child(game.intermission_manager.screen_briefing)
	bots._node_added(game)
	root.add_child(game)
	expect(players.player_presences.size() == 2 and game.total_score_by_network_id.size() == 3, "independent presences and scores")
	for id in bots.bots:
		expect(players.player_presences[id].customization == original_outfits[id], "in-game presence keeps the lobby outfit")
	for i in 2:
		var brief = game.intermission_manager.screen_briefing
		brief.players_ready = {1: false, ids[0]: false, ids[2]: false}
		bots._process(0)
		expect(brief.players_ready == {1: false, ids[0]: true, ids[2]: true}, "only bots auto-ready every round")
		var round_node := Round.new()
		bots._node_added(round_node)
		expect(round_node.players_loaded == bots.bots.keys(), "only bots preloaded")
		round_node.free()
	await check_escalator(bots)
	await check_disco(bots, ids)
	check_junk(bots, players)
	game.free()
	expect(bots.bots.is_empty() and not globals.allow_singleplayer and bots.steam.limit == 4, "release seats and restore room settings")
	await check_remote_roster()
	if not failed: print("Lobby Bots checks passed")
	quit(1 if failed else 0)

# Two SceneMultiplayer roots exchange the production RPCs over a real loopback peer.
func check_remote_roster():
	var server_peer := ENetMultiplayerPeer.new()
	var err := server_peer.create_server(0)
	expect(err == OK, "open loopback server")
	if err != OK: return
	var server_root := Node.new()
	var client_root := Node.new()
	root.add_child(server_root, true)
	root.add_child(client_root, true)
	var server_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	set_multiplayer(server_api, server_root.get_path())
	set_multiplayer(client_api, client_root.get_path())
	server_api.multiplayer_peer = server_peer
	var host := Bots.new()
	var guest := Bots.new()
	host.name = "lobby-bots"
	guest.name = host.name
	server_root.add_child(host)
	client_root.add_child(guest)
	var host_lobby := Lobby.new()
	var guest_lobby := Lobby.new()
	for pair in [[host, host_lobby, server_root], [guest, guest_lobby, client_root]]:
		pair[1].add_child(pair[1].lobby_handler)
		pair[0]._enter_lobby(pair[1])
		pair[2].add_child(pair[1])
	host._mod_init(LoaderFixture.new(junk_override))
	host._add()
	host._mod_ready(null)
	await process_frame
	var network := root.get_node("NetworkManager")
	server_api.peer_connected.connect(network.on_peer_connected.emit)
	var client_peer := ENetMultiplayerPeer.new()
	err = client_peer.create_client("127.0.0.1", server_peer.host.get_local_port())
	expect(err == OK, "open loopback client")
	client_api.multiplayer_peer = client_peer
	var deadline := Time.get_ticks_msec() + 3000
	while guest.bots.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(guest.bots == host.bots and not guest.bots.is_empty(), "late join receives current roster")
	expect(guest.outfits == host.outfits and guest.outfits.size() == 1, "late join receives the host-selected outfit")
	guest._add()
	expect(guest.bots.size() == 1, "client cannot add")
	if not guest.bots.is_empty():
		guest._remove(guest.bots.keys()[0])
	expect(guest.bots.size() == 1, "client cannot remove")
	var first_id := client_api.get_unique_id()
	client_peer.close()
	client_api.multiplayer_peer = null
	deadline = Time.get_ticks_msec() + 3000
	while server_api.get_peers().has(first_id) and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(not server_api.get_peers().has(first_id), "host observes guest disconnect")
	guest._reset()
	client_peer = ENetMultiplayerPeer.new()
	err = client_peer.create_client("127.0.0.1", server_peer.host.get_local_port())
	expect(err == OK, "reconnect guest")
	client_api.multiplayer_peer = client_peer
	deadline = Time.get_ticks_msec() + 3000
	while guest.bots.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(guest.bots == host.bots and guest.bots.size() == 1, "reconnected guest receives the existing bot")
	expect(guest.outfits == host.outfits, "reconnection restores the same outfit")
	host._remove(host.bots.keys()[0])
	deadline = Time.get_ticks_msec() + 3000
	while not guest.bots.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(guest.bots.is_empty(), "host removal replicates")
	expect(guest.outfits.is_empty(), "host removal clears the guest outfit")
	var host_arena = junk_override.new()
	var guest_arena = junk_override.new()
	host_arena.name = "JunkPlatform"
	guest_arena.name = host_arena.name
	server_root.add_child(host_arena)
	client_root.add_child(guest_arena)
	host_arena._orient_camera(client_api.get_unique_id(), 180.0, false)
	deadline = Time.get_ticks_msec() + 3000
	while guest_arena.camera_rotation == 0.0 and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(guest_arena.camera_rotation == 180.0 and host_arena.camera_rotation == 0.0, "rotated human guest receives its own camera RPC")
	server_root.free()
	client_root.free()
	client_peer.close()
	server_peer.close()

func check_disco(bots, ids: Array):
	var survivors: Array = bots.bots.keys()
	var arena := DiscoArena.new()
	bots.game.add_child(arena)
	bots.game.minigame = arena
	var script = load(get_script().resource_path.get_base_dir().path_join("disco_player_fixture.gd"))
	script.take_over_path(bots.DISCO_PLAYER)
	for id in survivors.duplicate():
		var actor = script.new()
		actor.player_presence = {"network_id": id}
		arena.active_players[id] = actor
		root.add_child(actor)
		actor.set_multiplayer_authority(id)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.falls = id == ids[0]
		actor.died.connect(func(dead_id): survivors.erase(dead_id))
		bots._node_added(actor)
	var falling = arena.active_players[ids[0]]
	var rival = arena.active_players[ids[2]]
	falling.shove_area.overlaps.append(rival)
	bots._physics_process(0)
	expect(falling.players_in_shove_proximity == [rival], "host tracks a live target during shove wind-up")
	for actor in bots.disco_actors:
		expect(actor.get_multiplayer_authority() == 1 and actor.is_physics_processing() and not actor.is_processing(), "host simulates bot physics without input")
	await physics_frame
	await physics_frame
	expect(survivors == [ids[2]], "after host elimination, a falling bot leaves one survivor")
	expect(falling.players_in_shove_proximity.is_empty(), "elimination cancels the pending shove target")
	for actor in bots.disco_actors.duplicate(): actor.free()

func check_junk(bots, players):
	var fixture_path: String = get_script().resource_path.get_base_dir().path_join("junk_platform_fixture.gd")
	var path := OS.get_temp_dir().path_join("lobby-bots-fixture-%d.zip" % OS.get_process_id())
	var pack := ZIPPacker.new()
	pack.open(path)
	pack.start_file(bots.JUNK_GAME.trim_prefix("res://"))
	pack.write_file(FileAccess.get_file_as_bytes(fixture_path))
	pack.close_file()
	pack.close()
	expect(ProjectSettings.load_resource_pack(path), "mount synthetic game interface")

	junk_override.source_code = FileAccess.get_file_as_string("res://junk_platform.gd")
	var err := junk_override.reload()
	expect(err == OK, "compile MPML override against game interface")
	if err != OK: return
	var arena = junk_override.new()
	root.add_child(arena)
	var roster = players.player_presences.duplicate()
	var saved = bots.bots.duplicate()
	var ids: Array = bots.bots.keys()
	players.player_presences = {1: {}}
	for id in bots.bots: players.player_presences[id] = {}
	players.player_presences[77] = {}
	arena.spawn_players()
	expect(arena.players[77].spawn_position == arena.player_spawn_position_node.get_child(1).position, "late-registering human retains lobby seat")
	expect(arena.camera_rotation == 180.0 and arena.active_players.size() == 4, "host gets its camera and all four seats spawn")
	var fourth = arena.players[ids[1]]
	expect(fourth.spawn_rotation == 180.0 and fourth.spawn_position.z == -13, "fourth bot keeps native orientation")
	fourth.emit_died.emit(fourth.network_id)
	expect(arena.active_players.size() == 3, "bot elimination reaches native handler")
	players.player_presences.erase(77)
	var next_arena = junk_override.new()
	root.add_child(next_arena)
	next_arena.spawn_players()
	expect(next_arena.player_count == 3 and next_arena.players[ids[1]].spawn_rotation == 180.0, "empty seat preserves fourth marker next round")
	players.player_presences[88] = {}
	expect(bots.seats_for_round(players.player_presences) == [1, 88, ids[0], ids[1]], "new arrival fills the vacant seat")
	next_arena.free()
	bots.bots.clear()
	arena.spawn_players()
	expect(arena.vanilla_spawn, "human-only lobby uses original spawn routine")
	bots.bots.assign(saved)
	players.player_presences = roster
	arena.free()
	DirAccess.remove_absolute(path)

func check_button_position(bots, stage: String):
	var button: Rect2 = bots.add_button.get_global_rect()
	var room: Rect2 = bots.lobby.lobby_handler.root.get_global_rect()
	expect(button.has_area() and room.encloses(button), "entire button visible in " + stage)
	expect(is_equal_approx(room.end.x - button.end.x, 24.0) and is_equal_approx(button.position.y - room.position.y, 24.0), "button margins in " + stage)

func check_failed_override():
	for result in [false, null]:
		var mod := Bots.new()
		var loader := LoaderFixture.new(result)
		root.add_child(mod)
		mod._mod_init(loader)
		var room := Lobby.new()
		room.add_child(room.lobby_handler)
		room.lobby_handler.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mod._enter_lobby(room)
		root.add_child(room)
		mod._process(0)
		expect(mod.add_button.visible and mod.add_button.disabled and mod.add_button.text.contains("Junk Platform"), "failed override is visible in lobby")
		mod._add()
		expect(mod.bots.is_empty() and mod.steam.limit == 4 and loader.notes.size() == 1, "both loader failure returns keep human seats available")
		var args := OS.get_cmdline_user_args()
		if result == false and args.size() > 1:
			await process_frame
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(args[1]) == OK, "capture load failure")
		room.free()
		mod.free()

func check_escalator(bots):
	var script = load(get_script().resource_path.get_base_dir().path_join("escalator_player_fixture.gd"))
	script.take_over_path(bots.ESCALATOR_PLAYER)
	var racers: Array = []
	var arena := Node3D.new()
	root.add_child(arena)
	var bottom := Area3D.new()
	arena.add_child(bottom)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(10, 2, 1)
	bottom.add_child(shape)
	var eliminated := []
	bottom.area_entered.connect(func(area):
		var racer = area.get_parent().get_parent().get_parent()
		if racers.has(racer):
			racers.erase(racer)
			racer.active = false
			eliminated.append(racer.player_presence.network_id)
	)
	var ids: Array = bots.bots.keys()
	for id in ids:
		var racer = script.new()
		racer.position.x = racers.size() * 2
		racer.player_presence = {"network_id": id}
		racer.game_instance = {"active_players": racers}
		arena.add_child(racer)
		racer.set_multiplayer_authority(id)
		bots._node_added(racer)
		racers.append(racer)
	# Accelerate only simulated movement; Godot still detects the actual Area3D overlap.
	for frame in 45:
		bots._physics_process(0.15)
		await physics_frame
		if racers.size() == 1: break
	expect(eliminated == [ids[1]] and racers.size() == 1, "with host already out the belt eliminates the slower bot")
	if racers.size() == 1:
		expect(racers[0].multiplayer_synchronizer.get_multiplayer_authority() == 1 and racers[0].get_multiplayer_authority() == ids[0], "host replicates position without taking over player UI")
		var progress: float = racers[0].path_follow_3d.progress_ratio
		bots._physics_process(1.0)
		expect(racers[0].path_follow_3d.progress_ratio == progress, "last bot stops advancing during settlement")
	arena.free()
	expect(bots.escalator_actors.is_empty(), "escalator actors released on scene exit")
