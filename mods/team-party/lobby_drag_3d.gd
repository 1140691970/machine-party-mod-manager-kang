extends RefCounted

## 3D lobby chair rings/halos, ragdoll drag/drop animations, remote drag sync, and nametag coloring.

var tp: Node


func _init(owner: Node) -> void:
	tp = owner


func set_lobby_cursor(kind: StringName) -> void:
	if kind == tp._current_cursor_kind:
		return
	tp._current_cursor_kind = kind
	if DisplayServer.get_name() == "headless":
		return
	var tree: SceneTree = tp.get_tree()
	var cm = tree.root.get_node_or_null("CursorManager") if (tree != null and tree.root != null) else null
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
		if not tp._cursor_textures.has(kind) and ResourceLoader.exists(cpath):
			var loaded = ResourceLoader.load(cpath)
			if loaded is Texture2D:
				tp._cursor_textures[kind] = loaded
		var tex = tp._cursor_textures.get(kind, null)
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


func set_slot_pivot_pose(slot_node: Node3D, seat: int, offset_vec: Vector3, tilt_euler: Vector3 = Vector3.ZERO, stretch_scale: Vector3 = Vector3.ONE, pivot_y: float = 1.45) -> void:
	if slot_node == null or not is_instance_valid(slot_node):
		return
	var rest_xform: Transform3D = tp._lobby_seat_rest_slot_xform.get(seat, slot_node.transform) as Transform3D
	if not tp._lobby_seat_rest_slot_xform.has(seat) and not (tp._drag_active and seat == tp._drag_seat):
		tp._lobby_seat_rest_slot_xform[seat] = rest_xform
	var floor_w: Vector3 = seat_world_floor_pos(slot_node, null, seat)
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


func restore_slot_transform(seat: int) -> void:
	if seat < 0 or not is_instance_valid(tp.lobby):
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or not (handler.get("players") is Array):
		return
	var players_arr: Array = handler.get("players") as Array
	if seat < players_arr.size():
		var snode = players_arr[seat]
		if snode is Node3D and is_instance_valid(snode) and tp._lobby_seat_rest_slot_xform.has(seat):
			(snode as Node3D).transform = tp._lobby_seat_rest_slot_xform[seat] as Transform3D


func begin_drag_skeleton(slot_node: Node3D) -> void:
	restore_drag_skeleton()
	if slot_node == null or not is_instance_valid(slot_node):
		return
	var ap := slot_node.get_node_or_null("main character2/anim_character rig") as AnimationPlayer
	if ap != null:
		tp._drag_anim = ap
		tp._drag_anim_was_playing = ap.is_playing()
		ap.pause()
	var sk := slot_node.get_node_or_null("main character2/Armature_001/Skeleton3D") as Skeleton3D
	if sk != null:
		tp._drag_skel = sk
		tp._drag_saved_bones.clear()
		for i in range(sk.get_bone_count()):
			tp._drag_saved_bones[i] = sk.get_bone_pose_rotation(i)


func restore_drag_skeleton() -> void:
	if tp._drag_skel != null and is_instance_valid(tp._drag_skel):
		for idx_v in tp._drag_saved_bones.keys():
			var idx: int = int(idx_v)
			if idx >= 0 and idx < tp._drag_skel.get_bone_count():
				tp._drag_skel.set_bone_pose_rotation(idx, tp._drag_saved_bones[idx_v] as Quaternion)
	if tp._drag_anim != null and is_instance_valid(tp._drag_anim) and tp._drag_anim_was_playing:
		tp._drag_anim.play()
	tp._drag_skel = null
	tp._drag_anim = null
	tp._drag_saved_bones.clear()
	tp._drag_anim_was_playing = false


func _blend_drag_bone(bname: String, local_euler: Vector3, weight: float) -> void:
	if tp._drag_skel == null or not is_instance_valid(tp._drag_skel):
		return
	var idx: int = tp._drag_skel.find_bone(bname)
	if idx < 0 or not tp._drag_saved_bones.has(idx):
		return
	var rest_q: Quaternion = tp._drag_skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	var target_q: Quaternion = (rest_q * Quaternion.from_euler(local_euler)).normalized()
	tp._drag_skel.set_bone_pose_rotation(idx, (tp._drag_saved_bones[idx] as Quaternion).slerp(target_q, weight))


func apply_drag_dangling_pose() -> void:
	if tp._drag_skel == null or not is_instance_valid(tp._drag_skel):
		return
	var t_pick: float = clampf(tp._drag_elapsed / 0.14, 0.0, 1.0)
	var blend: float = 1.0 - pow(1.0 - t_pick, 3.0)
	var vx: float = clampf(tp._drag_vel.x / 10.0, -1.0, 1.0)
	var vy: float = clampf(tp._drag_vel.y / 10.0, -1.0, 1.0)
	var kick: float = sin(tp._anim_time * 9.5)
	var wave: float = sin(tp._anim_time * 7.8 + 0.9)

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


func sync_lobby_camera_angle() -> void:
	if not is_instance_valid(tp.lobby):
		return
	var cam := tp.lobby.get_node_or_null("LobbyPreviewViewport/LobbyViewport/Camera3D") as Camera3D
	if cam == null:
		return
	var wants_elevated: bool = tp._reg.is_team_mode_active() and tp._assign.lobby_total_seats() > 4
	if wants_elevated:
		if not tp._lobby_cam_adjusted:
			tp._orig_lobby_cam_xform = cam.transform
			tp._lobby_cam_adjusted = true
			cam.position = tp._orig_lobby_cam_xform.origin + Vector3(0.0, 2.35, 1.1)
			cam.rotation_degrees.x = tp._orig_lobby_cam_xform.basis.get_euler().x * (180.0 / PI) - 5.2
	elif tp._lobby_cam_adjusted:
		cam.transform = tp._orig_lobby_cam_xform
		tp._lobby_cam_adjusted = false


