extends RefCounted

## Asset loader and 3D builders for Roller Carnival (滾筒嘉年華).
## Uses authentic Machine Party 3D worker characters, cosmetics, textures,
## fonts, and animations when Machine Party.pck is mounted/available,
## with procedural mesh fallbacks if standalone assets are absent.

const PLAYER_COLORS := [
	Color(0.22, 0.58, 1.00), # P1: Blue
	Color(0.70, 0.34, 0.98), # P2: Purple
	Color(0.22, 0.84, 0.44), # P3: Green
	Color(0.96, 0.28, 0.30), # P4: Red
	Color(0.86, 0.89, 0.93), # P5: White / Silver
	Color(1.00, 0.56, 0.14), # P6: Orange
	Color(0.14, 0.86, 0.88), # P7: Cyan
	Color(1.00, 0.84, 0.20), # P8: Yellow
	Color(1.00, 0.36, 0.72), # P9: Hot Pink
	Color(0.62, 0.92, 0.24), # P10: Lime
	Color(0.95, 0.66, 0.22), # P11: Amber
	Color(0.20, 0.92, 0.68), # P12: Emerald
	Color(0.88, 0.20, 0.48), # P13: Crimson
	Color(0.30, 0.48, 0.98), # P14: Cobalt
	Color(0.76, 0.54, 1.00), # P15: Amethyst
	Color(0.84, 0.72, 0.34), # P16: Brass Gold
]

