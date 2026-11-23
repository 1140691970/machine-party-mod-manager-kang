extends RefCounted

## Persistent GPU particle FX pools, 3D score popups, and shockwave rings for Spike Ring.

const POOL_HIT_FX := 6
const POOL_DUST_FX := 4

var hit_fx_pool: Array[Dictionary] = []
var dust_fx_pool: Array[Dictionary] = []
var hit_fx_cursor: int = 0
var dust_fx_cursor: int = 0

var popups: Array = []
var shockwaves: Array = []


func clear() -> void:
	popups.clear()
	shockwaves.clear()
	hit_fx_pool.clear()
	dust_fx_pool.clear()
	hit_fx_cursor = 0
	dust_fx_cursor = 0


func _collect_particles_recursive(node: Node, out: Array[Node]) -> void:
	if node is GPUParticles3D:
		var gp: GPUParticles3D = node
		gp.emitting = false
		out.append(gp)
	elif node is CPUParticles3D:
		var cp: CPUParticles3D = node
		cp.emitting = false
		out.append(cp)
	for child in node.get_children():
		_collect_particles_recursive(child, out)


func _build_fx_pool(fx_root: Node3D, scene: PackedScene, count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if scene == null or fx_root == null:
		return pool
	for _i in range(count):
		var inst: Node = scene.instantiate()
		if inst is Node3D:
			var n3: Node3D = inst as Node3D
			if n3.get_script() != null:
				n3.set_script(null)
			var emitters: Array[Node] = []
			_collect_particles_recursive(n3, emitters)
			n3.position = Vector3(0.0, -50.0, 0.0)
			n3.visible = false
			fx_root.add_child(n3)
			pool.append({"node": n3, "emitters": emitters, "timer": 0.0})
		elif inst != null:
			inst.queue_free()
	return pool


func init_pools(stage: Node3D) -> void:
	var fx_root: Node3D = stage._fx_root
	if bool(stage._is_self_test) or fx_root == null:
		return
	hit_fx_pool = _build_fx_pool(fx_root, stage._fx_hit_scene, POOL_HIT_FX)
	dust_fx_pool = _build_fx_pool(fx_root, stage._fx_dust_scene, POOL_DUST_FX)
	if str(stage._screenshot_path).is_empty():
		var warm_pos := Vector3(0.0, 0.3, 0.0)
		for pool in [hit_fx_pool, dust_fx_pool]:
			if not pool.is_empty():
				trigger_fx_entry(pool[0], warm_pos, 0.01, 0.08)


func trigger_fx_entry(entry: Dictionary, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	var n3: Node3D = entry["node"]
	if not is_instance_valid(n3):
		return
	n3.position = world_pos
	n3.scale = Vector3.ONE * scale_val
	n3.visible = true
	entry["timer"] = lifetime
	for em in entry["emitters"]:
		if em is GPUParticles3D:
			var gp: GPUParticles3D = em
			gp.restart()
			gp.emitting = true
		elif em is CPUParticles3D:
			var cp: CPUParticles3D = em
			cp.restart()
			cp.emitting = true


func step_fx_pools(delta: float) -> void:
	for pool in [hit_fx_pool, dust_fx_pool]:
		for entry in pool:
			var rem: float = float(entry["timer"])
			if rem > 0.0:
				rem -= delta
				entry["timer"] = rem
				if rem <= 0.0:
					var n3: Node3D = entry["node"]
					if is_instance_valid(n3):
						n3.visible = false
						n3.position = Vector3(0.0, -50.0, 0.0)


func spawn_fx(stage: Node3D, scene: PackedScene, world_pos: Vector3, scale_val: float, lifetime: float) -> void:
	if bool(stage._is_self_test) or scene == null:
		return
	if scene == stage._fx_hit_scene and not hit_fx_pool.is_empty():
		var entry: Dictionary = hit_fx_pool[hit_fx_cursor % hit_fx_pool.size()]
		hit_fx_cursor += 1
		trigger_fx_entry(entry, world_pos, scale_val, lifetime)
	elif scene == stage._fx_dust_scene and not dust_fx_pool.is_empty():
		var entry: Dictionary = dust_fx_pool[dust_fx_cursor % dust_fx_pool.size()]
		dust_fx_cursor += 1
		trigger_fx_entry(entry, world_pos, scale_val, lifetime)


func spawn_score_popup(stage: Node3D, world_pos: Vector3, text: String, color: Color) -> void:
	var fx_root: Node3D = stage._fx_root
	if bool(stage._is_self_test) or fx_root == null:
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 46
	lbl.outline_size = 10
	lbl.pixel_size = 0.011
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = color
	var term_font: Font = stage._term_font
	if term_font != null:
		lbl.font = term_font
	lbl.position = world_pos
	fx_root.add_child(lbl)
	popups.append({"node": lbl, "age": 0.0, "max_age": 0.85, "base_col": color})


func spawn_shockwave(stage: Node3D, world_pos: Vector3) -> void:
	var fx_root: Node3D = stage._fx_root
	var meshes = stage.M
	var cfg = stage.C
	if bool(stage._is_self_test) or fx_root == null or meshes == null or cfg == null:
		return
	var ring: MeshInstance3D = meshes.build_shockwave_ring()
	ring.position = world_pos
	ring.scale = Vector3(0.35, 1.0, 0.35)
	fx_root.add_child(ring)
	shockwaves.append({"node": ring, "age": 0.0, "max_age": 0.34, "max_r": float(cfg.SHOCKWAVE_RANGE)})


func step_popups_and_shockwaves(delta: float) -> void:
	for i in range(popups.size() - 1, -1, -1):
		var pop: Dictionary = popups[i]
		var lbl: Label3D = pop["node"]
		pop["age"] = float(pop["age"]) + delta
		var t: float = float(pop["age"]) / float(pop["max_age"])
		if not is_instance_valid(lbl) or t >= 1.0:
			if is_instance_valid(lbl):
				lbl.queue_free()
			popups.remove_at(i)
		else:
			lbl.position.y += delta * 1.45
			var col: Color = pop["base_col"]
			col.a = clampf(1.0 - t * t, 0.0, 1.0)
			lbl.modulate = col
			popups[i] = pop

	for i in range(shockwaves.size() - 1, -1, -1):
		var sw: Dictionary = shockwaves[i]
		var ring: MeshInstance3D = sw["node"]
		sw["age"] = float(sw["age"]) + delta
		var t: float = float(sw["age"]) / float(sw["max_age"])
		if not is_instance_valid(ring) or t >= 1.0:
			if is_instance_valid(ring):
				ring.queue_free()
			shockwaves.remove_at(i)
		else:
			var r: float = lerpf(0.35, float(sw["max_r"]), 1.0 - pow(1.0 - t, 2.0))
			ring.scale = Vector3(r, maxf(0.15, 1.0 - t * 0.7), r)
			shockwaves[i] = sw
