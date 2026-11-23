extends RefCounted

## MPM Core Minigame SDK — declarative minigame registration & dynamic Hub v2 slot allocation (>= 1000).

const DYNAMIC_SLOT_BASE := 1000

var _event_bus = null


func _init(bus = null) -> void:
	_event_bus = bus


func _get_custom_map(loader = null) -> Dictionary:
	var dict: Dictionary = {}
	if loader != null and loader.has_method("registry"):
		var raw = loader.registry("custom_minigames")
		if raw is Dictionary:
			dict = raw
	elif Engine.has_meta("_mpm_custom_minigames"):
		var existing = Engine.get_meta("_mpm_custom_minigames")
		if existing is Dictionary:
			dict = existing
	Engine.set_meta("_mpm_custom_minigames", dict)
	return dict


func _get_hub(loader = null) -> Dictionary:
	var dict: Dictionary = {}
	if loader != null and loader.has_method("registry"):
		var raw = loader.registry("custom_minigames_hub")
		if raw is Dictionary:
			dict = raw
	elif Engine.has_meta("_mpm_custom_minigames_hub"):
		var existing = Engine.get_meta("_mpm_custom_minigames_hub")
		if existing is Dictionary:
			dict = existing
	if not dict.has("dynamic_slots") or not (dict["dynamic_slots"] is Dictionary):
		dict["dynamic_slots"] = {}
	Engine.set_meta("_mpm_custom_minigames_hub", dict)
	return dict


func allocate_slot(mod_id: String, preferred_slot: int = -1, loader = null) -> int:
	if preferred_slot > 0:
		return preferred_slot
	var custom_map: Dictionary = _get_custom_map(loader)
	var hub: Dictionary = _get_hub(loader)
	var dynamic_slots: Dictionary = hub["dynamic_slots"] as Dictionary
	if dynamic_slots.has(mod_id):
		return int(dynamic_slots[mod_id])
	var used: Dictionary = {}
	for k in custom_map.keys():
		used[int(k)] = true
	for v in dynamic_slots.values():
		used[int(v)] = true
	var candidate: int = DYNAMIC_SLOT_BASE
	while used.has(candidate):
		candidate += 1
	dynamic_slots[mod_id] = candidate
	return candidate


func register_minigame(spec: Dictionary, loader = null) -> Dictionary:
	var mod_id: String = str(spec.get("mod_id", "")).strip_edges()
	if mod_id.is_empty():
		return {"ok": false, "error": "missing_mod_id"}
	var custom_map: Dictionary = _get_custom_map(loader)
	var preferred: int = int(spec.get("slot_id", -1))
	var slot_id: int = allocate_slot(mod_id, preferred, loader)

	var entry: Dictionary = spec.duplicate()
	entry["mod_id"] = mod_id
	entry["slot_id"] = slot_id
	if not entry.has("scene_path"):
		entry["scene_path"] = ""
	if not entry.has("packed_scene"):
		entry["packed_scene"] = null
	if not entry.has("icon_texture"):
		entry["icon_texture"] = null
	if not entry.has("default_rounds"):
		entry["default_rounds"] = 1
	if not entry.has("display_name"):
		entry["display_name"] = mod_id
	if not entry.has("brief_content"):
		entry["brief_content"] = ""
	if not entry.has("controls_data"):
		entry["controls_data"] = []

	custom_map[slot_id] = entry
	if _event_bus != null and _event_bus.has_method("emit_event"):
		_event_bus.emit_event("mpm_core.minigame_registered", {"mod_id": mod_id, "slot_id": slot_id})
	return {"ok": true, "slot_id": slot_id, "entry": entry}


func unregister_minigame(mod_id: String, loader = null) -> bool:
	var custom_map: Dictionary = _get_custom_map(loader)
	var hub: Dictionary = _get_hub(loader)
	var dynamic_slots: Dictionary = hub["dynamic_slots"] as Dictionary
	var removed := false
	var to_erase: Array = []
	for key in custom_map.keys():
		var item = custom_map[key]
		if item is Dictionary and str((item as Dictionary).get("mod_id", "")) == mod_id:
			to_erase.append(key)
	for key in to_erase:
		custom_map.erase(key)
		removed = true
	if dynamic_slots.has(mod_id):
		dynamic_slots.erase(mod_id)
		removed = true
	if removed and _event_bus != null and _event_bus.has_method("emit_event"):
		_event_bus.emit_event("mpm_core.minigame_unregistered", {"mod_id": mod_id})
	return removed


func list_minigames(loader = null) -> Array:
	var custom_map: Dictionary = _get_custom_map(loader)
	var slots: Array = []
	for k in custom_map.keys():
		slots.append(int(k))
	slots.sort()
	var out: Array = []
	for slot_id in slots:
		out.append(custom_map[slot_id])
	return out
