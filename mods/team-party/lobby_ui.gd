extends RefCounted

## Lobby CRT team selector panel, swap request banner, UI sound effects, and text formatting.

var tp: Node


func _init(owner: Node) -> void:
	tp = owner


func make_crt_panel_style(_border_col: Color = Color.WHITE, _bg_col: Color = Color.BLACK) -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func style_outline_label(lbl: Label, col: Color = Color.WHITE, font_sz: int = 16, outline_sz: int = 5) -> void:
	var f: Font = tp._reg.get_ui_font()
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	lbl.add_theme_constant_override("outline_size", outline_sz)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


func style_crt_button(btn: Button, _accent: Color = Color.WHITE, highlighted: bool = false, font_sz: int = 20) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	var f: Font = tp._reg.get_ui_font()
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", font_sz)

	var normal := StyleBoxFlat.new()
	normal.set_border_width_all(2)
	normal.corner_detail = 1
	normal.anti_aliasing = false
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color.WHITE
	hover.border_color = Color.WHITE

	var disabled_sb := normal.duplicate() as StyleBoxFlat
	disabled_sb.bg_color = Color(0.0, 0.0, 0.0, 0.32)
	disabled_sb.border_color = Color(0.8, 0.8, 0.8, 0.33)

	if highlighted:
		normal.bg_color = Color.WHITE
		normal.border_color = Color.WHITE
		btn.add_theme_color_override("font_color", Color.BLACK)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		btn.add_theme_color_override("font_pressed_color", Color.BLACK)
	else:
		normal.bg_color = Color.BLACK
		normal.border_color = Color.WHITE
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		btn.add_theme_color_override("font_pressed_color", Color.BLACK)
	btn.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.36))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled_sb)


func play_ui_click() -> void:
	if tp._sfx_ui_click == null and ResourceLoader.exists("res://audio/menu click.ogg"):
		var s = ResourceLoader.load("res://audio/menu click.ogg")
		if s is AudioStream:
			tp._sfx_ui_click = s as AudioStream
	if tp._sfx_ui_click != null and tp.is_inside_tree():
		if tp._sfx_ui_player == null or not is_instance_valid(tp._sfx_ui_player):
			tp._sfx_ui_player = AudioStreamPlayer.new()
			tp._sfx_ui_player.name = "TeamPartyClickSfx"
			tp.add_child(tp._sfx_ui_player)
		tp._sfx_ui_player.stream = tp._sfx_ui_click
		tp._sfx_ui_player.pitch_scale = randf_range(0.95, 1.05)
		tp._sfx_ui_player.play()


func notify_lobby_terminal(msg: String) -> void:
	if not is_instance_valid(tp.lobby):
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler != null and handler.has_method("send_lobby_message"):
		handler.call("send_lobby_message", msg)


