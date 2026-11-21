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


static func build_worker_character(idx: int, net_id: int, nickname: String, customization: Array, is_local: bool, visual_scale: float = 0.90, label_y: float = 2.20) -> Dictionary:
	ensure_game_pck_mounted()
	var col: Color = _resolve_player_color(idx, customization)
	var root := Node3D.new()
	root.name = "Player_%d" % net_id

	# Ground drop shadow disc.
	var shadow := MeshInstance3D.new()
	shadow.name = "GroundShadow"
	var sh_m := CylinderMesh.new()
	var shadow_r: float = 0.40 * maxf(0.5, visual_scale / 0.28)
	sh_m.top_radius = shadow_r
	sh_m.bottom_radius = shadow_r
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
		rig.scale = Vector3(visual_scale, visual_scale, visual_scale)
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
	label.position = Vector3(0.0, label_y, 0.0)
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
	hp_label.position = Vector3(0.0, label_y - 0.34, 0.0)
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
	## Authentic Machine Party 256x256 monochrome (#000 / #e5e5e5) CRT silhouette icon
	## matching stock minigames and Roller Carnival in Custom Playlist & Intermission Picker.
	var image := Image.new()
	image.load_svg_from_string("""
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
	  <rect width="256" height="256" fill="#000"/>
	  <g fill="#e5e5e5">
	    <!-- Cross blast rays behind bomb -->
	    <path d="M118 14h20l-4 42h-12zM118 200h20l-4 42h-12zM14 118l42 4v12l-42 4zM200 122l42-4v20l-42-4z"/>
	    <!-- Diagonal sparks -->
	    <path d="M48 48l28 20-8 8-20-28zM208 48l-20 28-8-8 28-20zM48 208l20-28 8 8-28 20zM208 208l-28-20 8-8 20 28z"/>
	    <!-- Industrial pressure bomb canister -->
	    <circle cx="128" cy="140" r="56" stroke="#000" stroke-width="10"/>
	    <rect x="104" y="68" width="48" height="22" rx="6" stroke="#000" stroke-width="8"/>
	    <!-- Hazard band cutouts -->
	    <rect x="74" y="132" width="108" height="16" fill="#000"/>
	    <rect x="82" y="136" width="92" height="8" fill="#e5e5e5"/>
	    <!-- Lit fuse & spark star -->
	    <path d="M128 68c0-18 16-24 28-28" fill="none" stroke="#e5e5e5" stroke-width="10" stroke-linecap="round"/>
	    <polygon points="168,20 174,34 190,34 177,43 182,58 168,49 154,58 159,43 146,34 162,34"/>
	  </g>
	</svg>""")
	return ImageTexture.create_from_image(image)


# ============================================================================
# Spike Ring / 尖刺圆环 —— 圆形竞技场与机关视觉
# ----------------------------------------------------------------------------
# 全部复用原版 Machine Party 工业纹理、Terminal F4 字体与官方角色 rig。
# 不引入任何外部素材；游戏 PCK 未挂载时 make_std_mat 自动退化为纯色材质。
# ============================================================================

static func _color_of(rgb: Array) -> Color:
	if rgb.size() >= 3:
		return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	return Color(0.96, 0.68, 0.22)


