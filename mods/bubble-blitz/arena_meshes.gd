extends RefCounted

## Authentic Machine Party 3D asset loader and arena builders for Bubble Blitz (泡泡爆破).
## Reuses vanilla Machine Party worker rigs, cosmetics, industrial textures,
## Terminal F4 font, and CRT monitor aesthetics when Machine Party.pck is available,
## with clean procedural fallbacks for headless tests.

const PLAYER_COLORS := [
	Color(0.22, 0.58, 1.00),
	Color(0.70, 0.34, 0.98),
	Color(0.22, 0.84, 0.44),
	Color(0.96, 0.28, 0.30),
	Color(0.86, 0.89, 0.93),
	Color(1.00, 0.56, 0.14),
	Color(0.14, 0.86, 0.88),
	Color(1.00, 0.84, 0.20),
	Color(1.00, 0.36, 0.72),
	Color(0.62, 0.92, 0.24),
	Color(0.95, 0.66, 0.22),
	Color(0.20, 0.92, 0.68),
	Color(0.88, 0.20, 0.48),
	Color(0.30, 0.48, 0.98),
	Color(0.76, 0.54, 1.00),
	Color(0.84, 0.72, 0.34),
]

const SUIT_TINTS := [
	Color.WHITE,
	Color.WHITE,
	Color.WHITE,
	Color.WHITE,
	Color.WHITE,
	Color(1.0, 0.62, 0.26),
	Color(0.32, 0.92, 0.96),
	Color.WHITE,
	Color(1.0, 0.45, 0.78),
	Color(0.68, 1.0, 0.34),
	Color(1.0, 0.72, 0.30),
	Color(0.32, 0.95, 0.74),
	Color(0.95, 0.26, 0.52),
	Color(0.38, 0.58, 1.0),
	Color(0.82, 0.62, 1.0),
	Color(0.92, 0.78, 0.38),
]

const SUIT_TEXTURE_MAP := [
	"res://modules/character_customization/character_customization_textures/main character painted blue.png",
	"res://modules/character_customization/character_customization_textures/main character painted purple.png",
	"res://modules/character_customization/character_customization_textures/main character painted green.png",
	"res://modules/character_customization/character_customization_textures/main character painted red.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://modules/character_customization/character_customization_textures/main character painted yellow.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
	"res://models/intermission intro2/intermission intro2_main character2_main character white.png",
]

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

const GLASSES_COSMETICS := {
	0: {"path": "res://models/character cosmetics/cosmetic_glasses sunglasses/cosmetic_glasses sunglasses.glb", "tf": Transform3D(Basis(Vector3(-0.000494335, -0.00512526, 0.999987), Vector3(-0.0133705, 0.999898, 0.00511819), Vector3(-0.99991, -0.0133678, -0.000562828)), Vector3(0.249448, 0.222335, 6.0644e-05))},
	5: {"path": "res://models/character cosmetics/cosmetic_reading glasses/cosmetic_reading glasses.glb", "tf": Transform3D(Basis(Vector3(0.00952975, -0.0227329, 0.999696), Vector3(-0.141247, 0.989687, 0.0238517), Vector3(-0.989929, -0.141432, 0.00622053)), Vector3(0.253487, 0.231504, -0.0139316))},
}

const HAT_COSMETIC_BY_NAME := {
	"tophat": 0,
	"traffic_cone": 1,
	"rubiks_cube": 2,
	"maska_helmet": 3,
	"beer_hat": 4,
	"cap_blade": 5,
	"drill_sgt_hat": 6,
	"hard_hat": 7,
}

const GLASSES_COSMETIC_BY_NAME := {
	"sunglasses": 0,
	"reading_glasses": 5,
}

const SUIT_COLOR_VALUES := {
	"red": Color(0.96, 0.28, 0.30),
	"blue": Color(0.22, 0.58, 1.00),
	"green": Color(0.22, 0.84, 0.44),
	"yellow": Color(1.00, 0.84, 0.20),
	"purple": Color(0.70, 0.34, 0.98),
}

const TEX_THREADPLATE := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_threadplate albedo.png"
const TEX_THREADPLATE_NORMAL := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_threadplate normal 1024.png"
const TEX_SHREDDER := "res://minigames/escalator_pit/models/escalator pit art11/escalator pit art11_shredder6.png"
const TEX_HEAVY_RUST := "res://minigames/junk_platform/models/junk platform visuals2/junk platform visuals2_heavy rust2.png"
const TEX_METAL_PLATE := "res://minigames/dvd_roomba/models/dvd roomba visuals1_metal plate1.png"
const TEX_FLOOR := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba floor5.png"
const TEX_GRATE := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba grate.png"
const TEX_PIPES := "res://minigames/forklift_certified/models/forklift certified visuals1/forklift certified visuals1_fc pipes2.png"
const TEX_WALL := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba walls1.png"
const TEX_SIDING := "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba siding.png"
const TEX_CRATE_WOOD := "res://minigames/smoke_break/models/smoke break near final3/smoke break near final3_crate3.png"
const TEX_CRATE_SUPPLY := "res://minigames/forklift_certified/models/forklift certified visuals1/forklift certified visuals1_box2.png"
const TEX_BARREL := "res://minigames/chisel_gauntlet_multiplayer/models/chisel gauntlet art2/chisel gauntlet art2_barrel.jpg"
const TEX_SCORCH := "res://textures/particles/scorch_01.png"
const TEX_SMOKE := "res://textures/particles/smoke/smoke_07.png"
const TEX_EXPLOSION_MARK := "res://textures/decals/explosion_mark.png"