const PLAYER_NAMES := [
	"玩家 1 (你)",
	"發條阿紫",
	"鍋爐綠醬",
	"紅心活塞",
	"白銀鉚釘",
	"橘子渦輪",
	"青藍齒輪",
	"黃金彈簧",
	"霓虹飛輪",
	"蒸氣板手",
	"琥珀發條",
	"翡翠軸承",
	"深紅閥門",
	"鈷藍彈簧",
	"紫晶渦輪",
	"黑金齒輪",
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

# Indices match PLAYER_COLORS (16 distinct workers using Machine Party textures & tints)
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

static var _pck_checked: bool = false
static var _pck_available: bool = false


static func ensure_game_pck_mounted() -> bool:
	if _pck_checked:
		return _pck_available
	_pck_checked = true

	if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
		_pck_available = true
		return true

	var pck_path := OS.get_environment("MP_PCK_PATH")
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
	return load_optional("res://fonts/Terminal F4.ttf")


static func make_toon_mat(color: Color, roughness: float = 0.48, metallic: float = 0.08, emission: Color = Color.BLACK, emission_energy: float = 0.0, tex_path: String = "", uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if not tex_path.is_empty():
		var tex = load_optional(tex_path)
		if tex is Texture2D:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.uv1_triplanar = true
			mat.uv1_scale = uv_scale
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


static func build_stage_and_environment(root: Node3D, cfg) -> Dictionary:
	ensure_game_pck_mounted()
	var result := {
		"gears": [],
		"bulbs": [],
		"lava_mesh": null,
		"lava_bubbles": [],
		"beacon_gold": null,
		"beacon_silver": null,
		"starting_line": null,
		"lane_tracks": [],
	}

	# --- World Environment (Machine Party low-saturation warm industrial tone + bloom) ---
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.35, 0.30)
	env.ambient_light_energy = 0.78
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.12
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.88
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.14
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)

	# --- Warm Directional Key Light with Crisp Shadows ---
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "KeyLight"
	dir_light.light_color = Color(1.0, 0.90, 0.76)
	dir_light.light_energy = 1.85
	dir_light.shadow_enabled = true
	dir_light.directional_shadow_max_distance = 45.0
	dir_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	root.add_child(dir_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "RimFillLight"
	fill_light.light_color = Color(0.62, 0.74, 1.0)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(-35.0, 145.0, 0.0)
	root.add_child(fill_light)

	# --- Oblique 45-degree Top-Down Camera ---
	var cam := Camera3D.new()
	cam.name = "StageCamera"
	cam.fov = 40.0
	cam.position = Vector3(0.45, 11.8, 11.8)
	cam.look_at_from_position(cam.position, Vector3(0.35, 0.65, 0.0), Vector3.UP)
	cam.current = true
	root.add_child(cam)

	# --- Main Stage Platform (Machine Party industrial floor textures) ---
	var left_x: float = cfg.stage_left_lava_x
	var right_x: float = cfg.roller_spawn_x + 0.8
	var stage_width: float = right_x - left_x
	var stage_center_x: float = (left_x + right_x) * 0.5
	var stage_depth: float = 9.2

	var deck := MeshInstance3D.new()
	deck.name = "StageDeck"
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(stage_width, 0.9, stage_depth)
	deck.mesh = deck_box
	deck.material_override = make_toon_mat(
		Color(0.75, 0.70, 0.74), 0.58, 0.35, Color.BLACK, 0.0,
		"res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba floor5.png",
		Vector3(0.24, 0.24, 0.24)
	)
	deck.position = Vector3(stage_center_x, -0.45, 0.0)
	root.add_child(deck)

	# Mechanical seam lines & cracks
	var seam_mat := make_toon_mat(Color(0.22, 0.20, 0.24), 0.70, 0.45, Color.BLACK, 0.0, "res://minigames/dvd_roomba/models/dvd roomba visuals1_metal plate1.png", Vector3(0.3, 0.3, 0.3))
	for i in range(9):
		var sx: float = left_x + 1.1 + float(i) * (stage_width - 1.5) / 8.0
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(0.10, 0.02, stage_depth - 0.5)
		seam.mesh = seam_mesh
		seam.material_override = seam_mat
		seam.position = Vector3(sx, 0.01, 0.0)
		root.add_child(seam)

	# Starting Line (Option A: all 1-8 players stand shoulder-to-shoulder at player_spawn_x)
	var start_line := MeshInstance3D.new()
	start_line.name = "StartingLine"
	var sl_mesh := BoxMesh.new()
	sl_mesh.size = Vector3(0.24, 0.024, stage_depth - 0.6)
	start_line.mesh = sl_mesh
	start_line.material_override = make_toon_mat(Color(1.0, 0.80, 0.22), 0.35, 0.3, Color(1.0, 0.72, 0.14), 0.38)
	start_line.position = Vector3(cfg.player_spawn_x, 0.014, 0.0)
	root.add_child(start_line)
	result["starting_line"] = start_line

	# Horizontal lane tracks from starting line leftward toward lava (16 reusable tracks)
	var lane_mat := make_toon_mat(Color(0.36, 0.31, 0.38, 0.55), 0.65, 0.25)
	lane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var lane_tracks: Array = []
	for li in range(16):
		var lane := MeshInstance3D.new()
		lane.name = "LaneTrack_%d" % li
		var lm := BoxMesh.new()
		lm.size = Vector3(1.0, 0.014, 0.09)
		lane.mesh = lm
		lane.material_override = lane_mat
		root.add_child(lane)
		lane_tracks.append(lane)
	result["lane_tracks"] = lane_tracks

	var crack_mat := make_toon_mat(Color(0.10, 0.08, 0.11), 0.85, 0.1)
	for c in [Vector3(-2.6, 0.012, -1.6), Vector3(1.8, 0.012, 2.0), Vector3(-4.1, 0.012, 1.3), Vector3(4.3, 0.012, -1.9)]:
		var crack := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.95, 0.015, 0.07)
		crack.mesh = cm
		crack.material_override = crack_mat
		crack.position = c
		crack.rotation_degrees.y = (c.x * 23.0)
		root.add_child(crack)

	# Left Hazard Warning Stripes + Grate bordering the lava pit
	var stripe_yellow := make_toon_mat(Color(0.96, 0.74, 0.12), 0.45, 0.2, Color(0.96, 0.65, 0.08), 0.18, "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba grate.png", Vector3(0.5, 0.5, 0.5))
	var stripe_dark := make_toon_mat(Color(0.18, 0.16, 0.20), 0.55, 0.35, Color.BLACK, 0.0, "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba grate.png", Vector3(0.5, 0.5, 0.5))
	for idx in range(14):
		var sz: float = -stage_depth * 0.5 + 0.3 + float(idx) * (stage_depth / 14.0)
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.75, 0.03, 0.44)
		stripe.mesh = sm
		stripe.material_override = stripe_yellow if (idx % 2 == 0) else stripe_dark
		stripe.position = Vector3(left_x + 0.38, 0.015, sz)
		root.add_child(stripe)

	# Front & Back Brass / Industrial Metal Rails
	var brass_mat := make_toon_mat(Color(0.82, 0.60, 0.24), 0.34, 0.70, Color.BLACK, 0.0, "res://minigames/dvd_roomba/models/dvd roomba visuals1_metal plate1.png", Vector3(0.4, 0.4, 0.4))
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(stage_width, 0.34, 0.32)
		rail.mesh = rm
		rail.material_override = brass_mat
		rail.position = Vector3(stage_center_x, 0.14, side * (stage_depth * 0.5 + 0.12))
		root.add_child(rail)

	# --- Boiling Orange-Yellow Lava Pit on Far Left ---
	var lava_width: float = 7.5
	var lava_center_x: float = left_x - lava_width * 0.5 + 0.05
	var lava := MeshInstance3D.new()
	lava.name = "LavaPool"
	var lava_box := BoxMesh.new()
	lava_box.size = Vector3(lava_width, 0.4, stage_depth + 4.0)
	lava.mesh = lava_box
	lava.material_override = make_toon_mat(Color(0.92, 0.24, 0.03), 0.30, 0.0, Color(0.95, 0.28, 0.03), 0.95)
	lava.position = Vector3(lava_center_x, -0.58, 0.0)
	root.add_child(lava)
	result["lava_mesh"] = lava

	var lava_light := OmniLight3D.new()
	lava_light.name = "LavaGlowLight"
	lava_light.light_color = Color(1.0, 0.42, 0.08)
	lava_light.light_energy = 3.2
	lava_light.omni_range = 10.5
	lava_light.position = Vector3(left_x - 1.8, 1.2, 0.0)
	root.add_child(lava_light)

	var bubble_mat := make_toon_mat(Color(1.0, 0.68, 0.12), 0.2, 0.0, Color(1.0, 0.62, 0.08), 1.45)
	for b in range(12):
		var bmesh := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.22 + float(b % 3) * 0.08
		sph.height = sph.radius * 2.0
		bmesh.mesh = sph
		bmesh.material_override = bubble_mat
		var bx: float = left_x - 0.65 - float(b % 4) * 1.15
		var bz: float = -3.4 + float(b) * 0.62
		bmesh.position = Vector3(bx, -0.45, bz)
		root.add_child(bmesh)
		result["lava_bubbles"].append({
			"node": bmesh,
			"base_x": bx,
			"base_z": bz,
			"phase": float(b) * 0.73,
		})

	# --- Carnival String Lights & Rotating Mechanical Gears ---
	var post_mat := make_toon_mat(Color(0.55, 0.48, 0.52), 0.45, 0.6, Color.BLACK, 0.0, "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba pipes.png", Vector3(0.5, 0.5, 0.5))
	var bulb_palette := [
		Color(1.0, 0.32, 0.24),
		Color(1.0, 0.82, 0.18),
		Color(0.22, 0.88, 1.0),
		Color(0.95, 0.36, 0.88),
	]
	for p in range(6):
		var px: float = left_x + 1.2 + float(p) * 2.7
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.12
		pm.height = 2.6
		post.mesh = pm
		post.material_override = post_mat
		post.position = Vector3(px, 1.3, -stage_depth * 0.5 - 0.15)
		root.add_child(post)

		var col: Color = bulb_palette[p % bulb_palette.size()]
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.20
		bm.height = 0.40
		bulb.mesh = bm
		bulb.material_override = make_toon_mat(col, 0.2, 0.0, col, 2.2)
		bulb.position = Vector3(px, 2.7, -stage_depth * 0.5 - 0.15)
		root.add_child(bulb)
		result["bulbs"].append(bulb)

	var warm_stage_light := OmniLight3D.new()
	warm_stage_light.name = "CarnivalStageGlow"
	warm_stage_light.light_color = Color(1.0, 0.76, 0.40)
	warm_stage_light.light_energy = 2.6
	warm_stage_light.omni_range = 18.0
	warm_stage_light.position = Vector3(1.5, 4.6, -2.5)
	root.add_child(warm_stage_light)

	for g in range(4):
		var saw_tex := "res://minigames/dvd_roomba/models/dvd roomba visuals1_circular saw2.png" if g % 2 == 0 else "res://minigames/dvd_roomba/models/dvd roomba visuals1_circular saw bloody.png"
		var gear := _build_gear(1.25 + float(g % 2) * 0.55, 10, Color(0.84, 0.64, 0.36) if g % 2 == 0 else Color(0.68, 0.70, 0.74), saw_tex)
		gear.position = Vector3(-3.8 + float(g) * 4.2, 0.75 + float(g % 2) * 0.9, -stage_depth * 0.5 - 0.75)
		root.add_child(gear)
		result["gears"].append(gear)

	# --- Right-side Roller Dispenser Gantry ---
	var gantry_x: float = cfg.roller_spawn_x + 0.2
	var gantry_mat := make_toon_mat(Color(0.58, 0.52, 0.56), 0.38, 0.7, Color.BLACK, 0.0, "res://minigames/dvd_roomba/models/dvd roomba visuals1_dvd roomba siding.png", Vector3(0.4, 0.4, 0.4))
	for gz in [-stage_depth * 0.5 - 0.15, stage_depth * 0.5 + 0.15]:
		var pillar := MeshInstance3D.new()
		var pil_m := BoxMesh.new()
		pil_m.size = Vector3(0.55, 3.4, 0.55)
		pillar.mesh = pil_m
		pillar.material_override = gantry_mat
		pillar.position = Vector3(gantry_x, 1.7, gz)
		root.add_child(pillar)

	var top_beam := MeshInstance3D.new()
	var beam_m := BoxMesh.new()
	beam_m.size = Vector3(0.65, 0.55, stage_depth + 0.85)
	top_beam.mesh = beam_m
	top_beam.material_override = brass_mat
	top_beam.position = Vector3(gantry_x, 3.35, 0.0)
	root.add_child(top_beam)

	var beacon_gold := MeshInstance3D.new()
	var bg_m := SphereMesh.new()
	bg_m.radius = 0.28
	bg_m.height = 0.56
	beacon_gold.mesh = bg_m
	beacon_gold.material_override = make_toon_mat(Color(1.0, 0.82, 0.18), 0.2, 0.0, Color(1.0, 0.78, 0.12), 0.6)
	beacon_gold.position = Vector3(gantry_x - 0.2, 3.35, -1.2)
	root.add_child(beacon_gold)
	result["beacon_gold"] = beacon_gold

	var beacon_silver := MeshInstance3D.new()
	var bs_m := SphereMesh.new()
	bs_m.radius = 0.28
	bs_m.height = 0.56
	beacon_silver.mesh = bs_m
	beacon_silver.material_override = make_toon_mat(Color(0.75, 0.90, 1.0), 0.2, 0.0, Color(0.55, 0.85, 1.0), 0.6)
	beacon_silver.position = Vector3(gantry_x - 0.2, 3.35, 1.2)
	root.add_child(beacon_silver)
	result["beacon_silver"] = beacon_silver

	update_starting_line(result, cfg)
	return result


