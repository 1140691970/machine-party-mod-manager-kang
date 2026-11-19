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
	var size_px := Vector2i(2560, 1440) if args.has("--party-hd-1440") else Vector2i(1920, 1080)
	window.mode = Window.MODE_WINDOWED
	if args.has("--party-hd-internal"):
		window.content_scale_size = size_px
	window.size = size_px
	window.move_to_center()
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
