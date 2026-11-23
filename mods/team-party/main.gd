extends Node

## Team Party (組隊派對) — Global Team Mode Mod for Machine Party (API v2).
##
## Features:
## - Room-level team setup in the lobby: FFA / 2 / 3 / 4 teams (Red, Blue, Green, Yellow).
## - Manual team selection for humans & host-controlled bot assignment (never auto-spawns bots).
## - One-click "Shuffle Teams" across all existing humans and host-added bots.
## - Shared team registry (`Engine` meta `&"mpm_team_party"`) for first-party & community mods.
## - Global in-game team nameplate coloring, `▼ [TEAM]` badges, friendly-fire shove filtering,
##   early team victory on vanilla survival minigames, and Fall Guys Squads-style synchronized scoring.

const MOD_ID := "team-party"
const META_KEY := &"mpm_team_party"
const LOBBY_SCRIPT := "res://scenes/lobby/scripts/lobby_scene.gd"
const SKIP_SCENE_TOKENS := ["lobby", "intermission", "main_menu", "mainmenu", "cutscene"]

const TEAM_DEFS := {
	1: {
		"key": "red",
		"color": Color(1.0, 0.30, 0.28, 1.0),
		"tag_en": "[RED]",
		"tag_cn": "[红]",
		"tag_tw": "[紅]",
		"name_en": "Red",
		"name_cn": "红队",
		"name_tw": "紅隊",
	},
	2: {
		"key": "blue",
		"color": Color(0.26, 0.68, 1.0, 1.0),
		"tag_en": "[BLU]",
		"tag_cn": "[蓝]",
		"tag_tw": "[藍]",
		"name_en": "Blue",
		"name_cn": "蓝队",
		"name_tw": "藍隊",
	},
	3: {
		"key": "green",
		"color": Color(0.28, 0.92, 0.48, 1.0),
		"tag_en": "[GRN]",
		"tag_cn": "[绿]",
		"tag_tw": "[綠]",
		"name_en": "Green",
		"name_cn": "绿队",
		"name_tw": "綠隊",
	},
	4: {
		"key": "yellow",
		"color": Color(1.0, 0.84, 0.24, 1.0),
		"tag_en": "[YEL]",
		"tag_cn": "[黄]",
		"tag_tw": "[黃]",
		"name_en": "Yellow",
		"name_cn": "黄队",
		"name_tw": "黃隊",
	},
}

const FORMAT_FFA := 0
const FORMAT_DUO := 1
const FORMAT_SQUAD := 2
const FORMAT_TRIO := 3
const FORMAT_CUSTOM := 4

const KNOWN_PREFIXES := [
	"[RED] ", "[BLU] ", "[GRN] ", "[YEL] ",
	"[红] ", "[蓝] ", "[绿] ", "[黄] ",
	"[紅] ", "[藍] ", "[綠] ", "[黃] ",
]

var team_count: int = 0 # 0 = FFA, 2 / 3 / 4 = active team count
var team_format: int = FORMAT_FFA
var teams: Dictionary = {} # int network_id -> int team_id (1..4)
var locked: bool = false

var _shared_state: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var lobby: Node = null
var game: Node = null
var current_minigame: Node = null
var _minigame_synced: bool = false
var _early_win_triggered: bool = false
var _initial_teams_seen: Dictionary = {}

# Lobby UI references
var panel: PanelContainer = null
var _title_label: Label = null
var _format_buttons: Dictionary = {}
var mode_button: Button = null
var _actions_row: HBoxContainer = null
var shuffle_button: Button = null
var my_team_button: Button = null
var rows: VBoxContainer = null
var _hint_label: Label = null
var _swap_offer_row: HBoxContainer = null
var _swap_offer_label: Label = null
var _swap_accept_btn: Button = null
var _swap_decline_btn: Button = null
var _pending_swap_requests: Dictionary = {} # int target_peer_id -> {"from_id": int, "expires_at": float}
var _incoming_swap_from: int = 0
var _incoming_swap_name: String = ""
var _incoming_swap_expires: float = 0.0
var _last_roster_sig: String = ""
var _lobby_seat_rings: Dictionary = {} # int seat -> MeshInstance3D
var _lobby_seat_halos: Dictionary = {} # int seat -> MeshInstance3D
var _lobby_seat_rest_floor: Dictionary = {} # int seat -> Vector3 rest floor center
var _lobby_seat_rest_slot_xform: Dictionary = {} # int seat -> Transform3D rest transform
var _hovered_seat: int = -1
var _drag_seat: int = -1
var _drag_actor_id: int = 0
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _drag_orig_slot_pos: Vector3 = Vector3.ZERO
var _drag_orig_floor: Vector3 = Vector3.ZERO
var _drag_visual_pos: Vector3 = Vector3.ZERO
var _drag_target_pos: Vector3 = Vector3.ZERO
var _drag_vel: Vector3 = Vector3.ZERO
var _drag_elapsed: float = 0.0
var _drag_skel: Skeleton3D = null
var _drag_anim: AnimationPlayer = null
var _drag_saved_bones: Dictionary = {} # int bone_idx -> Quaternion
var _drag_anim_was_playing: bool = false
var _drag_rest_collar: Vector3 = Vector3.ZERO
var _drag_is_remote: bool = false
var _drag_net_accum: float = 0.0
var _drag_last_sent_pos: Vector3 = Vector3.ZERO
var _drag_last_sent_hover: int = -2
var _seat_drop_bounce: Dictionary = {} # int seat -> float remaining bounce sec
var _hop_seat: int = -1
var _anim_time: float = 0.0
var _orig_lobby_cam_xform: Transform3D = Transform3D.IDENTITY
var _lobby_cam_adjusted: bool = false
var _cursor_textures: Dictionary = {}
var _current_cursor_kind: StringName = &""

# In-game Team HUD overlay
var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _hud_hbox: HBoxContainer = null
var _hud_rows: HBoxContainer = null
var _hud_refresh_accum: float = 0.0
var _hud_wins: Dictionary = {} # int team_id -> int session wins
var _last_hud_sig: String = ""
var _current_stage_node: Node = null

# In-game actor tracking: instance_id -> Dictionary
var _tracked_actors: Dictionary = {}
var _wrapped_script_cache: Dictionary = {} # base GDScript -> wrapped GDScript
var _cjk_badge_font: Font = null
var _crt_font_checked: bool = false
var _crt_font: Font = null


class _DiscoBrainTeamWrapper:
	var _inner
	var _tp: Node

	func _init(inner, tp: Node) -> void:
		_inner = inner
		_tp = tp

	func tick(actor, arena, number: int, delta: float) -> void:
		if _inner == null:
			return
		if _tp == null or not is_instance_valid(_tp) or not bool(_tp.call("is_team_mode_active")) or arena == null:
			_inner.tick(actor, arena, number, delta)
			return
		var ap = arena.get("active_players") if (&"active_players" in arena) else null
		if not (ap is Dictionary):
			_inner.tick(actor, arena, number, delta)
			return
		var active_dict: Dictionary = ap as Dictionary
		var my_id: int = int(_tp.call("_presence_network_id", actor.get(&"player_presence")))
		if my_id == 0:
			_inner.tick(actor, arena, number, delta)
			return
		var saved: Dictionary = {}
		for k in active_dict.keys():
			var other = active_dict[k]
			if other != null and other != actor and is_instance_valid(other) and (&"player_presence" in other):
				var other_id: int = int(_tp.call("_presence_network_id", other.get(&"player_presence")))
				if other_id != 0 and bool(_tp.call("are_teammates", my_id, other_id)):
					saved[k] = other
		for k in saved.keys():
			active_dict.erase(k)
		_inner.tick(actor, arena, number, delta)
		for k in saved.keys():
			active_dict[k] = saved[k]


func _mod_init(loader) -> void:
	_rng.randomize()
	_publish_state()
	if loader != null:
		if loader.has_method("on_scene_script"):
			loader.on_scene_script(LOBBY_SCRIPT, _enter_lobby)
		if loader.has_method("on_node_added"):
			loader.on_node_added(_node_added)
		if loader.has_method("has_api") and bool(loader.call("has_api", "registry")):
			var reg = loader.registry("team_party")
			if reg is Dictionary:
				(reg as Dictionary)["state"] = _shared_state


func _mod_ready(_loader) -> void:
	set_physics_process_priority(50)
	_publish_state()
	_connect_network.call_deferred()


func _exit_tree() -> void:
	_cancel_lobby_drag()
	for rec in _tracked_actors.values():
		_cleanup_actor_record(rec)
	_tracked_actors.clear()
	_clear_lobby_3d_rings()
	_seat_drop_bounce.clear()
	_hop_seat = -1
	_lobby_cam_adjusted = false
	_current_stage_node = null
	if is_instance_valid(_hud_layer):
		_hud_layer.queue_free()
	_hud_layer = null
	_hud_panel = null
	_hud_hbox = null
	_hud_rows = null
	_hud_title_lbl = null
	_hint_label = null
	_swap_offer_row = null
	_swap_offer_label = null
	_swap_accept_btn = null
	_swap_decline_btn = null
	_pending_swap_requests.clear()
	_incoming_swap_from = 0
	_incoming_swap_name = ""
	_incoming_swap_expires = 0.0
	if is_instance_valid(_sfx_ui_player):
		_sfx_ui_player.stop()
		_sfx_ui_player.queue_free()
	_sfx_ui_player = null
	_sfx_ui_click = null
	_wrapped_script_cache.clear()
	_hud_wins.clear()
	_cursor_textures.clear()
	_cjk_badge_font = null
	_crt_font = null
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null)
	if Engine.has_meta(META_KEY):
		var meta = Engine.get_meta(META_KEY)
		if meta is Dictionary and (meta as Dictionary).get("node", null) == self:
			Engine.remove_meta(META_KEY)


func _get_cjk_badge_font() -> Font:
	if _cjk_badge_font == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray([
			"PingFang TC", "PingFang SC", "Microsoft JhengHei", "Microsoft YaHei",
			"Noto Sans CJK TC", "Heiti TC", "Helvetica Neue", "Arial"
		])
		if not _crt_font_checked:
			_crt_font_checked = true
			if ResourceLoader.exists("res://fonts/Terminal F4.ttf"):
				var f = ResourceLoader.load("res://fonts/Terminal F4.ttf")
				if f is Font:
					var fv := FontVariation.new()
					fv.base_font = f as Font
					fv.fallbacks = [sys]
					_crt_font = fv
		_cjk_badge_font = _crt_font if _crt_font != null else sys
	return _cjk_badge_font


func _get_ui_font() -> Font:
	return _get_cjk_badge_font()


func _is_tw_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo")


func _is_cn_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return not _is_tw_locale(low) and (low.begins_with("zh") or low == "zhs")


func _is_player_spotlight_enabled() -> bool:
	if not Engine.has_meta(&"mpm_player_spotlight_active") or not bool(Engine.get_meta(&"mpm_player_spotlight_active")):
		return false
	if get_tree() != null and get_tree().root != null:
		var spot := get_tree().root.get_node_or_null("ModLoader/player-spotlight")
		if spot != null and (&"enabled" in spot):
			return bool(spot.get(&"enabled"))
	return true


func _publish_state() -> void:
	_shared_state["enabled"] = is_team_mode_active()
	_shared_state["team_count"] = team_count
	_shared_state["team_format"] = team_format
	_shared_state["teams"] = teams
	_shared_state["node"] = self
	Engine.set_meta(META_KEY, _shared_state)


func _label(en: String, cn: String, tw: String) -> String:
	var locale: String = TranslationServer.get_locale()
	if _is_tw_locale(locale):
		return tw
	if _is_cn_locale(locale):
		return cn
	return en


# ============================================================================
# Shared Team Registry API (read by vanilla hooks & first-party mods)
# ============================================================================

func is_team_mode_active() -> bool:
	return team_count >= 2


func get_team(net_id: int) -> int:
	if team_count < 2:
		return 0
	var tid: int = int(teams.get(net_id, 0))
	if tid >= 1 and tid <= team_count:
		return tid
	return 0


func are_teammates(id_a: int, id_b: int) -> bool:
	if team_count < 2 or id_a == id_b:
		return false
	var ta: int = get_team(id_a)
	return ta > 0 and ta == get_team(id_b)


func get_team_color(team_id: int) -> Color:
	if TEAM_DEFS.has(team_id):
		return (TEAM_DEFS[team_id] as Dictionary)["color"] as Color
	return Color.WHITE


func get_team_tag(team_id: int) -> String:
	if not TEAM_DEFS.has(team_id):
		return ""
	var d: Dictionary = TEAM_DEFS[team_id]
	return _label(str(d["tag_en"]), str(d["tag_cn"]), str(d["tag_tw"]))


func get_team_name(team_id: int) -> String:
	if not TEAM_DEFS.has(team_id):
		return _label("Unassigned", "未分队", "未分隊")
	var d: Dictionary = TEAM_DEFS[team_id]
	return _label(str(d["name_en"]), str(d["name_cn"]), str(d["name_tw"]))


func strip_team_prefix(text: String) -> String:
	for p in KNOWN_PREFIXES:
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
	for t in range(1, team_count + 1):
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
		for t in range(1, team_count + 1):
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


# ============================================================================
# Network & Lobby Participant Helpers
# ============================================================================

func _network():
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("NetworkManager")


func _local_peer_id() -> int:
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func _is_host_authoritative() -> bool:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _lobby_bots_mod() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("ModLoader/lobby-bots")


func _connect_network() -> void:
	var network = _network()
	if network != null and network.has_signal("on_peer_connected"):
		if not network.on_peer_connected.is_connected(_peer_connected):
			network.on_peer_connected.connect(_peer_connected)


func _peer_connected(id: int) -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_teams.rpc_id(id, team_count, teams.duplicate(), team_format, _hud_wins.duplicate())


func _can_host_edit() -> bool:
	if not is_instance_valid(lobby) or locked:
		return false
	if multiplayer != null and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	var handler = lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")):
		return false
	if bool(lobby.get("loading")):
		return false
	return true


func _can_guest_pick_self() -> bool:
	if not is_instance_valid(lobby) or locked or team_count < 2:
		return false
	var handler = lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")):
		return false
	if bool(lobby.get("loading")):
		return false
	return true


func _collect_lobby_participants() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var network = _network()
	if network != null and network.get("active_backend") != null:
		var backend = network.active_backend
		var connected = backend.get("connected_players")
		if connected is Dictionary:
			var peer_ids: Array = (connected as Dictionary).keys()
			peer_ids.sort()
			# Keep host (1) first for clean ordering
			if peer_ids.has(1):
				peer_ids.erase(1)
				peer_ids.push_front(1)
			for raw_pid in peer_ids:
				var pid: int = int(raw_pid)
				var info = (connected as Dictionary)[raw_pid]
				if info is Dictionary and bool((info as Dictionary).get("debug", false)):
					continue
				var p_name: String = str((info as Dictionary).get("name", "Player %d" % pid)) if info is Dictionary else "Player %d" % pid
				seen[pid] = true
				entries.append({"id": pid, "name": p_name, "is_bot": false})

	if is_instance_valid(lobby):
		var seat_map = lobby.get("player_order_by_seat")
		if seat_map is Dictionary:
			var seat_keys: Array = (seat_map as Dictionary).keys()
			seat_keys.sort()
			for sk in seat_keys:
				var pid: int = int((seat_map as Dictionary)[sk])
				if pid > 0 and not seen.has(pid):
					seen[pid] = true
					entries.append({"id": pid, "name": "Player %d" % pid, "is_bot": false})

	var bot_mod: Node = _lobby_bots_mod()
	if bot_mod != null:
		var bots_dict = bot_mod.get("bots")
		if bots_dict is Dictionary:
			var bot_entries: Array = []
			for raw_bid in (bots_dict as Dictionary).keys():
				var bid: int = int(raw_bid)
				var raw_val = (bots_dict as Dictionary)[raw_bid]
				var bnum: int = absi(bid)
				var bname: String = ""
				if raw_val is Dictionary:
					var d: Dictionary = raw_val as Dictionary
					if d.has("num"):
						bnum = int(d["num"])
					bname = str(d.get("name", ""))
				elif typeof(raw_val) in [TYPE_INT, TYPE_FLOAT]:
					bnum = int(raw_val)
				if bname.is_empty():
					bname = "Bot %d" % bnum
				bot_entries.append({"id": bid, "num": bnum, "name": bname})
			bot_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["num"]) < int(b["num"])
			)
			for be in bot_entries:
				var bid: int = int(be["id"])
				if not seen.has(bid):
					seen[bid] = true
					entries.append({"id": bid, "name": str(be["name"]), "is_bot": true})
	return entries


func _smallest_team(exclude_id: int = 0) -> int:
	if team_count < 2:
		return 0
	var counts: Dictionary = {}
	for t in range(1, team_count + 1):
		counts[t] = 0
	for raw_id in teams.keys():
		var nid: int = int(raw_id)
		if nid == exclude_id:
			continue
		var t: int = int(teams[raw_id])
		if t >= 1 and t <= team_count:
			counts[t] = int(counts[t]) + 1
	var best_t: int = 1
	var best_c: int = 999999
	for t in range(1, team_count + 1):
		var c: int = int(counts[t])
		if c < best_c:
			best_c = c
			best_t = t
	return best_t


func _reconcile_lobby_teams(participants: Array[Dictionary]) -> bool:
	if team_count < 2 or locked or not _is_host_authoritative():
		return false
	if team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO] and participants.size() >= 2:
		var desired_teams: int = _calc_format_team_count(team_format, participants.size())
		if desired_teams >= 2 and desired_teams != team_count:
			team_count = desired_teams
			_assign_balanced_order(participants, false)
			return true
	var valid_ids: Dictionary = {}
	for p in participants:
		valid_ids[int(p["id"])] = true
	var changed: bool = false
	for raw_id in teams.keys():
		var nid: int = int(raw_id)
		if not valid_ids.has(nid):
			teams.erase(raw_id)
			changed = true
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = seats.size()
	for p in participants:
		var nid: int = int(p["id"])
		var cur: int = int(teams.get(nid, 0))
		if cur < 1 or cur > team_count:
			var picked: int = 0
			if team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO] and total_seats > 0:
				var sidx: int = seats.find(nid)
				if sidx >= 0:
					picked = _seat_zone_team(sidx, total_seats)
			if picked < 1 or picked > team_count:
				picked = _smallest_team(nid)
			teams[nid] = picked
			changed = true
	return changed


# ============================================================================
# Lobby UI & Team Operations (Vanilla CRT Style + Format Presets)
# ============================================================================

var _orig_nametag_alpha: Dictionary = {}
var _sfx_ui_click: AudioStream = null
var _sfx_ui_player: AudioStreamPlayer = null
var _hud_title_lbl: Label = null
var _format_badge_lbl: Label = null


func _set_lobby_cursor(kind: StringName) -> void:
	if kind == _current_cursor_kind:
		return
	_current_cursor_kind = kind
	if DisplayServer.get_name() == "headless":
		return
	var cm = get_tree().root.get_node_or_null("CursorManager") if (get_tree() != null and get_tree().root != null) else null
	if cm != null and cm.has_method("set_cursor_image"):
		cm.call("set_cursor_image", kind)
		return
	var path_map := {
		&"point": "res://textures/cursor xp_point.png",
		&"hover": "res://textures/cursor xp_hover.png",
		&"grab": "res://textures/cursor xp_grab.png",
		&"invalid": "res://textures/cursor xp_invalid.png",
	}
	var cpath: String = str(path_map.get(kind, ""))
	if not cpath.is_empty():
		if not _cursor_textures.has(kind) and ResourceLoader.exists(cpath):
			var loaded = ResourceLoader.load(cpath)
			if loaded is Texture2D:
				_cursor_textures[kind] = loaded
		var tex = _cursor_textures.get(kind, null)
		if tex is Texture2D:
			Input.set_custom_mouse_cursor(tex as Texture2D, Input.CURSOR_ARROW, Vector2(12, 12))
			return
	match kind:
		&"grab":
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		&"hover":
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		_:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _set_slot_pivot_pose(slot_node: Node3D, seat: int, offset_vec: Vector3, tilt_euler: Vector3 = Vector3.ZERO, stretch_scale: Vector3 = Vector3.ONE, pivot_y: float = 1.45) -> void:
	if slot_node == null or not is_instance_valid(slot_node):
		return
	var rest_xform: Transform3D = _lobby_seat_rest_slot_xform.get(seat, slot_node.transform) as Transform3D
	if not _lobby_seat_rest_slot_xform.has(seat) and not (_drag_active and seat == _drag_seat):
		_lobby_seat_rest_slot_xform[seat] = rest_xform
	var floor_w: Vector3 = _seat_world_floor_pos(slot_node, null, seat)
	var chest_w: Vector3 = Vector3(floor_w.x, pivot_y, floor_w.z)
	var parent_n: Node = slot_node.get_parent()
	var chest_parent: Vector3 = (parent_n as Node3D).to_local(chest_w) if (parent_n is Node3D) else chest_w
	var dest_parent: Vector3 = (parent_n as Node3D).to_local(chest_w + offset_vec) if (parent_n is Node3D) else (chest_w + offset_vec)
	var parent_delta: Vector3 = dest_parent - chest_parent
	var pivot_local: Vector3 = rest_xform.affine_inverse() * chest_parent
	var b := Basis.from_euler(tilt_euler)
	var scaled_p := Vector3(pivot_local.x * stretch_scale.x, pivot_local.y * stretch_scale.y, pivot_local.z * stretch_scale.z)
	var new_origin: Vector3 = rest_xform.origin + parent_delta + (rest_xform.basis * pivot_local) - (rest_xform.basis * b * scaled_p)
	slot_node.transform = Transform3D(rest_xform.basis * b.scaled(stretch_scale), new_origin)


