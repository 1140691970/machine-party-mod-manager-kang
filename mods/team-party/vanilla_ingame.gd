extends RefCounted

## Official/vanilla minigame lifecycle hooks, early team victory, 3D badges/rings, and shove filtering.

var tp: Node


class _DiscoBrainTeamWrapper:
	var _inner
	var _tp: Node

	func _init(inner, tp_node: Node) -> void:
		_inner = inner
		_tp = tp_node

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


func _init(owner: Node) -> void:
	tp = owner


func attach_game(node: Node) -> void:
	tp.game = node
	if not node.tree_exiting.is_connected(Callable(tp, "_on_game_exiting")):
		node.tree_exiting.connect(Callable(tp, "_on_game_exiting"), CONNECT_ONE_SHOT)
	tp._hud.refresh_hud(true)


func on_game_exiting() -> void:
	tp.game = null
	tp.current_minigame = null
	tp._minigame_synced = false
	tp._early_win_triggered = false
	tp._initial_teams_seen.clear()
	tp.locked = false
	for rec in tp._tracked_actors.values():
		cleanup_actor_record(rec)
	tp._tracked_actors.clear()
	tp._hud.hide_hud()


func attach_minigame(mg: Node) -> void:
	tp.current_minigame = mg
	tp._minigame_synced = false
	tp._early_win_triggered = false
	tp._initial_teams_seen.clear()
	var fin_cb := Callable(tp, "_on_minigame_finished").bind(mg)
	if not mg.minigame_finished.is_connected(fin_cb):
		mg.minigame_finished.connect(fin_cb, CONNECT_ONE_SHOT)
	var exit_cb := Callable(tp, "_on_minigame_exiting").bind(mg)
	if not mg.tree_exiting.is_connected(exit_cb):
		mg.tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)
	tp._hud.refresh_hud(true)


func on_minigame_exiting(mg: Node) -> void:
	if tp.current_minigame == mg:
		tp.current_minigame = null
	for key in tp._tracked_actors.keys():
		var rec: Dictionary = tp._tracked_actors[key]
		var actor = rec.get("actor", null)
		if actor == null or not is_instance_valid(actor) or not (actor as Node).is_inside_tree():
			cleanup_actor_record(rec)
			tp._tracked_actors.erase(key)
	tp._hud.refresh_hud(true)


func extract_alive_ids(mg: Node) -> Array[int]:
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
				var nid: int = presence_network_id(item.get(&"player_presence"))
				if nid != 0:
					alive.append(nid)
	return alive


func on_minigame_finished(_id, mg: Node) -> void:
	if tp._minigame_synced or not tp._reg.is_team_mode_active():
		return
	if not tp._assign.is_host_authoritative() or not is_instance_valid(tp.game) or not is_instance_valid(mg):
		return
	if tp.game.has_method("is_current_game_cutscene") and bool(tp.game.call("is_current_game_cutscene")):
		return
	if bool(mg.get_meta(&"mpm_team_scores_applied", false)):
		tp._minigame_synced = true
		return
	var round_scores = tp.game.get("round_score_by_network_id")
	if not (round_scores is Dictionary) or (round_scores as Dictionary).is_empty():
		return
	var alive_ids: Array[int] = extract_alive_ids(mg)
	var synced: Dictionary = tp._reg.compute_team_synchronized_scores(round_scores as Dictionary, alive_ids)
	for k in synced.keys():
		(round_scores as Dictionary)[k] = int(synced[k])
	tp._minigame_synced = true
	mg.set_meta(&"mpm_team_scores_applied", true)
	tp._hud.record_team_win(synced, mg)


func check_vanilla_early_team_victory() -> void:
	if tp._early_win_triggered or not tp._reg.is_team_mode_active():
		return
	if not tp._assign.is_host_authoritative() or not is_instance_valid(tp.current_minigame):
		return
	var mg: Node = tp.current_minigame
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
		var tid: int = tp._reg.get_team(int(raw_nid))
		if tid > 0:
			active_teams[tid] = true
			tp._initial_teams_seen[tid] = true

	if tp._initial_teams_seen.size() >= 2 and active_teams.size() == 1:
		tp._early_win_triggered = true
		trigger_vanilla_team_win(mg)


