extends RefCounted

## Authentic Machine Party 3D asset loader and arena builders for Core Heist (能源搶奪戰).
## Reuses vanilla Machine Party worker rigs, cosmetics, industrial textures,
## Terminal F4 font, and animations when Machine Party.pck is available,
## with clean procedural fallbacks for headless tests.

const TEX_THREADPLATE := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_threadplate albedo.png"
const TEX_THREADPLATE_NORMAL := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_threadplate normal 1024.png"
const TEX_CONTROL_PANEL := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_chisel gauntlet control panel1.png"
const TEX_METAL_PLATE := "res://minigames/dvd_roomba/models/dvd roomba visuals1_metal plate1.png"
const TEX_GRATE := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba grate.png"
const TEX_WALL := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba walls1.png"
const TEX_SIDING := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba siding.png"
const TEX_PIPES := "res://minigames/forklift_certified/models/forklift certified visuals1/forklift certified visuals1_fc pipes2.png"
const TEX_HEAVY_RUST := "res://minigames/junk_platform/models/junk platform visuals2/junk platform visuals2_heavy rust2.png"
const TEX_CONVEYOR := "res://textures/conveyor belt new1.png"
const GLB_WALL_LAMP := "res://models/elevator light2/elevator light2.glb"

const TEAM_SUIT_TEXTURES := {
	1: "res://modules/character_customization/character_customization_textures/main character painted red.png",
	2: "res://modules/character_customization/character_customization_textures/main character painted blue.png",
	3: "res://modules/character_customization/character_customization_textures/main character painted green.png",
	4: "res://modules/character_customization/character_customization_textures/main character painted yellow.png",
}

const HAT_COSMETICS := [
	{"path": "res://models/character cosmetics/cosmetic_tophat/cosmetic_tophat.glb", "tf": Transform3D(Basis(Vector3(8.158974e-05, -0.037862033, 0.99928296), Vector3(0.019726971, 0.999088, 0.037853032), Vector3(-0.999805, 0.019709742, 0.00082841865)), Vector3(-0.037711527, -0.012129298, 0.0011413771))},
	{"path": "res://models/character cosmetics/cosmetic_traffic cone/cosmetic_traffic cone.glb", "tf": Transform3D(Basis(Vector3(8.235251e-05, 0.01972697, -0.999805), Vector3(-0.037861828, 0.999088, 0.019709704), Vector3(0.99928296, 0.03785286, 0.0008291773)), Vector3(0.003989991, 0.022721278, 0.00048916205))},
	{"path": "res://models/character cosmetics/cosmetic_rubiks cube/cosmetic_rubiks cube.glb", "tf": Transform3D(Basis(Vector3(-0.0005221995, -0.03484504, 0.9993929), Vector3(0.0957382, 0.9947999, 0.034734927), Vector3(-0.995406, 0.095698185, 0.0028165167)), Vector3(-0.042844664, -0.28462917, -0.0064088996))},
	{"path": "res://models/character cosmetics/cosmetic_maska helmet/cosmetic_maska helmet.glb", "tf": Transform3D(Basis(Vector3(7.8010664e-05, -0.035887193, 0.94715995), Vector3(0.018698016, 0.94697505, 0.035878647), Vector3(-0.94765496, 0.018681668, 0.00078588596)), Vector3(0.14080398, -0.25333482, -0.0127572995))},
	{"path": "res://models/character cosmetics/cosmetic_beer hat/cosmetic_beer hat.glb", "tf": Transform3D(Basis(Vector3(1.0025692e-06, -1.7719703e-12, 0.974151), Vector3(-1.4175761e-11, 0.974151, 1.7719849e-12), Vector3(-0.974152, -1.4175778e-11, 1.0025702e-06)), Vector3(-0.0142675, -0.0986309, -0.022806684))},
	{"path": "res://models/character cosmetics/cosmetic_cap blade/cosmetic_cap blade.glb", "tf": Transform3D(Basis(Vector3(0.003480548, 0.004266754, 0.956244), Vector3(0.113083966, 0.94953805, -0.0046484363), Vector3(-0.949544, 0.11309913, 0.0029515137)), Vector3(0.084976204, -0.106761985, -0.0011991335))},
	{"path": "res://models/character cosmetics/cosmetic_drill sgt hat/cosmetic_drill sgt hat.glb", "tf": Transform3D(Basis(Vector3(-4.4703484e-08, 1.8626451e-09, 1.0), Vector3(0.10154249, 0.9948314, 3.7252903e-09), Vector3(-0.9948314, 0.10154248, -3.7252903e-08)), Vector3(0.026, -0.018, 0.0))},
	{"path": "res://models/character cosmetics/cosmetic_hard hat/cosmetic_hard hat.glb", "tf": Transform3D(Basis(Vector3(-4.4703484e-08, -1.8626451e-09, 1.0), Vector3(0.1583304, 0.9873862, 9.313226e-09), Vector3(-0.9873862, 0.15833038, -3.7252903e-08)), Vector3(0.073, -0.045, 0.0))},
]

const HAT_COSMETIC_BY_NAME := {
	"tophat": 0, "traffic_cone": 1, "rubiks_cube": 2, "maska_helmet": 3,
	"beer_hat": 4, "cap_blade": 5, "drill_sgt_hat": 6, "hard_hat": 7,
}