func _restore_slot_transform(seat: int) -> void:
	if seat < 0 or not is_instance_valid(lobby):
		return
	var handler = lobby.get("lobby_handler")
	if handler == null or not (handler.get("players") is Array):
		return
	var players_arr: Array = handler.get("players") as Array
	if seat < players_arr.size():
		var snode = players_arr[seat]
		if snode is Node3D and is_instance_valid(snode) and _lobby_seat_rest_slot_xform.has(seat):
			(snode as Node3D).transform = _lobby_seat_rest_slot_xform[seat] as Transform3D


func _begin_drag_skeleton(slot_node: Node3D) -> void:
	_restore_drag_skeleton()
	if slot_node == null or not is_instance_valid(slot_node):
		return
	var ap := slot_node.get_node_or_null("main character2/anim_character rig") as AnimationPlayer
	if ap != null:
		_drag_anim = ap
		_drag_anim_was_playing = ap.is_playing()
		ap.pause()
	var sk := slot_node.get_node_or_null("main character2/Armature_001/Skeleton3D") as Skeleton3D
	if sk != null:
		_drag_skel = sk
		_drag_saved_bones.clear()
		for i in range(sk.get_bone_count()):
			_drag_saved_bones[i] = sk.get_bone_pose_rotation(i)


func _restore_drag_skeleton() -> void:
	if _drag_skel != null and is_instance_valid(_drag_skel):
		for idx_v in _drag_saved_bones.keys():
			var idx: int = int(idx_v)
			if idx >= 0 and idx < _drag_skel.get_bone_count():
				_drag_skel.set_bone_pose_rotation(idx, _drag_saved_bones[idx_v] as Quaternion)
	if _drag_anim != null and is_instance_valid(_drag_anim) and _drag_anim_was_playing:
		_drag_anim.play()
	_drag_skel = null
	_drag_anim = null
	_drag_saved_bones.clear()
	_drag_anim_was_playing = false


func _blend_drag_bone(bname: String, local_euler: Vector3, weight: float) -> void:
	if _drag_skel == null or not is_instance_valid(_drag_skel):
		return
	var idx: int = _drag_skel.find_bone(bname)
	if idx < 0 or not _drag_saved_bones.has(idx):
		return
	var rest_q: Quaternion = _drag_skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	var target_q: Quaternion = (rest_q * Quaternion.from_euler(local_euler)).normalized()
	_drag_skel.set_bone_pose_rotation(idx, (_drag_saved_bones[idx] as Quaternion).slerp(target_q, weight))


func _apply_drag_dangling_pose() -> void:
	if _drag_skel == null or not is_instance_valid(_drag_skel):
		return
	var t_pick: float = clampf(_drag_elapsed / 0.14, 0.0, 1.0)
	var blend: float = 1.0 - pow(1.0 - t_pick, 3.0)
	var vx: float = clampf(_drag_vel.x / 10.0, -1.0, 1.0)
	var vy: float = clampf(_drag_vel.y / 10.0, -1.0, 1.0)
	var kick: float = sin(_anim_time * 9.5)
	var wave: float = sin(_anim_time * 7.8 + 0.9)

	_blend_drag_bone("spine", Vector3(vx * 0.14, 0.0, 0.10 - vy * 0.08), blend)
	_blend_drag_bone("chest", Vector3(vx * 0.16, 0.0, 0.18), blend)
	_blend_drag_bone("neck", Vector3(0.0, clampf(vx * 0.22, -0.25, 0.25), -0.08), blend)
	_blend_drag_bone("head", Vector3(-vx * 0.18, clampf(vx * 0.35, -0.35, 0.35), -0.15 + vy * 0.14), blend)

	_blend_drag_bone("thigh.L", Vector3(-vx * 0.32, 0.0, 0.18 + kick * 0.24 - vy * 0.16), blend)
	_blend_drag_bone("thigh.R", Vector3(-vx * 0.32, 0.0, 0.18 - kick * 0.24 - vy * 0.16), blend)
	_blend_drag_bone("shin.L", Vector3(0.0, 0.0, 0.34 + maxf(0.0, -kick) * 0.32 - vy * 0.18), blend)
	_blend_drag_bone("shin.R", Vector3(0.0, 0.0, 0.34 + maxf(0.0, kick) * 0.32 - vy * 0.18), blend)
	_blend_drag_bone("foot.L", Vector3(0.0, 0.0, -0.35), blend)
	_blend_drag_bone("foot.R", Vector3(0.0, 0.0, -0.35), blend)

	_blend_drag_bone("upper_arm.L", Vector3(0.55 + wave * 0.24 - vy * 0.28, 0.0, 0.25 + vx * 0.25), blend)
	_blend_drag_bone("upper_arm.R", Vector3(-0.55 - wave * 0.24 + vy * 0.28, 0.0, 0.25 - vx * 0.25), blend)
	_blend_drag_bone("forearm.L", Vector3(0.45 + wave * 0.15, 0.0, 0.25), blend)
	_blend_drag_bone("forearm.R", Vector3(-0.45 - wave * 0.15, 0.0, 0.25), blend)


func _sync_lobby_camera_angle() -> void:
	if not is_instance_valid(lobby):
		return
	var cam := lobby.get_node_or_null("LobbyPreviewViewport/LobbyViewport/Camera3D") as Camera3D
	if cam == null:
		return
	var wants_elevated: bool = is_team_mode_active() and _lobby_total_seats() > 4
	if wants_elevated:
		if not _lobby_cam_adjusted:
			_orig_lobby_cam_xform = cam.transform
			_lobby_cam_adjusted = true
			cam.position = _orig_lobby_cam_xform.origin + Vector3(0.0, 2.35, 1.1)
			cam.rotation_degrees.x = _orig_lobby_cam_xform.basis.get_euler().x * (180.0 / PI) - 5.2
	elif _lobby_cam_adjusted:
		cam.transform = _orig_lobby_cam_xform
		_lobby_cam_adjusted = false


func _cancel_lobby_drag() -> void:
	var was_active: bool = _drag_active
	var was_local_active: bool = _drag_active and not _drag_is_remote
	var seat_restore: int = _drag_seat
	_restore_drag_skeleton()
	if seat_restore >= 0:
		_restore_slot_transform(seat_restore)
	if _hop_seat >= 0:
		_restore_slot_transform(_hop_seat)
		_hop_seat = -1
	_drag_seat = -1
	_drag_actor_id = 0
	_drag_start_pos = Vector2.ZERO
	_drag_active = false
	_drag_is_remote = false
	_drag_net_accum = 0.0
	_drag_last_sent_pos = Vector3.ZERO
	_drag_last_sent_hover = -2
	_drag_orig_slot_pos = Vector3.ZERO
	_drag_orig_floor = Vector3.ZERO
	_drag_visual_pos = Vector3.ZERO
	_drag_target_pos = Vector3.ZERO
	_drag_vel = Vector3.ZERO
	_drag_elapsed = 0.0
	_drag_rest_collar = Vector3.ZERO
	_set_lobby_cursor(&"point")
	if was_local_active:
		_broadcast_drag_end(seat_restore, [])
	if was_active and is_instance_valid(lobby) and lobby.is_inside_tree():
		_update_lobby_nametags()


func _enter_lobby(node: Node) -> void:
	lobby = node
	locked = false
	_hovered_seat = -1
	_lobby_cam_adjusted = false
	_seat_drop_bounce.clear()
	_hop_seat = -1
	_cancel_lobby_drag()
	_last_roster_sig = ""
	_orig_nametag_alpha.clear()
	_clear_lobby_3d_rings()
	_hide_hud()
	if lobby.is_node_ready():
		_setup_lobby_panel()
		_sync_lobby_camera_angle()
	else:
		lobby.ready.connect(func() -> void:
			_setup_lobby_panel()
			_sync_lobby_camera_angle()
		, CONNECT_ONE_SHOT)
	lobby.tree_exiting.connect(_leave_lobby, CONNECT_ONE_SHOT)


func _leave_lobby() -> void:
	_cancel_lobby_drag()
	if _lobby_cam_adjusted and is_instance_valid(lobby):
		var cam := lobby.get_node_or_null("LobbyPreviewViewport/LobbyViewport/Camera3D") as Camera3D
		if cam != null:
			cam.transform = _orig_lobby_cam_xform
	_lobby_cam_adjusted = false
	_seat_drop_bounce.clear()
	_hop_seat = -1
	_clear_lobby_3d_rings()
	if DisplayServer.get_name() != "headless" and get_tree() != null and get_tree().root != null and get_tree().root.get_node_or_null("CursorManager") == null:
		Input.set_custom_mouse_cursor(null)
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null
	mode_button = null
	shuffle_button = null
	my_team_button = null
	rows = null
	_actions_row = null
	_hint_label = null
	_swap_offer_row = null
	_swap_offer_label = null
	_swap_accept_btn = null
	_swap_decline_btn = null
	_pending_swap_requests.clear()
	_incoming_swap_from = 0
	_incoming_swap_name = ""
	_incoming_swap_expires = 0.0
	_title_label = null
	_format_badge_lbl = null
	_format_buttons.clear()
	_hovered_seat = -1
	if not locked:
		lobby = null
	_last_roster_sig = ""


func _make_crt_panel_style(_border_col: Color = Color.WHITE, _bg_col: Color = Color.BLACK) -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _style_outline_label(lbl: Label, col: Color = Color.WHITE, font_sz: int = 16, outline_sz: int = 5) -> void:
	var f: Font = _get_ui_font()
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	lbl.add_theme_constant_override("outline_size", outline_sz)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


func _style_crt_button(btn: Button, _accent: Color = Color.WHITE, highlighted: bool = false, font_sz: int = 20) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	var f: Font = _get_ui_font()
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


func _play_ui_click() -> void:
	if _sfx_ui_click == null and ResourceLoader.exists("res://audio/menu click.ogg"):
		var s = ResourceLoader.load("res://audio/menu click.ogg")
		if s is AudioStream:
			_sfx_ui_click = s as AudioStream
	if _sfx_ui_click != null and is_inside_tree():
		if _sfx_ui_player == null or not is_instance_valid(_sfx_ui_player):
			_sfx_ui_player = AudioStreamPlayer.new()
			_sfx_ui_player.name = "TeamPartyClickSfx"
			add_child(_sfx_ui_player)
		_sfx_ui_player.stream = _sfx_ui_click
		_sfx_ui_player.pitch_scale = randf_range(0.95, 1.05)
		_sfx_ui_player.play()


func _notify_lobby_terminal(msg: String) -> void:
	if not is_instance_valid(lobby):
		return
	var handler = lobby.get("lobby_handler")
	if handler != null and handler.has_method("send_lobby_message"):
		handler.call("send_lobby_message", msg)


func _setup_lobby_panel() -> void:
	if not is_instance_valid(lobby):
		return
	var handler = lobby.get("lobby_handler")
	if handler == null or handler.get("root") == null:
		return
	var root_ctrl: Control = handler.root

	panel = PanelContainer.new()
	panel.name = "TeamPartyPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_crt_panel_style())
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 24.0
	panel.offset_top = 24.0
	panel.offset_right = 24.0
	panel.offset_bottom = 24.0
	root_ctrl.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var fmt_bar := HBoxContainer.new()
	fmt_bar.name = "FormatBar"
	fmt_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fmt_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(fmt_bar)

	_format_buttons.clear()
	var fmt_defs := [
		[FORMAT_FFA, _label("OFF", "关", "關")],
		[FORMAT_DUO, _label("2/TEAM", "2人队", "2人隊")],
		[FORMAT_SQUAD, _label("4/TEAM", "4人队", "4人隊")],
		[FORMAT_CUSTOM, _label("FREE", "自由", "自由")],
	]
	for fd in fmt_defs:
		var fcode: int = int(fd[0])
		var fbtn := Button.new()
		fbtn.name = "FormatBtn_%d" % fcode
		fbtn.text = str(fd[1])
		fbtn.pressed.connect(_on_format_button_pressed.bind(fcode))
		_style_crt_button(fbtn, Color.WHITE, false, 20)
		fmt_bar.add_child(fbtn)
		_format_buttons[fcode] = fbtn

	_actions_row = HBoxContainer.new()
	_actions_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_row.add_theme_constant_override("separation", 5)
	vbox.add_child(_actions_row)

	shuffle_button = Button.new()
	shuffle_button.name = "ShuffleTeamsButton"
	shuffle_button.text = _label("SHUFFLE", "随机分队", "隨機分隊")
	shuffle_button.pressed.connect(_on_shuffle_pressed)
	_style_crt_button(shuffle_button, Color.WHITE, false, 20)
	_actions_row.add_child(shuffle_button)

	mode_button = Button.new()
	mode_button.name = "TeamModeButton"
	mode_button.pressed.connect(_on_custom_count_pressed)
	_style_crt_button(mode_button, Color.WHITE, false, 20)
	_actions_row.add_child(mode_button)

	my_team_button = Button.new()
	my_team_button.name = "MyTeamButton"
	my_team_button.visible = false
	my_team_button.pressed.connect(_on_my_team_pressed)
	_style_crt_button(my_team_button, Color.WHITE, false, 20)
	_actions_row.add_child(my_team_button)

	_hint_label = Label.new()
	_hint_label.name = "TeamChairHint"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_outline_label(_hint_label, Color.WHITE, 16, 5)
	vbox.add_child(_hint_label)

	_swap_offer_row = HBoxContainer.new()
	_swap_offer_row.name = "SwapOfferRow"
	_swap_offer_row.visible = false
	_swap_offer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swap_offer_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_swap_offer_row)

	_swap_offer_label = Label.new()
	_swap_offer_label.name = "SwapOfferLabel"
	_swap_offer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_outline_label(_swap_offer_label, Color(1.0, 0.92, 0.45), 16, 5)
	_swap_offer_row.add_child(_swap_offer_label)

	_swap_accept_btn = Button.new()
	_swap_accept_btn.name = "SwapAcceptButton"
	_swap_accept_btn.text = _label("ACCEPT", "同意", "同意")
	_swap_accept_btn.pressed.connect(_on_swap_accept_pressed)
	_style_crt_button(_swap_accept_btn, Color.WHITE, true, 18)
	_swap_offer_row.add_child(_swap_accept_btn)

	_swap_decline_btn = Button.new()
	_swap_decline_btn.name = "SwapDeclineButton"
	_swap_decline_btn.text = _label("DECLINE", "拒绝", "拒絕")
	_swap_decline_btn.pressed.connect(_on_swap_decline_pressed)
	_style_crt_button(_swap_decline_btn, Color.WHITE, false, 18)
	_swap_offer_row.add_child(_swap_decline_btn)

	rows = VBoxContainer.new()
	rows.name = "TeamMemberRows"
	rows.visible = false
	vbox.add_child(rows)

	if handler.has_signal("start_pressed") and not handler.start_pressed.is_connected(_lock_for_game):
		handler.start_pressed.connect(_lock_for_game)
	if handler.has_signal("back_pressed") and not handler.back_pressed.is_connected(_reset_lobby_state):
		handler.back_pressed.connect(_reset_lobby_state)

	_refresh_lobby_ui()


func _lobby_total_seats() -> int:
	if not is_instance_valid(lobby):
		return 0
	var count: int = 0
	var handler = lobby.get("lobby_handler")
	if handler != null and (handler.get("players") is Array):
		count = (handler.get("players") as Array).size()
	var seat_map = lobby.get("player_order_by_seat")
	if seat_map is Dictionary:
		count = maxi(count, (seat_map as Dictionary).size())
	return count


func _calc_format_team_count(fmt: int, participant_count: int) -> int:
	var n: int = maxi(2, maxi(participant_count, _lobby_total_seats()))
	match fmt:
		FORMAT_FFA:
			return 0
		FORMAT_DUO:
			# 8 seats -> 4 fixed teams (2v2v2v2), 4 seats -> 2 fixed teams (2v2)
			return clampi(ceili(float(n) / 2.0), 2, 4)
		FORMAT_SQUAD:
			# Big Squads: 2 big fixed teams (front/back 4v4 at 8 seats, 2v2 at 4 seats)
			return 2
		FORMAT_TRIO:
			return clampi(ceili(float(n) / 3.0), 2, 4)
		FORMAT_CUSTOM:
			return team_count if team_count >= 2 else (4 if n >= 7 else (3 if n >= 5 else 2))
		_:
			return 2


func _team_capacity() -> int:
	match team_format:
		FORMAT_DUO:
			return 2
		FORMAT_SQUAD:
			return 4
		FORMAT_TRIO:
			return 3
		_:
			return 0


func _seat_zone_team(seat_idx: int, total_seats: int) -> int:
	if team_count < 2 or seat_idx < 0:
		return 0
	var n_seats: int = maxi(2, total_seats)
	match team_format:
		FORMAT_DUO:
			return clampi((seat_idx / 2) + 1, 1, team_count)
		FORMAT_SQUAD:
			var half: int = ceili(float(n_seats) / 2.0)
			return 1 if seat_idx < half else 2
		FORMAT_TRIO:
			return clampi((seat_idx / 3) + 1, 1, team_count)
		_:
			return clampi((seat_idx * team_count) / n_seats + 1, 1, team_count)


func _is_bot_id(nid: int) -> bool:
	if nid == 0:
		return false
	var bot_mod: Node = _lobby_bots_mod()
	if bot_mod != null and (bot_mod.get("bots") is Dictionary):
		if (bot_mod.get("bots") as Dictionary).has(nid):
			return true
	return nid < 0


func _resolved_lobby_seats() -> Dictionary:
	var seats: Array = []
	var seat_count: int = 0
	if not is_instance_valid(lobby):
		return {"seats": seats, "count": 0}
	var handler = lobby.get("lobby_handler")
	if handler != null and (handler.get("players") is Array):
		seat_count = (handler.get("players") as Array).size()
	var seat_map = lobby.get("player_order_by_seat")
	var bot_mod: Node = _lobby_bots_mod()
	var bot_keys: Array = []
	if bot_mod != null and (bot_mod.get("bots") is Dictionary):
		bot_keys = (bot_mod.get("bots") as Dictionary).keys().duplicate()
	var total: int = seat_count
	if seat_map is Dictionary:
		total = maxi(total, (seat_map as Dictionary).size())
	var next_bot_idx: int = 0
	for s in range(total):
		var raw_id: int = -1
		if seat_map is Dictionary and (seat_map as Dictionary).has(s):
			raw_id = int((seat_map as Dictionary)[s])
		if raw_id > 0:
			seats.append(raw_id)
		elif next_bot_idx < bot_keys.size():
			seats.append(int(bot_keys[next_bot_idx]))
			next_bot_idx += 1
		else:
			seats.append(0) # 0 denotes an empty seat
	return {"seats": seats, "count": total}


func _team_members_list(tid: int, participants: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in participants:
		if get_team(int(p["id"])) == tid:
			out.append(p)
	return out


func _lock_for_game() -> void:
	if _is_host_authoritative() and not locked:
		_cancel_lobby_drag()
		_pending_swap_requests.clear()
		_incoming_swap_from = 0
		if team_count >= 2:
			var participants: Array[Dictionary] = _collect_lobby_participants()
			_reconcile_lobby_teams(participants)
			_sync_lobby_3d_visuals()
			_broadcast_teams()
		locked = true
		_hovered_seat = -1
		_publish_state()


func _reset_lobby_state() -> void:
	_cancel_lobby_drag()
	_pending_swap_requests.clear()
	_incoming_swap_from = 0
	locked = false
	_hovered_seat = -1
	_last_roster_sig = ""
	_publish_state()
	_sync_lobby_3d_visuals()


func _on_format_button_pressed(fmt: int) -> void:
	_play_ui_click()
	set_team_format(fmt)


func set_team_format(new_fmt: int) -> void:
	if not _can_host_edit():
		return
	var participants: Array[Dictionary] = _collect_lobby_participants()
	if new_fmt == FORMAT_FFA:
		_pending_swap_requests.clear()
		_incoming_swap_from = 0
		team_format = FORMAT_FFA
		set_team_mode(0)
		_sync_lobby_camera_angle()
		_notify_lobby_terminal(_label("MODE: FREE-FOR-ALL", "模式：各自为战", "模式：各自為戰"))
		return
	team_format = new_fmt
	var target_teams: int = _calc_format_team_count(new_fmt, participants.size())
	team_count = target_teams
	_assign_balanced_order(participants, false)
	_sync_lobby_camera_angle()
	_publish_state()
	_broadcast_teams()
	_refresh_lobby_ui()
	_sync_lobby_3d_visuals()
	_notify_lobby_terminal(_format_summary_text(participants.size()))


func _sync_bots_to_seat_zones() -> void:
	if not (team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO]) or team_count < 2:
		return
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total: int = seats.size()
	for s in range(total):
		var nid: int = int(seats[s])
		if nid != 0 and _is_bot_id(nid):
			var z: int = _seat_zone_team(s, total)
			if z >= 1 and z <= team_count:
				teams[nid] = z


