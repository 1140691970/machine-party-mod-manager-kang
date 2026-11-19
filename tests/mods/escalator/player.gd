class_name EscalatorPitPlayer
extends "res://escalator_player_fixture.gd"

signal correct_input(speed)

@rpc("any_peer", "call_local")
func kill_rpc(): active = false
@rpc("any_peer", "call_local")
func finish_rpc(): active = false
@rpc("any_peer", "call_local")
func show_win_indicator_rpc(): pass
@rpc("any_peer", "call_local")
func set_escalator_speed_rpc(value): escalator_speed = value

@rpc("authority", "call_local")
func set_player_presence_rpc(id): player_presence = {"network_id": id}
@rpc("authority", "call_local")
func set_manager_from_path_rpc(path): game_instance = get_node(path)
@rpc("authority", "call_local")
func teleport_rpc(pos): global_position = pos