func cancel_lobby_drag() -> void:
	var was_active: bool = tp._drag_active
	var was_local_active: bool = tp._drag_active and not tp._drag_is_remote
	var seat_restore: int = tp._drag_seat
	restore_drag_skeleton()
	if seat_restore >= 0:
		restore_slot_transform(seat_restore)
	if tp._hop_seat >= 0:
		restore_slot_transform(tp._hop_seat)
		tp._hop_seat = -1
	tp._drag_seat = -1
	tp._drag_actor_id = 0
	tp._drag_start_pos = Vector2.ZERO
	tp._drag_active = false
	tp._drag_is_remote = false
	tp._drag_net_accum = 0.0
	tp._drag_last_sent_pos = Vector3.ZERO
	tp._drag_last_sent_hover = -2
	tp._drag_orig_slot_pos = Vector3.ZERO
	tp._drag_orig_floor = Vector3.ZERO
	tp._drag_visual_pos = Vector3.ZERO
	tp._drag_target_pos = Vector3.ZERO
	tp._drag_vel = Vector3.ZERO
	tp._drag_elapsed = 0.0
	tp._drag_rest_collar = Vector3.ZERO
	set_lobby_cursor(&"point")
	if was_local_active:
		broadcast_drag_end(seat_restore, [])
	if was_active and is_instance_valid(tp.lobby) and tp.lobby.is_inside_tree():
		update_lobby_nametags()


func _on_lobby_ready() -> void:
	tp._ui.setup_lobby_panel()
	sync_lobby_camera_angle()


func enter_lobby(node: Node) -> void:
	tp.lobby = node
	tp.locked = false
	tp._hovered_seat = -1
	tp._lobby_cam_adjusted = false
	tp._seat_drop_bounce.clear()
	tp._hop_seat = -1
	cancel_lobby_drag()
	tp._last_roster_sig = ""
	tp._orig_nametag_alpha.clear()
	clear_lobby_3d_rings()
	tp._hud.hide_hud()
	if tp.lobby.is_node_ready():
		tp._ui.setup_lobby_panel()
		sync_lobby_camera_angle()
	else:
		tp.lobby.ready.connect(Callable(self, "_on_lobby_ready"), CONNECT_ONE_SHOT)
	tp.lobby.tree_exiting.connect(Callable(tp, "_leave_lobby"), CONNECT_ONE_SHOT)


func leave_lobby() -> void:
	cancel_lobby_drag()
	if tp._lobby_cam_adjusted and is_instance_valid(tp.lobby):
		var cam := tp.lobby.get_node_or_null("LobbyPreviewViewport/LobbyViewport/Camera3D") as Camera3D
		if cam != null:
			cam.transform = tp._orig_lobby_cam_xform
	tp._lobby_cam_adjusted = false
	tp._seat_drop_bounce.clear()
	tp._hop_seat = -1
	clear_lobby_3d_rings()
	var tree: SceneTree = tp.get_tree()
	if DisplayServer.get_name() != "headless" and tree != null and tree.root != null and tree.root.get_node_or_null("CursorManager") == null:
		Input.set_custom_mouse_cursor(null)
	if is_instance_valid(tp.panel):
		tp.panel.queue_free()
	tp.panel = null
	tp.mode_button = null
	tp.shuffle_button = null
	tp.my_team_button = null
	tp.rows = null
	tp._actions_row = null
	tp._hint_label = null
	tp._swap_offer_row = null
	tp._swap_offer_label = null
	tp._swap_accept_btn = null
	tp._swap_decline_btn = null
	tp._pending_swap_requests.clear()
	tp._incoming_swap_from = 0
	tp._incoming_swap_name = ""
	tp._incoming_swap_expires = 0.0
	tp._title_label = null
	tp._format_badge_lbl = null
	tp._format_buttons.clear()
	tp._hovered_seat = -1
	if not tp.locked:
		tp.lobby = null
	tp._last_roster_sig = ""


func broadcast_drag_begin() -> void:
	if tp._assign.is_host_authoritative() and tp._drag_active and not tp._drag_is_remote and tp._assign.has_any_remote_peers():
		tp._drag_net_accum = 0.0
		tp._drag_last_sent_pos = tp._drag_target_pos
		tp._drag_last_sent_hover = tp._hovered_seat
		tp.rpc(&"_rpc_drag_begin", tp._drag_seat, tp._drag_target_pos, tp._hovered_seat)


func broadcast_drag_pose_if_due(delta: float) -> void:
	if not tp._assign.is_host_authoritative() or not tp._drag_active or tp._drag_is_remote or not tp._assign.has_any_remote_peers():
		return
	tp._drag_net_accum += delta
	if tp._drag_net_accum < 0.05:
		return
	var pos_moved: bool = tp._drag_target_pos.distance_squared_to(tp._drag_last_sent_pos) > 0.0004
	if not pos_moved and tp._hovered_seat == tp._drag_last_sent_hover:
		return
	tp._drag_net_accum = 0.0
	tp._drag_last_sent_pos = tp._drag_target_pos
	tp._drag_last_sent_hover = tp._hovered_seat
	tp.rpc(&"_rpc_drag_pose", tp._drag_seat, tp._drag_target_pos, tp._hovered_seat)


