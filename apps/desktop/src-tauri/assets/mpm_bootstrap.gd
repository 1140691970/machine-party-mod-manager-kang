extends Node

## Built-in GPL-3.0-only mod bootstrap for Machine Party Mod Manager.
## Loaded first as `autoload/ModLoader` (`*res://modloader/bootstrap.gd`) so
## script overrides and resource registrations execute before game scripts load.

const LOADER_VERSION := "3"
const API_VERSION := 2
const LOG_PATH := "user://modloader.log"

const API_NAMES := [
	"note",
	"compile",
	"override_script",
	"override_script_rel",
	"dir_of",
	"has_mod",
	"mod_list",
	"open_mods_folder",
	"mount_assets",
	"register_script",
	"register_autoload",
	"register_global_class",
	"on_scene_script",
	"on_node_added",
	"on_main_menu",
	"on_lobby",
	"is_local_couch",
	"game_mode",
	"registry",
	"api_version",
	"loader_version",
	"has_api",
]

var mods_root: String = ""
var mods: Array = []

var _by_id: Dictionary = {}
var _kept_scripts: Array = []
var _registries: Dictionary = {}
var _scene_hooks: Dictionary = {}
var _node_added_hooks: Array = []
var _pending_autoloads: Dictionary = {}
var _watching: bool = false
var _log_lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	mods_root = _resolve_mods_root()
	note("Built-in MPM loader v%s (API v%d) scanning %s" % [LOADER_VERSION, API_VERSION, mods_root])
	_discover_and_init_mods()


func _ready() -> void:
	name = "ModLoader"
	for meta in mods:
		var mod_node = meta.get("node")
		if mod_node is Node and is_instance_valid(mod_node) and (mod_node as Node).get_parent() == null:
			add_child(mod_node as Node)
	_ensure_tree_watcher()
	call_deferred("_on_tree_ready")


func _resolve_mods_root() -> String:
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	if not exe_dir.is_empty():
		return exe_dir.path_join("mods")
	return ProjectSettings.globalize_path("res://").get_base_dir().path_join("mods")


func _discover_and_init_mods() -> void:
	if mods_root.is_empty() or not DirAccess.dir_exists_absolute(mods_root):
		return

	var da := DirAccess.open(mods_root)
	if da == null:
		return

	var candidates: Array = []
	da.list_dir_begin()
	while true:
		var entry_name: String = da.get_next()
		if entry_name.is_empty():
			break
		if entry_name.begins_with(".") or not da.current_is_dir():
			continue
		var mod_dir: String = mods_root.path_join(entry_name)
		var manifest_path: String = mod_dir.path_join("mod.json")
		if not FileAccess.file_exists(manifest_path):
			continue
		var parsed = _read_json_dict(manifest_path)
		if parsed.is_empty():
			note("skipped invalid mod.json in " + entry_name)
			continue
		if parsed.get("enabled", true) == false:
			continue
		var mod_id: String = str(parsed.get("id", "")).strip_edges()
		var entry_rel: String = str(parsed.get("entry", "")).strip_edges()
		if mod_id.is_empty() or entry_rel.is_empty():
			note("skipped mod missing id or entry in " + entry_name)
			continue
		var requires_raw = parsed.get("requires", [])
		var requires: Array = requires_raw if requires_raw is Array else []
		candidates.append({
			"id": mod_id,
			"name": str(parsed.get("name", mod_id)),
			"version": str(parsed.get("version", "0.0.0")),
			"entry": entry_rel,
			"priority": int(parsed.get("priority", 0)),
			"requires": requires,
			"dir": mod_dir,
			"node": null,
		})
	da.list_dir_end()

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a["priority"])
		var pb: int = int(b["priority"])
		if pa != pb:
			return pa < pb
		return str(a["id"]) < str(b["id"])
	)

	var candidate_ids: Dictionary = {}
	for c in candidates:
		candidate_ids[str(c["id"])] = true

	var loaded_ids: Dictionary = {}
	var remaining: Array = candidates
	while not remaining.is_empty():
		var next_pass: Array = []
		var progressed: bool = false
		for c in remaining:
			var deps: Array = c["requires"]
			var deps_missing := false
			var deps_ready := true
			for dep in deps:
				var dep_id: String = str(dep)
				if not candidate_ids.has(dep_id):
					deps_missing = true
					break
				if not loaded_ids.has(dep_id):
					deps_ready = false
					break
			if deps_missing:
				note("skipped mod %s: missing dependency" % str(c["id"]))
				continue
			if not deps_ready:
				next_pass.append(c)
				continue

			if _activate_mod(c):
				loaded_ids[str(c["id"])] = true
				progressed = true
		if not progressed:
			for c in next_pass:
				note("skipped mod %s: cyclic or unsatisfied dependency" % str(c["id"]))
			break
		remaining = next_pass


