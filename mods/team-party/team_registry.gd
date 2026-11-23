extends RefCounted

## Team registry, color/name localization, roster sorting, and Squads score synchronization.

var tp: Node


func _init(owner: Node) -> void:
	tp = owner


func get_cjk_badge_font() -> Font:
	if tp._cjk_badge_font == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray([
			"PingFang TC", "PingFang SC", "Microsoft JhengHei", "Microsoft YaHei",
			"Noto Sans CJK TC", "Heiti TC", "Helvetica Neue", "Arial",
		])
		if not tp._crt_font_checked:
			tp._crt_font_checked = true
			if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
				var f = ResourceLoader.load("res://fonts/Terminal F4.ttf")
				if f is Font:
					var fv := FontVariation.new()
					fv.base_font = f as Font
					fv.fallbacks = [sys]
					tp._crt_font = fv
		tp._cjk_badge_font = tp._crt_font if tp._crt_font != null else sys
	return tp._cjk_badge_font


func get_ui_font() -> Font:
	return get_cjk_badge_font()


func is_tw_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo")


func is_cn_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return not is_tw_locale(low) and (low.begins_with("zh") or low == "zhs")


func is_player_spotlight_enabled() -> bool:
	if not Engine.has_meta(&"mpm_player_spotlight_active") or not bool(Engine.get_meta(&"mpm_player_spotlight_active")):
		return false
	if tp.get_tree() != null and tp.get_tree().root != null:
		var spot := tp.get_tree().root.get_node_or_null("ModLoader/player-spotlight")
		if spot != null and (&"enabled" in spot):
			return bool(spot.get(&"enabled"))
	return true


func publish_state() -> void:
	tp._shared_state["enabled"] = is_team_mode_active()
	tp._shared_state["team_count"] = tp.team_count
	tp._shared_state["team_format"] = tp.team_format
	tp._shared_state["teams"] = tp.teams
	tp._shared_state["node"] = tp
	Engine.set_meta(tp.META_KEY, tp._shared_state)
	if Engine.has_meta(&"mpm_core"):
		var core_meta = Engine.get_meta(&"mpm_core")
		if core_meta is Dictionary:
			var bus = (core_meta as Dictionary).get("event_bus", null)
			if bus != null and bus.has_method("emit_event"):
				bus.emit_event("team_party.state_changed", {
					"enabled": is_team_mode_active(),
					"team_count": tp.team_count,
					"team_format": tp.team_format,
				})


func label(en: String, cn: String, tw: String) -> String:
	var locale: String = TranslationServer.get_locale()
	if is_tw_locale(locale):
		return tw
	if is_cn_locale(locale):
		return cn
	return en


func is_team_mode_active() -> bool:
	return tp.team_count >= 2


func get_team(net_id: int) -> int:
	if tp.team_count < 2:
		return 0
	var tid: int = int(tp.teams.get(net_id, 0))
	if tid >= 1 and tid <= tp.team_count:
		return tid
	return 0


func are_teammates(id_a: int, id_b: int) -> bool:
	if tp.team_count < 2 or id_a == id_b:
		return false
	var ta: int = get_team(id_a)
	return ta > 0 and ta == get_team(id_b)


func get_team_color(team_id: int) -> Color:
	var defs: Dictionary = tp.TEAM_DEFS
	if defs.has(team_id):
		return (defs[team_id] as Dictionary)["color"] as Color
	return Color.WHITE


func get_team_tag(team_id: int) -> String:
	var defs: Dictionary = tp.TEAM_DEFS
	if not defs.has(team_id):
		return ""
	var d: Dictionary = defs[team_id]
	return label(str(d["tag_en"]), str(d["tag_cn"]), str(d["tag_tw"]))


func get_team_name(team_id: int) -> String:
	var defs: Dictionary = tp.TEAM_DEFS
	if not defs.has(team_id):
		return label("Unassigned", "未分队", "未分隊")
	var d: Dictionary = defs[team_id]
	return label(str(d["name_en"]), str(d["name_cn"]), str(d["name_tw"]))


func strip_team_prefix(text: String) -> String:
	for p in tp.KNOWN_PREFIXES:
		if text.begins_with(p):
			return text.substr(p.length())
	return text


func format_team_nickname(net_id: int, base_name: String) -> String:
	var clean: String = strip_team_prefix(base_name)
	var tid: int = get_team(net_id)
	if tid <= 0:
		return clean
	return "%s %s" % [get_team_tag(tid), clean]


func sort_roster_by_team(roster: Array) -> Array:
	if not is_team_mode_active() or roster.size() <= 1:
		return roster.duplicate()
	var keyed: Array = []
	for i in range(roster.size()):
		var item = roster[i]
		var nid: int = 0
		if item is Dictionary:
			nid = int((item as Dictionary).get("network_id", 0))
		else:
			nid = int(item)
		var tid: int = get_team(nid)
		var sort_team: int = tid if tid > 0 else 999
		keyed.append({"team": sort_team, "idx": i, "item": item})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["team"]) != int(b["team"]):
			return int(a["team"]) < int(b["team"])
		return int(a["idx"]) < int(b["idx"])
	)
	var out: Array = []
	for entry in keyed:
		out.append((entry as Dictionary)["item"])
	return out