const GLB_SYRINGE := "res://minigames/knife_at_the_office/models/kato syringe2/kato syringe2.glb"
const GLB_SHOE := "res://models/shared/shoe_gib.glb"
const GLB_SPRING := "res://models/manufacture gun prop spring1/manufacture gun prop spring1.glb"
const GLB_DETONATOR := "res://minigames/chisel_gauntlet_multiplayer/models/exploding collar radio1/exploding collar radio1.glb"

static var _pck_checked: bool = false
static var _pck_available: bool = false


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


static func make_std_mat(
	albedo: Color,
	metallic: float = 0.15,
	roughness: float = 0.55,
	emission: Color = Color.BLACK,
	emission_energy: float = 0.0,
	transparent: bool = false,
	tex_path: String = "",
	uv_scale: Vector3 = Vector3.ONE,
	normal_path: String = ""
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if not tex_path.is_empty():
		var tex = load_optional(tex_path)
		if tex is Texture2D:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.uv1_triplanar = true
			mat.uv1_scale = uv_scale
	if not normal_path.is_empty():
		var norm = load_optional(normal_path)
		if norm is Texture2D:
			mat.normal_enabled = true
			mat.normal_texture = norm
			mat.normal_scale = 0.72
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func build_floor_and_backdrop(width: int, height: int, tile_size: float, theme_meta: Dictionary) -> Dictionary:
	ensure_game_pck_mounted()
	var root := Node3D.new()
	root.name = "ArenaFloor"

	var col_a: Color = theme_meta.get("floor_a", Color(0.56, 0.53, 0.50))
	var col_b: Color = theme_meta.get("floor_b", Color(0.44, 0.42, 0.40))
	var accent: Color = theme_meta.get("accent", Color(0.32, 0.86, 1.0))

	# Reuse vanilla Machine Party factory floor and metal grate textures with warm low-saturation industrial tone.
	var tint_a := Color(0.68, 0.64, 0.60).lerp(col_a, 0.16)
	var tint_b := Color(0.50, 0.48, 0.46).lerp(col_b, 0.16)
	var mat_a := make_std_mat(tint_a, 0.22, 0.78, Color.BLACK, 0.0, false, TEX_FLOOR, Vector3(0.35, 0.35, 0.35))
	var mat_b := make_std_mat(tint_b, 0.30, 0.70, Color.BLACK, 0.0, false, TEX_GRATE, Vector3(0.42, 0.42, 0.42))
	var mat_frame := make_std_mat(Color(0.24, 0.22, 0.21), 0.60, 0.65, Color.BLACK, 0.0, false, TEX_SIDING, Vector3(0.25, 0.25, 0.25))
	var mat_wall := make_std_mat(Color(0.40, 0.30, 0.24), 0.32, 0.80, Color.BLACK, 0.0, false, TEX_HEAVY_RUST, Vector3(0.18, 0.18, 0.18))
	var mat_pipe := make_std_mat(Color(0.44, 0.40, 0.36), 0.72, 0.44, Color.BLACK, 0.0, false, TEX_PIPES, Vector3(0.4, 0.4, 0.4))
	var mat_trim := make_std_mat(Color(0.14, 0.14, 0.15), 0.72, 0.50, Color.BLACK, 0.0, false, TEX_METAL_PLATE, Vector3(0.4, 0.4, 0.4))

	var total_w: float = float(width) * tile_size
	var total_h: float = float(height) * tile_size

	# Heavy dark charcoal industrial sub-deck (eliminates bright neon seams between floor tiles).
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(total_w + 2.8, 0.9, total_h + 2.8)
	deck.mesh = deck_mesh
	deck.material_override = mat_frame
	deck.position = Vector3(0.0, -0.49, 0.0)
	root.add_child(deck)

	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(total_w + 0.32, 0.09, total_h + 0.32)
	rim.mesh = rim_mesh
	rim.material_override = mat_trim
	rim.position = Vector3(0.0, -0.05, 0.0)
	root.add_child(rim)

	# Checkerboard factory floor tiles using two MultiMeshInstance3D batches.
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(tile_size * 0.995, 0.08, tile_size * 0.995)
	var transforms_a: Array[Transform3D] = []
	var transforms_b: Array[Transform3D] = []
	var ox: float = (float(width) - 1.0) * 0.5
	var oz: float = (float(height) - 1.0) * 0.5

	for y in range(height):
		for x in range(width):
			var pos := Vector3((float(x) - ox) * tile_size, -0.04, (float(y) - oz) * tile_size)
			var t := Transform3D(Basis.IDENTITY, pos)
			if (x + y) % 2 == 0:
				transforms_a.append(t)
			else:
				transforms_b.append(t)

	for pair in [[transforms_a, mat_a, "TilesA"], [transforms_b, mat_b, "TilesB"]]:
		var arr: Array[Transform3D] = pair[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tile_mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = str(pair[2])
		mmi.multimesh = mm
		mmi.material_override = pair[1]
		root.add_child(mmi)

	# --- Industrial Factory Back Wall + Pipes + Fluorescent Tubes + 3D CRT Monitor ---
	var back_z: float = -total_h * 0.5 - 1.35
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(total_w + 14.0, 6.2, 0.7)
	wall.mesh = wm
	wall.material_override = mat_wall
	wall.position = Vector3(0.0, 2.4, back_z)
	root.add_child(wall)

	for py in [1.1, 3.6]:
		var pipe := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.14
		pm.bottom_radius = 0.14
		pm.height = total_w + 12.0
		pipe.mesh = pm
		pipe.material_override = mat_pipe
		pipe.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		pipe.position = Vector3(0.0, py, back_z + 0.48)
		root.add_child(pipe)

	# Warm industrial fluorescent wall tubes.
	var tube_mat := make_std_mat(Color(0.95, 0.94, 0.82), 0.1, 0.2, Color(0.96, 0.92, 0.76), 1.8)
	var fixture_mat := make_std_mat(Color(0.22, 0.22, 0.24), 0.7, 0.45)
	for lx in [-total_w * 0.38, -total_w * 0.18, total_w * 0.18, total_w * 0.38]:
		var fix := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(1.45, 0.22, 0.30)
		fix.mesh = fm
		fix.material_override = fixture_mat
		fix.position = Vector3(lx, 2.85, back_z + 0.46)
		root.add_child(fix)

		var tube := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(1.25, 0.10, 0.14)
		tube.mesh = tm
		tube.material_override = tube_mat
		tube.position = Vector3(lx, 2.74, back_z + 0.56)
		root.add_child(tube)

	# 3D CRT Countdown & Theme Monitor mounted on back wall (authentic Machine Party style).
	var crt_root := Node3D.new()
	crt_root.name = "BackWallCRT"
	crt_root.position = Vector3(0.0, 2.15, back_z + 0.62)
	crt_root.rotation_degrees = Vector3(24.0, 0.0, 0.0)
	root.add_child(crt_root)

	var casing := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(4.6, 2.1, 0.65)
	casing.mesh = cm
	casing.material_override = make_std_mat(Color(0.10, 0.11, 0.12), 0.6, 0.5, Color.BLACK, 0.0, false, TEX_METAL_PLATE, Vector3(0.4, 0.4, 0.4))
	crt_root.add_child(casing)

	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(4.15, 1.65, 0.06)
	screen.mesh = sm
	screen.material_override = make_std_mat(Color(0.02, 0.05, 0.03), 0.1, 0.2, Color(0.03, 0.10, 0.05), 0.65)
	screen.position = Vector3(0.0, 0.0, 0.34)
	crt_root.add_child(screen)

	var term_font: Font = load_terminal_font()
	var monitor_timer := Label3D.new()
	monitor_timer.name = "MonitorTimer"
	monitor_timer.text = "01:15"
	monitor_timer.font_size = 136
	monitor_timer.pixel_size = 0.0072
	monitor_timer.modulate = Color(0.68, 1.0, 0.68)
	monitor_timer.outline_modulate = Color(0.04, 0.18, 0.06)
	monitor_timer.outline_size = 10
	if term_font != null:
		monitor_timer.font = term_font
	monitor_timer.position = Vector3(0.0, 0.22, 0.39)
	crt_root.add_child(monitor_timer)

	var monitor_theme := Label3D.new()
	monitor_theme.name = "MonitorTheme"
	monitor_theme.text = "BUBBLE BLITZ"
	monitor_theme.font_size = 46
	monitor_theme.pixel_size = 0.0068
	monitor_theme.modulate = Color(0.64, 0.96, 0.68)
	monitor_theme.outline_modulate = Color.BLACK
	monitor_theme.outline_size = 8
	if term_font != null:
		monitor_theme.font = term_font
	monitor_theme.position = Vector3(0.0, -0.46, 0.39)
	crt_root.add_child(monitor_theme)

	return {
		"root": root,
		"monitor_timer": monitor_timer,
		"monitor_theme": monitor_theme,
	}


static func build_steel_pillar(tile_size: float, accent: Color) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tile_size * 0.94, tile_size * 0.88, tile_size * 0.94)
	body.mesh = bm
	body.material_override = make_std_mat(
		Color(0.56, 0.58, 0.60),
		0.72,
		0.48,
		Color.BLACK,
		0.0,
		false,
		TEX_THREADPLATE,
		Vector3(0.65, 0.65, 0.65),
		TEX_THREADPLATE_NORMAL
	)
	body.position = Vector3(0.0, tile_size * 0.44, 0.0)
	n.add_child(body)

	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(tile_size * 0.74, tile_size * 0.14, tile_size * 0.74)
	cap.mesh = cm
	cap.material_override = make_std_mat(
		Color(0.46, 0.44, 0.42),
		0.80,
		0.36,
		accent * 0.18,
		0.22,
		false,
		TEX_METAL_PLATE,
		Vector3(0.7, 0.7, 0.7)
	)
	cap.position = Vector3(0.0, tile_size * 0.91, 0.0)
	n.add_child(cap)
	return n


static func build_crate(tile_size: float, is_gold: bool, base_color: Color) -> Node3D:
	var n := Node3D.new()
	var main_col: Color = Color(1.0, 0.84, 0.34) if is_gold else base_color.lerp(Color(0.92, 0.86, 0.78), 0.65)
	var em_col: Color = Color(0.95, 0.68, 0.12) if is_gold else Color.BLACK
	var em_e: float = 0.32 if is_gold else 0.0
	var tex_path: String = TEX_CRATE_SUPPLY if is_gold else TEX_CRATE_WOOD

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tile_size * 0.88, tile_size * 0.80, tile_size * 0.88)
	body.mesh = bm
	body.material_override = make_std_mat(
		main_col,
		0.45 if is_gold else 0.14,
		0.42 if is_gold else 0.78,
		em_col,
		em_e,
		false,
		tex_path,
		Vector3(0.82, 0.82, 0.82)
	)
	body.position = Vector3(0.0, tile_size * 0.40, 0.0)
	n.add_child(body)

	var brace_mat := make_std_mat(
		Color(0.60, 0.44, 0.14) if is_gold else Color(0.28, 0.24, 0.20),
		0.62,
		0.48,
		Color.BLACK,
		0.0,
		false,
		TEX_METAL_PLATE,
		Vector3(0.9, 0.9, 0.9)
	)
	var b1 := MeshInstance3D.new()
	var bm1 := BoxMesh.new()
	bm1.size = Vector3(tile_size * 0.90, tile_size * 0.09, tile_size * 0.16)
	b1.mesh = bm1
	b1.material_override = brace_mat
	b1.position = Vector3(0.0, tile_size * 0.80, 0.0)
	n.add_child(b1)

	var b2 := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(tile_size * 0.16, tile_size * 0.09, tile_size * 0.90)
	b2.mesh = bm2
	b2.material_override = brace_mat
	b2.position = Vector3(0.0, tile_size * 0.80, 0.0)
	n.add_child(b2)
	return n