func _arrange_seats_for_teams(participants: Array[Dictionary]) -> bool:
	if not is_instance_valid(lobby) or team_count < 2:
		return false
	var seat_map = lobby.get("player_order_by_seat")
	if not (seat_map is Dictionary):
		return false
	var sm: Dictionary = seat_map as Dictionary
	var total_seats: int = maxi(_lobby_total_seats(), sm.size())
	if total_seats < participants.size():
		return false
	var used_seats: Dictionary = {}
	for k in sm.keys():
		sm[k] = -1
	for p in participants:
		var nid: int = int(p["id"])
		if nid <= 0:
			continue
		var want_t: int = get_team(nid)
		var picked_s: int = -1
		for s in range(total_seats):
			if not used_seats.has(s) and _seat_zone_team(s, total_seats) == want_t:
				picked_s = s
				break
		if picked_s < 0:
			for s in range(total_seats):
				if not used_seats.has(s):
					picked_s = s
					break
		if picked_s >= 0:
			used_seats[picked_s] = true
			sm[picked_s] = nid
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and lobby.has_method("player_list_updated_rpc"):
		lobby.rpc("player_list_updated_rpc", sm)
	elif lobby.has_method("update_player_list"):
		lobby.call("update_player_list")
	return true


func _assign_balanced_order(participants: Array[Dictionary], do_shuffle: bool) -> void:
	if team_count < 2:
		return
	var ids: Array[int] = []
	for p in participants:
		ids.append(int(p["id"]))
	if do_shuffle:
		for i in range(ids.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: int = ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
	teams.clear()
	if not do_shuffle and (team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO]):
		var resolved := _resolved_lobby_seats()
		var seats: Array = resolved["seats"]
		var total_seats: int = seats.size()
		if total_seats > 0:
			for nid in ids:
				var sidx: int = seats.find(nid)
				if sidx >= 0:
					var zt: int = _seat_zone_team(sidx, total_seats)
					if zt >= 1 and zt <= team_count:
						teams[nid] = zt
		for nid in ids:
			if not teams.has(nid):
				teams[nid] = _smallest_team(nid)
	else:
		for i in range(ids.size()):
			teams[ids[i]] = (i % team_count) + 1
		if do_shuffle and (team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO]):
			if _arrange_seats_for_teams(participants):
				_sync_bots_to_seat_zones()


func _format_summary_text(n: int) -> String:
	if team_count < 2:
		return _label("FREE-FOR-ALL", "各自为战", "各自為戰")
	var counts: Array[String] = []
	for t in range(1, team_count + 1):
		var c: int = 0
		for raw_id in teams.keys():
			if int(teams[raw_id]) == t:
				c += 1
		if c > 0:
			counts.append(str(c))
	var split_tag: String = "v".join(counts) if not counts.is_empty() else ("%d TEAMS" % team_count)
	match team_format:
		FORMAT_DUO:
			return _label("2 PER TEAM (%s)" % split_tag, "2人一队 (%d人 · %s)" % [n, split_tag], "2人一隊 (%d人 · %s)" % [n, split_tag])
		FORMAT_SQUAD:
			return _label("4 PER TEAM (%s)" % split_tag, "红蓝大对抗 (%d人 · %s)" % [n, split_tag], "紅藍大對抗 (%d人 · %s)" % [n, split_tag])
		FORMAT_TRIO:
			return _label("3 PER TEAM (%s)" % split_tag, "3人一队 (%d人 · %s)" % [n, split_tag], "3人一隊 (%d人 · %s)" % [n, split_tag])
		_:
			return _label("%d TEAMS (%s)" % [team_count, split_tag], "自由组队 %d队 (%s)" % [team_count, split_tag], "自由組隊 %d隊 (%s)" % [team_count, split_tag])


func cycle_team_mode() -> void:
	if not _can_host_edit():
		return
	var next_count: int = 0
	match team_count:
		0: next_count = 2
		2: next_count = 3
		3: next_count = 4
		_: next_count = 0
	set_team_mode(next_count)


func set_team_mode(new_count: int) -> void:
	if not _can_host_edit():
		return
	if not (new_count in [0, 2, 3, 4]):
		return
	team_count = new_count
	if team_count == 0:
		team_format = FORMAT_FFA
		teams.clear()
	else:
		if team_format == FORMAT_FFA:
			team_format = FORMAT_CUSTOM
		var participants: Array[Dictionary] = _collect_lobby_participants()
		for raw_id in teams.keys():
			var t: int = int(teams[raw_id])
			if t < 1 or t > team_count:
				teams.erase(raw_id)
		_reconcile_lobby_teams(participants)
	_sync_lobby_camera_angle()
	_publish_state()
	_broadcast_teams()
	_refresh_lobby_ui()
	_sync_lobby_3d_visuals()


func shuffle_teams() -> void:
	if not _can_host_edit():
		return
	var participants: Array[Dictionary] = _collect_lobby_participants()
	if participants.is_empty():
		return
	if team_count < 2:
		team_format = FORMAT_DUO
		team_count = _calc_format_team_count(FORMAT_DUO, participants.size())
	elif team_format == FORMAT_DUO or team_format == FORMAT_SQUAD or team_format == FORMAT_TRIO:
		team_count = _calc_format_team_count(team_format, participants.size())
	_assign_balanced_order(participants, true)
	_sync_lobby_camera_angle()
	_publish_state()
	_broadcast_teams()
	_refresh_lobby_ui()
	_sync_lobby_3d_visuals()
	_notify_lobby_terminal(_label("SHUFFLED: %s" % _format_summary_text(participants.size()),
		"已随机洗牌分队：%s" % _format_summary_text(participants.size()),
		"已隨機洗牌分隊：%s" % _format_summary_text(participants.size())))


func _move_human_seat(actor_id: int, target_seat: int) -> void:
	if not is_instance_valid(lobby) or actor_id <= 0 or target_seat < 0:
		return
	var seat_map = lobby.get("player_order_by_seat")
	if not (seat_map is Dictionary) or not (seat_map as Dictionary).has(target_seat):
		return
	var sm: Dictionary = seat_map as Dictionary
	var occupant: int = int(sm[target_seat])
	if occupant > 0 and occupant != actor_id:
		return
	for k in sm.keys():
		if int(sm[k]) == actor_id:
			sm[k] = -1
	sm[target_seat] = actor_id
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and lobby.has_method("player_list_updated_rpc"):
		lobby.rpc("player_list_updated_rpc", sm)
	elif lobby.has_method("update_player_list"):
		lobby.call("update_player_list")


func _apply_team_join_or_swap(actor_id: int, desired_team: int, target_seat: int = -1, prefer_bot_id: int = 0) -> bool:
	if not _is_host_authoritative() or locked or team_count < 2:
		return false
	if actor_id == 0 or desired_team < 1 or desired_team > team_count:
		return false
	var participants: Array[Dictionary] = _collect_lobby_participants()
	var old_team: int = get_team(actor_id)
	if old_team == desired_team:
		if target_seat >= 0 and actor_id > 0:
			var resolved := _resolved_lobby_seats()
			var seats: Array = resolved["seats"]
			if target_seat < seats.size() and int(seats[target_seat]) == 0:
				_move_human_seat(actor_id, target_seat)
				_sync_bots_to_seat_zones()
				_refresh_lobby_ui()
				_sync_lobby_3d_visuals()
				return true
		return false

	var cap: int = _team_capacity()
	var target_members: Array[Dictionary] = _team_members_list(desired_team, participants)
	var seat_occupied_by_human: bool = false
	if target_seat >= 0 and is_instance_valid(lobby) and (lobby.get("player_order_by_seat") is Dictionary):
		var sm: Dictionary = lobby.get("player_order_by_seat") as Dictionary
		if sm.has(target_seat) and int(sm[target_seat]) > 0:
			seat_occupied_by_human = true

	if cap <= 0 or target_members.size() < cap:
		teams[actor_id] = desired_team
		if target_seat >= 0 and actor_id > 0 and not seat_occupied_by_human:
			_move_human_seat(actor_id, target_seat)
			_sync_bots_to_seat_zones()
		_publish_state()
		_broadcast_teams()
		_refresh_lobby_ui()
		_sync_lobby_3d_visuals()
		return true

	# Fixed-cap format is full: allow Smart Bot Swap when at least one Bot sits on desired_team.
	var swap_bot: int = 0
	if prefer_bot_id != 0 and _is_bot_id(prefer_bot_id) and get_team(prefer_bot_id) == desired_team:
		swap_bot = prefer_bot_id
	else:
		for m in target_members:
			if bool(m.get("is_bot", false)) or _is_bot_id(int(m["id"])):
				swap_bot = int(m["id"])
				break
	if swap_bot != 0:
		var fallback_team: int = old_team if old_team >= 1 else _smallest_team(actor_id)
		teams[actor_id] = desired_team
		teams[swap_bot] = fallback_team
		if target_seat >= 0 and actor_id > 0 and not seat_occupied_by_human:
			_move_human_seat(actor_id, target_seat)
			_sync_bots_to_seat_zones()
		_publish_state()
		_broadcast_teams()
		_refresh_lobby_ui()
		_sync_lobby_3d_visuals()
		return true
	return false


func assign_player_team(target_id: int, desired_team: int) -> void:
	if team_count < 2 or locked:
		return
	if desired_team < 1 or desired_team > team_count:
		return
	var local_id: int = _local_peer_id()
	if _is_host_authoritative():
		teams[target_id] = desired_team
		_publish_state()
		_broadcast_teams()
		_refresh_lobby_ui()
		_sync_lobby_3d_visuals()
	elif target_id == local_id and multiplayer != null and multiplayer.has_multiplayer_peer():
		_rpc_request_change_team.rpc_id(1, desired_team)


func _next_available_team_for(target_id: int) -> int:
	if team_count < 2:
		return 0
	var cur: int = get_team(target_id)
	var cap: int = _team_capacity()
	var participants: Array[Dictionary] = _collect_lobby_participants()
	for step in range(1, team_count + 1):
		var cand: int = ((cur - 1 + step) % team_count) + 1 if cur >= 1 else step
		if cand == cur:
			continue
		if cap <= 0:
			return cand
		var members: Array[Dictionary] = _team_members_list(cand, participants)
		if members.size() < cap:
			return cand
		for m in members:
			if bool(m.get("is_bot", false)) or _is_bot_id(int(m["id"])):
				return cand
	return 0


func cycle_participant_team(target_id: int) -> void:
	if team_count < 2 or locked:
		return
	var local_id: int = _local_peer_id()
	if not _is_host_authoritative() and target_id != local_id:
		return
	_play_ui_click()
	if _is_host_authoritative():
		if _team_capacity() <= 0:
			var cur: int = get_team(target_id)
			var next_t: int = (cur % team_count) + 1 if cur >= 1 else 1
			assign_player_team(target_id, next_t)
		else:
			var next_avail: int = _next_available_team_for(target_id)
			if next_avail > 0:
				_apply_team_join_or_swap(target_id, next_avail, -1, 0)
			else:
				_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
	elif multiplayer != null and multiplayer.has_multiplayer_peer():
		var cur_g: int = get_team(target_id)
		var next_g: int = (cur_g % team_count) + 1 if cur_g >= 1 else 1
		_rpc_request_change_team.rpc_id(1, next_g)


func click_lobby_chair(seat: int, acting_peer_id: int = 0) -> bool:
	if not is_team_mode_active() or locked or not is_instance_valid(lobby):
		return false
	var handler = lobby.get("lobby_handler")
	if handler != null and (not bool(handler.get("active")) or bool(lobby.get("loading"))):
		return false
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if seat < 0 or seat >= seats.size():
		return false

	var caller_id: int = acting_peer_id if acting_peer_id != 0 else _local_peer_id()
	var occ_id: int = int(seats[seat])
	var occ_is_bot: bool = _is_bot_id(occ_id)
	var is_empty: bool = (occ_id == 0)
	var zone_tid: int = _seat_zone_team(seat, seats.size())
	var is_host: bool = _is_host_authoritative() and (acting_peer_id == 0 or acting_peer_id == 1)

	var desired_team: int = zone_tid
	var actor_to_move: int = caller_id
	var target_seat: int = -1
	var prefer_bot: int = 0

	if is_empty:
		if desired_team <= 0:
			desired_team = _next_available_team_for(caller_id)
			if desired_team <= 0:
				desired_team = (get_team(caller_id) % team_count) + 1 if get_team(caller_id) >= 1 else 1
		target_seat = seat
	elif occ_id == caller_id:
		var next_t: int = _next_available_team_for(caller_id)
		if next_t <= 0:
			_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
			return false
		desired_team = next_t
	elif occ_is_bot:
		var bot_team: int = get_team(occ_id)
		desired_team = bot_team if bot_team > 0 else zone_tid
		if is_host and desired_team == get_team(caller_id):
			actor_to_move = occ_id
			desired_team = _next_available_team_for(occ_id)
			if desired_team <= 0:
				_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
				return false
		else:
			prefer_bot = occ_id
			target_seat = seat
	else:
		# Clicked another human player's chair
		if is_host:
			var next_h: int = _next_available_team_for(occ_id)
			if next_h <= 0:
				_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
				return false
			actor_to_move = occ_id
			desired_team = next_h
		else:
			if occ_id == caller_id:
				return false
			_play_ui_click()
			if _is_host_authoritative():
				return _create_or_complete_swap_request(caller_id, occ_id)
			elif multiplayer != null and multiplayer.has_multiplayer_peer():
				_rpc_request_chair_action.rpc_id(1, seat, get_team(occ_id))
				return true
			return false

	_play_ui_click()
	if _is_host_authoritative():
		var ok: bool = _apply_team_join_or_swap(actor_to_move, desired_team, target_seat, prefer_bot)
		if ok and target_seat >= 0:
			_seat_drop_bounce[target_seat] = 0.22
		if not ok and desired_team != get_team(actor_to_move):
			_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
		return ok
	elif multiplayer != null and multiplayer.has_multiplayer_peer():
		_rpc_request_chair_action.rpc_id(1, seat, desired_team)
		return true
	return false


func _swap_lobby_seats(from_seat: int, from_id: int, to_seat: int, to_id: int) -> void:
	if not is_instance_valid(lobby):
		return
	var seat_map = lobby.get("player_order_by_seat")
	if not (seat_map is Dictionary):
		return
	var sm: Dictionary = seat_map as Dictionary
	if not sm.has(from_seat) or not sm.has(to_seat):
		return
	if from_id > 0 and to_id > 0:
		sm[from_seat] = to_id
		sm[to_seat] = from_id
	elif from_id > 0 and to_id <= 0:
		for k in sm.keys():
			if int(sm[k]) == from_id:
				sm[k] = -1
		sm[to_seat] = from_id
	elif from_id < 0 and to_id > 0:
		for k in sm.keys():
			if int(sm[k]) == to_id:
				sm[k] = -1
		sm[from_seat] = to_id
	else:
		return
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and lobby.has_method("player_list_updated_rpc"):
		lobby.rpc("player_list_updated_rpc", sm)
	elif lobby.has_method("update_player_list"):
		lobby.call("update_player_list")


func host_drop_chair(from_seat: int, to_seat: int) -> bool:
	if not _is_host_authoritative() or not is_team_mode_active() or locked or not is_instance_valid(lobby):
		return false
	if from_seat < 0 or to_seat < 0 or from_seat == to_seat:
		return false
	var handler = lobby.get("lobby_handler")
	if handler != null and (not bool(handler.get("active")) or bool(lobby.get("loading"))):
		return false
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if from_seat >= seats.size() or to_seat >= seats.size():
		return false

	var from_id: int = int(seats[from_seat])
	var to_id: int = int(seats[to_seat])
	if from_id == 0:
		return false

	if to_id != 0:
		# 1-to-1 swap (Human<->Human, Human<->Bot, Bot<->Human, Bot<->Bot)
		var t_from: int = get_team(from_id)
		var t_to: int = get_team(to_id)
		if team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO]:
			var z_to: int = _seat_zone_team(to_seat, seats.size())
			var z_from: int = _seat_zone_team(from_seat, seats.size())
			if z_to > 0:
				teams[from_id] = z_to
			if z_from > 0:
				teams[to_id] = z_from
		elif t_from > 0 and t_to > 0:
			teams[from_id] = t_to
			teams[to_id] = t_from
		_swap_lobby_seats(from_seat, from_id, to_seat, to_id)
		if (from_id > 0 and _is_bot_id(to_id)) or (_is_bot_id(from_id) and to_id > 0):
			_sync_bots_to_seat_zones()
		_seat_drop_bounce[to_seat] = 0.24
		_seat_drop_bounce[from_seat] = 0.24
		_publish_state()
		_broadcast_teams()
		_refresh_lobby_ui()
		_sync_lobby_3d_visuals()
		_play_ui_click()
		_broadcast_terminal_notice(_swap_completed_notice(from_id, to_id))
		return true

	# Dropped onto an empty chair
	var zone_tid: int = _seat_zone_team(to_seat, seats.size())
	var desired_team: int = zone_tid if zone_tid > 0 else get_team(from_id)
	if desired_team < 1 or desired_team > team_count:
		desired_team = 1
	var ok: bool = _apply_team_join_or_swap(from_id, desired_team, to_seat, 0)
	if ok:
		_seat_drop_bounce[to_seat] = 0.24
		_play_ui_click()
	else:
		_notify_lobby_terminal(_label("TEAM FULL", "队伍已满", "隊伍已滿"))
	return ok


func _on_cycle_mode_pressed() -> void:
	_play_ui_click()
	cycle_team_mode()


func _on_custom_count_pressed() -> void:
	if not _can_host_edit():
		return
	_play_ui_click()
	var next_c: int = 3 if team_count == 2 else (4 if team_count == 3 else 2)
	team_format = FORMAT_CUSTOM
	set_team_mode(next_c)


func _on_shuffle_pressed() -> void:
	_play_ui_click()
	shuffle_teams()


func _on_my_team_pressed() -> void:
	if not _can_guest_pick_self():
		return
	cycle_participant_team(_local_peer_id())


func _broadcast_teams() -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_teams.rpc(team_count, teams.duplicate(), team_format, _hud_wins.duplicate())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_change_team(desired_team: int) -> void:
	if not _is_host_authoritative() or locked or team_count < 2:
		return
	var sender: int = multiplayer.get_remote_sender_id() if multiplayer != null else 0
	if sender <= 0:
		return
	if desired_team < 1 or desired_team > team_count:
		return
	_apply_team_join_or_swap(sender, desired_team, -1, 0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_chair_action(target_seat: int, desired_team: int) -> void:
	if not _is_host_authoritative() or locked or team_count < 2:
		return
	var sender: int = multiplayer.get_remote_sender_id() if multiplayer != null else 0
	if sender <= 0:
		return
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if target_seat < 0 or target_seat >= seats.size():
		return
	var occ_id: int = int(seats[target_seat])
	var zone_tid: int = _seat_zone_team(target_seat, seats.size())
	var target_team: int = desired_team
	var seat_arg: int = -1
	var prefer_bot: int = 0
	if occ_id == 0:
		target_team = zone_tid if zone_tid > 0 else desired_team
		seat_arg = target_seat
	elif _is_bot_id(occ_id):
		var bt: int = get_team(occ_id)
		target_team = bt if bt > 0 else desired_team
		prefer_bot = occ_id
		seat_arg = target_seat
	elif occ_id != sender:
		_create_or_complete_swap_request(sender, occ_id)
		return
	if target_team < 1 or target_team > team_count:
		return
	_apply_team_join_or_swap(sender, target_team, seat_arg, prefer_bot)


func _participant_display_name(nid: int) -> String:
	for p in _collect_lobby_participants():
		if int(p["id"]) == nid:
			return strip_team_prefix(str(p.get("name", "Player %d" % nid)))
	return "Player %d" % nid


func _clear_swap_requests_for(peer_id: int) -> void:
	_pending_swap_requests.erase(peer_id)
	var erase_keys: Array = []
	for k in _pending_swap_requests.keys():
		var req = _pending_swap_requests[k]
		if req is Dictionary and int((req as Dictionary).get("from_id", 0)) == peer_id:
			erase_keys.append(k)
	for ek in erase_keys:
		_pending_swap_requests.erase(ek)
	if _incoming_swap_from == peer_id:
		_incoming_swap_from = 0
		_incoming_swap_name = ""
		_incoming_swap_expires = 0.0


func _has_connected_remote_peer(peer_id: int) -> bool:
	if peer_id <= 0 or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return false
	return peer_id in multiplayer.get_peers()


func _deliver_swap_offer(target_id: int, from_id: int) -> void:
	var from_name: String = _participant_display_name(from_id)
	if target_id == _local_peer_id():
		_incoming_swap_from = from_id
		_incoming_swap_name = from_name
		_incoming_swap_expires = _anim_time + 12.0
		_refresh_lobby_ui()
	elif _has_connected_remote_peer(target_id):
		_rpc_receive_swap_offer.rpc_id(target_id, from_id, from_name)


func _deliver_terminal_notice(peer_id: int, msg: String) -> void:
	if peer_id == _local_peer_id():
		_notify_lobby_terminal(msg)
	elif _has_connected_remote_peer(peer_id):
		_rpc_notify_terminal.rpc_id(peer_id, msg)


func _broadcast_terminal_notice(msg: String) -> void:
	_notify_lobby_terminal(msg)
	if _is_host_authoritative() and _has_any_remote_peers():
		_rpc_notify_terminal.rpc(msg)


func _swap_completed_notice(id_a: int, id_b: int) -> String:
	var na: String = _participant_display_name(id_a)
	var nb: String = _participant_display_name(id_b)
	return _label("%s ⇄ %s SWAPPED SEATS" % [na, nb], "%s 与 %s 已互换座位" % [na, nb], "%s 與 %s 已互換座位" % [na, nb])


func _execute_human_seat_swap(id_a: int, id_b: int) -> bool:
	if not _is_host_authoritative() or locked or team_count < 2 or not is_instance_valid(lobby):
		return false
	if id_a <= 0 or id_b <= 0 or id_a == id_b:
		return false
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var seat_a: int = seats.find(id_a)
	var seat_b: int = seats.find(id_b)
	if seat_a < 0 or seat_b < 0 or seat_a == seat_b:
		return false
	var t_a: int = get_team(id_a)
	var t_b: int = get_team(id_b)
	if team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO]:
		var z_a: int = _seat_zone_team(seat_a, seats.size())
		var z_b: int = _seat_zone_team(seat_b, seats.size())
		if z_b > 0:
			teams[id_a] = z_b
		if z_a > 0:
			teams[id_b] = z_a
	elif t_a > 0 and t_b > 0:
		teams[id_a] = t_b
		teams[id_b] = t_a
	_swap_lobby_seats(seat_a, id_a, seat_b, id_b)
	_seat_drop_bounce[seat_a] = 0.24
	_seat_drop_bounce[seat_b] = 0.24
	_broadcast_drag_end(-1, [seat_a, seat_b])
	_publish_state()
	_broadcast_teams()
	_refresh_lobby_ui()
	_sync_lobby_3d_visuals()
	_play_ui_click()
	return true