func setup_lobby_panel() -> void:
	if not is_instance_valid(tp.lobby):
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or handler.get("root") == null:
		return
	var root_ctrl: Control = handler.root

	var p := PanelContainer.new()
	p.name = "TeamPartyPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", make_crt_panel_style())
	p.anchor_left = 0.0
	p.anchor_right = 0.0
	p.anchor_top = 0.0
	p.anchor_bottom = 0.0
	p.offset_left = 24.0
	p.offset_top = 24.0
	p.offset_right = 24.0
	p.offset_bottom = 24.0
	root_ctrl.add_child(p)
	tp.panel = p

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 5)
	p.add_child(vbox)

	var fmt_bar := HBoxContainer.new()
	fmt_bar.name = "FormatBar"
	fmt_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fmt_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(fmt_bar)

	tp._format_buttons.clear()
	var fmt_defs := [
		[tp.FORMAT_FFA, tp._reg.label("OFF", "关", "關")],
		[tp.FORMAT_DUO, tp._reg.label("2/TEAM", "2人队", "2人隊")],
		[tp.FORMAT_SQUAD, tp._reg.label("4/TEAM", "4人队", "4人隊")],
		[tp.FORMAT_CUSTOM, tp._reg.label("FREE", "自由", "自由")],
	]
	for fd in fmt_defs:
		var fcode: int = int(fd[0])
		var fbtn := Button.new()
		fbtn.name = "FormatBtn_%d" % fcode
		fbtn.text = str(fd[1])
		fbtn.pressed.connect(Callable(tp, "_on_format_button_pressed").bind(fcode))
		style_crt_button(fbtn, Color.WHITE, false, 20)
		fmt_bar.add_child(fbtn)
		tp._format_buttons[fcode] = fbtn

	var actions := HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 5)
	vbox.add_child(actions)
	tp._actions_row = actions

	var shuf := Button.new()
	shuf.name = "ShuffleTeamsButton"
	shuf.text = tp._reg.label("SHUFFLE", "随机分队", "隨機分隊")
	shuf.pressed.connect(Callable(tp, "_on_shuffle_pressed"))
	style_crt_button(shuf, Color.WHITE, false, 20)
	actions.add_child(shuf)
	tp.shuffle_button = shuf

	var mode_btn := Button.new()
	mode_btn.name = "TeamModeButton"
	mode_btn.pressed.connect(Callable(tp, "_on_custom_count_pressed"))
	style_crt_button(mode_btn, Color.WHITE, false, 20)
	actions.add_child(mode_btn)
	tp.mode_button = mode_btn

	var my_btn := Button.new()
	my_btn.name = "MyTeamButton"
	my_btn.visible = false
	my_btn.pressed.connect(Callable(tp, "_on_my_team_pressed"))
	style_crt_button(my_btn, Color.WHITE, false, 20)
	actions.add_child(my_btn)
	tp.my_team_button = my_btn

	var hint := Label.new()
	hint.name = "TeamChairHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_outline_label(hint, Color.WHITE, 16, 5)
	vbox.add_child(hint)
	tp._hint_label = hint

	var swap_row := HBoxContainer.new()
	swap_row.name = "SwapOfferRow"
	swap_row.visible = false
	swap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swap_row.add_theme_constant_override("separation", 6)
	vbox.add_child(swap_row)
	tp._swap_offer_row = swap_row

	var swap_lbl := Label.new()
	swap_lbl.name = "SwapOfferLabel"
	swap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_outline_label(swap_lbl, Color(1.0, 0.92, 0.45), 16, 5)
	swap_row.add_child(swap_lbl)
	tp._swap_offer_label = swap_lbl

	var acc := Button.new()
	acc.name = "SwapAcceptButton"
	acc.text = tp._reg.label("ACCEPT", "同意", "同意")
	acc.pressed.connect(Callable(tp, "_on_swap_accept_pressed"))
	style_crt_button(acc, Color.WHITE, true, 18)
	swap_row.add_child(acc)
	tp._swap_accept_btn = acc

	var dec := Button.new()
	dec.name = "SwapDeclineButton"
	dec.text = tp._reg.label("DECLINE", "拒绝", "拒絕")
	dec.pressed.connect(Callable(tp, "_on_swap_decline_pressed"))
	style_crt_button(dec, Color.WHITE, false, 18)
	swap_row.add_child(dec)
	tp._swap_decline_btn = dec

	var member_rows := VBoxContainer.new()
	member_rows.name = "TeamMemberRows"
	member_rows.visible = false
	vbox.add_child(member_rows)
	tp.rows = member_rows

	if handler.has_signal("start_pressed") and not handler.start_pressed.is_connected(Callable(tp, "_lock_for_game")):
		handler.start_pressed.connect(Callable(tp, "_lock_for_game"))
	if handler.has_signal("back_pressed") and not handler.back_pressed.is_connected(Callable(tp, "_reset_lobby_state")):
		handler.back_pressed.connect(Callable(tp, "_reset_lobby_state"))

	refresh_lobby_ui()


func format_summary_text(n: int) -> String:
	if tp.team_count < 2:
		return tp._reg.label("FREE-FOR-ALL", "各自为战", "各自為戰")
	var counts: Array[String] = []
	for t in range(1, tp.team_count + 1):
		var c: int = 0
		for raw_id in tp.teams.keys():
			if int(tp.teams[raw_id]) == t:
				c += 1
		if c > 0:
			counts.append(str(c))
	var split_tag: String = "v".join(counts) if not counts.is_empty() else ("%d TEAMS" % tp.team_count)
	match tp.team_format:
		tp.FORMAT_DUO:
			return tp._reg.label("2 PER TEAM (%s)" % split_tag, "2人一队 (%d人 · %s)" % [n, split_tag], "2人一隊 (%d人 · %s)" % [n, split_tag])
		tp.FORMAT_SQUAD:
			return tp._reg.label("4 PER TEAM (%s)" % split_tag, "红蓝大对抗 (%d人 · %s)" % [n, split_tag], "紅藍大對抗 (%d人 · %s)" % [n, split_tag])
		tp.FORMAT_TRIO:
			return tp._reg.label("3 PER TEAM (%s)" % split_tag, "3人一队 (%d人 · %s)" % [n, split_tag], "3人一隊 (%d人 · %s)" % [n, split_tag])
		_:
			return tp._reg.label("%d TEAMS (%s)" % [tp.team_count, split_tag], "自由组队 %d队 (%s)" % [tp.team_count, split_tag], "自由組隊 %d隊 (%s)" % [tp.team_count, split_tag])


func mode_button_text() -> String:
	var n: int = tp._assign.collect_lobby_participants().size()
	if tp.team_count < 2:
		return tp._reg.label("Teams: Off (Free-for-All)", "当前：个人混战 (点击切 2 队)", "目前：個人混戰 (點擊切 2 隊)")
	return format_summary_text(n)