static func build_conveyor_tile(tile_size: float, dir: Vector2i, accent: Color) -> Node3D:
	var n := Node3D.new()
	var belt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tile_size * 0.94, 0.06, tile_size * 0.94)
	belt.mesh = bm
	belt.material_override = make_std_mat(
		Color(0.30, 0.32, 0.34),
		0.45,
		0.72,
		Color.BLACK,
		0.0,
		false,
		TEX_SHREDDER,
		Vector3(0.8, 0.8, 0.8)
	)
	belt.position = Vector3(0.0, 0.03, 0.0)
	n.add_child(belt)

	# Industrial stencil hazard chevron painted on conveyor belt (low-saturation ochre, no neon).
	var arrow := MeshInstance3D.new()
	var am := PrismMesh.new()
	am.size = Vector3(tile_size * 0.38, tile_size * 0.40, 0.03)
	arrow.mesh = am
	var arrow_col := Color(0.76, 0.56, 0.16)
	arrow.material_override = make_std_mat(arrow_col, 0.15, 0.62, arrow_col, 0.18)
	arrow.position = Vector3(0.0, 0.072, 0.0)
	arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var yaw: float = 0.0
	if dir == Vector2i(1, 0):
		yaw = -90.0
	elif dir == Vector2i(-1, 0):
		yaw = 90.0
	elif dir == Vector2i(0, 1):
		yaw = 180.0
	elif dir == Vector2i(0, -1):
		yaw = 0.0
	n.rotation_degrees = Vector3(0.0, yaw, 0.0)
	n.add_child(arrow)
	return n


