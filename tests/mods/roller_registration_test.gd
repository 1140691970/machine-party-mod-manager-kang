extends SceneTree

class Handler:
	extends Node
	@export var rounds: int = 1
	var listed := false

class Loader:
	extends RefCounted
	var available := false
	var replacement := GDScript.new()
	func dir_of(_id): return ProjectSettings.globalize_path("res://")
	func compile(path):
		if path.ends_with("official_minigame.gd"):
			return Handler if available else null
		return load("res://" + path.get_file())
	func override_script_rel(_id, path, _rel):
		if path.ends_with("playlist_handler.gd"):
			replacement.source_code = 'extends "res://scenes/lobby/components/playlist_handler.gd"\nfunc _ready(): listed = true\n'
			if replacement.reload() != OK: return false
			replacement.take_over_path(path)
			return true
		return false
	func on_node_added(callback):
		Engine.get_main_loop().node_added.connect(callback)
	func note(_message): pass

func _initialize(): call_deferred("_run")

func _run():
	var base := load("res://scenes/lobby/components/playlist_handler.gd") as GDScript
	var stock: Node = base.new()
	stock.rounds = 4
	var scene := PackedScene.new()
	scene.pack(stock)
	stock.free()
	var mod = load("res://main.gd").new()
	root.add_child(mod)
	var loader := Loader.new()
	mod._mod_init(loader)
	if mod._packed_minigame_scene != null: return fail("unavailable wrapper registered")
	loader.available = true
	mod._mod_ready(loader)
	var packed = load(mod.TARGET_SCENE_PATH)
	if packed == null or packed != mod._packed_minigame_scene: return fail("no scene after ready")
	var level = packed.instantiate()
	if not level.has_node("Stage"): return fail("missing playable stage")
	level.free()

	var cached = scene.instantiate()
	root.add_child(cached)
	if not cached.listed or cached.rounds != 4: return fail("cached handler did not use override with original settings")
	print("Roller registration checks passed")
	quit()

func fail(message):
	push_error(message)
	quit(1)