func _activate_mod(meta: Dictionary) -> bool:
	var mod_id: String = str(meta["id"])
	if _by_id.has(mod_id):
		note("duplicate mod id skipped: " + mod_id)
		return false

	var entry_path: String = str(meta["dir"]).path_join(str(meta["entry"]))
	var script: GDScript = compile(entry_path)
	if script == null:
		note("compile failed for entry: " + entry_path)
		return false

	var inst = script.new()
	if not (inst is Node):
		note("mod entry must extend Node: " + mod_id)
		return false

	var mod_node: Node = inst
	mod_node.name = mod_id
	meta["node"] = mod_node
	_by_id[mod_id] = meta
	mods.append(meta)

	if mod_node.has_method("_mod_init"):
		mod_node.call("_mod_init", self)
	note("loaded %s v%s" % [mod_id, str(meta["version"])])
	return true


func _on_tree_ready() -> void:
	_ensure_tree_watcher()
	_flush_pending_autoloads()
	for meta in mods:
		var mod_node = meta.get("node")
		if mod_node != null and is_instance_valid(mod_node) and mod_node.has_method("_mod_ready"):
			mod_node.call("_mod_ready", self)


func _read_json_dict(path: String) -> Dictionary:
	var txt: String = FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


func note(text: String) -> void:
	var line: String = "[modloader] " + str(text)
	print(line)
	_log_lines.append(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log_lines) + "\n")
		f.close()


func compile(abs_path: String) -> GDScript:
	var src: String = FileAccess.get_file_as_string(abs_path)
	if src.is_empty():
		note("cannot read script: " + abs_path)
		return null
	var gd := GDScript.new()
	gd.source_code = src
	var err: int = gd.reload()
	if err != OK:
		note("compile failed (%d): %s" % [err, abs_path])
		return null
	_kept_scripts.append(gd)
	return gd


func override_script(res_path: String, abs_path: String) -> bool:
	var gd: GDScript = compile(abs_path)
	if gd == null:
		return false
	gd.take_over_path(res_path)
	note("override %s <- %s" % [res_path, abs_path])
	return true


func override_script_rel(id: String, res_path: String, rel: String) -> bool:
	var base: String = dir_of(id)
	if base.is_empty():
		return false
	return override_script(res_path, base.path_join(rel))


func register_script(id: String, rel: String, res_id: String) -> bool:
	return override_script_rel(id, res_id, rel)


func register_autoload(singleton_name: String, id: String, rel: String) -> bool:
	var base: String = dir_of(id)
	if base.is_empty():
		return false
	var target_res: String = "res://modloader/autoload_%s_%s.gd" % [id, singleton_name]
	var gd: GDScript = compile(base.path_join(rel))
	if gd == null:
		return false
	gd.take_over_path(target_res)
	ProjectSettings.set_setting("autoload/" + singleton_name, "*" + target_res)
	_pending_autoloads[singleton_name] = gd
	return true


