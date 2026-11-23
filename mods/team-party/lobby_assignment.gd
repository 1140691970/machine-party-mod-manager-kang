extends RefCounted

## Lobby team formats, seat resolution, balanced/shuffled assignment, smart bot swap, and consent swap requests.

var tp: Node


func _init(owner: Node) -> void:
	tp = owner


func network():
	if tp.get_tree() == null or tp.get_tree().root == null:
		return null
	return tp.get_tree().root.get_node_or_null("NetworkManager")


func local_peer_id() -> int:
	var mp = tp.multiplayer
	if mp != null and mp.has_multiplayer_peer():
		return mp.get_unique_id()
	return 1


func is_host_authoritative() -> bool:
	var mp = tp.multiplayer
	if mp == null or not mp.has_multiplayer_peer():
		return true
	return mp.is_server()


func lobby_bots_mod() -> Node:
	if tp.get_tree() == null or tp.get_tree().root == null:
		return null
	return tp.get_tree().root.get_node_or_null("ModLoader/lobby-bots")


func has_any_remote_peers() -> bool:
	var mp = tp.multiplayer
	return mp != null and mp.has_multiplayer_peer() and not mp.get_peers().is_empty()


func peer_connected(id: int) -> void:
	var mp = tp.multiplayer
	if mp != null and mp.has_multiplayer_peer() and mp.is_server():
		tp.rpc_id(id, &"_sync_teams", tp.team_count, tp.teams.duplicate(), tp.team_format, tp._hud_wins.duplicate())


func broadcast_teams() -> void:
	var mp = tp.multiplayer
	if mp != null and mp.has_multiplayer_peer() and mp.is_server():
		tp.rpc(&"_sync_teams", tp.team_count, tp.teams.duplicate(), tp.team_format, tp._hud_wins.duplicate())


func can_host_edit() -> bool:
	if not is_instance_valid(tp.lobby) or tp.locked:
		return false
	var mp = tp.multiplayer
	if mp != null and mp.has_multiplayer_peer() and not mp.is_server():
		return false
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")):
		return false
	if bool(tp.lobby.get("loading")):
		return false
	return true


func can_guest_pick_self() -> bool:
	if not is_instance_valid(tp.lobby) or tp.locked or tp.team_count < 2:
		return false
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")):
		return false
	if bool(tp.lobby.get("loading")):
		return false
	return true


func collect_lobby_participants() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var net = network()
	if net != null and net.get("active_backend") != null:
		var backend = net.active_backend
		var connected = backend.get("connected_players")
		if connected is Dictionary:
			var peer_ids: Array = (connected as Dictionary).keys()
			peer_ids.sort()
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

	if is_instance_valid(tp.lobby):
		var seat_map = tp.lobby.get("player_order_by_seat")
		if seat_map is Dictionary:
			var seat_keys: Array = (seat_map as Dictionary).keys()
			seat_keys.sort()
			for sk in seat_keys:
				var pid: int = int((seat_map as Dictionary)[sk])
				if pid > 0 and not seen.has(pid):
					seen[pid] = true
					entries.append({"id": pid, "name": "Player %d" % pid, "is_bot": false})

	var bot_mod: Node = lobby_bots_mod()
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


func lobby_total_seats() -> int:
	if not is_instance_valid(tp.lobby):
		return 0
	var count: int = 0
	var handler = tp.lobby.get("lobby_handler")
	if handler != null and (handler.get("players") is Array):
		count = (handler.get("players") as Array).size()
	var seat_map = tp.lobby.get("player_order_by_seat")
	if seat_map is Dictionary:
		count = maxi(count, (seat_map as Dictionary).size())
	return count


func reconcile_lobby_teams(participants: Array[Dictionary]) -> bool:
	if tp.team_count < 2 or tp.locked or not is_host_authoritative():
		return false
	if tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO] and participants.size() >= 2:
		var desired_teams: int = tp._reg.calc_format_team_count(tp.team_format, participants.size(), lobby_total_seats())
		if desired_teams >= 2 and desired_teams != tp.team_count:
			tp.team_count = desired_teams
			assign_balanced_order(participants, false)
			return true
	var valid_ids: Dictionary = {}
	for p in participants:
		valid_ids[int(p["id"])] = true
	var changed: bool = false
	for raw_id in tp.teams.keys():
		var nid: int = int(raw_id)
		if not valid_ids.has(nid):
			tp.teams.erase(raw_id)
			changed = true
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = seats.size()
	for p in participants:
		var nid: int = int(p["id"])
		var cur: int = int(tp.teams.get(nid, 0))
		if cur < 1 or cur > tp.team_count:
			var picked: int = 0
			if tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO] and total_seats > 0:
				var sidx: int = seats.find(nid)
				if sidx >= 0:
					picked = tp._reg.seat_zone_team(sidx, total_seats)
			if picked < 1 or picked > tp.team_count:
				picked = tp._reg.smallest_team(nid)
			tp.teams[nid] = picked
			changed = true
	return changed


