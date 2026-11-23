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
	var core = loader.compile(loader.dir_of("mpm-core").path_join("main.gd")).new()
	var roller = loader.compile(loader.dir_of("roller-carnival").path_join("main.gd")).new()
	var bubble = loader.compile(loader.dir_of("bubble-blitz").path_join("main.gd")).new()
	var spike = loader.compile(loader.dir_of("spike-ring").path_join("main.gd")).new()
	root.add_child(core)
	root.add_child(roller)
	root.add_child(bubble)
	root.add_child(spike)

	core._mod_init(loader)
	roller._mod_init(loader)
	bubble._mod_init(loader)
	spike._mod_init(loader)
	core._mod_ready(loader)
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

	# Verify admission gating in override_game.gd (FFA excludes team_only, empty custom falls back, Team Party includes)
	var core_meta: Dictionary = Engine.get_meta(&"mpm_core") as Dictionary
	var sdk = core_meta["minigame_sdk"]
	var team_reg: Dictionary = sdk.register_minigame({
		"mod_id": "team-only-fixture",
		"slot_id": 1000,
		"admission": {"mode_support": "team_only", "min_teams": 2},
	}, loader)
	if not bool(team_reg.get("ok", false)):
		return _fail("failed to register team-only-fixture")

	Engine.set_meta(&"mpm_team_party", {"enabled": false, "team_count": 0, "teams": {}})
	gm.set("custom_game", false)
	gm.set("arcade_game", false)
	game_node.generate_session_playlist()
	if game_node.session_minigame_list.has(1000):
		return _fail("FFA default playlist must exclude team_only slot 1000")

	gm.set("custom_game", true)
	gm.set("arcade_game", true)
	game_node.generate_session_playlist()
	if game_node.session_minigame_list.has(1000):
		return _fail("FFA arcade playlist must exclude team_only slot 1000")

	# Custom playlist with ONLY slot 1000 in FFA must fall back to eligible defaults
	var globals_node: Node = root.get_node("Globals")
	var saved_session: Array = (globals_node.get("session_playlist") as Array).duplicate()
	globals_node.set("session_playlist", [MinigameListResource.create(1000, 1)])
	gm.set("arcade_game", false)
	game_node.generate_session_playlist()
	if game_node.session_minigame_list.is_empty() or game_node.session_minigame_list.has(1000):
		return _fail("empty custom playlist fallback failed in FFA: " + str(game_node.session_minigame_list))
	globals_node.set("session_playlist", saved_session)

	# Enable Team Party 2v2 -> slot 1000 is now included in default playlist
	Engine.set_meta(&"mpm_team_party", {"enabled": true, "team_count": 2, "teams": {1: 1, 2: 2}})
	gm.set("custom_game", false)
	gm.set("arcade_game", false)
	game_node.generate_session_playlist()
	if not game_node.session_minigame_list.has(1000):
		return _fail("Team Party default playlist should include team_only slot 1000")

	Engine.remove_meta(&"mpm_team_party")
	Engine.remove_meta(&"mpm_core")
	Engine.remove_meta(&"_mpm_custom_minigames")
	Engine.remove_meta(&"_mpm_custom_minigames_hub")
	game_node.free()
	spike.free()
	bubble.free()
	roller.free()
	core.free()
	print("MULTI_MINIGAME_COEXISTENCE_PASSED")
	quit(0)


func _fail(msg: String) -> void:
	push_error("COEXISTENCE_TEST_FAIL: " + msg)
	quit(1)
