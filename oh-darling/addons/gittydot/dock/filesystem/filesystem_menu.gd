## "Git: …" items in the FileSystem dock's right-click menu: history, the change in the Changes panel, revert, add and ignore. Plain items rather than a submenu, for the reason given in script_menu.gd.
extends EditorContextMenuPlugin

const GitStatusFlags := preload("res://addons/gittydot/util/git_status_flags.gd")

## Set by plugin.gd: filesystem_colors.gd (holds the latest status) and the Git dock (runs the actions).
var colors: Node
var dock: Control
## Called with a repo-relative path; plugin.gd points them at the Git Log and the Changes panel.
var show_file_history: Callable
var show_change: Callable


func _popup_menu(paths: PackedStringArray) -> void:
	if colors == null or colors.repo == null:
		return
	colors.refresh()
	var files := _repo_paths(paths, false)
	var changed := _changed_under(paths)
	var untracked := changed.filter(func(p: String) -> bool: return GitStatusFlags.is_untracked(colors.status_by_path[p]))
	if files.size() == 1 and paths.size() == 1:
		if not untracked.has(files[0]):
			add_context_menu_item("Git: Show History", func(_p: Variant) -> void: show_file_history.call(files[0]))
		if changed.has(files[0]):
			add_context_menu_item("Git: Show Change", func(_p: Variant) -> void: show_change.call(files[0]))
	if not untracked.is_empty():
		add_context_menu_item("Git: Add %s to Git" % _count(untracked), func(_p: Variant) -> void: dock.add_paths(untracked))
	var ignore_targets := _ignore_targets(paths)
	if not ignore_targets.is_empty():
		var label := "Git: Add Folder to .gitignore" if ignore_targets.size() == 1 and String(ignore_targets[0]).ends_with("/") else ("Git: Add to .gitignore" if ignore_targets.size() == 1 else "Git: Add %d Paths to .gitignore" % ignore_targets.size())
		add_context_menu_item(label, func(_p: Variant) -> void: dock.ignore_paths(ignore_targets))
	if not changed.is_empty():
		add_context_menu_item("Git: Revert %s…" % _count(changed), func(_p: Variant) -> void: dock.revert_paths(changed))


## Repo-relative paths of the selected res:// files (folders too when with_folders, without their trailing "/").
func _repo_paths(paths: PackedStringArray, with_folders: bool) -> Array:
	var root: String = colors.repo.get_repo_root() + "/"
	var out: Array = []
	for path in paths:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)) and not with_folders:
			continue
		var abs_path := ProjectSettings.globalize_path(path).trim_suffix("/")
		if abs_path.begins_with(root):
			out.append(abs_path.substr(root.length()))
	return out


func _ignore_targets(paths: PackedStringArray) -> Array:
	var selected := _repo_paths(paths, true)
	var root: String = colors.repo.get_repo_root()
	var out := []
	for path: String in selected:
		out.append(path + "/" if DirAccess.dir_exists_absolute(root.path_join(path)) else path)
	return out


## Changed repo paths that are selected or inside a selected folder (the whole repo for res://).
func _changed_under(paths: PackedStringArray) -> Array:
	var selected := _repo_paths(paths, true)
	var whole_repo: bool = paths.has("res://") and colors.repo.get_repo_root() + "/" == ProjectSettings.globalize_path("res://")
	var out: Array = []
	for path in colors.status_by_path:
		if colors.status_by_path[path] & GitStatusFlags.CONFLICTED:
			continue
		if whole_repo or selected.any(func(s: String) -> bool: return path == s or path.begins_with(s + "/")):
			out.append(path)
	return out


static func _count(paths: Array) -> String:
	return "\"%s\"" % paths[0].get_file() if paths.size() == 1 else "%d Files" % paths.size()