func is_bot_id(nid: int) -> bool:
	if nid == 0:
		return false
	var bot_mod: Node = lobby_bots_mod()
	if bot_mod != null and (bot_mod.get("bots") is Dictionary):
		if (bot_mod.get("bots") as Dictionary).has(nid):
			return true
	return nid < 0


func resolved_lobby_seats() -> Dictionary:
	var seats: Array = []
	var seat_count: int = 0
	if not is_instance_valid(tp.lobby):
		return {"seats": seats, "count": 0}
	var handler = tp.lobby.get("lobby_handler")
	if handler != null and (handler.get("players") is Array):
		seat_count = (handler.get("players") as Array).size()
	var seat_map = tp.lobby.get("player_order_by_seat")
	var bot_mod: Node = lobby_bots_mod()
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
			seats.append(0)
	return {"seats": seats, "count": total}


func team_members_list(tid: int, participants: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in participants:
		if tp._reg.get_team(int(p["id"])) == tid:
			out.append(p)
	return out


func lock_for_game() -> void:
	if is_host_authoritative() and not tp.locked:
		tp._drag.cancel_lobby_drag()
		tp._pending_swap_requests.clear()
		tp._incoming_swap_from = 0
		if tp.team_count >= 2:
			var participants: Array[Dictionary] = collect_lobby_participants()
			reconcile_lobby_teams(participants)
			tp._drag.update_lobby_nametags()
			broadcast_teams()
		tp.locked = true
		tp._hovered_seat = -1
		tp._reg.publish_state()


func reset_lobby_state() -> void:
	tp._drag.cancel_lobby_drag()
	tp._pending_swap_requests.clear()
	tp._incoming_swap_from = 0
	tp.locked = false
	tp._hovered_seat = -1
	tp._last_roster_sig = ""
	tp._reg.publish_state()
	tp._drag.update_lobby_nametags()


func set_team_format(new_fmt: int) -> void:
	if not can_host_edit():
		return
	var participants: Array[Dictionary] = collect_lobby_participants()
	if new_fmt == tp.FORMAT_FFA:
		tp._pending_swap_requests.clear()
		tp._incoming_swap_from = 0
		tp.team_format = tp.FORMAT_FFA
		set_team_mode(0)
		tp._drag.sync_lobby_camera_angle()
		tp._ui.notify_lobby_terminal(tp._reg.label("MODE: FREE-FOR-ALL", "模式：各自为战", "模式：各自為戰"))
		return
	tp.team_format = new_fmt
	tp.team_count = tp._reg.calc_format_team_count(new_fmt, participants.size(), lobby_total_seats())
	assign_balanced_order(participants, false)
	tp._drag.sync_lobby_camera_angle()
	tp._reg.publish_state()
	broadcast_teams()
	tp._ui.refresh_lobby_ui()
	tp._drag.update_lobby_nametags()
	tp._ui.notify_lobby_terminal(tp._ui.format_summary_text(participants.size()))


func sync_bots_to_seat_zones() -> void:
	if not (tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]) or tp.team_count < 2:
		return
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total: int = seats.size()
	for s in range(total):
		var nid: int = int(seats[s])
		if nid != 0 and is_bot_id(nid):
			var z: int = tp._reg.seat_zone_team(s, total)
			if z >= 1 and z <= tp.team_count:
				tp.teams[nid] = z


func _commit_lobby_seat_map(sm: Dictionary) -> void:
	var mp = tp.multiplayer
	if mp != null and mp.has_multiplayer_peer() and mp.is_server() and tp.lobby.has_method("player_list_updated_rpc"):
		tp.lobby.rpc("player_list_updated_rpc", sm)
	elif tp.lobby.has_method("update_player_list"):
		tp.lobby.call("update_player_list")