func broadcast_drag_end(from_seat: int, bounce_seats: Array) -> void:
	if tp._assign.is_host_authoritative() and not tp._drag_is_remote and tp._assign.has_any_remote_peers():
		tp.rpc(&"_rpc_drag_end", from_seat, bounce_seats)


func apply_remote_drag_begin(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not is_instance_valid(tp.lobby) or not tp.lobby.is_inside_tree():
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null:
		return
	var players_arr = handler.get("players")
	var nametags = handler.get("nametags")
	if not (players_arr is Array) or seat < 0 or seat >= (players_arr as Array).size():
		return
	restore_drag_skeleton()
	if tp._drag_seat >= 0:
		restore_slot_transform(tp._drag_seat)
	if tp._hop_seat >= 0:
		restore_slot_transform(tp._hop_seat)
		tp._hop_seat = -1
	var snode: Node3D = (players_arr as Array)[seat] as Node3D if (players_arr as Array)[seat] is Node3D else null
	if snode == null or not is_instance_valid(snode):
		return
	var slbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags is Array and seat < (nametags as Array).size()) else null
	tp._drag_orig_floor = seat_world_floor_pos(snode, slbl, seat)
	tp._drag_rest_collar = Vector3(tp._drag_orig_floor.x, 2.05, tp._drag_orig_floor.z)
	if not tp._seat_drop_bounce.has(seat):
		tp._lobby_seat_rest_slot_xform[seat] = snode.transform
	tp._drag_seat = seat
	tp._drag_actor_id = 0
	tp._drag_active = true
	tp._drag_is_remote = true
	tp._drag_elapsed = 0.0
	tp._drag_visual_pos = tp._drag_rest_collar
	tp._drag_target_pos = target_pos
	tp._drag_vel = Vector3(0.0, 3.0, 0.0)
	tp._hovered_seat = hover_seat
	begin_drag_skeleton(snode)
	update_lobby_nametags()


func apply_remote_drag_pose(seat: int, target_pos: Vector3, hover_seat: int) -> void:
	if not tp._drag_active or not tp._drag_is_remote or tp._drag_seat != seat:
		return
	tp._drag_target_pos = target_pos
	if hover_seat != tp._hovered_seat:
		tp._hovered_seat = hover_seat
		if is_instance_valid(tp.lobby) and tp.lobby.is_inside_tree():
			update_lobby_nametags()


func apply_remote_drag_end(from_seat: int, bounce_seats: Array) -> void:
	restore_drag_skeleton()
	if tp._drag_seat >= 0:
		restore_slot_transform(tp._drag_seat)
	if from_seat >= 0:
		restore_slot_transform(from_seat)
	if tp._hop_seat >= 0:
		restore_slot_transform(tp._hop_seat)
		tp._hop_seat = -1
	tp._drag_seat = -1
	tp._drag_actor_id = 0
	tp._drag_active = false
	tp._drag_is_remote = false
	tp._drag_vel = Vector3.ZERO
	tp._drag_elapsed = 0.0
	tp._hovered_seat = -1
	for bs in bounce_seats:
		tp._seat_drop_bounce[int(bs)] = 0.24
	if is_instance_valid(tp.lobby) and tp.lobby.is_inside_tree():
		update_lobby_nametags()


func clear_lobby_3d_rings() -> void:
	for k in tp._lobby_seat_rings.keys():
		var ring = tp._lobby_seat_rings[k]
		if is_instance_valid(ring) and ring is Node:
			(ring as Node).queue_free()
	tp._lobby_seat_rings.clear()
	for k in tp._lobby_seat_halos.keys():
		var halo = tp._lobby_seat_halos[k]
		if is_instance_valid(halo) and halo is Node:
			(halo as Node).queue_free()
	tp._lobby_seat_halos.clear()
	tp._lobby_seat_rest_floor.clear()
	tp._lobby_seat_rest_slot_xform.clear()
	tp._seat_drop_bounce.clear()
	tp._hop_seat = -1


func seat_world_floor_pos(slot_node: Node3D, lbl: Label3D, seat: int = -1) -> Vector3:
	if seat >= 0 and tp._lobby_seat_rest_floor.has(seat):
		return tp._lobby_seat_rest_floor[seat] as Vector3
	var pos := Vector3(0.0, 0.06, 0.0)
	if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
		pos = Vector3(lbl.global_position.x, 0.06, lbl.global_position.z)
	elif slot_node != null and is_instance_valid(slot_node) and slot_node.is_inside_tree():
		var arm := slot_node.get_node_or_null("main character2/Armature_001") as Node3D
		if arm != null and arm.is_inside_tree():
			pos = Vector3(arm.global_position.x, 0.06, arm.global_position.z)
		else:
			pos = Vector3(slot_node.global_position.x, 0.06, slot_node.global_position.z)
	if seat >= 0 and not (tp._drag_active and seat == tp._drag_seat) and not tp._seat_drop_bounce.has(seat) and seat != tp._hop_seat and slot_node != null and slot_node.is_inside_tree():
		tp._lobby_seat_rest_floor[seat] = pos
	return pos


