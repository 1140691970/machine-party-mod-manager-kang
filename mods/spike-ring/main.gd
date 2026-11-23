extends Node

## MPML API v2 Entry Point for Spike Ring (尖刺圆环).
## Registers into the shared Multi-Minigame Coexistence Hub (ADR-015) on a REAL
## vanilla slot (BurnRecycle = 17), exactly like Roller Carnival (6) and Bubble
## Blitz (8): the packed scene and icon replace the vanilla resources at their
## original paths via take_over_path(), so the official load_minigame(), playlist,
## CRT picker and overlay mods (e.g. Overtime) all keep working on a known id.
## A synthetic high slot (>= 100) is NOT used: Overtime's compiled game.gdc
## treats unknown identifiers as invalid and falls back to ChiselGauntlet (0).
## The four hub override scripts are byte-identical generic drivers: the hub
## installs them once (HUB_VERSION=1) and later mods only add metadata.

const MOD_ID := "spike-ring"
const HUB_VERSION := 1
const TARGET_SLOT_ID := 17                   # Globals.MinigameIdentifier.BurnRecycle
const TARGET_SCENE_PATH := "res://minigames/burn_recycle/burn_recycle.tscn"
const TARGET_ICON_PATH := "res://minigames/intermission_new/minigame_icons/minigame icon_burn recycle.png"
const REG_RES_DIR := "res://mods_spike_ring/"
const DEFAULT_ROUNDS := 2                   # 两关：自动切换机关配置与难度倍率

const HUB_OVERRIDES := {
	"res://scripts/scenes/game/game.gd": "override_game.gd",
	"res://scenes/local_game/script/local_game.gd": "override_local_game.gd",
	"res://scenes/lobby/components/playlist_handler.gd": "override_playlist.gd",
	"res://minigames/intermission_new/components/intermission_game_picker.gd": "override_picker.gd",
}

var _loader = null
var _mod_dir: String = ""
var _config_script = null
var _meshes_script = null
var _game_script = null
var _registered_scripts: Dictionary = {}
var _packed_minigame_scene: PackedScene = null
var _icon_texture: Texture2D = null
var _official_script: GDScript


static func _display_name() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZH"):
		return "尖刺圆环"
	return "SPIKE RING"


static func _brief_content() -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	if loc.begins_with("ZHS"):
		return "3 秒准备后开启 60 秒生存赛，躲开墙壁激光、电锯、伸缩地刺与终局缩圈尖刺环！\n[WASD / 方向键] 移动，[空格] 推搡对手；拾取空投护盾、重推 2x 与 360° 冲击波争夺优势。\n每存活 1 秒 +1 分，推倒对手 +2 分，终局存活额外 +10 分！"
	if loc.begins_with("ZH"):
		return "3 秒準備後開啟 60 秒生存賽，躲開牆壁雷射、電鋸、伸縮地刺與終局縮圈尖刺環！\n[WASD / 方向鍵] 移動，[空白鍵] 推搡對手；拾取空投護盾、重推 2x 與 360° 衝擊波爭奪優勢。\n每存活 1 秒 +1 分，推倒對手 +2 分，終局存活額外 +10 分！"
	return "3s prep then a 60s survival match: dodge wall lasers, saws, floor spikes and the shrinking spike ring!\n[WASD / Arrows] move, [Space] shove rivals; grab visible airdrops (Shield, 2x Shove, 360° Shockwave).\n+1 per second alive, +2 per shove, +10 survival bonus at the end!"


static func _controls_data() -> Array:
	var loc: String = TranslationServer.get_locale().to_upper()
	var move_text := "MOVE [WASD / ARROWS]"
	var shove_text := "SHOVE [SPACE]"
	if loc.begins_with("ZHS"):
		move_text = "移动 [WASD / 方向键]"
		shove_text = "推搡 [空格]"
	elif loc.begins_with("ZH"):
		move_text = "移動 [WASD / 方向鍵]"
		shove_text = "推搡 [空白鍵]"
	return [
		{
			"control_text": move_text,
			"controller_text": "MOVE",
			"keyboard_icons": ["KeyboardW"],
			"controller_icons": ["ControllerLeftStick"],
		},
		{
			"control_text": shove_text,
			"controller_text": "SHOVE",
			"keyboard_icons": ["KeyboardSpace"],
			"controller_icons": ["ControllerFaceSouth"],
		},
	]


func _mod_init(loader) -> void:
	_loader = loader
	_mod_dir = str(loader.dir_of(MOD_ID))
	_try_register(loader)


func _get_shared_registry(loader, reg_name: String, meta_key: String) -> Dictionary:
	var dict: Dictionary = {}
	if loader != null and loader.has_method("registry"):
		var raw = loader.registry(reg_name)
		if raw is Dictionary:
			dict = raw
	elif Engine.has_meta(meta_key):
		var existing = Engine.get_meta(meta_key)
		if existing is Dictionary:
			dict = existing
	Engine.set_meta(meta_key, dict)
	return dict