func arrange_seats_for_teams(participants: Array[Dictionary]) -> bool:
	if not is_instance_valid(tp.lobby) or tp.team_count < 2:
		return false
	var seat_map = tp.lobby.get("player_order_by_seat")
	if not (seat_map is Dictionary):
		return false
	var sm: Dictionary = seat_map as Dictionary
	var total_seats: int = maxi(lobby_total_seats(), sm.size())
	if total_seats < participants.size():
		return false
	var used_seats: Dictionary = {}
	for k in sm.keys():
		sm[k] = -1
	for p in participants:
		var nid: int = int(p["id"])
		if nid <= 0:
			continue
		var want_t: int = tp._reg.get_team(nid)
		var picked_s: int = -1
		for s in range(total_seats):
			if not used_seats.has(s) and tp._reg.seat_zone_team(s, total_seats) == want_t:
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
	_commit_lobby_seat_map(sm)
	return true


func assign_balanced_order(participants: Array[Dictionary], do_shuffle: bool) -> void:
	if tp.team_count < 2:
		return
	var ids: Array[int] = []
	for p in participants:
		ids.append(int(p["id"]))
	if do_shuffle:
		for i in range(ids.size() - 1, 0, -1):
			var j: int = tp._rng.randi_range(0, i)
			var tmp: int = ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
	tp.teams.clear()
	if not do_shuffle and (tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]):
		var resolved := resolved_lobby_seats()
		var seats: Array = resolved["seats"]
		var total_seats: int = seats.size()
		if total_seats > 0:
			for nid in ids:
				var sidx: int = seats.find(nid)
				if sidx >= 0:
					var zt: int = tp._reg.seat_zone_team(sidx, total_seats)
					if zt >= 1 and zt <= tp.team_count:
						tp.teams[nid] = zt
		for nid in ids:
			if not tp.teams.has(nid):
				tp.teams[nid] = tp._reg.smallest_team(nid)
	else:
		for i in range(ids.size()):
			tp.teams[ids[i]] = (i % tp.team_count) + 1
		if do_shuffle and (tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]):
			if arrange_seats_for_teams(participants):
				sync_bots_to_seat_zones()


func cycle_team_mode() -> void:
	if not can_host_edit():
		return
	var next_count: int = 0
	match tp.team_count:
		0: next_count = 2
		2: next_count = 3
		3: next_count = 4
		_: next_count = 0
	set_team_mode(next_count)


func set_team_mode(new_count: int) -> void:
	if not can_host_edit():
		return
	if not (new_count in [0, 2, 3, 4]):
		return
	tp.team_count = new_count
	if tp.team_count == 0:
		tp.team_format = tp.FORMAT_FFA
		tp.teams.clear()
	else:
		if tp.team_format == tp.FORMAT_FFA:
			tp.team_format = tp.FORMAT_CUSTOM
		var participants: Array[Dictionary] = collect_lobby_participants()
		for raw_id in tp.teams.keys():
			var t: int = int(tp.teams[raw_id])
			if t < 1 or t > tp.team_count:
				tp.teams.erase(raw_id)
		reconcile_lobby_teams(participants)
	tp._drag.sync_lobby_camera_angle()
	tp._reg.publish_state()
	broadcast_teams()
	tp._ui.refresh_lobby_ui()
	tp._drag.update_lobby_nametags()


func shuffle_teams() -> void:
	if not can_host_edit():
		return
	var participants: Array[Dictionary] = collect_lobby_participants()
	if participants.is_empty():
		return
	if tp.team_count < 2:
		tp.team_format = tp.FORMAT_DUO
		tp.team_count = tp._reg.calc_format_team_count(tp.FORMAT_DUO, participants.size(), lobby_total_seats())
	elif tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]:
		tp.team_count = tp._reg.calc_format_team_count(tp.team_format, participants.size(), lobby_total_seats())
	assign_balanced_order(participants, true)
	tp._drag.sync_lobby_camera_angle()
	tp._reg.publish_state()
	broadcast_teams()
	tp._ui.refresh_lobby_ui()
	tp._drag.update_lobby_nametags()
	var summary: String = tp._ui.format_summary_text(participants.size())
	tp._ui.notify_lobby_terminal(tp._reg.label(
		"SHUFFLED: %s" % summary,
		"已随机洗牌分队：%s" % summary,
		"已隨機洗牌分隊：%s" % summary
	))


