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
