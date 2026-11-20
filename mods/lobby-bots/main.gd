extends Node

const LOBBY := "res://scenes/lobby/scripts/lobby_scene.gd"
const JUNK_PLAYER := "res://minigames/junk_platform/components/player/scripts/junk_platform_player.gd"
const DISCO_PLAYER := "res://minigames/disco_dodge/components/player/scripts/disco_dodge_player.gd"
const ESCALATOR_PLAYER := "res://minigames/escalator_pit/components/player/scripts/escalator_pit_player.gd"
const JUNK_GAME := "res://minigames/junk_platform/scripts/junk_platform.gd"
const FIRST_ID := 2147483647

# Keys identify participants throughout the session, values are stable display numbers.
var bots: Dictionary[int, int] = {}
var outfits: Dictionary[int, Array] = {}
var lobby: Node
var game: Node
var panel: VBoxContainer
var add_button: Button
var rows: VBoxContainer
var shown_seats: Dictionary[int, Array] = {}
var match_seats: Array[int] = []
var locked := false
var base_limit := 0
var reserved_room := 0
var junk_actors: Array[Node] = []
var disco_actors: Array[Node] = []
var escalator_actors: Array[Node] = []
var junk_override_ready := false
var original_singleplayer := false
var owns_singleplayer := false

func _mod_init(loader) -> void:
	if loader.has_method("override_script_rel"):
		var result = loader.override_script_rel("lobby-bots", JUNK_GAME, "junk_platform.gd")
		# The built-in loader returns a bool; external MPML returns the compiled script.
		junk_override_ready = result is GDScript or (result is bool and result)
	if not junk_override_ready and loader.has_method("note"):
		loader.note("Lobby Bots: could not register the Junk Platform override. Adding bots is disabled.")
	if loader.has_method("on_scene_script"):
		loader.on_scene_script(LOBBY, _enter_lobby)
	# The game script may be overridden by another MPML mod.
	if loader.has_method("on_node_added"):
		loader.on_node_added(_node_added)

func _node_added(node: Node) -> void:
	if node.has_signal("player_game_ready") and node.has_method("load_minigame"):
		node.ready.connect(_game_ready.bind(node), CONNECT_ONE_SHOT)
	elif is_instance_valid(game) and not bots.is_empty():
		if node.get_script() != null:
			match node.get_script().resource_path:
				JUNK_PLAYER:
					_track_actor(node, junk_actors)
				DISCO_PLAYER:
					_track_actor(node, disco_actors)
				ESCALATOR_PLAYER:
					_track_actor(node, escalator_actors)
		if not multiplayer.is_server():
			return
		if node.has_signal("minigame_ready") and node.has_method("player_loaded"):
			# The native loader counts presences in _ready. Seed only in-process participants.
			for id in bots:
				node.players_loaded.append(id)

func _track_actor(actor: Node, actors: Array[Node]) -> void:
	actors.append(actor)
	actor.tree_exiting.connect(func(): actors.erase(actor), CONNECT_ONE_SHOT)

func _enter_lobby(node: Node) -> void:
	_reset()
	lobby = node
	locked = false
	lobby.ready.connect(_setup_panel, CONNECT_ONE_SHOT)
	lobby.tree_exiting.connect(_leave_lobby, CONNECT_ONE_SHOT)

func _setup_panel() -> void:
	var handler = lobby.lobby_handler
	var toolbar := HBoxContainer.new()
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.alignment = BoxContainer.ALIGNMENT_END
	handler.root.add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_right = -24
	toolbar.offset_top = 24
	toolbar.offset_bottom = 24
	panel = VBoxContainer.new()
	toolbar.add_child(panel)
	add_button = Button.new()
	add_button.text = _label("Add bot", "添加机器人", "加入機器人")
	if not junk_override_ready:
		add_button.text = _label("Bots unavailable: Junk Platform failed to load",
			"无法添加机器人：Junk Platform 补丁未加载", "無法加入機器人：Junk Platform 補丁未載入")
		add_button.disabled = true
	add_button.pressed.connect(_add)
	panel.add_child(add_button)
	rows = VBoxContainer.new()
	panel.add_child(rows)
	handler.start_pressed.connect(_lock_for_game)
	handler.back_pressed.connect(_reset)
	_draw_rows()

