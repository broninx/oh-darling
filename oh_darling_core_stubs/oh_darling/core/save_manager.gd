# ==============================================================================
#  SAVE MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Write and read the ONE save file. The game has AUTOSAVE ONLY (GDD).
#    There is no manual save, no second slot and no backup. Every choice is
#    permanent. This is a design rule, not a missing feature.
#
#  OWNS
#    - The file user://autosave.json
#
#  SIGNALS IT SENDS
#    - game_saved
#    - game_loaded
#
#  SIGNALS IT LISTENS TO
#    - none. GameManager calls save() at the correct moments.
#
#  PUBLIC API
#    - save()          : collect data from the managers and write the file
#    - load_game()     : read the file and give the data back to the managers
#    - has_save()      : true if a save file exists (for the "Continue" button)
#    - delete_save()   : for "New Game"
#
#  HOW IT WORKS
#    Each manager that has data to keep gives a Dictionary from get_save_data()
#    and takes it back in load_save_data(). SaveManager only puts them together
#    in one JSON file. It does not know what is inside each Dictionary.
#
#  MUST NOT
#    - Decide WHEN to save. GameManager decides.
#    - Keep game data itself. It is a "pipe", not a "store".
#
#  TODO
#    - Add NPC state, quest flags and Dialogue Manager variables.
#      To add something: give your manager get_save_data() / load_save_data(),
#      then add one line in save() and one line in load_game().
# ==============================================================================
extends Node
## Autosave only. One file, one slot.

signal game_saved
signal game_loaded

const SAVE_PATH: String = "user://autosave.json"
const TEMP_PATH: String = "user://autosave.tmp"
const SAVE_VERSION: int = 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"time": TimeManager.get_save_data(),
		"emotion": EmotionManager.get_save_data(),
	}
	# Write to a temporary file first. A crash during the write
	# then does not destroy the old save.
	var file: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (error %d)." % [TEMP_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.rename_absolute(TEMP_PATH, SAVE_PATH)
	game_saved.emit()


func load_game() -> bool:
	if not has_save():
		return false
	var text: String = FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SaveManager: the save file is not valid.")
		return false
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_error("SaveManager: wrong save version.")  # TODO: migration
		return false
	TimeManager.load_save_data(data.get("time", {}))
	EmotionManager.load_save_data(data.get("emotion", {}))
	game_loaded.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