func trigger_vanilla_team_win(mg: Node) -> void:
	var tree: SceneTree = tp.get_tree()
	if tree == null:
		return
	await tree.create_timer(1.0).timeout
	if not is_instance_valid(tp) or not is_instance_valid(mg) or not mg.is_inside_tree() or not tp._reg.is_team_mode_active():
		return
	if (&"finished" in mg and bool(mg.get(&"finished"))) or (&"game_end" in mg and bool(mg.get(&"game_end"))):
		return
	var ap = mg.get("active_players")
	if not (ap is Dictionary):
		return
	var active_dict: Dictionary = ap as Dictionary
	var active_teams: Dictionary = {}
	for raw_nid in active_dict.keys():
		var tid: int = tp._reg.get_team(int(raw_nid))
		if tid > 0:
			active_teams[tid] = true
	if active_teams.size() > 1:
		tp._early_win_triggered = false
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
	await tree.create_timer(2.0).timeout
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


func is_skipped_scene_node(node: Node) -> bool:
	var path_lower: String = str(node.get_path()).to_lower()
	for tok in tp.SKIP_SCENE_TOKENS:
		if path_lower.contains(tok):
			return true
	return false


func presence_network_id(presence) -> int:
	if presence == null:
		return 0
	if presence is Dictionary:
		return int((presence as Dictionary).get("network_id", 0))
	if presence is Object and &"network_id" in presence:
		return int(presence.get(&"network_id"))
	return 0


func is_first_person_rig(node: Node3D, depth: int = 4) -> bool:
	if depth <= 0:
		return false
	for child in node.get_children():
		if child is Camera3D and (child as Camera3D).current:
			return true
		if child is Node3D and is_first_person_rig(child as Node3D, depth - 1):
			return true
	return false


func find_actor_label(actor: Node3D) -> Label3D:
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


func track_actor(actor: Node3D) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var nid: int = presence_network_id(actor.get(&"player_presence"))
	if nid == 0:
		return
	var key: int = actor.get_instance_id()
	if tp._tracked_actors.has(key):
		return
	if is_first_person_rig(actor):
		return

	var lbl: Label3D = find_actor_label(actor)
	var badge: Label3D = null
	if tp._reg.is_team_mode_active() and tp._reg.get_team(nid) > 0:
		badge = create_team_badge(actor, nid)
	var ring: MeshInstance3D = ensure_actor_team_ring(actor, tp._reg.get_team(nid))

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
	tp._tracked_actors[key] = rec
	actor.tree_exiting.connect(func():
		if is_instance_valid(tp) and tp._tracked_actors.has(key):
			cleanup_actor_record(tp._tracked_actors[key])
			tp._tracked_actors.erase(key)
	, CONNECT_ONE_SHOT)
	sync_actor_visual(rec)


func create_team_badge(actor: Node3D, nid: int) -> Label3D:
	var tid: int = tp._reg.get_team(nid)
	if tid <= 0:
		return null
	var badge := Label3D.new()
	badge.name = "MpmTeamBadge"
	badge.font = tp._reg.get_cjk_badge_font()
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.font_size = 28
	badge.pixel_size = 0.0072
	badge.outline_size = 10
	badge.outline_modulate = Color.BLACK
	badge.position = Vector3(0.0, 2.35, 0.0)
	badge.text = "▼ %s" % tp._reg.get_team_tag(tid)
	badge.modulate = tp._reg.get_team_color(tid)
	actor.add_child(badge)
	return badge


