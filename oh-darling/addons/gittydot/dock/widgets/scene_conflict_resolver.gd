## Merge-conflict dialog for a .tscn/.tres: merges both sides node by node (scene_merge.gd) and asks only about the properties or nodes both sides changed differently.
@tool
extends ConfirmationDialog

const SceneMerge := preload("res://addons/gittydot/util/scene_merge.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")

## Emitted after the file was saved; marked is true when it was also `git add`-ed.
signal saved(path: String, marked: bool)
## "Edit as Text" was pressed: the owner should open the line-based resolver instead.
signal text_mode_requested(path: String)

const COLOR_OURS := Color(0.55, 0.7, 1.0)
const COLOR_THEIRS := Color(0.55, 0.9, 0.6)
const VALUE_MAX := 90

var _repo: RefCounted
var _path := ""
var _result: Dictionary = {}
## Conflict id -> "ours" | "theirs".
var _choices := {}
var _tree: Tree
var _status_label: Label
## In a rebase the sides swap: "ours" is the branch being rebased onto, "theirs" the commit being replayed.
var _rebasing := false


func _init() -> void:
	title = "Resolve Scene Conflicts"
	ok_button_text = "Save and Mark Resolved"
	unresizable = false
	exclusive = false
	min_size = UiScale.size_i(720, 420)
	add_button("Edit as Text…", false, "text")
	confirmed.connect(_save)
	custom_action.connect(func(action: StringName) -> void:
		if action == &"text":
			hide()
			text_mode_requested.emit(_path)
	)
	visibility_changed.connect(func() -> void:
		if not visible:
			queue_free.call_deferred()
	)


## Merges the index's base/ours/theirs versions of path and pops the dialog up; false (with error) if they can't be merged this way.
func open(repo: RefCounted, path: String) -> Dictionary:
	_repo = repo
	_path = path
	_rebasing = repo.get_operation_state()["kind"] == "rebase"
	var text := func(stage: String) -> String: return repo.get_file_bytes(stage, path).get_string_from_utf8()
	_result = SceneMerge.merge(text.call(":1"), text.call(":2"), text.call(":3"))
	if not _result["ok"]:
		return _result
	title = "Resolve Scene Conflicts — %s" % path
	_build()
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	popup_centered(Vector2i(mini(int(UiScale.px(1000)), int(screen.x * 0.85)), mini(int(UiScale.px(640)), int(screen.y * 0.85))))
	_update_status()
	return { "ok": true }


func _build() -> void:
	var layout := VBoxContainer.new()
	add_child(layout)
	var conflicts: Array = _result["conflicts"]
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "%d change%s merged on their own. %s" % [_result["auto"].size(), "" if _result["auto"].size() == 1 else "s",
			"Pick a side for each of the %d conflict%s below (click a value)." % [conflicts.size(), "" if conflicts.size() == 1 else "s"] if not conflicts.is_empty() else "Nothing left to decide."]
	layout.add_child(intro)

	var buttons := HBoxContainer.new()
	for side in ["ours", "theirs"]:
		var b := Button.new()
		b.text = ("Take All Ours (%s)" % _ours_label()) if side == "ours" else ("Take All Theirs (%s)" % _theirs_label())
		b.disabled = conflicts.is_empty()
		b.pressed.connect(func() -> void:
			for c in conflicts:
				_choices[c["id"]] = side
			_refresh_rows()
		)
		buttons.add_child(b)
	layout.add_child(buttons)

	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Node / property")
	_tree.set_column_title(1, "Ours (%s)" % _ours_label())
	_tree.set_column_title(2, "Theirs (%s)" % _theirs_label())
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_edited.connect(_on_item_edited)
	layout.add_child(_tree)
	var root := _tree.create_item()
	for c in conflicts:
		var item := _tree.create_item(root)
		item.set_text(0, c["label"] + (": " + String(c["prop"]).trim_prefix("(").trim_suffix(")") if not c["prop"].is_empty() else "  (whole node)"))
		item.set_metadata(0, c["id"])
		for col in [1, 2]:
			var side := "ours" if col == 1 else "theirs"
			var value: Variant = c[side]
			item.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
			item.set_editable(col, true)
			item.set_text(col, _short(value))
			item.set_tooltip_text(col, "deleted" if value == null else String(value))
			item.set_custom_color(col, COLOR_OURS if col == 1 else COLOR_THEIRS)
	if not _result["auto"].is_empty():
		var auto := _tree.create_item(root)
		auto.set_text(0, "Merged automatically (%d)" % _result["auto"].size())
		auto.set_custom_color(0, Color(1, 1, 1, 0.6))
		auto.collapsed = not conflicts.is_empty()
		for line in _result["auto"]:
			var item := _tree.create_item(auto)
			item.set_text(0, line)
			item.set_custom_color(0, Color(1, 1, 1, 0.6))

	_status_label = Label.new()
	layout.add_child(_status_label)


func _ours_label() -> String:
	return "branch rebased onto" if _rebasing else "current branch"


func _theirs_label() -> String:
	return "your commit being replayed" if _rebasing else "incoming"


static func _short(value: Variant) -> String:
	if value == null:
		return "(deleted)"
	var text := String(value).replace("\n", " ⏎ ")
	return text if text.length() <= VALUE_MAX else text.left(VALUE_MAX) + "…"


## A side's checkbox was clicked: it becomes that conflict's choice, the other side unticks.
func _on_item_edited() -> void:
	var item := _tree.get_edited()
	var id: Variant = item.get_metadata(0)
	if id == null:
		return
	_choices[id] = "ours" if _tree.get_edited_column() == 1 else "theirs"
	_refresh_rows()


func _refresh_rows() -> void:
	for item in _tree.get_root().get_children():
		var id: Variant = item.get_metadata(0)
		if id == null:
			continue
		item.set_checked(1, _choices.get(id, "") == "ours")
		item.set_checked(2, _choices.get(id, "") == "theirs")
	_update_status()


func _update_status() -> void:
	var left: int = _result["conflicts"].size() - _choices.size()
	_status_label.text = "%d conflict%s still to decide" % [left, "" if left == 1 else "s"] if left > 0 else "Ready — save to write the merged file."
	get_ok_button().disabled = left > 0


func _save() -> void:
	var file := FileAccess.open(_repo.get_repo_root().path_join(_path), FileAccess.WRITE)
	if file == null:
		EditorInterface.get_editor_toaster().push_toast("GittyDot: couldn't write %s" % _path, EditorToaster.SEVERITY_ERROR)
		return
	file.store_string(SceneMerge.result_text(_result, _choices))
	file.close()
	var marked: bool = _repo.mark_resolved(_path)["ok"]
	EditorOpen.refresh_external_change(_repo.get_repo_root(), _path)
	saved.emit(_path, marked)