const GLASSES_COSMETICS := {
	0: {"path": "res://models/character cosmetics/cosmetic_glasses sunglasses/cosmetic_glasses sunglasses.glb", "tf": Transform3D(Basis(Vector3(-0.000494335, -0.00512526, 0.999987), Vector3(-0.0133705, 0.999898, 0.00511819), Vector3(-0.99991, -0.0133678, -0.000562828)), Vector3(0.249448, 0.222335, 6.0644e-05))},
	5: {"path": "res://models/character cosmetics/cosmetic_reading glasses/cosmetic_reading glasses.glb", "tf": Transform3D(Basis(Vector3(0.00952975, -0.0227329, 0.999696), Vector3(-0.141247, 0.989687, 0.0238517), Vector3(-0.989929, -0.141432, 0.00622053)), Vector3(0.253487, 0.231504, -0.0139316))},
}

const GLASSES_COSMETIC_BY_NAME := {
	"sunglasses": 0, "reading_glasses": 5,
}

static var _pck_checked: bool = false
static var _pck_available: bool = false
static var _shove_anim_cache: Animation = null
static var _shove_anim_checked: bool = false

var _mesh_cache: Dictionary = {}
var _mat_cache: Dictionary = {}


static func ensure_game_pck_mounted() -> bool:
	if _pck_checked:
		return _pck_available
	_pck_checked = true
	if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
		_pck_available = true
		return true
	var pck_path: String = OS.get_environment("MP_PCK_PATH")
	if not pck_path.is_empty() and FileAccess.file_exists(pck_path):
		if ProjectSettings.load_resource_pack(pck_path, false):
			_pck_available = ResourceLoader.exists("res://fonts/Terminal F4.ttf")
			return _pck_available
	_pck_available = false
	return false


static func load_optional(path: String):
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func load_terminal_font() -> Font:
	return load_optional("res://fonts/Terminal F4.ttf") as Font


func _get_mat(
	key: String,
	albedo: Color,
	metallic: float = 0.25,
	roughness: float = 0.55,
	emission: Color = Color.BLACK,
	emission_energy: float = 0.0,
	alpha: bool = false,
	tex_path: String = "",
	uv_scale: Vector3 = Vector3.ONE,
	normal_path: String = ""
) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not tex_path.is_empty():
		var tex = load_optional(tex_path)
		if tex is Texture2D:
			mat.albedo_texture = tex as Texture2D
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.uv1_scale = uv_scale
	if not normal_path.is_empty():
		var ntex = load_optional(normal_path)
		if ntex is Texture2D:
			mat.normal_enabled = true
			mat.normal_texture = ntex as Texture2D
			mat.normal_scale = 0.72
	_mat_cache[key] = mat
	return mat


func _get_box(key: String, size: Vector3) -> BoxMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key] as BoxMesh
	var m := BoxMesh.new()
	m.size = size
	_mesh_cache[key] = m
	return m


func _get_cyl(key: String, top_r: float, bot_r: float, h: float, segs: int = 18) -> CylinderMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key] as CylinderMesh
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = segs
	_mesh_cache[key] = m
	return m


func _get_torus(key: String, inner_r: float, outer_r: float, rings: int = 24) -> TorusMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key] as TorusMesh
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = rings
	m.ring_segments = 6
	_mesh_cache[key] = m
	return m


