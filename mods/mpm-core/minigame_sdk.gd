extends RefCounted

## MPM Core Minigame SDK — declarative minigame registration & dynamic Hub v2 slot allocation (>= 1000).

const DYNAMIC_SLOT_BASE := 1000

var _event_bus = null
var _locale = null


func _init(bus = null, locale_helper = null) -> void:
	_event_bus = bus
	_locale = locale_helper


func _get_custom_map(loader = null) -> Dictionary:
	var dict: Dictionary = {}
	if loader != null and loader.has_method("registry"):
		var raw = loader.registry("custom_minigames")
		if raw is Dictionary:
			dict = raw
	elif Engine.has_meta("_mpm_custom_minigames"):
		var existing = Engine.get_meta("_mpm_custom_minigames")
		if existing is Dictionary:
			dict = existing
	Engine.set_meta("_mpm_custom_minigames", dict)
	return dict


func _get_hub(loader = null) -> Dictionary:
	var dict: Dictionary = {}
	if loader != null and loader.has_method("registry"):
		var raw = loader.registry("custom_minigames_hub")
		if raw is Dictionary:
			dict = raw
	elif Engine.has_meta("_mpm_custom_minigames_hub"):
		var existing = Engine.get_meta("_mpm_custom_minigames_hub")
		if existing is Dictionary:
			dict = existing
	if not dict.has("dynamic_slots") or not (dict["dynamic_slots"] is Dictionary):
		dict["dynamic_slots"] = {}
	Engine.set_meta("_mpm_custom_minigames_hub", dict)
	return dict


func allocate_slot(mod_id: String, preferred_slot: int = -1, loader = null) -> int:
	if preferred_slot > 0:
		return preferred_slot
	var custom_map: Dictionary = _get_custom_map(loader)
	var hub: Dictionary = _get_hub(loader)
	var dynamic_slots: Dictionary = hub["dynamic_slots"] as Dictionary
	if dynamic_slots.has(mod_id):
		return int(dynamic_slots[mod_id])
	var used: Dictionary = {}
	for k in custom_map.keys():
		used[int(k)] = true
	for v in dynamic_slots.values():
		used[int(v)] = true
	var candidate: int = DYNAMIC_SLOT_BASE
	while used.has(candidate):
		candidate += 1
	dynamic_slots[mod_id] = candidate
	return candidate


func register_minigame(spec: Dictionary, loader = null) -> Dictionary:
	var mod_id: String = str(spec.get("mod_id", "")).strip_edges()
	if mod_id.is_empty():
		return {"ok": false, "error": "missing_mod_id"}
	var custom_map: Dictionary = _get_custom_map(loader)
	var preferred: int = int(spec.get("slot_id", -1))
	var slot_id: int = allocate_slot(mod_id, preferred, loader)

	var entry: Dictionary = spec.duplicate()
	entry["mod_id"] = mod_id
	entry["slot_id"] = slot_id
	if not entry.has("scene_path"):
		entry["scene_path"] = ""
	if not entry.has("packed_scene"):
		entry["packed_scene"] = null
	if not entry.has("icon_texture"):
		entry["icon_texture"] = null
	if not entry.has("default_rounds"):
		entry["default_rounds"] = 1
	if not entry.has("display_name"):
		entry["display_name"] = mod_id
	if not entry.has("brief_content"):
		entry["brief_content"] = ""
	if not entry.has("controls_data"):
		entry["controls_data"] = []
	var normalized_adm: Dictionary = normalize_admission(entry)
	entry["admission"] = {
		"mode_support": normalized_adm["mode_support"],
		"auto_temp_teams": normalized_adm["auto_temp_teams"],
		"min_teams": normalized_adm["min_teams"],
		"max_teams": normalized_adm["max_teams"],
		"min_total_players": normalized_adm["min_total_players"],
		"min_players_per_team": normalized_adm["min_players_per_team"],
		"allow_local_couch": normalized_adm["allow_local_couch"],
		"custom_check": normalized_adm["custom_check"],
		"_has_explicit_team_bounds": normalized_adm["_has_explicit_team_bounds"],
		"_has_explicit_per_team": normalized_adm["_has_explicit_per_team"],
	}

	custom_map[slot_id] = entry
	if _event_bus != null and _event_bus.has_method("emit_event"):
		_event_bus.emit_event("mpm_core.minigame_registered", {"mod_id": mod_id, "slot_id": slot_id})
	return {"ok": true, "slot_id": slot_id, "entry": entry}


