## Opens a repo-relative path in whichever editor Godot normally uses for
## it — same as double-clicking it in the FileSystem dock. Shared by
## changes_panel.gd and history_panel.gd. No class_name: internal helper,
## addressed via preload (see git_status_flags.gd for why).
extends RefCounted

## Registered by the fork: unsupported text/configuration files open in the central diff screen.
static var open_raw_file: Callable


## The repo root isn't necessarily the Godot project root, so this resolves
## through an absolute path rather than assuming path is already
## res://-relative. Returns an error message to show, or "" on success.
static func open_file(repo_root: String, path: String) -> String:
	var abs_path := repo_root.path_join(path)
	var res_path := ProjectSettings.localize_path(abs_path)
	if not res_path.begins_with("res://"):
		return "This file is outside the current Godot project:\n%s" % abs_path

	if res_path.get_extension() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(res_path)
		return ""

	if not ResourceLoader.exists(res_path):
		if open_raw_file.is_valid() and FileAccess.file_exists(res_path):
			open_raw_file.call(path, 1)
			return ""
		return "This file cannot be opened in the current editor:\n%s" % res_path

	var resource := load(res_path)
	if resource == null:
		return "Failed to load:\n%s" % res_path

	if resource is Script:
		EditorInterface.edit_script(resource)
		EditorInterface.set_main_screen_editor("Script")
	else:
		EditorInterface.edit_resource(resource)
	return ""


## Like open_file(), but for scripts/text also jumps to line (1-based).
static func open_file_at_line(repo_root: String, path: String, line: int) -> String:
	var res_path := ProjectSettings.localize_path(repo_root.path_join(path))
	if res_path.begins_with("res://") and ResourceLoader.exists(res_path):
		var resource := load(res_path)
		if resource is Script:
			EditorInterface.edit_script(resource, maxi(1, line), 0)
			EditorInterface.set_main_screen_editor("Script")
			return ""
		var error := open_file(repo_root, path)
		# edit_script() only takes scripts; a text file (.md, .json...) is opened as a resource and its tab's caret moved here.
		if error.is_empty() and current_tab_path() == res_path:
			var code_edit := EditorInterface.get_script_editor().get_current_editor().get_base_editor() as CodeEdit
			if code_edit != null:
				code_edit.set_caret_line(clampi(line - 1, 0, code_edit.get_line_count() - 1))
				code_edit.center_viewport_to_caret()
		return error
	return open_file(repo_root, path)


## Reloads a file the editor doesn't know changed on disk (after revert, resolve...); its script tab is rewritten even with unsaved edits, since discarding them is the point.
static func refresh_external_change(repo_root: String, path: String) -> void:
	refresh_external_changes(repo_root, [path])


## refresh_external_change() for several repo-relative paths at once.
static func refresh_external_changes(repo_root: String, paths: Array) -> void:
	# Also covers a file revert_file() just deleted outright.
	EditorInterface.get_resource_filesystem().scan()
	var discarded := PackedStringArray()
	for path: String in paths:
		var res_path := ProjectSettings.localize_path(repo_root.path_join(path))
		if not res_path.begins_with("res://"):
			continue
		if res_path.get_extension() in ["tscn", "scn"]:
			if res_path in EditorInterface.get_open_scenes() and FileAccess.file_exists(res_path):
				EditorInterface.reload_scene_from_path(res_path)
			continue
		discarded.append(res_path)
		# CACHE_MODE_REPLACE re-reads it if it's already loaded (open script tab, resource used by an open scene...).
		if ResourceLoader.exists(res_path):
			ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	sync_open_scripts(discarded)


## Same as refresh_external_change(), but for an operation that can touch
## the whole working tree (checkout_commit, reset_branch_to, ...) rather
## than one known path.
static func refresh_all_external_changes() -> void:
	EditorInterface.get_resource_filesystem().scan()
	for scene_path in EditorInterface.get_open_scenes():
		# Unsaved new scenes have no path, and a checkout may have deleted the file.
		if not scene_path.is_empty() and FileAccess.file_exists(scene_path):
			EditorInterface.reload_scene_from_path(scene_path)
	sync_open_scripts()