func build_arena(parent: Node3D, team_ids: Array, cfg, vault_by_team: Dictionary, pillars: Array) -> Dictionary:
	ensure_game_pck_mounted()
	var team_count: int = clampi(team_ids.size(), 2, 4)
	var arena_size: float = float(cfg.arena_size_for_teams(team_count))
	var half: float = arena_size * 0.5
	var term_font: Font = load_terminal_font()

	var floor_mat := _get_mat("floor", Color(0.76, 0.80, 0.86), 0.28, 0.62, Color.BLACK, 0.0, false, TEX_THREADPLATE, Vector3(12.0, 12.0, 1.0), TEX_THREADPLATE_NORMAL)
	var wall_mat := _get_mat("wall_tex", Color(0.84, 0.86, 0.90), 0.4, 0.5, Color.BLACK, 0.0, false, TEX_WALL, Vector3(8.0, 1.0, 1.0))
	var trim_mat := _get_mat("trim", Color(0.78, 0.82, 0.86), 0.55, 0.38, Color.BLACK, 0.0, false, TEX_METAL_PLATE, Vector3(2.0, 2.0, 1.0))
	var panel_mat := _get_mat("ctrl_panel", Color(0.86, 0.88, 0.92), 0.45, 0.42, Color.BLACK, 0.0, false, TEX_CONTROL_PANEL, Vector3(1.0, 1.0, 1.0))
	var hazard_mat := _get_mat("hazard", Color(0.95, 0.68, 0.16), 0.2, 0.45, Color(0.92, 0.65, 0.14), 0.35, false, TEX_SIDING, Vector3(6.0, 1.0, 1.0))
	var pipes_mat := _get_mat("pipes", Color(0.86, 0.88, 0.92), 0.55, 0.38, Color.BLACK, 0.0, false, TEX_PIPES, Vector3(2.0, 2.0, 1.0))
	var rust_mat := _get_mat("rust", Color(0.88, 0.84, 0.80), 0.45, 0.55, Color.BLACK, 0.0, false, TEX_HEAVY_RUST, Vector3(2.0, 2.0, 1.0))
	var conv_mat_l := _get_mat("conveyor_l", Color(0.82, 0.86, 0.90), 0.35, 0.45, Color.BLACK, 0.0, false, TEX_CONVEYOR, Vector3(3.0, 1.0, 1.0))
	var conv_mat_r := _get_mat("conveyor_r", Color(0.82, 0.86, 0.90), 0.35, 0.45, Color.BLACK, 0.0, false, TEX_CONVEYOR, Vector3(3.0, 1.0, 1.0))
	var crt_body_mat := _get_mat("crt_body", Color(0.11, 0.13, 0.17), 0.5, 0.4)
	var amber_beacon_mat := _get_mat("amber_beacon", Color(1.0, 0.65, 0.14), 0.2, 0.2, Color(1.0, 0.62, 0.10), 2.4)

	# Main industrial floor
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = _get_box("floor_" + str(int(arena_size)), Vector3(arena_size, 0.5, arena_size))
	floor_mi.position = Vector3(0.0, -0.25, 0.0)
	floor_mi.material_override = floor_mat
	parent.add_child(floor_mi)

	# Reinforced perimeter walls + corner stanchions + optional factory wall lamps
	var wall_specs: Array = [
		[Vector3(0.0, 0.52, -half), Vector3(arena_size + 0.7, 1.04, 0.62)],
		[Vector3(0.0, 0.52, half), Vector3(arena_size + 0.7, 1.04, 0.62)],
		[Vector3(-half, 0.52, 0.0), Vector3(0.62, 1.04, arena_size + 0.7)],
		[Vector3(half, 0.52, 0.0), Vector3(0.62, 1.04, arena_size + 0.7)],
	]
	for i in range(wall_specs.size()):
		var spec: Array = wall_specs[i] as Array
		var w := MeshInstance3D.new()
		var sz: Vector3 = spec[1] as Vector3
		w.mesh = _get_box("wall_%d_%d" % [int(arena_size), i], sz)
		w.position = spec[0] as Vector3
		w.material_override = wall_mat
		parent.add_child(w)

		var stripe := MeshInstance3D.new()
		stripe.mesh = _get_box("wstripe_%d_%d" % [int(arena_size), i], Vector3(sz.x * 0.99, 0.16, sz.z * 1.02))
		stripe.position = (spec[0] as Vector3) + Vector3(0.0, 0.54, 0.0)
		stripe.material_override = hazard_mat
		parent.add_child(stripe)

	var lamp_packed = load_optional(GLB_WALL_LAMP)
	for lx in [-half * 0.45, half * 0.45]:
		if lamp_packed is PackedScene:
			var lamp := (lamp_packed as PackedScene).instantiate() as Node3D
			lamp.position = Vector3(lx, 1.25, -half + 0.35)
			lamp.scale = Vector3(0.75, 0.75, 0.75)
			parent.add_child(lamp)

	# Central Energy Reactor Station
	var disp_root := Node3D.new()
	disp_root.name = "EnergyReactorStation"
	parent.add_child(disp_root)

	var disp_plinth := MeshInstance3D.new()
	disp_plinth.mesh = _get_cyl("disp_plinth", 1.55, 1.72, 0.42, 8)
	disp_plinth.position = Vector3(0.0, 0.21, 0.0)
	disp_plinth.material_override = trim_mat
	disp_root.add_child(disp_plinth)

	var disp_base := MeshInstance3D.new()
	disp_base.mesh = _get_cyl("disp_base", 1.28, 1.48, 0.85, 16)
	disp_base.position = Vector3(0.0, 0.78, 0.0)
	disp_base.material_override = rust_mat
	disp_root.add_child(disp_base)

	var disp_core := MeshInstance3D.new()
	disp_core.mesh = _get_cyl("disp_core", 0.68, 0.68, 2.35, 20)
	disp_core.position = Vector3(0.0, 2.05, 0.0)
	disp_core.material_override = _get_mat("disp_glow", Color(0.24, 0.88, 1.0, 0.92), 0.1, 0.15, Color(0.20, 0.86, 1.0), 2.8, true)
	disp_root.add_child(disp_core)

	# 4 armored vertical pipe ribs around the reactor core
	for r_idx in range(4):
		var ang: float = float(r_idx) * PI * 0.5 + PI * 0.25
		var rib := MeshInstance3D.new()
		rib.mesh = _get_cyl("disp_rib", 0.15, 0.17, 2.45, 10)
		rib.position = Vector3(cos(ang) * 1.05, 2.05, sin(ang) * 1.05)
		rib.material_override = pipes_mat
		disp_root.add_child(rib)

	# Armored reactor crown + top beacon
	var disp_cap := MeshInstance3D.new()
	disp_cap.mesh = _get_cyl("disp_cap", 0.95, 1.32, 0.48, 8)
	disp_cap.position = Vector3(0.0, 3.35, 0.0)
	disp_cap.material_override = trim_mat
	disp_root.add_child(disp_cap)

	var disp_beacon := MeshInstance3D.new()
	disp_beacon.mesh = _get_cyl("disp_beacon", 0.26, 0.34, 0.32, 12)
	disp_beacon.position = Vector3(0.0, 3.72, 0.0)
	disp_beacon.material_override = amber_beacon_mat
	disp_root.add_child(disp_beacon)

	# 2 counter-rotating energy containment rings
	var disp_ring := MeshInstance3D.new()
	disp_ring.mesh = _get_torus("disp_ring", 1.25, 1.44, 24)
	disp_ring.position = Vector3(0.0, 1.85, 0.0)
	disp_ring.scale = Vector3(1.0, 0.22, 1.0)
	disp_ring.material_override = _get_mat("disp_ring_mat", Color(0.35, 0.95, 1.0), 0.2, 0.3, Color(0.35, 0.95, 1.0), 2.2)
	disp_root.add_child(disp_ring)

	var disp_ring_b := MeshInstance3D.new()
	disp_ring_b.mesh = _get_torus("disp_ring_b", 1.02, 1.18, 24)
	disp_ring_b.position = Vector3(0.0, 2.55, 0.0)
	disp_ring_b.scale = Vector3(1.0, 0.22, 1.0)
	disp_ring_b.material_override = _get_mat("disp_ring_b_mat", Color(1.0, 0.78, 0.22), 0.2, 0.3, Color(1.0, 0.72, 0.16), 1.9)
	disp_root.add_child(disp_ring_b)

	# Flanking conveyor chute hoods (-X and +X)
	for dir_sign in [-1.0, 1.0]:
		var hood := MeshInstance3D.new()
		hood.mesh = _get_box("chute_hood", Vector3(0.65, 0.95, 1.75))
		hood.position = Vector3(dir_sign * 1.48, 0.65, 0.0)
		hood.material_override = panel_mat
		disp_root.add_child(hood)

	# Two short opposing conveyor belts (-X and +X) with steel side rails and end rollers
	var chevron_mat := _get_mat("chevron", Color(0.28, 0.88, 1.0), 0.2, 0.3, Color(0.28, 0.88, 1.0), 1.5)
	var conv_len: float = float(cfg.CONVEYOR_END_X) - float(cfg.CONVEYOR_START_X)
	var conv_mid: float = (float(cfg.CONVEYOR_END_X) + float(cfg.CONVEYOR_START_X)) * 0.5
	var half_z: float = float(cfg.CONVEYOR_HALF_Z)
	for dir_sign in [-1.0, 1.0]:
		var belt := MeshInstance3D.new()
		belt.mesh = _get_box("belt", Vector3(conv_len, 0.12, half_z * 2.0))
		belt.position = Vector3(dir_sign * conv_mid, 0.05, 0.0)
		belt.material_override = conv_mat_l if dir_sign < 0.0 else conv_mat_r
		parent.add_child(belt)

		for side_z in [-half_z - 0.08, half_z + 0.08]:
			var rail := MeshInstance3D.new()
			rail.mesh = _get_box("belt_rail", Vector3(conv_len + 0.16, 0.20, 0.14))
			rail.position = Vector3(dir_sign * conv_mid, 0.10, side_z)
			rail.material_override = trim_mat
			parent.add_child(rail)

		var roller := MeshInstance3D.new()
		roller.mesh = _get_cyl("belt_roller", 0.14, 0.14, half_z * 2.1, 12)
		roller.rotation.x = PI * 0.5
		roller.position = Vector3(dir_sign * float(cfg.CONVEYOR_END_X), 0.08, 0.0)
		roller.material_override = pipes_mat
		parent.add_child(roller)

		for s_idx in range(3):
			var strip := MeshInstance3D.new()
			strip.mesh = _get_box("belt_strip", Vector3(0.16, 0.03, half_z * 1.45))
			var offset_x: float = float(cfg.CONVEYOR_START_X) + 0.6 + float(s_idx) * 1.15
			strip.position = Vector3(dir_sign * offset_x, 0.12, 0.0)
			strip.material_override = chevron_mat
			parent.add_child(strip)

	# 4 Industrial Buffer Pillars with steel collars & top beacons
	for raw_pil in pillars:
		var p2: Vector2 = raw_pil as Vector2
		var pbase := MeshInstance3D.new()
		pbase.mesh = _get_cyl("pil_base", float(cfg.PILLAR_RADIUS) * 1.12, float(cfg.PILLAR_RADIUS) * 1.18, 0.30, 16)
		pbase.position = Vector3(p2.x, 0.15, p2.y)
		pbase.material_override = trim_mat
		parent.add_child(pbase)

		var pil := MeshInstance3D.new()
		pil.mesh = _get_cyl("pillar", float(cfg.PILLAR_RADIUS) * 0.90, float(cfg.PILLAR_RADIUS) * 0.96, 2.55, 16)
		pil.position = Vector3(p2.x, 1.45, p2.y)
		pil.material_override = rust_mat
		parent.add_child(pil)

		var pcap := MeshInstance3D.new()
		pcap.mesh = _get_cyl("pil_cap", float(cfg.PILLAR_RADIUS) * 1.04, float(cfg.PILLAR_RADIUS) * 1.04, 0.24, 16)
		pcap.position = Vector3(p2.x, 2.75, p2.y)
		pcap.material_override = trim_mat
		parent.add_child(pcap)

		var band := MeshInstance3D.new()
		band.mesh = _get_cyl("pillar_band", float(cfg.PILLAR_RADIUS) * 0.99, float(cfg.PILLAR_RADIUS) * 0.99, 0.26, 16)
		band.position = Vector3(p2.x, 1.55, p2.y)
		band.material_override = hazard_mat
		parent.add_child(band)

		var pbeacon := MeshInstance3D.new()
		pbeacon.mesh = _get_cyl("pil_beacon", 0.18, 0.22, 0.18, 10)
		pbeacon.position = Vector3(p2.x, 2.95, p2.y)
		pbeacon.material_override = amber_beacon_mat
		parent.add_child(pbeacon)

	# Team Recycling Furnace Vaults with overhead gantry & CRT scoreboard
	var vault_nodes: Dictionary = {}
	var grate_mat := _get_mat("vault_grate", Color(0.65, 0.70, 0.76), 0.4, 0.45, Color.BLACK, 0.0, false, TEX_GRATE, Vector3(2.0, 2.0, 1.0))
	for raw_tid in team_ids:
		var tid: int = int(raw_tid)
		var bp: Vector2 = vault_by_team.get(tid, Vector2.ZERO) as Vector2
		var tcol: Color = (cfg.TEAM_COLORS.get(tid, Color.WHITE) as Color)
		var vroot := Node3D.new()
		vroot.name = "Vault_T%d" % tid
		vroot.position = Vector3(bp.x, 0.0, bp.y)
		vroot.look_at_from_position(Vector3(bp.x, 0.0, bp.y), Vector3.ZERO, Vector3.UP)
		parent.add_child(vroot)

		var pad := MeshInstance3D.new()
		pad.mesh = _get_cyl("vault_pad", float(cfg.VAULT_RADIUS) + 0.08, float(cfg.VAULT_RADIUS) + 0.24, 0.18, 24)
		pad.position = Vector3(0.0, 0.09, 0.0)
		pad.material_override = trim_mat
		vroot.add_child(pad)

		var grate := MeshInstance3D.new()
		grate.mesh = _get_cyl("vault_grate_m", float(cfg.VAULT_RADIUS) - 0.18, float(cfg.VAULT_RADIUS) - 0.18, 0.20, 24)
		grate.position = Vector3(0.0, 0.10, 0.0)
		grate.material_override = grate_mat
		vroot.add_child(grate)

		var inner_pad := MeshInstance3D.new()
		inner_pad.mesh = _get_cyl("vault_inner", float(cfg.VAULT_RADIUS) - 0.55, float(cfg.VAULT_RADIUS) - 0.55, 0.21, 24)
		inner_pad.position = Vector3(0.0, 0.11, 0.0)
		inner_pad.material_override = _get_mat("vault_pad_%d" % tid, tcol * 0.78, 0.2, 0.3, tcol, 1.25)
		vroot.add_child(inner_pad)

		var arch := MeshInstance3D.new()
		arch.mesh = _get_torus("vault_arch", float(cfg.VAULT_RADIUS) - 0.20, float(cfg.VAULT_RADIUS) + 0.02, 24)
		arch.position = Vector3(0.0, 0.20, 0.0)
		arch.scale = Vector3(1.0, 0.24, 1.0)
		arch.material_override = _get_mat("vault_arch_%d" % tid, tcol, 0.2, 0.3, tcol, 1.8)
		vroot.add_child(arch)

		# Twin gantry pylons + overhead CRT scoreboard housing
		var gantry_r: float = float(cfg.VAULT_RADIUS) - 0.15
		for gx in [-gantry_r * 0.78, gantry_r * 0.78]:
			var post := MeshInstance3D.new()
			post.mesh = _get_cyl("vault_post", 0.14, 0.16, 2.35, 10)
			post.position = Vector3(gx, 1.20, 0.0)
			post.material_override = pipes_mat
			vroot.add_child(post)

		var crt_box := MeshInstance3D.new()
		crt_box.mesh = _get_box("vault_crt", Vector3(2.2, 1.15, 0.42))
		crt_box.position = Vector3(0.0, 2.65, 0.0)
		crt_box.material_override = crt_body_mat
		vroot.add_child(crt_box)

		var crt_bezel := MeshInstance3D.new()
		crt_bezel.mesh = _get_box("vault_bezel", Vector3(2.32, 1.26, 0.32))
		crt_bezel.position = Vector3(0.0, 2.65, 0.0)
		crt_bezel.material_override = _get_mat("vault_bezel_%d" % tid, tcol, 0.2, 0.3, tcol, 1.2)
		vroot.add_child(crt_bezel)

		var lock_ring := MeshInstance3D.new()
		lock_ring.name = "LockRing"
		lock_ring.mesh = _get_torus("vault_lock", float(cfg.VAULT_RADIUS) + 0.16, float(cfg.VAULT_RADIUS) + 0.34, 24)
		lock_ring.position = Vector3(0.0, 0.72, 0.0)
		lock_ring.scale = Vector3(1.0, 0.45, 1.0)
		lock_ring.material_override = _get_mat("vault_lock_%d" % tid, Color(tcol.r, tcol.g, tcol.b, 0.75), 0.1, 0.2, tcol, 2.8, true)
		lock_ring.visible = false
		vroot.add_child(lock_ring)

		var score_lbl := Label3D.new()
		score_lbl.name = "ScoreLabel"
		score_lbl.text = "0"
		score_lbl.font_size = 78
		score_lbl.pixel_size = 0.018
		score_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		score_lbl.no_depth_test = true
		score_lbl.modulate = tcol
		score_lbl.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
		score_lbl.outline_size = 12
		if term_font != null:
			score_lbl.font = term_font
		score_lbl.position = Vector3(0.0, 2.65, 0.0)
		vroot.add_child(score_lbl)

		vault_nodes[tid] = {
			"root": vroot,
			"lock_ring": lock_ring,
			"score_label": score_lbl,
		}

	return {
		"vault_nodes": vault_nodes,
		"dispenser_ring": disp_ring,
		"dispenser_ring_b": disp_ring_b,
		"conveyor_mat_l": conv_mat_l,
		"conveyor_mat_r": conv_mat_r,
	}