func unregister_minigame(mod_id: String, loader = null) -> bool:
	var custom_map: Dictionary = _get_custom_map(loader)
	var hub: Dictionary = _get_hub(loader)
	var dynamic_slots: Dictionary = hub["dynamic_slots"] as Dictionary
	var removed := false
	var to_erase: Array = []
	for key in custom_map.keys():
		var item = custom_map[key]
		if item is Dictionary and str((item as Dictionary).get("mod_id", "")) == mod_id:
			to_erase.append(key)
	for key in to_erase:
		custom_map.erase(key)
		removed = true
	if dynamic_slots.has(mod_id):
		dynamic_slots.erase(mod_id)
		removed = true
	if removed and _event_bus != null and _event_bus.has_method("emit_event"):
		_event_bus.emit_event("mpm_core.minigame_unregistered", {"mod_id": mod_id})
	return removed


func list_minigames(loader = null) -> Array:
	var custom_map: Dictionary = _get_custom_map(loader)
	var slots: Array = []
	for k in custom_map.keys():
		slots.append(int(k))
	slots.sort()
	var out: Array = []
	for slot_id in slots:
		out.append(custom_map[slot_id])
	return out


func normalize_admission(spec: Dictionary) -> Dictionary:
	var raw_val = spec.get("admission", {})
	var raw: Dictionary = raw_val if raw_val is Dictionary else {}
	var mode_support: String = str(raw.get("mode_support", "both")).strip_edges().to_lower()
	if mode_support != "team_only" and mode_support != "ffa_only":
		mode_support = "both"
	var auto_temp_teams: bool = bool(raw.get("auto_temp_teams", false))
	var min_teams: int = max(2, int(raw.get("min_teams", 2)))
	var max_teams: int = max(min_teams, int(raw.get("max_teams", 4)))
	var min_total_players: int = max(0, int(raw.get("min_total_players", 0)))
	var min_players_per_team: int = max(1, int(raw.get("min_players_per_team", 1)))
	var allow_local_couch: bool = bool(raw.get("allow_local_couch", true))
	var custom_raw = raw.get("custom_check", Callable())
	var custom_check: Callable = custom_raw if custom_raw is Callable else Callable()
	var has_bounds: bool = bool(raw["_has_explicit_team_bounds"]) if raw.has("_has_explicit_team_bounds") else (raw.has("min_teams") or raw.has("max_teams"))
	var has_per_team: bool = bool(raw["_has_explicit_per_team"]) if raw.has("_has_explicit_per_team") else raw.has("min_players_per_team")
	return {
		"mode_support": mode_support,
		"auto_temp_teams": auto_temp_teams,
		"min_teams": min_teams,
		"max_teams": max_teams,
		"min_total_players": min_total_players,
		"min_players_per_team": min_players_per_team,
		"allow_local_couch": allow_local_couch,
		"custom_check": custom_check,
		"_has_explicit_team_bounds": has_bounds,
		"_has_explicit_per_team": has_per_team,
	}