func _leave_lobby() -> void:
	if not multiplayer.has_multiplayer_peer() or (multiplayer.is_server() and not locked):
		_reset()

func _lock_for_game() -> void:
	if multiplayer.is_server() and not locked:
		match_seats = _lobby_seats()
		locked = true

func _label(en: String, cn: String, tw: String) -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale in ["zht", "zh_tw", "zh_hant"]:
		return tw
	if locale.begins_with("zh"):
		return cn
	return en

func _network():
	return get_node("/root/NetworkManager")

func _can_edit() -> bool:
	return is_instance_valid(lobby) and not locked and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and lobby.lobby_handler.active and not lobby.loading and _network().active_backend != null

func _capacity() -> int:
	var capacity := mini(lobby.player_order_by_seat.size(), _network().max_player_count)
	return mini(capacity, base_limit) if base_limit > 0 else capacity

func _steam():
	return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null

func _humans() -> int:
	var backend = _network().active_backend
	var count: int = backend.connected_players.size()
	var steam = _steam()
	if steam != null and backend.lobby_id > 0:
		count = maxi(count, steam.getNumLobbyMembers(backend.lobby_id))
	return count

func _reserve(count: int) -> bool:
	var backend = _network().active_backend
	var steam = _steam()
	if steam == null or backend.lobby_id <= 0:
		return false
	if base_limit == 0:
		base_limit = steam.getLobbyMemberLimit(backend.lobby_id)
		reserved_room = backend.lobby_id
	var limit := mini(_capacity(), base_limit) - count if count > 0 else base_limit
	if limit < 1 or not steam.setLobbyMemberLimit(backend.lobby_id, limit):
		return false
	if count == 0:
		base_limit = 0
		reserved_room = 0
	return true

func _has_space() -> bool:
	return junk_override_ready and _humans() + bots.size() < _capacity()

func _random_outfit() -> Array:
	var used := outfits.values()
	var choices: Array[Array] = []
	var colors: Array = get_node("/root/Globals").suit_colors
	var host: Array = _network().active_backend.self_data.customization
	# Native characters render blue when a saved suit color is missing.
	used.append([host[0], host[1], host[2] if colors.has(host[2]) else "blue"])
	for hat in ["", "beer_hat", "cap_blade", "tophat", "traffic_cone", "maska_helmet", "drill_sgt_hat", "hard_hat"]:
		# The native wardrobe disallows glasses with the full-face helmet.
		for glasses in ([""] if hat == "maska_helmet" else ["", "sunglasses", "reading_glasses"]):
			for color in colors:
				var outfit := [hat, glasses, color]
				if not used.has(outfit):
					choices.append(outfit)
	return choices.pick_random()

func _add() -> void:
	if not _can_edit() or not _has_space():
		return
	if not _reserve(bots.size() + 1):
		return
	var number := 1
	while bots.values().has(number) or _network().active_backend.connected_players.has(FIRST_ID - number):
		number += 1
	bots[FIRST_ID - number] = number
	outfits[FIRST_ID - number] = _random_outfit()
	_changed()

func _remove(id: int) -> void:
	if _can_edit() and bots.has(id) and _reserve(bots.size() - 1):
		bots.erase(id)
		outfits.erase(id)
		_changed()

func _changed() -> void:
	var globals = get_node("/root/Globals")
	if not bots.is_empty() and not owns_singleplayer:
		original_singleplayer = globals.allow_singleplayer
		globals.allow_singleplayer = true
		owns_singleplayer = true
	elif bots.is_empty():
		_restore_singleplayer()
	lobby.update_player_list()
	_sync_roster.rpc(bots, outfits)
	_draw_rows()