func build_battery_node(cfg) -> Node3D:
	var root := Node3D.new()
	root.visible = false

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _get_cyl("bat_std", 0.24, 0.24, 0.48, 14)
	body.position = Vector3(0.0, 0.32, 0.0)
	body.material_override = _get_mat("bat_std_mat", Color(0.28, 0.88, 1.0), 0.25, 0.25, Color(0.24, 0.85, 1.0), 1.8)
	root.add_child(body)

	var cap_top := MeshInstance3D.new()
	cap_top.name = "CapTop"
	cap_top.mesh = _get_cyl("bat_cap_std", 0.27, 0.27, 0.09, 14)
	cap_top.position = Vector3(0.0, 0.56, 0.0)
	cap_top.material_override = _get_mat("bat_cap_steel", Color(0.68, 0.74, 0.82), 0.65, 0.32)
	root.add_child(cap_top)

	var cap_bot := MeshInstance3D.new()
	cap_bot.name = "CapBot"
	cap_bot.mesh = _get_cyl("bat_cap_std", 0.27, 0.27, 0.09, 14)
	cap_bot.position = Vector3(0.0, 0.08, 0.0)
	cap_bot.material_override = _get_mat("bat_cap_steel", Color(0.68, 0.74, 0.82), 0.65, 0.32)
	root.add_child(cap_bot)

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _get_torus("bat_eq_ring", 0.26, 0.33, 16)
	ring.position = Vector3(0.0, 0.34, 0.0)
	ring.scale = Vector3(1.0, 0.30, 1.0)
	ring.material_override = _get_mat("bat_ring_gold", Color(1.0, 0.78, 0.22), 0.5, 0.25, Color(1.0, 0.75, 0.15), 1.4)
	ring.visible = false
	root.add_child(ring)

	var lock_halo := MeshInstance3D.new()
	lock_halo.name = "LockHalo"
	lock_halo.mesh = _get_torus("bat_halo", 0.38, 0.46, 16)
	lock_halo.position = Vector3(0.0, 0.10, 0.0)
	lock_halo.scale = Vector3(1.0, 0.25, 1.0)
	lock_halo.material_override = _get_mat("bat_halo_mat", Color(0.45, 0.92, 1.0, 0.8), 0.1, 0.2, Color(0.45, 0.92, 1.0), 2.2, true)
	lock_halo.visible = false
	root.add_child(lock_halo)
	return root


