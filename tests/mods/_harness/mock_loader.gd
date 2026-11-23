extends RefCounted

const API_VERSION := 2

var registry: Dictionary = {}
var base_dir: String = ""
var scene_hooks: Dictionary = {}
var node_added_hooks: Array[Callable] = []
var script_overrides: Dictionary = {}
var registered_scripts: Dictionary = {}
var notes: Array[String] = []


func _init(dir: String = "") -> void:
	base_dir = dir


func has_api(min_version: int) -> bool:
	return API_VERSION >= min_version


func dir_of(_mod_instance) -> String:
	return base_dir


func compile(file_path: String) -> Script:
	var loaded := ResourceLoader.load(file_path)
	if loaded is Script:
		return loaded as Script
	return null


func on_scene_script(res_path: String, cb: Callable) -> void:
	if not scene_hooks.has(res_path):
		scene_hooks[res_path] = []
	var hooks: Array = scene_hooks[res_path]
	hooks.append(cb)


func on_node_added(cb: Callable) -> void:
	node_added_hooks.append(cb)


func override_script_rel(res_path: String, rel_path: String) -> void:
	var full_path := base_dir.path_join(rel_path) if not base_dir.is_empty() else rel_path
	var script := compile(full_path)
	if script != null:
		script_overrides[res_path] = script


func register_script(res_path: String, script: Script) -> void:
	registered_scripts[res_path] = script


func note(msg: String) -> void:
	notes.append(msg)


func trigger_scene(res_path: String, node: Node) -> void:
	if not scene_hooks.has(res_path):
		return
	var hooks: Array = scene_hooks[res_path]
	for cb in hooks:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(node)


func trigger_node_added(node: Node) -> void:
	for cb in node_added_hooks:
		if cb.is_valid():
			cb.call(node)
