## Colors changed, new and conflicted files in the editor's FileSystem dock by their git status, and folders that contain any.
@tool
extends Node

const RepoOpener := preload("res://addons/gittydot/util/repo_opener.gd")
const GitStatusFlags := preload("res://addons/gittydot/util/git_status_flags.gd")
const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const RepoWatcher := preload("res://addons/gittydot/util/repo_watcher.gd")

## Untracked files in the dock: grey would read as "disabled" there, so they get the usual "unversioned" red-brown.
const COLOR_UNTRACKED := Color(0.45, 0.82, 0.52)
const COLOR_CONFLICTED := Color(1.0, 0.4, 0.4)
## Folders get their strongest child's color, faded toward the normal text.
const FOLDER_FADE := 0.35
const META_ORIGINAL := &"godit_original_color"
const META_SUFFIX := &"gittydot_original_suffix"

## Null when the project isn't in a git repo.
var repo: RefCounted
var _tree: Tree
## The file list shown next to the tree in the dock's split mode.
var _list: ItemList
## res:// paths the file list currently shows in a git color, to restore when they're no longer changed.
var _list_colored := {}
var _list_paint_queued := false
## res:// path (folders end in "/") -> Color, from the last status.
var _colors := {}
var _badges := {}
## Repo-relative path -> status bits, from the last status (read by filesystem_menu.gd).
var status_by_path := {}
var _signature := ""
## The FileSystem dock rebuilds its whole Tree on rescans and searches; a new root item means the colors are gone.
var _painted_root: TreeItem


func _ready() -> void:
	repo = RepoOpener.open_current_project_repo()["repo"]
	if repo == null:
		return
	var dock := EditorInterface.get_file_system_dock()
	var trees := dock.find_children("*", "Tree", true, false)
	if trees.is_empty():
		return
	_tree = trees[0]
	_tree.draw.connect(_on_tree_draw)
	_tree.item_collapsed.connect(func(_item: TreeItem) -> void: _paint.call_deferred())
	var lists := dock.find_children("*", "ItemList", true, false)
	if not lists.is_empty():
		_list = lists[0]
		_list.draw.connect(_queue_list_paint)
	RepoWatcher.watch(self, _on_polled)
	refresh()


func _exit_tree() -> void:
	_colors = {}
	_badges = {}
	if _tree != null and is_instance_valid(_tree):
		_tree.draw.disconnect(_on_tree_draw)
		_paint()
	if _list != null and is_instance_valid(_list):
		_list.draw.disconnect(_queue_list_paint)
		_paint_list()


func _on_polled(snapshot: Dictionary) -> void:
	refresh(repo.parse_status(snapshot["status"]))


## Repaints if the status (entries, else a fresh `git status`) changed.
func refresh(entries: Variant = null) -> void:
	if repo == null or _tree == null:
		return
	if entries == null:
		entries = repo.get_status()
	var signature := str(entries.map(func(e: Dictionary) -> String: return "%s:%d" % [e["path"], e["status"]]))
	if signature == _signature:
		return
	_signature = signature
	status_by_path = {}
	_colors = {}
	_badges = {}
	var project_root := ProjectSettings.globalize_path("res://")
	var folder_rank := {}
	for entry in entries:
		var status: int = entry["status"]
		if status & GitStatusFlags.IGNORED:
			continue
		status_by_path[entry["path"]] = status
		var abs_path: String = repo.get_repo_root().path_join(entry["path"])
		if not abs_path.begins_with(project_root):
			continue
		var res_path := "res://" + abs_path.substr(project_root.length())
		var color := color_for(status)
		_colors[res_path] = color
		_badges[res_path] = status_badge(status)
		# Conflicts outrank changes, which outrank new files, in the folder's color.
		var rank := 3 if status & GitStatusFlags.CONFLICTED else (1 if GitStatusFlags.is_untracked(status) else 2)
		var dir := res_path.get_base_dir()
		while dir.length() > "res://".length():
			var key := dir + "/"
			if rank > folder_rank.get(key, 0):
				folder_rank[key] = rank
				_colors[key] = color.lerp(GitIcons.COLOR_DEFAULT, FOLDER_FADE)
			dir = dir.get_base_dir()
	_paint()


