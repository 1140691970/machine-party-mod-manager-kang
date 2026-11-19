extends Node

const MOD_ID := "__MOD_ID__"

func _mod_init(loader) -> void:
	var directory: String = loader.dir_of(MOD_ID)
	if ResourceLoader.has_cached("res://autoloads/globals.gd"):
		push_error(MOD_ID + ": Globals was loaded before the overlay")
		return
	if directory.is_empty() or not ProjectSettings.load_resource_pack(directory.path_join("overlay.zip"), true):
		push_error(MOD_ID + ": could not mount overlay.zip")
		return
	loader.note(MOD_ID + ": mounted overlay.zip")
