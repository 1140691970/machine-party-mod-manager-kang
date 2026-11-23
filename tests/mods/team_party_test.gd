extends SceneTree

class LoaderFixture:
	var scene_hooks := {}
	var node_callbacks: Array = []
	var registries := {}

	func has_api(api_name: String) -> bool:
		return api_name == "registry"

	func on_scene_script(path: String, cb: Callable) -> void:
		scene_hooks[path] = cb

	func on_node_added(cb: Callable) -> void:
		node_callbacks.append(cb)

	func registry(id: String) -> Dictionary:
		if not registries.has(id):
			registries[id] = {}
		return registries[id]


class NetworkFixture extends Node:
	signal on_peer_connected(id)
	var active_backend := {
		"connected_players": {
			1: {"name": "Host"},
			2: {"name": "Guest2"},
		}
	}


class BotsFixture extends Node:
	var bots := {-1: 1}


class LobbyHandlerFixture extends Control:
	signal start_pressed
	signal back_pressed
	var active := true
	var root: Control = self
	var players: Array = []
	var nametags: Array = []
	var last_message: String = ""

	func send_lobby_message(msg: String) -> void:
		last_message = msg


class LobbyFixture extends Node:
	var lobby_handler := LobbyHandlerFixture.new()
	var loading := false
	var player_order_by_seat := {0: 1, 1: 2, 2: -1, 3: -1}


class GameFixture extends Node:
	signal player_game_ready(id)
	var round_score_by_network_id := {}
	var in_cutscene: bool = false

	func load_minigame():
		pass

	func is_current_game_cutscene() -> bool:
		return in_cutscene


class MinigameFixture extends Node:
	signal minigame_finished(id)
	signal player_scores_finalized(scores)
	var active_players := {}
	var dead_players := []
	var player_scores := {}
	var player_count := 4
	var finished := false
	var game_end := false
	var finish_called := false

	func calculate_score():
		pass

	func finish_game():
		finish_called = true
		minigame_finished.emit(0)


var _failed := false


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("TEAM_PARTY_TEST_FAIL: " + msg)


