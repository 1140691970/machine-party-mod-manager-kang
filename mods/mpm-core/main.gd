extends Node

## MPM Core (核心運行庫) — Early-loading shared runtime library for Machine Party mods.
##
## Loads at priority -100, installs Minigame Hub v2 (superseding legacy HUB_VERSION = 1),
## runs Lobby UI Coordinator v2 (causing mpm_bootstrap.gd's legacy layout pass to yield),
## and exposes `event_bus`, `locale`, and `lobby_ui` via `Engine` meta `&"mpm_core"`.

const MOD_ID := "mpm-core"
const CORE_VERSION := "0.1.0"
const HUB_VERSION := 2
const META_KEY := &"mpm_core"
const REG_RES_DIR := "res://mods_mpm_core/"
const LOBBY_SCRIPT := "res://scenes/lobby/scripts/lobby_scene.gd"

const HUB_OVERRIDES := {
	"res://scripts/scenes/game/game.gd": "override_game.gd",
	"res://scenes/local_game/script/local_game.gd": "override_local_game.gd",
	"res://scenes/lobby/components/playlist_handler.gd": "override_playlist.gd",
	"res://minigames/intermission_new/components/intermission_game_picker.gd": "override_picker.gd",
}

const HELPER_SCRIPTS := [
	"event_bus.gd",
	"locale_utils.gd",
	"lobby_ui_coordinator.gd",
	"minigame_sdk.gd",
	"fx_pool.gd",
	"hook_chain.gd",
]

var _registered_scripts: Dictionary = {}
var event_bus = null
var locale = null
var lobby_ui = null
var minigame_sdk = null
var hook_chain = null
var _fx_pool_script: GDScript = null


func _load_sibling_script(filename: String) -> GDScript:
	if _registered_scripts.has(filename) and _registered_scripts[filename] != null:
		return _registered_scripts[filename] as GDScript
	if ResourceLoader.exists(REG_RES_DIR + filename):
		var reg_res = ResourceLoader.load(REG_RES_DIR + filename)
		if reg_res is GDScript:
			return reg_res as GDScript
	var self_script: Script = get_script()
	if self_script != null and not self_script.resource_path.is_empty():
		var sibling_path: String = self_script.resource_path.get_base_dir().path_join(filename)
		if ResourceLoader.exists(sibling_path):
			var sib_res = ResourceLoader.load(sibling_path)
			if sib_res is GDScript:
				return sib_res as GDScript
	var fallback_path: String = "res://" + filename
	if ResourceLoader.exists(fallback_path):
		var fb_res = load(fallback_path)
		if fb_res is GDScript:
			return fb_res as GDScript
	return null


func _register_mod_scripts(loader) -> void:
	if loader == null:
		return
	var use_register_api := false
	if loader.has_method("has_api"):
		use_register_api = bool(loader.call("has_api", "register_script"))
	if use_register_api and loader.has_method("register_script"):
		for rel in HELPER_SCRIPTS:
			var res_path: String = REG_RES_DIR + rel
			loader.register_script(MOD_ID, rel, res_path)
			_registered_scripts[rel] = ResourceLoader.load(res_path)
		return
	if loader.has_method("compile") and loader.has_method("dir_of"):
		var mod_dir: String = str(loader.dir_of(MOD_ID))
		for rel in HELPER_SCRIPTS:
			var gd = loader.compile(mod_dir.path_join(rel))
			if gd != null:
				gd.take_over_path(REG_RES_DIR + rel)
				_registered_scripts[rel] = gd


func _ensure_modules() -> void:
	if event_bus == null:
		event_bus = _load_sibling_script("event_bus.gd").new()
	if locale == null:
		locale = _load_sibling_script("locale_utils.gd").new()
	if lobby_ui == null:
		lobby_ui = _load_sibling_script("lobby_ui_coordinator.gd").new()
	if minigame_sdk == null:
		minigame_sdk = _load_sibling_script("minigame_sdk.gd").new(event_bus)
	if hook_chain == null:
		hook_chain = _load_sibling_script("hook_chain.gd").new()
	if _fx_pool_script == null:
		_fx_pool_script = _load_sibling_script("fx_pool.gd")


func create_fx_pool() -> Object:
	_ensure_modules()
	if _fx_pool_script != null:
		return _fx_pool_script.new()
	return null


func _publish_meta(loader = null) -> void:
	var payload := {
		"version": CORE_VERSION,
		"hub_version": HUB_VERSION,
		"node": self,
		"event_bus": event_bus,
		"locale": locale,
		"lobby_ui": lobby_ui,
		"minigame_sdk": minigame_sdk,
		"hook_chain": hook_chain,
		"register_minigame": Callable(minigame_sdk, "register_minigame"),
		"unregister_minigame": Callable(minigame_sdk, "unregister_minigame"),
		"fx_pool_script": _fx_pool_script,
		"create_fx_pool": Callable(self, "create_fx_pool"),
	}
	Engine.set_meta(META_KEY, payload)
	if loader != null and loader.has_method("has_api") and bool(loader.call("has_api", "registry")):
		var reg = loader.registry("mpm_core")
		if reg is Dictionary:
			(reg as Dictionary).merge(payload, true)


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


func _install_hub_overrides(loader) -> void:
	if loader == null or not loader.has_method("override_script_rel"):
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
			continue
		var replacement := ResourceLoader.get_cached_ref(path) as GDScript
		if replacement != null and replacement.get_base_script() != null:
			cached_overrides[replacement.get_base_script()] = replacement
			installed_paths[path] = true
	if installed_paths.size() >= HUB_OVERRIDES.size():
		hub["version"] = maxi(installed_version, HUB_VERSION)


func _on_lobby_entered(lobby: Node) -> void:
	_ensure_modules()
	lobby_ui.attach_lobby(lobby)


func _mod_init(loader) -> void:
	_register_mod_scripts(loader)
	_ensure_modules()
	_publish_meta(loader)
	_install_hub_overrides(loader)
	if loader != null and loader.has_method("on_scene_script"):
		loader.on_scene_script(LOBBY_SCRIPT, _on_lobby_entered)
	if loader != null and loader.has_method("note"):
		loader.note(MOD_ID + ": initialized v%s (HUB_VERSION=%d)" % [CORE_VERSION, HUB_VERSION])


func _mod_ready(loader) -> void:
	_ensure_modules()
	_publish_meta(loader)
	_install_hub_overrides(loader)


func _process(delta: float) -> void:
	if lobby_ui != null:
		lobby_ui.step(delta)


func _exit_tree() -> void:
	if lobby_ui != null:
		lobby_ui.detach_lobby()
	if event_bus != null:
		event_bus.clear()
	if hook_chain != null:
		hook_chain.clear()
	if Engine.has_meta(META_KEY):
		var meta = Engine.get_meta(META_KEY)
		if meta is Dictionary and (meta as Dictionary).get("node", null) == self:
			Engine.remove_meta(META_KEY)
	event_bus = null
	locale = null
	lobby_ui = null
	minigame_sdk = null
	hook_chain = null
	_fx_pool_script = null
	_registered_scripts.clear()