static func _disc(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 64
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _spike(height: float, base_radius: float, mat: Material) -> MeshInstance3D:
	## Godot 4 用 top_radius=0 的 CylinderMesh 作为圆锥尖刺。
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = base_radius
	mesh.height = height
	mesh.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func build_arena(radius: float, accent_rgb: Array) -> Dictionary:
	## 构建俯视 2.5D 圆形机械竞技场：黄铜地板、齿轮、尖刺墙、警示灯、喷火口、CRT 后墙。
	## 返回 {root, timer_label, phase_label, alive_label, nozzles}.
	ensure_game_pck_mounted()
	var accent: Color = _color_of(accent_rgb)
	var root := Node3D.new()
	root.name = "SpikeRingArena"

	var brass := make_std_mat(Color(0.42, 0.32, 0.18), 0.72, 0.42, Color.BLACK, 0.0, false, TEX_THREADPLATE, Vector3(10.0, 10.0, 10.0), TEX_THREADPLATE_NORMAL)
	var floor_mat := make_std_mat(Color(0.30, 0.28, 0.26), 0.35, 0.78, Color.BLACK, 0.0, false, TEX_FLOOR, Vector3(9.0, 9.0, 9.0))
	var dark_steel := make_std_mat(Color(0.16, 0.16, 0.18), 0.80, 0.42, Color.BLACK, 0.0, false, TEX_METAL_PLATE, Vector3(3.0, 3.0, 3.0))
	var rust := make_std_mat(Color(0.36, 0.22, 0.15), 0.55, 0.72, Color.BLACK, 0.0, false, TEX_HEAVY_RUST, Vector3(4.0, 4.0, 4.0))
	var spike_mat := make_std_mat(Color(0.72, 0.66, 0.58), 0.88, 0.28)
	var lamp_mat := make_std_mat(Color(0.95, 0.14, 0.10), 0.10, 0.30, Color(1.0, 0.16, 0.08), 2.6)
	var accent_mat := make_std_mat(accent, 0.55, 0.38, accent * 0.65, 1.1)
	var pipe_mat := make_std_mat(Color(0.30, 0.28, 0.26), 0.70, 0.45, Color.BLACK, 0.0, false, TEX_PIPES, Vector3(2.0, 2.0, 2.0))

	# --- 圆形地板（略低于 y=0，玩家站在 y=0）---
	var floor_node := _disc(radius, 0.30, floor_mat)
	floor_node.name = "Floor"
	floor_node.position = Vector3(0.0, -0.16, 0.0)
	root.add_child(floor_node)

	# 地板上的同心黄铜刻度环与径向铆钉带，强化"机械转盘"观感。
	for raw_r in [radius * 0.32, radius * 0.64, radius * 0.93]:
		var ring_r: float = raw_r
		var ring := _disc(ring_r, 0.02, accent_mat)
		ring.position = Vector3(0.0, 0.012, 0.0)
		root.add_child(ring)
		var inner := _disc(ring_r - 0.09, 0.024, floor_mat)
		inner.position = Vector3(0.0, 0.018, 0.0)
		root.add_child(inner)

	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		var rivet := _box(Vector3(0.10, 0.06, 0.34), brass)
		rivet.position = Vector3(cos(a) * radius * 0.78, 0.04, sin(a) * radius * 0.78)
		rivet.rotation.y = -a
		root.add_child(rivet)

	# --- 外圈齿轮装饰（12 组，黄铜齿盘 + 6 齿）---
	var gear_count: int = 12
	for g in range(gear_count):
		var ga: float = TAU * float(g) / float(gear_count)
		var gear_root := Node3D.new()
		gear_root.position = Vector3(cos(ga) * (radius + 0.85), -0.05, sin(ga) * (radius + 0.85))
		gear_root.rotation.y = -ga
		root.add_child(gear_root)
		var plate := _disc(0.72, 0.16, brass)
		gear_root.add_child(plate)
		for t in range(6):
			var ta: float = TAU * float(t) / 6.0
			var tooth := _box(Vector3(0.20, 0.18, 0.26), dark_steel)
			tooth.position = Vector3(cos(ta) * 0.72, 0.0, sin(ta) * 0.72)
			tooth.rotation.y = -ta
			gear_root.add_child(tooth)
		var hub := _disc(0.20, 0.20, accent_mat)
		hub.position = Vector3(0.0, 0.12, 0.0)
		gear_root.add_child(hub)

	# --- 圆形尖刺墙：沿圆周 inward-facing 锥刺 + 底部黄铜护圈 ---
	var wall_ring := _disc(radius + 0.20, 0.55, dark_steel)
	wall_ring.position = Vector3(0.0, -0.28, 0.0)
	root.add_child(wall_ring)
	var wall_inner := _disc(radius - 0.06, 0.58, floor_mat)
	wall_inner.position = Vector3(0.0, -0.27, 0.0)
	root.add_child(wall_inner)

	var spike_count: int = 72
	for s in range(spike_count):
		var sa: float = TAU * float(s) / float(spike_count)
		var sp := _spike(0.90, 0.16, spike_mat)
		sp.position = Vector3(cos(sa) * (radius + 0.02), 0.42, sin(sa) * (radius + 0.02))
		sp.rotation_degrees = Vector3(0.0, -rad_to_deg(sa), 72.0)
		root.add_child(sp)

	# --- 红色警示灯（12 盏，与喷火口交错）---
	for l in range(12):
		var la: float = TAU * float(l) / 12.0 + TAU / 24.0
		var lamp := Node3D.new()
		lamp.position = Vector3(cos(la) * (radius + 0.30), 0.90, sin(la) * (radius + 0.30))
		root.add_child(lamp)
		var cage := _box(Vector3(0.34, 0.34, 0.34), rust)
		lamp.add_child(cage)
		var bulb := MeshInstance3D.new()
		var bulb_mesh := SphereMesh.new()
		bulb_mesh.radius = 0.15
		bulb_mesh.height = 0.30
		bulb.mesh = bulb_mesh
		bulb.material_override = lamp_mat
		bulb.position = Vector3(0.0, 0.22, 0.0)
		lamp.add_child(bulb)

	# --- 圆周喷火口（12 个，复用原版管道纹理），供喷火机关定位 ---
	var nozzles: Array = []
	for n_id in range(12):
		var na: float = TAU * float(n_id) / 12.0
		var nozzle := Node3D.new()
		nozzle.name = "Nozzle_%d" % n_id
		nozzle.position = Vector3(cos(na) * (radius + 0.12), 0.34, sin(na) * (radius + 0.12))
		nozzle.rotation.y = -na
		root.add_child(nozzle)
		var body := _box(Vector3(0.70, 0.52, 0.62), pipe_mat)
		nozzle.add_child(body)
		var muzzle := _disc(0.20, 0.46, dark_steel)
		muzzle.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		muzzle.position = Vector3(-0.40, 0.0, 0.0)
		nozzle.add_child(muzzle)
		var led := _box(Vector3(0.10, 0.10, 0.44), lamp_mat)
		led.position = Vector3(-0.40, 0.30, 0.0)
		nozzle.add_child(led)
		nozzles.append(nozzle)

	# --- 后墙 CRT 监视器：官方 Terminal F4 字体显示倒计时 / 阶段 / 存活人数 ---
	var term_font: Font = load_terminal_font()
	var crt_root := Node3D.new()
	crt_root.name = "CRTBackWall"
	crt_root.position = Vector3(0.0, 5.2, -radius - 3.2)
	root.add_child(crt_root)
	var crt_frame := _box(Vector3(9.4, 4.2, 0.45), dark_steel)
	crt_root.add_child(crt_frame)
	var crt_screen := _box(Vector3(8.8, 3.6, 0.10), make_std_mat(Color(0.02, 0.05, 0.04), 0.0, 0.9, Color(0.10, 0.55, 0.24), 0.35))
	crt_screen.position = Vector3(0.0, 0.0, 0.28)
	crt_root.add_child(crt_screen)

	var timer_label := Label3D.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "60"
	timer_label.font_size = 128
	timer_label.pixel_size = 0.014
	timer_label.modulate = Color(0.62, 1.0, 0.64)
	timer_label.outline_modulate = Color(0.0, 0.0, 0.0)
	timer_label.outline_size = 14
	timer_label.position = Vector3(0.0, 0.55, 0.36)
	if term_font != null:
		timer_label.font = term_font
	crt_root.add_child(timer_label)

	var phase_label := Label3D.new()
	phase_label.name = "PhaseLabel"
	phase_label.text = "WARMUP"
	phase_label.font_size = 44
	phase_label.pixel_size = 0.011
	phase_label.modulate = accent
	phase_label.outline_modulate = Color(0.0, 0.0, 0.0)
	phase_label.outline_size = 10
	phase_label.position = Vector3(0.0, -0.95, 0.36)
	if term_font != null:
		phase_label.font = term_font
	crt_root.add_child(phase_label)

	var alive_label := Label3D.new()
	alive_label.name = "AliveLabel"
	alive_label.text = "ALIVE 0"
	alive_label.font_size = 40
	alive_label.pixel_size = 0.010
	alive_label.modulate = Color(1.0, 0.86, 0.42)
	alive_label.outline_modulate = Color(0.0, 0.0, 0.0)
	alive_label.outline_size = 10
	alive_label.position = Vector3(0.0, -1.55, 0.36)
	if term_font != null:
		alive_label.font = term_font
	crt_root.add_child(alive_label)

	# --- 场地照明（复用官方暖色低饱和工业氛围由 game.gd 的 Environment 提供） ---
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.88, 0.72)
	key.shadow_enabled = true
	root.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "ForgeGlow"
	fill.position = Vector3(0.0, 6.5, 0.0)
	fill.light_color = accent
	fill.light_energy = 2.2
	fill.omni_range = radius * 2.4
	root.add_child(fill)

	return {
		"root": root,
		"timer_label": timer_label,
		"phase_label": phase_label,
		"alive_label": alive_label,
		"nozzles": nozzles,
	}


