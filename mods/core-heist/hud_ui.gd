extends RefCounted

## HUD overlay for Core Heist: team score bar, countdown timer, phase alerts, resonance status.

var _layer: CanvasLayer = null
var _top_label: Label = null
var _timer_label: Label = null
var _banner_label: Label = null
var _resonance_label: Label = null
var _results_panel: PanelContainer = null
var _results_label: Label = null
var _hint_label: Label = null
var _banner_timer: float = 0.0


static func pick_loc(en: String, cn: String, tw: String) -> String:
	var low: String = TranslationServer.get_locale().to_lower()
	if low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo"):
		return tw
	if low.begins_with("zh") or low == "zhs":
		return cn
	return en


static func team_name(tid: int) -> String:
	match tid:
		1: return pick_loc("RED", "红队", "紅隊")
		2: return pick_loc("BLU", "蓝队", "藍隊")
		3: return pick_loc("GRN", "绿队", "綠隊")
		4: return pick_loc("YEL", "黄队", "黃隊")
		_: return "T%d" % tid


static func draw_banner() -> String:
	return pick_loc("DRAW!", "平局!", "平手!")


func build_hud(parent: Node, team_helper = null) -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	var ui_font: Font = null
	if team_helper != null and team_helper.has_method("tp_font"):
		ui_font = team_helper.call("tp_font") as Font
	if ui_font == null and ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
		ui_font = ResourceLoader.load("res://fonts/Terminal F4.ttf") as Font
	var num_font: Font = null
	if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
		num_font = ResourceLoader.load("res://fonts/Terminal F4.ttf") as Font

	_layer = CanvasLayer.new()
	_layer.name = "CoreHeistHud"
	_layer.layer = 10
	parent.add_child(_layer)

	var top_panel := PanelContainer.new()
	top_panel.anchor_left = 0.5
	top_panel.anchor_right = 0.5
	top_panel.anchor_top = 0.0
	top_panel.offset_left = -360.0
	top_panel.offset_right = 360.0
	top_panel.offset_top = 12.0
	top_panel.offset_bottom = 64.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.86)
	sb.border_color = Color(0.28, 0.72, 0.92, 0.78)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	top_panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(top_panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	top_panel.add_child(hbox)

	_top_label = Label.new()
	_top_label.add_theme_font_size_override("font_size", 20)
	if ui_font != null:
		_top_label.add_theme_font_override("font", ui_font)
	_top_label.text = "CORE HEIST"
	hbox.add_child(_top_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 24)
	if num_font != null:
		_timer_label.add_theme_font_override("font", num_font)
	_timer_label.modulate = Color(1.0, 0.90, 0.35)
	_timer_label.text = "75s"
	hbox.add_child(_timer_label)

	_banner_label = Label.new()
	_banner_label.anchor_left = 0.5
	_banner_label.anchor_right = 0.5
	_banner_label.anchor_top = 0.0
	_banner_label.offset_left = -380.0
	_banner_label.offset_right = 380.0
	_banner_label.offset_top = 82.0
	_banner_label.offset_bottom = 132.0
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 28)
	if ui_font != null:
		_banner_label.add_theme_font_override("font", ui_font)
	_banner_label.modulate = Color(1.0, 0.88, 0.35)
	_banner_label.visible = false
	_layer.add_child(_banner_label)

	_resonance_label = Label.new()
	_resonance_label.anchor_left = 0.5
	_resonance_label.anchor_right = 0.5
	_resonance_label.anchor_bottom = 1.0
	_resonance_label.anchor_top = 1.0
	_resonance_label.offset_left = -260.0
	_resonance_label.offset_right = 260.0
	_resonance_label.offset_top = -54.0
	_resonance_label.offset_bottom = -18.0
	_resonance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resonance_label.add_theme_font_size_override("font_size", 20)
	if ui_font != null:
		_resonance_label.add_theme_font_override("font", ui_font)
	_resonance_label.modulate = Color(0.35, 0.95, 1.0)
	_resonance_label.visible = false
	_layer.add_child(_resonance_label)

	_results_panel = PanelContainer.new()
	_results_panel.anchor_left = 0.5
	_results_panel.anchor_right = 0.5
	_results_panel.anchor_top = 0.5
	_results_panel.anchor_bottom = 0.5
	_results_panel.offset_left = -220.0
	_results_panel.offset_right = 220.0
	_results_panel.offset_top = -120.0
	_results_panel.offset_bottom = 120.0
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	rsb.border_color = Color(1.0, 0.82, 0.24, 0.90)
	rsb.set_border_width_all(2)
	rsb.set_corner_radius_all(8)
	rsb.content_margin_left = 20.0
	rsb.content_margin_right = 20.0
	rsb.content_margin_top = 16.0
	rsb.content_margin_bottom = 16.0
	_results_panel.add_theme_stylebox_override("panel", rsb)
	_results_panel.visible = false
	_layer.add_child(_results_panel)

	_results_label = Label.new()
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_results_label.add_theme_font_size_override("font_size", 22)
	if ui_font != null:
		_results_label.add_theme_font_override("font", ui_font)
	_results_panel.add_child(_results_label)

	_hint_label = Label.new()
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.offset_left = 14.0
	_hint_label.offset_right = 560.0
	_hint_label.offset_top = -34.0
	_hint_label.offset_bottom = -10.0
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.modulate = Color(0.75, 0.82, 0.90, 0.85)
	if ui_font != null:
		_hint_label.add_theme_font_override("font", ui_font)
	_hint_label.text = pick_loc(
		"[WASD] Move  [Space] Shove / Throw  [R] Restart  [F2-F4] 2-4 Teams",
		"[WASD] 移动  [空格] 推搡/抛投  [R] 重开  [F2-F4] 2-4队",
		"[WASD] 移動  [空白鍵] 推搡/拋投  [R] 重開  [F2-F4] 2-4隊"
	)
	_hint_label.visible = false
	_layer.add_child(_hint_label)


