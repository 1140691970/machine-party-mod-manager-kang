extends Node

## Team Party (組隊派對) — Global Team Mode Mod for Machine Party (API v2).
##
## Owns:
## - Room-level team setup in the lobby: OFF / 2/TEAM / 4/TEAM / FREE (Red, Blue, Green, Yellow),
##   chair click / ragdoll drag-and-drop, smart bot swap, and guest consent swaps.
## - Shared team registry (`Engine` meta `&"mpm_team_party"`) consumed natively by first-party
##   minigame mods (`bubble-blitz`, `spike-ring`, `roller-carnival`) and community mods.
## - Official/vanilla minigame hooks: in-game `▼ [TEAM]` badges, ground rings, friendly shove
##   filtering, Disco AI target filtering, early team victory, Squads synchronized scoring, and
##   top-right frameless HUD.

const MOD_ID := "team-party"
const META_KEY := &"mpm_team_party"
const REG_RES_DIR := "res://mods_team_party/"
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

const HELPER_SCRIPTS := [
	"team_registry.gd",
	"lobby_assignment.gd",
	"lobby_ui.gd",
	"lobby_drag_3d.gd",
	"vanilla_ingame.gd",
	"ingame_hud.gd",
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
var _pending_swap_requests: Dictionary = {}
var _incoming_swap_from: int = 0
var _incoming_swap_name: String = ""
var _incoming_swap_expires: float = 0.0
var _last_roster_sig: String = ""
var _lobby_seat_rings: Dictionary = {}
var _lobby_seat_halos: Dictionary = {}
var _lobby_seat_rest_floor: Dictionary = {}
var _lobby_seat_rest_slot_xform: Dictionary = {}
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
var _drag_saved_bones: Dictionary = {}
var _drag_anim_was_playing: bool = false
var _drag_rest_collar: Vector3 = Vector3.ZERO
var _drag_is_remote: bool = false
var _drag_net_accum: float = 0.0
var _drag_last_sent_pos: Vector3 = Vector3.ZERO
var _drag_last_sent_hover: int = -2
var _seat_drop_bounce: Dictionary = {}
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
var _hud_wins: Dictionary = {}
var _last_hud_sig: String = ""
var _current_stage_node: Node = null

# In-game actor tracking & UI assets
var _tracked_actors: Dictionary = {}
var _cjk_badge_font: Font = null
var _crt_font_checked: bool = false
var _crt_font: Font = null
var _orig_nametag_alpha: Dictionary = {}
var _sfx_ui_click: AudioStream = null
var _sfx_ui_player: AudioStreamPlayer = null
var _hud_title_lbl: Label = null
var _format_badge_lbl: Label = null

# Modular helper instances
var _registered_scripts: Dictionary = {}
var _reg = null
var _assign = null
var _ui = null
var _drag = null
var _vanilla = null
var _hud = null


func _load_sibling_script(filename: String) -> GDScript:
	if _registered_scripts.has(filename) and _registered_scripts[filename] != null:
		return _registered_scripts[filename] as GDScript
	if ResourceLoader.exists(REG_RES_DIR + filename):
		var reg_res = ResourceLoader.load(REG_RES_DIR + filename)
		if reg_res is GDScript:
			return reg_res as GDScript
	var self_script: Script = get_script()
	if self_script != null and not self_script.resource_path.is_empty():
		var sibling_path: String = self_script.resource_path.get_base_dir().path_join(filename)
		if ResourceLoader.exists(sibling_path):
			var sib_res = ResourceLoader.load(sibling_path)
			if sib_res is GDScript:
				return sib_res as GDScript
	var fallback_path: String = "res://" + filename
	if ResourceLoader.exists(fallback_path):
		var fb_res = load(fallback_path)
		if fb_res is GDScript:
			return fb_res as GDScript
	return null


func _register_mod_scripts(loader) -> void:
	if loader == null:
		return
	var use_register_api := false
	if loader.has_method("has_api"):
		use_register_api = bool(loader.call("has_api", "register_script"))
	if use_register_api and loader.has_method("register_script"):
		for rel in HELPER_SCRIPTS:
			var res_path: String = REG_RES_DIR + rel
			loader.register_script(MOD_ID, rel, res_path)
			_registered_scripts[rel] = ResourceLoader.load(res_path)
		return
	if loader.has_method("compile") and loader.has_method("dir_of"):
		var mod_dir: String = str(loader.dir_of(MOD_ID))
		for rel in HELPER_SCRIPTS:
			var gd = loader.compile(mod_dir.path_join(rel))
			if gd != null:
				gd.take_over_path(REG_RES_DIR + rel)
				_registered_scripts[rel] = gd


func _ensure_modules() -> void:
	if _reg == null:
		_reg = _load_sibling_script("team_registry.gd").new(self)
	if _assign == null:
		_assign = _load_sibling_script("lobby_assignment.gd").new(self)
	if _ui == null:
		_ui = _load_sibling_script("lobby_ui.gd").new(self)
	if _drag == null:
		_drag = _load_sibling_script("lobby_drag_3d.gd").new(self)
	if _vanilla == null:
		_vanilla = _load_sibling_script("vanilla_ingame.gd").new(self)
	if _hud == null:
		_hud = _load_sibling_script("ingame_hud.gd").new(self)


func _mod_init(loader) -> void:
	_rng.randomize()
	_register_mod_scripts(loader)
	_ensure_modules()
	_reg.publish_state()
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
	_ensure_modules()
	set_physics_process_priority(50)
	_reg.publish_state()
	_connect_network.call_deferred()


func _exit_tree() -> void:
	if _drag != null:
		_drag.cancel_lobby_drag()
		_drag.clear_lobby_3d_rings()
	for rec in _tracked_actors.values():
		if _vanilla != null:
			_vanilla.cleanup_actor_record(rec)
	_tracked_actors.clear()
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
	_reg = null
	_assign = null
	_ui = null
	_drag = null
	_vanilla = null
	_hud = null
	_registered_scripts.clear()


func _connect_network() -> void:
	_ensure_modules()
	var net = _assign.network()
	if net != null and net.has_signal("on_peer_connected"):
		if not net.on_peer_connected.is_connected(_peer_connected):
			net.on_peer_connected.connect(_peer_connected)


func _peer_connected(id: int) -> void:
	_ensure_modules()
	_assign.peer_connected(id)


func _input(event: InputEvent) -> void:
	if _drag != null:
		_drag.handle_input(event)


func _physics_process(_delta: float) -> void:
	if _vanilla != null:
		_vanilla.step_physics()


func _process(delta: float) -> void:
	_anim_time += delta
	_ensure_modules()
	_drag.step_lobby(delta)
	if _reg.is_team_mode_active():
		_vanilla.check_vanilla_early_team_victory()
	_vanilla.step_actors(delta)
	_hud.step_hud(delta)


func _node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_ensure_modules()
	if node.has_signal("player_game_ready") and node.has_method("load_minigame"):
		_vanilla.attach_game(node)
		return
	if node.has_signal("minigame_finished") and node.has_signal("player_scores_finalized"):
		_vanilla.attach_minigame(node)
		return
	if node is Node3D and node.has_meta(&"mpm_native_team_stage"):
		_hud.register_native_team_stage(node)
		return
	if node is Node3D and node.get_script() != null and &"player_presence" in node:
		if not _vanilla.is_skipped_scene_node(node):
			Callable(self, "_track_actor").call_deferred(node as Node3D)


# ============================================================================
# Public Team Registry API (read by native minigames, vanilla hooks & tests)
# ============================================================================

func is_team_mode_active() -> bool:
	_ensure_modules()
	return _reg.is_team_mode_active()

func get_team(net_id: int) -> int:
	_ensure_modules()
	return _reg.get_team(net_id)

func are_teammates(id_a: int, id_b: int) -> bool:
	_ensure_modules()
	return _reg.are_teammates(id_a, id_b)

func get_team_color(team_id: int) -> Color:
	_ensure_modules()
	return _reg.get_team_color(team_id)

func get_team_tag(team_id: int) -> String:
	_ensure_modules()
	return _reg.get_team_tag(team_id)

func get_team_name(team_id: int) -> String:
	_ensure_modules()
	return _reg.get_team_name(team_id)

func strip_team_prefix(text: String) -> String:
	_ensure_modules()
	return _reg.strip_team_prefix(text)

func format_team_nickname(net_id: int, base_name: String) -> String:
	_ensure_modules()
	return _reg.format_team_nickname(net_id, base_name)

func sort_roster_by_team(roster: Array) -> Array:
	_ensure_modules()
	return _reg.sort_roster_by_team(roster)

func compute_team_synchronized_scores(raw_scores: Dictionary, alive_ids: Array = []) -> Dictionary:
	_ensure_modules()
	return _reg.compute_team_synchronized_scores(raw_scores, alive_ids)

func record_team_win(scores: Dictionary, stage_node: Node = null) -> void:
	_ensure_modules()
	_hud.record_team_win(scores, stage_node)

func register_native_team_stage(stage: Node) -> void:
	_ensure_modules()
	_hud.register_native_team_stage(stage)

func set_team_format(new_fmt: int) -> void:
	_ensure_modules()
	_assign.set_team_format(new_fmt)

func cycle_team_mode() -> void:
	_ensure_modules()
	_assign.cycle_team_mode()

func set_team_mode(new_count: int) -> void:
	_ensure_modules()
	_assign.set_team_mode(new_count)

func shuffle_teams() -> void:
	_ensure_modules()
	_assign.shuffle_teams()

func assign_player_team(target_id: int, desired_team: int) -> void:
	_ensure_modules()
	_assign.assign_player_team(target_id, desired_team)

func cycle_participant_team(target_id: int) -> void:
	_ensure_modules()
	_assign.cycle_participant_team(target_id)

func click_lobby_chair(seat: int, acting_peer_id: int = 0) -> bool:
	_ensure_modules()
	return _assign.click_lobby_chair(seat, acting_peer_id)

func host_drop_chair(from_seat: int, to_seat: int) -> bool:
	_ensure_modules()
	return _assign.host_drop_chair(from_seat, to_seat)

func respond_swap_request(accepted: bool, responding_peer_id: int = 0) -> bool:
	_ensure_modules()
	return _assign.respond_swap_request(accepted, responding_peer_id)


# ============================================================================
# Facade Delegators for Tests & Signal Callbacks
# ============================================================================

func _publish_state() -> void:
	_ensure_modules()
	_reg.publish_state()

func _enter_lobby(node: Node) -> void:
	_ensure_modules()
	_drag.enter_lobby(node)

func _leave_lobby() -> void:
	if _drag != null:
		_drag.leave_lobby()

func _refresh_lobby_ui() -> void:
	_ensure_modules()
	_ui.refresh_lobby_ui()

func _update_lobby_nametags() -> void:
	_ensure_modules()
	_drag.update_lobby_nametags()

func _sync_lobby_3d_visuals() -> void:
	_ensure_modules()
	_drag.update_lobby_nametags()

func _lock_for_game() -> void:
	_ensure_modules()
	_assign.lock_for_game()

func _reset_lobby_state() -> void:
	_ensure_modules()
	_assign.reset_lobby_state()

func _cancel_lobby_drag() -> void:
	if _drag != null:
		_drag.cancel_lobby_drag()

func _attach_game(node: Node) -> void:
	_ensure_modules()
	_vanilla.attach_game(node)

func _on_game_exiting() -> void:
	if _vanilla != null:
		_vanilla.on_game_exiting()

func _attach_minigame(mg: Node) -> void:
	_ensure_modules()
	_vanilla.attach_minigame(mg)

func _on_minigame_exiting(mg: Node) -> void:
	if _vanilla != null:
		_vanilla.on_minigame_exiting(mg)

func _on_minigame_finished(id, mg: Node) -> void:
	if _vanilla != null:
		_vanilla.on_minigame_finished(id, mg)

func _on_stage_exiting(node: Node) -> void:
	if _hud != null:
		_hud.on_stage_exiting(node)

func _presence_network_id(presence) -> int:
	_ensure_modules()
	return _vanilla.presence_network_id(presence)

func _track_actor(actor: Node3D) -> void:
	_ensure_modules()
	_vanilla.track_actor(actor)

func _sync_actor_visual(rec: Dictionary) -> void:
	_ensure_modules()
	_vanilla.sync_actor_visual(rec)

func _refresh_hud(force: bool = false) -> void:
	_ensure_modules()
	_hud.refresh_hud(force)

func _hide_hud() -> void:
	if _hud != null:
		_hud.hide_hud()

func _is_tw_locale(loc: String = "") -> bool:
	_ensure_modules()
	return _reg.is_tw_locale(loc)

func _is_cn_locale(loc: String = "") -> bool:
	_ensure_modules()
	return _reg.is_cn_locale(loc)

func _seat_zone_team(seat_idx: int, total_seats: int) -> int:
	_ensure_modules()
	return _reg.seat_zone_team(seat_idx, total_seats)

func _apply_team_join_or_swap(actor_id: int, desired_team: int, target_seat: int = -1, prefer_bot_id: int = 0) -> bool:
	_ensure_modules()
	return _assign.apply_team_join_or_swap(actor_id, desired_team, target_seat, prefer_bot_id)

func _seat_world_floor_pos(slot_node: Node3D, lbl: Label3D, seat: int = -1) -> Vector3:
	_ensure_modules()
	return _drag.seat_world_floor_pos(slot_node, lbl, seat)

func _project_seat_to_screen(world_pt: Vector3, cam: Camera3D, sub_vp: Viewport, tex_rect: TextureRect) -> Vector2:
	_ensure_modules()
	return _drag.project_seat_to_screen(world_pt, cam, sub_vp, tex_rect)

func _screen_to_lobby_drag_pos(mouse_pos: Vector2) -> Variant:
	_ensure_modules()
	return _drag.screen_to_lobby_drag_pos(mouse_pos)

func _begin_drag_skeleton(slot_node: Node3D) -> void:
	_ensure_modules()
	_drag.begin_drag_skeleton(slot_node)

func _apply_drag_dangling_pose() -> void:
	_ensure_modules()
	_drag.apply_drag_dangling_pose()

func _clear_lobby_3d_rings() -> void:
	if _drag != null:
		_drag.clear_lobby_3d_rings()

func _cleanup_actor_record(rec: Dictionary) -> void:
	if _vanilla != null:
		_vanilla.cleanup_actor_record(rec)

func _apply_remote_drag_begin(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	_ensure_modules()
	_drag.apply_remote_drag_begin(seat, target_pos, hover_seat)

func _apply_remote_drag_pose(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	_ensure_modules()
	_drag.apply_remote_drag_pose(seat, target_pos, hover_seat)

func _apply_remote_drag_end(from_seat: int, bounce_seats: Array) -> void:
	_ensure_modules()
	_drag.apply_remote_drag_end(from_seat, bounce_seats)

func _on_format_button_pressed(fmt: int) -> void:
	_ensure_modules()
	_ui.play_ui_click()
	_assign.set_team_format(fmt)

func _on_cycle_mode_pressed() -> void:
	_ensure_modules()
	_ui.play_ui_click()
	_assign.cycle_team_mode()

func _on_custom_count_pressed() -> void:
	_ensure_modules()
	if not _assign.can_host_edit():
		return
	_ui.play_ui_click()
	var next_c: int = 3 if team_count == 2 else (4 if team_count == 3 else 2)
	team_format = FORMAT_CUSTOM
	_assign.set_team_mode(next_c)

func _on_shuffle_pressed() -> void:
	_ensure_modules()
	_ui.play_ui_click()
	_assign.shuffle_teams()

func _on_my_team_pressed() -> void:
	_ensure_modules()
	if not _assign.can_guest_pick_self():
		return
	_assign.cycle_participant_team(_assign.local_peer_id())

func _on_swap_accept_pressed() -> void:
	_ensure_modules()
	_ui.play_ui_click()
	_assign.respond_swap_request(true)

func _on_swap_decline_pressed() -> void:
	_ensure_modules()
	_ui.play_ui_click()
	_assign.respond_swap_request(false)


# ============================================================================
# Multiplayer RPC Endpoints (must live directly on the Node script)
# ============================================================================

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_change_team(desired_team: int) -> void:
	_ensure_modules()
	_assign.handle_rpc_request_change_team(desired_team)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_chair_action(target_seat: int, desired_team: int) -> void:
	_ensure_modules()
	_assign.handle_rpc_request_chair_action(target_seat, desired_team)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_respond_swap(from_id: int, accepted: bool) -> void:
	_ensure_modules()
	_assign.handle_rpc_respond_swap(from_id, accepted)

@rpc("authority", "call_remote", "reliable")
func _rpc_receive_swap_offer(from_id: int, from_name: String) -> void:
	_ensure_modules()
	_assign.apply_receive_swap_offer(from_id, from_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_notify_terminal(msg: String) -> void:
	_ensure_modules()
	_ui.notify_lobby_terminal(msg)

@rpc("authority", "call_remote", "reliable")
func _rpc_drag_begin(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	_ensure_modules()
	if not _assign.is_host_authoritative():
		_drag.apply_remote_drag_begin(seat, target_pos, hover_seat)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_drag_pose(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	_ensure_modules()
	if not _assign.is_host_authoritative():
		_drag.apply_remote_drag_pose(seat, target_pos, hover_seat)

@rpc("authority", "call_remote", "reliable")
func _rpc_drag_end(from_seat: int, bounce_seats: Array) -> void:
	_ensure_modules()
	if not _assign.is_host_authoritative():
		_drag.apply_remote_drag_end(from_seat, bounce_seats)

@rpc("authority", "call_remote", "reliable")
func _sync_teams(count: int, mapping: Dictionary, fmt: int = -1, wins: Dictionary = {}) -> void:
	_ensure_modules()
	_assign.apply_sync_teams(count, mapping, fmt, wins)
