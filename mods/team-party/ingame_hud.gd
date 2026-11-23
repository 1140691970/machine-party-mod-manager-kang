extends RefCounted

## Top-right frameless team status HUD and native custom-minigame stage tracking.

var tp: Node


func _init(owner: Node) -> void:
	tp = owner


func ensure_hud() -> void:
	if not tp.is_inside_tree():
		return
	if is_instance_valid(tp._hud_layer) and is_instance_valid(tp._hud_panel):
		return
	var layer := CanvasLayer.new()
	layer.name = "TeamPartyHudLayer"
	layer.layer = 20
	tp.add_child(layer)
	tp._hud_layer = layer

	var panel := PanelContainer.new()
	panel.name = "TeamPartyHudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -20.0
	panel.offset_left = -20.0
	panel.offset_top = 14.0
	layer.add_child(panel)
	tp._hud_panel = panel

	var rows := HBoxContainer.new()
	rows.name = "TeamHudRows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 18)
	panel.add_child(rows)
	tp._hud_rows = rows


func hide_hud() -> void:
	if is_instance_valid(tp._hud_panel):
		tp._hud_panel.visible = false
	if is_instance_valid(tp._hud_layer):
		tp._hud_layer.visible = false


func record_team_win(scores: Dictionary, stage_node: Node = null) -> void:
	if not tp._reg.is_team_mode_active() or scores.is_empty():
		return
	if stage_node != null and is_instance_valid(stage_node):
		if bool(stage_node.get_meta(&"mpm_hud_win_recorded", false)):
			return
		stage_node.set_meta(&"mpm_hud_win_recorded", true)
	var team_best: Dictionary = {}
	var best_score: int = -999999
	for raw_nid in scores.keys():
		var tid: int = tp._reg.get_team(int(raw_nid))
		if tid <= 0:
			continue
		var sc: int = int(scores[raw_nid])
		team_best[tid] = maxi(int(team_best.get(tid, -999999)), sc)
		best_score = maxi(best_score, sc)
	if team_best.is_empty():
		return
	for raw_tid in team_best.keys():
		if int(team_best[raw_tid]) == best_score:
			var tid: int = int(raw_tid)
			tp._hud_wins[tid] = int(tp._hud_wins.get(tid, 0)) + 1
	tp._assign.broadcast_teams()
	refresh_hud(true)


func _gather_hud_teams() -> Dictionary:
	var stats: Dictionary = {} # tid -> {total, alive, trapped}
	var seen_nids: Dictionary = {}

	if is_instance_valid(tp._current_stage_node) and tp._current_stage_node.is_inside_tree() and (&"_players" in tp._current_stage_node):
		var raw_ps = tp._current_stage_node.get("_players")
		var items: Array = []
		if raw_ps is Dictionary:
			items = (raw_ps as Dictionary).values()
		elif raw_ps is Array:
			items = raw_ps as Array
		for p_raw in items:
			if not (p_raw is Dictionary):
				continue
			var p: Dictionary = p_raw as Dictionary
			var nid: int = int(p.get("network_id", 0))
			var tid: int = tp._reg.get_team(nid)
			if tid <= 0:
				continue
			seen_nids[nid] = true
			if not stats.has(tid):
				stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
			var st: Dictionary = stats[tid]
			st["total"] = int(st["total"]) + 1
			if bool(p.get("alive", false)):
				if bool(p.get("trapped", false)):
					st["trapped"] = int(st["trapped"]) + 1
				else:
					st["alive"] = int(st["alive"]) + 1

	if stats.is_empty() and is_instance_valid(tp.current_minigame) and tp.current_minigame.is_inside_tree():
		var ap = tp.current_minigame.get("active_players") if (&"active_players" in tp.current_minigame) else null
		if ap is Dictionary:
			for raw_k in (ap as Dictionary).keys():
				seen_nids[int(raw_k)] = true
				var tid: int = tp._reg.get_team(int(raw_k))
				if tid > 0:
					if not stats.has(tid):
						stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
					var st: Dictionary = stats[tid]
					st["total"] = int(st["total"]) + 1
					st["alive"] = int(st["alive"]) + 1
		var dp = tp.current_minigame.get("dead_players") if (&"dead_players" in tp.current_minigame) else null
		if dp is Array:
			for raw_k in (dp as Array):
				var nid: int = int(raw_k)
				if seen_nids.has(nid):
					continue
				seen_nids[nid] = true
				var tid: int = tp._reg.get_team(nid)
				if tid > 0:
					if not stats.has(tid):
						stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
					var st: Dictionary = stats[tid]
					st["total"] = int(st["total"]) + 1

	if not tp._tracked_actors.is_empty():
		for rec in tp._tracked_actors.values():
			var actor = rec.get("actor", null)
			if actor == null or not is_instance_valid(actor):
				continue
			var nid: int = int(rec.get("nid", 0))
			if seen_nids.has(nid):
				continue
			var tid: int = tp._reg.get_team(nid)
			if tid <= 0:
				continue
			seen_nids[nid] = true
			if not stats.has(tid):
				stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
			var st: Dictionary = stats[tid]
			st["total"] = int(st["total"]) + 1
			var is_alive: bool = (actor as Node3D).visible and (not bool(rec.get("has_active", false)) or bool((actor as Object).get(&"active")))
			if is_alive:
				st["alive"] = int(st["alive"]) + 1

	if stats.is_empty():
		for raw_nid in tp.teams.keys():
			var tid: int = tp._reg.get_team(int(raw_nid))
			if tid > 0:
				if not stats.has(tid):
					stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
				var st: Dictionary = stats[tid]
				st["total"] = int(st["total"]) + 1
				st["alive"] = int(st["alive"]) + 1
	return stats


