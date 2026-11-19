extends Node3D

var player_presence := {}
var game_instance
var active := true
var speed := 0.0
var escalator_speed := 1.0
var progress_ratio_increase_scale := 0.25
var path_follow_3d := PathFollow3D.new()
var multiplayer_synchronizer := Node.new()
var character_animation_tree := {}

func _ready():
	add_child(multiplayer_synchronizer)
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 10))
	add_child(path)
	path.add_child(path_follow_3d)
	path_follow_3d.loop = false
	path_follow_3d.progress_ratio = 0.5
	var area := Area3D.new()
	path_follow_3d.add_child(area)
	area.owner = self
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.05
	area.add_child(shape)