func move_human_seat(actor_id: int, target_seat: int) -> void:
	if not is_instance_valid(tp.lobby) or actor_id <= 0 or target_seat < 0:
		return
	var seat_map = tp.lobby.get("player_order_by_seat")
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
	_commit_lobby_seat_map(sm)


func apply_team_join_or_swap(actor_id: int, desired_team: int, target_seat: int = -1, prefer_bot_id: int = 0) -> bool:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2:
		return false
	if actor_id == 0 or desired_team < 1 or desired_team > tp.team_count:
		return false
	var participants: Array[Dictionary] = collect_lobby_participants()
	var old_team: int = tp._reg.get_team(actor_id)
	if old_team == desired_team:
		if target_seat >= 0 and actor_id > 0:
			var resolved := resolved_lobby_seats()
			var seats: Array = resolved["seats"]
			if target_seat < seats.size() and int(seats[target_seat]) == 0:
				move_human_seat(actor_id, target_seat)
				sync_bots_to_seat_zones()
				tp._ui.refresh_lobby_ui()
				tp._drag.update_lobby_nametags()
				return true
		return false

	var cap: int = tp._reg.team_capacity()
	var target_members: Array[Dictionary] = team_members_list(desired_team, participants)
	var seat_occupied_by_human: bool = false
	if target_seat >= 0 and is_instance_valid(tp.lobby) and (tp.lobby.get("player_order_by_seat") is Dictionary):
		var sm: Dictionary = tp.lobby.get("player_order_by_seat") as Dictionary
		if sm.has(target_seat) and int(sm[target_seat]) > 0:
			seat_occupied_by_human = true

	if cap <= 0 or target_members.size() < cap:
		tp.teams[actor_id] = desired_team
		if target_seat >= 0 and actor_id > 0 and not seat_occupied_by_human:
			move_human_seat(actor_id, target_seat)
			sync_bots_to_seat_zones()
		tp._reg.publish_state()
		broadcast_teams()
		tp._ui.refresh_lobby_ui()
		tp._drag.update_lobby_nametags()
		return true

	# Fixed-cap format is full: allow Smart Bot Swap when at least one Bot sits on desired_team.
	var swap_bot: int = 0
	if prefer_bot_id != 0 and is_bot_id(prefer_bot_id) and tp._reg.get_team(prefer_bot_id) == desired_team:
		swap_bot = prefer_bot_id
	else:
		for m in target_members:
			if bool(m.get("is_bot", false)) or is_bot_id(int(m["id"])):
				swap_bot = int(m["id"])
				break
	if swap_bot != 0:
		var fallback_team: int = old_team if old_team >= 1 else tp._reg.smallest_team(actor_id)
		tp.teams[actor_id] = desired_team
		tp.teams[swap_bot] = fallback_team
		if target_seat >= 0 and actor_id > 0 and not seat_occupied_by_human:
			move_human_seat(actor_id, target_seat)
			sync_bots_to_seat_zones()
		tp._reg.publish_state()
		broadcast_teams()
		tp._ui.refresh_lobby_ui()
		tp._drag.update_lobby_nametags()
		return true
	return false


func assign_player_team(target_id: int, desired_team: int) -> void:
	if tp.team_count < 2 or tp.locked:
		return
	if desired_team < 1 or desired_team > tp.team_count:
		return
	var local_id: int = local_peer_id()
	if is_host_authoritative():
		tp.teams[target_id] = desired_team
		tp._reg.publish_state()
		broadcast_teams()
		tp._ui.refresh_lobby_ui()
		tp._drag.update_lobby_nametags()
	elif target_id == local_id and tp.multiplayer != null and tp.multiplayer.has_multiplayer_peer():
		tp.rpc_id(1, &"_rpc_request_change_team", desired_team)


func next_available_team_for(target_id: int) -> int:
	if tp.team_count < 2:
		return 0
	var cur: int = tp._reg.get_team(target_id)
	var cap: int = tp._reg.team_capacity()
	var participants: Array[Dictionary] = collect_lobby_participants()
	for step in range(1, tp.team_count + 1):
		var cand: int = ((cur - 1 + step) % tp.team_count) + 1 if cur >= 1 else step
		if cand == cur:
			continue
		if cap <= 0:
			return cand
		var members: Array[Dictionary] = team_members_list(cand, participants)
		if members.size() < cap:
			return cand
		for m in members:
			if bool(m.get("is_bot", false)) or is_bot_id(int(m["id"])):
				return cand
	return 0