func configure_battery_visual(node: Node3D, cell_type: int, locked: bool, perm_locked: bool, cfg) -> void:
	if node == null or not is_instance_valid(node):
		return
	var body := node.get_node_or_null("Body") as MeshInstance3D
	var cap_top := node.get_node_or_null("CapTop") as MeshInstance3D
	var cap_bot := node.get_node_or_null("CapBot") as MeshInstance3D
	var ring := node.get_node_or_null("Ring") as MeshInstance3D
	var halo := node.get_node_or_null("LockHalo") as MeshInstance3D

	if cell_type == cfg.CELL_CORE:
		if body != null:
			body.mesh = _get_cyl("bat_core", 0.38, 0.40, 0.74, 16)
			body.position = Vector3(0.0, 0.45, 0.0)
			body.material_override = _get_mat("bat_core_mat", Color(1.0, 0.38, 0.16), 0.25, 0.2, Color(1.0, 0.42, 0.14), 3.0)
		if cap_top != null:
			cap_top.mesh = _get_cyl("bat_cap_core", 0.44, 0.42, 0.13, 16)
			cap_top.position = Vector3(0.0, 0.84, 0.0)
			cap_top.material_override = _get_mat("bat_cap_dark", Color(0.24, 0.27, 0.34), 0.7, 0.35)
		if cap_bot != null:
			cap_bot.mesh = _get_cyl("bat_cap_core", 0.42, 0.44, 0.13, 16)
			cap_bot.position = Vector3(0.0, 0.09, 0.0)
			cap_bot.material_override = _get_mat("bat_cap_dark", Color(0.24, 0.27, 0.34), 0.7, 0.35)
		if ring != null:
			ring.mesh = _get_torus("bat_core_ring", 0.42, 0.52, 18)
			ring.position = Vector3(0.0, 0.46, 0.0)
			ring.material_override = _get_mat("bat_ring_core", Color(1.0, 0.56, 0.18), 0.3, 0.2, Color(1.0, 0.50, 0.14), 2.4)
			ring.visible = true
	elif cell_type == cfg.CELL_GOLD:
		if body != null:
			body.mesh = _get_cyl("bat_gold", 0.28, 0.28, 0.58, 14)
			body.position = Vector3(0.0, 0.36, 0.0)
			body.material_override = _get_mat("bat_gold_mat", Color(1.0, 0.84, 0.18), 0.45, 0.2, Color(1.0, 0.78, 0.12), 2.2)
		if cap_top != null:
			cap_top.mesh = _get_cyl("bat_cap_gold", 0.32, 0.32, 0.10, 14)
			cap_top.position = Vector3(0.0, 0.66, 0.0)
			cap_top.material_override = _get_mat("bat_cap_brass", Color(0.86, 0.68, 0.24), 0.7, 0.28)
		if cap_bot != null:
			cap_bot.mesh = _get_cyl("bat_cap_gold", 0.32, 0.32, 0.10, 14)
			cap_bot.position = Vector3(0.0, 0.08, 0.0)
			cap_bot.material_override = _get_mat("bat_cap_brass", Color(0.86, 0.68, 0.24), 0.7, 0.28)
		if ring != null:
			ring.mesh = _get_torus("bat_eq_ring", 0.29, 0.36, 16)
			ring.position = Vector3(0.0, 0.36, 0.0)
			ring.material_override = _get_mat("bat_ring_gold", Color(1.0, 0.78, 0.22), 0.5, 0.25, Color(1.0, 0.75, 0.15), 1.4)
			ring.visible = true
	else:
		if body != null:
			body.mesh = _get_cyl("bat_std", 0.24, 0.24, 0.48, 14)
			body.position = Vector3(0.0, 0.32, 0.0)
			body.material_override = _get_mat("bat_std_mat", Color(0.28, 0.88, 1.0), 0.25, 0.25, Color(0.24, 0.85, 1.0), 1.8)
		if cap_top != null:
			cap_top.mesh = _get_cyl("bat_cap_std", 0.27, 0.27, 0.09, 14)
			cap_top.position = Vector3(0.0, 0.56, 0.0)
			cap_top.material_override = _get_mat("bat_cap_steel", Color(0.68, 0.74, 0.82), 0.65, 0.32)
		if cap_bot != null:
			cap_bot.mesh = _get_cyl("bat_cap_std", 0.27, 0.27, 0.09, 14)
			cap_bot.position = Vector3(0.0, 0.08, 0.0)
			cap_bot.material_override = _get_mat("bat_cap_steel", Color(0.68, 0.74, 0.82), 0.65, 0.32)
		if ring != null:
			ring.visible = false
	if halo != null:
		halo.visible = locked or perm_locked