static func build_surroundings(radius: float, accent_rgb: Array) -> Node3D:
	## 场地四周的机械狂欢环境：延伸工业地板、黄铜/霓虹环、径向管道、静态齿轮与
	## 红色警示灯。正俯视相机会扫到半径约 2R 的区域，用它取代原先的纯黑背景。
	## 全部复用游戏内工业纹理，不引入外部素材；装饰不参与碰撞与出局判定。
	ensure_game_pck_mounted()
	var accent: Color = _color_of(accent_rgb)
	var root := Node3D.new()
	root.name = "Surroundings"
	var outer_r: float = radius * 2.30

	var rust_floor := make_std_mat(Color(0.20, 0.14, 0.10), 0.48, 0.78, Color.BLACK, 0.0, false, TEX_HEAVY_RUST, Vector3(15.0, 15.0, 15.0))
	var plate_floor := make_std_mat(Color(0.25, 0.21, 0.17), 0.62, 0.62, Color.BLACK, 0.0, false, TEX_THREADPLATE, Vector3(12.0, 12.0, 12.0))
	var grate := make_std_mat(Color(0.21, 0.19, 0.17), 0.80, 0.52, Color.BLACK, 0.0, false, TEX_GRATE, Vector3(7.0, 7.0, 7.0))
	var brass := make_std_mat(Color(0.46, 0.34, 0.18), 0.78, 0.40, Color.BLACK, 0.0, false, TEX_THREADPLATE, Vector3(3.0, 3.0, 3.0))
	var pipe := make_std_mat(Color(0.31, 0.27, 0.22), 0.70, 0.48, Color.BLACK, 0.0, false, TEX_PIPES, Vector3(2.0, 2.0, 2.0))
	var lamp := make_std_mat(Color(0.95, 0.16, 0.10), 0.10, 0.30, Color(1.0, 0.18, 0.06), 2.8)
	var neon := make_std_mat(accent, 0.0, 0.50, accent * 0.80, 2.0, true)

	# 1) 大外围地板 + 两层金属平台（顶面依次抬高，避免共面闪烁）
	var ground := _disc(outer_r, 0.60, rust_floor)
	ground.position = Vector3(0.0, -0.70, 0.0)
	root.add_child(ground)
	var grating := _disc(radius + 5.40, 0.06, grate)
	grating.position = Vector3(0.0, -0.36, 0.0)
	root.add_child(grating)
	var grating_inner := _disc(radius + 1.35, 0.06, plate_floor)
	grating_inner.position = Vector3(0.0, -0.31, 0.0)
	root.add_child(grating_inner)

	# 2) 发光黄铜环 / 霓虹环：分隔竞技场与外围工厂
	for raw_rr in [radius + 1.30, radius + 5.25]:
		var rr: float = raw_rr
		var ring := _disc(rr, 0.04, neon)
		ring.position = Vector3(0.0, -0.27, 0.0)
		root.add_child(ring)
		var cover := _disc(rr - 0.16, 0.05, plate_floor)
		cover.position = Vector3(0.0, -0.24, 0.0)
		root.add_child(cover)

	# 3) 16 条径向工业管道 + 两端法兰
	var pipe_count: int = 16
	for i in range(pipe_count):
		var a: float = TAU * float(i) / float(pipe_count)
		var inner: float = radius + 1.60
		var outer: float = radius + 5.00
		var mid_r: float = (inner + outer) * 0.5
		var seg := _box(Vector3(outer - inner, 0.34, 0.42), pipe)
		seg.position = Vector3(cos(a) * mid_r, -0.10, sin(a) * mid_r)
		seg.rotation.y = -a
		root.add_child(seg)
		for raw_rr2 in [inner, outer]:
			var rr2: float = raw_rr2
			var flange := _disc(0.46, 0.16, brass)
			flange.position = Vector3(cos(a) * rr2, -0.06, sin(a) * rr2)
			root.add_child(flange)

	# 4) 8 组静态大齿轮 / 阀门（不滚动，纯氛围）
	var gear_count: int = 8
	for g in range(gear_count):
		var ga: float = TAU * float(g) / float(gear_count) + TAU / 16.0
		var gr: float = radius + 3.30
		var gr_root := Node3D.new()
		gr_root.position = Vector3(cos(ga) * gr, -0.18, sin(ga) * gr)
		root.add_child(gr_root)
		var plate := _disc(1.05, 0.20, brass)
		gr_root.add_child(plate)
		for t in range(10):
			var ta: float = TAU * float(t) / 10.0
			var tooth := _box(Vector3(0.30, 0.24, 0.34), grate)
			tooth.position = Vector3(cos(ta) * 1.05, 0.0, sin(ta) * 1.05)
			tooth.rotation.y = -ta
			gr_root.add_child(tooth)
		var hub := _disc(0.30, 0.26, neon)
		hub.position = Vector3(0.0, 0.14, 0.0)
		gr_root.add_child(hub)

	# 5) 12 盏红色警示灯，每 3 盏带一盏暖色点光
	for l in range(12):
		var la: float = TAU * float(l) / 12.0 + TAU / 24.0
		var lr: float = radius + 1.75
		var lamp_node := Node3D.new()
		lamp_node.position = Vector3(cos(la) * lr, 0.15, sin(la) * lr)
		root.add_child(lamp_node)
		var cage := _box(Vector3(0.42, 0.36, 0.42), grate)
		lamp_node.add_child(cage)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.17
		bm.height = 0.34
		bulb.mesh = bm
		bulb.material_override = lamp
		bulb.position = Vector3(0.0, 0.26, 0.0)
		lamp_node.add_child(bulb)
		if l % 3 == 0:
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.52, 0.22)
			glow.light_energy = 1.4
			glow.omni_range = 7.0
			glow.position = Vector3(0.0, 1.10, 0.0)
			lamp_node.add_child(glow)
	return root


