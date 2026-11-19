class_name State
extends Node

signal countdown_started
signal tick(value)
signal expired

class Filter:
	func begin_shift(_from, _to, _duration): pass

var MusicManager := {"filter_controller": Filter.new()}
var GameManager := {"custom_game": true}
var Globals := {"MinigameRoundsByPlayerCount": {}}
var PlayerManager := {"player_presences": {}}
var state_machine
var transitions := []
var state_time := 0.0

@rpc("authority", "call_local")
func transition_to_rpc(target: StringName, _msg := {}):
	transitions.append(target)
	if has_node(NodePath(target)):
		get_node(NodePath(target)).enter()