func cycle_participant_team(target_id: int) -> void:
	if tp.team_count < 2 or tp.locked:
		return
	var local_id: int = local_peer_id()
	if not is_host_authoritative() and target_id != local_id:
		return
	tp._ui.play_ui_click()
	if is_host_authoritative():
		if tp._reg.team_capacity() <= 0:
			var cur: int = tp._reg.get_team(target_id)
			var next_t: int = (cur % tp.team_count) + 1 if cur >= 1 else 1
			assign_player_team(target_id, next_t)
		else:
			var next_avail: int = next_available_team_for(target_id)
			if next_avail > 0:
				apply_team_join_or_swap(target_id, next_avail, -1, 0)
			else:
				tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
	elif tp.multiplayer != null and tp.multiplayer.has_multiplayer_peer():
		var cur_g: int = tp._reg.get_team(target_id)
		var next_g: int = (cur_g % tp.team_count) + 1 if cur_g >= 1 else 1
		tp.rpc_id(1, &"_rpc_request_change_team", next_g)


func click_lobby_chair(seat: int, acting_peer_id: int = 0) -> bool:
	if not tp._reg.is_team_mode_active() or tp.locked or not is_instance_valid(tp.lobby):
		return false
	var handler = tp.lobby.get("lobby_handler")
	if handler != null and (not bool(handler.get("active")) or bool(tp.lobby.get("loading"))):
		return false
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if seat < 0 or seat >= seats.size():
		return false

	var caller_id: int = acting_peer_id if acting_peer_id != 0 else local_peer_id()
	var occ_id: int = int(seats[seat])
	var occ_is_bot: bool = is_bot_id(occ_id)
	var is_empty: bool = (occ_id == 0)
	var zone_tid: int = tp._reg.seat_zone_team(seat, seats.size())
	var is_host: bool = is_host_authoritative() and (acting_peer_id == 0 or acting_peer_id == 1)

	var desired_team: int = zone_tid
	var actor_to_move: int = caller_id
	var target_seat: int = -1
	var prefer_bot: int = 0

	if is_empty:
		if desired_team <= 0:
			desired_team = next_available_team_for(caller_id)
			if desired_team <= 0:
				var cur_t: int = tp._reg.get_team(caller_id)
				desired_team = (cur_t % tp.team_count) + 1 if cur_t >= 1 else 1
		target_seat = seat
	elif occ_id == caller_id:
		var next_t: int = next_available_team_for(caller_id)
		if next_t <= 0:
			tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
			return false
		desired_team = next_t
	elif occ_is_bot:
		var bot_team: int = tp._reg.get_team(occ_id)
		desired_team = bot_team if bot_team > 0 else zone_tid
		if is_host and desired_team == tp._reg.get_team(caller_id):
			actor_to_move = occ_id
			desired_team = next_available_team_for(occ_id)
			if desired_team <= 0:
				tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
				return false
		else:
			prefer_bot = occ_id
			target_seat = seat
	else:
		if is_host:
			var next_h: int = next_available_team_for(occ_id)
			if next_h <= 0:
				tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
				return false
			actor_to_move = occ_id
			desired_team = next_h
		else:
			if occ_id == caller_id:
				return false
			tp._ui.play_ui_click()
			if is_host_authoritative():
				return create_or_complete_swap_request(caller_id, occ_id)
			elif tp.multiplayer != null and tp.multiplayer.has_multiplayer_peer():
				tp.rpc_id(1, &"_rpc_request_chair_action", seat, tp._reg.get_team(occ_id))
				return true
			return false

	tp._ui.play_ui_click()
	if is_host_authoritative():
		var ok: bool = apply_team_join_or_swap(actor_to_move, desired_team, target_seat, prefer_bot)
		if ok and target_seat >= 0:
			tp._seat_drop_bounce[target_seat] = 0.22
		if not ok and desired_team != tp._reg.get_team(actor_to_move):
			tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
		return ok
	elif tp.multiplayer != null and tp.multiplayer.has_multiplayer_peer():
		tp.rpc_id(1, &"_rpc_request_chair_action", seat, desired_team)
		return true
	return false


func swap_lobby_seats(from_seat: int, from_id: int, to_seat: int, to_id: int) -> void:
	if not is_instance_valid(tp.lobby):
		return
	var seat_map = tp.lobby.get("player_order_by_seat")
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
	_commit_lobby_seat_map(sm)