static func build_crusher_block(tile_size: float) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tile_size * 0.95, tile_size * 1.12, tile_size * 0.95)
	body.mesh = bm
	body.material_override = make_std_mat(
		Color(0.36, 0.32, 0.30),
		0.78,
		0.42,
		Color.BLACK,
		0.0,
		false,
		TEX_SHREDDER,
		Vector3(0.7, 0.7, 0.7)
	)
	body.position = Vector3(0.0, tile_size * 0.56, 0.0)
	n.add_child(body)

	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(tile_size * 0.98, tile_size * 0.22, tile_size * 0.98)
	stripe.mesh = sm
	stripe.material_override = make_std_mat(Color(0.96, 0.70, 0.10), 0.3, 0.45, Color(0.96, 0.50, 0.06), 0.65)
	stripe.position = Vector3(0.0, tile_size * 0.96, 0.0)
	n.add_child(stripe)
	return n


static func _collect_aabb(node: Node, parent_xform: Transform3D) -> AABB:
	var combined := AABB()
	var has_box := false
	var cur_xform: Transform3D = parent_xform
	if node is Node3D:
		cur_xform = parent_xform * (node as Node3D).transform
	if node is VisualInstance3D:
		var local_box: AABB = (node as VisualInstance3D).get_aabb()
		if local_box.size.length_squared() > 0.00001:
			var world_box: AABB = cur_xform * local_box
			combined = world_box if not has_box else combined.merge(world_box)
			has_box = true
	for child in node.get_children():
		var sub: AABB = _collect_aabb(child, cur_xform)
		if sub.size.length_squared() > 0.00001:
			combined = sub if not has_box else combined.merge(sub)
			has_box = true
	return combined


