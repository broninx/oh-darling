## Before a git operation works with the files on disk, offers to save the scenes and scripts that are still unsaved in the editor.
## No class_name: internal helper, addressed via preload.
extends RefCounted

const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")
const ScriptAutosave := preload("res://addons/gittydot/util/script_autosave.gd")
const WorkingDiff := preload("res://addons/gittydot/dock/widgets/working_diff.gd")

const ALWAYS_SAVE_SETTING_KEY := "save_before_git"


static func flush_scripts() -> bool:
	if not WorkingDiff.flush_all():
		return false
	return ScriptAutosave.instance == null or not ScriptAutosave.instance.enabled or ScriptAutosave.instance.call("flush_pending")


## res:// paths of open scenes and scripts with unsaved edits (untitled scenes excluded: there's no file to save them to).
static func unsaved_files() -> PackedStringArray:
	var paths := WorkingDiff.dirty_paths()
	for path in EditorInterface.get_unsaved_scenes():
		if not path.is_empty():
			paths.append(path)
	var script_editor := EditorInterface.get_script_editor()
	if script_editor != null:
		for path in script_editor.get_unsaved_files():
			if not path.is_empty() and not paths.has(path):
				paths.append(path)
	return paths


static func save_all() -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor != null:
		script_editor.save_all_scripts()
	EditorInterface.save_all_scenes()


## Coroutine. verb names the operation ("Commit", "Checkout"...); for_commit says the risk is missing edits rather than overwritten ones. False = the user cancelled.
static func ensure_saved(parent: Node, verb: String, for_commit := false) -> bool:
	if not WorkingDiff.flush_all():
		await Dialogs.error(parent, "Comparison save paused", "A working-file comparison could not be saved. Its draft is kept. Resolve the message in GittyDot before %s." % verb)
		return false
	if ScriptAutosave.instance != null and ScriptAutosave.instance.enabled:
		if not ScriptAutosave.instance.call("flush_pending"):
			await Dialogs.error(parent, "Auto-save paused", "A script changed on disk or could not be saved. Resolve it in the editor before %s." % verb)
			return false
	var unsaved := unsaved_files()
	if unsaved.is_empty():
		return true
	if Settings.get_value(ALWAYS_SAVE_SETTING_KEY, false):
		save_all()
		return true
	var shown := Array(unsaved.slice(0, 8)).map(func(p: String) -> String: return "  " + p.trim_prefix("res://"))
	if unsaved.size() > 8:
		shown.append("  … and %d more" % (unsaved.size() - 8))
	var risk := "The commit only takes what's saved on disk, so these edits would be left out." if for_commit \
			else "%s changes files on disk; unsaved edits could end up out of sync with them or overwrite the result later." % verb
	var answer: String = await Dialogs.error_with_actions(parent, "Unsaved Changes",
			"%d file%s ha%s unsaved changes:\n%s\n\n%s" % [unsaved.size(), "" if unsaved.size() == 1 else "s", "s" if unsaved.size() == 1 else "ve", "\n".join(shown), risk],
			{ "save": "Save and %s" % verb, "always": "Always Save First", "skip": "%s Without Saving" % verb })
	match answer:
		"save":
			save_all()
		"always":
			Settings.set_value(ALWAYS_SAVE_SETTING_KEY, true)
			save_all()
		"skip":
			pass
		_:
			return false
	return true
