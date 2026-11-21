extends SceneTree

class FakePlayer extends Node3D:
	var player_presence: Dictionary = {}
	var active: bool = true


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var mod_script := load("res://main.gd") as Script
	if mod_script == null:
		_fail("Could not load res://main.gd")
		return
	var mod: Node = mod_script.new()
	mod.name = "PlayerSpotlight"
	root.add_child(mod)
	mod._mod_init(null)
	mod._mod_ready(null)
	await process_frame
	await process_frame

	if not Engine.has_meta(&"mpm_player_spotlight_active"):
		_fail("Expected mpm_player_spotlight_active meta to be set")
		return

	# 1. Vanilla-style minigame with local + remote players
	var stage := Node3D.new()
	stage.name = "DiscoDodgeStage"
	root.add_child(stage)

	var local_p := FakePlayer.new()
	local_p.name = "LocalPlayer"
	local_p.player_presence = {"network_id": 1}
	local_p.position = Vector3(2.0, 0.5, -1.0)
	var local_lbl := Label3D.new()
	local_lbl.modulate = Color.WHITE
	local_p.add_child(local_lbl)
	stage.add_child(local_p)

	var remote_p := FakePlayer.new()
	remote_p.name = "RemotePlayer"
	remote_p.player_presence = {"network_id": 2}
	var remote_lbl := Label3D.new()
	remote_lbl.modulate = Color.WHITE
	remote_p.add_child(remote_lbl)
	stage.add_child(remote_p)

	# 2. Lobby player should be skipped
	var lobby := Node3D.new()
	lobby.name = "LobbyScene"
	root.add_child(lobby)
	var lobby_p := FakePlayer.new()
	lobby_p.name = "LobbyLocal"
	lobby_p.player_presence = {"network_id": 1}
	lobby.add_child(lobby_p)

	# 3. First-person player with active child Camera3D should be skipped
	var fp_p := FakePlayer.new()
	fp_p.name = "FirstPersonPlayer"
	fp_p.player_presence = {"network_id": 1}
	var fp_cam := Camera3D.new()
	fp_cam.current = true
	fp_p.add_child(fp_cam)
	stage.add_child(fp_p)

	# 4. Explicit mpm_local_player group (first-party custom minigame)
	var custom_p := Node3D.new()
	custom_p.name = "CustomLocalPlayer"
	custom_p.add_to_group(&"mpm_local_player")
	custom_p.set_meta(&"mpm_alive", true)
	stage.add_child(custom_p)

	await process_frame
	await process_frame

	var tracked: Dictionary = mod.get("_tracked")
	if not tracked.has(local_p.get_instance_id()):
		_fail("Local vanilla player was not tracked")
		return
	if tracked.has(remote_p.get_instance_id()):
		_fail("Remote player should not be tracked")
		return
	if tracked.has(lobby_p.get_instance_id()):
		_fail("Lobby player should be skipped")
		return
	if tracked.has(fp_p.get_instance_id()):
		_fail("First-person player with active camera should be skipped")
		return
	if not tracked.has(custom_p.get_instance_id()):
		_fail("Custom mpm_local_player group node was not tracked")
		return

	var rec: Dictionary = tracked[local_p.get_instance_id()]
	var spot: SpotLight3D = rec["spot"]
	if not spot.visible:
		_fail("Local player spotlight should be visible")
		return
	if not (rec.get("alive_props", []) as Array).has(&"active"):
		_fail("Alive property should be cached on tracked record")
		return
	if local_lbl.modulate == Color.WHITE:
		_fail("Local player nametag should be tinted")
		return
	if remote_lbl.modulate != Color.WHITE:
		_fail("Remote player nametag should stay white")
		return

	# Verify F8 toggle disables spotlight and restores nametag
	mod.set_spotlight_enabled(false)
	await process_frame
	if spot.visible:
		_fail("Spotlight should be hidden when disabled")
		return
	if local_lbl.modulate != Color.WHITE:
		_fail("Nametag should restore to white when disabled")
		return

	mod.set_spotlight_enabled(true)
	await process_frame
	if not spot.visible:
		_fail("Spotlight should re-enable")
		return

	# Verify elimination hides spotlight
	local_p.active = false
	custom_p.set_meta(&"mpm_alive", false)
	await process_frame
	if spot.visible:
		_fail("Spotlight should hide when active=false")
		return
	var custom_spot: SpotLight3D = tracked[custom_p.get_instance_id()]["spot"]
	if custom_spot.visible:
		_fail("Custom spotlight should hide when mpm_alive=false")
		return

	# Verify cleanup when stage is freed
	stage.queue_free()
	await process_frame
	await process_frame
	if not (mod.get("_tracked") as Dictionary).is_empty():
		_fail("Tracked spotlights should clean up after stage exits")
		return

	print("Player Spotlight checks passed")
	quit(0)