static func _customize_official_rig(rig: Node3D, net_id: int, team_id: int, customization: Array = []) -> void:
	var sk := rig.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if sk == null:
		return

	var char_mesh := sk.get_node_or_null("character mesh") as MeshInstance3D
	if char_mesh != null:
		var suit_path: String = str(TEAM_SUIT_TEXTURES.get(team_id, TEAM_SUIT_TEXTURES[1]))
		var suit_tex = load_optional(suit_path)
		if suit_tex is Texture2D:
			var suit_mat := StandardMaterial3D.new()
			suit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			suit_mat.albedo_texture = suit_tex as Texture2D
			suit_mat.albedo_color = Color.WHITE
			suit_mat.metallic = 0.02
			suit_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(0, suit_mat)

		var hands_tex = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2_main character hands boots.png")
		if hands_tex is Texture2D:
			var hands_mat := StandardMaterial3D.new()
			hands_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			hands_mat.albedo_texture = hands_tex as Texture2D
			hands_mat.roughness = 0.76
			hands_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(1, hands_mat)

		var eye_tex = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2_main character eye open.png")
		if eye_tex is Texture2D:
			var eye_mat := StandardMaterial3D.new()
			eye_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			eye_mat.albedo_texture = eye_tex as Texture2D
			eye_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(2, eye_mat)

	var has_custom: bool = not customization.is_empty()
	var hat_cfg = null
	if has_custom:
		var hat_name: String = str(customization[0]).strip_edges().to_lower()
		if HAT_COSMETIC_BY_NAME.has(hat_name):
			hat_cfg = HAT_COSMETICS[int(HAT_COSMETIC_BY_NAME[hat_name])]
	else:
		hat_cfg = HAT_COSMETICS[absi(net_id) % HAT_COSMETICS.size()]
	if hat_cfg is Dictionary:
		var hat_packed = load_optional(str((hat_cfg as Dictionary)["path"]))
		if hat_packed is PackedScene:
			var hat_attach := BoneAttachment3D.new()
			hat_attach.name = "ModHatAttachment"
			hat_attach.bone_name = "hat"
			hat_attach.bone_idx = sk.find_bone("hat")
			sk.add_child(hat_attach)
			var hat_inst: Node3D = (hat_packed as PackedScene).instantiate() as Node3D
			hat_inst.transform = (hat_cfg as Dictionary)["tf"] as Transform3D
			hat_attach.add_child(hat_inst)

	var gl_cfg = null
	if has_custom and customization.size() >= 2:
		var gl_name: String = str(customization[1]).strip_edges().to_lower()
		if GLASSES_COSMETIC_BY_NAME.has(gl_name):
			gl_cfg = GLASSES_COSMETICS[int(GLASSES_COSMETIC_BY_NAME[gl_name])]
	elif GLASSES_COSMETICS.has(absi(net_id) % 8):
		gl_cfg = GLASSES_COSMETICS[absi(net_id) % 8]
	if gl_cfg is Dictionary:
		var gl_packed = load_optional(str((gl_cfg as Dictionary)["path"]))
		if gl_packed is PackedScene:
			var gl_attach := BoneAttachment3D.new()
			gl_attach.name = "ModGlassesAttachment"
			gl_attach.bone_name = "head"
			gl_attach.bone_idx = sk.find_bone("head")
			sk.add_child(gl_attach)
			var gl_inst: Node3D = (gl_packed as PackedScene).instantiate() as Node3D
			gl_inst.transform = (gl_cfg as Dictionary)["tf"] as Transform3D
			gl_attach.add_child(gl_inst)