func hud_team_short_label(tid: int) -> String:
	var is_tw: bool = tp._reg.is_tw_locale()
	var is_cn: bool = tp._reg.is_cn_locale()
	match tid:
		1: return "紅" if is_tw else ("红" if is_cn else "RED")
		2: return "藍" if is_tw else ("蓝" if is_cn else "BLU")
		3: return "綠" if is_tw else ("绿" if is_cn else "GRN")
		4: return "黃" if is_tw else ("黄" if is_cn else "YEL")
		_: return "?"


func refresh_hud(force: bool = false) -> void:
	var in_lobby: bool = is_instance_valid(tp.lobby) and tp.lobby.is_inside_tree()
	var is_cutscene: bool = (
		is_instance_valid(tp.game)
		and tp.game.has_method("is_current_game_cutscene")
		and bool(tp.game.call("is_current_game_cutscene"))
	)
	var in_match: bool = (
		(is_instance_valid(tp.current_minigame) and tp.current_minigame.is_inside_tree() and not tp._vanilla.is_skipped_scene_node(tp.current_minigame))
		or (is_instance_valid(tp._current_stage_node) and tp._current_stage_node.is_inside_tree())
	)
	if not tp._reg.is_team_mode_active() or in_lobby or is_cutscene or not in_match:
		hide_hud()
		return
	ensure_hud()
	if not is_instance_valid(tp._hud_panel) or not is_instance_valid(tp._hud_rows):
		return
	tp._hud_layer.visible = true
	tp._hud_panel.visible = true

	var stats: Dictionary = _gather_hud_teams()
	var keys: Array = stats.keys()
	keys.sort()
	var my_tid: int = tp._reg.get_team(tp._assign.local_peer_id())
	var sig_parts: PackedStringArray = PackedStringArray()
	for tid_v in keys:
		var tid: int = int(tid_v)
		var st: Dictionary = stats[tid]
		sig_parts.append("%d:%d:%d:%d:%d" % [
			tid, int(st["alive"]), int(st["trapped"]), int(st["total"]), int(tp._hud_wins.get(tid, 0))
		])
	var sig: String = "%s|%d|%s" % [TranslationServer.get_locale(), my_tid, ",".join(sig_parts)]
	if not force and sig == tp._last_hud_sig:
		return
	tp._last_hud_sig = sig

	for child in tp._hud_rows.get_children():
		tp._hud_rows.remove_child(child)
		child.queue_free()

	for tid_v in keys:
		var tid: int = int(tid_v)
		var st: Dictionary = stats[tid]
		var tcol: Color = tp._reg.get_team_color(tid)
		var total: int = int(st["total"])
		var alive_n: int = int(st["alive"])
		var trapped_n: int = int(st["trapped"])
		var dead_n: int = maxi(0, total - alive_n - trapped_n)
		var team_alive: bool = (alive_n + trapped_n) > 0

		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 6)
		tp._hud_rows.add_child(item)

		if tid == my_tid:
			var me_lbl := Label.new()
			me_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			me_lbl.text = "▶"
			tp._ui.style_outline_label(me_lbl, Color.WHITE, 20, 5)
			item.add_child(me_lbl)

		var name_lbl := Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.text = hud_team_short_label(tid)
		tp._ui.style_outline_label(name_lbl, tcol if team_alive else Color(tcol.r, tcol.g, tcol.b, 0.45), 20, 5)
		item.add_child(name_lbl)

		var pip_str: String = ""
		for _i in range(alive_n):
			pip_str += "●"
		for _i in range(trapped_n):
			pip_str += "◎"
		for _i in range(dead_n):
			pip_str += "○"
		var pips_lbl := Label.new()
		pips_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips_lbl.text = pip_str
		tp._ui.style_outline_label(pips_lbl, tcol if team_alive else Color(0.54, 0.58, 0.62, 0.68), 20, 5)
		item.add_child(pips_lbl)

		var wins: int = int(tp._hud_wins.get(tid, 0))
		if wins > 0:
			var win_lbl := Label.new()
			win_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			win_lbl.text = "★%d" % wins
			tp._ui.style_outline_label(win_lbl, Color(1.0, 0.86, 0.28), 20, 5)
			item.add_child(win_lbl)


func on_stage_exiting(node: Node) -> void:
	if tp._current_stage_node == node:
		tp._current_stage_node = null
	tp._last_hud_sig = ""
	refresh_hud(true)


func register_native_team_stage(stage: Node) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	tp._current_stage_node = stage
	var exit_cb := Callable(tp, "_on_stage_exiting").bind(stage)
	if not stage.tree_exiting.is_connected(exit_cb):
		stage.tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)
	refresh_hud(true)


func step_hud(delta: float) -> void:
	tp._hud_refresh_accum += delta
	if tp._hud_refresh_accum >= 0.16:
		tp._hud_refresh_accum = 0.0
		refresh_hud(false)