func _make_chair_torus_mesh(inner_r: float, outer_r: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = outer_r
	torus.rings = 28
	torus.ring_segments = 6
	return torus


func _ensure_lobby_chair_ring(seat: int, slot_node: Node3D, lbl: Label3D) -> MeshInstance3D:
	if tp._lobby_seat_rings.has(seat):
		var existing = tp._lobby_seat_rings[seat]
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
	var floor_w: Vector3 = seat_world_floor_pos(slot_node, lbl, seat)
	if container is Node3D and (container as Node3D).is_inside_tree():
		ring.position = (container as Node3D).to_local(floor_w)
	else:
		ring.position = floor_w
	tp._lobby_seat_rings[seat] = ring
	return ring


func _ensure_lobby_chair_halo(seat: int, slot_node: Node3D, lbl: Label3D) -> MeshInstance3D:
	if tp._lobby_seat_halos.has(seat):
		var existing = tp._lobby_seat_halos[seat]
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
	var floor_w: Vector3 = seat_world_floor_pos(slot_node, lbl, seat) + Vector3(0.0, 0.02, 0.0)
	if container is Node3D and (container as Node3D).is_inside_tree():
		halo.position = (container as Node3D).to_local(floor_w)
	else:
		halo.position = floor_w
	tp._lobby_seat_halos[seat] = halo
	return halo


func _seat_zone_blocked_for_local(zone_tid: int, cap: int, local_id: int, participants: Array[Dictionary]) -> bool:
	if zone_tid <= 0 or cap <= 0 or tp._reg.get_team(local_id) == zone_tid:
		return false
	var zm: Array[Dictionary] = tp._assign.team_members_list(zone_tid, participants)
	if zm.size() < cap:
		return false
	for m in zm:
		if bool(m.get("is_bot", false)) or tp._assign.is_bot_id(int(m["id"])):
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
	var floor_w: Vector3 = seat_world_floor_pos(slot_node, lbl, seat)
	var container: Node = halo.get_parent()
	var bounce_rem: float = float(tp._seat_drop_bounce.get(seat, 0.0))

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
	elif tp._drag_active and is_hov:
		if occupied:
			var sp: float = 0.5 + 0.5 * sin(tp._anim_time * 10.0)
			ring_s = 1.15 + 0.08 * sp
			ring_a = 1.0
			ring_col = chair_col.lerp(Color.WHITE, 0.25 + 0.2 * sp)
			halo_s = 1.08 + 0.14 * sp
			halo_y = 0.08 + 0.08 * sp
			halo_a = 0.95
			halo_col = chair_col.lerp(Color.WHITE, 0.5)
		else:
			var p: float = fmod(tp._anim_time * 1.85, 1.0)
			ring_s = 1.16 + 0.07 * sin(tp._anim_time * 8.5)
			ring_a = 0.98
			ring_col = chair_col.lerp(Color.WHITE, 0.35)
			halo_s = lerpf(1.26, 0.72, p)
			halo_y = 0.06 + p * 0.78
			halo_a = (1.0 - p) * 0.94
			halo_col = chair_col.lerp(Color.WHITE, 0.55)
	elif not occupied:
		var pulse: float = 0.5 + 0.5 * sin(tp._anim_time * 3.0 + float(seat) * 0.75)
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


func animate_lobby_seats(delta: float) -> void:
	if not is_instance_valid(tp.lobby):
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null:
		return
	var players_arr = handler.get("players")
	var nametags = handler.get("nametags")
	if not (players_arr is Array) or not (nametags is Array):
		return

	if not tp._seat_drop_bounce.is_empty():
		var finished: Array = []
		for s_key in tp._seat_drop_bounce.keys():
			var s_idx: int = int(s_key)
			var rem: float = float(tp._seat_drop_bounce[s_key]) - delta
			if rem <= 0.0:
				finished.append(s_key)
				restore_slot_transform(s_idx)
			else:
				tp._seat_drop_bounce[s_key] = rem
				if s_idx >= 0 and s_idx < (players_arr as Array).size() and not (tp._drag_active and s_idx == tp._drag_seat):
					var bnode = (players_arr as Array)[s_idx]
					if bnode is Node3D and is_instance_valid(bnode):
						var t: float = clampf(1.0 - (rem / 0.24), 0.0, 1.0)
						var by: float = sin(t * PI) * exp(-t * 2.5) * 0.28
						var sq: float = sin(t * PI * 2.0) * (1.0 - t) * 0.16
						var stretch := Vector3(1.0 + sq * 0.65, maxf(0.76, 1.0 - sq), 1.0 + sq * 0.65)
						set_slot_pivot_pose(bnode as Node3D, s_idx, Vector3(0.0, by, 0.0), Vector3.ZERO, stretch)
		for fkey in finished:
			tp._seat_drop_bounce.erase(fkey)

	var resolved: Dictionary = tp._assign.resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = mini(seats.size(), mini((nametags as Array).size(), (players_arr as Array).size()))
	var want_hop: int = -1
	if tp._drag_active and tp._hovered_seat >= 0 and tp._hovered_seat != tp._drag_seat and tp._hovered_seat < total_seats:
		if int(seats[tp._hovered_seat]) != 0:
			want_hop = tp._hovered_seat
	if tp._hop_seat >= 0 and tp._hop_seat != want_hop:
		if not tp._seat_drop_bounce.has(tp._hop_seat):
			restore_slot_transform(tp._hop_seat)
		tp._hop_seat = -1
	if want_hop >= 0 and not tp._seat_drop_bounce.has(want_hop):
		tp._hop_seat = want_hop
		var hnode = (players_arr as Array)[want_hop]
		if hnode is Node3D and is_instance_valid(hnode):
			var hop_y: float = absf(sin(tp._anim_time * 7.5)) * 0.16
			var hop_tilt: float = sin(tp._anim_time * 7.5) * 0.06
			set_slot_pivot_pose(hnode as Node3D, want_hop, Vector3(0.0, hop_y, 0.0), Vector3(0.0, 0.0, hop_tilt), Vector3.ONE)

	if not tp._reg.is_team_mode_active() or not ResourceLoader.exists("res://scenes/lobby/lobby_scene.tscn"):
		return
	var cap: int = tp._reg.team_capacity()
	var local_id: int = tp._assign.local_peer_id()
	var participants: Array[Dictionary] = tp._assign.collect_lobby_participants()
	var fixed_zone: bool = (tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO])
	for seat in range(total_seats):
		var slot_node: Node3D = (players_arr as Array)[seat] as Node3D if (players_arr as Array)[seat] is Node3D else null
		if slot_node == null:
			continue
		var lbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags is Array and seat < (nametags as Array).size()) else null
		var nid: int = int(seats[seat])
		var occupied: bool = (nid != 0) and slot_node.visible
		var zone_tid: int = tp._reg.seat_zone_team(seat, total_seats)
		var is_hov: bool = (seat == tp._hovered_seat) and not tp.locked
		if occupied and tp._reg.get_team(nid) > 0:
			var tid: int = tp._reg.get_team(nid)
			var chair_col: Color = tp._reg.get_team_color(zone_tid) if (fixed_zone and zone_tid > 0) else tp._reg.get_team_color(tid)
			_apply_chair_ring_and_halo(seat, slot_node, lbl, chair_col, true, is_hov, tp._drag_active and seat == tp._drag_seat, false)
		elif not occupied:
			var empty_col: Color = tp._reg.get_team_color(zone_tid) if zone_tid > 0 else Color(0.88, 0.88, 0.88)
			var zone_full_humans: bool = _seat_zone_blocked_for_local(zone_tid, cap, local_id, participants)
			_apply_chair_ring_and_halo(seat, slot_node, lbl, empty_col, false, is_hov, false, zone_full_humans)