static func _attach_normalized_glb(parent: Node3D, glb_path: String, target_extent: float, base_y: float, tilt_deg: Vector3 = Vector3.ZERO) -> bool:
	var packed = load_optional(glb_path)
	if not (packed is PackedScene):
		return false
	var inst = (packed as PackedScene).instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	var holder := Node3D.new()
	holder.position = Vector3(0.0, base_y, 0.0)
	holder.rotation_degrees = tilt_deg
	var model: Node3D = inst
	var box: AABB = _collect_aabb(model, Transform3D.IDENTITY)
	var max_dim: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if max_dim > 0.001:
		var s: float = target_extent / max_dim
		model.scale = Vector3.ONE * s
		var center: Vector3 = box.position + box.size * 0.5
		model.position = -center * s
	holder.add_child(model)
	parent.add_child(holder)
	return true


static func build_water_bubble(tile_size: float, _owner_color: Color) -> Node3D:
	## Authentic Machine Party industrial explosive canister (dark iron + hazard rust barrel + red detonator LED).
	var n := Node3D.new()

	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = tile_size * 0.34
	bm.bottom_radius = tile_size * 0.38
	bm.height = tile_size * 0.14
	base.mesh = bm
	base.material_override = make_std_mat(Color(0.24, 0.24, 0.26), 0.82, 0.42, Color.BLACK, 0.0, false, TEX_METAL_PLATE, Vector3(1.2, 1.2, 1.2))
	base.position = Vector3(0.0, tile_size * 0.07, 0.0)
	n.add_child(base)

	var canister := MeshInstance3D.new()
	canister.name = "CanisterBody"
	var cm := CylinderMesh.new()
	cm.top_radius = tile_size * 0.29
	cm.bottom_radius = tile_size * 0.31
	cm.height = tile_size * 0.52
	canister.mesh = cm
	canister.material_override = make_std_mat(Color(0.68, 0.22, 0.16), 0.48, 0.54, Color.BLACK, 0.0, false, TEX_BARREL, Vector3(0.9, 0.9, 0.9))
	canister.position = Vector3(0.0, tile_size * 0.38, 0.0)
	n.add_child(canister)

	# Hazard dark-amber steel clamp band (unified industrial palette, no bright neon).
	var band := MeshInstance3D.new()
	var bnd_m := CylinderMesh.new()
	bnd_m.top_radius = tile_size * 0.315
	bnd_m.bottom_radius = tile_size * 0.315
	bnd_m.height = tile_size * 0.10
	band.mesh = bnd_m
	band.material_override = make_std_mat(Color(0.66, 0.46, 0.14), 0.55, 0.46, Color(0.45, 0.26, 0.05), 0.25, false, TEX_METAL_PLATE)
	band.position = Vector3(0.0, tile_size * 0.38, 0.0)
	n.add_child(band)

	var cap := MeshInstance3D.new()
	var cap_m := CylinderMesh.new()
	cap_m.top_radius = tile_size * 0.18
	cap_m.bottom_radius = tile_size * 0.24
	cap_m.height = tile_size * 0.12
	cap.mesh = cap_m
	cap.material_override = make_std_mat(Color(0.22, 0.22, 0.24), 0.85, 0.36, Color.BLACK, 0.0, false, TEX_THREADPLATE)
	cap.position = Vector3(0.0, tile_size * 0.68, 0.0)
	n.add_child(cap)

	var beacon := MeshInstance3D.new()
	beacon.name = "FuseBeacon"
	var sm := SphereMesh.new()
	sm.radius = tile_size * 0.10
	sm.height = tile_size * 0.20
	beacon.mesh = sm
	beacon.material_override = make_std_mat(Color(0.95, 0.20, 0.10), 0.1, 0.2, Color(1.0, 0.18, 0.08), 2.2)
	beacon.position = Vector3(0.0, tile_size * 0.79, 0.0)
	n.add_child(beacon)
	return n


static func build_blast_cell(tile_size: float, is_center: bool) -> Node3D:
	## Gritty vanilla scorch + fiery smoke cloud indicator (replaces blocky orange cubes).
	var n := Node3D.new()

	# Ground scorch / ember ring using vanilla scorch_01.png.
	var ground_quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(tile_size * (1.28 if is_center else 1.06), tile_size * (1.28 if is_center else 1.06))
	ground_quad.mesh = qm
	ground_quad.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ground_quad.position = Vector3(0.0, 0.06, 0.0)
	var scorch_mat := StandardMaterial3D.new()
	scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scorch_mat.albedo_color = Color(1.0, 0.44, 0.12, 0.85 if is_center else 0.70)
	var scorch_tex = load_optional(TEX_SCORCH)
	if scorch_tex is Texture2D:
		scorch_mat.albedo_texture = scorch_tex
	ground_quad.material_override = scorch_mat
	n.add_child(ground_quad)

	# Billboard smoke/fire puff using vanilla smoke_07.png (no solid cubes or spheres).
	var puff := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(tile_size * (1.20 if is_center else 0.92), tile_size * (1.20 if is_center else 0.92))
	puff.mesh = pm
	puff.position = Vector3(0.0, tile_size * (0.46 if is_center else 0.34), 0.0)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_mat.albedo_color = Color(1.0, 0.56, 0.22, 0.72 if is_center else 0.58)
	var smoke_tex = load_optional(TEX_SMOKE)
	if smoke_tex is Texture2D:
		puff_mat.albedo_texture = smoke_tex
	puff.material_override = puff_mat
	n.add_child(puff)

	if is_center:
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.55, 0.20)
		flash.light_energy = 4.5
		flash.omni_range = tile_size * 3.2
		flash.position = Vector3(0.0, 0.65, 0.0)
		n.add_child(flash)

	return n


