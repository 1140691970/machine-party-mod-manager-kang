extends Node

class Actor extends Node:
	signal emit_died(id)
	signal event_fallen(id)
	var network_id := 0
	var spawn_position := Vector3.ZERO
	var spawn_rotation := 0.0

	@rpc("authority", "call_local", "reliable")
	func set_player_presence(id: int): network_id = id

	@rpc("authority", "call_local", "reliable")
	func setup_rpc(pos: Vector3, angle: float):
		spawn_position = pos
		spawn_rotation = angle

class Factory:
	func instantiate(): return Actor.new()

class JunkHandler:
	var points := {}
	func add_spawn_point(id, point): points[id] = point

var player_scene := Factory.new()
var junk_handler := JunkHandler.new()
var players_node := Node.new()
var player_spawn_position_node := Node3D.new()
var players := {}
var active_players := {}
var player_scores := {}
var player_count := 0
var camera_rotation := 0.0
var vanilla_spawn := false

func _ready():
	add_child(players_node)
	add_child(player_spawn_position_node)
	for z in [-13, 13, 13, -13]:
		var marker := Node3D.new()
		player_spawn_position_node.add_child(marker)
		marker.position = Vector3(marker.get_index(), 0, z)

func spawn_players(): vanilla_spawn = true
func _on_player_died(id): active_players.erase(id)
func _on_player_fallen(_id): pass

@rpc("any_peer", "call_remote", "reliable")
func rotate_camera_rpc(angle: float): camera_rotation = angle