func sync_actor_visual(rec: Dictionary) -> void:
	var actor: Node3D = rec["actor"] as Node3D
	if actor == null or not is_instance_valid(actor):
		return
	var nid: int = int(rec["nid"])
	var current_nid: int = presence_network_id(actor.get(&"player_presence"))
	if current_nid != 0 and current_nid != nid:
		nid = current_nid
		rec["nid"] = nid

	var tid: int = tp._reg.get_team(nid)
	var alive: bool = actor.visible and (not bool(rec["has_active"]) or bool(actor.get(&"active")))
	var lbl = rec.get("label", null)
	if (lbl == null or not is_instance_valid(lbl)):
		lbl = find_actor_label(actor)
		if lbl != null:
			rec["label"] = lbl
			rec["orig_modulate"] = (lbl as Label3D).modulate

	var spotlight_active: bool = tp._reg.is_player_spotlight_enabled()
	var is_local_actor: bool = nid == tp._assign.local_peer_id()
	var tcol: Color = tp._reg.get_team_color(tid) if tid > 0 else Color.WHITE

	var label_shows_text: bool = false
	if is_instance_valid(lbl) and lbl is Label3D:
		var l3: Label3D = lbl as Label3D
		var badge_font: Font = tp._reg.get_cjk_badge_font()
		if badge_font != null and l3.font != badge_font:
			l3.font = badge_font
		if tid > 0 and alive:
			if not l3.text.is_empty():
				label_shows_text = l3.visible
				var formatted: String = tp._reg.format_team_nickname(nid, l3.text)
				if l3.text != formatted:
					l3.text = formatted
			if not (is_local_actor and spotlight_active):
				var desired := Color(tcol.r, tcol.g, tcol.b, l3.modulate.a)
				if not l3.modulate.is_equal_approx(desired):
					l3.modulate = desired
		else:
			var cleaned: String = tp._reg.strip_team_prefix(l3.text)
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
			badge = create_team_badge(actor, nid)
			rec["badge"] = badge
		if is_instance_valid(badge) and badge is Label3D:
			var b3: Label3D = badge as Label3D
			var show_badge: bool = (not label_shows_text) or (float(rec.get("age", 99.0)) < 3.5)
			b3.visible = show_badge
			b3.text = "▼ %s" % tp._reg.get_team_tag(tid)
			b3.modulate = tcol
	elif is_instance_valid(badge) and badge is Label3D:
		(badge as Label3D).visible = false

	var ring = rec.get("ring", null)
	if tid > 0 and alive:
		if ring == null or not is_instance_valid(ring):
			ring = ensure_actor_team_ring(actor, tid)
			rec["ring"] = ring
		if is_instance_valid(ring) and ring is MeshInstance3D:
			var rmesh := ring as MeshInstance3D
			rmesh.visible = true
			var rmat := rmesh.material_override as StandardMaterial3D
			if rmat != null:
				rmat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.72)
	elif is_instance_valid(ring) and ring is MeshInstance3D:
		(ring as MeshInstance3D).visible = false


func ensure_actor_team_ring(actor: Node3D, tid: int) -> MeshInstance3D:
	if actor == null or not is_instance_valid(actor) or tid <= 0 or not tp._reg.is_team_mode_active():
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
	var tcol: Color = tp._reg.get_team_color(tid)
	mat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 0.72)
	ring.material_override = mat
	actor.add_child(ring)
	return ring


func cleanup_actor_record(rec: Dictionary) -> void:
	var badge = rec.get("badge", null)
	if is_instance_valid(badge) and badge is Node:
		(badge as Node).queue_free()
	var ring = rec.get("ring", null)
	if is_instance_valid(ring) and ring is Node:
		(ring as Node).queue_free()
	var lbl = rec.get("label", null)
	if is_instance_valid(lbl) and lbl is Label3D:
		var l3: Label3D = lbl as Label3D
		l3.text = tp._reg.strip_team_prefix(l3.text)
		l3.modulate = rec.get("orig_modulate", Color.WHITE) as Color


func step_physics() -> void:
	if not tp._reg.is_team_mode_active() or tp._tracked_actors.is_empty():
		return
	for key in tp._tracked_actors.keys():
		var rec: Dictionary = tp._tracked_actors[key]
		var actor = rec.get("actor", null)
		if actor == null or not is_instance_valid(actor):
			continue
		if (actor as Node).has_meta(&"lobby_bots_disco_brain"):
			var brain = (actor as Node).get_meta(&"lobby_bots_disco_brain")
			if brain != null and not (brain is _DiscoBrainTeamWrapper):
				(actor as Node).set_meta(&"lobby_bots_disco_brain", _DiscoBrainTeamWrapper.new(brain, tp))
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
				var other_id: int = presence_network_id((other as Object).get(&"player_presence"))
				if other_id != 0 and tp._reg.are_teammates(my_id, other_id):
					arr.remove_at(i)


func step_actors(delta: float) -> void:
	if tp._tracked_actors.is_empty():
		return
	var stale: Array = []
	for key in tp._tracked_actors.keys():
		var rec: Dictionary = tp._tracked_actors[key]
		var actor = rec.get("actor", null)
		if actor == null or not is_instance_valid(actor) or not (actor as Node).is_inside_tree():
			stale.append(key)
		else:
			rec["age"] = float(rec.get("age", 0.0)) + delta
			sync_actor_visual(rec)
	for key in stale:
		cleanup_actor_record(tp._tracked_actors[key])
		tp._tracked_actors.erase(key)