func _create_or_complete_swap_request(from_id: int, target_id: int) -> bool:
	if not _is_host_authoritative() or locked or team_count < 2:
		return false
	if from_id <= 0 or target_id <= 0 or from_id == target_id:
		return false
	if _pending_swap_requests.has(from_id):
		var rev = _pending_swap_requests[from_id]
		if rev is Dictionary and int((rev as Dictionary).get("from_id", 0)) == target_id:
			_clear_swap_requests_for(from_id)
			_clear_swap_requests_for(target_id)
			var ok_mut: bool = _execute_human_seat_swap(from_id, target_id)
			if ok_mut:
				_broadcast_terminal_notice(_swap_completed_notice(from_id, target_id))
			return ok_mut
	_pending_swap_requests[target_id] = {"from_id": from_id, "expires_at": _anim_time + 12.0}
	_deliver_swap_offer(target_id, from_id)
	var tname: String = _participant_display_name(target_id)
	_deliver_terminal_notice(from_id, _label("SWAP REQUEST SENT TO %s" % tname, "已向 %s 发出换位请求" % tname, "已向 %s 發出換位請求" % tname))
	return true


func respond_swap_request(accepted: bool, responding_peer_id: int = 0) -> bool:
	var responder: int = responding_peer_id if responding_peer_id != 0 else _local_peer_id()
	if _is_host_authoritative():
		if not _pending_swap_requests.has(responder):
			if responder == _local_peer_id() and _incoming_swap_from != 0:
				_incoming_swap_from = 0
				_incoming_swap_name = ""
				_incoming_swap_expires = 0.0
				_refresh_lobby_ui()
			return false
		var req: Dictionary = _pending_swap_requests[responder] as Dictionary
		var from_id: int = int(req.get("from_id", 0))
		_pending_swap_requests.erase(responder)
		if responder == _local_peer_id() and _incoming_swap_from == from_id:
			_incoming_swap_from = 0
			_incoming_swap_name = ""
			_incoming_swap_expires = 0.0
		if accepted:
			var swapped: bool = _execute_human_seat_swap(from_id, responder)
			if swapped:
				_broadcast_terminal_notice(_swap_completed_notice(from_id, responder))
			_refresh_lobby_ui()
			return swapped
		else:
			var rname: String = _participant_display_name(responder)
			_deliver_terminal_notice(from_id, _label("%s DECLINED SWAP" % rname, "%s 已拒绝换位" % rname, "%s 已拒絕換位" % rname))
			_refresh_lobby_ui()
			return true
	elif multiplayer != null and multiplayer.has_multiplayer_peer() and _incoming_swap_from > 0:
		var offer_from: int = _incoming_swap_from
		_incoming_swap_from = 0
		_incoming_swap_name = ""
		_incoming_swap_expires = 0.0
		_rpc_respond_swap.rpc_id(1, offer_from, accepted)
		_refresh_lobby_ui()
		return true
	return false


func _on_swap_accept_pressed() -> void:
	_play_ui_click()
	respond_swap_request(true)


func _on_swap_decline_pressed() -> void:
	_play_ui_click()
	respond_swap_request(false)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_respond_swap(from_id: int, accepted: bool) -> void:
	if not _is_host_authoritative() or locked or team_count < 2:
		return
	var sender: int = multiplayer.get_remote_sender_id() if multiplayer != null else 0
	if sender <= 0 or not _pending_swap_requests.has(sender):
		return
	var req = _pending_swap_requests[sender]
	if req is Dictionary and int((req as Dictionary).get("from_id", 0)) == from_id:
		respond_swap_request(accepted, sender)


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_swap_offer(from_id: int, from_name: String) -> void:
	_incoming_swap_from = from_id
	_incoming_swap_name = from_name
	_incoming_swap_expires = _anim_time + 12.0
	_refresh_lobby_ui()


@rpc("authority", "call_remote", "reliable")
func _rpc_notify_terminal(msg: String) -> void:
	_notify_lobby_terminal(msg)


func _has_any_remote_peers() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()


func _broadcast_drag_begin() -> void:
	if _is_host_authoritative() and _drag_active and not _drag_is_remote and _has_any_remote_peers():
		_drag_net_accum = 0.0
		_drag_last_sent_pos = _drag_target_pos
		_drag_last_sent_hover = _hovered_seat
		_rpc_drag_begin.rpc(_drag_seat, _drag_target_pos, _hovered_seat)


func _broadcast_drag_pose_if_due(delta: float) -> void:
	if not _is_host_authoritative() or not _drag_active or _drag_is_remote or not _has_any_remote_peers():
		return
	_drag_net_accum += delta
	if _drag_net_accum < 0.05:
		return
	var pos_moved: bool = _drag_target_pos.distance_squared_to(_drag_last_sent_pos) > 0.0004
	if not pos_moved and _hovered_seat == _drag_last_sent_hover:
		return
	_drag_net_accum = 0.0
	_drag_last_sent_pos = _drag_target_pos
	_drag_last_sent_hover = _hovered_seat
	_rpc_drag_pose.rpc(_drag_seat, _drag_target_pos, _hovered_seat)


func _broadcast_drag_end(from_seat: int, bounce_seats: Array) -> void:
	if _is_host_authoritative() and not _drag_is_remote and _has_any_remote_peers():
		_rpc_drag_end.rpc(from_seat, bounce_seats)


func _apply_remote_drag_begin(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not is_instance_valid(lobby) or not lobby.is_inside_tree():
		return
	var handler = lobby.get("lobby_handler")
	if handler == null:
		return
	var players_arr = handler.get("players")
	var nametags = handler.get("nametags")
	if not (players_arr is Array) or seat < 0 or seat >= (players_arr as Array).size():
		return
	_restore_drag_skeleton()
	if _drag_seat >= 0:
		_restore_slot_transform(_drag_seat)
	if _hop_seat >= 0:
		_restore_slot_transform(_hop_seat)
		_hop_seat = -1
	var snode: Node3D = (players_arr as Array)[seat] as Node3D if (players_arr as Array)[seat] is Node3D else null
	if snode == null or not is_instance_valid(snode):
		return
	var slbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags is Array and seat < (nametags as Array).size()) else null
	_drag_orig_floor = _seat_world_floor_pos(snode, slbl, seat)
	_drag_rest_collar = Vector3(_drag_orig_floor.x, 2.05, _drag_orig_floor.z)
	if not _seat_drop_bounce.has(seat):
		_lobby_seat_rest_slot_xform[seat] = snode.transform
	_drag_seat = seat
	_drag_actor_id = 0
	_drag_active = true
	_drag_is_remote = true
	_drag_elapsed = 0.0
	_drag_visual_pos = _drag_rest_collar
	_drag_target_pos = target_pos
	_drag_vel = Vector3(0.0, 3.0, 0.0)
	_hovered_seat = hover_seat
	_begin_drag_skeleton(snode)
	_update_lobby_nametags()


