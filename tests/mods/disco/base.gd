class_name BaseCharacterBodyPlayer
extends CharacterBody3D

var player_presence = {}
var player_name_label := Label3D.new()
var GameManager = {"local_game": false, "game_focused": true}
var Globals = {"Epsilon": 0.001}
var PauseMenu = {"active": false}
var DynamicInput
var AchievementManager
var SoundManager = self

func set_player_presence(id):
	player_presence = {"network_id": id}
	set_multiplayer_authority(id)

@rpc("any_peer", "call_local")
func play_positional_rpc(_sound, _position, _bus, _volume, _pitch): pass