func compute_team_synchronized_scores(raw_scores: Dictionary, alive_ids: Array = []) -> Dictionary:
	## Fall Guys Squads-style scoring:
	## - Supports arbitrary/asymmetric team sizes (e.g., 2v2v2v2, 4v4, 3v2v2, 1v3).
	## - Each team's base score = max(member score) ("carry" / best survivor of team).
	## - Teams where every member survived (when alive_ids is non-empty) gain +1 all-alive bonus.
	## - Every member of a team receives the exact same synchronized score.
	if not is_team_mode_active() or raw_scores.is_empty():
		return raw_scores.duplicate()

	var alive_lookup: Dictionary = {}
	for raw_id in alive_ids:
		alive_lookup[int(raw_id)] = true
	var has_alive_info: bool = not alive_lookup.is_empty()

	var eff_teams: Dictionary = {}
	var team_counts: Dictionary = {}
	for t in range(1, tp.team_count + 1):
		team_counts[t] = 0

	var sorted_ids: Array = []
	for raw_nid in raw_scores.keys():
		sorted_ids.append(int(raw_nid))
	sorted_ids.sort()

	for nid in sorted_ids:
		var tid: int = get_team(nid)
		if tid > 0:
			eff_teams[nid] = tid
			team_counts[tid] = int(team_counts.get(tid, 0)) + 1

	for nid in sorted_ids:
		if eff_teams.has(nid):
			continue
		var pick: int = 1
		var best_c: int = 999999
		for t in range(1, tp.team_count + 1):
			var c: int = int(team_counts.get(t, 0))
			if c < best_c:
				best_c = c
				pick = t
		eff_teams[nid] = pick
		team_counts[pick] = int(team_counts.get(pick, 0)) + 1

	var members_by_team: Dictionary = {}
	for nid in sorted_ids:
		var tid: int = int(eff_teams[nid])
		if not members_by_team.has(tid):
			members_by_team[tid] = []
		(members_by_team[tid] as Array).append(nid)

	var team_scores: Dictionary = {}
	for tid_raw in members_by_team.keys():
		var tid: int = int(tid_raw)
		var members: Array = members_by_team[tid]
		var best_score: int = -999999
		var all_alive: bool = has_alive_info and not members.is_empty()
		for nid in members:
			var sc: int = int(raw_scores.get(nid, 0))
			if sc > best_score:
				best_score = sc
			if has_alive_info and not alive_lookup.has(int(nid)):
				all_alive = false
		if best_score < 0:
			best_score = 0
		team_scores[tid] = best_score + (1 if all_alive else 0)

	var out: Dictionary = {}
	for raw_nid in raw_scores.keys():
		var nid: int = int(raw_nid)
		var tid: int = int(eff_teams[nid])
		out[raw_nid] = int(team_scores.get(tid, int(raw_scores[raw_nid])))
	return out


func smallest_team(exclude_id: int = 0) -> int:
	if tp.team_count < 2:
		return 0
	var counts: Dictionary = {}
	for t in range(1, tp.team_count + 1):
		counts[t] = 0
	for raw_id in tp.teams.keys():
		var nid: int = int(raw_id)
		if nid == exclude_id:
			continue
		var t: int = int(tp.teams[raw_id])
		if t >= 1 and t <= tp.team_count:
			counts[t] = int(counts[t]) + 1
	var best_t: int = 1
	var best_c: int = 999999
	for t in range(1, tp.team_count + 1):
		var c: int = int(counts[t])
		if c < best_c:
			best_c = c
			best_t = t
	return best_t


func calc_format_team_count(fmt: int, participant_count: int, total_seats: int) -> int:
	var n: int = maxi(2, maxi(participant_count, total_seats))
	match fmt:
		tp.FORMAT_FFA:
			return 0
		tp.FORMAT_DUO:
			return clampi(ceili(float(n) / 2.0), 2, 4)
		tp.FORMAT_SQUAD:
			return 2
		tp.FORMAT_TRIO:
			return clampi(ceili(float(n) / 3.0), 2, 4)
		tp.FORMAT_CUSTOM:
			return tp.team_count if tp.team_count >= 2 else (4 if n >= 7 else (3 if n >= 5 else 2))
		_:
			return 2


func team_capacity() -> int:
	match tp.team_format:
		tp.FORMAT_DUO:
			return 2
		tp.FORMAT_SQUAD:
			return 4
		tp.FORMAT_TRIO:
			return 3
		_:
			return 0


func seat_zone_team(seat_idx: int, total_seats: int) -> int:
	if tp.team_count < 2 or seat_idx < 0:
		return 0
	var n_seats: int = maxi(2, total_seats)
	match tp.team_format:
		tp.FORMAT_DUO:
			return clampi((seat_idx / 2) + 1, 1, tp.team_count)
		tp.FORMAT_SQUAD:
			var half: int = ceili(float(n_seats) / 2.0)
			return 1 if seat_idx < half else 2
		tp.FORMAT_TRIO:
			return clampi((seat_idx / 3) + 1, 1, tp.team_count)
		_:
			return clampi((seat_idx * tp.team_count) / n_seats + 1, 1, tp.team_count)