static func update_starting_line(scene_props: Dictionary, cfg) -> void:
	if scene_props.is_empty() or cfg == null:
		return
	var sl = scene_props.get("starting_line", null)
	if sl is Node3D:
		(sl as Node3D).position.x = cfg.player_spawn_x

	var lane_tracks = scene_props.get("lane_tracks", [])
	if not (lane_tracks is Array):
		return
	var left_limit: float = cfg.stage_left_lava_x + 0.8
	var right_limit: float = cfg.player_spawn_x + 0.6
	var lane_len: float = maxf(1.0, right_limit - left_limit)
	var lane_center_x: float = (left_limit + right_limit) * 0.5
	var lane_count: int = clampi(cfg.max_players, 1, 16)
	var z_half: float = 3.75 if lane_count > 8 else 3.15
	for li in range(lane_tracks.size()):
		var lane = lane_tracks[li]
		if not (lane is Node3D):
			continue
		var lane_node := lane as Node3D
		if li >= lane_count:
			lane_node.visible = false
			continue
		lane_node.visible = true
		var lz: float = 0.0 if lane_count == 1 else lerpf(-z_half, z_half, float(li) / float(lane_count - 1))
		lane_node.position = Vector3(lane_center_x, 0.012, lz)
		lane_node.scale = Vector3(lane_len, 1.0, 1.0)