static func _load_official_shove_anim() -> Animation:
	if _shove_anim_checked:
		return _shove_anim_cache
	_shove_anim_checked = true
	var anim := Animation.new()
	anim.length = 0.34
	anim.loop_mode = Animation.LOOP_NONE
	var tracks: Array = [
		["Armature/Skeleton3D:spine", Quaternion(0.0, 0.0, 0.0, 1.0), Quaternion(0.14, 0.0, 0.0, 0.99)],
		["Armature/Skeleton3D:chest", Quaternion(0.0, 0.0, 0.0, 1.0), Quaternion(0.18, 0.0, 0.0, 0.98)],
		["Armature/Skeleton3D:shoulder.L", Quaternion(-0.45, 0.04, 0.03, 0.89), Quaternion(-0.73, 0.05, 0.04, 0.68)],
		["Armature/Skeleton3D:upper_arm.L", Quaternion(-0.25, 0.02, -0.06, 0.96), Quaternion(-0.57, 0.03, -0.10, 0.82)],
		["Armature/Skeleton3D:forearm.L", Quaternion(-0.35, 0.02, -0.10, 0.93), Quaternion(-0.08, 0.02, -0.10, 0.99)],
		["Armature/Skeleton3D:shoulder.R", Quaternion(0.45, -0.05, 0.04, 0.89), Quaternion(0.74, -0.07, 0.06, 0.66)],
		["Armature/Skeleton3D:upper_arm.R", Quaternion(0.25, -0.01, -0.05, 0.96), Quaternion(0.56, -0.01, -0.07, 0.82)],
		["Armature/Skeleton3D:forearm.R", Quaternion(0.35, 0.05, -0.10, 0.93), Quaternion(0.16, 0.06, -0.12, 0.97)],
	]
	for tr in tracks:
		var idx: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(idx, NodePath(str(tr[0])))
		var q_rest: Quaternion = (tr[1] as Quaternion).normalized()
		var q_push: Quaternion = (tr[2] as Quaternion).normalized()
		anim.rotation_track_insert_key(idx, 0.0, q_rest)
		anim.rotation_track_insert_key(idx, 0.09, q_push)
		anim.rotation_track_insert_key(idx, 0.21, q_push)
		anim.rotation_track_insert_key(idx, 0.34, q_rest)
	_shove_anim_cache = anim
	return _shove_anim_cache


