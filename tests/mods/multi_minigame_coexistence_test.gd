extends SceneTree

class MockLoader:
	extends RefCounted
	var _regs: Dictionary = {}
	var override_calls: int = 0
	var _kept: Array = []

	func dir_of(id: String) -> String:
		return ProjectSettings.globalize_path("res://mods").path_join(id)

	func registry(name: String) -> Dictionary:
		if not _regs.has(name):
			_regs[name] = {}
		return _regs[name]

	func has_api(name: String) -> bool:
		return name in ["registry", "register_script", "override_script_rel", "compile"]

	func compile(abs_path: String) -> GDScript:
		var src: String = FileAccess.get_file_as_string(abs_path)
		if src.is_empty():
			return null
		var gd := GDScript.new()
		gd.source_code = src
		if gd.reload() != OK:
			return null
		_kept.append(gd)
		return gd

	func register_script(id: String, rel: String, res_id: String) -> bool:
		var gd := compile(dir_of(id).path_join(rel))
		if gd == null:
			return false
		gd.take_over_path(res_id)
		return true

	func override_script_rel(id: String, res_path: String, rel: String) -> bool:
		override_calls += 1
		var gd := compile(dir_of(id).path_join(rel))
		if gd == null:
			return false
		gd.take_over_path(res_path)
		return true

	func on_node_added(_cb: Callable) -> void: pass
	func on_lobby(_cb: Callable) -> void: pass
	func on_scene_script(_p: String, _cb: Callable) -> void: pass
	func note(_msg: String) -> void: pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader := MockLoader.new()
	var roller = loader.compile(loader.dir_of("roller-carnival").path_join("main.gd")).new()
	var bubble = loader.compile(loader.dir_of("bubble-blitz").path_join("main.gd")).new()
	root.add_child(roller)
	root.add_child(bubble)

	roller._mod_init(loader)
	bubble._mod_init(loader)
	roller._mod_ready(loader)
	bubble._mod_ready(loader)

	var custom_map: Dictionary = loader.registry("custom_minigames")
	if not custom_map.has(6) or not custom_map.has(8):
		return _fail("both slots 6 and 8 must be registered in custom_minigames")

	# Hub overrides should only be installed once (4 scripts) even when 2 minigame mods load.
	if loader.override_calls != 4:
		return _fail("expected exactly 4 idempotent hub overrides, got %d" % loader.override_calls)

	# Both packed scenes should instantiate with a Stage child.
	for scene_path in [
		"res://minigames/shape_cutter/shape_cutter.tscn",
		"res://minigames/scavenger_chairs/scavenger_chairs.tscn",
	]:
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed == null:
			return _fail("missing packed scene: " + scene_path)
		var inst := packed.instantiate()
		if not inst.has_node("Stage"):
			inst.free()
			return _fail("scene missing Stage node: " + scene_path)
		inst.free()

	# Verify overridden game.gd includes both custom minigames in default_playlist and session_minigame_list.
	var game_script := ResourceLoader.load("res://scripts/scenes/game/game.gd") as GDScript
	var game_node = game_script.new()
	root.add_child(game_node)
	game_node.generate_session_playlist()
	if not game_node.session_minigame_list.has(6) or not game_node.session_minigame_list.has(8):
		return _fail("default playlist missing coexisting custom minigames: " + str(game_node.session_minigame_list))

	# Verify Arcade mode also includes both custom minigames.
	var gm: Node = root.get_node("GameManager")
	gm.set("custom_game", true)
	gm.set("arcade_game", true)
	game_node.generate_session_playlist()
	if not game_node.session_minigame_list.has(6) or not game_node.session_minigame_list.has(8):
		return _fail("arcade playlist missing coexisting custom minigames: " + str(game_node.session_minigame_list))

	game_node.free()
	print("MULTI_MINIGAME_COEXISTENCE_PASSED")
	quit(0)


func _fail(msg: String) -> void:
	push_error("COEXISTENCE_TEST_FAIL: " + msg)
	quit(1)