static func _build_gear(radius: float, teeth: int, color: Color, tex_path: String = "") -> Node3D:
	var gear := Node3D.new()
	var mat := make_toon_mat(color, 0.35, 0.75, Color.BLACK, 0.0, tex_path, Vector3(0.4, 0.4, 0.4))

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.26
	disc.mesh = cyl
	disc.material_override = mat
	disc.rotation_degrees.x = 90.0
	gear.add_child(disc)

	for t in range(teeth):
		var angle: float = TAU * float(t) / float(teeth)
		var tooth := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(radius * 0.26, radius * 0.28, 0.24)
		tooth.mesh = tm
		tooth.material_override = mat
		tooth.position = Vector3(cos(angle) * (radius + 0.1), sin(angle) * (radius + 0.1), 0.0)
		tooth.rotation.z = angle
		gear.add_child(tooth)

	return gear


static func build_cartoon_character(idx: int, nickname: String) -> Dictionary:
	ensure_game_pck_mounted()
	var col: Color = PLAYER_COLORS[idx % PLAYER_COLORS.size()]
	var root := Node3D.new()
	root.name = "Player_%d" % (idx + 1)

	# Ground drop shadow disc (stays at y=0.025 even when character jumps)
	var shadow := MeshInstance3D.new()
	shadow.name = "GroundShadow"
	var sh_m := CylinderMesh.new()
	sh_m.top_radius = 0.42
	sh_m.bottom_radius = 0.42
	sh_m.height = 0.02
	shadow.mesh = sh_m
	shadow.material_override = make_toon_mat(Color(0.03, 0.02, 0.04, 0.7), 0.9, 0.0)
	shadow.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.position = Vector3(0.0, 0.025, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)

	var visual := Node3D.new()
	visual.name = "VisualPivot"
	root.add_child(visual)

	var anim_player: AnimationPlayer = null
	var char_packed = load_optional("res://minigames/exploding_collar_race/models/main character2/main character2.glb")
	if char_packed is PackedScene:
		var rig: Node3D = char_packed.instantiate()
		rig.name = "OfficialCharacterRig"
		# main character2.glb Armature faces local -Z; rotate -90 deg so character faces +X (toward incoming rollers)
		rig.rotation_degrees.y = -90.0
		# Original mesh height is ~4.84 units -> 0.31 scale aligns character height to ~1.50 units
		rig.scale = Vector3(0.31, 0.31, 0.31)
		visual.add_child(rig)
		_customize_official_rig(rig, idx)
		anim_player = _setup_official_animations(rig)
	else:
		_build_fallback_character(visual, idx, col)

	# Floating colored nickname Label3D
	var label := Label3D.new()
	label.name = "NicknameLabel"
	label.text = nickname
	label.font_size = 34
	label.pixel_size = 0.0082
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = col.lightened(0.22)
	label.outline_modulate = Color(0.04, 0.03, 0.06)
	label.outline_size = 10
	var font := load_terminal_font()
	if font != null:
		label.font = font
	label.position = Vector3(0.0, 1.92, 0.0)
	root.add_child(label)

	return {
		"root": root,
		"visual": visual,
		"shadow": shadow,
		"label": label,
		"anim_player": anim_player,
	}