func build_admission_context(overrides: Dictionary = {}) -> Dictionary:
	var is_local: bool = false
	if overrides.has("is_local"):
		is_local = bool(overrides["is_local"])
	else:
		var ml_local = Engine.get_main_loop()
		if ml_local is SceneTree and (ml_local as SceneTree).root != null:
			var gm = (ml_local as SceneTree).root.get_node_or_null("GameManager")
			if gm != null and (&"local_game" in gm):
				is_local = bool(gm.get(&"local_game"))
	var tp_meta: Dictionary = {}
	if Engine.has_meta(&"mpm_team_party"):
		var raw_tp = Engine.get_meta(&"mpm_team_party")
		if raw_tp is Dictionary:
			tp_meta = raw_tp as Dictionary
	var team_enabled: bool = false
	if overrides.has("team_enabled"):
		team_enabled = bool(overrides["team_enabled"])
	elif not is_local or bool(tp_meta.get("local_supported", false)):
		team_enabled = bool(tp_meta.get("enabled", false))
	var team_count: int = int(overrides.get("team_count", tp_meta.get("team_count", 0)))
	var teams_raw = overrides.get("teams", tp_meta.get("teams", {}))
	var teams: Dictionary = teams_raw if teams_raw is Dictionary else {}
	var total_players: int = -1
	if overrides.has("total_players") and int(overrides["total_players"]) >= 0:
		total_players = int(overrides["total_players"])
	else:
		var ml = Engine.get_main_loop()
		if ml is SceneTree and (ml as SceneTree).root != null:
			var pm = (ml as SceneTree).root.get_node_or_null("PlayerManager")
			if pm != null and (&"player_presences" in pm):
				var presences = pm.get(&"player_presences")
				if presences is Dictionary:
					total_players = (presences as Dictionary).size()
		if total_players < 0 and not teams.is_empty():
			total_players = teams.size()
	return {
		"is_local": is_local,
		"team_enabled": team_enabled,
		"team_count": team_count,
		"teams": teams,
		"total_players": total_players,
	}


func evaluate_minigame_eligibility(spec: Dictionary, context: Dictionary = {}) -> Dictionary:
	var adm: Dictionary = normalize_admission(spec)
	var ctx: Dictionary = build_admission_context(context)
	var is_local: bool = bool(ctx["is_local"])
	var team_enabled: bool = bool(ctx["team_enabled"])
	var team_count: int = int(ctx["team_count"])
	var teams: Dictionary = ctx["teams"] as Dictionary
	var total_players: int = int(ctx["total_players"])
	var mode_support: String = str(adm["mode_support"])
	var min_teams: int = int(adm["min_teams"])
	var max_teams: int = int(adm["max_teams"])
	var min_total_players: int = int(adm["min_total_players"])
	var min_players_per_team: int = int(adm["min_players_per_team"])
	var has_explicit_bounds: bool = bool(adm["_has_explicit_team_bounds"])
	var has_explicit_per_team: bool = bool(adm["_has_explicit_per_team"])

	if not bool(adm["allow_local_couch"]) and is_local:
		return {"eligible": false, "hard_blocked": true, "soft_warning": false, "reason_key": "local_unsupported", "admission": adm}
	if mode_support == "team_only" and not team_enabled:
		return {"eligible": false, "hard_blocked": true, "soft_warning": false, "reason_key": "needs_team_mode", "admission": adm}
	if mode_support == "ffa_only" and team_enabled:
		return {"eligible": false, "hard_blocked": true, "soft_warning": false, "reason_key": "ffa_only", "admission": adm}
	if team_enabled and (mode_support == "team_only" or has_explicit_bounds):
		if team_count < min_teams or team_count > max_teams:
			return {"eligible": false, "hard_blocked": true, "soft_warning": false, "reason_key": "team_count_out_of_range", "admission": adm}

	if min_total_players > 0 and total_players >= 0 and total_players < min_total_players:
		return {"eligible": false, "hard_blocked": false, "soft_warning": true, "reason_key": "needs_more_players", "admission": adm}

	if team_enabled and (mode_support == "team_only" or has_explicit_bounds or has_explicit_per_team):
		if not teams.is_empty() or total_players >= 0:
			var team_sizes: Dictionary = {}
			for raw_tid in teams.values():
				var tid: int = int(raw_tid)
				if tid >= 1 and tid <= team_count:
					team_sizes[tid] = int(team_sizes.get(tid, 0)) + 1
			var active_team_count: int = team_sizes.size()
			if active_team_count < min_teams:
				return {"eligible": false, "hard_blocked": false, "soft_warning": true, "reason_key": "needs_more_teams", "admission": adm}
			var min_active_size: int = 999999
			for sz in team_sizes.values():
				min_active_size = min(min_active_size, int(sz))
			if min_players_per_team > 1 and min_active_size < min_players_per_team:
				return {"eligible": false, "hard_blocked": false, "soft_warning": true, "reason_key": "needs_more_per_team", "admission": adm}

	var custom_check: Callable = adm["custom_check"] as Callable
	if custom_check.is_valid():
		var res = custom_check.call(spec, ctx)
		if res is Dictionary:
			var d: Dictionary = res as Dictionary
			var ok: bool = bool(d.get("eligible", true))
			if not ok:
				return {
					"eligible": false,
					"hard_blocked": bool(d.get("hard_blocked", false)),
					"soft_warning": bool(d.get("soft_warning", not bool(d.get("hard_blocked", false)))),
					"reason_key": str(d.get("reason_key", "custom_blocked")),
					"admission": adm,
				}
		elif res is bool and not bool(res):
			return {"eligible": false, "hard_blocked": true, "soft_warning": false, "reason_key": "custom_blocked", "admission": adm}

	return {"eligible": true, "hard_blocked": false, "soft_warning": false, "reason_key": "", "admission": adm}