func can_interact_with_seat(_seat: int, occ_id: int) -> bool:
	if not tp._reg.is_team_mode_active() or tp.locked:
		return false
	if occ_id == 0:
		return true
	if occ_id == tp._assign.local_peer_id() or tp._assign.is_bot_id(occ_id):
		return true
	return tp._assign.is_host_authoritative() or tp._reg.get_team(occ_id) != tp._reg.get_team(tp._assign.local_peer_id())


func update_lobby_nametags() -> void:
	if not is_instance_valid(tp.lobby):
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null:
		return
	var nametags = handler.get("nametags")
	var players_arr = handler.get("players")
	if not (nametags is Array) or not (players_arr is Array):
		return

	var resolved: Dictionary = tp._assign.resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var total_seats: int = mini(seats.size(), mini((nametags as Array).size(), (players_arr as Array).size()))
	var active_teams: bool = tp._reg.is_team_mode_active()
	var cap: int = tp._reg.team_capacity()
	var participants: Array[Dictionary] = []
	if active_teams:
		participants = tp._assign.collect_lobby_participants()
	var local_id: int = tp._assign.local_peer_id()
	var ui_font: Font = tp._reg.get_ui_font()
	var has_3d_lobby: bool = ResourceLoader.exists("res://scenes/lobby/lobby_scene.tscn")

	for seat in range(total_seats):
		var slot_obj = (players_arr as Array)[seat]
		var slot_node: Node3D = slot_obj as Node3D if slot_obj is Node3D else null
		var tag_node = (nametags as Array)[seat]
		if not (tag_node is Label3D) or not is_instance_valid(tag_node):
			continue
		var lbl: Label3D = tag_node as Label3D
		if not tp._orig_nametag_alpha.has(seat):
			tp._orig_nametag_alpha[seat] = lbl.modulate.a
		var nid: int = int(seats[seat])
		var slot_visible: bool = slot_node == null or slot_node.visible
		var occupied: bool = (nid != 0) and slot_visible
		if slot_node != null and slot_node.is_inside_tree() and not (tp._drag_active and seat == tp._drag_seat) and not tp._seat_drop_bounce.has(seat) and seat != tp._hop_seat:
			tp._lobby_seat_rest_slot_xform[seat] = slot_node.transform
		var zone_tid: int = tp._reg.seat_zone_team(seat, total_seats)
		var is_hov: bool = (seat == tp._hovered_seat) and not tp.locked
		var show_empty_chair: bool = active_teams and not occupied
		var fixed_zone: bool = (tp.team_format in [tp.FORMAT_DUO, tp.FORMAT_SQUAD, tp.FORMAT_TRIO])

		if active_teams and occupied and tp._reg.get_team(nid) > 0:
			var tid: int = tp._reg.get_team(nid)
			if not lbl.text.is_empty():
				var formatted: String = tp._reg.format_team_nickname(nid, lbl.text)
				if lbl.text != formatted:
					lbl.text = formatted
			if ui_font != null and lbl.font != ui_font:
				lbl.font = ui_font
			var tcol: Color = tp._reg.get_team_color(tid)
			var boost_a: float = 0.96 if float(tp._orig_nametag_alpha[seat]) < 0.85 else lbl.modulate.a
			var target_col := Color(tcol.r, tcol.g, tcol.b, boost_a)
			if not lbl.modulate.is_equal_approx(target_col):
				lbl.modulate = target_col
			lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.94)

			if slot_node != null and has_3d_lobby:
				var chair_col: Color = tp._reg.get_team_color(zone_tid) if (fixed_zone and zone_tid > 0) else tcol
				_apply_chair_ring_and_halo(seat, slot_node, lbl, chair_col, true, is_hov, tp._drag_active and seat == tp._drag_seat, false)
		elif show_empty_chair:
			if ui_font != null and lbl.font != ui_font:
				lbl.font = ui_font
			if slot_node != null and has_3d_lobby:
				var zone_full_humans: bool = _seat_zone_blocked_for_local(zone_tid, cap, local_id, participants)
				var empty_col: Color = tp._reg.get_team_color(zone_tid) if zone_tid > 0 else Color(0.88, 0.88, 0.88)
				_apply_chair_ring_and_halo(seat, slot_node, lbl, empty_col, false, is_hov, false, zone_full_humans)
		else:
			if not occupied:
				if tp._lobby_seat_rings.has(seat) and is_instance_valid(tp._lobby_seat_rings[seat]):
					(tp._lobby_seat_rings[seat] as Node3D).visible = false
				if tp._lobby_seat_halos.has(seat) and is_instance_valid(tp._lobby_seat_halos[seat]):
					(tp._lobby_seat_halos[seat] as Node3D).visible = false
				continue
			var cleaned: String = tp._reg.strip_team_prefix(lbl.text)
			if lbl.text != cleaned:
				lbl.text = cleaned
			var orig_a: float = float(tp._orig_nametag_alpha.get(seat, 1.0))
			var white_col := Color(1.0, 1.0, 1.0, orig_a)
			if not lbl.modulate.is_equal_approx(white_col):
				lbl.modulate = white_col
			if tp._lobby_seat_rings.has(seat) and is_instance_valid(tp._lobby_seat_rings[seat]):
				(tp._lobby_seat_rings[seat] as Node3D).visible = false
			if tp._lobby_seat_halos.has(seat) and is_instance_valid(tp._lobby_seat_halos[seat]):
				(tp._lobby_seat_halos[seat] as Node3D).visible = false