func host_drop_chair(from_seat: int, to_seat: int) -> bool:
	if not is_host_authoritative() or not tp._reg.is_team_mode_active() or tp.locked or not is_instance_valid(tp.lobby):
		return false
	if from_seat < 0 or to_seat < 0 or from_seat == to_seat:
		return false
	var handler = tp.lobby.get("lobby_handler")
	if handler != null and (not bool(handler.get("active")) or bool(tp.lobby.get("loading"))):
		return false
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if from_seat >= seats.size() or to_seat >= seats.size():
		return false

	var from_id: int = int(seats[from_seat])
	var to_id: int = int(seats[to_seat])
	if from_id == 0:
		return false

	if to_id != 0:
		var t_from: int = tp._reg.get_team(from_id)
		var t_to: int = tp._reg.get_team(to_id)
		if tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]:
			var z_to: int = tp._reg.seat_zone_team(to_seat, seats.size())
			var z_from: int = tp._reg.seat_zone_team(from_seat, seats.size())
			if z_to > 0:
				tp.teams[from_id] = z_to
			if z_from > 0:
				tp.teams[to_id] = z_from
		elif t_from > 0 and t_to > 0:
			tp.teams[from_id] = t_to
			tp.teams[to_id] = t_from
		swap_lobby_seats(from_seat, from_id, to_seat, to_id)
		if (from_id > 0 and is_bot_id(to_id)) or (is_bot_id(from_id) and to_id > 0):
			sync_bots_to_seat_zones()
		tp._seat_drop_bounce[to_seat] = 0.24
		tp._seat_drop_bounce[from_seat] = 0.24
		tp._reg.publish_state()
		broadcast_teams()
		tp._ui.refresh_lobby_ui()
		tp._drag.update_lobby_nametags()
		tp._ui.play_ui_click()
		broadcast_terminal_notice(swap_completed_notice(from_id, to_id))
		return true

	var zone_tid: int = tp._reg.seat_zone_team(to_seat, seats.size())
	var desired_team: int = zone_tid if zone_tid > 0 else tp._reg.get_team(from_id)
	if desired_team < 1 or desired_team > tp.team_count:
		desired_team = 1
	var ok: bool = apply_team_join_or_swap(from_id, desired_team, to_seat, 0)
	if ok:
		tp._seat_drop_bounce[to_seat] = 0.24
		tp._ui.play_ui_click()
	else:
		tp._ui.notify_lobby_terminal(tp._reg.label("TEAM FULL", "队伍已满", "隊伍已滿"))
	return ok


func handle_rpc_request_change_team(desired_team: int) -> void:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2:
		return
	var sender: int = tp.multiplayer.get_remote_sender_id() if tp.multiplayer != null else 0
	if sender <= 0:
		return
	if desired_team < 1 or desired_team > tp.team_count:
		return
	apply_team_join_or_swap(sender, desired_team, -1, 0)


func handle_rpc_request_chair_action(target_seat: int, desired_team: int) -> void:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2:
		return
	var sender: int = tp.multiplayer.get_remote_sender_id() if tp.multiplayer != null else 0
	if sender <= 0:
		return
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	if target_seat < 0 or target_seat >= seats.size():
		return
	var occ_id: int = int(seats[target_seat])
	var zone_tid: int = tp._reg.seat_zone_team(target_seat, seats.size())
	var target_team: int = desired_team
	var seat_arg: int = -1
	var prefer_bot: int = 0
	if occ_id == 0:
		target_team = zone_tid if zone_tid > 0 else desired_team
		seat_arg = target_seat
	elif is_bot_id(occ_id):
		var bt: int = tp._reg.get_team(occ_id)
		target_team = bt if bt > 0 else desired_team
		prefer_bot = occ_id
		seat_arg = target_seat
	elif occ_id != sender:
		create_or_complete_swap_request(sender, occ_id)
		return
	if target_team < 1 or target_team > tp.team_count:
		return
	apply_team_join_or_swap(sender, target_team, seat_arg, prefer_bot)


func participant_display_name(nid: int) -> String:
	for p in collect_lobby_participants():
		if int(p["id"]) == nid:
			return tp._reg.strip_team_prefix(str(p.get("name", "Player %d" % nid)))
	return "Player %d" % nid