static func _pickup_short_label(item_type: int) -> String:
	var loc: String = TranslationServer.get_locale().to_upper()
	var is_zhs: bool = loc.begins_with("ZHS")
	var is_zh: bool = loc.begins_with("ZH")
	if item_type == 1:
		return "炸弹+1" if is_zhs else ("炸彈+1" if is_zh else "BOMB+")
	if item_type == 2:
		return "范围+1" if is_zhs else ("範圍+1" if is_zh else "RANGE+")
	if item_type == 3:
		return "移速+" if is_zhs else ("移速+" if is_zh else "SPEED+")
	if item_type == 4:
		return "踢弹" if is_zhs else ("踢彈" if is_zh else "KICK")
	return "救命针" if is_zhs else ("救命針" if is_zh else "NEEDLE")


static func build_powerup_node(tile_size: float, item_type: int) -> Node3D:
	## Authentic Machine Party 3D industrial pickups on unified dark-steel supply pads (no rainbow neon).
	var n := Node3D.new()
	var spin_root := Node3D.new()
	spin_root.name = "SpinMesh"
	spin_root.position = Vector3(0.0, tile_size * 0.44, 0.0)
	n.add_child(spin_root)

	var attached := false
	if item_type == 1: # BOMB+ (mini industrial explosive canister)
		var mini := build_water_bubble(tile_size * 0.54, Color.WHITE)
		mini.position = Vector3(0.0, -tile_size * 0.22, 0.0)
		spin_root.add_child(mini)
		attached = true
	elif item_type == 2: # POWER+ (vanilla exploding collar radio detonator)
		attached = _attach_normalized_glb(spin_root, GLB_DETONATOR, tile_size * 0.62, 0.0, Vector3(12.0, 0.0, 14.0))
	elif item_type == 3: # SPEED+ (vanilla industrial spring)
		attached = _attach_normalized_glb(spin_root, GLB_SPRING, tile_size * 0.58, 0.0, Vector3(22.0, 0.0, 18.0))
	elif item_type == 4: # KICK (vanilla heavy work boot)
		attached = _attach_normalized_glb(spin_root, GLB_SHOE, tile_size * 0.64, 0.0, Vector3(10.0, 0.0, -14.0))
	else: # NEEDLE (vanilla glowing kato syringe)
		attached = _attach_normalized_glb(spin_root, GLB_SYRINGE, tile_size * 0.72, 0.0, Vector3(28.0, 0.0, 32.0))

	if not attached:
		var fallback := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3.ONE * (tile_size * 0.36)
		fallback.mesh = fm
		fallback.material_override = make_std_mat(Color(0.76, 0.60, 0.24), 0.4, 0.4, Color(0.76, 0.55, 0.16), 0.5)
		spin_root.add_child(fallback)

	# Unified dark industrial steel supply pad with subtle warm-amber rim (consistent with Machine Party).
	var pad := MeshInstance3D.new()
	var pm2 := CylinderMesh.new()
	pm2.top_radius = tile_size * 0.30
	pm2.bottom_radius = tile_size * 0.34
	pm2.height = 0.07
	pad.mesh = pm2
	pad.material_override = make_std_mat(Color(0.22, 0.22, 0.24), 0.78, 0.46, Color.BLACK, 0.0, false, TEX_METAL_PLATE)
	pad.position = Vector3(0.0, 0.035, 0.0)
	n.add_child(pad)

	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = tile_size * 0.315
	rm.bottom_radius = tile_size * 0.315
	rm.height = 0.025
	ring.mesh = rm
	ring.material_override = make_std_mat(Color(0.86, 0.68, 0.26, 0.62), 0.2, 0.35, Color(0.82, 0.58, 0.16), 0.65, true)
	ring.position = Vector3(0.0, 0.075, 0.0)
	n.add_child(ring)

	# Clean Terminal F4 tag above each pickup so players know what it does at a glance.
	var tag := Label3D.new()
	tag.name = "PickupTag"
	tag.text = _pickup_short_label(item_type)
	tag.font_size = 28
	tag.pixel_size = 0.0064
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color(0.96, 0.90, 0.68)
	tag.outline_modulate = Color.BLACK
	tag.outline_size = 9
	var term_font: Font = load_terminal_font()
	if term_font != null:
		tag.font = term_font
	tag.position = Vector3(0.0, tile_size * 0.86, 0.0)
	n.add_child(tag)
	return n


static func build_trap_bubble_shell() -> Node3D:
	## Authentic Machine Party "CRITICAL / LOCKDOWN" hazard ring instead of a cartoon blue soap bubble.
	## Signals the 4-second downed state where rivals can bump-execute or Needle can auto-revive.
	var root := Node3D.new()
	root.name = "TrapBubble"
	root.visible = false

	var outer_ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.52
	tm.outer_radius = 0.66
	outer_ring.mesh = tm
	outer_ring.material_override = make_std_mat(
		Color(0.94, 0.18, 0.12, 0.85),
		0.2,
		0.3,
		Color(1.0, 0.16, 0.10),
		1.8,
		true
	)
	outer_ring.position = Vector3(0.0, 0.08, 0.0)
	root.add_child(outer_ring)

	var inner_disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.52
	dm.bottom_radius = 0.52
	dm.height = 0.02
	inner_disc.mesh = dm
	inner_disc.material_override = make_std_mat(
		Color(0.86, 0.12, 0.08, 0.24),
		0.0,
		0.5,
		Color(0.92, 0.14, 0.08),
		0.7,
		true
	)
	inner_disc.position = Vector3(0.0, 0.04, 0.0)
	root.add_child(inner_disc)

	var alarm_light := OmniLight3D.new()
	alarm_light.light_color = Color(1.0, 0.18, 0.12)
	alarm_light.light_energy = 2.6
	alarm_light.omni_range = 2.6
	alarm_light.position = Vector3(0.0, 0.75, 0.0)
	root.add_child(alarm_light)

	return root