func set_standalone_hint(visible_flag: bool) -> void:
	if _hint_label != null and is_instance_valid(_hint_label):
		_hint_label.visible = visible_flag


func show_results(team_ids: Array, team_scores: Dictionary, winners: Array, is_standalone: bool) -> void:
	if _results_panel == null or not is_instance_valid(_results_panel) or _results_label == null:
		return
	var rows: Array = []
	for raw_tid in team_ids:
		var tid: int = int(raw_tid)
		rows.append({"tid": tid, "score": int(team_scores.get(tid, 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"])
	)
	var lines: Array[String] = []
	if winners.size() > 1:
		lines.append(draw_banner())
	elif winners.size() == 1:
		lines.append("%s %s" % [team_name(int(winners[0])), pick_loc("WINS!", "获胜!", "獲勝!")])
	lines.append("")
	for i in range(rows.size()):
		var r: Dictionary = rows[i] as Dictionary
		lines.append("#%d  %s : %d" % [i + 1, team_name(int(r["tid"])), int(r["score"])])
	if is_standalone:
		lines.append("")
		lines.append(pick_loc("[R] Restart  |  [F2/F3/F4] 2/3/4 Teams", "[R] 重开  |  [F2/F3/F4] 2/3/4 队", "[R] 重開  |  [F2/F3/F4] 2/3/4 隊"))
	_results_label.text = "\n".join(lines)
	_results_panel.visible = true


func hide_results() -> void:
	if _results_panel != null and is_instance_valid(_results_panel):
		_results_panel.visible = false


func show_banner(text: String, color: Color = Color(1.0, 0.88, 0.35), duration: float = 2.4) -> void:
	if _banner_label == null or not is_instance_valid(_banner_label):
		return
	_banner_label.text = text
	_banner_label.modulate = color
	_banner_label.visible = not text.is_empty()
	_banner_timer = duration


func update_hud(team_ids: Array, team_scores: Dictionary, time_remaining: float, phase: int, prep_remaining: float, resonance_active: bool, delta: float) -> void:
	if _top_label == null or not is_instance_valid(_top_label):
		return
	var parts: Array[String] = []
	for raw_tid in team_ids:
		var tid: int = int(raw_tid)
		parts.append("%s: %d" % [team_name(tid), int(team_scores.get(tid, 0))])
	_top_label.text = "  |  ".join(parts)

	if phase == 0:
		_timer_label.text = "%ds" % ceili(maxf(0.0, prep_remaining))
		_timer_label.modulate = Color(0.55, 0.92, 1.0)
	else:
		_timer_label.text = "%ds" % ceili(maxf(0.0, time_remaining))
		_timer_label.modulate = Color(1.0, 0.38, 0.28) if time_remaining <= 15.0 else Color(1.0, 0.90, 0.35)

	if _resonance_label != null and is_instance_valid(_resonance_label):
		_resonance_label.visible = resonance_active
		if resonance_active:
			_resonance_label.text = pick_loc(
				"RESONANCE ACTIVE (1.15x SPEED)",
				"双人电磁共振激活 (1.15x 移速)",
				"雙人電磁共振啟動 (1.15x 移速)"
			)

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and _banner_label != null and is_instance_valid(_banner_label):
			_banner_label.visible = false
