## "Git: …" items in the script editor's right-click menu: preview/rollback the change at the caret, the commit behind the caret's line, file history, and the blame toggle. Plain items rather than a submenu: a PopupMenu handed to add_context_submenu_item() gets parented into the editor's menu, and freeing it on plugin reload left the editor with a dangling submenu that crashed on the next right-click.
extends EditorContextMenuPlugin

const WebLinks := preload("res://addons/gittydot/util/web_links.gd")

## Set by plugin.gd.
var diff_gutter: Node
var blame_gutter: Node
## Called with an oid / a repo-relative path; plugin.gd points them at the Git Log.
var show_commit: Callable
var show_file_history: Callable


func _popup_menu(paths: PackedStringArray) -> void:
	for item: Array in _items(_code_edit_from(paths)):
		add_context_menu_item(item[0], item[1])


## [label, callback(target)] for code_edit's menu; empty when it isn't a file inside the repo.
func _items(code_edit: CodeEdit) -> Array:
	if code_edit == null or not code_edit.has_meta(diff_gutter.META_REL_PATH):
		return []
	var items: Array = []
	if diff_gutter.region_at_line(code_edit, code_edit.get_caret_line()) != -1:
		items.append(["Git: Preview Change", _on_preview])
		items.append(["Git: Rollback Change", _on_rollback])
		items.append(["Git: Show Change in Changes Panel", _on_show_in_changes])
	items.append(["Git: Show Commit for This Line", _on_line_commit])
	items.append(["Git: Show History of This File", _on_file_history])
	var resolved: Dictionary = diff_gutter.resolve_repo(code_edit.get_meta(diff_gutter.META_RES_PATH, ""))
	if not resolved.is_empty():
		var site := WebLinks.site(resolved["repo"])
		if not site.is_empty():
			items.append(["Git: Open Line on %s" % site["name"], _on_open_on_web])
	items.append(["Git: Hide Blame" if blame_gutter.is_enabled() else "Git: Show Blame", _on_toggle_blame])
	return items


## Text file tabs (.md, .json...) don't ask context menu plugins, so the same items go straight into their menu as it opens.
func hook_text_editor(editor: Control, code_edit: CodeEdit) -> void:
	var menus := editor.get_children().filter(func(n: Node) -> bool: return n is PopupMenu)
	if menus.is_empty():
		return
	var menu: PopupMenu = menus[0]
	if menu.has_meta(META_HOOKED):
		return
	menu.set_meta(META_HOOKED, true)
	var on_popup := _fill_text_menu.bind(menu, code_edit)
	menu.about_to_popup.connect(on_popup)
	var on_id := _on_text_menu_id.bind(code_edit)
	menu.id_pressed.connect(on_id)
	_text_menu_connections.append([menu, on_popup, on_id])


const META_HOOKED := &"godit_menu_hooked"
## Our items' ids in a text tab's menu start here, clear of the editor's own.
const TEXT_MENU_ID_BASE := 77000
## [PopupMenu, about_to_popup callable, id_pressed callable], for unhook_text_editors().
var _text_menu_connections: Array = []
## Callbacks of the items last added to a text tab's menu, by id - TEXT_MENU_ID_BASE.
var _text_menu_actions: Array = []


func _fill_text_menu(menu: PopupMenu, code_edit: CodeEdit) -> void:
	var items := _items(code_edit)
	_text_menu_actions = items.map(func(item: Array) -> Callable: return item[1])
	if items.is_empty():
		return
	menu.add_separator()
	for i in items.size():
		menu.add_item(items[i][0], TEXT_MENU_ID_BASE + i)


func _on_text_menu_id(id: int, code_edit: CodeEdit) -> void:
	var index := id - TEXT_MENU_ID_BASE
	if index >= 0 and index < _text_menu_actions.size():
		_text_menu_actions[index].call(code_edit)


## Called by plugin.gd on disable: the text tabs outlive the plugin.
func unhook_text_editors() -> void:
	for entry: Array in _text_menu_connections:
		var menu: PopupMenu = entry[0]
		if is_instance_valid(menu):
			menu.remove_meta(META_HOOKED)
			menu.about_to_popup.disconnect(entry[1])
			menu.id_pressed.disconnect(entry[2])
	_text_menu_connections.clear()


## The callback gets the CodeEdit itself; _popup_menu() gets its node path.
static func _code_edit_from(target: Variant) -> CodeEdit:
	if target is CodeEdit:
		return target
	if (target is PackedStringArray or target is Array) and not target.is_empty():
		return Engine.get_main_loop().root.get_node_or_null(NodePath(str(target[0]))) as CodeEdit
	return null


func _on_preview(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit != null:
		diff_gutter.show_preview(code_edit, diff_gutter.region_at_line(code_edit, code_edit.get_caret_line()))


func _on_rollback(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit != null:
		diff_gutter.rollback(code_edit, diff_gutter.region_at_line(code_edit, code_edit.get_caret_line()))


func _on_show_in_changes(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit != null:
		diff_gutter.change_clicked.emit(code_edit.get_meta(diff_gutter.META_REL_PATH, ""), code_edit.get_caret_line() + 1)


func _on_line_commit(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit == null:
		return
	var oid: String = await blame_gutter.commit_at(code_edit.get_meta(diff_gutter.META_RES_PATH, ""), code_edit, code_edit.get_caret_line())
	if oid.is_empty():
		EditorInterface.get_editor_toaster().push_toast("Git: this line isn't committed yet.")
	else:
		show_commit.call(oid)


func _on_file_history(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit != null:
		show_file_history.call(code_edit.get_meta(diff_gutter.META_REL_PATH, ""))


## The caret's line in the last pushed version of the file (lines may be off by your unpushed edits).
func _on_open_on_web(target: Variant) -> void:
	var code_edit := _code_edit_from(target)
	if code_edit == null:
		return
	var resolved: Dictionary = diff_gutter.resolve_repo(code_edit.get_meta(diff_gutter.META_RES_PATH, ""))
	var repo: RefCounted = resolved["repo"]
	var ref := WebLinks.pushed_base(repo)
	if ref.is_empty():
		EditorInterface.get_editor_toaster().push_toast("Git: this branch isn't pushed yet, so there's nothing to open.")
		return
	OS.shell_open(WebLinks.file_url(WebLinks.site(repo), ref, resolved["rel_path"], code_edit.get_caret_line() + 1))


func _on_toggle_blame(_target: Variant) -> void:
	blame_gutter.toggle_requested.emit(not blame_gutter.is_enabled())