static func _customize_official_rig(rig: Node3D, idx: int) -> void:
	var sk := rig.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if sk == null:
		return

	var char_mesh := sk.get_node_or_null("character mesh") as MeshInstance3D
	if char_mesh != null:
		var suit_tex = load_optional(SUIT_TEXTURE_MAP[idx % SUIT_TEXTURE_MAP.size()])
		if suit_tex is Texture2D:
			var suit_mat := StandardMaterial3D.new()
			suit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			suit_mat.albedo_texture = suit_tex
			suit_mat.albedo_color = SUIT_TINTS[idx % SUIT_TINTS.size()]
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

	# Attach official Machine Party 3D hat to Skeleton3D bone "hat" (idx 5)
	var hat_cfg: Dictionary = HAT_COSMETICS[idx % HAT_COSMETICS.size()]
	var hat_packed = load_optional(str(hat_cfg["path"]))
	if hat_packed is PackedScene:
		var hat_attach := BoneAttachment3D.new()
		hat_attach.name = "ModHatAttachment"
		hat_attach.bone_name = "hat"
		hat_attach.bone_idx = sk.find_bone("hat")
		sk.add_child(hat_attach)

		var hat_inst: Node3D = hat_packed.instantiate()
		hat_inst.transform = hat_cfg["tf"]
		hat_attach.add_child(hat_inst)

	# Attach official Machine Party 3D glasses where configured
	if GLASSES_COSMETICS.has(idx):
		var gl_cfg: Dictionary = GLASSES_COSMETICS[idx]
		var gl_packed = load_optional(str(gl_cfg["path"]))
		if gl_packed is PackedScene:
			var gl_attach := BoneAttachment3D.new()
			gl_attach.name = "ModGlassesAttachment"
			gl_attach.bone_name = "head"
			gl_attach.bone_idx = sk.find_bone("head")
			sk.add_child(gl_attach)

			var gl_inst: Node3D = gl_packed.instantiate()
			gl_inst.transform = gl_cfg["tf"]
			gl_attach.add_child(gl_inst)


