extends SceneTree

class Actor extends Node3D:
	var players_in_shove_proximity := []
	var visuals := self
	var active := true
	var shoves := 0
	func shove(): shoves += 1

func _initialize():
	run.call_deferred()

func run():
	var brain := preload("res://main.gd").DiscoBrain.new()
	var bot := Actor.new()
	var rival := Actor.new()
	root.add_child(bot)
	root.add_child(rival)
	bot.position = Vector3(-4, 0, 0)
	rival.position = bot.position + Vector3.FORWARD
	bot.players_in_shove_proximity.append(rival)
	var arena := {"tiles": [], "tile_rows": 3, "tile_columns": 3, "tile_size": 4.0,
		"active_players": {1: rival, 101: bot}, "display1_symbols": [{"visible": false}, {"visible": true}]}
	for z in 3:
		var row := []
		for x in 3:
			row.append({"global_position": Vector3(x - 1, 0, z - 1) * 4, "symbol_index": 0,
				"armed": false, "is_tile_removed_from_play": false, "collision_shape": {"disabled": false}})
		arena.tiles.append(row)
	arena.tiles[1][2].symbol_index = 1
	arena.tiles[1][1].collision_shape.disabled = true
	arena.tiles[0][0].armed = true
	brain.decide(bot, arena, 1)
	var escaped := brain.waypoint == Vector3(-4, 0, 4) and bot.shoves == 0
	arena.tiles[1][0].symbol_index = 1
	brain.decide(bot, arena, 1)
	brain.decide(bot, arena, 1)
	var ok := escaped and bot.shoves == 1
	if ok: print("Disco decisions passed")
	else: push_error("Expected a detour before one safe shove with cooldown")
	bot.free()
	rival.free()
	quit(0 if ok else 1)
