extends SceneTree

class Loader:
	extends RefCounted
	var broadcast_id := ""
	func has_mod(id: String) -> bool:
		return id == broadcast_id
	func note(_message: String) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader := Loader.new()
	var args := OS.get_cmdline_user_args()
	if args.has("--test-broadcast"):
		loader.broadcast_id = "broadcast-8p-freecam"
	elif args.has("--test-legacy-broadcast"):
		loader.broadcast_id = "broadcast-8p"
	if root.mode == Window.MODE_WINDOWED:
		root.size = Vector2i(913, 607)
	root.content_scale_size = Vector2i(960, 540)
	var mode := root.mode
	if args.has("--test-fullscreen") and not check(mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN], "Test starts in fullscreen"):
		return
	var size_px := root.size
	var position_px := root.position
	var base := root.content_scale_size
	var original_cap := Engine.max_fps
	var lobby := Node3D.new()
	var camera := Camera3D.new()
	var seat := Node3D.new()
	var host := Node3D.new()
	root.add_child(lobby)
	lobby.add_child(camera)
	lobby.add_child(seat)
	seat.add_child(host)
	var hud := Label.new()
	hud.name = "ReadyButton"
	lobby.add_child(hud)
	var effect := ColorRect.new()
	effect.name = "Post Processing"
	lobby.add_child(effect)
	var hd = load("res://main.gd").new()
	root.add_child(hd)
	hd._mod_ready(loader)
	await process_frame
	await process_frame
	if not loader.broadcast_id.is_empty():
		if not check(effect.visible and Engine.max_fps == original_cap, "Broadcast owns display settings"):
			return
	else:
		var fps := 120 if args.has("--party-hd-120") else 60
		if not check(Engine.max_fps == fps and not effect.visible, "FPS and existing filters"):
			return
		if not check(root.content_scale_size == base and root.mode == mode and root.size == size_px and root.position == position_px, "Window and UI geometry must be preserved"):
			return
		var height := root.get_texture().get_height()
		var target := 1440 if args.has("--party-hd-1440") else 1080
		if height > 0 and not check(is_equal_approx(root.scaling_3d_scale, clampf(float(target) / height, 1, 2)), "Only 3D render scale changes"):
			return
		var next_filter := ColorRect.new()
		next_filter.name = "Vignette"
		lobby.add_child(next_filter)
		if not check(not next_filter.visible and hud.visible, "New scene filters and HUD"):
			return
		effect.show()
		hd.get_child(0).timeout.emit()
		if not check(not effect.visible, "Scene scripts can re-enable filters"):
			return
	if not check(host.get_parent() == seat and host.visible and root.get_camera_3d() == camera, "Seat and camera ownership"):
		return
	print("Standalone HD checks passed")
	quit()

func check(ok: bool, reason: String) -> bool:
	if not ok:
		push_error(reason)
		quit(1)
	return ok
