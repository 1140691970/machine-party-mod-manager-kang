extends Node

signal died(id)
class ShoveArea:
	var overlaps := []
	func get_overlapping_bodies(): return overlaps

var player_presence := {}
var active := true
var shove_area := ShoveArea.new()
var players_in_shove_proximity := []
var shoved := false
var shoving := true
var falls := false
func _physics_process(_delta):
	if falls:
		falls = false
		active = false
		died.emit(player_presence.network_id)