static func _setup_official_animations(rig: Node3D) -> AnimationPlayer:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return null
	var lib := AnimationLibrary.new()
	var anim_idle = load_optional("res://animations/standing_idle_dynamic.res")
	var anim_shove: Animation = _load_official_shove_anim()
	var anim_shoved = load_optional("res://minigames/disco_dodge/animations/shoved_main2.res")
	if anim_shoved == null:
		anim_shoved = load_optional("res://minigames/disco_dodge/animations/shoved_main.res")

	var anim_run: Animation = null
	for raw_name in ap.get_animation_list():
		var aname: String = str(raw_name)
		if aname.to_lower() == "running" or aname.to_lower().ends_with("/running") or "run" in aname.to_lower():
			var candidate := ap.get_animation(raw_name)
			if candidate is Animation:
				anim_run = candidate
				break
	if anim_run == null:
		var fallback_run = load_optional("res://minigames/knife_at_the_office/animations/infected_running.res")
		if fallback_run is Animation:
			anim_run = fallback_run as Animation

	if anim_idle is Animation:
		var dup_idle: Animation = (anim_idle as Animation).duplicate()
		dup_idle.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"idle", dup_idle)
	if anim_run != null:
		var dup_run: Animation = anim_run.duplicate()
		dup_run.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"run", dup_run)
	if anim_shove is Animation:
		lib.add_animation(&"shove", anim_shove)
	if anim_shoved is Animation:
		lib.add_animation(&"shoved", anim_shoved as Animation)

	if not lib.get_animation_list().is_empty():
		ap.add_animation_library(&"mp_mod", lib)
		if ap.has_animation(&"mp_mod/idle"):
			ap.play(&"mp_mod/idle")
	return ap


func _build_fallback_character(rig: Node3D, team_id: int, cfg) -> void:
	var tcol: Color = (cfg.TEAM_COLORS.get(team_id, Color(0.85, 0.85, 0.9)) as Color)
	var torso := MeshInstance3D.new()
	torso.mesh = _get_cyl("p_torso", 0.30, 0.34, 0.72, 12)
	torso.position = Vector3(0.0, 0.48, 0.0)
	torso.material_override = _get_mat("p_body_%d" % team_id, tcol.lerp(Color(0.22, 0.25, 0.32), 0.45), 0.45, 0.4)
	rig.add_child(torso)

	var head := MeshInstance3D.new()
	head.mesh = _get_box("p_head", Vector3(0.42, 0.36, 0.38))
	head.position = Vector3(0.0, 1.05, 0.0)
	head.material_override = _get_mat("p_head_%d" % team_id, Color(0.86, 0.90, 0.96), 0.3, 0.35)
	rig.add_child(head)

	var visor := MeshInstance3D.new()
	visor.mesh = _get_box("p_visor", Vector3(0.32, 0.12, 0.08))
	visor.position = Vector3(0.0, 1.06, 0.20)
	visor.material_override = _get_mat("p_visor_%d" % team_id, tcol, 0.2, 0.2, tcol, 2.2)
	rig.add_child(visor)


func build_player_visual(net_id: int, nickname: String, team_id: int, customization: Array, team_helper, cfg) -> Dictionary:
	ensure_game_pck_mounted()
	var root := Node3D.new()
	root.name = "Player_%d" % net_id

	var shadow := MeshInstance3D.new()
	shadow.name = "ShadowDisc"
	shadow.mesh = _get_cyl("p_shadow", 0.46, 0.46, 0.02, 14)
	shadow.position = Vector3(0.0, 0.015, 0.0)
	shadow.material_override = _get_mat("p_shadow_mat", Color(0.0, 0.0, 0.0, 0.42), 0.0, 1.0, Color.BLACK, 0.0, true)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)

	var rig := Node3D.new()
	rig.name = "Rig"
	root.add_child(rig)

	var anim_player: AnimationPlayer = null
	var char_packed = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2.glb")
	if char_packed is PackedScene:
		var official_rig: Node3D = (char_packed as PackedScene).instantiate() as Node3D
		official_rig.name = "OfficialCharacterRig"
		official_rig.rotation_degrees.y = 180.0
		official_rig.scale = Vector3(0.42, 0.42, 0.42)
		rig.add_child(official_rig)
		_customize_official_rig(official_rig, net_id, team_id, customization)
		anim_player = _setup_official_animations(official_rig)
	else:
		_build_fallback_character(rig, team_id, cfg)

	var term_font: Font = load_terminal_font()
	var lbl := Label3D.new()
	lbl.name = "NameLabel"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 38
	lbl.pixel_size = 0.0088
	lbl.position = Vector3(0.0, 2.20, 0.0)
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.05, 0.06, 0.08, 1.0)
	if term_font != null:
		lbl.font = term_font
	lbl.text = nickname
	root.add_child(lbl)

	if team_helper != null and team_id > 0:
		team_helper.attach_foot_ring(root, team_id, 0.44, 0.56)
		team_helper.apply_nameplate(lbl, nickname, team_id, 12)

	return {
		"root": root,
		"rig": rig,
		"name_label": lbl,
		"anim_player": anim_player,
	}


func build_core_heist_icon() -> Texture2D:
	var w: int = 128
	var h: int = 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.11, 0.16, 1.0))
	for y in range(h):
		for x in range(w):
			var dx: float = float(x - 64)
			var dy: float = float(y - 64)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 52.0 and dist >= 45.0:
				img.set_pixel(x, y, Color(0.26, 0.68, 1.0, 1.0))
			elif dist < 24.0:
				img.set_pixel(x, y, Color(1.0, 0.45, 0.16, 1.0))
			elif absf(dx) < 10.0 and absf(dy) < 38.0:
				img.set_pixel(x, y, Color(1.0, 0.84, 0.22, 1.0))
	return ImageTexture.create_from_image(img)