func split_badge_text(participants: Array[Dictionary]) -> String:
	if tp.team_count < 2:
		return tp._reg.label("OFF", "关", "關")
	var counts: Array[String] = []
	for t in range(1, tp.team_count + 1):
		var c: int = 0
		for p in participants:
			if tp._reg.get_team(int(p["id"])) == t:
				c += 1
		if c > 0:
			counts.append(str(c))
	if not counts.is_empty():
		return "v".join(counts)
	return "%dT" % tp.team_count


func refresh_lobby_ui() -> void:
	if not is_instance_valid(tp.panel):
		return
	var is_host: bool = tp._assign.is_host_authoritative()
	var participants: Array[Dictionary] = tp._assign.collect_lobby_participants()
	var active_teams: bool = tp.team_count >= 2

	var fmt_bar := tp.panel.find_child("FormatBar", true, false) as HBoxContainer
	if fmt_bar != null:
		fmt_bar.visible = is_host

	for fcode_raw in tp._format_buttons.keys():
		var fcode: int = int(fcode_raw)
		var fbtn: Button = tp._format_buttons[fcode_raw] as Button
		if is_instance_valid(fbtn):
			var is_sel: bool = (tp.team_format == fcode) or (tp.team_count == 0 and fcode == tp.FORMAT_FFA)
			fbtn.disabled = not is_host or tp.locked
			style_crt_button(fbtn, Color.WHITE, is_sel, 20)

	if is_instance_valid(tp._actions_row):
		tp._actions_row.visible = active_teams and is_host
	if is_instance_valid(tp.shuffle_button):
		tp.shuffle_button.visible = active_teams and is_host
		tp.shuffle_button.disabled = tp.locked
		style_crt_button(tp.shuffle_button, Color.WHITE, false, 20)
	if is_instance_valid(tp.mode_button):
		tp.mode_button.visible = active_teams and is_host and tp.team_format == tp.FORMAT_CUSTOM
		tp.mode_button.disabled = tp.locked
		tp.mode_button.text = "%d%s" % [tp.team_count, tp._reg.label(" TEAMS", "队", "隊")]
		style_crt_button(tp.mode_button, Color.WHITE, false, 20)
	if is_instance_valid(tp.my_team_button):
		tp.my_team_button.visible = false

	if is_instance_valid(tp._hint_label):
		if active_teams:
			tp._hint_label.visible = true
			if is_host:
				tp._hint_label.text = "%s · %s" % [
					split_badge_text(participants),
					tp._reg.label("DRAG WORKER TO MOVE / CLICK CHAIR", "拖拽人物换椅 / 点击入座", "拖曳人物換椅 / 點擊入座"),
				]
			else:
				tp._hint_label.text = "%s (%s) · %s" % [
					tp._reg.label("SQUADS", "组队", "組隊"),
					split_badge_text(participants),
					tp._reg.label("CLICK EMPTY CHAIR / CLICK PLAYER TO SWAP", "点击空椅入座 / 点击玩家请求换位", "點擊空椅入座 / 點擊玩家請求換位"),
				]
			style_outline_label(tp._hint_label, Color.WHITE, 16, 5)
		else:
			tp._hint_label.visible = false

	if is_instance_valid(tp._swap_offer_row):
		var show_offer: bool = active_teams and not tp.locked and tp._incoming_swap_from > 0
		tp._swap_offer_row.visible = show_offer
		if show_offer:
			if is_instance_valid(tp._swap_offer_label):
				tp._swap_offer_label.text = tp._reg.label(
					"%s WANTS TO SWAP" % tp._incoming_swap_name,
					"%s 请求与你换位" % tp._incoming_swap_name,
					"%s 請求與你換位" % tp._incoming_swap_name
				)
				style_outline_label(tp._swap_offer_label, Color(1.0, 0.92, 0.45), 16, 5)
			if is_instance_valid(tp._swap_accept_btn):
				style_crt_button(tp._swap_accept_btn, Color.WHITE, true, 18)
			if is_instance_valid(tp._swap_decline_btn):
				style_crt_button(tp._swap_decline_btn, Color.WHITE, false, 18)


func short_team_code(tid: int) -> String:
	var is_tw: bool = tp._reg.is_tw_locale()
	var is_cn: bool = tp._reg.is_cn_locale()
	match tid:
		1: return "■紅" if is_tw else ("■红" if is_cn else "RED")
		2: return "■藍" if is_tw else ("■蓝" if is_cn else "BLU")
		3: return "■綠" if is_tw else ("■绿" if is_cn else "GRN")
		4: return "■黃" if is_tw else ("■黄" if is_cn else "YEL")
		_: return "■"
