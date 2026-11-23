extends RefCounted

## Lobby UI Coordinator v2: resolves overlapping mod panels cleanly without touching vanilla buttons.

const META_V2 := &"mpm_lobby_ui_coordinator_v2"
const UI_STACK_GAP := 12.0
const UI_SCREEN_MARGIN := 16.0
const UI_MAX_VIEWPORT_RATIO := 0.55

var _lobby: Node = null
var _panels: Array[Control] = []
var _base_offsets: Dictionary = {} # instance_id -> Dictionary
var _accum: float = 0.0


func is_active() -> bool:
	return _lobby != null and is_instance_valid(_lobby) and _lobby.is_inside_tree()


func attach_lobby(lobby: Node) -> void:
	if lobby == null or not is_instance_valid(lobby):
		return
	_lobby = lobby
	_accum = 0.0
	Engine.set_meta(META_V2, true)
	var cb := Callable(self, "detach_lobby")
	if not lobby.tree_exiting.is_connected(cb):
		lobby.tree_exiting.connect(cb, CONNECT_ONE_SHOT)


func detach_lobby() -> void:
	_lobby = null
	_panels.clear()
	_base_offsets.clear()
	_accum = 0.0
	if Engine.has_meta(META_V2):
		Engine.remove_meta(META_V2)


func register_panel(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if not _panels.has(ctrl):
		_panels.append(ctrl)
	var cid: int = ctrl.get_instance_id()
	if not _base_offsets.has(cid):
		_base_offsets[cid] = {
			"left": ctrl.offset_left,
			"right": ctrl.offset_right,
			"top": ctrl.offset_top,
			"bottom": ctrl.offset_bottom,
			"dx": 0.0,
			"dy": 0.0,
		}


func step(delta: float) -> void:
	if not is_active():
		if Engine.has_meta(META_V2):
			detach_lobby()
		return
	_accum += delta
	if _accum >= 0.1:
		_accum = 0.0
		layout()


func layout() -> void:
	if not is_active():
		return
	var vp: Viewport = _lobby.get_viewport()
	if vp == null:
		return
	var vp_rect: Rect2 = vp.get_visible_rect()
	if vp_rect.size.x <= 1.0 or vp_rect.size.y <= 1.0:
		return

	var alive: Array[Control] = []
	var items: Array[Dictionary] = []
	for ctrl in _panels:
		if not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
			continue
		alive.append(ctrl)
		if not ctrl.visible:
			continue
		var rect: Rect2 = ctrl.get_global_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		if rect.size.x > vp_rect.size.x * UI_MAX_VIEWPORT_RATIO and rect.size.y > vp_rect.size.y * UI_MAX_VIEWPORT_RATIO:
			continue
		var cid: int = ctrl.get_instance_id()
		var st: Dictionary = _base_offsets.get(cid, {})
		var base_rect := Rect2(
			rect.position - Vector2(float(st.get("dx", 0.0)), float(st.get("dy", 0.0))),
			rect.size
		)
		items.append({"ctrl": ctrl, "st": st, "base": base_rect, "order": _panels.find(ctrl)})
	_panels = alive

	if items.size() < 2:
		for item in items:
			_shift(item["ctrl"] as Control, item["st"] as Dictionary, 0.0, 0.0)
		return

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2 = a["base"] as Rect2
		var rb: Rect2 = b["base"] as Rect2
		if absf(ra.position.y - rb.position.y) > 4.0:
			return ra.position.y < rb.position.y
		if absf(ra.position.x - rb.position.x) > 4.0:
			return ra.position.x < rb.position.x
		return int(a["order"]) < int(b["order"])
	)

	var placed: Array[Rect2] = []
	for item in items:
		var ctrl: Control = item["ctrl"] as Control
		var st: Dictionary = item["st"] as Dictionary
		var base_rect: Rect2 = item["base"] as Rect2
		var candidate: Rect2 = base_rect
		for _step in 12:
			var blocker: Rect2 = Rect2()
			var found := false
			for r in placed:
				if candidate.grow(UI_STACK_GAP * 0.5).intersects(r.grow(UI_STACK_GAP * 0.5)):
					blocker = r
					found = true
					break
			if not found:
				break
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
		_shift(ctrl, st, candidate.position.x - base_rect.position.x, candidate.position.y - base_rect.position.y)
		placed.append(candidate)


func _shift(ctrl: Control, st: Dictionary, new_dx: float, new_dy: float) -> void:
	var prev_dx: float = float(st.get("dx", 0.0))
	var prev_dy: float = float(st.get("dy", 0.0))
	if absf(new_dx - prev_dx) <= 0.5 and absf(new_dy - prev_dy) <= 0.5:
		return
	ctrl.offset_left = float(st.get("left", ctrl.offset_left)) + new_dx
	ctrl.offset_right = float(st.get("right", ctrl.offset_right)) + new_dx
	ctrl.offset_top = float(st.get("top", ctrl.offset_top)) + new_dy
	ctrl.offset_bottom = float(st.get("bottom", ctrl.offset_bottom)) + new_dy
	st["dx"] = new_dx
	st["dy"] = new_dy