static func color_for(status: int) -> Color:
	if status & GitStatusFlags.CONFLICTED:
		return COLOR_CONFLICTED
	if GitStatusFlags.is_untracked(status):
		return COLOR_UNTRACKED
	return GitIcons.status_color(status)


func _on_tree_draw() -> void:
	if _tree.get_root() != _painted_root:
		_painted_root = _tree.get_root()
		_paint.call_deferred()


## Applies _colors to every row, restoring rows that were colored before but aren't changed any more.
func _paint() -> void:
	if _tree == null or not is_instance_valid(_tree) or _tree.get_root() == null:
		return
	_painted_root = _tree.get_root()
	_queue_list_paint()
	var stack: Array[TreeItem] = [_tree.get_root()]
	while not stack.is_empty():
		var item: TreeItem = stack.pop_back()
		var path: Variant = item.get_metadata(0)
		if path is String:
			var badge: String = _badges.get(path, "")
			if not badge.is_empty():
				if not item.has_meta(META_SUFFIX):
					item.set_meta(META_SUFFIX, item.get_suffix(0))
				item.set_suffix(0, "  " + badge)
			elif item.has_meta(META_SUFFIX):
				item.set_suffix(0, item.get_meta(META_SUFFIX))
				item.remove_meta(META_SUFFIX)
			var color: Variant = _colors.get(path)
			if color != null:
				if not item.has_meta(META_ORIGINAL):
					item.set_meta(META_ORIGINAL, item.get_custom_color(0))
				if item.get_custom_color(0) != color:
					item.set_custom_color(0, color)
			elif item.has_meta(META_ORIGINAL):
				var original: Color = item.get_meta(META_ORIGINAL)
				if original == Color(): # the getter's value for "no custom color"
					item.clear_custom_color(0)
				else:
					item.set_custom_color(0, original)
				item.remove_meta(META_ORIGINAL)
		var child := item.get_first_child()
		while child != null:
			stack.append(child)
			child = child.get_next()


## The list is refilled on every folder change and has no per-item slot to mark, so each redraw re-checks its (one folder's worth of) items.
func _queue_list_paint() -> void:
	if _list_paint_queued or _list == null or not _list.is_visible_in_tree():
		return
	_list_paint_queued = true
	(func() -> void:
		_list_paint_queued = false
		_paint_list()
	).call_deferred()


func _paint_list() -> void:
	if _list == null or not is_instance_valid(_list):
		return
	for i in _list.item_count:
		var path: Variant = _list.get_item_metadata(i)
		if not path is String:
			continue
		var color: Variant = _colors.get(path, _colors.get(path + "/"))
		var text := _list.get_item_text(i)
		var prior: Dictionary = _list_colored.get(path, {})
		if not prior.is_empty() and text == prior.get("painted", ""):
			text = prior["base"]
		var badge: String = _badges.get(path, "")
		var painted := text + ("  [" + badge + "]" if not badge.is_empty() else "")
		if _list.get_item_text(i) != painted:
			_list.set_item_text(i, painted)
		if color != null:
			_list_colored[path] = {"base": text, "painted": painted}
			if _list.get_item_custom_fg_color(i) != color:
				_list.set_item_custom_fg_color(i, color)
		elif _list_colored.has(path):
			_list_colored.erase(path)
			_list.set_item_custom_fg_color(i, Color()) # Color() = no custom color


static func status_badge(status: int) -> String:
	if status & GitStatusFlags.CONFLICTED:
		return "!"
	if status & (GitStatusFlags.WT_DELETED | GitStatusFlags.INDEX_DELETED):
		return "D"
	if status & (GitStatusFlags.WT_NEW | GitStatusFlags.INDEX_NEW):
		return "A"
	if status & (GitStatusFlags.WT_RENAMED | GitStatusFlags.INDEX_RENAMED):
		return "R"
	return "M"