static func build_hazard_warning(type: int, a: Vector2, b: Vector2, width: float) -> Node3D:
	## 地面红色警示带 + 喷火口亮灯 / 轨迹预警线。
	var root := Node3D.new()
	root.name = "HazardWarning"
	var mid: Vector2 = (a + b) * 0.5
	var length: float = a.distance_to(b)
	var angle: float = atan2(b.y - a.y, b.x - a.x)
	var warn_mat := make_std_mat(Color(0.95, 0.12, 0.08, 0.55), 0.0, 0.9, Color(1.0, 0.18, 0.06), 1.9, true)
	var strip := _box(Vector3(length, 0.02, maxf(0.10, width)), warn_mat)
	strip.position = Vector3(mid.x, 0.045, mid.y)
	strip.rotation.y = -angle
	root.add_child(strip)
	# 两侧虚线导轨，机械风格的路标感
	var rail_mat := make_std_mat(Color(1.0, 0.62, 0.12, 0.75), 0.0, 0.7, Color(1.0, 0.45, 0.08), 1.4, true)
	for raw_side in [-1.0, 1.0]:
		var side: float = raw_side
		var off: Vector2 = Vector2(-sin(angle), cos(angle)) * (width * 0.5 + 0.06) * side
		var rail := _box(Vector3(length, 0.02, 0.06), rail_mat)
		rail.position = Vector3(mid.x + off.x, 0.055, mid.y + off.y)
		rail.rotation.y = -angle
		root.add_child(rail)
	if type == 1:  # HZ_SAW
		# 电锯额外画一条细轨迹中心线
		var line := _box(Vector3(length, 0.02, 0.05), make_std_mat(Color(1.0, 0.86, 0.30, 0.9), 0.0, 0.6, Color(1.0, 0.8, 0.2), 2.2, true))
		line.position = Vector3(mid.x, 0.065, mid.y)
		line.rotation.y = -angle
		root.add_child(line)
	return root