func _make_actor_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node3D
var player_presence := {}
var player_name_label: Label3D = null
var players_in_shove_proximity: Array = []
var active: bool = true
"""
	s.reload()
	return s


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	TranslationServer.set_locale("en")
	var loader := LoaderFixture.new()

	var net := NetworkFixture.new()
	net.name = "NetworkManager"
	root.add_child(net)

	var mod_loader := Node.new()
	mod_loader.name = "ModLoader"
	root.add_child(mod_loader)

	var bots := BotsFixture.new()
	bots.name = "lobby-bots"
	mod_loader.add_child(bots)

	var mod_script: GDScript = load("res://main.gd")
	var mod: Node = mod_script.new()
	mod.name = "team-party"
	mod_loader.add_child(mod)
	mod._mod_init(loader)
	mod._mod_ready(loader)

	# 1. Registry & initial FFA state
	expect(Engine.has_meta(&"mpm_team_party"), "Engine meta mpm_team_party must be registered")
	expect(not bool(mod.call("is_team_mode_active")), "starts in FFA mode")
	expect(int(mod.get("team_count")) == 0, "initial team_count is 0")

	# 2. Lobby attachment, UI placement & mode cycling
	var lobby := LobbyFixture.new()
	lobby.name = "Lobby"
	lobby.lobby_handler.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(lobby.lobby_handler)
	for i in range(4):
		var seat_node := Node3D.new()
		var lbl := Label3D.new()
		lbl.text = ["Host", "Guest2", "Bot 1", ""][i]
		lobby.add_child(seat_node)
		seat_node.add_child(lbl)
		lobby.lobby_handler.players.append(seat_node)
		lobby.lobby_handler.nametags.append(lbl)
	root.add_child(lobby)

	mod._enter_lobby(lobby)
	await process_frame

	expect(is_instance_valid(mod.get("panel")), "Lobby TeamPartyPanel created")
	var panel: PanelContainer = mod.get("panel") as PanelContainer
	expect(is_equal_approx(panel.offset_left, 24.0) and is_equal_approx(panel.offset_top, 24.0), "panel pinned top-left")

	mod.call("cycle_team_mode")
	expect(int(mod.get("team_count")) == 2 and bool(mod.call("is_team_mode_active")), "cycles 0 -> 2 teams")
	mod.call("cycle_team_mode")
	expect(int(mod.get("team_count")) == 3, "cycles 2 -> 3 teams")
	mod.call("cycle_team_mode")
	expect(int(mod.get("team_count")) == 4, "cycles 3 -> 4 teams")
	mod.call("cycle_team_mode")
	expect(int(mod.get("team_count")) == 0 and not bool(mod.call("is_team_mode_active")), "cycles 4 -> 0 FFA")

	# 3. Switch to 2 teams & shuffle across ONLY existing humans + existing lobby-bots bots (no auto-spawn!)
	mod.call("set_team_mode", 2)
	expect(bots.bots.size() == 1 and bots.bots.has(-1), "team-party must NEVER auto-spawn bots")
	mod.call("shuffle_teams")
	expect(bots.bots.size() == 1, "shuffle must NEVER auto-spawn bots")
	for existing_id in [1, 2, -1]:
		var t: int = int(mod.call("get_team", existing_id))
		expect(t == 1 or t == 2, "existing participant %d assigned to valid team" % existing_id)
	expect(int(mod.call("get_team", -99)) == 0, "unpresent non-existent bot ID must not be created")

	# 4. Host manual assignment for humans and bots + guest self-team cycle button
	mod.call("assign_player_team", 1, 1)
	mod.call("assign_player_team", 2, 2)
	mod.call("assign_player_team", -1, 2)
	expect(int(mod.call("get_team", -1)) == 2 and bool(mod.call("are_teammates", 2, -1)), "host moved Bot 1 to team 2")
	expect(not bool(mod.call("are_teammates", 1, 2)), "players on different teams are enemies")

	mod.call("_on_my_team_pressed")
	expect(int(mod.call("get_team", 1)) == 2 and bool(mod.call("are_teammates", 1, 2)), "MyTeam button switches local player team")
	mod.call("assign_player_team", 1, 1)

	# Late-joiner / straggler auto-balance on lock
	net.active_backend["connected_players"][4] = {"name": "Latecomer"}
	# Currently Team 1 has [1] (size 1), Team 2 has [2, -1] (size 2). Straggler 4 must auto-fill Team 1.
	mod.call("_lock_for_game")
	expect(bool(mod.get("locked")), "lobby locks teams on game start")
	expect(int(mod.call("get_team", 4)) == 1, "straggler balances into smallest team")
	mod.set("locked", false)

	# 5. Lobby nametag coloring + prefix & FFA restore
	mod._process(0.1)
	var host_lbl: Label3D = lobby.lobby_handler.nametags[0] as Label3D
	var g2_lbl: Label3D = lobby.lobby_handler.nametags[1] as Label3D
	var red_col: Color = mod.call("get_team_color", 1)
	var blue_col: Color = mod.call("get_team_color", 2)
	expect(host_lbl.text.begins_with("[RED] "), "host lobby nametag prefixed with [RED]")
	expect(host_lbl.modulate.is_equal_approx(Color(red_col.r, red_col.g, red_col.b, 1.0)), "host lobby nametag colored red")
	expect(g2_lbl.text.begins_with("[BLU] "), "guest2 lobby nametag prefixed with [BLU]")
	expect(g2_lbl.modulate.is_equal_approx(Color(blue_col.r, blue_col.g, blue_col.b, 1.0)), "guest2 lobby nametag colored blue")

	mod.call("set_team_mode", 0)
	mod._process(0.1)
	expect(host_lbl.text == "Host" and host_lbl.modulate.is_equal_approx(Color.WHITE), "FFA restores lobby nametag text & color")
	var hud_in_lobby = mod.get("_hud_panel")
	expect(hud_in_lobby == null or not (hud_in_lobby as Control).visible, "in-game Team HUD stays hidden in lobby")

	# 5b. 8-player Overtime formats: FORMAT_DUO (2v2v2v2), shuffle_teams balance, FORMAT_SQUAD (4v4)
	for extra_nid in [3, 5]:
		net.active_backend["connected_players"][extra_nid] = {"name": "Player %d" % extra_nid}
	for b_idx in range(2, 4):
		bots.bots[-b_idx] = b_idx
	mod.call("set_team_format", 1) # FORMAT_DUO -> 4 teams of 2 at 8 players
	expect(int(mod.get("team_count")) == 4, "8-player FORMAT_DUO activates 4 teams (2v2v2v2)")
	expect(int(mod.call("_seat_zone_team", 0, 8)) == 1 and int(mod.call("_seat_zone_team", 1, 8)) == 1, "_seat_zone_team maps seats 0..1 to Red in 8p FORMAT_DUO")
	expect(int(mod.call("_seat_zone_team", 2, 8)) == 2 and int(mod.call("_seat_zone_team", 3, 8)) == 2, "_seat_zone_team maps seats 2..3 to Blue in 8p FORMAT_DUO")
	expect(int(mod.call("_seat_zone_team", 4, 8)) == 3 and int(mod.call("_seat_zone_team", 5, 8)) == 3, "_seat_zone_team maps seats 4..5 to Green in 8p FORMAT_DUO")
	expect(int(mod.call("_seat_zone_team", 6, 8)) == 4 and int(mod.call("_seat_zone_team", 7, 8)) == 4, "_seat_zone_team maps seats 6..7 to Yellow in 8p FORMAT_DUO")
	var duo_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	for pid_raw in [1, 2, 3, 4, 5, -1, -2, -3]:
		var tid: int = int(mod.call("get_team", pid_raw))
		duo_counts[tid] = int(duo_counts.get(tid, 0)) + 1
	expect(duo_counts[1] == 2 and duo_counts[2] == 2 and duo_counts[3] == 2 and duo_counts[4] == 2, "FORMAT_DUO assigns exactly 2 players per team across 8 participants")

	mod.call("shuffle_teams")
	var shuffled_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	for pid_raw in [1, 2, 3, 4, 5, -1, -2, -3]:
		var tid: int = int(mod.call("get_team", pid_raw))
		shuffled_counts[tid] = int(shuffled_counts.get(tid, 0)) + 1
	expect(shuffled_counts[1] == 2 and shuffled_counts[2] == 2 and shuffled_counts[3] == 2 and shuffled_counts[4] == 2, "shuffle_teams preserves 2v2v2v2 balance across 8 participants")

	mod.call("set_team_format", 2) # FORMAT_SQUAD -> 2 big teams (4v4)
	expect(int(mod.get("team_count")) == 2, "8-player FORMAT_SQUAD activates 2 teams (4v4)")
	expect(int(mod.call("_seat_zone_team", 0, 8)) == 1 and int(mod.call("_seat_zone_team", 3, 8)) == 1, "_seat_zone_team maps front/row1 0..3 to Red in 8p FORMAT_SQUAD")
	expect(int(mod.call("_seat_zone_team", 4, 8)) == 2 and int(mod.call("_seat_zone_team", 7, 8)) == 2, "_seat_zone_team maps row2 4..7 to Blue in 8p FORMAT_SQUAD")
	var squad_counts := {1: 0, 2: 0}
	for pid_raw in [1, 2, 3, 4, 5, -1, -2, -3]:
		var tid: int = int(mod.call("get_team", pid_raw))
		squad_counts[tid] = int(squad_counts.get(tid, 0)) + 1
	expect(squad_counts[1] == 4 and squad_counts[2] == 4, "FORMAT_SQUAD balances 8 players as 4v4")

	# Clean back to 4 participants while staying in FORMAT_DUO -> must auto-recalculate 4 teams -> 2 teams (2v2)
	mod.call("set_team_format", 1)
	expect(int(mod.get("team_count")) == 4, "8-player FORMAT_DUO starts at 4 teams before shrink")
	for extra_nid in [3, 4, 5]:
		net.active_backend["connected_players"].erase(extra_nid)
	for b_idx in range(2, 4):
		bots.bots.erase(-b_idx)
	lobby.player_order_by_seat = {0: 1, 1: 2, 2: -1, 3: -1}
	mod._process(0.1)
	expect(int(mod.get("team_count")) == 2, "FORMAT_DUO auto-recalculates 4 -> 2 teams when room shrinks to 3 participants")

	# 5c. Chair click join, strict team cap & Smart Bot Swap
	# State now: seats={0:1(Red), 1:2(Red), 2:-1(Blue Bot), 3:empty(Blue zone)}, cap=2
	# Guest 2 clicks empty chair 3 (Blue zone) -> moves to seat 3 & joins Team 2 (Blue)
	var empty_join_ok: bool = bool(mod.call("click_lobby_chair", 3, 2))
	expect(empty_join_ok and int(mod.call("get_team", 2)) == 2, "Guest clicking empty Blue chair joins Blue team")
	expect(int(lobby.player_order_by_seat.get(3, -1)) == 2 and int(lobby.player_order_by_seat.get(1, 0)) == -1, "Empty chair click updates physical seat in player_order_by_seat")

	# Now put Host(1) + Guest2(2) on Red [cap=2], Bot(-1) + Guest3(3) on Blue -> Guest3 cannot force into full all-human Red team
	net.active_backend["connected_players"][3] = {"name": "Guest3"}
	mod.set("teams", {1: 1, 2: 1, -1: 2, 3: 2})
	var blocked_full: bool = bool(mod.call("_apply_team_join_or_swap", 3, 1, -1, 0))
	expect(not blocked_full and int(mod.call("get_team", 3)) == 2, "Fixed-cap FORMAT_DUO rejects joining a full all-human team")

	# Put Host(1) + Bot(-1) on Red [cap=2], Guest2(2) + Guest3(3) on Blue -> Guest2 joins full Red team by Smart Bot Swap with -1
	mod.set("teams", {1: 1, -1: 1, 2: 2, 3: 2})
	var bot_swap_ok: bool = bool(mod.call("_apply_team_join_or_swap", 2, 1, -1, -1))
	expect(bot_swap_ok and int(mod.call("get_team", 2)) == 1 and int(mod.call("get_team", -1)) == 2, "Smart Bot Swap puts human Guest2 on Red and Bot -1 onto Blue")

	# 5d. Host Grab-and-Drop (host_drop_chair): Human<->Human, Human->Empty, Human<->Bot
	bots.bots.clear()
	net.active_backend["connected_players"][4] = {"name": "Guest4"}
	lobby.player_order_by_seat = {0: 1, 1: 2, 2: 3, 3: 4}
	mod.set("teams", {1: 1, 2: 1, 3: 2, 4: 2})
	var hh_swap_ok: bool = bool(mod.call("host_drop_chair", 1, 2))
	expect(hh_swap_ok and int(mod.call("get_team", 2)) == 2 and int(mod.call("get_team", 3)) == 1, "host_drop_chair swaps teams between two humans")
	expect(int(lobby.player_order_by_seat.get(1, -1)) == 3 and int(lobby.player_order_by_seat.get(2, -1)) == 2, "host_drop_chair swaps physical seats between two humans")

	net.active_backend["connected_players"].erase(4)
	lobby.player_order_by_seat = {0: 1, 1: 3, 2: 2, 3: -1}
	mod.set("teams", {1: 1, 3: 1, 2: 2})
	var empty_drop_ok: bool = bool(mod.call("host_drop_chair", 1, 3))
	expect(empty_drop_ok and int(mod.call("get_team", 3)) == 2, "host_drop_chair moves human into empty Blue chair & changes team")
	expect(int(lobby.player_order_by_seat.get(3, -1)) == 3 and int(lobby.player_order_by_seat.get(1, 0)) == -1, "host_drop_chair vacates old chair when moving human to empty chair")

	bots.bots[-1] = 1
	lobby.player_order_by_seat = {0: 1, 1: 3, 2: -1, 3: 2}
	mod.set("teams", {1: 1, 3: 1, -1: 2, 2: 2})
	var hb_swap_ok: bool = bool(mod.call("host_drop_chair", 0, 2))
	expect(hb_swap_ok and int(mod.call("get_team", 1)) == 2 and int(mod.call("get_team", -1)) == 1, "host_drop_chair swaps human Host with Bot on target team")
	expect(int(lobby.player_order_by_seat.get(2, -1)) == 1 and int(lobby.player_order_by_seat.get(0, 0)) == -1, "host_drop_chair moves human onto Bot seat and frees old seat")

	net.active_backend["connected_players"].erase(3)
	lobby.player_order_by_seat = {0: 1, 1: 2, 2: -1, 3: -1}

	# 5e. Fixed chair team stances in an 8-seat lobby when removing/adding Bots + zero text badges
	var h_expand = lobby.lobby_handler
	for extra_s in range(4, 8):
		var es := Node3D.new()
		es.name = "Stand%d" % extra_s
		h_expand.add_child(es)
		h_expand.players.append(es)
		var el := Label3D.new()
		el.text = ""
		h_expand.add_child(el)
		h_expand.nametags.append(el)
		lobby.player_order_by_seat[extra_s] = -1
	bots.bots.clear()
	mod.call("set_team_format", 1) # 2/TEAM on 8 seats -> fixed 4 zones regardless of empty chairs
	expect(int(mod.get("team_count")) == 4, "FORMAT_DUO locks 4 fixed team zones across 8 chairs even with 2 players")
	# Move Guest 2 onto seat 4 (Green zone = team 3) while 0 bots exist
	var drop_green_ok: bool = bool(mod.call("host_drop_chair", 1, 4))
	expect(drop_green_ok and int(mod.call("get_team", 2)) == 3, "Dropping human onto empty seat 4 places them on fixed Green team")
	# Add Bot -1 (fills first open -1 seat = seat 1, Red zone = team 1) -> inherits Red without flipping seat 4 or team_count
	bots.bots[-1] = 1
	mod._process(0.05)
	expect(int(mod.get("team_count")) == 4 and int(mod.call("get_team", -1)) == 1 and int(mod.call("get_team", 2)) == 3, "Adding a Bot inherits its chair zone team without changing chair stances or moving seated humans")
	# Remove Bot -1 -> fixed 4 team zones & Guest 2 on Green remain unchanged, zero text badges created
	bots.bots.erase(-1)
	mod._process(0.05)
	expect(int(mod.get("team_count")) == 4 and int(mod.call("get_team", 2)) == 3, "Removing a Bot keeps fixed 4 team zones intact")
	expect(lobby.find_children("TeamChairBadge_*", "", true, false).is_empty(), "No floating TeamChairBadge_* text labels are created in lobby")

	# 5f. Skeleton-less fixture safely handles drag skeleton begin/apply/cancel/restore
	var f0_node: Node3D = lobby.lobby_handler.players[0] as Node3D
	mod.set("_drag_seat", 0)
	mod.set("_drag_active", true)
	mod.set("_drag_elapsed", 0.25)
	mod.call("_begin_drag_skeleton", f0_node)
	mod.call("_apply_drag_dangling_pose")
	mod.call("_cancel_lobby_drag")
	expect(int(mod.get("_drag_seat")) == -1 and not bool(mod.get("_drag_active")) and mod.get("_drag_skel") == null, "_cancel_lobby_drag and _restore_drag_skeleton exit cleanly on skeleton-less fixture")

	# 5g. Non-host chair interaction: clicking another human requests consent; clicking empty chair moves directly
	net.active_backend["connected_players"][3] = {"name": "Guest3"}
	lobby.player_order_by_seat = {0: 1, 1: -1, 2: 2, 3: 3, 4: -1, 5: -1, 6: -1, 7: -1}
	mod.call("set_team_format", 1) # Red: 0(1), 1(empty); Blue: 2(2), 3(3)
	# Test 1: Guest 2 clicks Host 1's chair (seat 0) -> creates pending swap request WITHOUT moving either player
	lobby.lobby_handler.last_message = ""
	var req_ok: bool = bool(mod.call("click_lobby_chair", 0, 2))
	var pending_d: Dictionary = mod.get("_pending_swap_requests") as Dictionary
	expect(req_ok and pending_d.has(1) and int((pending_d[1] as Dictionary).get("from_id", 0)) == 2, "Non-host clicking another human's chair sends swap request instead of force swapping")
	expect(int(mod.get("_incoming_swap_from")) == 2 and int(lobby.player_order_by_seat.get(0, -1)) == 1 and int(lobby.player_order_by_seat.get(2, -1)) == 2, "Pending swap request preserves seats & teams until target responds")
	expect(not lobby.lobby_handler.last_message.contains("SWAPPED SEATS"), "Pending swap request does not broadcast swap completion")
	# Test 2: Host 1 declines -> clears request, seats & teams stay unchanged
	lobby.lobby_handler.last_message = ""
	var dec_ok: bool = bool(mod.call("respond_swap_request", false, 1))
	expect(dec_ok and not (mod.get("_pending_swap_requests") as Dictionary).has(1) and int(mod.get("_incoming_swap_from")) == 0, "Declining swap request clears pending state")
	expect(int(mod.call("get_team", 1)) == 1 and int(mod.call("get_team", 2)) == 2 and int(lobby.player_order_by_seat.get(0, -1)) == 1, "Declined swap leaves seats and teams intact")
	expect(lobby.lobby_handler.last_message.is_empty(), "Declining swap notifies requester privately without room-wide terminal broadcast")
	# Test 3: Guest 2 requests again and Host 1 accepts -> swaps physical seats & teams cleanly & broadcasts completion
	mod.call("click_lobby_chair", 0, 2)
	lobby.lobby_handler.last_message = ""
	var acc_ok: bool = bool(mod.call("respond_swap_request", true, 1))
	expect(acc_ok and not (mod.get("_pending_swap_requests") as Dictionary).has(1), "Accepting swap request clears pending state and succeeds")
	expect(lobby.lobby_handler.last_message.contains("SWAPPED SEATS"), "Accepting swap broadcasts completion notice to lobby")
	expect(int(lobby.player_order_by_seat.get(0, -1)) == 2 and int(lobby.player_order_by_seat.get(2, -1)) == 1, "Accepted swap exchanges physical chairs between Guest 2 and Host 1")
	expect(int(mod.call("get_team", 2)) == 1 and int(mod.call("get_team", 1)) == 2, "Accepted swap exchanges team memberships")
	# Test 4: Mutual click between Guest 2 (now seat 0) and Guest 3 (seat 3) auto-completes without banner button
	mod.call("click_lobby_chair", 3, 2)
	lobby.lobby_handler.last_message = ""
	expect(int(lobby.player_order_by_seat.get(0, -1)) == 2 and int(lobby.player_order_by_seat.get(3, -1)) == 3, "First click in mutual pair waits for counterparty")
	var mut_ok: bool = bool(mod.call("click_lobby_chair", 0, 3))
	expect(mut_ok and lobby.lobby_handler.last_message.contains("SWAPPED SEATS"), "Mutual click completion broadcasts swap notice to lobby")
	expect(int(lobby.player_order_by_seat.get(0, -1)) == 3 and int(lobby.player_order_by_seat.get(3, -1)) == 2, "Counterparty clicking back completes swap immediately")
	expect(int(mod.call("get_team", 3)) == 1 and int(mod.call("get_team", 2)) == 2, "Mutual swap assigns target seat zone teams cleanly")
	# Test 5: Non-host Guest 2 clicks empty seat 5 (Green zone) -> moves directly without consent
	var empty_move_ok: bool = bool(mod.call("click_lobby_chair", 5, 2))
	expect(empty_move_ok and int(lobby.player_order_by_seat.get(5, -1)) == 2 and int(mod.call("get_team", 2)) == 3, "Non-host clicking empty chair moves directly without needing consent")
	# 5h. Team assignment never changes player/bot outfit customization
	(net.active_backend["connected_players"][2] as Dictionary)["customization"] = ["hard_hat", "", "purple"]
	mod.call("assign_player_team", 2, 1)
	mod._process(0.1)
	var kept_cust: Array = (net.active_backend["connected_players"][2] as Dictionary).get("customization", []) as Array
	expect(kept_cust.size() >= 3 and str(kept_cust[2]) == "purple", "Team assignment preserves player customization/suit color untouched")

	# 5i. Real-time host-to-client lobby drag sync (begin, pose stream + interpolation, drop end + bounce)
	mod.call("_apply_remote_drag_begin", 0, Vector3(1.0, 2.5, 6.0), 2)
	expect(bool(mod.get("_drag_active")) and bool(mod.get("_drag_is_remote")) and int(mod.get("_drag_seat")) == 0 and int(mod.get("_hovered_seat")) == 2, "_apply_remote_drag_begin enters remote drag state and sets target hover")
	var pre_vpos: Vector3 = mod.get("_drag_visual_pos") as Vector3
	mod.call("_apply_remote_drag_pose", 0, Vector3(2.4, 2.8, 6.0), 3)
	mod._process(0.05)
	var post_vpos: Vector3 = mod.get("_drag_visual_pos") as Vector3
	expect(int(mod.get("_hovered_seat")) == 3 and post_vpos.distance_to(Vector3(2.4, 2.8, 6.0)) < pre_vpos.distance_to(Vector3(2.4, 2.8, 6.0)), "_apply_remote_drag_pose updates hover seat and interpolates client visual position")
	mod.call("_apply_remote_drag_end", 0, [3, 0])
	var bdict: Dictionary = mod.get("_seat_drop_bounce") as Dictionary
	expect(not bool(mod.get("_drag_active")) and not bool(mod.get("_drag_is_remote")) and int(mod.get("_drag_seat")) == -1 and int(mod.get("_hovered_seat")) == -1, "_apply_remote_drag_end exits remote drag and clears hover")
	expect(bdict.has(3) and bdict.has(0), "_apply_remote_drag_end schedules landing bounce on affected seats")

	net.active_backend["connected_players"].erase(3)

	mod.call("set_team_format", 0)

	# Leave lobby (as vanilla does when transitioning into Game/Arena)
	lobby.free()

	# Re-enable 2 Teams and check _sync_teams mirrors mapping, format, and wins cleanly
	mod.call("_sync_teams", 2, {1: 1, 2: 1, 3: 2, 4: 2}, 4, {1: 2, 2: 1})
	expect(bool(mod.call("is_team_mode_active")) and bool(mod.call("are_teammates", 1, 2)), "_sync_teams mirrors team mapping")
	expect(int(mod.get("team_format")) == 4 and int((mod.get("_hud_wins") as Dictionary).get(1, 0)) == 2, "_sync_teams mirrors team_format and _hud_wins")
	mod.set("_hud_wins", {})

	# 6. In-game actors: nameplate tint + player-spotlight protection + MpmTeamBadge + shove filter
	Engine.set_meta(&"mpm_player_spotlight_active", true)
	var arena := Node3D.new()
	arena.name = "DiscoArena"
	root.add_child(arena)

	var actor_script := _make_actor_script()
	var spotlight_gold := Color(1.0, 0.90, 0.20, 1.0)

	var actor1: Node3D = actor_script.new()
	actor1.player_presence = {"network_id": 1}
	var l1 := Label3D.new()
	l1.text = "Host"
	l1.modulate = spotlight_gold
	actor1.add_child(l1)
	actor1.player_name_label = l1
	arena.add_child(actor1)
	mod._node_added(actor1)

	var actor2: Node3D = actor_script.new()
	actor2.player_presence = {"network_id": 2}
	var l2 := Label3D.new()
	l2.text = "Ally"
	actor2.add_child(l2)
	actor2.player_name_label = l2
	arena.add_child(actor2)
	mod._node_added(actor2)

	var actor3: Node3D = actor_script.new()
	actor3.player_presence = {"network_id": 3}
	var l3 := Label3D.new()
	l3.text = "" # simulates minigame hiding/clearing Label3D
	actor3.add_child(l3)
	actor3.player_name_label = l3
	arena.add_child(actor3)
	mod._node_added(actor3)

	await process_frame
	mod._process(4.0) # age past 3.5s intro window

	expect(l1.text.begins_with("[RED] "), "local actor keeps team prefix alongside spotlight")
	expect(l1.modulate.is_equal_approx(spotlight_gold), "player-spotlight local color is preserved on actor 1")
	expect(l2.text.begins_with("[RED] ") and l2.modulate.is_equal_approx(Color(red_col.r, red_col.g, red_col.b, 1.0)), "teammate actor colored red + tagged")
	var badge3: Label3D = actor3.get_node_or_null("MpmTeamBadge") as Label3D
	expect(badge3 != null and badge3.visible and badge3.text.contains("[BLU]"), "hidden/empty Label3D shows MpmTeamBadge past intro")
	var ring2 := actor2.get_node_or_null("MpmTeamRing") as MeshInstance3D
	expect(ring2 != null and ring2.visible, "tracked team actor gets glowing MpmTeamRing underfoot")

	actor1.players_in_shove_proximity = [actor2, actor3]
	mod._physics_process(0.016)
	expect(actor1.players_in_shove_proximity.size() == 1 and actor1.players_in_shove_proximity[0] == actor3, "players_in_shove_proximity removes teammate actor2 and keeps enemy actor3")

	# 7. Vanilla survival early team victory + Fall Guys Squads synchronized scoring
	var game := GameFixture.new()
	game.name = "Game"
	game.round_score_by_network_id = {1: 5, 2: 1, 3: 4, 4: 0}
	root.add_child(game)
	mod._node_added(game)

	var mg := MinigameFixture.new()
	mg.name = "DiscoMinigame"
	mg.active_players = {1: true, 2: true, 3: true, 4: true}
	game.add_child(mg)
	mod._node_added(mg)

	# Seed initial teams seen with all 4 alive, then eliminate team 2 (3 & 4)
	mod._process(0.05)
	mod._process(0.20)
	var hud_in_game = mod.get("_hud_panel") as Control
	expect(hud_in_game != null and hud_in_game.visible, "in-game top-right Team HUD becomes visible during active minigame")
	expect((hud_in_game as PanelContainer).get_theme_stylebox("panel") is StyleBoxEmpty, "in-game Team HUD panel uses frameless StyleBoxEmpty")
	expect(mod.get("_hud_rows") is HBoxContainer, "in-game Team HUD rows use single-line HBoxContainer")
	game.in_cutscene = true
	mod._process(0.20)
	expect(not hud_in_game.visible, "in-game Team HUD automatically hides during cutscenes/intermissions")
	game.in_cutscene = false
	mod._process(0.20)
	expect(hud_in_game.visible, "in-game Team HUD restores when returning from cutscene")
	mg.active_players = {1: true, 2: true}
	mg.dead_players = [3, 4]
	mod._process(0.05)
	expect(bool(mod.get("_early_win_triggered")), "early team victory triggered when only 1 team stays alive")

	await create_timer(1.15).timeout
	expect(mg.finished and mg.finish_called, "vanilla survival minigame finishes early")
	expect(int(game.round_score_by_network_id.get(1, -1)) == 6 and int(game.round_score_by_network_id.get(2, -1)) == 6, "winning team (1,2) gets best(5)+all_alive(1)=6 synchronized")
	expect(int(game.round_score_by_network_id.get(3, -1)) == 4 and int(game.round_score_by_network_id.get(4, -1)) == 4, "eliminated team (3,4) shares best(4)+0=4 synchronized")

	# 8. Asymmetric 3v2v2 Fall Guys Squads scoring check
	mod.call("_sync_teams", 3, {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3})
	var squad_scores: Dictionary = mod.call("compute_team_synchronized_scores", {
		1: 7, 2: 4, 3: 2, # Red 3 members, one out -> best 7 + 0 = 7
		4: 5, 5: 3,       # Blue 2 members, both alive -> best 5 + 1 = 6
		6: 1, 7: 0,       # Green 2 members, both out -> best 1 + 0 = 1
	}, [1, 2, 4, 5])
	expect(int(squad_scores[1]) == 7 and int(squad_scores[2]) == 7 and int(squad_scores[3]) == 7, "Red 3-stack shares 7")
	expect(int(squad_scores[4]) == 6 and int(squad_scores[5]) == 6, "Blue 2-stack all-alive shares 5+1=6")
	expect(int(squad_scores[6]) == 1 and int(squad_scores[7]) == 1, "Green 2-stack eliminated shares 1")

	# 9. Traditional Chinese ZHT locale tag + live player-spotlight F8 toggle compatibility
	TranslationServer.set_locale("ZHT")
	expect(str(mod.call("get_team_tag", 1)) == "[紅]", "ZHT locale returns Traditional Chinese tag [紅]")
	expect(str(mod.call("get_team_name", 1)) == "紅隊", "ZHT locale returns Traditional Chinese team name 紅隊")
	expect(bool(mod.call("_is_tw_locale", "zh_Hant_TW")), "zh_Hant_TW recognized as TW locale")
	expect(bool(mod.call("_is_cn_locale", "ZHS")), "ZHS recognized as CN locale")
	TranslationServer.set_locale("en")

	# Clean teardown (avoid leaked resources/nodes)
	if Engine.has_meta(&"mpm_player_spotlight_active"):
		Engine.remove_meta(&"mpm_player_spotlight_active")
	game.free()
	arena.free()
	mod._process(0.20)
	expect(hud_in_game == null or not is_instance_valid(hud_in_game) or not hud_in_game.visible, "in-game Team HUD hides once match/game exits")
	mod_loader.free()
	net.free()
	for uid_rel in [
		"res://main.gd.uid",
		"res://team_registry.gd.uid",
		"res://lobby_assignment.gd.uid",
		"res://lobby_ui.gd.uid",
		"res://lobby_drag_3d.gd.uid",
		"res://vanilla_ingame.gd.uid",
		"res://ingame_hud.gd.uid",
	]:
		if FileAccess.file_exists(uid_rel):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(uid_rel))

	if _failed:
		quit(1)
		return
	print("Team Party checks passed")
	quit(0)
