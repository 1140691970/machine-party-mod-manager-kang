extends Node

const FILTER_NAMES := ["postprocessing", "postprocess", "posterization", "vignette", "dither", "halftone", "crt"]
const FILTER_ASSETS := ["grunge", "overlay"]
const DEFAULT_MAX_SCALE := 1.5
const HIGH_MAX_SCALE := 2.0

var _tracked_filters: Dictionary = {}  # instance_id (int) -> Node

func _mod_ready(loader) -> void:
	if loader.has_method("has_mod") and (loader.has_mod("broadcast-8p-freecam") or loader.has_mod("broadcast-8p")):
		loader.note("Standalone HD: Broadcast is managing the display.")
		return
	# Apply after the game's autoloads restore the saved window mode.
	_apply.call_deferred(OS.get_cmdline_args() + OS.get_cmdline_user_args())

func _exit_tree() -> void:
	_tracked_filters.clear()

func _apply(args: PackedStringArray) -> void:
	var window := get_tree().root
	var allow_supersample := args.has("--party-hd-1440")
	var target_height := 1440 if allow_supersample else 1080
	var max_scale := HIGH_MAX_SCALE if (allow_supersample or args.has("--party-hd-2x")) else DEFAULT_MAX_SCALE
	window.size_changed.connect(_scale_3d.bind(window, target_height, max_scale, allow_supersample))
	_scale_3d(window, target_height, max_scale, allow_supersample)
	Engine.max_fps = 120 if args.has("--party-hd-120") else 60
	var vsync_mode := DisplayServer.VSYNC_DISABLED if args.has("--party-hd-no-vsync") else DisplayServer.VSYNC_ENABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

	_filter_branch(window)
	get_tree().node_added.connect(_on_node_added)
	# Lightweight safety net over tracked filter nodes only (no periodic full-tree walks).
	var refresh := Timer.new()
	refresh.wait_time = 4.0
	refresh.timeout.connect(_refresh_tracked_filters)
	add_child(refresh)
	refresh.start()

# In viewport stretch mode the 3D target is based on the viewport texture,
# not the size of the desktop window. Keep the 2D canvas at the game resolution
# and avoid supersampling above the actual window height unless explicitly requested.
func _scale_3d(window: Window, target_height: int, max_scale: float, allow_supersample: bool) -> void:
	var height := window.get_texture().get_height()
	if height <= 0:
		return
	var effective_target := target_height
	if not allow_supersample and window.size.y > 0:
		effective_target = mini(target_height, window.size.y)
	var desired := clampf(float(effective_target) / height, 1.0, max_scale)
	if not is_equal_approx(window.scaling_3d_scale, desired):
		window.scaling_3d_scale = desired

func _on_node_added(node: Node) -> void:
	_hide_filter(node)

func _filter_branch(node: Node) -> void:
	if _hide_filter(node):
		return
	for child in node.get_children():
		_filter_branch(child)

func _hide_filter(node: Node) -> bool:
	if not (node is CanvasItem or node is CanvasLayer):
		return false
	var matched := _matches(str(node.name), FILTER_NAMES)
	if not matched and node is CanvasItem:
		var material: Material = node.material
		if material:
			matched = _filter_asset(material)
			if not matched and material is ShaderMaterial and material.shader:
				matched = _filter_asset(material.shader)
	if matched:
		if node.visible:
			node.hide()
		_track_filter(node)
	return matched

func _track_filter(node: Node) -> void:
	var key := node.get_instance_id()
	if _tracked_filters.has(key):
		return
	_tracked_filters[key] = node
	if node.has_signal("visibility_changed"):
		var cb := _on_filter_visibility_changed.bind(node)
		if not node.is_connected("visibility_changed", cb):
			node.connect("visibility_changed", cb)

func _on_filter_visibility_changed(node: Node) -> void:
	if is_instance_valid(node) and node.visible:
		node.hide()

func _refresh_tracked_filters() -> void:
	if _tracked_filters.is_empty():
		return
	var stale: Array = []
	for key in _tracked_filters.keys():
		var node = _tracked_filters[key]
		if node == null or not is_instance_valid(node) or not (node as Node).is_inside_tree():
			stale.append(key)
		elif node.visible:
			node.hide()
	for key in stale:
		_tracked_filters.erase(key)

func _filter_asset(resource: Resource) -> bool:
	var filename := resource.resource_path.get_file()
	return _matches(filename, FILTER_NAMES) or _matches(filename, FILTER_ASSETS)

func _matches(value: String, tokens: Array) -> bool:
	var normalized := value.to_lower().replace("_", "").replace(" ", "").replace("-", "")
	for token in tokens:
		if normalized.contains(token):
			return true
	return false
