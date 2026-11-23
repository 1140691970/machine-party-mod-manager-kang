extends SceneTree

## Headless test for mods/mpm-core/:
## - HUB_VERSION = 2 supersedes legacy HUB_VERSION = 1
## - event_bus (on, once, off, emit_event)
## - locale_utils (TW / CN / EN)
## - lobby_ui_coordinator v2 sets mpm_lobby_ui_coordinator_v2 and resolves overlapping panels

var _failed: bool = false
var _events_seen: Array[String] = []


func expect(cond: bool, label: String) -> void:
	if not cond:
		push_error("FAIL: " + label)
		_failed = true


func _on_once(payload: Dictionary) -> void:
	_events_seen.append("once:" + str(payload.get("v", "")))


func _on_persist(payload: Dictionary) -> void:
	_events_seen.append("on:" + str(payload.get("v", "")))


class MockLoader extends Node:
	var registries: Dictionary = {}
	var notes: Array[String] = []
	var overrides: Dictionary = {}
	var scene_hooks: Dictionary = {}

	func has_api(name: String) -> bool:
		return name in ["registry", "override_script_rel", "on_scene_script", "note"]

	func registry(name: String) -> Dictionary:
		if not registries.has(name):
			registries[name] = {}
		return registries[name] as Dictionary

	func note(msg: String) -> void:
		notes.append(msg)

	func on_scene_script(path: String, cb: Callable) -> void:
		scene_hooks[path] = cb

	func override_script_rel(_mod_id: String, target_path: String, _rel: String) -> bool:
		overrides[target_path] = true
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var loader := MockLoader.new()
	root.add_child(loader)

	# Simulate legacy HUB_VERSION = 1 installed before mpm-core
	var hub: Dictionary = loader.registry("custom_minigames_hub")
	hub["version"] = 1
	hub["installed_paths"] = {
		"res://scripts/scenes/game/game.gd": true,
		"res://scenes/local_game/script/local_game.gd": true,
		"res://scenes/lobby/components/playlist_handler.gd": true,
		"res://minigames/intermission_new/components/intermission_game_picker.gd": true,
	}

	var core_script := load("res://main.gd") as GDScript
	var core := core_script.new() as Node
	root.add_child(core)
	core.call("_mod_init", loader)
	core.call("_mod_ready", loader)

	expect(int(hub.get("version", 0)) == 2, "mpm-core upgrades HUB_VERSION 1 -> 2")
	expect(loader.overrides.size() == 4, "mpm-core installs all 4 HUB v2 overrides")
	expect(Engine.has_meta(&"mpm_core"), "mpm_core Engine meta published")
	var meta: Dictionary = Engine.get_meta(&"mpm_core") as Dictionary
	var bus = meta["event_bus"]
	var loc = meta["locale"]
	var coord = meta["lobby_ui"]

	# Event bus tests
	var persist_cb := Callable(self, "_on_persist")
	bus.on("round.start", persist_cb)
	bus.once("round.start", Callable(self, "_on_once"))
	bus.emit_event("round.start", {"v": "1"})
	bus.emit_event("round.start", {"v": "2"})
	bus.off("round.start", persist_cb)
	bus.emit_event("round.start", {"v": "3"})
	expect(_events_seen == ["on:1", "once:1", "on:2"], "event_bus on/once/off/emit works")

	# Locale helper tests
	expect(bool(loc.is_tw_locale("zh_Hant_TW")), "is_tw_locale detects zh_Hant_TW")
	expect(bool(loc.is_cn_locale("zh_CN")), "is_cn_locale detects zh_CN")

	# Lobby UI coordinator v2 tests
	var lobby := Node.new()
	root.add_child(lobby)
	var ui_layer := CanvasLayer.new()
	lobby.add_child(ui_layer)
	var p1 := PanelContainer.new()
	p1.custom_minimum_size = Vector2(200.0, 100.0)
	p1.offset_left = 24.0
	p1.offset_top = 24.0
	p1.offset_right = 224.0
	p1.offset_bottom = 124.0
	ui_layer.add_child(p1)
	var p2 := PanelContainer.new()
	p2.custom_minimum_size = Vector2(200.0, 100.0)
	p2.offset_left = 24.0
	p2.offset_top = 24.0
	p2.offset_right = 224.0
	p2.offset_bottom = 124.0
	ui_layer.add_child(p2)

	coord.attach_lobby(lobby)
	coord.register_panel(p1)
	coord.register_panel(p2)
	await process_frame
	coord.layout()
	expect(bool(Engine.get_meta(&"mpm_lobby_ui_coordinator_v2", false)), "mpm_lobby_ui_coordinator_v2 active")
	expect(p2.offset_top > p1.offset_top, "lobby_ui_coordinator shifts overlapping panel down")

	# Minigame SDK & dynamic slot allocation (>= 1000)
	var sdk = meta["minigame_sdk"]
	var custom_map: Dictionary = loader.registry("custom_minigames")
	custom_map[6] = {"mod_id": "roller-carnival", "slot_id": 6}
	Engine.set_meta("_mpm_custom_minigames", custom_map)
	var reg_events: Array = []
	bus.on("mpm_core.minigame_registered", func(p: Dictionary) -> void:
		reg_events.append(str(p.get("mod_id", "")) + ":" + str(p.get("slot_id", "")))
	)
	var r1: Dictionary = sdk.register_minigame({"mod_id": "demo-a", "display_name": "Demo A"}, loader)
	var r2: Dictionary = sdk.register_minigame({"mod_id": "demo-b", "display_name": "Demo B"}, loader)
	var r1_dup: Dictionary = sdk.register_minigame({"mod_id": "demo-a", "display_name": "Demo A"}, loader)
	expect(bool(r1.get("ok", false)) and int(r1.get("slot_id", 0)) == 1000, "first dynamic slot is 1000")
	expect(bool(r2.get("ok", false)) and int(r2.get("slot_id", 0)) == 1001, "second dynamic slot is 1001")
	expect(int(r1_dup.get("slot_id", 0)) == 1000, "re-registering demo-a reuses slot 1000")
	expect(reg_events.size() == 3 and reg_events[0] == "demo-a:1000", "minigame_registered event emitted")
	expect(bool(sdk.unregister_minigame("demo-a", loader)), "unregister_minigame removes demo-a")
	expect(not custom_map.has(1000), "slot 1000 removed from _mpm_custom_minigames")

	# MpmFxPool tests
	var fx_holder := Node3D.new()
	root.add_child(fx_holder)
	var pool = meta["create_fx_pool"].call()
	var created_count: int = int(pool.register_pool("spark", fx_holder, func() -> Node:
		return Node3D.new()
	, 2))
	expect(created_count == 2 and int(pool.available_count("spark")) == 2, "MpmFxPool registers 2 pooled nodes")
	expect(int(pool.warmup("spark")) == 2, "MpmFxPool warmup touches 2 nodes")
	var fx1 = pool.acquire("spark", 0.5)
	var fx2 = pool.acquire("spark", 0.5)
	var fx3 = pool.acquire("spark", 0.5)
	expect(fx1 != null and fx2 != null and fx3 == null, "MpmFxPool caps active nodes at capacity")
	expect(int(pool.active_count("spark")) == 2 and int(pool.available_count("spark")) == 0, "MpmFxPool tracks active/available counts")
	pool.tick(0.3)
	expect(int(pool.active_count("spark")) == 2, "MpmFxPool keeps nodes active before expiry")
	pool.tick(0.3)
	expect(int(pool.active_count("spark")) == 0 and int(pool.available_count("spark")) == 2, "MpmFxPool auto-releases expired nodes")
	pool.clear()
	fx_holder.free()

	# HookChain (SDK-4) tests
	var chain = meta["hook_chain"]
	var hook_order: Array = []
	var h_late: String = str(chain.add_hook("demo.calc", func(ctx, args: Array):
		hook_order.append("late")
		return int(ctx.next([int(args[0]) + 1])) * 2
	, 10))
	var h_early: String = str(chain.add_hook("demo.calc", func(ctx, args: Array):
		hook_order.append("early")
		return int(ctx.next([int(args[0]) * 3]))
	, -10))
	var calc_result: int = int(chain.invoke("demo.calc", func(x: int) -> int:
		hook_order.append("base")
		return x + 5
	, [4]))
	# (4 * 3 + 1 + 5) * 2 = 36
	expect(calc_result == 36, "hook_chain transforms args & return value in priority order")
	expect(hook_order == ["early", "late", "base"], "hook_chain executes lower priority number first")
	expect(bool(chain.remove_hook("demo.calc", h_late)), "hook_chain remove_hook removes late hook")
	expect(int(chain.hook_count("demo.calc")) == 1, "hook_chain hook_count == 1 after removal")
	var h_short: String = str(chain.add_hook("demo.calc", func(_ctx, _args: Array):
		return 999
	, -50))
	expect(int(chain.invoke("demo.calc", func(_x: int) -> int:
		return 0
	, [1])) == 999, "hook_chain supports short-circuit return")
	chain.remove_hook("demo.calc", h_early)
	chain.remove_hook("demo.calc", h_short)
	expect(int(chain.hook_count("demo.calc")) == 0, "hook_chain empty after removing all hooks")

	# Admission gating tests
	var mod_both: Dictionary = {"mod_id": "both-mod"}
	var mod_team: Dictionary = {
		"mod_id": "team-mod",
		"admission": {
			"mode_support": "team_only",
			"min_teams": 2,
			"max_teams": 2,
			"min_total_players": 4,
			"min_players_per_team": 2,
			"allow_local_couch": false,
		},
	}
	var mod_ffa: Dictionary = {
		"mod_id": "ffa-mod",
		"admission": {"mode_support": "ffa_only"},
	}

	var res_both_ffa: Dictionary = sdk.evaluate_minigame_eligibility(mod_both, {"team_enabled": false, "total_players": 2})
	var res_both_team: Dictionary = sdk.evaluate_minigame_eligibility(mod_both, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 2}, "total_players": 2})
	expect(bool(res_both_ffa.get("eligible", false)) and bool(res_both_team.get("eligible", false)), "default both mod is eligible in FFA and Team Party")

	var res_team_ffa: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": false, "total_players": 4})
	expect(not bool(res_team_ffa.get("eligible", true)) and bool(res_team_ffa.get("hard_blocked", false)) and str(res_team_ffa.get("reason_key", "")) == "needs_team_mode", "team_only hard-blocked in FFA")

	var res_team_ok: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 1, 3: 2, 4: 2}, "total_players": 4})
	expect(bool(res_team_ok.get("eligible", false)) and not bool(res_team_ok.get("hard_blocked", true)), "team_only eligible in 2v2")

	var res_team_3t: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": true, "team_count": 3, "teams": {1: 1, 2: 2, 3: 3, 4: 1}, "total_players": 4})
	expect(not bool(res_team_3t.get("eligible", true)) and bool(res_team_3t.get("hard_blocked", false)) and str(res_team_3t.get("reason_key", "")) == "team_count_out_of_range", "team_only hard-blocked when team_count > max_teams")

	var res_team_2v0: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 1, 3: 1, 4: 1}, "total_players": 4})
	expect(not bool(res_team_2v0.get("eligible", true)) and bool(res_team_2v0.get("soft_warning", false)) and str(res_team_2v0.get("reason_key", "")) == "needs_more_teams", "team_only soft-warned in asymmetric 2v0")

	var res_team_1v2: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 2, 3: 2, 4: 2}, "total_players": 4})
	expect(not bool(res_team_1v2.get("eligible", true)) and bool(res_team_1v2.get("soft_warning", false)) and str(res_team_1v2.get("reason_key", "")) == "needs_more_per_team", "team_only soft-warned in 1v3 when min_players_per_team == 2")

	var res_team_players: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 2}, "total_players": 2})
	expect(not bool(res_team_players.get("eligible", true)) and bool(res_team_players.get("soft_warning", false)) and str(res_team_players.get("reason_key", "")) == "needs_more_players", "min_total_players triggers soft warning")

	var res_team_local: Dictionary = sdk.evaluate_minigame_eligibility(mod_team, {"is_local": true, "total_players": 4})
	expect(not bool(res_team_local.get("eligible", true)) and bool(res_team_local.get("hard_blocked", false)) and str(res_team_local.get("reason_key", "")) == "local_unsupported", "allow_local_couch=false hard-blocked in local mode")

	var res_ffa_ok: Dictionary = sdk.evaluate_minigame_eligibility(mod_ffa, {"team_enabled": false, "total_players": 2})
	var res_ffa_blocked: Dictionary = sdk.evaluate_minigame_eligibility(mod_ffa, {"team_enabled": true, "team_count": 2, "teams": {1: 1, 2: 2}, "total_players": 2})
	expect(bool(res_ffa_ok.get("eligible", false)) and not bool(res_ffa_blocked.get("eligible", true)) and bool(res_ffa_blocked.get("hard_blocked", false)) and str(res_ffa_blocked.get("reason_key", "")) == "ffa_only", "ffa_only eligible in FFA and hard-blocked in Team Party")

	expect(not str(sdk.format_admission_tag(res_team_ffa, mod_team)).is_empty(), "format_admission_tag returns non-empty tag for blocked mod")
	expect(str(sdk.format_admission_tag(res_team_ok, mod_team)).is_empty(), "format_admission_tag returns empty string for eligible mod")

	# Regression #1: register_minigame() round-trip must preserve default "both" without forcing explicit bounds
	var reg_both: Dictionary = sdk.register_minigame({"mod_id": "default-both-rt"}, loader)
	var reg_both_entry: Dictionary = reg_both["entry"] as Dictionary
	var res_both_rt: Dictionary = sdk.evaluate_minigame_eligibility(reg_both_entry, {"team_enabled": true, "team_count": 2, "teams": {1: 1}, "total_players": 1})
	expect(bool(res_both_rt.get("eligible", false)), "registered default both mod stays eligible for solo player in team mode")

	# Regression #2: build_admission_context() auto-detects GameManager.local_game
	var gm_script := GDScript.new()
	gm_script.source_code = "extends Node\nvar local_game: bool = true\n"
	gm_script.reload()
	var gm_node := gm_script.new() as Node
	gm_node.name = "GameManager"
	root.add_child(gm_node)
	var auto_ctx: Dictionary = sdk.build_admission_context({})
	expect(bool(auto_ctx.get("is_local", false)), "build_admission_context auto-detects GameManager.local_game = true")
	gm_node.free()

	# Event bus round-trip for team_party.state_changed
	var tp_events: Array = []
	var tp_cb := func(p: Dictionary) -> void:
		tp_events.append(bool(p.get("enabled", false)))
	bus.on("team_party.state_changed", tp_cb)
	bus.emit_event("team_party.state_changed", {"enabled": true, "team_count": 2})
	bus.off("team_party.state_changed", tp_cb)
	expect(tp_events == [true], "team_party.state_changed event round-trip works")

	lobby.free()
	core.free()
	loader.free()
	for uid_rel in [
		"res://main.gd.uid",
		"res://event_bus.gd.uid",
		"res://locale_utils.gd.uid",
		"res://lobby_ui_coordinator.gd.uid",
		"res://minigame_sdk.gd.uid",
		"res://fx_pool.gd.uid",
		"res://hook_chain.gd.uid",
	]:
		if FileAccess.file_exists(uid_rel):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(uid_rel))

	if _failed:
		quit(1)
		return
	print("MPM Core checks passed")
	quit(0)
