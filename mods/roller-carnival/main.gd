extends Node

## MPML API v2 Entry Point for Roller Carnival (滾筒嘉年華).
## Registers overrides so Roller Carnival joins Machine Party's minigame rotation
## (repurposing unused slot Globals.MinigameIdentifier.ShapeCutter = 6).

const MOD_ID := "roller-carnival"
const TARGET_SLOT_ID := 6 # Globals.MinigameIdentifier.ShapeCutter
const TARGET_SCENE_PATH := "res://minigames/shape_cutter/shape_cutter.tscn"
const REG_RES_DIR := "res://mods_roller_carnival/"

var _loader = null
var _mod_dir: String = ""
var _config_script = null
var _meshes_script = null
var _game_script = null
var _packed_minigame_scene: PackedScene = null
var _roller_icon_texture: Texture2D = null
var _official_script: GDScript


func _mod_init(loader) -> void:
	_loader = loader
	_mod_dir = str(loader.dir_of(MOD_ID))

	_official_script = loader.compile(_mod_dir.path_join("official_minigame.gd"))
	_register_mod_scripts(loader)
	if _meshes_script != null:
		_roller_icon_texture = _meshes_script.build_roller_icon()
		_roller_icon_texture.take_over_path("res://minigames/intermission_new/minigame_icons/placeholder_icons/minigame icon_placeholder11.png")
	_prepare_packed_minigame_scene()

	if loader.has_method("override_script_rel"):
		loader.override_script_rel(MOD_ID, "res://scripts/scenes/game/game.gd", "override_game.gd")
		loader.override_script_rel(MOD_ID, "res://scenes/lobby/components/playlist_handler.gd", "override_playlist.gd")
		loader.override_script_rel(MOD_ID, "res://minigames/intermission_new/components/intermission_game_picker.gd", "override_picker.gd")

	if loader.has_method("on_lobby"):
		loader.on_lobby(func(_lobby): _ensure_default_playlist_entry())
	if loader.has_method("on_scene_script"):
		loader.on_scene_script("res://scripts/scenes/game/game.gd", _on_game_entered)

	if loader.has_method("has_api") and loader.call("has_api", "registry"):
		var reg = loader.registry("minigames")
		if reg is Dictionary:
			reg[MOD_ID] = REG_RES_DIR + "roller_carnival_game.gd"

	loader.note(MOD_ID + ": initialized (integrated into slot ShapeCutter=6)")


func _mod_ready(loader) -> void:
	_loader = loader
	if _mod_dir.is_empty():
		_mod_dir = str(loader.dir_of(MOD_ID))

	_ensure_default_playlist_entry()


func _register_mod_scripts(loader) -> void:
	var use_register_api := false
	if loader.has_method("has_api"):
		use_register_api = bool(loader.call("has_api", "register_script"))

	if use_register_api and loader.has_method("register_script"):
		loader.register_script(MOD_ID, "config.gd", REG_RES_DIR + "config.gd")
		loader.register_script(MOD_ID, "carnival_meshes.gd", REG_RES_DIR + "carnival_meshes.gd")
		loader.register_script(MOD_ID, "roller_carnival_game.gd", REG_RES_DIR + "roller_carnival_game.gd")
		_config_script = ResourceLoader.load(REG_RES_DIR + "config.gd")
		_meshes_script = ResourceLoader.load(REG_RES_DIR + "carnival_meshes.gd")
		_game_script = ResourceLoader.load(REG_RES_DIR + "roller_carnival_game.gd")
		return

	if loader.has_method("compile"):
		_config_script = loader.compile(_mod_dir.path_join("config.gd"))
		if _config_script != null:
			_config_script.take_over_path(REG_RES_DIR + "config.gd")
		_meshes_script = loader.compile(_mod_dir.path_join("carnival_meshes.gd"))
		if _meshes_script != null:
			_meshes_script.take_over_path(REG_RES_DIR + "carnival_meshes.gd")
		_game_script = loader.compile(_mod_dir.path_join("roller_carnival_game.gd"))
		if _game_script != null:
			_game_script.take_over_path(REG_RES_DIR + "roller_carnival_game.gd")


func _prepare_packed_minigame_scene() -> void:
	if _game_script == null or _official_script == null:
		return
	var dummy_root: Node = _official_script.new()
	dummy_root.name = "RollerCarnival"
	var stage: Node3D = _game_script.new()
	stage.name = "Stage"
	dummy_root.add_child(stage)
	stage.owner = dummy_root

	var packed := PackedScene.new()
	var err: int = packed.pack(dummy_root)
	dummy_root.free()
	if err != OK:
		if _loader != null:
			_loader.note(MOD_ID + ": failed to pack RollerCarnival scene, err=" + str(err))
		return

	_packed_minigame_scene = packed
	if ResourceLoader.exists(TARGET_SCENE_PATH) or TARGET_SCENE_PATH.begins_with("res://"):
		_packed_minigame_scene.take_over_path(TARGET_SCENE_PATH)


func _get_globals_node() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("Globals")


func _ensure_default_playlist_entry() -> void:
	var glb := _get_globals_node()
	if glb == null:
		return

	var default_pl = glb.get("default_playlist")
	if default_pl is Array:
		var has_slot := false
		for item in default_pl:
			if item != null and int(item.get("game_identifier")) == TARGET_SLOT_ID:
				has_slot = true
				break
		if not has_slot and ResourceLoader.exists("res://scripts/resources/minigame_list_resource.gd"):
			var mlr_script = ResourceLoader.load("res://scripts/resources/minigame_list_resource.gd")
			if mlr_script != null:
				var mlr = mlr_script.new()
				mlr.set("game_identifier", TARGET_SLOT_ID)
				mlr.set("total_rounds", 1)
				default_pl.append(mlr)


func _on_game_entered(game_node: Node) -> void:
	if game_node == null:
		return
	_ensure_default_playlist_entry()
	_prepare_packed_minigame_scene()
