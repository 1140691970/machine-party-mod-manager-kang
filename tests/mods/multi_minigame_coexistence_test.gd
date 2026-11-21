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
	var spike = loader.compile(loader.dir_of("spike-ring").path_join("main.gd")).new()
	root.add_child(roller)
	root.add_child(bubble)
	root.add_child(spike)

	roller._mod_init(loader)
	bubble._mod_init(loader)
	spike._mod_init(loader)
	roller._mod_ready(loader)
	bubble._mod_ready(loader)
	spike._mod_ready(loader)

	var custom_map: Dictionary = loader.registry("custom_minigames")
	if not custom_map.has(6) or not custom_map.has(8) or not custom_map.has(17):
		return _fail("slots 6, 8 and 17 must all be registered in custom_minigames")

	# Hub overrides should only be installed once (4 scripts) even when 3 minigame mods load.
	if loader.override_calls != 4:
		return _fail("expected exactly 4 idempotent hub overrides, got %d" % loader.override_calls)

	# All three minigames occupy real vanilla slots: their packed scenes must be
	# reachable through the stock scene paths AND instantiate with a Stage child.
	for scene_path in [
		"res://minigames/shape_cutter/shape_cutter.tscn",
		"res://minigames/scavenger_chairs/scavenger_chairs.tscn",
		"res://minigames/burn_recycle/burn_recycle.tscn",
	]:
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed == null:
			return _fail("missing packed scene: " + scene_path)
		var inst := packed.instantiate()
		if not inst.has_node("Stage"):
			inst.free()
			return _fail("scene missing Stage node: " + scene_path)
		inst.free()

	# The hub spec for slot 17 must still expose the packed scene.
	var spike_spec: Dictionary = custom_map[17]
	var spike_packed: PackedScene = spike_spec.get("packed_scene", null) as PackedScene
	if spike_packed == null:
		return _fail("slot 17 has no packed_scene")
	var spike_inst := spike_packed.instantiate()
	if not spike_inst.has_node("Stage"):
		spike_inst.free()
		return _fail("slot 17 scene missing Stage node")
	spike_inst.free()

	# Verify overridden game.gd includes all three custom minigames in default & arcade playlists.
	var game_script := ResourceLoader.load("res://scripts/scenes/game/game.gd") as GDScript
	var game_node = game_script.new()
	root.add_child(game_node)
	game_node.generate_session_playlist()
	if not game_node.session_minigame_list.has(6) or not game_node.session_minigame_list.has(8) or not game_node.session_minigame_list.has(17):
		return _fail("default playlist missing coexisting custom minigames: " + str(game_node.session_minigame_list))

	var gm: Node = root.get_node("GameManager")
	gm.set("custom_game", true)
	gm.set("arcade_game", true)
	game_node.generate_session_playlist()
	if not game_node.session_minigame_list.has(6) or not game_node.session_minigame_list.has(8) or not game_node.session_minigame_list.has(17):
		return _fail("arcade playlist missing coexisting custom minigames: " + str(game_node.session_minigame_list))

	game_node.free()
	print("MULTI_MINIGAME_COEXISTENCE_PASSED")
	quit(0)


func _fail(msg: String) -> void:
	push_error("COEXISTENCE_TEST_FAIL: " + msg)
	quit(1)
