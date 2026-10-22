@tool
extends VBoxContainer
## Central workspace: working files are editable; staged and historical snapshots are read-only.

const DiffView := preload("res://addons/gittydot/dock/widgets/diff_view.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")
const RepoWatcher := preload("res://addons/gittydot/util/repo_watcher.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")

var repo: RefCounted
var diff_view: Control
var path := ""
var _mode: OptionButton
var _path_label: Label
var _open_button: Button
var _layout: OptionButton
var _signature := ""
## Immutable historical comparison requested by Git Log; empty for working-file modes.
var _comparison := {}
var _shown_mode := 0
var _refresh_queued := false


func _init() -> void:
	name = "GittyDotWorkspace"
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_path_label = Label.new()
	_path_label.text = "Select a changed file in Commit or use FileSystem → Git: Show Change"
	_path_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(_path_label)
	_mode = OptionButton.new()
	_mode.add_item("Latest commit → Working file", 0)
	_mode.add_item("Unstaged changes", 1)
	_mode.add_item("Staged changes", 2)
	_mode.tooltip_text = "Compare against HEAD, the staging area, or the working file"
	_mode.item_selected.connect(func(_index: int) -> void:
		if not diff_view.flush_working_editor():
			_mode.select(_shown_mode)
			return
		refresh()
	)
	toolbar.add_child(_mode)
	_layout = OptionButton.new()
	_layout.add_item("Side by side", 0)
	_layout.add_item("Unified", 1)
	_layout.tooltip_text = "Diff layout"
	_layout.select(0 if Settings.get_value("diff_side_by_side", true) else 1)
	_layout.item_selected.connect(func(index: int) -> void: diff_view.set_side_by_side(index == 0))
	toolbar.add_child(_layout)
	_open_button = Button.new()
	_open_button.text = "Open in Editor"
	_open_button.disabled = true
	_open_button.pressed.connect(_open_native)
	toolbar.add_child(_open_button)
	diff_view = DiffView.new()
	add_child(diff_view)
	diff_view.options_changed.connect(refresh)
	diff_view.layout_changed.connect(func(side_by_side: bool) -> void: _layout.select(0 if side_by_side else 1))
	diff_view.open_location_requested.connect(func(p: String, line: int) -> void:
		var error := EditorOpen.open_file_at_line(repo.get_repo_root(), p, line)
		if not error.is_empty():
			Dialogs.error(self, "Open File", error)
	)
	diff_view.hunk_action_requested.connect(_on_hunk_action)
	diff_view.working_file_saved.connect(_on_working_saved)


func set_repo(value: RefCounted) -> void:
	repo = value
	RepoWatcher.watch(self, _on_polled)


func open_path(value: String, line := 1) -> void:
	if not diff_view.flush_working_editor():
		return
	if not _comparison.is_empty():
		_mode.select(0)
	_comparison.clear()
	_mode.visible = true
	path = value
	refresh()
	diff_view.scroll_to_line.call_deferred(line)


func open_comparison(context: Dictionary) -> void:
	if not diff_view.flush_working_editor():
		return
	if context.get("kind", "") == "worktree":
		_mode.select(0)
		open_path(context["path"])
		return
	_comparison = context.duplicate(true)
	path = context["path"]
	_mode.visible = false
	refresh()
	diff_view.scroll_to_line.call_deferred(1)