func _pick_locale(en: String, cn: String, tw: String) -> String:
	if _locale != null and _locale.has_method("pick"):
		return str(_locale.call("pick", en, cn, tw))
	var low: String = TranslationServer.get_locale().to_lower()
	if low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo"):
		return tw
	if low.begins_with("zh") or low == "zhs":
		return cn
	return en


func format_admission_tag(result: Dictionary, spec: Dictionary = {}) -> String:
	if bool(result.get("eligible", true)):
		return ""
	var reason: String = str(result.get("reason_key", ""))
	var adm_raw = result.get("admission", normalize_admission(spec))
	var adm: Dictionary = adm_raw if adm_raw is Dictionary else normalize_admission(spec)
	var min_t: int = int(adm.get("min_teams", 2))
	var max_t: int = int(adm.get("max_teams", 4))
	var min_p: int = int(adm.get("min_total_players", 2))
	var min_per: int = int(adm.get("min_players_per_team", 1))
	match reason:
		"needs_team_mode":
			return _pick_locale("[Team Mode]", "[需组队]", "[需組隊]")
		"ffa_only":
			return _pick_locale("[Solo Only]", "[仅混战]", "[僅混戰]")
		"team_count_out_of_range":
			if min_t == max_t:
				return _pick_locale("[%d Teams Only]" % min_t, "[限 %d 队]" % min_t, "[限 %d 隊]" % min_t)
			return _pick_locale("[%d-%d Teams]" % [min_t, max_t], "[%d-%d 队]" % [min_t, max_t], "[%d-%d 隊]" % [min_t, max_t])
		"needs_more_players":
			return _pick_locale("[Need %d+ Players]" % min_p, "[需 %d+ 人]" % min_p, "[需 %d+ 人]" % min_p)
		"needs_more_teams":
			return _pick_locale("[Need %d+ Teams]" % min_t, "[需 %d+ 队]" % min_t, "[需 %d+ 隊]" % min_t)
		"needs_more_per_team":
			return _pick_locale("[Need %d+/Team]" % min_per, "[每队需≥%d人]" % min_per, "[每隊需≥%d人]" % min_per)
		"local_unsupported":
			return _pick_locale("[Online Only]", "[仅联机]", "[僅連線]")
		"custom_blocked":
			return _pick_locale("[Locked]", "[未满足条件]", "[未滿足條件]")
	return ""