func _flush_pending_autoloads() -> void:
	var root: Window = get_tree().root if get_tree() != null else null
	if root == null:
		return
	for s_name in _pending_autoloads.keys():
		if root.has_node(str(s_name)):
			continue
		var gd: GDScript = _pending_autoloads[s_name]
		var inst = gd.new()
		if inst is Node:
			var n: Node = inst
			n.name = str(s_name)
			root.add_child(n)
		else:
			note("register_autoload skipped non-Node runtime child: " + str(s_name))


func register_global_class(cls_name: String, id: String, rel: String) -> bool:
	var target_res: String = "res://modloader/class_%s_%s.gd" % [id, cls_name]
	return register_script(id, rel, target_res)


func mount_assets(id: String, rel_zip: String) -> bool:
	var base: String = dir_of(id)
	if base.is_empty():
		return false
	var full: String = base.path_join(rel_zip)
	if not FileAccess.file_exists(full):
		note("mount_assets missing archive: " + full)
		return false
	return ProjectSettings.load_resource_pack(full, false)


func dir_of(id: String) -> String:
	if _by_id.has(id):
		return str((_by_id[id] as Dictionary).get("dir", ""))
	return ""


func has_mod(id: String) -> bool:
	return _by_id.has(id)


func mod_list() -> Array:
	var out: Array = []
	for meta in mods:
		out.append(str(meta["id"]))
	return out


func open_mods_folder() -> void:
	if not mods_root.is_empty():
		DirAccess.make_dir_recursive_absolute(mods_root)
		OS.shell_open(mods_root)


func _ensure_tree_watcher() -> void:
	if _watching or get_tree() == null:
		return
	_watching = true
	get_tree().node_added.connect(_on_tree_node_added)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	for cb in _node_added_hooks:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(node)
	var scr = node.get_script()
	if scr is Script:
		var spath: String = (scr as Script).resource_path
		if _scene_hooks.has(spath):
			var cbs: Array = _scene_hooks[spath]
			for cb in cbs:
				if cb is Callable and (cb as Callable).is_valid():
					(cb as Callable).call(node)


func on_scene_script(res_path: String, cb: Callable) -> void:
	_ensure_tree_watcher()
	if not _scene_hooks.has(res_path):
		_scene_hooks[res_path] = []
	(_scene_hooks[res_path] as Array).append(cb)


func on_node_added(cb: Callable) -> void:
	_ensure_tree_watcher()
	_node_added_hooks.append(cb)


func on_main_menu(cb: Callable) -> void:
	on_scene_script("res://scenes/main_menu/main_menu.gd", cb)
	on_scene_script("res://scenes/main_menu/scripts/main_menu.gd", cb)


func on_lobby(cb: Callable) -> void:
	on_scene_script("res://scenes/main_menu/main_menu.gd", cb)
	on_scene_script("res://scenes/main_menu/scripts/main_menu.gd", cb)
	on_scene_script("res://scenes/lobby/scripts/lobby_scene.gd", cb)


func is_local_couch() -> bool:
	var root: Window = get_tree().root if get_tree() != null else null
	if root == null:
		return false
	var gm: Node = root.get_node_or_null("GameManager")
	if gm == null:
		return false
	return bool(gm.get("local_game"))


func game_mode() -> StringName:
	if is_local_couch():
		return &"local"
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null:
		var nm: Node = root.get_node_or_null("NetworkManager")
		if nm != null and nm.get("active_backend") != null:
			var gm: Node = root.get_node_or_null("GameManager")
			if gm != null and bool(gm.get("game_in_progress")):
				return &"networked"
	return &"menu"


func registry(reg_name: String) -> Dictionary:
	if not _registries.has(reg_name):
		_registries[reg_name] = {}
	return _registries[reg_name]


func api_version() -> int:
	return API_VERSION


func loader_version() -> String:
	return LOADER_VERSION


func has_api(n) -> bool:
	if n is int or n is float:
		return API_VERSION >= int(n)
	return API_NAMES.has(str(n))
