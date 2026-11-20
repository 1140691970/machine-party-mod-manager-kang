extends Node

## Built-in GPL-3.0-only mod bootstrap for Machine Party Mod Manager.
## Loaded first as `autoload/ModLoader` (`*res://modloader/bootstrap.gd`) so
## script overrides and resource registrations execute before game scripts load.

const LOADER_VERSION := "5"
const API_VERSION := 2
const LOG_PATH := "user://modloader.log"
const LOBBY_SCENE_SCRIPT := "res://scenes/lobby/scripts/lobby_scene.gd"
const UI_STACK_GAP := 12.0
const UI_SCREEN_MARGIN := 16.0
const UI_MAX_VIEWPORT_RATIO := 0.55
const UI_LAYOUT_INTERVAL := 0.1

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

# Lobby UI de-conflictor state (active only while in lobby).
var _root_snapshot_done: bool = false
var _vanilla_root_ids: Dictionary = {}
var _mod_root_layers: Array = []
var _lobby_node: Node = null
var _lobby_vanilla_ids: Dictionary = {}
var _lobby_mod_layers: Dictionary = {}
var _lobby_mod_roots: Array = []
var _lobby_ui_state: Dictionary = {}
var _lobby_ui_order: int = 0
var _lobby_layout_accum: float = 0.0
var _lobby_layout_queued: bool = false


func _init() -> void:
	mods_root = _resolve_mods_root()
	note("Built-in MPM loader v%s (API v%d) scanning %s" % [LOADER_VERSION, API_VERSION, mods_root])
	_discover_and_init_mods()


func _ready() -> void:
	name = "ModLoader"
	set_process(false)
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
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null:
		for child in root.get_children():
			_vanilla_root_ids[child.get_instance_id()] = true
	_root_snapshot_done = true
	for meta in mods:
		var mod_node = meta.get("node")
		if mod_node != null and is_instance_valid(mod_node) and mod_node.has_method("_mod_ready"):
			mod_node.call("_mod_ready", self)
	if root != null:
		for child in root.get_children():
			_maybe_record_mod_root_layer(child)


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
	if _root_snapshot_done:
		_maybe_record_mod_root_layer(node)
	var scr = node.get_script()
	var spath: String = (scr as Script).resource_path if scr is Script else ""
	if spath == LOBBY_SCENE_SCRIPT:
		_begin_lobby_ui_guard(node)
	elif is_instance_valid(_lobby_node):
		_observe_lobby_added_node(node)
	for cb in _node_added_hooks:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(node)
	if not spath.is_empty() and _scene_hooks.has(spath):
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


# --- Lobby UI de-conflictor (zero-touch for all mods, never moves vanilla UI) ---

func _maybe_record_mod_root_layer(node: Node) -> void:
	if not (node is CanvasLayer or node is Control):
		return
	var tree: SceneTree = get_tree()
	if tree == null or node.get_parent() != tree.root:
		return
	if _vanilla_root_ids.has(node.get_instance_id()) or node == tree.current_scene:
		return
	var sf: String = node.scene_file_path
	if not sf.is_empty() and not sf.begins_with("res://mod"):
		return
	if not _mod_root_layers.has(node):
		_mod_root_layers.append(node)


func _begin_lobby_ui_guard(lobby_node: Node) -> void:
	_end_lobby_ui_guard()
	_lobby_node = lobby_node
	_snapshot_subtree_ids(lobby_node)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null:
		for child in root.get_children():
			if not _mod_root_layers.has(child):
				_lobby_vanilla_ids[child.get_instance_id()] = true
		if not root.size_changed.is_connected(_queue_lobby_layout):
			root.size_changed.connect(_queue_lobby_layout)
	if not lobby_node.tree_exiting.is_connected(_end_lobby_ui_guard):
		lobby_node.tree_exiting.connect(_end_lobby_ui_guard, CONNECT_ONE_SHOT)
	_scan_persistent_mod_ui()
	set_process(true)
	_queue_lobby_layout()


func _end_lobby_ui_guard() -> void:
	set_process(false)
	for raw in _lobby_mod_roots:
		if raw is Control and is_instance_valid(raw):
			var cid: int = (raw as Control).get_instance_id()
			if _lobby_ui_state.has(cid):
				_apply_control_shift(raw as Control, _lobby_ui_state[cid] as Dictionary, 0.0, 0.0)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.size_changed.is_connected(_queue_lobby_layout):
		root.size_changed.disconnect(_queue_lobby_layout)
	_lobby_node = null
	_lobby_vanilla_ids.clear()
	_lobby_mod_layers.clear()
	_lobby_mod_roots.clear()
	_lobby_ui_state.clear()
	_lobby_ui_order = 0
	_lobby_layout_accum = 0.0
	_lobby_layout_queued = false