@rpc("authority", "call_remote", "reliable")
func _sync_roster(roster: Dictionary[int, int], appearances: Dictionary[int, Array]) -> void:
	bots.assign(roster)
	outfits.assign(appearances)
	_draw_rows()

func _draw_rows() -> void:
	if not is_instance_valid(rows):
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for id in bots:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = "Bot %d · %s" % [bots[id], _label("Ready", "已准备", "已準備")]
		row.add_child(label)
		if multiplayer.is_server():
			var remove := Button.new()
			remove.text = _label("Remove", "移除", "移除")
			remove.pressed.connect(_remove.bind(id))
			row.add_child(remove)

func _mod_ready(_loader) -> void:
	# External MPML runs this hook before the remaining autoloads enter the tree.
	_connect_network.call_deferred()

func _connect_network() -> void:
	var network = _network()
	if not network.on_peer_connected.is_connected(_peer_connected):
		network.on_peer_connected.connect(_peer_connected)

func _peer_connected(id: int) -> void:
	if multiplayer.is_server() and not bots.is_empty():
		_sync_roster.rpc_id(id, bots, outfits)

func _game_ready(node: Node) -> void:
	game = node
	game.tree_exiting.connect(_reset, CONNECT_ONE_SHOT)
	if not multiplayer.is_server() or bots.is_empty():
		return
	var players = get_node("/root/PlayerManager")
	for id in bots:
		var outfit: Array = outfits[id]
		var presence = players.add_player(id, outfit.duplicate())
		_configure_presence(id, players.get_path_to(presence), bots[id], outfit)
		game.total_score_by_network_id[id] = 0
		game.game_score_by_network_id[id] = 0
		game.round_score_by_network_id[id] = 0
	game.player_game_ready.connect(_send_presences)

func _send_presences(peer: int) -> void:
	if peer == 1:
		return
	var players = get_node("/root/PlayerManager")
	for id in bots:
		var p = players.player_presences[id]
		_configure_presence.rpc_id(peer, id, players.get_path_to(p), bots[id], p.customization)

@rpc("authority", "call_remote", "reliable")
func _configure_presence(id: int, path: NodePath, number: int, outfit: Array) -> void:
	var players = get_node("/root/PlayerManager")
	var p = players.get_node(path)
	p.network_id = id
	p.network_name = "Bot %d" % number
	p.customization = outfit
	p.active = true
	p.set_multiplayer_authority(1)
	players.player_presences[id] = p

func _lobby_seats() -> Array[int]:
	var seats: Array[int] = []
	var ids := bots.keys()
	var next := 0
	for seat in lobby.player_order_by_seat.size():
		var id: int = lobby.player_order_by_seat[seat]
		if id < 0 and next < ids.size():
			id = ids[next]
			next += 1
		seats.append(id)
	return seats

func seats_for_round(presences: Dictionary) -> Array[int]:
	var seats := match_seats.duplicate()
	for seat in seats.size():
		if not presences.has(seats[seat]):
			seats[seat] = -1
	for id in presences:
		if seats.has(id):
			continue
		var free := seats.find(-1)
		if free < 0:
			seats.append(id)
		else:
			seats[free] = id
	match_seats = seats
	return seats

func _show_lobby_seats() -> void:
	var handler = lobby.lobby_handler
	var seats := _lobby_seats()
	for seat in mini(seats.size(), handler.players.size()):
		var id := seats[seat]
		if not bots.has(id):
			if shown_seats.erase(seat) and id < 0:
				handler.players[seat].visible = false
			continue
		var appearance := [id, outfits[id]]
		if shown_seats.get(seat) != appearance or not handler.players[seat].visible:
			var assigner = handler.customization_assigners[seat]
			var outfit: Array = outfits[id]
			assigner.assign_hat(outfit[0])
			assigner.assign_glasses(outfit[1])
			assigner.assign_suit_color(outfit[2])
			handler.nametags[seat].text = "Bot %d" % bots[id]
			handler.players[seat].visible = true
			shown_seats[seat] = appearance