static func build_hazard_active(type: int, a: Vector2, b: Vector2, width: float) -> Node3D:
	## 激活视觉：喷火长条 / 电锯本体 / 激光扫描线。纯几何 + 发光材质，复用原版焦痕纹理。
	var root := Node3D.new()
	root.name = "HazardActive"
	var mid: Vector2 = (a + b) * 0.5
	var length: float = a.distance_to(b)
	var angle: float = atan2(b.y - a.y, b.x - a.x)
	if type == 0:  # HZ_FLAME
		var flame_mat := make_std_mat(Color(1.0, 0.42, 0.08, 0.85), 0.0, 0.9, Color(1.0, 0.36, 0.06), 3.2, true, TEX_SCORCH, Vector3(6.0, 1.0, 1.0))
		var band := _box(Vector3(length, 0.42, width), flame_mat)
		band.position = Vector3(mid.x, 0.24, mid.y)
		band.rotation.y = -angle
		root.add_child(band)
		# 分节火舌，制造"喷火口逐段点火"的机械感
		var seg_mat := make_std_mat(Color(1.0, 0.86, 0.24, 0.9), 0.0, 0.7, Color(1.0, 0.72, 0.16), 3.6, true)
		var seg_count: int = maxi(3, int(length / 1.1))
		for i in range(seg_count):
			var t: float = (float(i) + 0.5) / float(seg_count)
			var p: Vector2 = a.lerp(b, t)
			var seg := _box(Vector3(0.55, 0.52, width * 0.62), seg_mat)
			seg.position = Vector3(p.x, 0.30, p.y)
			seg.rotation.y = -angle
			root.add_child(seg)
	elif type == 2:  # HZ_LASER
		# 贴地辉光带：多线并发时在地板上形成清晰的"激光栅栏"
		var glow_mat := make_std_mat(Color(1.0, 0.18, 0.12, 0.38), 0.0, 0.8, Color(1.0, 0.14, 0.08), 1.6, true)
		var ground_glow := _box(Vector3(length, 0.02, width * 2.4), glow_mat)
		ground_glow.position = Vector3(mid.x, 0.035, mid.y)
		ground_glow.rotation.y = -angle
		root.add_child(ground_glow)
		var laser_mat := make_std_mat(Color(1.0, 0.22, 0.18, 0.95), 0.0, 0.6, Color(1.0, 0.20, 0.12), 4.2, true)
		var beam := _box(Vector3(length, 0.14, width), laser_mat)
		beam.position = Vector3(mid.x, 0.62, mid.y)
		beam.rotation.y = -angle
		root.add_child(beam)
		var core := _box(Vector3(length, 0.05, maxf(0.06, width * 0.35)), make_std_mat(Color(1.0, 0.94, 0.72, 1.0), 0.0, 0.4, Color(1.0, 0.92, 0.6), 5.0, true))
		core.position = Vector3(mid.x, 0.64, mid.y)
		core.rotation.y = -angle
		root.add_child(core)
		for raw_endp in [a, b]:
			var endp: Vector2 = raw_endp
			var emitter := _box(Vector3(0.55, 0.72, 0.55), make_std_mat(Color(0.24, 0.24, 0.26), 0.8, 0.4))
			emitter.position = Vector3(endp.x, 0.36, endp.y)
			root.add_child(emitter)
	else:
		# 电锯轨道：贴地细长金属轨 + 两端轴承
		var track_mat := make_std_mat(Color(0.22, 0.22, 0.24), 0.85, 0.35, Color.BLACK, 0.0, false, TEX_GRATE, Vector3(8.0, 1.0, 1.0))
		var track := _box(Vector3(length, 0.06, width * 0.55), track_mat)
		track.position = Vector3(mid.x, 0.05, mid.y)
		track.rotation.y = -angle
		root.add_child(track)
		for raw_endp in [a, b]:
			var endp: Vector2 = raw_endp
			var bearing := _disc(0.36, 0.30, make_std_mat(Color(0.38, 0.30, 0.18), 0.8, 0.4, Color.BLACK, 0.0, false, TEX_THREADPLATE, Vector3(1.0, 1.0, 1.0)))
			bearing.position = Vector3(endp.x, 0.14, endp.y)
			root.add_child(bearing)
	return root


