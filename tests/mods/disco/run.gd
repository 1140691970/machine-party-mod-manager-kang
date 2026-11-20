extends SceneTree

class Arena extends Node3D:
	var tile_size := 4.0
	var tile_rows := 3
	var tile_columns := 3
	var tiles := []
	var display1_symbols := []
	var active_players := {}

class Game extends Node:
	var minigame := Arena.new()

var game := Game.new()
var arena := game.minigame
var bots = preload("res://main.gd").new()
var failures := 0

func expect(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func _initialize(): run.call_deferred()

func player(id: int, pos: Vector3) -> DiscoDodgePlayer:
	var actor := DiscoDodgePlayer.new()
	actor.position = pos
	actor.gravity = 0
	actor.visuals = Node3D.new()
	actor.add_child(actor.visuals)
	actor.shove_area = Area3D.new()
	actor.visuals.add_child(actor.shove_area)
	var reach := CollisionShape3D.new()
	reach.shape = SphereShape3D.new()
	reach.shape.radius = 1.2
	reach.position.z = -0.6
	actor.shove_area.add_child(reach)
	actor.collision_shape = CollisionShape3D.new()
	actor.collision_shape.shape = SphereShape3D.new()
	actor.collision_shape.shape.radius = 0.2
	actor.add_child(actor.collision_shape)
	actor.animation_tree = AnimationTree.new()
	actor.add_child(actor.animation_tree)
	actor.fall_cast = ShapeCast3D.new()
	actor.fall_cast.shape = SphereShape3D.new()
	actor.add_child(actor.fall_cast)
	actor.speaker_shoved = AudioStreamPlayer3D.new()
	actor.add_child(actor.speaker_shoved)
	actor.multiplayer_synchronizer = MultiplayerSynchronizer.new()
	actor.add_child(actor.multiplayer_synchronizer)
	actor.add_child(actor.player_name_label)
	arena.add_child(actor)
	actor.set_player_presence(id)
	actor.active = true
	arena.active_players[id] = actor
	return actor

func run():
	root.add_child(game)
	game.add_child(arena)
	root.add_child(bots)
	bots.set_process(false)
	bots.game = game
	bots.bots.assign({101: 1})
	node_added.connect(bots._node_added)
	arena.display1_symbols = [{"visible": false}, {"visible": true}]
	for z in 3:
		var row := []
		for x in 3:
			var tile := DiscoDodgeTile.new()
			tile.position = Vector3(x - 1, 0, z - 1) * arena.tile_size
			arena.add_child(tile)
			row.append(tile)
		arena.tiles.append(row)
	var bot := player(101, Vector3(-4, 0, 0))
	var human := player(1, Vector3(4, 0, 0))
	human.set_process(false)
	var hits := []
	human.event_shoved.connect(func(): hits.append(human.position))
	arena.tiles[1][2].symbol_index = 1
	arena.tiles[1][1].collision_shape.disabled = true
	arena.tiles[0][0].is_tile_removed_from_play = true
	# An opponent in reach on the wrong symbol must not distract the bot.
	human.position = bot.position + Vector3(0, 0, -0.8)
	for frame in 5: await physics_frame
	expect(hits.is_empty() and not bot.shoving and bot.movement_input.z > 0, "bot prioritises escape when a rival is within reach")
	human.position = Vector3(4, 0, 0)
	var crossed_gap := false
	for frame in 330:
		await physics_frame
		crossed_gap = crossed_gap or (absf(bot.position.x) < 1.9 and absf(bot.position.z) < 1.9)
		if not hits.is_empty(): break
	expect(not crossed_gap, "bot routes around missing floor")
	expect(not hits.is_empty(), "bot reaches the indicated tile and lands a native shove")
	if not hits.is_empty():
		var impact: Vector3 = hits[0]
		for frame in 8: await physics_frame
		expect(human.position.distance_to(impact) > 0.4, "native shove displaces the other player")
	expect(not human.has_meta(&"lobby_bots_disco_brain"), "human keeps its own input")
	bots.set_physics_process(false)
	await create_timer(0.5).timeout
	human.shoved = false
	var before := hits.size()
	bot.players_in_shove_proximity.assign([human])
	bot.shove()
	expect(bot.shoving, "second shove entered wind-up")
	bot.active = false
	bot.died.emit(bot.player_presence.network_id)
	expect(bot.players_in_shove_proximity.is_empty(), "elimination clears pending shove immediately")
	await create_timer(0.5).timeout
	expect(hits.size() == before, "native wind-up cannot hit after elimination")
	game.free()
	bots.free()
	if failures == 0: print("Native Disco Dodge bot checks passed")
	quit(0 if failures == 0 else 1)
