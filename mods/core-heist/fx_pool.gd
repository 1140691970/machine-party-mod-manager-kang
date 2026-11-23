extends RefCounted

## Persistent FX pool for Core Heist using mpm-core.create_fx_pool() with standalone fallback.
## Zero runtime PackedScene.instantiate() or queue_free() during active gameplay.

const POOL_SHOVE := 6
const POOL_DEPOSIT := 4
const POOL_WARN := 2
const POOL_RESONANCE := 4
const POOL_POPUPS := 8

var _core_pool = null
var _fallback_pools: Dictionary = {}
var _fallback_active: Dictionary = {}
var _popup_pool: Array = []
var _popup_cursor: int = 0
var _shared_meshes: Dictionary = {}
var _shared_mats: Dictionary = {}
var _initialized: bool = false


func _get_or_make_mat(key: String, color: Color, emission_energy: float = 2.0) -> StandardMaterial3D:
	if _shared_mats.has(key):
		return _shared_mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b, 1.0)
	mat.emission_energy_multiplier = emission_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_mats[key] = mat
	return mat


func _get_ring_mesh(key: String, inner_r: float, outer_r: float) -> TorusMesh:
	if _shared_meshes.has(key):
		return _shared_meshes[key] as TorusMesh
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = 24
	m.ring_segments = 6
	_shared_meshes[key] = m
	return m


func _get_beam_mesh() -> CylinderMesh:
	if _shared_meshes.has("beam"):
		return _shared_meshes["beam"] as CylinderMesh
	var m := CylinderMesh.new()
	m.top_radius = 0.08
	m.bottom_radius = 0.08
	m.height = 1.0
	m.radial_segments = 10
	_shared_meshes["beam"] = m
	return m