func _apply_remote_drag_pose(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not _drag_active or not _drag_is_remote or _drag_seat != seat:
		return
	_drag_target_pos = target_pos
	if hover_seat != _hovered_seat:
		_hovered_seat = hover_seat
		if is_instance_valid(lobby) and lobby.is_inside_tree():
			_update_lobby_nametags()


func _apply_remote_drag_end(from_seat: int, bounce_seats: Array) -> void:
	_restore_drag_skeleton()
	if _drag_seat >= 0:
		_restore_slot_transform(_drag_seat)
	if from_seat >= 0:
		_restore_slot_transform(from_seat)
	if _hop_seat >= 0:
		_restore_slot_transform(_hop_seat)
		_hop_seat = -1
	_drag_seat = -1
	_drag_actor_id = 0
	_drag_active = false
	_drag_is_remote = false
	_drag_vel = Vector3.ZERO
	_drag_elapsed = 0.0
	_hovered_seat = -1
	for bs in bounce_seats:
		_seat_drop_bounce[int(bs)] = 0.24
	if is_instance_valid(lobby) and lobby.is_inside_tree():
		_update_lobby_nametags()


@rpc("authority", "call_remote", "reliable")
func _rpc_drag_begin(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not _is_host_authoritative():
		_apply_remote_drag_begin(seat, target_pos, hover_seat)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_drag_pose(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not _is_host_authoritative():
		_apply_remote_drag_pose(seat, target_pos, hover_seat)


@rpc("authority", "call_remote", "reliable")
func _rpc_drag_end(from_seat: int, bounce_seats: Array) -> void:
	if not _is_host_authoritative():
		_apply_remote_drag_end(from_seat, bounce_seats)


@rpc("authority", "call_remote", "reliable")
func _sync_teams(count: int, mapping: Dictionary, fmt: int = -1, wins: Dictionary = {}) -> void:
	team_count = count
	if fmt >= 0:
		team_format = fmt
	elif team_count == 0:
		team_format = FORMAT_FFA
	elif team_format == FORMAT_FFA:
		team_format = FORMAT_CUSTOM
	teams.clear()
	for k in mapping.keys():
		teams[int(k)] = int(mapping[k])
	if count == 0:
		if _drag_is_remote:
			_cancel_lobby_drag()
		_hud_wins.clear()
		_pending_swap_requests.clear()
		_incoming_swap_from = 0
		_incoming_swap_name = ""
		_incoming_swap_expires = 0.0
	elif not wins.is_empty():
		_hud_wins.clear()
		for wk in wins.keys():
			_hud_wins[int(wk)] = int(wins[wk])
	_publish_state()
	_refresh_lobby_ui()
	_sync_lobby_3d_visuals()
	_refresh_hud(true)


func _mode_button_text() -> String:
	var n: int = _collect_lobby_participants().size()
	if team_count < 2:
		return _label("Teams: Off (Free-for-All)", "当前：个人混战 (点击切 2 队)", "目前：個人混戰 (點擊切 2 隊)")
	return _format_summary_text(n)


func _split_badge_text(participants: Array[Dictionary]) -> String:
	if team_count < 2:
		return _label("OFF", "关", "關")
	var counts: Array[String] = []
	for t in range(1, team_count + 1):
		var c: int = 0
		for p in participants:
			if get_team(int(p["id"])) == t:
				c += 1
		if c > 0:
			counts.append(str(c))
	if not counts.is_empty():
		return "v".join(counts)
	return "%dT" % team_count


func _refresh_lobby_ui() -> void:
	if not is_instance_valid(panel):
		return
	var is_host: bool = _is_host_authoritative()
	var participants: Array[Dictionary] = _collect_lobby_participants()
	var active_teams: bool = team_count >= 2

	var fmt_bar := panel.find_child("FormatBar", true, false) as HBoxContainer
	if fmt_bar != null:
		fmt_bar.visible = is_host

	for fcode_raw in _format_buttons.keys():
		var fcode: int = int(fcode_raw)
		var fbtn: Button = _format_buttons[fcode_raw] as Button
		if is_instance_valid(fbtn):
			var is_sel: bool = (team_format == fcode) or (team_count == 0 and fcode == FORMAT_FFA)
			fbtn.disabled = not is_host or locked
			_style_crt_button(fbtn, Color.WHITE, is_sel, 20)

	if is_instance_valid(_actions_row):
		_actions_row.visible = active_teams and is_host
	if is_instance_valid(shuffle_button):
		shuffle_button.visible = active_teams and is_host
		shuffle_button.disabled = locked
		_style_crt_button(shuffle_button, Color.WHITE, false, 20)
	if is_instance_valid(mode_button):
		mode_button.visible = active_teams and is_host and team_format == FORMAT_CUSTOM
		mode_button.disabled = locked
		mode_button.text = "%d%s" % [team_count, _label(" TEAMS", "队", "隊")]
		_style_crt_button(mode_button, Color.WHITE, false, 20)
	if is_instance_valid(my_team_button):
		my_team_button.visible = false

	if is_instance_valid(_hint_label):
		if active_teams:
			_hint_label.visible = true
			if is_host:
				_hint_label.text = "%s · %s" % [
					_split_badge_text(participants),
					_label("DRAG WORKER TO MOVE / CLICK CHAIR", "拖拽人物换椅 / 点击入座", "拖曳人物換椅 / 點擊入座"),
				]
			else:
				_hint_label.text = "%s (%s) · %s" % [
					_label("SQUADS", "组队", "組隊"),
					_split_badge_text(participants),
					_label("CLICK EMPTY CHAIR / CLICK PLAYER TO SWAP", "点击空椅入座 / 点击玩家请求换位", "點擊空椅入座 / 點擊玩家請求換位"),
				]
			_style_outline_label(_hint_label, Color.WHITE, 16, 5)
		else:
			_hint_label.visible = false

	if is_instance_valid(_swap_offer_row):
		var show_offer: bool = active_teams and not locked and _incoming_swap_from > 0
		_swap_offer_row.visible = show_offer
		if show_offer:
			if is_instance_valid(_swap_offer_label):
				_swap_offer_label.text = _label(
					"%s WANTS TO SWAP" % _incoming_swap_name,
					"%s 请求与你换位" % _incoming_swap_name,
					"%s 請求與你換位" % _incoming_swap_name
				)
				_style_outline_label(_swap_offer_label, Color(1.0, 0.92, 0.45), 16, 5)
			if is_instance_valid(_swap_accept_btn):
				_style_crt_button(_swap_accept_btn, Color.WHITE, true, 18)
			if is_instance_valid(_swap_decline_btn):
				_style_crt_button(_swap_decline_btn, Color.WHITE, false, 18)


func _short_team_code(tid: int) -> String:
	var is_tw: bool = _is_tw_locale()
	var is_cn: bool = _is_cn_locale()
	match tid:
		1: return "■紅" if is_tw else ("■红" if is_cn else "RED")
		2: return "■藍" if is_tw else ("■蓝" if is_cn else "BLU")
		3: return "■綠" if is_tw else ("■绿" if is_cn else "GRN")
		4: return "■黃" if is_tw else ("■黄" if is_cn else "YEL")
		_: return "■"


func _clear_lobby_3d_rings() -> void:
	for k in _lobby_seat_rings.keys():
		var ring = _lobby_seat_rings[k]
		if is_instance_valid(ring) and ring is Node:
			(ring as Node).queue_free()
	_lobby_seat_rings.clear()
	for k in _lobby_seat_halos.keys():
		var halo = _lobby_seat_halos[k]
		if is_instance_valid(halo) and halo is Node:
			(halo as Node).queue_free()
	_lobby_seat_halos.clear()
	_lobby_seat_rest_floor.clear()
	_lobby_seat_rest_slot_xform.clear()
	_seat_drop_bounce.clear()
	_hop_seat = -1


func _seat_world_floor_pos(slot_node: Node3D, lbl: Label3D, seat: int = -1) -> Vector3:
	if seat >= 0 and _lobby_seat_rest_floor.has(seat):
		return _lobby_seat_rest_floor[seat] as Vector3
	var pos := Vector3(0.0, 0.06, 0.0)
	if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
		pos = Vector3(lbl.global_position.x, 0.06, lbl.global_position.z)
	elif slot_node != null and is_instance_valid(slot_node) and slot_node.is_inside_tree():
		var arm := slot_node.get_node_or_null("main character2/Armature_001") as Node3D
		if arm != null and arm.is_inside_tree():
			pos = Vector3(arm.global_position.x, 0.06, arm.global_position.z)
		else:
			pos = Vector3(slot_node.global_position.x, 0.06, slot_node.global_position.z)
	if seat >= 0 and not (_drag_active and seat == _drag_seat) and not _seat_drop_bounce.has(seat) and seat != _hop_seat and slot_node != null and slot_node.is_inside_tree():
		_lobby_seat_rest_floor[seat] = pos
	return pos


func _make_chair_torus_mesh(inner_r: float, outer_r: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = outer_r
	torus.rings = 28
	torus.ring_segments = 6
	return torus


func _ensure_lobby_chair_ring(seat: int, slot_node: Node3D, lbl: Label3D) -> MeshInstance3D:
	if _lobby_seat_rings.has(seat):
		var existing = _lobby_seat_rings[seat]
		if is_instance_valid(existing) and existing is MeshInstance3D:
			return existing as MeshInstance3D
	var ring := MeshInstance3D.new()
	ring.name = "TeamChairRing_%d" % seat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.mesh = _make_chair_torus_mesh(0.54, 0.68)
	ring.scale = Vector3(1.0, 0.14, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	var container: Node = slot_node.get_parent() if (slot_node != null and slot_node.get_parent() != null) else slot_node
	container.add_child(ring)
	var floor_w: Vector3 = _seat_world_floor_pos(slot_node, lbl, seat)
	if container is Node3D and (container as Node3D).is_inside_tree():
		ring.position = (container as Node3D).to_local(floor_w)
	else:
		ring.position = floor_w
	_lobby_seat_rings[seat] = ring
	return ring


func _ensure_lobby_chair_halo(seat: int, slot_node: Node3D, lbl: Label3D) -> MeshInstance3D:
	if _lobby_seat_halos.has(seat):
		var existing = _lobby_seat_halos[seat]
		if is_instance_valid(existing) and existing is MeshInstance3D:
			return existing as MeshInstance3D
	var halo := MeshInstance3D.new()
	halo.name = "TeamChairHalo_%d" % seat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.mesh = _make_chair_torus_mesh(0.34, 0.43)
	halo.scale = Vector3(1.0, 0.14, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.material_override = mat
	var container: Node = slot_node.get_parent() if (slot_node != null and slot_node.get_parent() != null) else slot_node
	container.add_child(halo)
	var floor_w: Vector3 = _seat_world_floor_pos(slot_node, lbl, seat) + Vector3(0.0, 0.02, 0.0)
	if container is Node3D and (container as Node3D).is_inside_tree():
		halo.position = (container as Node3D).to_local(floor_w)
	else:
		halo.position = floor_w
	_lobby_seat_halos[seat] = halo
	return halo


func _seat_zone_blocked_for_local(zone_tid: int, cap: int, local_id: int, participants: Array[Dictionary]) -> bool:
	if zone_tid <= 0 or cap <= 0 or get_team(local_id) == zone_tid:
		return false
	var zm: Array[Dictionary] = _team_members_list(zone_tid, participants)
	if zm.size() < cap:
		return false
	for m in zm:
		if bool(m.get("is_bot", false)) or _is_bot_id(int(m["id"])):
			return false
	return true


func _apply_chair_ring_and_halo(
	seat: int,
	slot_node: Node3D,
	lbl: Label3D,
	chair_col: Color,
	occupied: bool,
	is_hov: bool,
	is_drag_src: bool,
	zone_full_humans: bool
) -> void:
	var ring := _ensure_lobby_chair_ring(seat, slot_node, lbl)
	var halo := _ensure_lobby_chair_halo(seat, slot_node, lbl)
	var floor_w: Vector3 = _seat_world_floor_pos(slot_node, lbl, seat)
	var container: Node = halo.get_parent()
	var bounce_rem: float = float(_seat_drop_bounce.get(seat, 0.0))

	ring.visible = true
	halo.visible = true

	var ring_s: float = 1.0
	var ring_a: float = 0.78 if occupied else 0.56
	var ring_col: Color = chair_col
	var halo_s: float = 1.0
	var halo_y: float = 0.02
	var halo_a: float = 0.20
	var halo_col: Color = chair_col

	if bounce_rem > 0.0:
		var rt: float = clampf(1.0 - (bounce_rem / 0.24), 0.0, 1.0)
		ring_s = 1.0 + sin(rt * PI) * 0.16
		ring_a = 1.0
		ring_col = chair_col.lerp(Color.WHITE, 0.35 * (1.0 - rt))
		halo_s = lerpf(0.95, 1.65, rt)
		halo_y = 0.02 + (1.0 - rt) * 0.06
		halo_a = (1.0 - rt) * 0.95
		halo_col = chair_col.lerp(Color.WHITE, 0.55)
	elif is_drag_src:
		ring_s = 0.95
		ring_a = 0.30
		halo_s = 0.90
		halo_a = 0.18
	elif _drag_active and is_hov:
		if occupied:
			# Occupied swap target: brisk pulse on ring & halo (worker also performs anticipation hop)
			var sp: float = 0.5 + 0.5 * sin(_anim_time * 10.0)
			ring_s = 1.15 + 0.08 * sp
			ring_a = 1.0
			ring_col = chair_col.lerp(Color.WHITE, 0.25 + 0.2 * sp)
			halo_s = 1.08 + 0.14 * sp
			halo_y = 0.08 + 0.08 * sp
			halo_a = 0.95
			halo_col = chair_col.lerp(Color.WHITE, 0.5)
		else:
			# Empty drop target: pure 3D rising beacon animation (zero text badge)
			var p: float = fmod(_anim_time * 1.85, 1.0)
			ring_s = 1.16 + 0.07 * sin(_anim_time * 8.5)
			ring_a = 0.98
			ring_col = chair_col.lerp(Color.WHITE, 0.35)
			halo_s = lerpf(1.26, 0.72, p)
			halo_y = 0.06 + p * 0.78
			halo_a = (1.0 - p) * 0.94
			halo_col = chair_col.lerp(Color.WHITE, 0.55)
	elif not occupied:
		var pulse: float = 0.5 + 0.5 * sin(_anim_time * 3.0 + float(seat) * 0.75)
		if zone_full_humans:
			ring_s = 1.0
			ring_a = 0.32
			halo_s = 0.92
			halo_y = 0.02
			halo_a = 0.14
		elif is_hov:
			ring_s = 1.14
			ring_a = 0.95
			ring_col = chair_col.lerp(Color.WHITE, 0.2)
			halo_s = 1.05 + 0.14 * pulse
			halo_y = 0.04 + 0.12 * pulse
			halo_a = 0.72 + 0.24 * pulse
			halo_col = chair_col.lerp(Color.WHITE, 0.45)
		else:
			ring_s = 1.0 + 0.02 * pulse
			ring_a = 0.58 + 0.10 * pulse
			halo_s = 0.92 + 0.14 * pulse
			halo_y = 0.02 + 0.05 * pulse
			halo_a = 0.36 + 0.30 * pulse
	elif is_hov:
		ring_s = 1.13
		ring_a = 0.98
		ring_col = chair_col.lerp(Color.WHITE, 0.18)
		halo_s = 1.15
		halo_y = 0.05
		halo_a = 0.72
		halo_col = chair_col.lerp(Color.WHITE, 0.35)

	ring.scale = Vector3(ring_s, 0.18 if is_hov else 0.14, ring_s)
	halo.scale = Vector3(halo_s, 0.14, halo_s)
	var halo_w: Vector3 = floor_w + Vector3(0.0, halo_y, 0.0)
	if container is Node3D and (container as Node3D).is_inside_tree():
		halo.position = (container as Node3D).to_local(halo_w)
	else:
		halo.position = halo_w
	var rmat := ring.material_override as StandardMaterial3D
	if rmat != null:
		rmat.albedo_color = Color(ring_col.r, ring_col.g, ring_col.b, ring_a)
	var hmat := halo.material_override as StandardMaterial3D
	if hmat != null:
		hmat.albedo_color = Color(halo_col.r, halo_col.g, halo_col.b, halo_a)


func _animate_lobby_seats(delta: float) -> void:
	if not is_instance_valid(lobby):
		return
	var handler = lobby.get("lobby_handler")
	if handler == null:
		return
	var players_arr = handler.get("players")
	var nametags = handler.get("nametags")
	if not (players_arr is Array) or not (nametags is Array):
		return

	# 1. Advance landing squash-and-bounce transitions
	if not _seat_drop_bounce.is_empty():
		var finished: Array = []
		for s_key in _seat_drop_bounce.keys():
			var s_idx: int = int(s_key)
			var rem: float = float(_seat_drop_bounce[s_key]) - delta
			if rem <= 0.0:
				finished.append(s_key)
				_restore_slot_transform(s_idx)
			else:
				_seat_drop_bounce[s_key] = rem
				if s_idx >= 0 and s_idx < (players_arr as Array).size() and not (_drag_active and s_idx == _drag_seat):
					var bnode = (players_arr as Array)[s_idx]
					if bnode is Node3D and is_instance_valid(bnode):
						var t: float = clampf(1.0 - (rem / 0.24), 0.0, 1.0)
						var by: float = sin(t * PI) * exp(-t * 2.5) * 0.28
						var sq: float = sin(t * PI * 2.0) * (1.0 - t) * 0.16
						var stretch := Vector3(1.0 + sq * 0.65, maxf(0.76, 1.0 - sq), 1.0 + sq * 0.65)
						_set_slot_pivot_pose(bnode as Node3D, s_idx, Vector3(0.0, by, 0.0), Vector3.ZERO, stretch)
		for fkey in finished:
			_seat_drop_bounce.erase(fkey)

	# 2. Drive anticipation hop on occupied swap-target chair during drag
	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = mini(seats.size(), mini((nametags as Array).size(), (players_arr as Array).size()))
	var want_hop: int = -1
	if _drag_active and _hovered_seat >= 0 and _hovered_seat != _drag_seat and _hovered_seat < total_seats:
		if int(seats[_hovered_seat]) != 0:
			want_hop = _hovered_seat
	if _hop_seat >= 0 and _hop_seat != want_hop:
		if not _seat_drop_bounce.has(_hop_seat):
			_restore_slot_transform(_hop_seat)
		_hop_seat = -1
	if want_hop >= 0 and not _seat_drop_bounce.has(want_hop):
		_hop_seat = want_hop
		var hnode = (players_arr as Array)[want_hop]
		if hnode is Node3D and is_instance_valid(hnode):
			var hop_y: float = absf(sin(_anim_time * 7.5)) * 0.16
			var hop_tilt: float = sin(_anim_time * 7.5) * 0.06
			_set_slot_pivot_pose(hnode as Node3D, want_hop, Vector3(0.0, hop_y, 0.0), Vector3(0.0, 0.0, hop_tilt), Vector3.ONE)

	# 3. Animate 3D chair rings & halos cleanly in real-time
	if not is_team_mode_active() or not ResourceLoader.exists("res://scenes/lobby/lobby_scene.tscn"):
		return
	var cap: int = _team_capacity()
	var local_id: int = _local_peer_id()
	var participants: Array[Dictionary] = _collect_lobby_participants()
	var fixed_zone: bool = (team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO])
	for seat in range(total_seats):
		var slot_node: Node3D = (players_arr as Array)[seat] as Node3D if (players_arr as Array)[seat] is Node3D else null
		if slot_node == null:
			continue
		var lbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags as Array)[seat] is Label3D else null
		var nid: int = int(seats[seat])
		var occupied: bool = (nid != 0) and slot_node.visible
		var zone_tid: int = _seat_zone_team(seat, total_seats)
		var is_hov: bool = (seat == _hovered_seat) and not locked
		if occupied and get_team(nid) > 0:
			var tid: int = get_team(nid)
			var chair_col: Color = get_team_color(zone_tid) if (fixed_zone and zone_tid > 0) else get_team_color(tid)
			_apply_chair_ring_and_halo(seat, slot_node, lbl, chair_col, true, is_hov, _drag_active and seat == _drag_seat, false)
		elif not occupied:
			var empty_col: Color = get_team_color(zone_tid) if zone_tid > 0 else Color(0.88, 0.88, 0.88)
			var zone_full_humans: bool = _seat_zone_blocked_for_local(zone_tid, cap, local_id, participants)
			_apply_chair_ring_and_halo(seat, slot_node, lbl, empty_col, false, is_hov, false, zone_full_humans)


func _sync_lobby_3d_visuals() -> void:
	_update_lobby_nametags()


func _can_interact_with_seat(seat: int, occ_id: int) -> bool:
	if not is_team_mode_active() or locked:
		return false
	if occ_id == 0:
		return true
	if occ_id == _local_peer_id() or _is_bot_id(occ_id):
		return true
	return _is_host_authoritative() or get_team(occ_id) != get_team(_local_peer_id())


func _update_lobby_nametags() -> void:
	if not is_instance_valid(lobby):
		return
	var handler = lobby.get("lobby_handler")
	if handler == null:
		return
	var nametags = handler.get("nametags")
	var players_arr = handler.get("players")
	if not (nametags is Array) or not (players_arr is Array):
		return

	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = mini(seats.size(), mini((nametags as Array).size(), (players_arr as Array).size()))
	var active_teams: bool = is_team_mode_active()
	var cap: int = _team_capacity()
	var participants: Array[Dictionary] = []
	if active_teams:
		participants = _collect_lobby_participants()
	var local_id: int = _local_peer_id()
	var ui_font: Font = _get_ui_font()
	var has_3d_lobby: bool = ResourceLoader.exists("res://scenes/lobby/lobby_scene.tscn")

	for seat in range(total_seats):
		var slot_obj = (players_arr as Array)[seat]
		var slot_node: Node3D = slot_obj as Node3D if slot_obj is Node3D else null
		var tag_node = (nametags as Array)[seat]
		if not (tag_node is Label3D) or not is_instance_valid(tag_node):
			continue
		var lbl: Label3D = tag_node as Label3D
		if not _orig_nametag_alpha.has(seat):
			_orig_nametag_alpha[seat] = lbl.modulate.a
		var nid: int = int(seats[seat])
		var slot_visible: bool = slot_node == null or slot_node.visible
		var occupied: bool = (nid != 0) and slot_visible
		if slot_node != null and slot_node.is_inside_tree() and not (_drag_active and seat == _drag_seat) and not _seat_drop_bounce.has(seat) and seat != _hop_seat:
			_lobby_seat_rest_slot_xform[seat] = slot_node.transform
		var zone_tid: int = _seat_zone_team(seat, total_seats)
		var is_hov: bool = (seat == _hovered_seat) and not locked
		var show_empty_chair: bool = active_teams and not occupied
		var fixed_zone: bool = (team_format in [FORMAT_DUO, FORMAT_SQUAD, FORMAT_TRIO])

		if active_teams and occupied and get_team(nid) > 0:
			var tid: int = get_team(nid)
			if not lbl.text.is_empty():
				var formatted: String = format_team_nickname(nid, lbl.text)
				if lbl.text != formatted:
					lbl.text = formatted
			if ui_font != null and lbl.font != ui_font:
				lbl.font = ui_font
			var tcol: Color = get_team_color(tid)
			var boost_a: float = 0.96 if float(_orig_nametag_alpha[seat]) < 0.85 else lbl.modulate.a
			var target_col := Color(tcol.r, tcol.g, tcol.b, boost_a)
			if not lbl.modulate.is_equal_approx(target_col):
				lbl.modulate = target_col
			lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.94)

			if slot_node != null and has_3d_lobby:
				var chair_col: Color = get_team_color(zone_tid) if (fixed_zone and zone_tid > 0) else tcol
				_apply_chair_ring_and_halo(seat, slot_node, lbl, chair_col, true, is_hov, _drag_active and seat == _drag_seat, false)
		elif show_empty_chair:
			if ui_font != null and lbl.font != ui_font:
				lbl.font = ui_font
			if slot_node != null and has_3d_lobby:
				var zone_full_humans: bool = _seat_zone_blocked_for_local(zone_tid, cap, local_id, participants)
				var empty_col: Color = get_team_color(zone_tid) if zone_tid > 0 else Color(0.88, 0.88, 0.88)
				_apply_chair_ring_and_halo(seat, slot_node, lbl, empty_col, false, is_hov, false, zone_full_humans)
		else:
			if not occupied:
				if _lobby_seat_rings.has(seat) and is_instance_valid(_lobby_seat_rings[seat]):
					(_lobby_seat_rings[seat] as Node3D).visible = false
				if _lobby_seat_halos.has(seat) and is_instance_valid(_lobby_seat_halos[seat]):
					(_lobby_seat_halos[seat] as Node3D).visible = false
				continue
			var cleaned: String = strip_team_prefix(lbl.text)
			if lbl.text != cleaned:
				lbl.text = cleaned
			var orig_a: float = float(_orig_nametag_alpha.get(seat, 1.0))
			var white_col := Color(1.0, 1.0, 1.0, orig_a)
			if not lbl.modulate.is_equal_approx(white_col):
				lbl.modulate = white_col
			if _lobby_seat_rings.has(seat) and is_instance_valid(_lobby_seat_rings[seat]):
				(_lobby_seat_rings[seat] as Node3D).visible = false
			if _lobby_seat_halos.has(seat) and is_instance_valid(_lobby_seat_halos[seat]):
				(_lobby_seat_halos[seat] as Node3D).visible = false


func _project_seat_to_screen(world_pt: Vector3, cam: Camera3D, sub_vp: Viewport, tex_rect: TextureRect) -> Vector2:
	if cam == null or cam.is_position_behind(world_pt):
		return Vector2(-99999.0, -99999.0)
	var vp_pt: Vector2 = cam.unproject_position(world_pt)
	if tex_rect != null and is_instance_valid(tex_rect) and sub_vp != get_viewport():
		var vp_size: Vector2 = Vector2(sub_vp.get_visible_rect().size)
		if vp_size.x <= 0.0 or vp_size.y <= 0.0:
			return Vector2(-99999.0, -99999.0)
		var uv: Vector2 = vp_pt / vp_size
		return tex_rect.get_global_transform_with_canvas() * (uv * tex_rect.size)
	return vp_pt


func _screen_to_lobby_drag_pos(mouse_pos: Vector2) -> Variant:
	if not is_instance_valid(lobby):
		return null
	var handler = lobby.get("lobby_handler")
	if handler == null or not (handler.get("players") is Array) or (handler.get("players") as Array).is_empty():
		return null
	var first_slot: Node3D = (handler.get("players") as Array)[0] as Node3D
	if first_slot == null or not first_slot.is_inside_tree():
		return null
	var sub_vp: Viewport = first_slot.get_viewport()
	if sub_vp == null:
		return null
	var cam: Camera3D = sub_vp.get_camera_3d()
	if cam == null:
		return null
	var vp_pt: Vector2 = mouse_pos
	var tex_rect: TextureRect = lobby.get_node_or_null("Lobby/Control/TextureRect") as TextureRect
	if tex_rect != null and is_instance_valid(tex_rect) and sub_vp != get_viewport():
		if tex_rect.size.x <= 0.0 or tex_rect.size.y <= 0.0:
			return null
		var local_rect: Vector2 = tex_rect.get_global_transform_with_canvas().affine_inverse() * mouse_pos
		var uv: Vector2 = local_rect / tex_rect.size
		vp_pt = uv * Vector2(sub_vp.get_visible_rect().size)
	var ray_origin: Vector3 = cam.project_ray_origin(vp_pt)
	var ray_dir: Vector3 = cam.project_ray_normal(vp_pt)
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var min_cam_dist: float = 16.0
	var has_any_seat: bool = false
	for fp_v in _lobby_seat_rest_floor.values():
		var fp: Vector3 = fp_v as Vector3
		var d_cam: float = (fp - cam.global_position).dot(cam_fwd)
		if not has_any_seat or d_cam < min_cam_dist:
			min_cam_dist = d_cam
			has_any_seat = true
	var fg_dist: float = maxf(4.5, min_cam_dist - 2.0)
	var fg_anchor: Vector3 = cam.global_position + cam_fwd * fg_dist
	var hit = Plane(-cam_fwd, fg_anchor).intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return null
	var world_hit: Vector3 = hit as Vector3
	world_hit.x = clampf(world_hit.x, -7.5, 7.5)
	world_hit.y = clampf(world_hit.y, 0.65, 6.2)
	world_hit.z = clampf(world_hit.z, -2.0, 18.0)
	return world_hit


func _is_interactive_ui_at_pointer() -> bool:
	if get_viewport() == null:
		return false
	var hov: Control = get_viewport().gui_get_hovered_control()
	while hov != null:
		if hov is BaseButton or hov is Slider or hov is LineEdit or hov is TextEdit:
			return true
		if hov is PanelContainer:
			var sb = hov.get_theme_stylebox("panel")
			if not (sb is StyleBoxEmpty):
				return true
		hov = hov.get_parent_control()
	return false


func _pick_lobby_chair_at(mouse_pos: Vector2) -> int:
	if not is_team_mode_active() or locked or not is_instance_valid(lobby):
		return -1
	var handler = lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")) or bool(lobby.get("loading")):
		return -1
	if _is_interactive_ui_at_pointer():
		return -1
	var players_arr = handler.get("players")
	var nametags = handler.get("nametags")
	if not (players_arr is Array) or (players_arr as Array).is_empty():
		return -1

	var first_slot: Node3D = (players_arr as Array)[0] as Node3D
	if first_slot == null or not first_slot.is_inside_tree():
		return -1
	var sub_vp: Viewport = first_slot.get_viewport()
	if sub_vp == null:
		return -1
	var cam: Camera3D = sub_vp.get_camera_3d()
	if cam == null:
		return -1
	var tex_rect: TextureRect = lobby.get_node_or_null("Lobby/Control/TextureRect") as TextureRect
	var hit_radius: float = maxf(44.0, tex_rect.size.x * 0.056) if (tex_rect != null and is_instance_valid(tex_rect)) else 66.0

	var resolved := _resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var best_seat: int = -1
	var best_dist: float = hit_radius
	var total: int = mini(seats.size(), (players_arr as Array).size())
	for seat in range(total):
		if _drag_active and seat == _drag_seat:
			continue
		var slot_node: Node3D = (players_arr as Array)[seat] as Node3D
		if slot_node == null:
			continue
		var lbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags is Array and seat < (nametags as Array).size()) else null
		var floor_p: Vector3 = _seat_world_floor_pos(slot_node, lbl, seat)
		var torso_p: Vector3 = Vector3(floor_p.x, 1.35, floor_p.z)
		var head_p: Vector3 = Vector3(floor_p.x, 2.35, floor_p.z)
		var s_torso: Vector2 = _project_seat_to_screen(torso_p, cam, sub_vp, tex_rect)
		var s_head: Vector2 = _project_seat_to_screen(head_p, cam, sub_vp, tex_rect)
		var d: float = minf(mouse_pos.distance_to(s_torso), mouse_pos.distance_to(s_head))
		if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
			var s_lbl: Vector2 = _project_seat_to_screen(lbl.global_position, cam, sub_vp, tex_rect)
			d = minf(d, mouse_pos.distance_to(s_lbl))
		if d < best_dist:
			best_dist = d
			best_seat = seat
	return best_seat


func _input(event: InputEvent) -> void:
	if not is_team_mode_active() or locked or not is_instance_valid(lobby):
		if _drag_seat >= 0:
			_cancel_lobby_drag()
		return
	var handler = lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")) or bool(lobby.get("loading")):
		if _drag_seat >= 0:
			_cancel_lobby_drag()
		return
	if _drag_is_remote:
		return
	if event is InputEventKey and _drag_seat >= 0:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_cancel_lobby_drag()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mpos: Vector2 = lobby.get_viewport().get_mouse_position() if lobby.get_viewport() != null else (event as InputEventMouseMotion).position
		if _drag_seat >= 0:
			if not _drag_active and mpos.distance_to(_drag_start_pos) >= 6.0:
				_drag_active = true
				_drag_elapsed = 0.0
				_set_lobby_cursor(&"grab")
				var players_arr = handler.get("players")
				if players_arr is Array and _drag_seat < (players_arr as Array).size():
					var dnode = (players_arr as Array)[_drag_seat]
					if dnode is Node3D and is_instance_valid(dnode):
						_begin_drag_skeleton(dnode as Node3D)
				_drag_visual_pos = _drag_rest_collar
				_drag_vel = Vector3(0.0, 3.0, 0.0)
				var first_hit = _screen_to_lobby_drag_pos(mpos)
				if first_hit is Vector3:
					_drag_target_pos = first_hit as Vector3
				_broadcast_drag_begin()
			if _drag_active:
				var target_hit: int = _pick_lobby_chair_at(mpos)
				if target_hit != _hovered_seat:
					_hovered_seat = target_hit
					_update_lobby_nametags()
				var drag_hit = _screen_to_lobby_drag_pos(mpos)
				if drag_hit is Vector3:
					_drag_target_pos = drag_hit as Vector3
		else:
			var hit: int = _pick_lobby_chair_at(mpos)
			_set_lobby_cursor(&"hover" if hit >= 0 else &"point")
			if hit != _hovered_seat:
				_hovered_seat = hit
				_update_lobby_nametags()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag_seat >= 0:
			_cancel_lobby_drag()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var mpos: Vector2 = lobby.get_viewport().get_mouse_position() if lobby.get_viewport() != null else mb.position
			if mb.pressed:
				var hit: int = _pick_lobby_chair_at(mpos)
				if hit >= 0:
					if _is_host_authoritative():
						var resolved := _resolved_lobby_seats()
						var seats: Array = resolved["seats"]
						var occ_id: int = int(seats[hit]) if hit < seats.size() else 0
						if occ_id != 0:
							var players_arr = handler.get("players")
							var nametags = handler.get("nametags")
							var snode: Node3D = (players_arr as Array)[hit] as Node3D if (players_arr is Array and hit < (players_arr as Array).size()) else null
							var slbl: Label3D = (nametags as Array)[hit] as Label3D if (nametags is Array and hit < (nametags as Array).size()) else null
							if snode != null:
								_drag_seat = hit
								_drag_actor_id = occ_id
								_drag_start_pos = mpos
								_drag_active = false
								_drag_elapsed = 0.0
								_drag_orig_slot_pos = snode.position
								_drag_orig_floor = _seat_world_floor_pos(snode, slbl, hit)
								if not _seat_drop_bounce.has(hit):
									_lobby_seat_rest_slot_xform[hit] = snode.transform
								_drag_rest_collar = Vector3(_drag_orig_floor.x, 2.05, _drag_orig_floor.z)
								_drag_visual_pos = _drag_rest_collar
								_drag_target_pos = _drag_rest_collar
								_drag_vel = Vector3.ZERO
								if get_viewport() != null:
									get_viewport().set_input_as_handled()
								return
					click_lobby_chair(hit)
					if get_viewport() != null:
						get_viewport().set_input_as_handled()
			elif _drag_seat >= 0:
				var from_seat: int = _drag_seat
				var was_active: bool = _drag_active
				_drag_seat = -1
				_drag_actor_id = 0
				_drag_active = false
				_drag_vel = Vector3.ZERO
				_drag_elapsed = 0.0
				_restore_drag_skeleton()
				if _hop_seat >= 0:
					_restore_slot_transform(_hop_seat)
					_hop_seat = -1
				_restore_slot_transform(from_seat)
				if was_active:
					var drop_seat: int = _pick_lobby_chair_at(mpos)
					_hovered_seat = drop_seat
					_set_lobby_cursor(&"hover" if drop_seat >= 0 else &"point")
					if drop_seat >= 0 and drop_seat != from_seat:
						if host_drop_chair(from_seat, drop_seat):
							var bseats: Array = [drop_seat]
							if _seat_drop_bounce.has(from_seat):
								bseats.append(from_seat)
							_broadcast_drag_end(from_seat, bseats)
						else:
							_seat_drop_bounce[from_seat] = 0.18
							_broadcast_drag_end(from_seat, [from_seat])
					else:
						_seat_drop_bounce[from_seat] = 0.18
						_broadcast_drag_end(from_seat, [from_seat])
						_update_lobby_nametags()
				else:
					_set_lobby_cursor(&"hover")
					click_lobby_chair(from_seat)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()



# ============================================================================
# In-Game Scene & Actor Integration
# ============================================================================

func _node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_signal("player_game_ready") and node.has_method("load_minigame"):
		_attach_game(node)
		return
	if node.has_signal("minigame_finished") and node.has_signal("player_scores_finalized"):
		_attach_minigame(node)
		return
	if node is Node3D and node.get_script() != null:
		if not bool(node.get_meta(&"mpm_team_wrapped", false)):
			if node.has_method("_hit_player_by_blast") and node.has_method("_setup_match_local"):
				_wrap_custom_stage(node, &"bubble_blitz")
				return
			if node.has_method("_try_push") and node.has_method("_step_airdrops"):
				_wrap_custom_stage(node, &"spike_ring")
				return
			if node.has_method("_evaluate_roller_interactions") and node.has_method("_spawn_players"):
				_wrap_custom_stage(node, &"roller_carnival")
				return
	if node is Node3D and node.get_script() != null and &"player_presence" in node:
		if not _is_skipped_scene_node(node):
			_track_actor.call_deferred(node as Node3D)


func _attach_game(node: Node) -> void:
	game = node
	if not node.tree_exiting.is_connected(_on_game_exiting):
		node.tree_exiting.connect(_on_game_exiting, CONNECT_ONE_SHOT)
	_refresh_hud(true)


func _on_game_exiting() -> void:
	game = null
	current_minigame = null
	_minigame_synced = false
	_early_win_triggered = false
	_initial_teams_seen.clear()
	locked = false
	for rec in _tracked_actors.values():
		_cleanup_actor_record(rec)
	_tracked_actors.clear()
	_hide_hud()


func _attach_minigame(mg: Node) -> void:
	current_minigame = mg
	_minigame_synced = false
	_early_win_triggered = false
	_initial_teams_seen.clear()
	# Connect before MinigamePlayingState enters so our score sync runs strictly before game.update_scores().
	if not mg.minigame_finished.is_connected(_on_minigame_finished):
		mg.minigame_finished.connect(_on_minigame_finished.bind(mg), CONNECT_ONE_SHOT)
	if not mg.tree_exiting.is_connected(_on_minigame_exiting.bind(mg)):
		mg.tree_exiting.connect(_on_minigame_exiting.bind(mg), CONNECT_ONE_SHOT)
	_refresh_hud(true)


func _on_minigame_exiting(mg: Node) -> void:
	if current_minigame == mg:
		current_minigame = null
	for key in _tracked_actors.keys():
		var rec: Dictionary = _tracked_actors[key]
		var actor = rec.get("actor", null)
		if actor == null or not is_instance_valid(actor) or not (actor as Node).is_inside_tree():
			_cleanup_actor_record(rec)
			_tracked_actors.erase(key)
	_refresh_hud(true)


func _extract_alive_ids(mg: Node) -> Array[int]:
	var alive: Array[int] = []
	if mg == null or not is_instance_valid(mg):
		return alive
	if not (&"active_players" in mg):
		return alive
	var ap = mg.get("active_players")
	if ap is Dictionary:
		for raw_k in (ap as Dictionary).keys():
			alive.append(int(raw_k))
	elif ap is Array:
		for item in (ap as Array):
			if item is int:
				alive.append(int(item))
			elif item is Object and &"player_presence" in item:
				var nid: int = _presence_network_id(item.get(&"player_presence"))
				if nid != 0:
					alive.append(nid)
	return alive


func _on_minigame_finished(_id, mg: Node) -> void:
	if _minigame_synced or not is_team_mode_active():
		return
	if not _is_host_authoritative() or not is_instance_valid(game) or not is_instance_valid(mg):
		return
	if game.has_method("is_current_game_cutscene") and bool(game.call("is_current_game_cutscene")):
		return
	if bool(mg.get_meta(&"mpm_team_scores_applied", false)):
		_minigame_synced = true
		return
	var round_scores = game.get("round_score_by_network_id")
	if not (round_scores is Dictionary) or (round_scores as Dictionary).is_empty():
		return
	var alive_ids: Array[int] = _extract_alive_ids(mg)
	var synced: Dictionary = compute_team_synchronized_scores(round_scores as Dictionary, alive_ids)
	for k in synced.keys():
		(round_scores as Dictionary)[k] = int(synced[k])
	_minigame_synced = true
	mg.set_meta(&"mpm_team_scores_applied", true)
	record_team_win(synced, mg)


func _check_vanilla_early_team_victory() -> void:
	if _early_win_triggered or not is_team_mode_active():
		return
	if not _is_host_authoritative() or not is_instance_valid(current_minigame):
		return
	var mg: Node = current_minigame
	if bool(mg.get_meta(&"mpm_custom_team_game", false)):
		return
	if &"infected_players" in mg:
		return
	if not (&"active_players" in mg and &"dead_players" in mg and &"player_scores" in mg):
		return
	if not (&"finished" in mg or &"game_end" in mg):
		return
	if (&"finished" in mg and bool(mg.get(&"finished"))) or (&"game_end" in mg and bool(mg.get(&"game_end"))):
		return
	var ap = mg.get("active_players")
	if not (ap is Dictionary):
		return
	var active_dict: Dictionary = ap as Dictionary
	if active_dict.size() < 2:
		return

	var active_teams: Dictionary = {}
	for raw_nid in active_dict.keys():
		var tid: int = get_team(int(raw_nid))
		if tid > 0:
			active_teams[tid] = true
			_initial_teams_seen[tid] = true

	if _initial_teams_seen.size() >= 2 and active_teams.size() == 1:
		_early_win_triggered = true
		_trigger_vanilla_team_win(mg)


func _trigger_vanilla_team_win(mg: Node) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(mg) or not mg.is_inside_tree() or not is_team_mode_active():
		return
	if (&"finished" in mg and bool(mg.get(&"finished"))) or (&"game_end" in mg and bool(mg.get(&"game_end"))):
		return
	var ap = mg.get("active_players")
	if not (ap is Dictionary):
		return
	var active_dict: Dictionary = ap as Dictionary
	var active_teams: Dictionary = {}
	for raw_nid in active_dict.keys():
		var tid: int = get_team(int(raw_nid))
		if tid > 0:
			active_teams[tid] = true
	if active_teams.size() > 1:
		_early_win_triggered = false
		return

	var dead_arr = mg.get("dead_players")
	var scores_dict = mg.get("player_scores")
	if not (dead_arr is Array) or not (scores_dict is Dictionary):
		return
	var dead_list: Array = dead_arr as Array
	var pscores: Dictionary = scores_dict as Dictionary

	if &"finished" in mg:
		mg.set("finished", true)
	if &"game_end" in mg:
		mg.set("game_end", true)

	for i in range(dead_list.size()):
		pscores[dead_list[i]] = i
	var top_score: int = int(mg.get("player_count")) if &"player_count" in mg else (dead_list.size() + active_dict.size())
	top_score = maxi(1, top_score)
	for raw_nid in active_dict.keys():
		pscores[raw_nid] = top_score

	if mg.has_method("calculate_score") and mg.has_method("finish_game"):
		mg.player_scores_finalized.emit(pscores)
		mg.call("finish_game")
		return

	mg.player_scores_finalized.emit(pscores)
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(mg) or not mg.is_inside_tree():
		return
	if mg.has_method("set_minigame_sfx_linear_volume_rpc"):
		mg.rpc("set_minigame_sfx_linear_volume_rpc", 0.0)
	var sm = mg.get("state_machine")
	if sm is Node and sm.has_method("transition_to_rpc"):
		if (sm as Node).has_node("Finish"):
			(sm as Node).rpc("transition_to_rpc", &"Finish")
		elif (sm as Node).has_node("Finished"):
			(sm as Node).rpc("transition_to_rpc", &"Finished")
	if mg.has_method("set_effects_visibility_rpc"):
		mg.rpc("set_effects_visibility_rpc", false)


# ============================================================================
# Actor Tracking, Visual Badges & Friendly-Fire Shove Filtering
# ============================================================================

func _is_skipped_scene_node(node: Node) -> bool:
	var path_lower: String = str(node.get_path()).to_lower()
	for tok in SKIP_SCENE_TOKENS:
		if path_lower.contains(tok):
			return true
	return false


func _presence_network_id(presence) -> int:
	if presence == null:
		return 0
	if presence is Dictionary:
		return int((presence as Dictionary).get("network_id", 0))
	if presence is Object and &"network_id" in presence:
		return int(presence.get(&"network_id"))
	return 0


func _is_first_person_rig(node: Node3D, depth: int = 4) -> bool:
	if depth <= 0:
		return false
	for child in node.get_children():
		if child is Camera3D and (child as Camera3D).current:
			return true
		if child is Node3D and _is_first_person_rig(child as Node3D, depth - 1):
			return true
	return false


func _find_actor_label(actor: Node3D) -> Label3D:
	if &"player_name_label" in actor:
		var raw = actor.get(&"player_name_label")
		if raw is Label3D and is_instance_valid(raw):
			return raw as Label3D
	for child in actor.get_children():
		if child is Label3D:
			return child as Label3D
		for grand in child.get_children():
			if grand is Label3D:
				return grand as Label3D
	return null


func _track_actor(actor: Node3D) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var nid: int = _presence_network_id(actor.get(&"player_presence"))
	if nid == 0:
		return
	var key: int = actor.get_instance_id()
	if _tracked_actors.has(key):
		return
	if _is_first_person_rig(actor):
		return

	var lbl: Label3D = _find_actor_label(actor)
	var badge: Label3D = null
	if is_team_mode_active() and get_team(nid) > 0:
		badge = _create_team_badge(actor, nid)
	var ring: MeshInstance3D = _ensure_actor_team_ring(actor, get_team(nid))

	var rec := {
		"actor": actor,
		"nid": nid,
		"label": lbl,
		"orig_modulate": lbl.modulate if lbl != null else Color.WHITE,
		"badge": badge,
		"ring": ring,
		"has_shove": &"players_in_shove_proximity" in actor,
		"has_active": &"active" in actor,
		"age": 0.0,
	}
	_tracked_actors[key] = rec
	actor.tree_exiting.connect(func():
		if _tracked_actors.has(key):
			_cleanup_actor_record(_tracked_actors[key])
			_tracked_actors.erase(key)
	, CONNECT_ONE_SHOT)
	_sync_actor_visual(rec)


func _create_team_badge(actor: Node3D, nid: int) -> Label3D:
	var tid: int = get_team(nid)
	if tid <= 0:
		return null
	var badge := Label3D.new()
	badge.name = "MpmTeamBadge"
	badge.font = _get_cjk_badge_font()
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.font_size = 28
	badge.pixel_size = 0.0072
	badge.outline_size = 10
	badge.outline_modulate = Color.BLACK
	badge.position = Vector3(0.0, 2.35, 0.0)
	badge.text = "▼ %s" % get_team_tag(tid)
	badge.modulate = get_team_color(tid)
	actor.add_child(badge)
	return badge


func _sync_actor_visual(rec: Dictionary) -> void:
	var actor: Node3D = rec["actor"] as Node3D
	if actor == null or not is_instance_valid(actor):
		return
	var nid: int = int(rec["nid"])
	var current_nid: int = _presence_network_id(actor.get(&"player_presence"))
	if current_nid != 0 and current_nid != nid:
		nid = current_nid
		rec["nid"] = nid

	var tid: int = get_team(nid)
	var alive: bool = actor.visible and (not bool(rec["has_active"]) or bool(actor.get(&"active")))
	var lbl = rec.get("label", null)
	if (lbl == null or not is_instance_valid(lbl)):
		lbl = _find_actor_label(actor)
		if lbl != null:
			rec["label"] = lbl
			rec["orig_modulate"] = (lbl as Label3D).modulate

	var spotlight_active: bool = _is_player_spotlight_enabled()
	var is_local_actor: bool = nid == _local_peer_id()
	var tcol: Color = get_team_color(tid) if tid > 0 else Color.WHITE

	var label_shows_text: bool = false
	if is_instance_valid(lbl) and lbl is Label3D:
		var l3: Label3D = lbl as Label3D
		var badge_font: Font = _get_cjk_badge_font()
		if badge_font != null and l3.font != badge_font:
			l3.font = badge_font
		if tid > 0 and alive:
			if not l3.text.is_empty():
				label_shows_text = l3.visible
				var formatted: String = format_team_nickname(nid, l3.text)
				if l3.text != formatted:
					l3.text = formatted
			if not (is_local_actor and spotlight_active):
				var desired := Color(tcol.r, tcol.g, tcol.b, l3.modulate.a)
				if not l3.modulate.is_equal_approx(desired):
					l3.modulate = desired
		else:
			var cleaned: String = strip_team_prefix(l3.text)
			if l3.text != cleaned:
				l3.text = cleaned
			if not (is_local_actor and spotlight_active):
				var orig: Color = rec["orig_modulate"] as Color
				var restore := Color(orig.r, orig.g, orig.b, l3.modulate.a)
				if not l3.modulate.is_equal_approx(restore):
					l3.modulate = restore

	var badge = rec.get("badge", null)
	if tid > 0 and alive:
		if badge == null or not is_instance_valid(badge):
			badge = _create_team_badge(actor, nid)
			rec["badge"] = badge
		if is_instance_valid(badge) and badge is Label3D:
			var b3: Label3D = badge as Label3D
			var show_badge: bool = (not label_shows_text) or (float(rec.get("age", 99.0)) < 3.5)
			b3.visible = show_badge
			b3.text = "▼ %s" % get_team_tag(tid)
			b3.modulate = tcol
	elif is_instance_valid(badge) and badge is Label3D:
		(badge as Label3D).visible = false

	var ring = rec.get("ring", null)
	if tid > 0 and alive:
		if ring == null or not is_instance_valid(ring):
			ring = _ensure_actor_team_ring(actor, tid)
			rec["ring"] = ring
		if is_instance_valid(ring) and ring is MeshInstance3D:
			var rmesh := ring as MeshInstance3D
			rmesh.visible = true
			var rmat := rmesh.material_override as StandardMaterial3D
			if rmat != null:
				rmat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.72)
	elif is_instance_valid(ring) and ring is MeshInstance3D:
		(ring as MeshInstance3D).visible = false


func _ensure_actor_team_ring(actor: Node3D, tid: int) -> MeshInstance3D:
	if actor == null or not is_instance_valid(actor) or tid <= 0 or not is_team_mode_active():
		return null
	var existing := actor.get_node_or_null("MpmTeamRing")
	if existing is MeshInstance3D:
		return existing as MeshInstance3D
	var ring := MeshInstance3D.new()
	ring.name = "MpmTeamRing"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.58
	torus.rings = 20
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.14, 1.0)
	ring.position = Vector3(0.0, 0.04, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tcol: Color = get_team_color(tid)
	mat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.72)
	ring.material_override = mat
	actor.add_child(ring)
	return ring