static func _setup_official_animations(rig: Node3D) -> AnimationPlayer:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return null

	var lib := AnimationLibrary.new()
	var anim_idle = load_optional("res://animations/standing_idle_dynamic.res")
	var anim_shove = load_optional("res://minigames/disco_dodge/animations/shoved_main.res")
	var anim_fall = load_optional("res://minigames/disco_dodge/animations/falling.res")

	if anim_idle is Animation:
		var dup_idle: Animation = anim_idle.duplicate()
		dup_idle.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"idle", dup_idle)
	if anim_shove is Animation:
		lib.add_animation(&"shoved", anim_shove)
	if anim_fall is Animation:
		var dup_fall: Animation = anim_fall.duplicate()
		dup_fall.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"falling", dup_fall)

	if not lib.get_animation_list().is_empty():
		ap.add_animation_library(&"mp_mod", lib)
		if lib.has_animation(&"idle"):
			ap.play(&"mp_mod/idle")
	elif ap.has_animation(&"standing idle"):
		ap.play(&"standing idle")

	return ap


static func _build_fallback_character(visual: Node3D, idx: int, col: Color) -> void:
	var body_mat := make_toon_mat(col, 0.42, 0.12)
	var accent_mat := make_toon_mat(col.darkened(0.32), 0.45, 0.18)
	var skin_mat := make_toon_mat(Color(1.0, 0.87, 0.74), 0.52, 0.02)
	var eye_mat := make_toon_mat(Color(0.08, 0.08, 0.10), 0.2, 0.1)

	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.29
	tm.height = 0.88
	torso.mesh = tm
	torso.material_override = body_mat
	torso.position = Vector3(0.0, 0.56, 0.0)
	visual.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	head.mesh = hm
	head.material_override = skin_mat
	head.position = Vector3(0.0, 1.16, 0.0)
	visual.add_child(head)

	for ez in [-0.10, 0.10]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.055
		em.height = 0.11
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(0.23, 1.18, ez)
		visual.add_child(eye)

	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.30
	cm.height = 0.22
	cap.mesh = cm
	cap.material_override = accent_mat
	cap.position = Vector3(0.0, 1.44 + float(idx % 2) * 0.04, 0.0)
	visual.add_child(cap)


