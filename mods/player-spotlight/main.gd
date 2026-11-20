extends Node

## Player Spotlight (MPML Utility Mod)
## Shines a local-only overhead industrial SpotLight3D onto your own character
## and subtly tints your own nametag across vanilla and first-party 3D minigames.
## Press F8 at any time to toggle the spotlight on or off.

const LOCAL_GROUP := &"mpm_local_player"
const META_ACTIVE := &"mpm_player_spotlight_active"
const META_ALIVE := &"mpm_alive"
const SKIP_PATH_TOKENS := ["lobby", "intermission", "main_menu", "mainmenu", "cutscene"]
const LOCAL_NAME_COLOR := Color(0.62, 1.0, 0.58, 1.0)
const SPOT_COLOR := Color(0.94, 1.0, 0.88)

var enabled: bool = true
var _tracked: Dictionary = {}  # instance_id (int) -> Dictionary
var _scan_timer: Timer = null


func _mod_init(_loader) -> void:
	Engine.set_meta(META_ACTIVE, true)


func _mod_ready(_loader) -> void:
	Engine.set_meta(META_ACTIVE, true)
	_setup.call_deferred()


func _exit_tree() -> void:
	for rec in _tracked.values():
		_cleanup_record(rec)
	_tracked.clear()
	if Engine.has_meta(META_ACTIVE):
		Engine.remove_meta(META_ACTIVE)


func _setup() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if _scan_timer == null:
		_scan_timer = Timer.new()
		_scan_timer.wait_time = 0.25
		_scan_timer.timeout.connect(_scan_tree)
		add_child(_scan_timer)
		_scan_timer.start()
	_scan_tree()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		set_spotlight_enabled(not enabled)


func set_spotlight_enabled(state: bool) -> void:
	enabled = state
	for rec in _tracked.values():
		_apply_record_visibility(rec)


func _on_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_inspect_node.call_deferred(node)


func _scan_tree() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	if root == null:
		return
	for node in get_tree().get_nodes_in_group(LOCAL_GROUP):
		if node is Node3D:
			_ensure_tracked(node as Node3D)
	_walk_branch(root)