func _cleanup_actor_record(rec: Dictionary) -> void:
	var badge = rec.get("badge", null)
	if is_instance_valid(badge) and badge is Node:
		(badge as Node).queue_free()
	var ring = rec.get("ring", null)
	if is_instance_valid(ring) and ring is Node:
		(ring as Node).queue_free()
	var lbl = rec.get("label", null)
	if is_instance_valid(lbl) and lbl is Label3D:
		var l3: Label3D = lbl as Label3D
		l3.text = strip_team_prefix(l3.text)
		l3.modulate = rec.get("orig_modulate", Color.WHITE) as Color


func _physics_process(_delta: float) -> void:
	if not is_team_mode_active() or _tracked_actors.is_empty():
		return
	for key in _tracked_actors.keys():
		var rec: Dictionary = _tracked_actors[key]
		var actor = rec.get("actor", null)
		if actor == null or not is_instance_valid(actor):
			continue
		if (actor as Node).has_meta(&"lobby_bots_disco_brain"):
			var brain = (actor as Node).get_meta(&"lobby_bots_disco_brain")
			if brain != null and not (brain is _DiscoBrainTeamWrapper):
				(actor as Node).set_meta(&"lobby_bots_disco_brain", _DiscoBrainTeamWrapper.new(brain, self))
		if not bool(rec["has_shove"]):
			continue
		var prox = actor.get(&"players_in_shove_proximity")
		if not (prox is Array) or (prox as Array).is_empty():
			continue
		var my_id: int = int(rec["nid"])
		var arr: Array = prox as Array
		for i in range(arr.size() - 1, -1, -1):
			var other = arr[i]
			if other is Object and &"player_presence" in other:
				var other_id: int = _presence_network_id((other as Object).get(&"player_presence"))
				if other_id != 0 and are_teammates(my_id, other_id):
					arr.remove_at(i)


func _process(delta: float) -> void:
	_anim_time += delta
	if is_instance_valid(lobby) and is_instance_valid(panel):
		var handler = lobby.get("lobby_handler")
		var show_panel: bool = handler != null and bool(handler.get("active")) and not bool(lobby.get("loading"))
		panel.visible = show_panel and (_is_host_authoritative() or is_team_mode_active())
		if show_panel:
			_hide_hud()
			var want_cam_elevated: bool = is_team_mode_active() and _lobby_total_seats() > 4
			if want_cam_elevated != _lobby_cam_adjusted:
				_sync_lobby_camera_angle()
			var participants: Array[Dictionary] = _collect_lobby_participants()
			var sig_parts: PackedStringArray = PackedStringArray()
			for p in participants:
				sig_parts.append("%d:%s:%d" % [int(p["id"]), str(p["name"]), get_team(int(p["id"]))])
			var sig: String = "%d|%s|%s" % [team_count, str(locked), "|".join(sig_parts)]
			if _reconcile_lobby_teams(participants):
				_publish_state()
				_broadcast_teams()
				sig = ""
			if sig != _last_roster_sig:
				_last_roster_sig = sig
				_refresh_lobby_ui()
			if _is_host_authoritative() and not _pending_swap_requests.is_empty():
				var expired_req: Array = []
				for tk in _pending_swap_requests.keys():
					var req = _pending_swap_requests[tk]
					if req is Dictionary and _anim_time >= float((req as Dictionary).get("expires_at", 0.0)):
						expired_req.append(tk)
				for ek in expired_req:
					_pending_swap_requests.erase(ek)
			if _incoming_swap_from > 0 and _anim_time >= _incoming_swap_expires:
				_incoming_swap_from = 0
				_incoming_swap_name = ""
				_incoming_swap_expires = 0.0
				_refresh_lobby_ui()
			if _drag_active and _drag_seat >= 0:
				_drag_elapsed += delta
				var players_arr = handler.get("players")
				if players_arr is Array and _drag_seat < (players_arr as Array).size():
					var dnode = (players_arr as Array)[_drag_seat]
					if dnode is Node3D and is_instance_valid(dnode):
						var dt: float = clampf(delta, 0.001, 0.05)
						var prev_pos: Vector3 = _drag_visual_pos
						var follow_alpha: float = 1.0 - exp(-32.0 * dt)
						_drag_visual_pos = _drag_visual_pos.lerp(_drag_target_pos, follow_alpha)
						var inst_vel: Vector3 = (_drag_visual_pos - prev_pos) / dt
						_drag_vel = _drag_vel.lerp(inst_vel, 1.0 - exp(-16.0 * dt))
						var rest_collar: Vector3 = _drag_rest_collar if _drag_rest_collar != Vector3.ZERO else Vector3(_drag_orig_floor.x, 2.05, _drag_orig_floor.z)
						var offset_vec: Vector3 = _drag_visual_pos - rest_collar
						var tilt_z: float = clampf(-_drag_vel.x * 0.048 + sin(_anim_time * 6.5) * 0.035, -0.46, 0.46)
						var yaw_y: float = clampf(_drag_vel.x * 0.038, -0.42, 0.42)
						var tilt_x: float = clampf(_drag_vel.y * 0.020 + cos(_anim_time * 5.0) * 0.02, -0.22, 0.22)
						var sy: float = clampf(1.03 + absf(_drag_vel.y) * 0.008, 0.97, 1.10)
						var sxz: float = 1.0 / sqrt(sy)
						_set_slot_pivot_pose(dnode as Node3D, _drag_seat, offset_vec, Vector3(tilt_x, yaw_y, tilt_z), Vector3(sxz, sy, sxz), 2.05)
						_apply_drag_dangling_pose()
						_broadcast_drag_pose_if_due(delta)
			_update_lobby_nametags()
			_animate_lobby_seats(delta)

	if is_team_mode_active():
		_check_vanilla_early_team_victory()

	if not _tracked_actors.is_empty():
		var stale: Array = []
		for key in _tracked_actors.keys():
			var rec: Dictionary = _tracked_actors[key]
			var actor = rec.get("actor", null)
			if actor == null or not is_instance_valid(actor) or not (actor as Node).is_inside_tree():
				stale.append(key)
			else:
				rec["age"] = float(rec.get("age", 0.0)) + delta
				_sync_actor_visual(rec)
		for key in stale:
			_cleanup_actor_record(_tracked_actors[key])
			_tracked_actors.erase(key)

	_hud_refresh_accum += delta
	if _hud_refresh_accum >= 0.16:
		_hud_refresh_accum = 0.0
		_refresh_hud(false)