func _process(_delta: float) -> void:
	if is_instance_valid(lobby) and is_instance_valid(panel):
		panel.visible = lobby.lobby_handler.active and not lobby.loading
		if panel.visible and (not bots.is_empty() or not shown_seats.is_empty()):
			_show_lobby_seats()
		add_button.visible = _can_edit()
		if add_button.visible:
			add_button.disabled = not _has_space()
	if bots.is_empty() or not is_instance_valid(game) or not multiplayer.is_server():
		return
	var brief = game.intermission_manager.screen_briefing
	if brief.active and not brief.all_ready:
		for id in bots:
			if brief.players_ready.get(id, true) == false:
				brief.set_ready_rpc.rpc(id, true)

# Disco spawns a rectangular grid centred on the origin, in tiles[z][x] order.
class DiscoBrain:
	var think_in := 0.0
	var shove_in := 0.0
	var waypoint := Vector3.ZERO

	func cell(arena, pos: Vector3) -> Vector2i:
		return Vector2i(floori(pos.x / arena.tile_size + arena.tile_rows * 0.5),
			floori(pos.z / arena.tile_size + arena.tile_columns * 0.5))

	func tile_at(arena, index: Vector2i):
		if index.y < 0 or index.y >= arena.tiles.size():
			return null
		var row: Array = arena.tiles[index.y]
		if index.x < 0 or index.x >= row.size():
			return null
		return row[index.x]

	func solid(tile) -> bool:
		return tile != null and not tile.armed and not tile.is_tile_removed_from_play and not tile.collision_shape.disabled

	func decide(actor, arena, number: int) -> void:
		var pos: Vector3 = actor.global_position
		var start := cell(arena, pos)
		var current = tile_at(arena, start)
		waypoint = pos
		if current == null or arena.active_players.size() < 2:
			return
		var rival = null
		for other in arena.active_players.values():
			if other != actor and other.active and (rival == null or pos.distance_squared_to(other.global_position) < pos.distance_squared_to(rival.global_position)):
				rival = other
		if rival == null:
			return
		var symbol := -1
		for i in arena.display1_symbols.size():
			if arena.display1_symbols[i].visible:
				symbol = i
				break
		var safe_here: bool = solid(current) and (symbol < 0 or current.symbol_index == symbol)
		if safe_here and shove_in <= 0.0 and actor.players_in_shove_proximity.has(rival):
			var direction: Vector3 = rival.global_position - pos
			if Vector2(direction.x, direction.z).length_squared() > 0.0001:
				actor.visuals.rotation.y = atan2(-direction.x, -direction.z)
				actor.shove()
				shove_in = 0.85 + 0.1 * (number % 3)
				return

		# Remember the first step to each reachable tile. Escape via the shortest
		# route; once safe, only cross matching tiles to approach another player.
		var queue := [start]
		var first_step := {start: start}
		var best := start
		var best_distance := INF
		var rival_cell := cell(arena, rival.global_position)
		for index: Vector2i in queue:
			var tile = tile_at(arena, index)
			if solid(tile) and (symbol < 0 or tile.symbol_index == symbol):
				var distance := index.distance_squared_to(rival_cell)
				if distance < best_distance:
					best = index
					best_distance = distance
				if not safe_here or distance == 0:
					break
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = index + offset
				if first_step.has(next):
					continue
				var adjacent = tile_at(arena, next)
				if not solid(adjacent):
					continue
				if safe_here and symbol >= 0 and adjacent.symbol_index != symbol:
					continue
				first_step[next] = next if index == start else first_step[index]
				queue.append(next)
		if safe_here and start == rival_cell:
			waypoint = rival.global_position
		elif best != start or safe_here:
			waypoint = tile_at(arena, first_step[best]).global_position

	func tick(actor, arena, number: int, delta: float) -> void:
		# Native shove() resolves hits after its wind-up, using this same list.
		actor.players_in_shove_proximity.clear()
		var participants: Array = arena.active_players.values()
		for body in actor.shove_area.get_overlapping_bodies():
			if body != actor and participants.has(body) and body.active:
				actor.players_in_shove_proximity.append(body)
		shove_in -= delta
		think_in -= delta
		if actor.shoved or actor.shoving:
			return
		if think_in <= 0.0:
			decide(actor, arena, number)
			think_in = 0.14 + 0.04 * (number % 3)
		var direction: Vector3 = waypoint - actor.global_position
		direction.y = 0.0
		actor.movement_input = direction.normalized() if direction.length() > 0.18 else Vector3.ZERO