func _try_register(loader) -> void:
	if _packed_minigame_scene != null:
		return
	_official_script = loader.compile(_mod_dir.path_join("official_minigame.gd"))
	_register_mod_scripts(loader)
	if not _prepare_packed_minigame_scene():
		return
	if _meshes_script != null:
		_icon_texture = _meshes_script.build_spike_ring_icon()
		if _icon_texture != null:
			_icon_texture.take_over_path(TARGET_ICON_PATH)
			if ResourceLoader.load(TARGET_ICON_PATH) != _icon_texture:
				_loader.note(MOD_ID + ": icon not cached at " + TARGET_ICON_PATH)

	_register_into_hub(loader)
	_install_hub_overrides(loader)

	if loader.has_method("on_lobby"):
		loader.on_lobby(func(_lobby): _ensure_default_playlist_entry())
	if loader.has_method("on_scene_script"):
		loader.on_scene_script("res://scripts/scenes/game/game.gd", _on_game_entered)
		loader.on_scene_script("res://scenes/local_game/script/local_game.gd", _on_game_entered)

	if loader.has_method("has_api") and loader.call("has_api", "registry"):
		var reg = loader.registry("minigames")
		if reg is Dictionary:
			reg[MOD_ID] = REG_RES_DIR + "spike_ring_game.gd"

	loader.note(MOD_ID + ": initialized via multi-minigame hub (slot BurnRecycle=17)")


func _mod_ready(loader) -> void:
	_loader = loader
	if _mod_dir.is_empty():
		_mod_dir = str(loader.dir_of(MOD_ID))
	if _packed_minigame_scene == null:
		_try_register(loader)
	else:
		_register_into_hub(loader)
		_install_hub_overrides(loader)
	_ensure_default_playlist_entry()


func _register_into_hub(loader) -> void:
	var spec := {
		"mod_id": MOD_ID,
		"slot_id": TARGET_SLOT_ID,
		"scene_path": TARGET_SCENE_PATH,
		"packed_scene": _packed_minigame_scene,
		"icon_texture": _icon_texture,
		"default_rounds": DEFAULT_ROUNDS,
		"display_name": Callable(self, "_display_name"),
		"brief_content": Callable(self, "_brief_content"),
		"controls_data": Callable(self, "_controls_data"),
	}
	if Engine.has_meta(&"mpm_core"):
		var core = Engine.get_meta(&"mpm_core")
		if core is Dictionary:
			var sdk = (core as Dictionary).get("minigame_sdk", null)
			if sdk != null and sdk.has_method("register_minigame"):
				sdk.register_minigame(spec, loader)
				return
	var custom_map: Dictionary = _get_shared_registry(loader, "custom_minigames", "_mpm_custom_minigames")
	custom_map[TARGET_SLOT_ID] = spec


func _install_hub_overrides(loader) -> void:
	## 幂等通用驱动：首个加载的小游戏安装一次，后续只写元数据。
	if not loader.has_method("override_script_rel"):
		return
	var hub: Dictionary = _get_shared_registry(loader, "custom_minigames_hub", "_mpm_custom_minigames_hub")
	var installed_version: int = int(hub.get("version", 0))
	if not hub.has("installed_paths") or not (hub["installed_paths"] is Dictionary):
		hub["installed_paths"] = {}
	if not hub.has("cached_overrides") or not (hub["cached_overrides"] is Dictionary):
		hub["cached_overrides"] = {}

	var installed_paths: Dictionary = hub["installed_paths"]
	var cached_overrides: Dictionary = hub["cached_overrides"]
	var upgrading: bool = HUB_VERSION > installed_version
	if installed_version >= HUB_VERSION and installed_paths.size() >= HUB_OVERRIDES.size():
		return

	for path in HUB_OVERRIDES:
		if installed_paths.has(path) and not upgrading:
			continue
		if not loader.override_script_rel(MOD_ID, path, HUB_OVERRIDES[path]):
			loader.note(MOD_ID + ": hub override failed: " + path)
			continue
		var replacement := ResourceLoader.get_cached_ref(path) as GDScript
		if replacement != null and replacement.get_base_script() != null:
			cached_overrides[replacement.get_base_script()] = replacement
			installed_paths[path] = true

	if installed_paths.size() >= HUB_OVERRIDES.size():
		hub["version"] = max(installed_version, HUB_VERSION)
	if not bool(hub.get("node_hook_installed", false)) and loader.has_method("on_node_added"):
		hub["node_hook_installed"] = true
		loader.on_node_added(_apply_cached_override)


