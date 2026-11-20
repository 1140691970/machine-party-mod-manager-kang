extends SceneTree

const LOBBY_SCRIPT_PATH := "res://scenes/lobby/scripts/lobby_scene.gd"

var failures: Array[String] = []


func expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _make_lobby_script() -> GDScript:
	var gd := GDScript.new()
	gd.source_code = "extends Node\nvar lobby_handler: Control\n"
	gd.reload()
	gd.take_over_path(LOBBY_SCRIPT_PATH)
	return gd


func _pump(loader: Node, frames: int = 2) -> void:
	for _i in frames:
		await process_frame
	loader._layout_lobby_mod_ui()
	await process_frame


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bootstrap_path: String = ProjectSettings.globalize_path("res://mpm_bootstrap.gd")
	var boot_script: GDScript = load(bootstrap_path)
	expect(boot_script != null, "mpm_bootstrap.gd should load")
	if boot_script == null:
		_finish()
		return

	var loader: Node = boot_script.new()
	root.size = Vector2i(1280, 720)
	root.add_child(loader)
	await process_frame

	expect(loader.loader_version() == "5", "loader_version should be 5")

	# Reproduce MachineParty-Plus VoiceHUD: added to /root via call_deferred during startup
	# BEFORE entering the lobby, initially hidden, and turned visible once inside the lobby.
	var voice_hud := CanvasLayer.new()
	voice_hud.name = "MPSB_VoiceHUD"
	voice_hud.layer = 45
	voice_hud.visible = false
	var voice_box := VBoxContainer.new()
	voice_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	voice_box.offset_left = -230
	voice_box.offset_right = -12
	voice_box.offset_top = 12
	var mute_btn := Button.new()
	mute_btn.text = "MUTE MIC"
	mute_btn.custom_minimum_size = Vector2(140, 32)
	var deafen_btn := Button.new()
	deafen_btn.text = "DEAFEN"
	deafen_btn.custom_minimum_size = Vector2(140, 32)
	voice_box.add_child(mute_btn)
	voice_box.add_child(deafen_btn)
	voice_hud.add_child(voice_box)
	root.add_child.call_deferred(voice_hud)
	await process_frame
	await process_frame

	# Build a synthetic vanilla lobby scene (with vanilla buttons already present before entering tree).
	var lobby_script: GDScript = _make_lobby_script()
	var lobby := Node.new()
	lobby.set_script(lobby_script)

	var handler_root := Control.new()
	handler_root.name = "Root"
	handler_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(handler_root)
	lobby.lobby_handler = handler_root

	var vanilla_back := Button.new()
	vanilla_back.text = "Back"
	vanilla_back.position = Vector2(24, 24)
	vanilla_back.size = Vector2(120, 40)
	handler_root.add_child(vanilla_back)

	# A vanilla button sitting in the right-hand slot where a naive shift might collide.
	var vanilla_ready := Button.new()
	vanilla_ready.text = "Ready"
	vanilla_ready.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	vanilla_ready.offset_left = -220
	vanilla_ready.offset_right = -24
	vanilla_ready.offset_top = 100
	vanilla_ready.offset_bottom = 148
	handler_root.add_child(vanilla_ready)

	root.add_child(lobby)
	await process_frame

	var vanilla_back_pos: Vector2 = vanilla_back.get_global_rect().position
	var vanilla_ready_pos: Vector2 = vanilla_ready.get_global_rect().position

	# Mod 1 (MachineParty+-like): CanvasLayer with a full-rect pass-through root holding both a top-right panel and a bottom-left chat box.
	var plus_layer := CanvasLayer.new()
	plus_layer.name = "MachinePartyPlusUI"
	lobby.add_child(plus_layer)

	var plus_root := Control.new()
	plus_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plus_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plus_layer.add_child(plus_root)

	var plus_panel := PanelContainer.new()
	plus_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	plus_panel.offset_left = -220
	plus_panel.offset_right = -24
	plus_panel.offset_top = 24
	plus_panel.offset_bottom = 84
	plus_root.add_child(plus_panel)

	var plus_btn := Button.new()
	plus_btn.text = "Public Lobby"
	plus_btn.custom_minimum_size = Vector2(180, 44)
	var plus_clicked := [false]
	plus_btn.pressed.connect(func(): plus_clicked[0] = true)
	plus_panel.add_child(plus_btn)

	var plus_chat := PanelContainer.new()
	plus_chat.position = Vector2(24, 560)
	plus_chat.size = Vector2(260, 120)
	var plus_chat_lbl := Label.new()
	plus_chat_lbl.text = "Lobby Chat"
	plus_chat.add_child(plus_chat_lbl)
	plus_root.add_child(plus_chat)

	# Mod 2 (lobby-bots-like): PRESET_TOP_WIDE HBoxContainer right-aligned on handler_root.
	var bots_toolbar := HBoxContainer.new()
	bots_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bots_toolbar.alignment = BoxContainer.ALIGNMENT_END
	handler_root.add_child(bots_toolbar)
	bots_toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bots_toolbar.offset_right = -24
	bots_toolbar.offset_top = 24
	bots_toolbar.offset_bottom = 24

	var bots_panel := VBoxContainer.new()
	bots_toolbar.add_child(bots_panel)

	var add_bot_btn := Button.new()
	add_bot_btn.text = "Add bot"
	add_bot_btn.custom_minimum_size = Vector2(140, 36)
	var bot_clicked := [false]
	add_bot_btn.pressed.connect(func(): bot_clicked[0] = true)
	bots_panel.add_child(add_bot_btn)

	# Mod 3 (non-overlapping chat at bottom-left) & Mod 4 (fullscreen modal) must stay untouched.
	var chat_box := PanelContainer.new()
	chat_box.position = Vector2(320, 560)
	chat_box.size = Vector2(260, 120)
	var chat_lbl := Label.new()
	chat_lbl.text = "Chat"
	chat_box.add_child(chat_lbl)
	handler_root.add_child(chat_box)

	var modal := PanelContainer.new()
	modal.position = Vector2(140, 60)
	modal.size = Vector2(1000, 600)
	var modal_lbl := Label.new()
	modal_lbl.text = "Settings Modal"
	modal.add_child(modal_lbl)
	handler_root.add_child(modal)

	await _pump(loader, 3)

	var plus_rect: Rect2 = loader._effective_content_rect(plus_panel)
	var bots_rect: Rect2 = loader._effective_content_rect(bots_toolbar)
	var ready_rect: Rect2 = vanilla_ready.get_global_rect()

	expect(not plus_rect.intersects(bots_rect), "MachineParty+ and lobby-bots must not overlap: %s vs %s" % [plus_rect, bots_rect])
	expect(not bots_rect.intersects(ready_rect), "Shifted lobby-bots must not overlap vanilla Ready button: %s vs %s" % [bots_rect, ready_rect])
	expect(bots_rect.position.y >= ready_rect.end.y + 10.0, "lobby-bots should clear both MachineParty+ and vanilla Ready button")
	expect(vanilla_back.get_global_rect().position == vanilla_back_pos, "Vanilla Back button must never move")
	expect(vanilla_ready.get_global_rect().position == vanilla_ready_pos, "Vanilla Ready button must never move")
	expect(chat_box.position == Vector2(320, 560), "Non-overlapping chat box must stay untouched")
	expect(plus_chat.position == Vector2(24, 560), "Non-overlapping sibling inside pass-through root must stay untouched")
	expect(modal.position == Vector2(140, 60), "Fullscreen modal must stay untouched")

	# Verify buttons still work normally.
	plus_btn.emit_signal("pressed")
	add_bot_btn.emit_signal("pressed")
	expect(plus_clicked[0] and bot_clicked[0], "Mod button signals must remain functional")

	# Dynamic growth (adding bot rows) should not break layout or falsely pin lobby-bots.
	var bot_row := Label.new()
	bot_row.text = "Bot 1 · Ready"
	bot_row.custom_minimum_size = Vector2(140, 32)
	bots_panel.add_child(bot_row)
	await _pump(loader, 2)
	var bots_state: Dictionary = loader._lobby_ui_state[bots_toolbar.get_instance_id()]
	expect(not bool(bots_state["pinned"]), "Growing container height must not falsely pin lobby-bots")

	# Snap-back: when MachineParty+ hides its CanvasLayer, lobby-bots returns to its original offset_top.
	plus_layer.visible = false
	await _pump(loader, 2)
	expect(absf(bots_toolbar.offset_top - 24.0) <= 1.0, "lobby-bots should snap back to offset_top=24 when MachineParty+ hides (got %s)" % bots_toolbar.offset_top)

	# Deferred startup root layer (MachineParty-Plus VoiceHUD) becomes visible in lobby:
	# VoiceHUD stays at y=12 and lobby-bots shifts cleanly below it even though VoiceHUD was added via call_deferred before lobby!
	voice_hud.visible = true
	await _pump(loader, 2)
	var voice_rect: Rect2 = loader._effective_content_rect(voice_box)
	var bots_rect_voice: Rect2 = loader._effective_content_rect(bots_toolbar)
	expect(voice_rect.size.y > 40.0, "Deferred VoiceHUD must be tracked and have valid content rect")
	expect(absf(voice_box.offset_top - 12.0) <= 1.0, "VoiceHUD should stay at its original offset_top=12")
	expect(not voice_rect.intersects(bots_rect_voice), "Deferred root VoiceHUD and lobby-bots must not overlap: %s vs %s" % [voice_rect, bots_rect_voice])
	expect(bots_rect_voice.position.y >= voice_rect.end.y + 10.0, "lobby-bots should shift below VoiceHUD")
	expect(not bots_rect_voice.intersects(ready_rect), "Shifted lobby-bots must also clear vanilla Ready button below VoiceHUD")
	voice_hud.visible = false
	await _pump(loader, 2)
	expect(absf(bots_toolbar.offset_top - 24.0) <= 1.0, "lobby-bots should snap back after VoiceHUD hides")

	# Pinned mod test: re-show MachineParty+ and simulate a mod forcing itself back to y=24.
	plus_layer.visible = true
	await _pump(loader, 2)
	bots_toolbar.offset_top = 24.0
	await _pump(loader, 2)
	expect(bool(bots_state["pinned"]), "Mod that overwrites its own offset_top should be detected as pinned")
	var plus_rect_after: Rect2 = loader._effective_content_rect(plus_panel)
	var bots_rect_after: Rect2 = loader._effective_content_rect(bots_toolbar)
	expect(not plus_rect_after.intersects(bots_rect_after), "After pinning one mod, the other movable mod must shift clear: %s vs %s" % [plus_rect_after, bots_rect_after])

	# Leaving lobby cleans up and disables _process.
	lobby.queue_free()
	await process_frame
	await process_frame
	expect(not loader.is_processing(), "Loader _process must turn off after leaving lobby")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Loader lobby UI checks passed")
		quit(0)
	else:
		for f in failures:
			push_error("FAIL: " + f)
		quit(1)