func _walk_branch(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_inspect_node(node)
	for child in node.get_children():
		_walk_branch(child)


func _inspect_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if _is_skipped_scene_node(node):
		return

	# 1. Explicit first-party mod opt-in group
	if node is Node3D and node.is_in_group(LOCAL_GROUP):
		_ensure_tracked(node as Node3D)
		return

	# 2. Vanilla LocationIndicator (points directly at local player's target_mesh)
	if _has_property(node, "target_mesh") and _has_property(node, "unproject_camera"):
		var tm = node.get("target_mesh")
		if tm is Node3D and is_instance_valid(tm) and not _is_skipped_scene_node(tm):
			var owner_target := _resolve_player_root(tm as Node3D)
			if owner_target != null and not _is_first_person_rig(owner_target):
				_ensure_tracked(owner_target)
		return

	# 3. Vanilla BasePlayer / minigame player nodes with player_presence
	if node is Node3D and _has_property(node, "player_presence"):
		if _is_local_presence(node.get("player_presence")) and not _is_first_person_rig(node as Node3D):
			_ensure_tracked(node as Node3D)


func _resolve_player_root(node: Node3D) -> Node3D:
	var cur: Node = node
	while cur != null and cur != get_tree().root:
		if cur is Node3D and (_has_property(cur, "player_presence") or cur is CharacterBody3D):
			return cur as Node3D
		cur = cur.get_parent()
	return node


func _local_network_id() -> int:
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func _is_local_presence(presence) -> bool:
	if presence == null:
		return false
	var local_id := _local_network_id()
	if presence is Dictionary:
		if presence.has("is_local") and bool(presence["is_local"]):
			return true
		if presence.has("network_id"):
			return int(presence["network_id"]) == local_id
		return false
	if presence is Object:
		if _has_property(presence, "network_id"):
			return int(presence.get("network_id")) == local_id
	return false


func _is_skipped_scene_node(node: Node) -> bool:
	var path_lower := str(node.get_path()).to_lower()
	for token in SKIP_PATH_TOKENS:
		if path_lower.contains(token):
			return true
	return false


func _is_first_person_rig(node: Node3D) -> bool:
	return _has_active_camera_descendant(node, 4)


func _has_active_camera_descendant(node: Node, depth: int) -> bool:
	if depth <= 0:
		return false
	for child in node.get_children():
		if child is Camera3D and (child as Camera3D).current:
			return true
		if _has_active_camera_descendant(child, depth - 1):
			return true
	return false


func _has_property(obj: Object, prop_name: String) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if str(p.get("name", "")) == prop_name:
			return true
	return false


func _find_nametag_label(target: Node3D) -> Label3D:
	for child in target.get_children():
		if child is Label3D:
			return child as Label3D
		for grand in child.get_children():
			if grand is Label3D:
				return grand as Label3D
	return null


func _ensure_tracked(target: Node3D) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var key := target.get_instance_id()
	if _tracked.has(key):
		return

	var spot := SpotLight3D.new()
	spot.name = "MpmPlayerSpotlight_%d" % key
	spot.light_color = SPOT_COLOR
	spot.light_energy = 16.0
	spot.spot_range = 6.2
	spot.spot_angle = 15.0
	spot.spot_angle_attenuation = 1.8
	spot.spot_attenuation = 0.65
	spot.shadow_enabled = false
	spot.rotation_degrees = Vector3(-87.0, 0.0, 0.0)
	add_child(spot)

	var lbl := _find_nametag_label(target)
	var orig_mod := lbl.modulate if lbl != null else Color.WHITE
	var rec := {
		"target": target,
		"spot": spot,
		"label": lbl,
		"orig_modulate": orig_mod,
	}
	_tracked[key] = rec
	_sync_record(rec)


func _is_target_alive(target: Node3D) -> bool:
	if not target.visible or not target.is_visible_in_tree():
		return false
	if target.has_meta(META_ALIVE) and not bool(target.get_meta(META_ALIVE)):
		return false
	if _has_property(target, "active") and not bool(target.get("active")):
		return false
	if _has_property(target, "alive") and not bool(target.get("alive")):
		return false
	if _has_property(target, "is_alive") and not bool(target.get("is_alive")):
		return false
	if _has_property(target, "is_dead") and bool(target.get("is_dead")):
		return false
	if _has_property(target, "dead") and bool(target.get("dead")):
		return false
	return true


func _apply_record_visibility(rec: Dictionary) -> void:
	var target = rec.get("target", null)
	var spot: SpotLight3D = rec.get("spot", null)
	if not is_instance_valid(target) or not is_instance_valid(spot):
		return
	var alive := _is_target_alive(target as Node3D)
	var show_spot := enabled and alive
	spot.visible = show_spot

	var lbl = rec.get("label", null)
	if lbl == null or not is_instance_valid(lbl):
		lbl = _find_nametag_label(target as Node3D)
		if lbl != null:
			rec["label"] = lbl
			rec["orig_modulate"] = (lbl as Label3D).modulate
	if is_instance_valid(lbl) and lbl is Label3D:
		(lbl as Label3D).modulate = LOCAL_NAME_COLOR if show_spot else rec["orig_modulate"]


func _sync_record(rec: Dictionary) -> void:
	var target: Node3D = rec["target"]
	var spot: SpotLight3D = rec["spot"]
	_apply_record_visibility(rec)
	if not spot.visible:
		return

	var scale_basis := target.global_transform.basis.get_scale()
	var avg_scale := clampf((absf(scale_basis.x) + absf(scale_basis.y) + absf(scale_basis.z)) / 3.0, 0.5, 2.5)
	var height := 3.8 * avg_scale
	spot.spot_range = 6.2 * avg_scale
	spot.light_energy = 16.0 * avg_scale
	var gpos := target.global_position
	spot.global_position = Vector3(gpos.x, gpos.y + height, gpos.z + 0.20 * avg_scale)
	spot.global_rotation_degrees = Vector3(-87.0, 0.0, 0.0)


func _cleanup_record(rec: Dictionary) -> void:
	var spot = rec.get("spot", null)
	if is_instance_valid(spot) and spot is Node:
		(spot as Node).queue_free()
	var lbl = rec.get("label", null)
	if is_instance_valid(lbl) and lbl is Label3D:
		(lbl as Label3D).modulate = rec.get("orig_modulate", Color.WHITE)


func _process(_delta: float) -> void:
	if _tracked.is_empty():
		return
	var stale: Array = []
	for key in _tracked.keys():
		var rec: Dictionary = _tracked[key]
		var target = rec.get("target", null)
		if target == null or not is_instance_valid(target) or not (target as Node).is_inside_tree():
			stale.append(key)
		else:
			_sync_record(rec)
	for key in stale:
		_cleanup_record(_tracked[key])
		_tracked.erase(key)
