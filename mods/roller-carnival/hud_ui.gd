extends RefCounted

## HUD overlay, countdown banner, YOU marker, and round summary panel for Roller Carnival.


class YouMarkerOverlay extends Control:
	var top_left: Vector2 = Vector2.ZERO
	var bound_size: Vector2 = Vector2.ZERO
	var marker_font: Font = null
	var marker_text: String = "YOU"
	var shake_offset: Vector2 = Vector2.ZERO
	var active: bool = false

	func _draw() -> void:
		if not active or bound_size.x <= 1.0 or bound_size.y <= 1.0:
			return
		var font_to_use: Font = marker_font if marker_font != null else ThemeDB.fallback_font
		var viewport_rect := get_viewport_rect()
		var bounds_center := top_left + bound_size * 0.5
		var viewport_center := viewport_rect.size * 0.5
		var dir := Vector2(1.0 if bounds_center.x < viewport_center.x else -1.0, 1.0 if bounds_center.y < viewport_center.y else -1.0)
		var start_point := Vector2(
			top_left.x + maxf(bound_size.x * dir.x, 0.0),
			top_left.y + maxf(bound_size.y * dir.y, 0.0)
		) - dir
		var text_size := font_to_use.get_string_size(marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		var text_point := start_point + dir * 32.0 + Vector2(minf(dir.x, 0.0) * text_size.x, 0.0)
		var line_pts := PackedVector2Array([
			start_point,
			start_point + dir * 32.0,
			start_point + dir * 32.0 + Vector2(dir.x * text_size.x, 0.0),
		])
		var corner := 16.0
		var shadow := Vector2(2.0, 2.0)
		for pass_idx in range(2):
			var off := (shadow if pass_idx == 0 else Vector2.ZERO) + shake_offset
			var col := Color.BLACK if pass_idx == 0 else Color.WHITE
			var p0 := top_left + off
			var p1 := top_left + Vector2(bound_size.x, 0.0) + off
			var p2 := top_left + bound_size + off
			var p3 := top_left + Vector2(0.0, bound_size.y) + off
			draw_line(p0, p0 + Vector2.RIGHT * corner, col, 2.0)
			draw_line(p0, p0 + Vector2.DOWN * corner, col, 2.0)
			draw_line(p1, p1 + Vector2.LEFT * corner, col, 2.0)
			draw_line(p1, p1 + Vector2.DOWN * corner, col, 2.0)
			draw_line(p2, p2 + Vector2.UP * corner, col, 2.0)
			draw_line(p2, p2 + Vector2.LEFT * corner, col, 2.0)
			draw_line(p3, p3 + Vector2.UP * corner, col, 2.0)
			draw_line(p3, p3 + Vector2.RIGHT * corner, col, 2.0)
			var s_pts := PackedVector2Array([line_pts[0] + off, line_pts[1] + off, line_pts[2] + off])
			draw_polyline(s_pts, col, 2.0, false)
			draw_string(font_to_use, text_point + Vector2(0.0, -4.0) + off, marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)


func build_ui(stage: Node3D) -> void:
	var meshes = stage._meshes
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "GameHUD"
	ui_layer.layer = 2
	stage.add_child(ui_layer)
	stage._ui_layer = ui_layer

	var term_font: Font = meshes.load_terminal_font()
	var hud_theme := Theme.new()
	if term_font != null:
		hud_theme.default_font = term_font
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.theme = hud_theme
	ui_layer.add_child(root_ctrl)

	var you_marker := YouMarkerOverlay.new()
	you_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	you_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	you_marker.marker_font = term_font
	you_marker.marker_text = stage._loc_or("LOC_CONTROL_YOU", "YOU")
	you_marker.visible = false
	root_ctrl.add_child(you_marker)
	stage._you_marker = you_marker

	var countdown_label := Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 68)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	countdown_label.add_theme_constant_override("outline_size", 8)
	root_ctrl.add_child(countdown_label)
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_label.hide()
	stage._countdown_label = countdown_label

	var go_label := Label.new()
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	go_label.add_theme_font_size_override("font_size", 68)
	go_label.add_theme_color_override("font_color", Color.WHITE)
	go_label.add_theme_color_override("font_outline_color", Color.BLACK)
	go_label.add_theme_constant_override("outline_size", 8)
	root_ctrl.add_child(go_label)
	go_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	go_label.hide()
	stage._go_label = go_label

	var round_banner := Control.new()
	round_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	round_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_banner.visible = false
	root_ctrl.add_child(round_banner)
	stage._round_banner = round_banner

	var banner_bg := ColorRect.new()
	banner_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	round_banner.add_child(banner_bg)

	var grunge_tex = meshes.load_optional("res://minigames/intermission_new/textures/intermission grunge overlay4.png")
	if grunge_tex is Texture2D:
		var grunge := TextureRect.new()
		grunge.set_anchors_preset(Control.PRESET_FULL_RECT)
		grunge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grunge.texture = grunge_tex
		grunge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grunge.stretch_mode = TextureRect.STRETCH_SCALE
		var g_mat := CanvasItemMaterial.new()
		g_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		grunge.material = g_mat
		grunge.modulate = Color(1.0, 1.0, 1.0, 0.25)
		round_banner.add_child(grunge)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_vbox.add_theme_constant_override("separation", 18)
	banner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_banner.add_child(banner_vbox)

	var round_title_label := Label.new()
	round_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_title_label.add_theme_font_size_override("font_size", 60)
	round_title_label.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	banner_vbox.add_child(round_title_label)
	stage._round_title_label = round_title_label

	var round_tagline_label := Label.new()
	round_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_tagline_label.add_theme_font_size_override("font_size", 24)
	round_tagline_label.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	round_tagline_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	banner_vbox.add_child(round_tagline_label)
	stage._round_tagline_label = round_tagline_label

	if bool(stage._hosted_in_official_game):
		return

	var results_panel := make_panel_box(Color(0.03, 0.04, 0.03, 0.96))
	results_panel.anchor_left = 0.5
	results_panel.anchor_right = 0.5
	results_panel.anchor_top = 0.5
	results_panel.anchor_bottom = 0.5
	results_panel.offset_left = -340.0
	results_panel.offset_right = 340.0
	results_panel.offset_top = -255.0
	results_panel.offset_bottom = 250.0
	results_panel.visible = false
	root_ctrl.add_child(results_panel)
	stage._results_panel = results_panel

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	results_panel.add_child(r_vbox)

	var results_title := Label.new()
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_title.text = "ROUND SUMMARY"
	results_title.add_theme_font_size_override("font_size", 28)
	results_title.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
	r_vbox.add_child(results_title)
	stage._results_title = results_title

	var results_subtitle := Label.new()
	results_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_subtitle.add_theme_font_size_override("font_size", 16)
	results_subtitle.add_theme_color_override("font_color", Color(0.76, 0.86, 0.74))
	r_vbox.add_child(results_subtitle)
	stage._results_subtitle = results_subtitle

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(r_scroll)

	var results_rows := VBoxContainer.new()
	results_rows.add_theme_constant_override("separation", 6)
	results_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_scroll.add_child(results_rows)
	stage._results_rows = results_rows