func clear_swap_requests_for(peer_id: int) -> void:
	tp._pending_swap_requests.erase(peer_id)
	var erase_keys: Array = []
	for k in tp._pending_swap_requests.keys():
		var req = tp._pending_swap_requests[k]
		if req is Dictionary and int((req as Dictionary).get("from_id", 0)) == peer_id:
			erase_keys.append(k)
	for ek in erase_keys:
		tp._pending_swap_requests.erase(ek)
	if tp._incoming_swap_from == peer_id:
		tp._incoming_swap_from = 0
		tp._incoming_swap_name = ""
		tp._incoming_swap_expires = 0.0


func has_connected_remote_peer(peer_id: int) -> bool:
	var mp = tp.multiplayer
	if peer_id <= 0 or mp == null or not mp.has_multiplayer_peer():
		return false
	return peer_id in mp.get_peers()


func deliver_swap_offer(target_id: int, from_id: int) -> void:
	var from_name: String = participant_display_name(from_id)
	if target_id == local_peer_id():
		tp._incoming_swap_from = from_id
		tp._incoming_swap_name = from_name
		tp._incoming_swap_expires = tp._anim_time + 12.0
		tp._ui.refresh_lobby_ui()
	elif has_connected_remote_peer(target_id):
		tp.rpc_id(target_id, &"_rpc_receive_swap_offer", from_id, from_name)


func deliver_terminal_notice(peer_id: int, msg: String) -> void:
	if peer_id == local_peer_id():
		tp._ui.notify_lobby_terminal(msg)
	elif has_connected_remote_peer(peer_id):
		tp.rpc_id(peer_id, &"_rpc_notify_terminal", msg)


func broadcast_terminal_notice(msg: String) -> void:
	tp._ui.notify_lobby_terminal(msg)
	if is_host_authoritative() and has_any_remote_peers():
		tp.rpc(&"_rpc_notify_terminal", msg)


func swap_completed_notice(id_a: int, id_b: int) -> String:
	var na: String = participant_display_name(id_a)
	var nb: String = participant_display_name(id_b)
	return tp._reg.label(
		"%s ⇄ %s SWAPPED SEATS" % [na, nb],
		"%s 与 %s 已互换座位" % [na, nb],
		"%s 與 %s 已互換座位" % [na, nb]
	)


func execute_human_seat_swap(id_a: int, id_b: int) -> bool:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2 or not is_instance_valid(tp.lobby):
		return false
	if id_a <= 0 or id_b <= 0 or id_a == id_b:
		return false
	var resolved := resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var seat_a: int = seats.find(id_a)
	var seat_b: int = seats.find(id_b)
	if seat_a < 0 or seat_b < 0 or seat_a == seat_b:
		return false
	var t_a: int = tp._reg.get_team(id_a)
	var t_b: int = tp._reg.get_team(id_b)
	if tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO]:
		var z_a: int = tp._reg.seat_zone_team(seat_a, seats.size())
		var z_b: int = tp._reg.seat_zone_team(seat_b, seats.size())
		if z_b > 0:
			tp.teams[id_a] = z_b
		if z_a > 0:
			tp.teams[id_b] = z_a
	elif t_a > 0 and t_b > 0:
		tp.teams[id_a] = t_b
		tp.teams[id_b] = t_a
	swap_lobby_seats(seat_a, id_a, seat_b, id_b)
	tp._seat_drop_bounce[seat_a] = 0.24
	tp._seat_drop_bounce[seat_b] = 0.24
	tp._drag.broadcast_drag_end(-1, [seat_a, seat_b])
	tp._reg.publish_state()
	broadcast_teams()
	tp._ui.refresh_lobby_ui()
	tp._drag.update_lobby_nametags()
	tp._ui.play_ui_click()
	return true


func create_or_complete_swap_request(from_id: int, target_id: int) -> bool:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2:
		return false
	if from_id <= 0 or target_id <= 0 or from_id == target_id:
		return false
	if tp._pending_swap_requests.has(from_id):
		var rev = tp._pending_swap_requests[from_id]
		if rev is Dictionary and int((rev as Dictionary).get("from_id", 0)) == target_id:
			clear_swap_requests_for(from_id)
			clear_swap_requests_for(target_id)
			var ok_mut: bool = execute_human_seat_swap(from_id, target_id)
			if ok_mut:
				broadcast_terminal_notice(swap_completed_notice(from_id, target_id))
			return ok_mut
	tp._pending_swap_requests[target_id] = {"from_id": from_id, "expires_at": tp._anim_time + 12.0}
	deliver_swap_offer(target_id, from_id)
	var tname: String = participant_display_name(target_id)
	deliver_terminal_notice(from_id, tp._reg.label(
		"SWAP REQUEST SENT TO %s" % tname,
		"已向 %s 发出换位请求" % tname,
		"已向 %s 發出換位請求" % tname
	))
	return true