func project_seat_to_screen(world_pt: Vector3, cam: Camera3D, sub_vp: Viewport, tex_rect: TextureRect) -> Vector2:
	if cam == null or cam.is_position_behind(world_pt):
		return Vector2(-99999.0, -99999.0)
	var vp_pt: Vector2 = cam.unproject_position(world_pt)
	if tex_rect != null and is_instance_valid(tex_rect) and sub_vp != tp.get_viewport():
		var vp_size: Vector2 = Vector2(sub_vp.get_visible_rect().size)
		if vp_size.x <= 0.0 or vp_size.y <= 0.0:
			return Vector2(-99999.0, -99999.0)
		var uv: Vector2 = vp_pt / vp_size
		return tex_rect.get_global_transform_with_canvas() * (uv * tex_rect.size)
	return vp_pt


func screen_to_lobby_drag_pos(mouse_pos: Vector2) -> Variant:
	if not is_instance_valid(tp.lobby):
		return null
	var handler = tp.lobby.get("lobby_handler")
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
	var tex_rect: TextureRect = tp.lobby.get_node_or_null("Lobby/Control/TextureRect") as TextureRect
	if tex_rect != null and is_instance_valid(tex_rect) and sub_vp != tp.get_viewport():
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
	for fp_v in tp._lobby_seat_rest_floor.values():
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
	var vp: Viewport = tp.get_viewport()
	if vp == null:
		return false
	var hov: Control = vp.gui_get_hovered_control()
	while hov != null:
		if hov is BaseButton or hov is Slider or hov is LineEdit or hov is TextEdit:
			return true
		if hov is PanelContainer:
			var sb = hov.get_theme_stylebox("panel")
			if not (sb is StyleBoxEmpty):
				return true
		hov = hov.get_parent_control()
	return false


func pick_lobby_chair_at(mouse_pos: Vector2) -> int:
	if not tp._reg.is_team_mode_active() or tp.locked or not is_instance_valid(tp.lobby):
		return -1
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")) or bool(tp.lobby.get("loading")):
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
	var tex_rect: TextureRect = tp.lobby.get_node_or_null("Lobby/Control/TextureRect") as TextureRect
	var hit_radius: float = maxf(44.0, tex_rect.size.x * 0.056) if (tex_rect != null and is_instance_valid(tex_rect)) else 66.0

	var resolved: Dictionary = tp._assign.resolved_lobby_seats()
	var seats: Array = resolved["seats"]
	var best_seat: int = -1
	var best_dist: float = hit_radius
	var total: int = mini(seats.size(), (players_arr as Array).size())
	for seat in range(total):
		if tp._drag_active and seat == tp._drag_seat:
			continue
		var slot_node: Node3D = (players_arr as Array)[seat] as Node3D
		if slot_node == null:
			continue
		var lbl: Label3D = (nametags as Array)[seat] as Label3D if (nametags is Array and seat < (nametags as Array).size()) else null
		var floor_p: Vector3 = seat_world_floor_pos(slot_node, lbl, seat)
		var torso_p: Vector3 = Vector3(floor_p.x, 1.35, floor_p.z)
		var head_p: Vector3 = Vector3(floor_p.x, 2.35, floor_p.z)
		var s_torso: Vector2 = project_seat_to_screen(torso_p, cam, sub_vp, tex_rect)
		var s_head: Vector2 = project_seat_to_screen(head_p, cam, sub_vp, tex_rect)
		var d: float = minf(mouse_pos.distance_to(s_torso), mouse_pos.distance_to(s_head))
		if lbl != null and is_instance_valid(lbl) and lbl.is_inside_tree():
			var s_lbl: Vector2 = project_seat_to_screen(lbl.global_position, cam, sub_vp, tex_rect)
			d = minf(d, mouse_pos.distance_to(s_lbl))
		if d < best_dist:
			best_dist = d
			best_seat = seat
	return best_seat


