extends Node

signal died(id)
var player_presence := {}
var falls := false
func _physics_process(_delta):
	if falls:
		falls = false
		died.emit(player_presence.network_id)