func _make_ring_node(key: String, inner_r: float, outer_r: float, color: Color, y_scale: float = 0.25) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _get_ring_mesh(key, inner_r, outer_r)
	mi.material_override = _get_or_make_mat(key, color, 2.4)
	mi.scale = Vector3(1.0, y_scale, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


func _make_warn_beacon() -> Node3D:
	var root := Node3D.new()
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.35
	cyl.height = 8.0
	cyl.radial_segments = 16
	col.mesh = cyl
	col.position = Vector3(0.0, 4.0, 0.0)
	col.material_override = _get_or_make_mat("warn_col", Color(1.0, 0.35, 0.15, 0.28), 3.0)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(col)

	var ring := MeshInstance3D.new()
	ring.mesh = _get_ring_mesh("warn_ring", 1.15, 1.40)
	ring.position = Vector3(0.0, 0.08, 0.0)
	ring.scale = Vector3(1.0, 0.2, 1.0)
	ring.material_override = _get_or_make_mat("warn_ring", Color(1.0, 0.55, 0.15, 0.85), 3.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return root


func _make_resonance_beam() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "BeamMesh"
	mi.mesh = _get_beam_mesh()
	mi.rotation.x = PI * 0.5
	mi.material_override = _get_or_make_mat("res_beam", Color(0.35, 0.92, 1.0, 0.82), 3.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


func _create_mpm_fx_pool():
	if Engine.has_meta(&"mpm_core"):
		var core = Engine.get_meta(&"mpm_core")
		if core is Dictionary:
			var mod_node = (core as Dictionary).get("node", null)
			if mod_node != null and mod_node.has_method("create_fx_pool"):
				return mod_node.call("create_fx_pool")
	return null


func init_pools(fx_root: Node3D, skip_warmup: bool = false) -> void:
	clear()
	if fx_root == null:
		return
	_core_pool = _create_mpm_fx_pool()
	_register_kind("shove", fx_root, func(): return _make_ring_node("shove", 0.55, 0.95, Color(1.0, 0.72, 0.28, 0.82)), POOL_SHOVE)
	_register_kind("deposit", fx_root, func(): return _make_ring_node("deposit", 0.85, 1.35, Color(0.35, 1.0, 0.65, 0.88)), POOL_DEPOSIT)
	_register_kind("warn", fx_root, func(): return _make_warn_beacon(), POOL_WARN)
	_register_kind("resonance", fx_root, func(): return _make_resonance_beam(), POOL_RESONANCE)
	_init_popup_pool(fx_root)
	_initialized = true
	if not skip_warmup:
		_warmup_in_frustum()


func _register_kind(kind: String, parent: Node3D, factory: Callable, capacity: int) -> void:
	if _core_pool != null and _core_pool.has_method("register_pool"):
		_core_pool.call("register_pool", kind, parent, factory, capacity)
		return
	var arr: Array = []
	for _i in range(capacity):
		var n: Node = factory.call() as Node
		if n != null:
			parent.add_child(n)
			if n is Node3D:
				(n as Node3D).visible = false
			arr.append(n)
	_fallback_pools[kind] = arr
	_fallback_active[kind] = []


func _warmup_in_frustum() -> void:
	for kind in ["shove", "deposit", "warn", "resonance"]:
		var n := acquire(kind, 0.08)
		if n is Node3D:
			var n3: Node3D = n as Node3D
			n3.position = Vector3(0.0, 0.25, 0.0)
			n3.scale = Vector3.ONE * 0.01


func acquire(kind: String, duration: float = 0.0) -> Node:
	if not _initialized:
		return null
	if _core_pool != null and _core_pool.has_method("acquire"):
		return _core_pool.call("acquire", kind, duration) as Node
	if not _fallback_pools.has(kind):
		return null
	var pool: Array = _fallback_pools[kind] as Array
	if pool.is_empty():
		return null
	var n: Node = pool.pop_back() as Node
	if n != null and is_instance_valid(n):
		if n is Node3D:
			(n as Node3D).visible = true
		(_fallback_active[kind] as Array).append({"node": n, "remaining": duration, "timed": duration > 0.0})
	return n


func release(kind: String, node: Node) -> void:
	if node == null:
		return
	if _core_pool != null and _core_pool.has_method("release"):
		_core_pool.call("release", kind, node)
		return
	if _fallback_active.has(kind):
		var act: Array = _fallback_active[kind] as Array
		for i in range(act.size() - 1, -1, -1):
			if (act[i] as Dictionary).get("node", null) == node:
				act.remove_at(i)
				break
	if is_instance_valid(node):
		if node is Node3D:
			(node as Node3D).visible = false
		var pool: Array = _fallback_pools.get(kind, []) as Array
		if not pool.has(node):
			pool.append(node)


func spawn_burst(kind: String, pos: Vector3, duration: float = 0.35, scale_val: float = 1.0) -> void:
	var n := acquire(kind, duration)
	if n is Node3D:
		var n3: Node3D = n as Node3D
		n3.position = pos
		n3.scale = Vector3.ONE * scale_val


func _init_popup_pool(fx_root: Node3D) -> void:
	_popup_pool.clear()
	_popup_cursor = 0
	var term_font: Font = null
	if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
		term_font = ResourceLoader.load("res://fonts/Terminal F4.ttf") as Font
	for _i in range(POOL_POPUPS):
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 54
		lbl.pixel_size = 0.014
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
		if term_font != null:
			lbl.font = term_font
		lbl.visible = false
		fx_root.add_child(lbl)
		_popup_pool.append({"label": lbl, "timer": 0.0, "max_t": 0.9, "base_col": Color.WHITE})


func spawn_popup(pos: Vector3, text: String, color: Color = Color(1.0, 0.9, 0.3)) -> void:
	if _popup_pool.is_empty():
		return
	var entry: Dictionary = _popup_pool[_popup_cursor] as Dictionary
	_popup_cursor = (_popup_cursor + 1) % _popup_pool.size()
	var lbl := entry["label"] as Label3D
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.position = pos
	lbl.text = text
	lbl.modulate = color
	lbl.visible = true
	entry["timer"] = 0.9
	entry["max_t"] = 0.9
	entry["base_col"] = color


func update_resonance_beam(node: Node3D, a: Vector3, b: Vector3, color: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	var dist: float = a.distance_to(b)
	if dist < 0.05:
		node.visible = false
		return
	var mid: Vector3 = (a + b) * 0.5 + Vector3(0.0, 0.75, 0.0)
	node.position = mid
	node.look_at(b + Vector3(0.0, 0.75, 0.0), Vector3.UP)
	node.scale = Vector3(1.0, 1.0, dist)
	var mi := node.get_node_or_null("BeamMesh") as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var mat := mi.material_override as StandardMaterial3D
		mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
		mat.emission = color


func tick(delta: float) -> void:
	if not _initialized:
		return
	for raw_pop in _popup_pool:
		var pop: Dictionary = raw_pop as Dictionary
		var t: float = float(pop["timer"])
		if t > 0.0:
			t = maxf(0.0, t - delta)
			pop["timer"] = t
			var lbl := pop["label"] as Label3D
			if lbl != null and is_instance_valid(lbl):
				if t <= 0.0:
					lbl.visible = false
				else:
					lbl.position.y += delta * 1.45
					var bc: Color = pop["base_col"] as Color
					lbl.modulate = Color(bc.r, bc.g, bc.b, clampf(t / float(pop["max_t"]) * 1.4, 0.0, 1.0))

	if _core_pool != null and _core_pool.has_method("tick"):
		_core_pool.call("tick", delta)
		return
	for kind in _fallback_active.keys():
		var act: Array = _fallback_active[kind] as Array
		var expired: Array = []
		for item in act:
			var d: Dictionary = item as Dictionary
			if not bool(d.get("timed", false)):
				continue
			var rem: float = float(d.get("remaining", 0.0)) - delta
			d["remaining"] = rem
			if rem <= 0.0:
				expired.append(d.get("node", null))
		for n in expired:
			if n is Node:
				release(str(kind), n as Node)


func clear() -> void:
	if _core_pool != null and _core_pool.has_method("clear"):
		_core_pool.call("clear")
	_core_pool = null
	_fallback_pools.clear()
	_fallback_active.clear()
	_popup_pool.clear()
	_initialized = false