func _snapshot_subtree_ids(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_lobby_vanilla_ids[node.get_instance_id()] = true
	for child in node.get_children():
		_snapshot_subtree_ids(child)


func _scan_persistent_mod_ui() -> void:
	for meta in mods:
		var mod_node = meta.get("node")
		if mod_node is Node and is_instance_valid(mod_node):
			_scan_mod_container_for_roots(mod_node as Node)
	for layer in _mod_root_layers:
		if layer is Node and is_instance_valid(layer):
			_scan_mod_container_for_roots(layer as Node)


func _scan_mod_container_for_roots(node: Node) -> void:
	if node is Control:
		_maybe_track_lobby_control(node as Control)
		return
	if node is CanvasLayer:
		_lobby_mod_layers[node.get_instance_id()] = true
	for child in node.get_children():
		_scan_mod_container_for_roots(child)


func _observe_lobby_added_node(node: Node) -> void:
	var nid: int = node.get_instance_id()
	if _lobby_vanilla_ids.has(nid):
		return
	var parent: Node = node.get_parent()
	if node is CanvasLayer:
		if _is_inside_lobby_or_mod_root(node):
			_lobby_mod_layers[nid] = true
			for child in node.get_children():
				if child is Control:
					_maybe_track_lobby_control(child as Control)
			_queue_lobby_layout()
		return
	if node is Control:
		# Ignore scene-authored vanilla nodes inside the lobby tree.
		if node.owner != null and _is_descendant_of(node, _lobby_node):
			_lobby_vanilla_ids[nid] = true
			return
		if _is_inside_lobby_or_mod_root(node) or (parent != null and _lobby_mod_layers.has(parent.get_instance_id())):
			_maybe_track_lobby_control(node as Control)
			_queue_lobby_layout()


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if ancestor == null or not is_instance_valid(ancestor):
		return false
	var cur: Node = node.get_parent()
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false


func _is_inside_lobby_or_mod_root(node: Node) -> bool:
	if _is_descendant_of(node, _lobby_node) or _is_descendant_of(node, self):
		return true
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and node.get_parent() == root and not _lobby_vanilla_ids.has(node.get_instance_id()):
		return true
	var cur: Node = node.get_parent()
	while cur != null:
		if _lobby_mod_layers.has(cur.get_instance_id()) or _mod_root_layers.has(cur):
			return true
		cur = cur.get_parent()
	return false


func _is_passthrough_fullscreen_wrapper(ctrl: Control) -> bool:
	return ctrl.get_class() == "Control" and ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE and ctrl.anchor_left <= 0.01 and ctrl.anchor_top <= 0.01 and ctrl.anchor_right >= 0.99 and ctrl.anchor_bottom >= 0.99


func _maybe_track_lobby_control(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if _lobby_vanilla_ids.has(ctrl.get_instance_id()):
		return
	if _is_passthrough_fullscreen_wrapper(ctrl):
		for child in ctrl.get_children():
			if child is Control:
				_maybe_track_lobby_control(child as Control)
		return
	var parent: Node = ctrl.get_parent()
	if parent is Container:
		return
	var cur: Node = parent
	while cur != null:
		if _lobby_ui_state.has(cur.get_instance_id()):
			return
		cur = cur.get_parent()
	var cid: int = ctrl.get_instance_id()
	if _lobby_ui_state.has(cid):
		return
	_lobby_ui_order += 1
	_lobby_mod_roots.append(ctrl)
	_lobby_ui_state[cid] = {
		"order": _lobby_ui_order,
		"initialized": false,
		"base_left": 0.0,
		"base_right": 0.0,
		"base_top": 0.0,
		"base_bottom": 0.0,
		"dx": 0.0,
		"dy": 0.0,
		"pinned": false,
	}


func _queue_lobby_layout() -> void:
	if _lobby_layout_queued or not is_instance_valid(_lobby_node):
		return
	_lobby_layout_queued = true
	call_deferred("_run_queued_lobby_layout")


func _run_queued_lobby_layout() -> void:
	_lobby_layout_queued = false
	if is_instance_valid(_lobby_node):
		_layout_lobby_mod_ui()


func _process(delta: float) -> void:
	if not is_instance_valid(_lobby_node):
		_end_lobby_ui_guard()
		return
	_lobby_layout_accum += delta
	if _lobby_layout_accum >= UI_LAYOUT_INTERVAL:
		_lobby_layout_accum = 0.0
		_layout_lobby_mod_ui()


func _is_control_really_visible(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
		return false
	var cur: Node = ctrl.get_parent()
	while cur != null:
		if cur is CanvasLayer and not (cur as CanvasLayer).visible:
			return false
		cur = cur.get_parent()
	return true


func _is_visual_content_control(ctrl: Control) -> bool:
	if ctrl is BaseButton or ctrl is Label or ctrl is RichTextLabel or ctrl is LineEdit:
		return true
	if ctrl is TextEdit or ctrl is SpinBox or ctrl is Slider or ctrl is ProgressBar:
		return true
	if ctrl is TextureRect or ctrl is ColorRect or ctrl is Panel or ctrl is PanelContainer:
		return true
	return ctrl.get_child_count() == 0 and ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _collect_content_rect(node: Node, acc: Array) -> void:
	if node is Control:
		var ctrl: Control = node as Control
		if not ctrl.visible:
			return
		var rect: Rect2 = ctrl.get_global_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0 and _is_visual_content_control(ctrl):
			if acc.is_empty():
				acc.append(rect)
			else:
				acc[0] = (acc[0] as Rect2).merge(rect)
	for child in node.get_children():
		_collect_content_rect(child, acc)


func _effective_content_rect(ctrl: Control) -> Rect2:
	if not _is_control_really_visible(ctrl):
		return Rect2()
	var acc: Array = []
	_collect_content_rect(ctrl, acc)
	if acc.is_empty():
		return Rect2()
	return acc[0] as Rect2


func _collect_vanilla_button_rects() -> Array:
	var rects: Array = []
	if not is_instance_valid(_lobby_node):
		return rects
	_walk_vanilla_buttons(_lobby_node, rects)
	return rects


func _walk_vanilla_buttons(node: Node, out: Array) -> void:
	if node is Control and not (node as Control).visible:
		return
	var nid: int = node.get_instance_id()
	if _lobby_ui_state.has(nid):
		return
	if node is BaseButton and _lobby_vanilla_ids.has(nid):
		var btn: Control = node as Control
		if _is_control_really_visible(btn):
			var r: Rect2 = btn.get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append(r)
	for child in node.get_children():
		_walk_vanilla_buttons(child, out)


func _control_was_repositioned(ctrl: Control, st: Dictionary) -> bool:
	var dx: float = float(st["dx"])
	var dy: float = float(st["dy"])
	if absf(dy) > 0.5:
		var expected_top: float = float(st["base_top"]) + dy if (ctrl.anchor_top == ctrl.anchor_bottom or dy > 0.0) else float(st["base_top"])
		if absf(ctrl.offset_top - expected_top) > 2.0:
			return true
	if absf(dx) > 0.5:
		if ctrl.anchor_left == ctrl.anchor_right or dx > 0.0:
			if absf(ctrl.offset_left - (float(st["base_left"]) + dx)) > 2.0:
				return true
		else:
			if absf(ctrl.offset_right - (float(st["base_right"]) + dx)) > 2.0:
				return true
	return false


func _apply_control_shift(ctrl: Control, st: Dictionary, new_dx: float, new_dy: float) -> void:
	var prev_dx: float = float(st["dx"])
	var prev_dy: float = float(st["dy"])
	if absf(new_dx - prev_dx) <= 0.5 and absf(new_dy - prev_dy) <= 0.5:
		return
	var delta_x: float = new_dx - prev_dx
	var delta_y: float = new_dy - prev_dy
	if ctrl.anchor_left == ctrl.anchor_right:
		ctrl.offset_left = float(st["base_left"]) + new_dx
		ctrl.offset_right += delta_x
	elif new_dx < 0.0:
		ctrl.offset_left = float(st["base_left"])
		ctrl.offset_right = float(st["base_right"]) + new_dx
	elif new_dx > 0.0:
		ctrl.offset_left = float(st["base_left"]) + new_dx
		ctrl.offset_right = float(st["base_right"])
	else:
		ctrl.offset_left = float(st["base_left"])
		ctrl.offset_right = float(st["base_right"])

	if ctrl.anchor_top == ctrl.anchor_bottom:
		ctrl.offset_top = float(st["base_top"]) + new_dy
		ctrl.offset_bottom += delta_y
	elif new_dy > 0.0:
		ctrl.offset_top = float(st["base_top"]) + new_dy
		ctrl.offset_bottom = float(st["base_bottom"])
	elif new_dy < 0.0:
		ctrl.offset_top = float(st["base_top"])
		ctrl.offset_bottom = float(st["base_bottom"]) + new_dy
	else:
		ctrl.offset_top = float(st["base_top"])
		ctrl.offset_bottom = float(st["base_bottom"])

	st["dx"] = new_dx
	st["dy"] = new_dy


func _rects_overlap_with_gap(a: Rect2, b: Rect2, gap: float) -> bool:
	return a.grow(gap * 0.5).intersects(b.grow(gap * 0.5))


func _layout_lobby_mod_ui() -> void:
	if not is_instance_valid(_lobby_node):
		return
	var vp: Viewport = _lobby_node.get_viewport()
	if vp == null:
		return
	var vp_rect: Rect2 = vp.get_visible_rect()
	if vp_rect.size.x <= 1.0 or vp_rect.size.y <= 1.0:
		return

	var alive: Array = []
	var pinned_items: Array = []
	var movable_items: Array = []

	for raw in _lobby_mod_roots:
		if not (raw is Control) or not is_instance_valid(raw):
			continue
		var ctrl: Control = raw as Control
		var cid: int = ctrl.get_instance_id()
		if not _lobby_ui_state.has(cid):
			continue
		alive.append(ctrl)
		var st: Dictionary = _lobby_ui_state[cid]
		var rect: Rect2 = _effective_content_rect(ctrl)
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		# Skip fullscreen modals, dim backdrops, or full-width banners (but allow tall narrow sidebars).
		var too_wide: bool = rect.size.x > vp_rect.size.x * UI_MAX_VIEWPORT_RATIO
		var too_tall: bool = rect.size.y > vp_rect.size.y * UI_MAX_VIEWPORT_RATIO
		if (too_wide and too_tall) or rect.size.x > vp_rect.size.x * 0.75 or rect.size.y > vp_rect.size.y * 0.85:
			continue
		if not bool(st["initialized"]):
			st["initialized"] = true
			st["base_left"] = ctrl.offset_left
			st["base_right"] = ctrl.offset_right
			st["base_top"] = ctrl.offset_top
			st["base_bottom"] = ctrl.offset_bottom
		elif not bool(st["pinned"]) and _control_was_repositioned(ctrl, st):
			st["pinned"] = true
			st["base_left"] = ctrl.offset_left
			st["base_right"] = ctrl.offset_right
			st["base_top"] = ctrl.offset_top
			st["base_bottom"] = ctrl.offset_bottom
			st["dx"] = 0.0
			st["dy"] = 0.0

		var base_rect := Rect2(
			rect.position - Vector2(float(st["dx"]), float(st["dy"])),
			rect.size
		)
		var item: Dictionary = {
			"ctrl": ctrl,
			"state": st,
			"base_rect": base_rect,
			"order": int(st["order"]),
		}
		if bool(st["pinned"]):
			pinned_items.append(item)
		else:
			movable_items.append(item)

	_lobby_mod_roots = alive

	if pinned_items.size() + movable_items.size() < 2:
		for item in movable_items:
			_apply_control_shift(item["ctrl"] as Control, item["state"] as Dictionary, 0.0, 0.0)
		return

	movable_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2 = a["base_rect"] as Rect2
		var rb: Rect2 = b["base_rect"] as Rect2
		if absf(ra.position.y - rb.position.y) > 4.0:
			return ra.position.y < rb.position.y
		if absf(ra.position.x - rb.position.x) > 4.0:
			return ra.position.x < rb.position.x
		return int(a["order"]) < int(b["order"])
	)

	var placed_rects: Array = []
	for item in pinned_items:
		placed_rects.append(item["base_rect"] as Rect2)

	var vanilla_buttons: Array = _collect_vanilla_button_rects()

	for item in movable_items:
		var ctrl: Control = item["ctrl"] as Control
		var st: Dictionary = item["state"] as Dictionary
		var base_rect: Rect2 = item["base_rect"] as Rect2
		var candidate: Rect2 = base_rect
		var collided := false

		for _step in 12:
			var blocker_found := false
			var blocker := Rect2()
			for r in placed_rects:
				var placed: Rect2 = r as Rect2
				if _rects_overlap_with_gap(candidate, placed, UI_STACK_GAP):
					blocker = placed
					blocker_found = true
					break
			if not blocker_found and collided:
				for vb in vanilla_buttons:
					var vrect: Rect2 = vb as Rect2
					if _rects_overlap_with_gap(candidate, vrect, UI_STACK_GAP):
						blocker = vrect
						blocker_found = true
						break
			if not blocker_found:
				break
			collided = true
			var next_y: float = blocker.end.y + UI_STACK_GAP
			if next_y + candidate.size.y <= vp_rect.end.y - UI_SCREEN_MARGIN:
				candidate.position.y = next_y
			else:
				var next_x: float = blocker.position.x - candidate.size.x - UI_STACK_GAP
				if next_x >= vp_rect.position.x + UI_SCREEN_MARGIN:
					candidate.position.x = next_x
					candidate.position.y = base_rect.position.y
				else:
					candidate.position.y = minf(next_y, vp_rect.end.y - candidate.size.y - UI_SCREEN_MARGIN)
					break

		var new_dx: float = candidate.position.x - base_rect.position.x
		var new_dy: float = candidate.position.y - base_rect.position.y
		_apply_control_shift(ctrl, st, new_dx, new_dy)
		placed_rects.append(candidate)