# ============================================================================
# In-Game Top-Right Frameless Team Status HUD
# ============================================================================

func _ensure_hud() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_hud_layer) and is_instance_valid(_hud_panel):
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "TeamPartyHudLayer"
	_hud_layer.layer = 20
	add_child(_hud_layer)

	_hud_panel = PanelContainer.new()
	_hud_panel.name = "TeamPartyHudPanel"
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud_panel.anchor_left = 1.0
	_hud_panel.anchor_right = 1.0
	_hud_panel.anchor_top = 0.0
	_hud_panel.anchor_bottom = 0.0
	_hud_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud_panel.offset_right = -20.0
	_hud_panel.offset_left = -20.0
	_hud_panel.offset_top = 14.0
	_hud_layer.add_child(_hud_panel)

	_hud_rows = HBoxContainer.new()
	_hud_rows.name = "TeamHudRows"
	_hud_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_rows.add_theme_constant_override("separation", 18)
	_hud_panel.add_child(_hud_rows)


func _hide_hud() -> void:
	if is_instance_valid(_hud_panel):
		_hud_panel.visible = false
	if is_instance_valid(_hud_layer):
		_hud_layer.visible = false


func record_team_win(scores: Dictionary, stage_node: Node = null) -> void:
	if not is_team_mode_active() or scores.is_empty():
		return
	if stage_node != null and is_instance_valid(stage_node):
		if bool(stage_node.get_meta(&"mpm_hud_win_recorded", false)):
			return
		stage_node.set_meta(&"mpm_hud_win_recorded", true)
	var team_best: Dictionary = {}
	var best_score: int = -999999
	for raw_nid in scores.keys():
		var tid: int = get_team(int(raw_nid))
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
			_hud_wins[tid] = int(_hud_wins.get(tid, 0)) + 1
	_broadcast_teams()
	_refresh_hud(true)


func _gather_hud_teams() -> Dictionary:
	var stats: Dictionary = {} # tid -> {total, alive, trapped}
	var seen_nids: Dictionary = {}

	if is_instance_valid(_current_stage_node) and _current_stage_node.is_inside_tree() and (&"_players" in _current_stage_node):
		var raw_ps = _current_stage_node.get("_players")
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
			var tid: int = get_team(nid)
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

	if stats.is_empty() and is_instance_valid(current_minigame) and current_minigame.is_inside_tree():
		var ap = current_minigame.get("active_players") if (&"active_players" in current_minigame) else null
		if ap is Dictionary:
			for raw_k in (ap as Dictionary).keys():
				seen_nids[int(raw_k)] = true
				var tid: int = get_team(int(raw_k))
				if tid > 0:
					if not stats.has(tid):
						stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
					var st: Dictionary = stats[tid]
					st["total"] = int(st["total"]) + 1
					st["alive"] = int(st["alive"]) + 1
		var dp = current_minigame.get("dead_players") if (&"dead_players" in current_minigame) else null
		if dp is Array:
			for raw_k in (dp as Array):
				var nid: int = int(raw_k)
				if seen_nids.has(nid):
					continue
				seen_nids[nid] = true
				var tid: int = get_team(nid)
				if tid > 0:
					if not stats.has(tid):
						stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
					var st: Dictionary = stats[tid]
					st["total"] = int(st["total"]) + 1

	if not _tracked_actors.is_empty():
		for rec in _tracked_actors.values():
			var actor = rec.get("actor", null)
			if actor == null or not is_instance_valid(actor):
				continue
			var nid: int = int(rec.get("nid", 0))
			if seen_nids.has(nid):
				continue
			var tid: int = get_team(nid)
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
		for raw_nid in teams.keys():
			var tid: int = get_team(int(raw_nid))
			if tid > 0:
				if not stats.has(tid):
					stats[tid] = {"total": 0, "alive": 0, "trapped": 0}
				var st: Dictionary = stats[tid]
				st["total"] = int(st["total"]) + 1
				st["alive"] = int(st["alive"]) + 1
	return stats


func _hud_team_short_label(tid: int) -> String:
	var is_tw: bool = _is_tw_locale()
	var is_cn: bool = _is_cn_locale()
	match tid:
		1: return "紅" if is_tw else ("红" if is_cn else "RED")
		2: return "藍" if is_tw else ("蓝" if is_cn else "BLU")
		3: return "綠" if is_tw else ("绿" if is_cn else "GRN")
		4: return "黃" if is_tw else ("黄" if is_cn else "YEL")
		_: return "?"


func _refresh_hud(force: bool = false) -> void:
	var in_lobby: bool = is_instance_valid(lobby) and lobby.is_inside_tree()
	var is_cutscene: bool = (
		is_instance_valid(game)
		and game.has_method("is_current_game_cutscene")
		and bool(game.call("is_current_game_cutscene"))
	)
	var in_match: bool = (
		(is_instance_valid(current_minigame) and current_minigame.is_inside_tree() and not _is_skipped_scene_node(current_minigame))
		or (is_instance_valid(_current_stage_node) and _current_stage_node.is_inside_tree())
	)
	if not is_team_mode_active() or in_lobby or is_cutscene or not in_match:
		_hide_hud()
		return
	_ensure_hud()
	if not is_instance_valid(_hud_panel) or not is_instance_valid(_hud_rows):
		return
	_hud_layer.visible = true
	_hud_panel.visible = true

	var stats: Dictionary = _gather_hud_teams()
	var keys: Array = stats.keys()
	keys.sort()
	var my_tid: int = get_team(_local_peer_id())
	var sig_parts: PackedStringArray = PackedStringArray()
	for tid_v in keys:
		var tid: int = int(tid_v)
		var st: Dictionary = stats[tid]
		sig_parts.append("%d:%d:%d:%d:%d" % [
			tid, int(st["alive"]), int(st["trapped"]), int(st["total"]), int(_hud_wins.get(tid, 0))
		])
	var sig: String = "%s|%d|%s" % [TranslationServer.get_locale(), my_tid, ",".join(sig_parts)]
	if not force and sig == _last_hud_sig:
		return
	_last_hud_sig = sig

	for child in _hud_rows.get_children():
		_hud_rows.remove_child(child)
		child.queue_free()

	for tid_v in keys:
		var tid: int = int(tid_v)
		var st: Dictionary = stats[tid]
		var tcol: Color = get_team_color(tid)
		var total: int = int(st["total"])
		var alive_n: int = int(st["alive"])
		var trapped_n: int = int(st["trapped"])
		var dead_n: int = maxi(0, total - alive_n - trapped_n)
		var team_alive: bool = (alive_n + trapped_n) > 0

		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 6)
		_hud_rows.add_child(item)

		if tid == my_tid:
			var me_lbl := Label.new()
			me_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			me_lbl.text = "▶"
			_style_outline_label(me_lbl, Color.WHITE, 20, 5)
			item.add_child(me_lbl)

		var name_lbl := Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.text = _hud_team_short_label(tid)
		_style_outline_label(name_lbl, tcol if team_alive else Color(tcol.r, tcol.g, tcol.b, 0.45), 20, 5)
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
		_style_outline_label(pips_lbl, tcol if team_alive else Color(0.54, 0.58, 0.62, 0.68), 20, 5)
		item.add_child(pips_lbl)

		var wins: int = int(_hud_wins.get(tid, 0))
		if wins > 0:
			var win_lbl := Label.new()
			win_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			win_lbl.text = "★%d" % wins
			_style_outline_label(win_lbl, Color(1.0, 0.86, 0.28), 20, 5)
			item.add_child(win_lbl)


func _on_stage_exiting(node: Node) -> void:
	if _current_stage_node == node:
		_current_stage_node = null
	_last_hud_sig = ""
	_refresh_hud(true)


# ============================================================================
# External Non-Invasive Custom Minigame Wrappers (No Edits to Other Mods)
# ============================================================================

func _wrap_custom_stage(node: Node, kind: StringName) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base_script = node.get_script()
	if not (base_script is GDScript):
		return
	var wrapped: GDScript = _wrapped_script_cache.get(base_script, null) as GDScript
	if wrapped == null:
		var src: String = (base_script as GDScript).source_code.replace("\r\n", "\n")
		if src.is_empty():
			return
		var base_dir: String = (base_script as GDScript).resource_path.get_base_dir()
		var gen: String = ""
		match kind:
			&"bubble_blitz":
				gen = _build_bubble_blitz_wrapper_source(src)
			&"spike_ring":
				gen = _build_spike_ring_wrapper_source(src)
			&"roller_carnival":
				gen = _build_roller_carnival_wrapper_source(src, base_dir)
		if gen.is_empty():
			return
		wrapped = GDScript.new()
		wrapped.source_code = gen
		if wrapped.reload() != OK:
			return
		_wrapped_script_cache[base_script] = wrapped

	var props: Dictionary = {}
	for prop in (base_script as GDScript).get_script_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not String(prop.name).begins_with("_mpm_"):
			props[prop.name] = node.get(prop.name)
	node.set_script(wrapped)
	for k in props.keys():
		node.set(k, props[k])
	node.set_meta(&"mpm_team_wrapped", true)
	_current_stage_node = node
	if not node.tree_exiting.is_connected(_on_stage_exiting.bind(node)):
		node.tree_exiting.connect(_on_stage_exiting.bind(node), CONNECT_ONE_SHOT)
	_last_hud_sig = ""
	_refresh_hud(true)


func _stage_common_helpers_source() -> String:
	return """
const _MPM_TEAM_COLORS := {
	1: Color(1.0, 0.30, 0.28, 1.0),
	2: Color(0.26, 0.68, 1.0, 1.0),
	3: Color(0.28, 0.92, 0.48, 1.0),
	4: Color(1.0, 0.84, 0.24, 1.0),
}
var _mpm_team_active: bool = false
var _mpm_roster_teams: Dictionary = {}


func _mpm_tp_node():
	if not Engine.has_meta(&"mpm_team_party"):
		return null
	var meta = Engine.get_meta(&"mpm_team_party")
	if typeof(meta) != TYPE_DICTIONARY or not bool((meta as Dictionary).get("enabled", false)):
		return null
	var tp_node = (meta as Dictionary).get("node", null)
	if tp_node != null and is_instance_valid(tp_node) and tp_node.has_method("get_team"):
		return tp_node
	return null


func _mpm_resolve_roster_teams(roster: Array) -> void:
	_mpm_roster_teams.clear()
	var tp = _mpm_tp_node()
	var distinct: Dictionary = {}
	for raw in roster:
		var entry: Dictionary = raw
		var nid: int = int(entry.get("network_id", 0))
		var tid: int = int(entry.get("team_id", 0))
		if tid <= 0 and tp != null:
			tid = int(tp.call("get_team", nid))
		_mpm_roster_teams[nid] = tid
		if tid > 0:
			distinct[tid] = true
	_mpm_team_active = distinct.size() >= 2


func _mpm_player_team(net_id: int) -> int:
	if not _mpm_team_active:
		return 0
	return int(_mpm_roster_teams.get(net_id, 0))


func _mpm_are_teammates(id_a: int, id_b: int) -> bool:
	if not _mpm_team_active or id_a == id_b:
		return false
	var ta: int = _mpm_player_team(id_a)
	return ta > 0 and ta == _mpm_player_team(id_b)


func _mpm_team_color(tid: int) -> Color:
	return _MPM_TEAM_COLORS.get(tid, Color.WHITE) as Color


func _mpm_sync_roster_suits(roster: Array) -> Array:
	var out: Array = []
	for raw in roster:
		if not (raw is Dictionary):
			out.append(raw)
			continue
		var entry: Dictionary = (raw as Dictionary).duplicate(false)
		var nid: int = int(entry.get("network_id", 0))
		var tid: int = _mpm_player_team(nid)
		if tid > 0:
			entry["team_id"] = tid
		out.append(entry)
	return out


func _mpm_attach_foot_ring(pnode: Node3D, tid: int, inner_r: float = 0.48, outer_r: float = 0.58) -> void:
	if pnode == null or not is_instance_valid(pnode) or tid <= 0:
		return
	var ring := pnode.get_node_or_null("MpmTeamRing") as MeshInstance3D
	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = "MpmTeamRing"
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var torus := TorusMesh.new()
		torus.inner_radius = inner_r
		torus.outer_radius = outer_r
		torus.rings = 20
		torus.ring_segments = 4
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.14, 1.0)
		ring.position = Vector3(0.0, 0.04, 0.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = mat
		pnode.add_child(ring)
	var tcol: Color = _mpm_team_color(tid)
	var rmat := ring.material_override as StandardMaterial3D
	if rmat != null:
		rmat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.72)
	ring.visible = true


func _mpm_notify_round_win(scores: Dictionary, stage_node: Node) -> void:
	var tp = _mpm_tp_node()
	if tp != null and tp.has_method("record_team_win"):
		tp.call("record_team_win", scores, stage_node)


func _mpm_tp_font() -> Font:
	var tp = _mpm_tp_node()
	if tp != null and tp.has_method("_get_cjk_badge_font"):
		return tp.call("_get_cjk_badge_font") as Font
	return null


func _mpm_is_tw_locale() -> bool:
	var low: String = TranslationServer.get_locale().to_lower()
	return low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo")


func _mpm_is_cn_locale() -> bool:
	var low: String = TranslationServer.get_locale().to_lower()
	return not _mpm_is_tw_locale() and (low.begins_with("zh") or low == "zhs")


func _mpm_team_tag(tid: int) -> String:
	var tp = _mpm_tp_node()
	if tp != null and tp.has_method("get_team_tag"):
		return str(tp.call("get_team_tag", tid))
	var is_tw: bool = _mpm_is_tw_locale()
	var is_cn: bool = _mpm_is_cn_locale()
	match tid:
		1: return "[紅]" if is_tw else ("[红]" if is_cn else "[RED]")
		2: return "[藍]" if is_tw else ("[蓝]" if is_cn else "[BLU]")
		3: return "[綠]" if is_tw else ("[绿]" if is_cn else "[GRN]")
		4: return "[黃]" if is_tw else ("[黄]" if is_cn else "[YEL]")
		_: return ""


func _mpm_team_win_banner(tid: int) -> String:
	var is_tw: bool = _mpm_is_tw_locale()
	var is_cn: bool = _mpm_is_cn_locale()
	match tid:
		1: return "紅隊獲勝!" if is_tw else ("红队获胜!" if is_cn else "RED TEAM WINS!")
		2: return "藍隊獲勝!" if is_tw else ("蓝队获胜!" if is_cn else "BLUE TEAM WINS!")
		3: return "綠隊獲勝!" if is_tw else ("绿队获胜!" if is_cn else "GREEN TEAM WINS!")
		4: return "黃隊獲勝!" if is_tw else ("黄队获胜!" if is_cn else "YELLOW TEAM WINS!")
		_: return "ROUND COMPLETE!"


func _mpm_sync_scores(raw_scores: Dictionary, alive_ids: Array) -> Dictionary:
	var tp = _mpm_tp_node()
	if tp != null and tp.has_method("compute_team_synchronized_scores"):
		return tp.call("compute_team_synchronized_scores", raw_scores, alive_ids) as Dictionary
	var alive_map: Dictionary = {}
	for raw_id in alive_ids:
		alive_map[int(raw_id)] = true
	var members_by_team: Dictionary = {}
	for raw_nid in raw_scores.keys():
		var nid: int = int(raw_nid)
		var tid: int = _mpm_player_team(nid)
		if tid <= 0:
			continue
		if not members_by_team.has(tid):
			members_by_team[tid] = []
		(members_by_team[tid] as Array).append(nid)
	var out: Dictionary = raw_scores.duplicate()
	for raw_tid in members_by_team.keys():
		var members: Array = members_by_team[raw_tid]
		var best_score: int = 0
		var all_alive: bool = not alive_map.is_empty() and not members.is_empty()
		for nid_v in members:
			var nid: int = int(nid_v)
			best_score = maxi(best_score, int(raw_scores.get(nid, 0)))
			if not alive_map.has(nid):
				all_alive = false
		var team_score: int = best_score + (1 if all_alive else 0)
		for nid_v in members:
			out[int(nid_v)] = team_score
	return out
"""