static func build_saw_body(radius: float) -> Node3D:
	## 旋转电锯盘：黄铜齿盘 + 冷钢锯齿，运行时由 game.gd 驱动 rotation.y。
	var root := Node3D.new()
	root.name = "SawBody"
	var blade := _disc(radius, 0.16, make_std_mat(Color(0.66, 0.68, 0.70), 0.92, 0.22, Color(0.35, 0.38, 0.42), 0.35))
	root.add_child(blade)
	var tooth_mat := make_std_mat(Color(0.86, 0.88, 0.90), 0.95, 0.18)
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		var tooth := _box(Vector3(0.16, 0.18, 0.20), tooth_mat)
		tooth.position = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		tooth.rotation.y = -a
		root.add_child(tooth)
	var hub := _disc(0.18, 0.22, make_std_mat(Color(0.92, 0.62, 0.16), 0.75, 0.3, Color(0.9, 0.5, 0.1), 0.8))
	hub.position = Vector3(0.0, 0.10, 0.0)
	root.add_child(hub)
	var spark := OmniLight3D.new()
	spark.light_color = Color(1.0, 0.72, 0.24)
	spark.light_energy = 1.6
	spark.omni_range = 3.0
	root.add_child(spark)
	return root


static func build_spike_ring_icon() -> ImageTexture:
	## 与原版小游戏一致的 256×256 单色 CRT 剪影：尖刺圆环 + 中心齿轮 + 警示箭头。
	var image := Image.new()
	image.load_svg_from_string("""
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
	  <rect width="256" height="256" fill="#000"/>
	  <g fill="#e5e5e5">
	    <!-- 外圈尖刺 -->
	    <g>
	      <polygon points="128,6 138,34 118,34"/>
	      <polygon points="128,250 138,222 118,222"/>
	      <polygon points="6,128 34,118 34,138"/>
	      <polygon points="250,128 222,118 222,138"/>
	      <polygon points="42,42 70,52 52,70"/>
	      <polygon points="214,42 204,70 186,52"/>
	      <polygon points="42,214 52,186 70,204"/>
	      <polygon points="214,214 186,204 204,186"/>
	      <polygon points="88,14 106,38 88,44"/>
	      <polygon points="168,14 168,44 150,38"/>
	      <polygon points="88,242 88,212 106,218"/>
	      <polygon points="168,242 150,218 168,212"/>
	      <polygon points="14,88 44,88 38,106"/>
	      <polygon points="242,88 218,106 212,88"/>
	      <polygon points="14,168 38,150 44,168"/>
	      <polygon points="242,168 212,168 218,150"/>
	    </g>
	    <!-- 主圆环（黄铜齿环剪影） -->
	    <path d="M128 44a84 84 0 1 0 0 168a84 84 0 1 0 0-168zm0 22a62 62 0 1 1 0 124a62 62 0 1 1 0-124z"/>
	    <!-- 环上铆钉 -->
	    <circle cx="128" cy="52" r="6"/><circle cx="128" cy="204" r="6"/>
	    <circle cx="52" cy="128" r="6"/><circle cx="204" cy="128" r="6"/>
	    <circle cx="74" cy="74" r="5"/><circle cx="182" cy="74" r="5"/>
	    <circle cx="74" cy="182" r="5"/><circle cx="182" cy="182" r="5"/>
	    <!-- 中心齿轮 -->
	    <circle cx="128" cy="128" r="34"/>
	    <g fill="#000">
	      <rect x="122" y="84" width="12" height="18"/>
	      <rect x="122" y="154" width="12" height="18"/>
	      <rect x="84" y="122" width="18" height="12"/>
	      <rect x="154" y="122" width="18" height="12"/>
	      <circle cx="128" cy="128" r="15"/>
	    </g>
	    <circle cx="128" cy="128" r="8" fill="#e5e5e5"/>
	    <!-- 顶部红色警示灯（剪影用留白三角表示） -->
	    <polygon points="128,26 120,40 136,40"/>
	  </g>
	</svg>""")
	return ImageTexture.create_from_image(image)