static func _resolve_player_color(idx: int, customization: Array) -> Color:
	if customization.size() >= 3:
		var suit_name: String = str(customization[2]).strip_edges().to_lower()
		if SUIT_COLOR_VALUES.has(suit_name):
			return SUIT_COLOR_VALUES[suit_name]
	return PLAYER_COLORS[idx % PLAYER_COLORS.size()]


static func build_worker_character(idx: int, net_id: int, nickname: String, customization: Array, is_local: bool) -> Dictionary:
	ensure_game_pck_mounted()
	var col: Color = _resolve_player_color(idx, customization)
	var root := Node3D.new()
	root.name = "Player_%d" % net_id

	# Ground drop shadow disc.
	var shadow := MeshInstance3D.new()
	shadow.name = "GroundShadow"
	var sh_m := CylinderMesh.new()
	sh_m.top_radius = 0.40
	sh_m.bottom_radius = 0.40
	sh_m.height = 0.02
	shadow.mesh = sh_m
	shadow.material_override = make_std_mat(Color(0.03, 0.02, 0.04, 0.7), 0.0, 0.9, Color.BLACK, 0.0, true)
	shadow.position = Vector3(0.0, 0.025, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)

	if is_local:
		root.add_to_group(&"mpm_local_player")
		root.set_meta(&"mpm_local_player", true)
		root.set_meta(&"mpm_alive", true)

	var avatar := Node3D.new()
	avatar.name = "Avatar"
	root.add_child(avatar)

	var anim_player: AnimationPlayer = null
	var char_packed = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2.glb")
	if char_packed is PackedScene:
		var rig: Node3D = (char_packed as PackedScene).instantiate()
		rig.name = "OfficialCharacterRig"
		# main character2.glb Armature faces local -Z; rotate 180 deg so local +Z aligns with atan2(fx, fz).
		rig.rotation_degrees.y = 180.0
		rig.scale = Vector3(0.28, 0.28, 0.28)
		avatar.add_child(rig)
		_customize_official_rig(rig, idx, customization)
		anim_player = _setup_official_animations(rig)
	else:
		_build_fallback_character(avatar, col)

	var trap_shell: Node3D = build_trap_bubble_shell()
	root.add_child(trap_shell)

	var term_font: Font = load_terminal_font()
	var formatted_name: String = nickname.left(11) + "-" if nickname.length() > 11 else nickname
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = formatted_name
	label.font_size = 36
	label.pixel_size = 0.0076
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.outline_size = 12
	if term_font != null:
		label.font = term_font
	label.position = Vector3(0.0, 1.98, 0.0)
	root.add_child(label)

	var hp_label := Label3D.new()
	hp_label.name = "HpBar"
	hp_label.text = "■■■"
	hp_label.font_size = 32
	hp_label.pixel_size = 0.0072
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.modulate = Color(0.98, 0.34, 0.28)
	hp_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	hp_label.outline_size = 10
	if term_font != null:
		hp_label.font = term_font
	hp_label.position = Vector3(0.0, 1.66, 0.0)
	root.add_child(hp_label)

	return {
		"root": root,
		"avatar": avatar,
		"color": col,
		"anim_player": anim_player,
	}