func handle_input(event: InputEvent) -> void:
	if not tp._reg.is_team_mode_active() or tp.locked or not is_instance_valid(tp.lobby):
		if tp._drag_seat >= 0:
			cancel_lobby_drag()
		return
	var handler = tp.lobby.get("lobby_handler")
	if handler == null or not bool(handler.get("active")) or bool(tp.lobby.get("loading")):
		if tp._drag_seat >= 0:
			cancel_lobby_drag()
		return
	if tp._drag_is_remote:
		return
	var vp: Viewport = tp.get_viewport()
	if event is InputEventKey and tp._drag_seat >= 0:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			cancel_lobby_drag()
			if vp != null:
				vp.set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mpos: Vector2 = tp.lobby.get_viewport().get_mouse_position() if tp.lobby.get_viewport() != null else (event as InputEventMouseMotion).position
		if tp._drag_seat >= 0:
			if not tp._drag_active and mpos.distance_to(tp._drag_start_pos) >= 6.0:
				tp._drag_active = true
				tp._drag_elapsed = 0.0
				set_lobby_cursor(&"grab")
				var players_arr = handler.get("players")
				if players_arr is Array and tp._drag_seat < (players_arr as Array).size():
					var dnode = (players_arr as Array)[tp._drag_seat]
					if dnode is Node3D and is_instance_valid(dnode):
						begin_drag_skeleton(dnode as Node3D)
				tp._drag_visual_pos = tp._drag_rest_collar
				tp._drag_vel = Vector3(0.0, 3.0, 0.0)
				var first_hit = screen_to_lobby_drag_pos(mpos)
				if first_hit is Vector3:
					tp._drag_target_pos = first_hit as Vector3
				broadcast_drag_begin()
			if tp._drag_active:
				var target_hit: int = pick_lobby_chair_at(mpos)
				if target_hit != tp._hovered_seat:
					tp._hovered_seat = target_hit
					update_lobby_nametags()
				var drag_hit = screen_to_lobby_drag_pos(mpos)
				if drag_hit is Vector3:
					tp._drag_target_pos = drag_hit as Vector3
		else:
			var hit: int = pick_lobby_chair_at(mpos)
			set_lobby_cursor(&"hover" if hit >= 0 else &"point")
			if hit != tp._hovered_seat:
				tp._hovered_seat = hit
				update_lobby_nametags()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and tp._drag_seat >= 0:
			cancel_lobby_drag()
			if vp != null:
				vp.set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var mpos: Vector2 = tp.lobby.get_viewport().get_mouse_position() if tp.lobby.get_viewport() != null else mb.position
			if mb.pressed:
				var hit: int = pick_lobby_chair_at(mpos)
				if hit >= 0:
					if tp._assign.is_host_authoritative():
						var resolved: Dictionary = tp._assign.resolved_lobby_seats()
						var seats: Array = resolved["seats"]
						var occ_id: int = int(seats[hit]) if hit < seats.size() else 0
						if occ_id != 0:
							var players_arr = handler.get("players")
							var nametags = handler.get("nametags")
							var snode: Node3D = (players_arr as Array)[hit] as Node3D if (players_arr is Array and hit < (players_arr as Array).size()) else null
							var slbl: Label3D = (nametags as Array)[hit] as Label3D if (nametags is Array and hit < (nametags as Array).size()) else null
							if snode != null:
								tp._drag_seat = hit
								tp._drag_actor_id = occ_id
								tp._drag_start_pos = mpos
								tp._drag_active = false
								tp._drag_elapsed = 0.0
								tp._drag_orig_slot_pos = snode.position
								tp._drag_orig_floor = seat_world_floor_pos(snode, slbl, hit)
								if not tp._seat_drop_bounce.has(hit):
									tp._lobby_seat_rest_slot_xform[hit] = snode.transform
								tp._drag_rest_collar = Vector3(tp._drag_orig_floor.x, 2.05, tp._drag_orig_floor.z)
								tp._drag_visual_pos = tp._drag_rest_collar
								tp._drag_target_pos = tp._drag_rest_collar
								tp._drag_vel = Vector3.ZERO
								if vp != null:
									vp.set_input_as_handled()
								return
					tp._assign.click_lobby_chair(hit)
					if vp != null:
						vp.set_input_as_handled()
			elif tp._drag_seat >= 0:
				var from_seat: int = tp._drag_seat
				var was_active: bool = tp._drag_active
				tp._drag_seat = -1
				tp._drag_actor_id = 0
				tp._drag_active = false
				tp._drag_vel = Vector3.ZERO
				tp._drag_elapsed = 0.0
				restore_drag_skeleton()
				if tp._hop_seat >= 0:
					restore_slot_transform(tp._hop_seat)
					tp._hop_seat = -1
				restore_slot_transform(from_seat)
				if was_active:
					var drop_seat: int = pick_lobby_chair_at(mpos)
					tp._hovered_seat = drop_seat
					set_lobby_cursor(&"hover" if drop_seat >= 0 else &"point")
					if drop_seat >= 0 and drop_seat != from_seat:
						if tp._assign.host_drop_chair(from_seat, drop_seat):
							var bseats: Array = [drop_seat]
							if tp._seat_drop_bounce.has(from_seat):
								bseats.append(from_seat)
							broadcast_drag_end(from_seat, bseats)
						else:
							tp._seat_drop_bounce[from_seat] = 0.18
							broadcast_drag_end(from_seat, [from_seat])
					else:
						tp._seat_drop_bounce[from_seat] = 0.18
						broadcast_drag_end(from_seat, [from_seat])
						update_lobby_nametags()
				else:
					set_lobby_cursor(&"hover")
					tp._assign.click_lobby_chair(from_seat)
				if vp != null:
					vp.set_input_as_handled()