func respond_swap_request(accepted: bool, responding_peer_id: int = 0) -> bool:
	var responder: int = responding_peer_id if responding_peer_id != 0 else local_peer_id()
	if is_host_authoritative():
		if not tp._pending_swap_requests.has(responder):
			if responder == local_peer_id() and tp._incoming_swap_from != 0:
				tp._incoming_swap_from = 0
				tp._incoming_swap_name = ""
				tp._incoming_swap_expires = 0.0
				tp._ui.refresh_lobby_ui()
			return false
		var req: Dictionary = tp._pending_swap_requests[responder] as Dictionary
		var from_id: int = int(req.get("from_id", 0))
		tp._pending_swap_requests.erase(responder)
		if responder == local_peer_id() and tp._incoming_swap_from == from_id:
			tp._incoming_swap_from = 0
			tp._incoming_swap_name = ""
			tp._incoming_swap_expires = 0.0
		if accepted:
			var swapped: bool = execute_human_seat_swap(from_id, responder)
			if swapped:
				broadcast_terminal_notice(swap_completed_notice(from_id, responder))
			tp._ui.refresh_lobby_ui()
			return swapped
		else:
			var rname: String = participant_display_name(responder)
			deliver_terminal_notice(from_id, tp._reg.label(
				"%s DECLINED SWAP" % rname,
				"%s 已拒绝换位" % rname,
				"%s 已拒絕換位" % rname
			))
			tp._ui.refresh_lobby_ui()
			return true
	elif tp.multiplayer != null and tp.multiplayer.has_multiplayer_peer() and tp._incoming_swap_from > 0:
		var offer_from: int = tp._incoming_swap_from
		tp._incoming_swap_from = 0
		tp._incoming_swap_name = ""
		tp._incoming_swap_expires = 0.0
		tp.rpc_id(1, &"_rpc_respond_swap", offer_from, accepted)
		tp._ui.refresh_lobby_ui()
		return true
	return false


func handle_rpc_respond_swap(from_id: int, accepted: bool) -> void:
	if not is_host_authoritative() or tp.locked or tp.team_count < 2:
		return
	var sender: int = tp.multiplayer.get_remote_sender_id() if tp.multiplayer != null else 0
	if sender <= 0 or not tp._pending_swap_requests.has(sender):
		return
	var req = tp._pending_swap_requests[sender]
	if req is Dictionary and int((req as Dictionary).get("from_id", 0)) == from_id:
		respond_swap_request(accepted, sender)


func apply_receive_swap_offer(from_id: int, from_name: String) -> void:
	tp._incoming_swap_from = from_id
	tp._incoming_swap_name = from_name
	tp._incoming_swap_expires = tp._anim_time + 12.0
	tp._ui.refresh_lobby_ui()


func apply_sync_teams(count: int, mapping: Dictionary, fmt: int = -1, wins: Dictionary = {}) -> void:
	tp.team_count = count
	if fmt >= 0:
		tp.team_format = fmt
	elif tp.team_count == 0:
		tp.team_format = tp.FORMAT_FFA
	elif tp.team_format == tp.FORMAT_FFA:
		tp.team_format = tp.FORMAT_CUSTOM
	tp.teams.clear()
	for k in mapping.keys():
		tp.teams[int(k)] = int(mapping[k])
	if count == 0:
		if tp._drag_is_remote:
			tp._drag.cancel_lobby_drag()
		tp._hud_wins.clear()
		tp._pending_swap_requests.clear()
		tp._incoming_swap_from = 0
		tp._incoming_swap_name = ""
		tp._incoming_swap_expires = 0.0
	elif not wins.is_empty():
		tp._hud_wins.clear()
		for wk in wins.keys():
			tp._hud_wins[int(wk)] = int(wins[wk])
	tp._reg.publish_state()
	tp._ui.refresh_lobby_ui()
	tp._drag.update_lobby_nametags()
	tp._hud.refresh_hud(true)