func make_panel_box(bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	st.corner_radius_top_left = 0
	st.corner_radius_top_right = 0
	st.corner_radius_bottom_left = 0
	st.corner_radius_bottom_right = 0
	st.border_color = Color(0.53, 0.83, 0.50, 0.85)
	st.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", st)
	return panel


func populate_results_ui(stage: Node3D, rankings: Array, reason: String) -> void:
	var results_rows: VBoxContainer = stage._results_rows
	var results_title: Label = stage._results_title
	var results_subtitle: Label = stage._results_subtitle
	var results_panel: PanelContainer = stage._results_panel
	if results_rows == null or results_panel == null:
		return
	for child in results_rows.get_children():
		child.queue_free()

	results_title.text = "ROUND SUMMARY // 本局排名"
	results_subtitle.text = reason
	for r in rankings:
		var is_alive := bool(r["alive"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var rk := Label.new()
		rk.custom_minimum_size.x = 46
		rk.text = "#%d" % int(r["rank"])
		rk.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
		rk.add_theme_font_size_override("font_size", 17)
		row.add_child(rk)

		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text = str(r["nickname"]) + ("  [存活]" if is_alive else "  [淘汰]")
		nm.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90) if is_alive else Color(0.66, 0.44, 0.44))
		nm.add_theme_font_size_override("font_size", 17)
		row.add_child(nm)

		var dg := Label.new()
		dg.custom_minimum_size.x = 110
		dg.text = "躲避 %d 次" % int(r["dodges"])
		dg.add_theme_color_override("font_color", Color(0.84, 0.90, 0.82))
		dg.add_theme_font_size_override("font_size", 17)
		row.add_child(dg)

		var bn := Label.new()
		bn.custom_minimum_size.x = 155
		bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bn.text = "原始分 +%d" % int(r["bonus"])
		bn.add_theme_color_override("font_color", Color(0.53, 0.83, 0.50))
		bn.add_theme_font_size_override("font_size", 17)
		row.add_child(bn)

		results_rows.add_child(row)

	results_panel.visible = true


func step_countdown_overlay(stage: Node3D) -> void:
	var countdown: float = float(stage._countdown)
	var countdown_sec: float = float(stage.COUNTDOWN_SECONDS)
	var round_banner: Control = stage._round_banner
	var round_tagline_label: Label = stage._round_tagline_label
	var countdown_label: Label = stage._countdown_label
	var go_label: Label = stage._go_label
	var sfx_ding: AudioStreamPlayer = stage._sfx_ding
	var sfx_countdown: AudioStreamPlayer = stage._sfx_countdown

	if round_banner != null and round_banner.visible:
		if countdown > 2.4:
			round_banner.modulate.a = 1.0
			round_tagline_label.visible_ratio = clampf((countdown_sec - countdown) / 0.50, 0.0, 1.0)
		elif countdown > 1.9:
			round_tagline_label.visible_ratio = 1.0
			round_banner.modulate.a = clampf((countdown - 1.9) / 0.50, 0.0, 1.0)
		else:
			round_banner.visible = false

	if countdown <= 2.3 and not bool(stage._you_marker_shown):
		stage._you_marker_shown = true
		stage._you_marker_timer = 3.15
		if sfx_ding != null and str(stage._screenshot_path).is_empty():
			sfx_ding.play()

	if countdown > 0.0:
		var cur_ceil := ceili(countdown)
		countdown_label.text = str(cur_ceil)
		countdown_label.visible = true
		countdown_label.modulate.a = 0.0 if countdown > 2.0 else 1.0
		if cur_ceil != int(stage._last_countdown_ceil) and cur_ceil > 0:
			stage._last_countdown_ceil = cur_ceil
			if cur_ceil <= 2 and sfx_countdown != null and str(stage._screenshot_path).is_empty():
				sfx_countdown.pitch_scale = 0.6
				sfx_countdown.play()
	else:
		countdown_label.visible = false
		if go_label != null:
			go_label.text = stage._loc_or("LOC_IM_GO", "GO!")
			go_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			go_label.position.y = 28.0
			go_label.show()
			stage._go_timer = 0.55
		if sfx_countdown != null and str(stage._screenshot_path).is_empty():
			sfx_countdown.pitch_scale = 0.8
			sfx_countdown.play()


func update_you_marker(stage: Node3D, delta: float) -> void:
	var you_marker = stage._you_marker
	if you_marker == null:
		return
	if float(stage._you_marker_timer) <= 0.0:
		if bool(you_marker.active):
			you_marker.active = false
			you_marker.visible = false
		return
	stage._you_marker_timer = maxf(0.0, float(stage._you_marker_timer) - delta)
	var lp: Dictionary = stage._find_local_player()
	var cam := stage.get_node_or_null("StageCamera") as Camera3D
	if lp.is_empty() or not bool(lp.get("alive", false)) or cam == null or bool(stage._match_ended) or float(stage._countdown) > 2.3:
		you_marker.active = false
		you_marker.visible = false
		return
	var px := float(lp["x"])
	var py := float(lp["y"]) + (lp["visual"] as Node3D).position.y
	var pz := float(lp["z"])
	var h := 0.85 if bool(lp["crouching"]) else 1.55
	var center := Vector3(px, py + h * 0.5, pz)
	var half := Vector3(0.40, h * 0.52, 0.40)
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var wp := center + Vector3(sx * half.x, sy * half.y, sz * half.z)
				if cam.is_position_behind(wp):
					you_marker.visible = false
					return
				var sp := cam.unproject_position(wp)
				min_pt.x = minf(min_pt.x, sp.x)
				min_pt.y = minf(min_pt.y, sp.y)
				max_pt.x = maxf(max_pt.x, sp.x)
				max_pt.y = maxf(max_pt.y, sp.y)
	you_marker.top_left = min_pt
	you_marker.bound_size = max_pt - min_pt
	var jitter_step := int(floor(float(stage._cam_sway_time) * 15.0)) % 4
	var jitters := [Vector2(0.5, 0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5)]
	you_marker.shake_offset = jitters[jitter_step]
	you_marker.active = true
	you_marker.visible = true
	you_marker.queue_redraw()
