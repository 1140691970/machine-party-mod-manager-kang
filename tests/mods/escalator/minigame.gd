class_name Minigame
extends Node3D

class PlayerPresence extends RefCounted:
	var network_id := 0

class EscalatorPitStairHandler extends Node:
	var speed := 0.0

class SpeakerController extends Node:
	var speaker
	var fade_duration
	var original_volume_db
	func fade_in_custom(_volume, _restart): pass

class Overlay:
	func set_screens_visibility(_visible): pass
	func set_background(_visible, _color): pass

signal minigame_ready(id)
signal minigame_finished(id)
signal player_scores_finalized(scores)
signal player_scored(id, score)
signal debug_player_specifics_initialized(transform)

var minigame_overlay := Overlay.new()
var GameManager := {"local_game": false}
var PlayerManager := {"player_presences": {}}
var state_machine
var players_loaded: Array[int] = []
var is_all_player_loaded := false
var round_number := 1
var total_rounds := 2

func _ready(): player_loaded(1)
func player_loaded(id):
	players_loaded.append(id)
	if players_loaded.size() == PlayerManager.player_presences.size():
		all_players_loaded()
func initialize(_number, _total, _scores = {}): pass
func initialize_debug_specifics(): pass
func all_players_loaded(): pass
func player_disconnected(_id): pass
func _on_countdown_started(): pass
func _on_countdown_tick(_tick): pass
func _on_countdown_expired(): pass

@rpc("authority", "call_local")
func set_minigame_sfx_linear_volume_rpc(_volume): pass
@rpc("authority", "call_local")
func set_effects_visibility_rpc(_visible): pass