static func _customize_official_rig(rig: Node3D, idx: int, customization: Array = []) -> void:
	var sk := rig.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if sk == null:
		return

	var has_custom: bool = not customization.is_empty()
	var char_mesh := sk.get_node_or_null("character mesh") as MeshInstance3D
	if char_mesh != null:
		var suit_tex = null
		var suit_tint := Color.WHITE
		if has_custom and customization.size() >= 3:
			var suit_name: String = str(customization[2]).strip_edges().to_lower()
			if SUIT_COLOR_VALUES.has(suit_name):
				suit_tex = load_optional("res://modules/character_customization/character_customization_textures/main character painted %s.png" % suit_name)
		if suit_tex == null:
			suit_tex = load_optional(SUIT_TEXTURE_MAP[idx % SUIT_TEXTURE_MAP.size()])
			suit_tint = SUIT_TINTS[idx % SUIT_TINTS.size()]
		if suit_tex is Texture2D:
			var suit_mat := StandardMaterial3D.new()
			suit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			suit_mat.albedo_texture = suit_tex
			suit_mat.albedo_color = suit_tint
			suit_mat.metallic = 0.02
			suit_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(0, suit_mat)

		var hands_tex = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2_main character hands boots.png")
		if hands_tex is Texture2D:
			var hands_mat := StandardMaterial3D.new()
			hands_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			hands_mat.albedo_texture = hands_tex
			hands_mat.roughness = 0.76
			hands_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(1, hands_mat)

		var eye_tex = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2_main character eye open.png")
		if eye_tex is Texture2D:
			var eye_mat := StandardMaterial3D.new()
			eye_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			eye_mat.albedo_texture = eye_tex
			eye_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			char_mesh.set_surface_override_material(2, eye_mat)

	var hat_cfg = null
	if has_custom:
		var hat_name: String = str(customization[0]).strip_edges().to_lower()
		if HAT_COSMETIC_BY_NAME.has(hat_name):
			hat_cfg = HAT_COSMETICS[int(HAT_COSMETIC_BY_NAME[hat_name])]
	else:
		hat_cfg = HAT_COSMETICS[idx % HAT_COSMETICS.size()]
	if hat_cfg is Dictionary:
		var hat_packed = load_optional(str(hat_cfg["path"]))
		if hat_packed is PackedScene:
			var hat_attach := BoneAttachment3D.new()
			hat_attach.name = "ModHatAttachment"
			hat_attach.bone_name = "hat"
			hat_attach.bone_idx = sk.find_bone("hat")
			sk.add_child(hat_attach)
			var hat_inst: Node3D = (hat_packed as PackedScene).instantiate()
			hat_inst.transform = hat_cfg["tf"]
			hat_attach.add_child(hat_inst)

	var gl_cfg = null
	if has_custom and customization.size() >= 2:
		var gl_name: String = str(customization[1]).strip_edges().to_lower()
		if GLASSES_COSMETIC_BY_NAME.has(gl_name):
			gl_cfg = GLASSES_COSMETICS[int(GLASSES_COSMETIC_BY_NAME[gl_name])]
	elif GLASSES_COSMETICS.has(idx):
		gl_cfg = GLASSES_COSMETICS[idx]
	if gl_cfg is Dictionary:
		var gl_packed = load_optional(str(gl_cfg["path"]))
		if gl_packed is PackedScene:
			var gl_attach := BoneAttachment3D.new()
			gl_attach.name = "ModGlassesAttachment"
			gl_attach.bone_name = "head"
			gl_attach.bone_idx = sk.find_bone("head")
			sk.add_child(gl_attach)
			var gl_inst: Node3D = (gl_packed as PackedScene).instantiate()
			gl_inst.transform = gl_cfg["tf"]
			gl_attach.add_child(gl_inst)


static func _setup_official_animations(rig: Node3D) -> AnimationPlayer:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return null

	var lib := AnimationLibrary.new()
	var anim_idle = load_optional("res://animations/standing_idle_dynamic.res")
	var anim_shove = load_optional("res://minigames/disco_dodge/animations/shoved_main.res")
	var anim_crawl = load_optional("res://animations/crawl_overwrite.res")
	var anim_fall = load_optional("res://minigames/disco_dodge/animations/falling.res")

	# Reuse vanilla built-in "running" animation from main character2.glb (fallback to infected_running.res).
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
		lib.add_animation(&"shoved", anim_shove as Animation)
	var downed_src = anim_crawl if anim_crawl is Animation else anim_fall
	if downed_src is Animation:
		var dup_downed: Animation = (downed_src as Animation).duplicate()
		dup_downed.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"falling", dup_downed)

	if not lib.get_animation_list().is_empty():
		ap.add_animation_library(&"mp_mod", lib)
		if ap.has_animation(&"mp_mod/idle"):
			ap.play(&"mp_mod/idle")
	return ap


static func _build_fallback_character(parent: Node3D, suit_color: Color) -> void:
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.28
	bm.height = 0.96
	body.mesh = bm
	body.material_override = make_std_mat(suit_color, 0.2, 0.52)
	body.position = Vector3(0.0, 0.52, 0.0)
	parent.add_child(body)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.24
	hm.height = 0.48
	head.mesh = hm
	head.material_override = make_std_mat(Color(0.92, 0.86, 0.78), 0.1, 0.55)
	head.position = Vector3(0.0, 1.12, 0.0)
	parent.add_child(head)


static func build_bubble_icon() -> ImageTexture:
	var size: int = 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.11, 0.16, 1.0))

	var center := Vector2(64.0, 66.0)
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x), float(y))
			var d: float = p.distance_to(center)
			if x < 5 or y < 5 or x >= size - 5 or y >= size - 5:
				img.set_pixel(x, y, Color(0.24, 0.84, 1.0, 1.0))
				continue
			if (absf(p.x - center.x) < 12.0 and absf(p.y - center.y) < 52.0) or (absf(p.y - center.y) < 12.0 and absf(p.x - center.x) < 52.0):
				img.set_pixel(x, y, Color(0.18, 0.68, 0.94, 1.0))
			if d < 34.0:
				var rim: float = clampf(d / 34.0, 0.0, 1.0)
				var col := Color(0.32, 0.88, 1.0, 1.0).lerp(Color(0.10, 0.42, 0.86, 1.0), rim * 0.72)
				if d > 29.0:
					col = Color(0.84, 0.98, 1.0, 1.0)
				img.set_pixel(x, y, col)
			if p.distance_to(Vector2(50.0, 50.0)) < 8.5:
				img.set_pixel(x, y, Color(0.95, 1.0, 1.0, 1.0))
			if absf(p.x - center.x) < 10.0 and y >= 22 and y <= 33:
				img.set_pixel(x, y, Color(0.96, 0.74, 0.18, 1.0))

	return ImageTexture.create_from_image(img)