func step_lobby(delta: float) -> void:
	if not is_instance_valid(tp.lobby) or not is_instance_valid(tp.panel):
		return
	var handler = tp.lobby.get("lobby_handler")
	var show_panel: bool = handler != null and bool(handler.get("active")) and not bool(tp.lobby.get("loading"))
	tp.panel.visible = show_panel and (tp._assign.is_host_authoritative() or tp._reg.is_team_mode_active())
	if not show_panel:
		return
	tp._hud.hide_hud()
	var want_cam_elevated: bool = tp._reg.is_team_mode_active() and tp._assign.lobby_total_seats() > 4
	if want_cam_elevated != tp._lobby_cam_adjusted:
		sync_lobby_camera_angle()
	var participants: Array[Dictionary] = tp._assign.collect_lobby_participants()
	var sig_parts: PackedStringArray = PackedStringArray()
	for p in participants:
		sig_parts.append("%d:%s:%d" % [int(p["id"]), str(p["name"]), tp._reg.get_team(int(p["id"]))])
	var sig: String = "%d|%s|%s" % [tp.team_count, str(tp.locked), "|".join(sig_parts)]
	if tp._assign.reconcile_lobby_teams(participants):
		tp._reg.publish_state()
		tp._assign.broadcast_teams()
		sig = ""
	if sig != tp._last_roster_sig:
		tp._last_roster_sig = sig
		tp._ui.refresh_lobby_ui()
	if tp._assign.is_host_authoritative() and not tp._pending_swap_requests.is_empty():
		var expired_req: Array = []
		for tk in tp._pending_swap_requests.keys():
			var req = tp._pending_swap_requests[tk]
			if req is Dictionary and tp._anim_time >= float((req as Dictionary).get("expires_at", 0.0)):
				expired_req.append(tk)
		for ek in expired_req:
			tp._pending_swap_requests.erase(ek)
	if tp._incoming_swap_from > 0 and tp._anim_time >= tp._incoming_swap_expires:
		tp._incoming_swap_from = 0
		tp._incoming_swap_name = ""
		tp._incoming_swap_expires = 0.0
		tp._ui.refresh_lobby_ui()
	if tp._drag_active and tp._drag_seat >= 0:
		tp._drag_elapsed += delta
		var players_arr = handler.get("players")
		if players_arr is Array and tp._drag_seat < (players_arr as Array).size():
			var dnode = (players_arr as Array)[tp._drag_seat]
			if dnode is Node3D and is_instance_valid(dnode):
				var dt: float = clampf(delta, 0.001, 0.05)
				var prev_pos: Vector3 = tp._drag_visual_pos
				var follow_alpha: float = 1.0 - exp(-32.0 * dt)
				tp._drag_visual_pos = tp._drag_visual_pos.lerp(tp._drag_target_pos, follow_alpha)
				var inst_vel: Vector3 = (tp._drag_visual_pos - prev_pos) / dt
				tp._drag_vel = tp._drag_vel.lerp(inst_vel, 1.0 - exp(-16.0 * dt))
				var rest_collar: Vector3 = tp._drag_rest_collar if tp._drag_rest_collar != Vector3.ZERO else Vector3(tp._drag_orig_floor.x, 2.05, tp._drag_orig_floor.z)
				var offset_vec: Vector3 = tp._drag_visual_pos - rest_collar
				var tilt_z: float = clampf(-tp._drag_vel.x * 0.048 + sin(tp._anim_time * 6.5) * 0.035, -0.46, 0.46)
				var yaw_y: float = clampf(tp._drag_vel.x * 0.038, -0.42, 0.42)
				var tilt_x: float = clampf(tp._drag_vel.y * 0.020 + cos(tp._anim_time * 5.0) * 0.02, -0.22, 0.22)
				var sy: float = clampf(1.03 + absf(tp._drag_vel.y) * 0.008, 0.97, 1.10)
				var sxz: float = 1.0 / sqrt(sy)
				set_slot_pivot_pose(dnode as Node3D, tp._drag_seat, offset_vec, Vector3(tilt_x, yaw_y, tilt_z), Vector3(sxz, sy, sxz), 2.05)
				apply_drag_dangling_pose()
				broadcast_drag_pose_if_due(delta)
	update_lobby_nametags()
	animate_lobby_seats(delta)
