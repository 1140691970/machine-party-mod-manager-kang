extends Node

const FILTER_NAMES := ["postprocessing", "postprocess", "posterization", "vignette", "dither", "halftone", "crt"]
const FILTER_ASSETS := ["grunge", "overlay"]

func _mod_ready(loader) -> void:
	if loader.has_method("has_mod") and (loader.has_mod("broadcast-8p-freecam") or loader.has_mod("broadcast-8p")):
		loader.note("Standalone HD: Broadcast is managing the display.")
		return
	# Apply after the game's autoloads restore the saved window mode.
	_apply.call_deferred(OS.get_cmdline_args() + OS.get_cmdline_user_args())

func _apply(args: PackedStringArray) -> void:
	var window := get_tree().root
	var target_height := 1440 if args.has("--party-hd-1440") else 1080
	window.size_changed.connect(_scale_3d.bind(window, target_height))
	_scale_3d(window, target_height)
	Engine.max_fps = 120 if args.has("--party-hd-120") else 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_filter_branch(window)
	get_tree().node_added.connect(_on_node_added)
	# Animations and deferred scene setup can re-enable an existing effect.
	var refresh := Timer.new()
	refresh.wait_time = 4.0
	refresh.timeout.connect(_filter_branch.bind(window))
	add_child(refresh)
	refresh.start()

# In viewport stretch mode the 3D target is based on the viewport texture,
# not the size of the desktop window. Keep the 2D canvas at the game resolution.
func _scale_3d(window: Window, target_height: int) -> void:
	var height := window.get_texture().get_height()
	if height > 0:
		window.scaling_3d_scale = clampf(float(target_height) / height, 1.0, 2.0)

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
		node.hide()
	return matched

func _filter_asset(resource: Resource) -> bool:
	var filename := resource.resource_path.get_file()
	return _matches(filename, FILTER_NAMES) or _matches(filename, FILTER_ASSETS)

func _matches(value: String, tokens: Array) -> bool:
	var normalized := value.to_lower().replace("_", "").replace(" ", "").replace("-", "")
	for token in tokens:
		if normalized.contains(token):
			return true
	return false