## Script and text file tabs keep their own buffer, so reloading the resource doesn't change what's shown; this rewrites each open tab whose file changed on disk (one undoable edit, caret and scroll kept, tab stays "saved"). Tabs with unsaved edits are left alone unless listed in discarded.
static func sync_open_scripts(discarded := PackedStringArray()) -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return
	var tabs := _open_tabs(script_editor)
	for tab: Dictionary in tabs:
		var path: String = tab["path"]
		var code_edit := (tab["editor"] as ScriptEditorBase).get_base_editor() as CodeEdit
		if code_edit == null or not FileAccess.file_exists(path):
			continue
		if code_edit.get_version() != code_edit.get_saved_version() and not discarded.has(path):
			continue # unsaved edits in the tab: leave them, Godot asks on its own
		var disk := FileAccess.get_file_as_string(path)
		if code_edit.text == disk:
			continue
		_replace_text_keeping_view(code_edit, disk)
		if tab["script"] != null:
			tab["script"].source_code = disk


## res:// path of the script editor's current tab, a script or a text file (.md, .json...); "" for help pages and built-in scripts.
static func current_tab_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	var current: ScriptEditorBase = script_editor.get_current_editor() if script_editor != null else null
	if current == null:
		return ""
	if current.get_class() == "ScriptTextEditor":
		var script := script_editor.get_current_script()
		return script.resource_path if script != null and not script.resource_path.contains("::") else ""
	for tab: Dictionary in _open_tabs(script_editor):
		if tab["editor"] == current:
			return tab["path"]
	return ""


## [{"editor", "path", "script" (null for a text file)}] for every script and text file tab with a file behind it.
static func _open_tabs(script_editor: ScriptEditor) -> Array:
	var tabs: Array = []
	var editors: Array = script_editor.get_open_script_editors()
	# get_open_scripts() lists only the ScriptTextEditor tabs, in tab order — pair it with those editors.
	var scripts: Array = script_editor.get_open_scripts()
	var script_editors := editors.filter(func(e: Node) -> bool: return e.get_class() == "ScriptTextEditor")
	for i in mini(scripts.size(), script_editors.size()):
		var script: Script = scripts[i]
		if script != null and not script.resource_path.is_empty() and not script.resource_path.contains("::"):
			tabs.append({ "editor": script_editors[i], "path": script.resource_path, "script": script })
	# Text files (.md, .json, .txt...) have no API giving their path; the script list's items carry it as the tooltip and the tab index as metadata.
	var text_editors := {}
	for editor: Node in editors:
		if editor.get_class() == "TextEditor":
			text_editors[editor.get_index()] = editor
	if not text_editors.is_empty():
		for list: ItemList in script_editor.find_children("*", "ItemList", true, false):
			for i in list.item_count:
				var tab_index: Variant = list.get_item_metadata(i)
				var path := list.get_item_tooltip(i)
				if tab_index is int and text_editors.has(tab_index) and path.begins_with("res://"):
					tabs.append({ "editor": text_editors[tab_index], "path": path, "script": null })
					text_editors.erase(tab_index)
	return tabs


static func _replace_text_keeping_view(code_edit: CodeEdit, text: String) -> void:
	var caret_line := code_edit.get_caret_line()
	var caret_column := code_edit.get_caret_column()
	var scroll := code_edit.scroll_vertical
	code_edit.begin_complex_operation()
	var last := code_edit.get_line_count() - 1
	code_edit.remove_text(0, 0, last, code_edit.get_line(last).length())
	code_edit.insert_text(text, 0, 0)
	code_edit.end_complex_operation()
	code_edit.tag_saved_version()
	code_edit.set_caret_line(mini(caret_line, code_edit.get_line_count() - 1))
	code_edit.set_caret_column(caret_column)
	code_edit.scroll_vertical = scroll