func refresh() -> void:
	_layout.select(0 if Settings.get_value("diff_side_by_side", true) else 1)
	if repo == null or path.is_empty():
		return
	_path_label.text = path
	_path_label.tooltip_text = path
	var native_path := _native_path()
	var local := ProjectSettings.localize_path(repo.get_repo_root().path_join(native_path))
	_open_button.disabled = native_path.is_empty() or not FileAccess.file_exists(local) or not local.begins_with("res://") or not (local.get_extension() in ["tscn", "scn"] or ResourceLoader.exists(local))
	var options: Dictionary = diff_view.get_options()
	if not _comparison.is_empty():
		var context := _comparison.duplicate(true)
		context["repo"] = repo
		context["actions"] = []
		_path_label.text = "%s  @ %s" % [path, String(context["new_rev"]).substr(0, 8)]
		_path_label.tooltip_text = "%s\n%s → %s" % [path, context["old_rev"], context["new_rev"]]
		var historical: String = repo.get_commit_file_diff(context["oid"], path, options) if context["kind"] == "commit" else repo.get_diff_between(context["old_rev"], context["new_rev"], path, options)
		diff_view.show_diff(historical, context)
		_signature = ""
		return
	var mode := _mode.selected
	_shown_mode = mode
	var text := ""
	var context := {"path": path, "repo": repo, "new_rev": "", "old_rev": "HEAD", "actions": []}
	var has_head: bool = not repo.read_head_oid().is_empty()
	if mode == 0:
		text = repo.get_diff(path, false, options) if repo.is_untracked(path) or not has_head else repo.get_diff_between("HEAD", "", path, options)
		context["note"] = "latest commit → working file" if has_head and not repo.is_untracked(path) else "new file · all lines added"
	elif mode == 1:
		text = repo.get_diff(path, false, options)
		context["old_rev"] = ":"
		context["actions"] = ["stage", "revert"]
		context["note"] = "index → working file"
	else:
		text = repo.get_diff(path, true, options)
		context["new_rev"] = ":"
		context["actions"] = ["unstage", "revert"]
		context["note"] = "latest commit → index"
	context["editable_worktree"] = mode != 2
	diff_view.show_diff(text, context)
	_signature = _content_signature()


func _on_polled(_snapshot: Dictionary) -> void:
	if diff_view._working_view.is_dirty():
		return # The editor owns its live draft; polling must never replace it.
	if _comparison.is_empty() and is_visible_in_tree() and _signature != _content_signature():
		refresh()


func _content_signature() -> String:
	if repo == null or path.is_empty():
		return ""
	return "%s|%s|%s" % [repo.read_head_oid(), hash(repo.get_file_bytes("", path)), hash(repo.get_file_bytes(":", path))]


func _open_native() -> void:
	if not diff_view.flush_working_editor():
		return
	var native_path := _native_path()
	var local := ProjectSettings.localize_path(repo.get_repo_root().path_join(native_path))
	# A clean open scene may still have its old tree cached after raw-text edits.
	# Reload only on the explicit Open in Editor action; never discard a native draft.
	if _comparison.is_empty() and local.get_extension() in ["tscn", "scn"] and local in EditorInterface.get_open_scenes() and local not in EditorInterface.get_unsaved_scenes():
		EditorOpen.refresh_external_change(repo.get_repo_root(), native_path)
	var error := EditorOpen.open_file(repo.get_repo_root(), _native_path())
	if not error.is_empty():
		Dialogs.error(self, "Open File", error)


func _on_working_saved() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func() -> void:
		_refresh_queued = false
		if not is_queued_for_deletion():
			refresh()
	).call_deferred()
	if RepoWatcher.instance != null:
		RepoWatcher.instance.poll_now()


func _native_path() -> String:
	return path if _comparison.is_empty() else repo.current_path(_comparison["new_rev"], path)


func _on_hunk_action(action: String, patch: String) -> void:
	if not _comparison.is_empty():
		return # Historical comparisons never mutate the index or working file.
	if not await SaveGuard.ensure_saved(self, action.capitalize()):
		return
	# Auto-save may have changed the patch's baseline; git apply checks context and fails safely.
	var result: Dictionary
	match action:
		"stage":
			result = repo.apply_patch(patch, true, false)
		"unstage":
			result = repo.apply_patch(patch, true, true)
		"revert":
			if not await Dialogs.confirm(self, "Revert Changes", "Discard the selected changes from this file?", "Revert"):
				return
			result = repo.discard_staged_patch(patch) if _mode.selected == 2 else repo.apply_patch(patch, false, true)
			if result["ok"]:
				EditorOpen.refresh_external_change(repo.get_repo_root(), path)
		_:
			return
	if not result["ok"]:
		await Dialogs.error(self, "Couldn't %s" % action, result["error"])
	if RepoWatcher.instance != null:
		RepoWatcher.instance.poll_now()
	refresh()