func _build_bubble_blitz_wrapper_source(base_src: String) -> String:
	var hooks := [
		["\nfunc _setup_match_local(theme_id: int, seed_val: int, roster: Array, is_preview: bool) -> void:", "\nfunc _mpm_orig__setup_match_local(theme_id: int, seed_val: int, roster: Array, is_preview: bool) -> void:"],
		["\nfunc _update_player_hud_3d(p: Dictionary) -> void:", "\nfunc _mpm_orig__update_player_hud_3d(p: Dictionary) -> void:"],
		["\nfunc _hit_player_by_blast(p: Dictionary, attacker_id: int) -> void:", "\nfunc _mpm_orig__hit_player_by_blast(p: Dictionary, attacker_id: int) -> void:"],
		["\nfunc _eliminate_player(p: Dictionary, killer_id: int, reason: String) -> void:", "\nfunc _mpm_orig__eliminate_player(p: Dictionary, killer_id: int, reason: String) -> void:"],
		["\nfunc _compute_ai_input(p: Dictionary, delta: float) -> Dictionary:", "\nfunc _mpm_orig__compute_ai_input(p: Dictionary, delta: float) -> Dictionary:"],
		["\nfunc _check_round_end() -> void:", "\nfunc _mpm_orig__check_round_end() -> void:"],
	]
	var out: String = base_src
	for pair in hooks:
		if not out.contains(pair[0]):
			return ""
		out = out.replace(pair[0], pair[1])
	out += _stage_common_helpers_source()
	out += """
var _mpm_last_scores: Dictionary = {}


func _setup_match_local(theme_id: int, seed_val: int, roster: Array, is_preview: bool) -> void:
	_mpm_resolve_roster_teams(roster)
	var synced_roster: Array = _mpm_sync_roster_suits(roster) if _mpm_team_active else roster
	_mpm_orig__setup_match_local(theme_id, seed_val, synced_roster, is_preview)
	if get_parent() != null:
		get_parent().set_meta(&"mpm_custom_team_game", _mpm_team_active)
		get_parent().set_meta(&"mpm_team_scores_applied", false)
	if not _mpm_team_active or _players.is_empty():
		return

	# Regroup existing safe-zone corner/perimeter slots clockwise around center by team.
	var slots: Array = []
	var order_ids: Array = []
	for raw in roster:
		var nid: int = int((raw as Dictionary).get("network_id", 0))
		if _players.has(nid):
			order_ids.append(nid)
			slots.append(_players[nid]["pos"])
	for raw_nid in _players.keys():
		if not order_ids.has(int(raw_nid)):
			order_ids.append(int(raw_nid))
			slots.append(_players[raw_nid]["pos"])

	slots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z, a.x) < atan2(b.z, b.x)
	)
	var keyed: Array = []
	for idx in range(order_ids.size()):
		var nid: int = int(order_ids[idx])
		var tid: int = _mpm_player_team(nid)
		keyed.append({"team": tid if tid > 0 else 999, "idx": idx, "nid": nid})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["team"]) != int(b["team"]):
			return int(a["team"]) < int(b["team"])
		return int(a["idx"]) < int(b["idx"])
	)

	var cjk_font: Font = _mpm_tp_font()
	for idx in range(keyed.size()):
		var nid: int = int((keyed[idx] as Dictionary)["nid"])
		var p: Dictionary = _players[nid]
		var tid: int = _mpm_player_team(nid)
		p["mpm_team_id"] = tid
		p["mpm_rescues"] = 0
		if idx < slots.size():
			var wp: Vector3 = slots[idx] as Vector3
			p["pos"] = wp
			var node: Node3D = p.get("node", null) as Node3D
			if node != null:
				node.position = wp
		if tid > 0:
			var base_nick: String = str(p.get("nickname", ""))
			var tag: String = _mpm_team_tag(tid)
			if not base_nick.begins_with(tag + " "):
				p["nickname"] = "%s %s" % [tag, base_nick]
			var pnode: Node3D = p.get("node", null) as Node3D
			if pnode != null:
				_mpm_attach_foot_ring(pnode, tid)
				var np := pnode.get_node_or_null("Nameplate") as Label3D
				if np != null:
					np.text = str(p["nickname"])
					np.modulate = _mpm_team_color(tid)
					if cjk_font != null and np.font != cjk_font:
						np.font = cjk_font
				var hp_lbl := pnode.get_node_or_null("HpBar") as Label3D
				if hp_lbl != null and cjk_font != null and hp_lbl.font != cjk_font:
					hp_lbl.font = cjk_font


func _update_player_hud_3d(p: Dictionary) -> void:
	_mpm_orig__update_player_hud_3d(p)
	if not _mpm_team_active:
		return
	if bool(p.get("alive", false)) and bool(p.get("trapped", false)) and not bool(p.get("has_needle", false)):
		var node: Node3D = p.get("node", null) as Node3D
		if node == null:
			return
		var hp_label := node.get_node_or_null("HpBar") as Label3D
		if hp_label != null:
			var rem: float = maxf(0.0, C.TRAPPED_DURATION_SEC - float(p.get("trapped_timer", 0.0)))
			var is_tw: bool = _mpm_is_tw_locale()
			var is_cn: bool = _mpm_is_cn_locale()
			hp_label.text = ("[救命! %.1fs]" % rem) if (is_tw or is_cn) else ("[HELP! %.1fs]" % rem)
			var cf: Font = _mpm_tp_font()
			if cf != null and hp_label.font != cf:
				hp_label.font = cf
			var tid: int = _mpm_player_team(int(p["network_id"]))
			var flash_on: bool = int(floor(Time.get_ticks_msec() * 0.010)) % 2 == 0
			hp_label.modulate = _mpm_team_color(tid) if (tid > 0 and flash_on) else Color(1.0, 0.92, 0.30)


func _hit_player_by_blast(p: Dictionary, attacker_id: int) -> void:
	if _mpm_team_active and attacker_id > 0 and _mpm_are_teammates(int(p["network_id"]), attacker_id):
		return
	_mpm_orig__hit_player_by_blast(p, attacker_id)


func _eliminate_player(p: Dictionary, killer_id: int, reason: String) -> void:
	if _mpm_team_active and reason == "BUMP POP" and killer_id > 0 and _mpm_are_teammates(int(p["network_id"]), killer_id):
		if not bool(p["alive"]) or not bool(p["trapped"]):
			return
		p["trapped"] = false
		p["trapped_timer"] = 0.0
		p["hp"] = 1
		p["invuln_timer"] = C.INVULN_DURATION_SEC
		if _players.has(killer_id):
			var rescuer: Dictionary = _players[killer_id]
			rescuer["mpm_rescues"] = int(rescuer.get("mpm_rescues", 0)) + 1
			var r_name: String = str(rescuer["nickname"])
			var v_name: String = str(p["nickname"])
			_show_kill_feed(("%s 救活了 %s!" % [r_name, v_name]) if (_mpm_is_tw_locale() or _mpm_is_cn_locale()) else ("%s RESCUED %s!" % [r_name, v_name]))
		if _sfx_ding != null:
			_sfx_ding.play()
		_update_player_hud_3d(p)
		return
	_mpm_orig__eliminate_player(p, killer_id, reason)


func _compute_ai_input(p: Dictionary, delta: float) -> Dictionary:
	var out: Dictionary = _mpm_orig__compute_ai_input(p, delta)
	if not _mpm_team_active or bool(out.get("drop", false)):
		return out
	var my_id: int = int(p["network_id"])
	var cell: Vector2i = C.world_to_grid(p["pos"], _map_width, _map_height)
	var danger: Dictionary = {}
	for b_id in _bubbles.keys():
		var b: Dictionary = _bubbles[b_id]
		var orig: Vector2i = b["cell"]
		danger[orig] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for step in range(1, int(b["power"]) + 1):
				var c: Vector2i = orig + d * step
				if _is_tile_blocked(c):
					break
				danger[c] = true
	if danger.has(cell):
		return out

	var best_dir := Vector2.ZERO
	var best_dist: int = 5
	for other_id in _players.keys():
		var oid: int = int(other_id)
		if oid == my_id or not _mpm_are_teammates(my_id, oid):
			continue
		var op: Dictionary = _players[other_id]
		if not bool(op["alive"]) or not bool(op["trapped"]):
			continue
		var mate_cell: Vector2i = C.world_to_grid(op["pos"], _map_width, _map_height)
		var dist_cells: int = abs(mate_cell.x - cell.x) + abs(mate_cell.y - cell.y)
		if dist_cells < best_dist:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: Vector2i = cell + d
				if _is_tile_blocked(nc) or _bubble_at_cell(nc) != -1 or danger.has(nc):
					continue
				if abs(mate_cell.x - nc.x) + abs(mate_cell.y - nc.y) < dist_cells:
					best_dist = dist_cells
					best_dir = Vector2(float(d.x), float(d.y))
	if best_dir.length_squared() > 0.1:
		return {"dir": best_dir, "drop": false}
	return out


func _check_round_end() -> void:
	if not _mpm_team_active:
		_mpm_orig__check_round_end()
		return
	if _round_ended:
		return
	var alive_ids: Array = []
	var alive_teams: Dictionary = {}
	for net_id in _players.keys():
		var pl: Dictionary = _players[net_id]
		if bool(pl["alive"]):
			alive_ids.append(int(net_id))
			var tid: int = _mpm_player_team(int(net_id))
			alive_teams[tid if tid > 0 else -int(net_id)] = true
	var should_end: bool = (_time_remaining <= 0.0) or (_players.size() > 1 and alive_teams.size() <= 1) or (_players.size() == 1 and alive_ids.is_empty())
	if not should_end:
		return

	_round_ended = true
	_round_active = false
	var entries: Array = []
	for net_id in _players.keys():
		var pl: Dictionary = _players[net_id]
		entries.append({
			"network_id": int(pl["network_id"]),
			"alive": bool(pl["alive"]),
			"elim_time": float(pl["elim_time"]),
			"pops": int(pl["pops"]),
			"traps": int(pl["traps"]),
		})
	var scores: Dictionary = _mpm_sync_scores(C.compute_rank_scores(entries), alive_ids)
	_mpm_last_scores = scores
	_mpm_notify_round_win(scores, self)
	if get_parent() != null:
		get_parent().set_meta(&"mpm_team_scores_applied", true)
	var win_tid: int = 0
	if alive_teams.size() == 1:
		var k: int = int(alive_teams.keys()[0])
		if k > 0:
			win_tid = k
	else:
		var best_sc: int = -1
		for nid_v in scores.keys():
			var tid: int = _mpm_player_team(int(nid_v))
			if tid > 0 and int(scores[nid_v]) > best_sc:
				best_sc = int(scores[nid_v])
				win_tid = tid
	var banner_text: String = _mpm_team_win_banner(win_tid) if win_tid > 0 else "ROUND COMPLETE!"
	_banner_label.text = banner_text
	if _is_self_test:
		return
	if _standalone_mode:
		await get_tree().create_timer(1.8).timeout
		if is_inside_tree():
			get_tree().quit()
	else:
		_rpc_round_banner.rpc(banner_text)
		await get_tree().create_timer(1.4).timeout
		if is_inside_tree():
			round_finished.emit(scores)
"""
	return out


func _build_spike_ring_wrapper_source(base_src: String) -> String:
	var hooks := [
		["\nfunc _setup_match_local(round_index: int, seed_val: int, roster: Array, is_preview: bool) -> void:", "\nfunc _mpm_orig__setup_match_local(round_index: int, seed_val: int, roster: Array, is_preview: bool) -> void:"],
		["\nfunc _try_push(attacker: Dictionary) -> void:", "\nfunc _mpm_orig__try_push(attacker: Dictionary) -> void:"],
		["\nfunc _step_airdrops(delta: float) -> void:", "\nfunc _mpm_orig__step_airdrops(delta: float) -> void:"],
		["\nfunc _compute_ai_input(p: Dictionary, delta: float, prep: bool) -> Dictionary:", "\nfunc _mpm_orig__compute_ai_input(p: Dictionary, delta: float, prep: bool) -> Dictionary:"],
		["\nfunc _check_round_end() -> void:", "\nfunc _mpm_orig__check_round_end() -> void:"],
		["\nfunc _finish_round(time_up: bool) -> void:", "\nfunc _mpm_orig__finish_round(time_up: bool) -> void:"],
	]
	var out: String = base_src
	for pair in hooks:
		if not out.contains(pair[0]):
			return ""
		out = out.replace(pair[0], pair[1])
	out += _stage_common_helpers_source()
	out += """
var _mpm_early_win_tid: int = 0


func _setup_match_local(round_index: int, seed_val: int, roster: Array, is_preview: bool) -> void:
	_mpm_resolve_roster_teams(roster)
	var synced_roster: Array = _mpm_sync_roster_suits(roster) if _mpm_team_active else roster
	_mpm_orig__setup_match_local(round_index, seed_val, synced_roster, is_preview)
	_mpm_early_win_tid = 0
	if get_parent() != null:
		get_parent().set_meta(&"mpm_custom_team_game", _mpm_team_active)
		get_parent().set_meta(&"mpm_team_scores_applied", false)
	if not _mpm_team_active or _players.is_empty():
		return

	var slots: Array = []
	var order_ids: Array = []
	for raw in roster:
		var nid: int = int((raw as Dictionary).get("network_id", 0))
		if _players.has(nid):
			order_ids.append(nid)
			slots.append(_players[nid]["pos"])
	for raw_nid in _players.keys():
		if not order_ids.has(int(raw_nid)):
			order_ids.append(int(raw_nid))
			slots.append(_players[raw_nid]["pos"])
	slots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z, a.x) < atan2(b.z, b.x)
	)
	var keyed: Array = []
	for idx in range(order_ids.size()):
		var nid: int = int(order_ids[idx])
		var tid: int = _mpm_player_team(nid)
		keyed.append({"team": tid if tid > 0 else 999, "idx": idx, "nid": nid})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["team"]) != int(b["team"]):
			return int(a["team"]) < int(b["team"])
		return int(a["idx"]) < int(b["idx"])
	)
	var cjk_font: Font = _mpm_tp_font()
	for idx in range(keyed.size()):
		var nid: int = int((keyed[idx] as Dictionary)["nid"])
		var p: Dictionary = _players[nid]
		var tid: int = _mpm_player_team(nid)
		if idx < slots.size():
			var sp: Vector3 = slots[idx] as Vector3
			p["pos"] = sp
			p["render_pos"] = sp
			_pos_history[nid] = [[0.0, sp]]
			var node: Node3D = p.get("node", null) as Node3D
			if node != null:
				node.position = sp
		if tid > 0:
			var base_nick: String = str(p.get("nickname", ""))
			var tag: String = _mpm_team_tag(tid)
			if not base_nick.begins_with(tag + " "):
				p["nickname"] = "%s %s" % [tag, base_nick]
			var pnode: Node3D = p.get("node", null) as Node3D
			if pnode != null:
				_mpm_attach_foot_ring(pnode, tid)
				var np := pnode.get_node_or_null("Nameplate") as Label3D
				if np != null:
					np.text = str(p["nickname"])
					np.modulate = _mpm_team_color(tid)
					if cjk_font != null and np.font != cjk_font:
						np.font = cjk_font


func _mpm_mask_teammates_invuln(my_nid: int) -> Dictionary:
	var saved: Dictionary = {}
	for raw_id in _players.keys():
		var oid: int = int(raw_id)
		if _mpm_are_teammates(my_nid, oid):
			var op: Dictionary = _players[raw_id]
			saved[raw_id] = float(op["invuln_timer"])
			op["invuln_timer"] = maxf(float(op["invuln_timer"]), 0.05)
	return saved


func _mpm_restore_teammates_invuln(saved: Dictionary) -> void:
	for raw_id in saved.keys():
		if _players.has(raw_id):
			_players[raw_id]["invuln_timer"] = float(saved[raw_id])


func _try_push(attacker: Dictionary) -> void:
	if not _mpm_team_active:
		_mpm_orig__try_push(attacker)
		return
	var saved: Dictionary = _mpm_mask_teammates_invuln(int(attacker["network_id"]))
	_mpm_orig__try_push(attacker)
	_mpm_restore_teammates_invuln(saved)


func _compute_ai_input(p: Dictionary, delta: float, prep: bool) -> Dictionary:
	if not _mpm_team_active:
		return _mpm_orig__compute_ai_input(p, delta, prep)
	var saved: Dictionary = _mpm_mask_teammates_invuln(int(p["network_id"]))
	var out: Dictionary = _mpm_orig__compute_ai_input(p, delta, prep)
	_mpm_restore_teammates_invuln(saved)
	return out


func _step_airdrops(delta: float) -> void:
	if not _mpm_team_active:
		_mpm_orig__step_airdrops(delta)
		return
	var pre_shields: Dictionary = {}
	for net_id in _players.keys():
		pre_shields[int(net_id)] = bool(_players[net_id].get("shield", false))
	_mpm_orig__step_airdrops(delta)
	var link_txt: String = "護盾共振!" if _mpm_is_tw_locale() else ("护盾共振!" if _mpm_is_cn_locale() else "SHIELD LINK!")
	for net_id in _players.keys():
		var picker_id: int = int(net_id)
		var picker: Dictionary = _players[net_id]
		if not bool(picker.get("shield", false)) or bool(pre_shields.get(picker_id, false)):
			continue
		var pflat := Vector2(picker["pos"].x, picker["pos"].z)
		for ally_id in _players.keys():
			var aid: int = int(ally_id)
			if aid == picker_id or not _mpm_are_teammates(picker_id, aid):
				continue
			var ally: Dictionary = _players[ally_id]
			if not bool(ally["alive"]) or bool(ally.get("shield", false)):
				continue
			var aflat := Vector2(ally["pos"].x, ally["pos"].z)
			if aflat.distance_to(pflat) <= 3.5:
				ally["shield"] = true
				_spawn_score_popup(Vector3(aflat.x, 2.5, aflat.y), link_txt, Color(0.36, 0.92, 1.0))


func _check_round_end() -> void:
	if not _mpm_team_active:
		_mpm_orig__check_round_end()
		return
	if _phase != PH_LIVE:
		return
	var alive_count: int = 0
	var alive_teams: Dictionary = {}
	for net_id in _players.keys():
		if bool(_players[net_id]["alive"]):
			alive_count += 1
			var tid: int = _mpm_player_team(int(net_id))
			alive_teams[tid if tid > 0 else -int(net_id)] = true
	var all_out: bool = (alive_count == 0 and _players.size() > 0)
	var team_decided: bool = (alive_teams.size() <= 1 and _players.size() > 1)
	var time_up: bool = (_time_remaining <= 0.0)
	if not all_out and not team_decided and not time_up:
		return
	_mpm_early_win_tid = 0
	if team_decided and alive_teams.size() == 1:
		var only_key: int = int(alive_teams.keys()[0])
		if only_key > 0:
			_mpm_early_win_tid = only_key
	_finish_round(time_up or _mpm_early_win_tid > 0)


func _finish_round(time_up: bool) -> void:
	if not _mpm_team_active:
		_mpm_orig__finish_round(time_up)
		return
	_phase = PH_ENDED
	if time_up:
		for net_id in _players.keys():
			var p: Dictionary = _players[net_id]
			if bool(p["alive"]):
				p["score"] = int(p["score"]) + C.SCORE_SURVIVAL_BONUS
				_spawn_score_popup(Vector3(p["pos"].x, 2.6, p["pos"].z), "+10 存活!", Color(1.0, 0.86, 0.28))
	var entries: Array = []
	var alive_ids: Array = []
	for net_id in _players.keys():
		var p: Dictionary = _players[net_id]
		if bool(p["alive"]):
			alive_ids.append(int(net_id))
		entries.append({
			"network_id": int(p["network_id"]),
			"nickname": str(p["nickname"]),
			"score": int(p["score"]),
			"alive_sec": float(p["alive_sec"]),
			"pushes": int(p["pushes"]),
			"hits_taken": int(p["hits_taken"]),
			"out_reason": str(p["out_reason"]),
			"alive": bool(p["alive"]),
			"team_id": _mpm_player_team(int(p["network_id"])),
		})
	var ranked: Array = C.rank_entries(entries)
	var official: Dictionary = _mpm_sync_scores(C.official_scores(ranked), alive_ids)
	_mpm_notify_round_win(official, self)
	var winner_tid: int = _mpm_early_win_tid
	if winner_tid <= 0 and ranked.size() > 0:
		winner_tid = int(ranked[0].get("team_id", 0))
	if not _standalone_mode and get_parent() != null:
		get_parent().set_meta(&"mpm_team_scores_applied", true)
	_result_rows = ranked
	_banner_label.text = _mpm_team_win_banner(winner_tid) if winner_tid > 0 else "ROUND COMPLETE"
	if not _standalone_mode and multiplayer.is_server():
		_rpc_round_result.rpc(ranked)
	if _standalone_mode:
		return
	round_finished.emit(official)
"""
	return out


func _build_roller_carnival_wrapper_source(base_src: String, base_dir: String) -> String:
	var hooks := [
		["\nfunc _load_dependencies() -> void:", "\nfunc _mpm_orig__load_dependencies() -> void:"],
		["\nfunc _spawn_players() -> void:", "\nfunc _mpm_orig__spawn_players() -> void:"],
		["\nfunc _check_round_end() -> void:", "\nfunc _mpm_orig__check_round_end() -> void:"],
		["\nfunc _finish_round(reason: String) -> void:", "\nfunc _mpm_orig__finish_round(reason: String) -> void:"],
	]
	var out: String = base_src
	for pair in hooks:
		if not out.contains(pair[0]):
			return ""
		out = out.replace(pair[0], pair[1])
	var safe_cfg_path: String = base_dir.path_join("config.gd").replace("\\", "\\\\").replace("\"", "\\\"")
	var safe_meshes_path: String = base_dir.path_join("carnival_meshes.gd").replace("\\", "\\\\").replace("\"", "\\\"")
	out += _stage_common_helpers_source()
	out += """

func _load_dependencies() -> void:
	if config == null:
		var cfg_script = load("__RC_CFG__")
		config = cfg_script.new()
	if _meshes == null:
		_meshes = load("__RC_MESHES__")
	_meshes.ensure_game_pck_mounted()


func _spawn_players() -> void:
	if _hosted_in_official_game or not _roster.is_empty():
		_mpm_resolve_roster_teams(_roster)
		if _mpm_team_active:
			_roster = _mpm_sync_roster_suits(_roster)
	_mpm_orig__spawn_players()
	if not _hosted_in_official_game and _roster.is_empty():
		_mpm_resolve_roster_teams(_players)
	if get_parent() != null:
		get_parent().set_meta(&"mpm_custom_team_game", _mpm_team_active)
		get_parent().set_meta(&"mpm_team_scores_applied", false)
	if not _mpm_team_active or _players.is_empty():
		return

	var lanes: Array = []
	for p in _players:
		lanes.append(float(p["z"]))
	lanes.sort()

	_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = _mpm_player_team(int(a["network_id"]))
		var tb: int = _mpm_player_team(int(b["network_id"]))
		var ka: int = ta if ta > 0 else 999
		var kb: int = tb if tb > 0 else 999
		if ka != kb:
			return ka < kb
		return int(a["id"]) < int(b["id"])
	)
	var cjk_font: Font = _mpm_tp_font()
	for i in range(_players.size()):
		var p: Dictionary = _players[i]
		if i < lanes.size():
			p["z"] = float(lanes[i])
			var pnode: Node3D = p["node"] as Node3D
			if pnode != null:
				pnode.position.z = float(lanes[i])
		var nid: int = int(p["network_id"])
		var tid: int = _mpm_player_team(nid)
		p["team_id"] = tid
		if tid > 0:
			var pnode: Node3D = p.get("node", null) as Node3D
			if pnode != null:
				_mpm_attach_foot_ring(pnode, tid, 0.36, 0.45)
			var base_nick: String = str(p["nickname"])
			var tag: String = _mpm_team_tag(tid)
			if not base_nick.begins_with(tag + " "):
				p["nickname"] = "%s %s" % [tag, base_nick]
			var lbl := p.get("label", null) as Label3D
			if lbl != null:
				var short_base: String = base_nick.left(11) + "-" if base_nick.length() > 11 else base_nick
				lbl.text = "%s %s" % [tag, short_base]
				lbl.modulate = _mpm_team_color(tid)
				if cjk_font != null and lbl.font != cjk_font:
					lbl.font = cjk_font


func _check_round_end() -> void:
	if not _mpm_team_active:
		_mpm_orig__check_round_end()
		return
	var alive_count: int = 0
	var alive_teams: Dictionary = {}
	for p in _players:
		if p["alive"]:
			alive_count += 1
			var tid: int = _mpm_player_team(int(p["network_id"]))
			alive_teams[tid if tid > 0 else -int(p["network_id"])] = true
	if alive_count == 0:
		_finish_round("全員落入粉碎熔爐淘汰（提前結束）")
	elif alive_teams.size() <= 1 and _players.size() > 1:
		var win_tid: int = int(alive_teams.keys()[0]) if alive_teams.size() == 1 else 0
		_finish_round(_mpm_team_win_banner(win_tid) if win_tid > 0 else "對局提前結束")
	elif _time_left <= 0.0:
		_finish_round("倒計時結束！%d 名存活玩家獲勝" % alive_count)


func _finish_round(reason: String) -> void:
	if not _mpm_team_active:
		_mpm_orig__finish_round(reason)
		return
	if _match_ended:
		return
	_match_ended = true
	var rankings: Array[Dictionary] = _compute_rankings()
	var finalized_scores: Dictionary = {}
	for r in rankings:
		finalized_scores[int(r["network_id"])] = int(r["bonus"])
	var alive_ids: Array = []
	for p in _players:
		if bool(p["alive"]):
			alive_ids.append(int(p["network_id"]))
	finalized_scores = _mpm_sync_scores(finalized_scores, alive_ids)
	_mpm_notify_round_win(finalized_scores, self)
	if _hosted_in_official_game and get_parent() != null:
		get_parent().set_meta(&"mpm_team_scores_applied", true)
	if _hosted_in_official_game and not _is_self_test:
		show_round_result.rpc(rankings, reason)
	else:
		show_round_result(rankings, reason)
	if _hosted_in_official_game:
		round_finished.emit(finalized_scores)
""".replace("__RC_CFG__", safe_cfg_path).replace("__RC_MESHES__", safe_meshes_path)
	return out