static func build_roller_mesh(roller_type: String, radius: float, length: float = 8.0) -> Dictionary:
	ensure_game_pck_mounted()
	var root := Node3D.new()
	var is_gold: bool = (roller_type == "gold")
	var base_color: Color = Color(1.0, 0.76, 0.18) if is_gold else Color(0.84, 0.90, 0.96)
	var glow_color: Color = Color(1.0, 0.72, 0.10) if is_gold else Color(0.55, 0.88, 1.0)
	var spike_color: Color = Color(0.52, 0.30, 0.06) if is_gold else Color(0.32, 0.38, 0.46)

	var body_mat := make_toon_mat(
		base_color, 0.24, 0.84, glow_color, 0.22,
		"res://minigames/dvd_roomba/models/dvd roomba visuals1_metal plate1.png",
		Vector3(0.6, 0.6, 0.6)
	)
	var glow_mat := make_toon_mat(glow_color, 0.2, 0.1, glow_color, 1.85)
	var spike_mat := make_toon_mat(spike_color, 0.35, 0.75)

	var spin_pivot := Node3D.new()
	spin_pivot.name = "SpinPivot"
	root.add_child(spin_pivot)

	var cyl_node := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl_node.mesh = cyl
	cyl_node.material_override = body_mat
	cyl_node.rotation_degrees.x = 90.0
	spin_pivot.add_child(cyl_node)

	for rz in [-2.6, -0.9, 0.9, 2.6]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = radius + 0.025
		rm.bottom_radius = radius + 0.025
		rm.height = 0.20
		ring.mesh = rm
		ring.material_override = glow_mat
		ring.rotation_degrees.x = 90.0
		ring.position = Vector3(0.0, 0.0, rz)
		spin_pivot.add_child(ring)

	for s_idx in range(6):
		var z_pos: float = -3.0 + float(s_idx) * 1.2
		for k in range(4):
			var ang: float = TAU * float(k) / 4.0 + float(s_idx) * 0.45
			var spike := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.015
			sm.bottom_radius = 0.085
			sm.height = 0.18
			spike.mesh = sm
			spike.material_override = spike_mat
			spike.position = Vector3(cos(ang) * (radius + 0.06), sin(ang) * (radius + 0.06), z_pos)
			spike.rotation.z = ang - PI * 0.5
			spin_pivot.add_child(spike)

	for ez in [-length * 0.5, length * 0.5]:
		var cap := _build_gear(radius + 0.08, 8, spike_color, "res://minigames/dvd_roomba/models/dvd roomba visuals1_circular saw bloody.png")
		cap.position = Vector3(0.0, 0.0, ez)
		spin_pivot.add_child(cap)

	return {
		"root": root,
		"spin": spin_pivot,
	}


## Original rolling drum pictogram for the official black-and-white icon grid.
static func build_roller_icon() -> ImageTexture:
	var image := Image.new()
	image.load_svg_from_string("""
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
	  <rect width="256" height="256" fill="#000"/>
	  <g fill="#e5e5e5">
	    <path d="M15 150h48l-8 13H7zm14-26h48l-8 13H21zm-8 53h33l6 13H13z"/>
	    <g transform="rotate(-28 145 132)">
	      <path d="M82 78h110v108H82c-20 0-33-24-33-54s13-54 33-54z"/>
	      <path d="M85 80c-23 25-23 78 0 104m25-104c-23 25-23 78 0 104" stroke="#000" stroke-width="10" fill="none"/>
	      <ellipse cx="193" cy="132" rx="35" ry="56" stroke="#000" stroke-width="9"/>
	      <ellipse cx="193" cy="132" rx="13" ry="25" fill="#000"/>
	    </g>
	  </g>
	</svg>""")
	return ImageTexture.create_from_image(image)
