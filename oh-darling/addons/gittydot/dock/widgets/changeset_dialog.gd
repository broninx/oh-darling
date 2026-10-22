## Resizable window listing the files that differ between two revisions (base → target, target "" = working tree) with a diff of the selected one. Used for Compare branches, Show stash and Compare with working tree.
@tool
extends AcceptDialog

const DiffViewScript := preload("res://addons/gittydot/dock/widgets/diff_view.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")
const TreeFolders := preload("res://addons/gittydot/util/tree_folders.gd")
const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")

var _repo: RefCounted
var _base := ""
var _target := ""
var _tree: Tree
var _diff_view: Control
var _summary: Label


func _init() -> void:
	ok_button_text = "Close"
	exclusive = false
	unresizable = false
	min_size = UiScale.size_i(640, 400)

	var layout := VBoxContainer.new()
	add_child(layout)

	_summary = Label.new()
	_summary.modulate.a = 0.75
	_summary.clip_text = true
	layout.add_child(_summary)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -180
	layout.add_child(split)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = UiScale.size(220, 0)
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	split.add_child(_tree)

	_diff_view = DiffViewScript.new()
	_diff_view.custom_minimum_size = UiScale.size(320, 0)
	_diff_view.options_changed.connect(_on_item_selected)
	split.add_child(_diff_view)

	close_requested.connect(queue_free)
	confirmed.connect(queue_free)


## Pops the dialog up showing base → target. Caller adds it to the tree first.
func open(repo: RefCounted, dialog_title: String, base: String, target: String) -> void:
	_repo = repo
	_base = base
	_target = target
	title = dialog_title

	var files: Array = repo.get_changed_files_between(base, target)
	# Stash's untracked files aren't in stash^..stash; each entry carries its own revisions instead.
	var untracked_rev: String = repo.stash_untracked_rev(target) if target.begins_with("stash@{") else ""
	if not untracked_rev.is_empty():
		for f in repo.get_changed_files_between(repo.empty_tree_oid(), untracked_rev):
			f["base"] = repo.empty_tree_oid()
			f["target"] = untracked_rev
			f["untracked"] = true
			files.append(f)
	_summary.text = "%d file%s changed · %s → %s" % [files.size(), "" if files.size() == 1 else "s", base, target if not target.is_empty() else "working tree"]
	_tree.clear()
	var root := _tree.create_item()
	var folders := {}
	var first: TreeItem = null
	for f in files:
		var path: String = f["path"]
		var parent := TreeFolders.get_or_create_folder(_tree, root, folders, path.get_base_dir())
		var item := _tree.create_item(parent)
		item.set_text(0, "%s  %s" % [GitIcons.delta_letter(f["status"]), path.get_file()])
		item.set_custom_color(0, GitIcons.delta_color(f["status"]))
		item.set_tooltip_text(0, path + ("\n(renamed from %s)" % f["old_path"] if f.has("old_path") else "") + ("\n(untracked when stashed)" if f.get("untracked", false) else ""))
		item.set_metadata(0, { "path": path, "status": f["status"], "base": f.get("base", base), "target": f.get("target", target) })
		if first == null:
			first = item
	if files.is_empty():
		var empty := _tree.create_item(root)
		empty.set_text(0, "(no differences)")
		empty.set_selectable(0, false)

	var screen_size := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	popup_centered(Vector2i(mini(int(UiScale.px(1100)), int(screen_size.x * 0.8)), mini(int(UiScale.px(720)), int(screen_size.y * 0.8))))
	if first != null:
		first.select(0)


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item == null or _repo == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not meta is Dictionary:
		return
	var path: String = meta["path"]
	var base: String = meta.get("base", _base)
	var target: String = meta.get("target", _target)
	_diff_view.show_diff(_repo.get_diff_between(base, target, path, _diff_view.get_options()), {
		"repo": _repo, "path": path, "old_rev": base, "new_rev": target,
	})


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		var path: String = _repo.current_path(_target if not _target.is_empty() else _base, meta["path"])
		if not path.is_empty():
			EditorOpen.open_file(_repo.get_repo_root(), path)