# Junk Platform disables remote characters' physics. Run the idle movement and
# fall checks on the host so its keyboard never drives a bot.
func _physics_process(delta: float) -> void:
	for actor in escalator_actors:
		var presence = actor.player_presence
		if presence == null or not bots.has(presence.network_id):
			continue
		# Replicate position and speed from the host. Camera/UI ownership stays with human players.
		if actor.multiplayer_synchronizer.get_multiplayer_authority() != 1:
			actor.multiplayer_synchronizer.set_multiplayer_authority(1)
		if multiplayer.is_server() and actor.active and actor.game_instance.active_players.size() > 1:
			# Distinct walking speeds let the belt separate the remaining bots even after the host exits.
			actor.speed = 1.25 / float(bots[presence.network_id])
			var advance: float = (actor.speed - actor.escalator_speed) * actor.progress_ratio_increase_scale * delta
			actor.path_follow_3d.progress_ratio = clampf(actor.path_follow_3d.progress_ratio + advance, 0.0, 1.0)
			actor.character_animation_tree.set("parameters/run_blend/blend_amount", minf(1.5, actor.speed + actor.escalator_speed))
	for actor in disco_actors:
		var presence = actor.player_presence
		if presence != null and bots.has(presence.network_id):
			if actor.get_multiplayer_authority() != 1:
				actor.set_multiplayer_authority(1)
			# Disco reads input in _process; its physics callback handles gravity, shoves and falls.
			actor.set_physics_process(multiplayer.is_server())
			if multiplayer.is_server() and actor.active and is_instance_valid(game.minigame):
				if not actor.has_meta(&"lobby_bots_disco_brain"):
					actor.set_meta(&"lobby_bots_disco_brain", DiscoBrain.new())
					# The native shove coroutine reads this list after its wind-up.
					actor.died.connect(func(_id): actor.players_in_shove_proximity.clear())
				actor.get_meta(&"lobby_bots_disco_brain").tick(actor, game.minigame, bots[presence.network_id], delta)
	for actor in junk_actors:
		var p = actor.player_presence
		if p == null or not bots.has(p.network_id):
			continue
		if actor.get_multiplayer_authority() != 1:
			actor.set_multiplayer_authority(1)
		if multiplayer.is_server() and actor.active:
			actor.update_movement(delta)
			actor.update_fall(delta)
			actor.update_animations(delta)

func _restore_singleplayer() -> void:
	if owns_singleplayer:
		get_node("/root/Globals").allow_singleplayer = original_singleplayer
		owns_singleplayer = false

func _reset() -> void:
	if base_limit > 0:
		var backend = _network().active_backend
		if backend != null and backend.lobby_id == reserved_room and _steam() != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_steam().setLobbyMemberLimit(backend.lobby_id, base_limit)
	base_limit = 0
	reserved_room = 0
	junk_actors.clear()
	disco_actors.clear()
	escalator_actors.clear()
	shown_seats.clear()
	match_seats.clear()
	_restore_singleplayer()
	bots.clear()
	outfits.clear()
	game = null
	lobby = null