func _apply_cached_override(node: Node) -> void:
	var original = node.get_script()
	if original == null or node.is_node_ready():
		return
	var hub_raw = Engine.get_meta("_mpm_custom_minigames_hub", {})
	if not (hub_raw is Dictionary):
		return
	var cached_overrides = (hub_raw as Dictionary).get("cached_overrides", {})
	if not (cached_overrides is Dictionary) or not (cached_overrides as Dictionary).has(original):
		return
	var exports := {}
	for property in original.get_script_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			exports[property.name] = node.get(property.name)
	node.set_script((cached_overrides as Dictionary)[original])
	for key in exports:
		node.set(key, exports[key])


func _register_mod_scripts(loader) -> void:
	var helper_files: Array[String] = [
		"config.gd",
		"arena_meshes.gd",
		"team_support.gd",
		"hazard_director.gd",
		"fx_pool.gd",
		"ai_controller.gd",
		"self_test.gd",
		"spike_ring_game.gd",
	]
	var use_register_api := false
	if loader.has_method("has_api"):
		use_register_api = bool(loader.call("has_api", "register_script"))
	if use_register_api and loader.has_method("register_script"):
		for rel in helper_files:
			var res_path: String = REG_RES_DIR + rel
			loader.register_script(MOD_ID, rel, res_path)
			_registered_scripts[rel] = ResourceLoader.load(res_path)
		_config_script = _registered_scripts.get("config.gd", null)
		_meshes_script = _registered_scripts.get("arena_meshes.gd", null)
		_game_script = _registered_scripts.get("spike_ring_game.gd", null)
		return
	if loader.has_method("compile"):
		for rel in helper_files:
			var gd = loader.compile(_mod_dir.path_join(rel))
			if gd != null:
				gd.take_over_path(REG_RES_DIR + rel)
				_registered_scripts[rel] = gd
		_config_script = _registered_scripts.get("config.gd", null)
		_meshes_script = _registered_scripts.get("arena_meshes.gd", null)
		_game_script = _registered_scripts.get("spike_ring_game.gd", null)


func _prepare_packed_minigame_scene() -> bool:
	if _game_script == null or _official_script == null or _meshes_script == null or _config_script == null:
		_loader.note(MOD_ID + ": missing runtime script, skipping playlist registration")
		return false
	var dummy_root: Node = _official_script.new()
	dummy_root.name = "SpikeRing"
	var stage: Node3D = _game_script.new()
	stage.name = "Stage"                   # official_minigame.gd expects $Stage
	dummy_root.add_child(stage)
	stage.owner = dummy_root

	var packed := PackedScene.new()
	var err: int = packed.pack(dummy_root)
	dummy_root.free()
	if err != OK:
		_loader.note(MOD_ID + ": failed to pack SpikeRing scene, err=" + str(err))
		return false

	packed.take_over_path(TARGET_SCENE_PATH)
	# 走原版 load_minigame(slot) 路径：ResourceLoader 必须命中替换后的场景，
	# 否则官方流程会重新加载回原版 BurnRecycle，玩家进的就不是尖刺圆环。
	if ResourceLoader.load(TARGET_SCENE_PATH) != packed:
		_loader.note(MOD_ID + ": scene registration failed at " + TARGET_SCENE_PATH)
		return false
	_packed_minigame_scene = packed
	return true


func _get_globals_node() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("Globals")


func _ensure_default_playlist_entry() -> void:
	if _packed_minigame_scene == null:
		return
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
				mlr.set("total_rounds", DEFAULT_ROUNDS)
				default_pl.append(mlr)


func _on_game_entered(game_node: Node) -> void:
	if game_node == null or _packed_minigame_scene == null:
		return
	_packed_minigame_scene.take_over_path(TARGET_SCENE_PATH)
	if _icon_texture != null:
		_icon_texture.take_over_path(TARGET_ICON_PATH)
	_ensure_default_playlist_entry()


func _exit_tree() -> void:
	if Engine.has_meta(&"mpm_core"):
		var core = Engine.get_meta(&"mpm_core")
		if core is Dictionary:
			var sdk = (core as Dictionary).get("minigame_sdk", null)
			if sdk != null and sdk.has_method("unregister_minigame"):
				sdk.unregister_minigame(MOD_ID, _loader)
	if Engine.has_meta("_mpm_custom_minigames"):
		var custom_map = Engine.get_meta("_mpm_custom_minigames")
		if custom_map is Dictionary:
			(custom_map as Dictionary).erase(TARGET_SLOT_ID)
			if (custom_map as Dictionary).is_empty():
				Engine.remove_meta("_mpm_custom_minigames")
	if not Engine.has_meta("_mpm_custom_minigames") and Engine.has_meta("_mpm_custom_minigames_hub"):
		var hub = Engine.get_meta("_mpm_custom_minigames_hub")
		if hub is Dictionary:
			(hub as Dictionary).clear()
		Engine.remove_meta("_mpm_custom_minigames_hub")
	_registered_scripts.clear()
	_config_script = null
	_meshes_script = null
	_game_script = null
	_packed_minigame_scene = null
	_icon_texture = null
