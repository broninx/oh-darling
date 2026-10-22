@tool
extends EditorPlugin

const DockScene := preload("res://addons/gittydot/dock/godit_dock.tscn")
const HistoryScene := preload("res://addons/gittydot/dock/godit_history_dock.tscn")
const DiffGutter := preload("res://addons/gittydot/dock/gutter/diff_gutter.gd")
const BlameGutter := preload("res://addons/gittydot/dock/gutter/blame_gutter.gd")
const ScriptMenu := preload("res://addons/gittydot/dock/gutter/script_menu.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")
const GitCli := preload("res://addons/gittydot/util/git_cli.gd")
const FilesystemColors := preload("res://addons/gittydot/dock/filesystem/filesystem_colors.gd")
const FilesystemMenu := preload("res://addons/gittydot/dock/filesystem/filesystem_menu.gd")
const RepoWatcher := preload("res://addons/gittydot/util/repo_watcher.gd")
const ScriptAutosave := preload("res://addons/gittydot/util/script_autosave.gd")
const MainScreen := preload("res://addons/gittydot/dock/gittydot_screen.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const WorkingDiff := preload("res://addons/gittydot/dock/widgets/working_diff.gd")
const PluginIconPath := "res://addons/gittydot/icon.png"

var dock_instance: Control
var history_dock_instance: Control
var main_screen: Control
var diff_gutter: Node
var blame_gutter: Node
var filesystem_colors: Node
var watcher: Node
var autosave: Node
var script_menu: EditorContextMenuPlugin
var filesystem_menu: EditorContextMenuPlugin
var tools_menu: PopupMenu
var _poll_queued := false


func _enter_tree() -> void:
	GitCli.prepare_environment()
	watcher = RepoWatcher.new()
	add_child(watcher)
	main_screen = MainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(main_screen)
	main_screen.hide()

	dock_instance = DockScene.instantiate()
	dock_instance.plugin = self
	dock_instance.name = "Commit"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, dock_instance)
	dock_instance._tab_container.set_tab_title(0, "Commit")
	dock_instance._changes_panel.diff_requested.connect(_show_main_diff)
	if dock_instance.has_repo():
		main_screen.set_repo(dock_instance._repo)

	history_dock_instance = HistoryScene.instantiate()
	history_dock_instance.custom_minimum_size.y = 260 * EditorInterface.get_editor_scale()
	add_control_to_bottom_panel(history_dock_instance, "Git Log")
	Dialogs.reveal_console = _show_console

	diff_gutter = DiffGutter.new()
	add_child(diff_gutter)
	diff_gutter.enable(self)
	diff_gutter.change_clicked.connect(_show_main_diff)
	blame_gutter = BlameGutter.new()
	add_child(blame_gutter)
	blame_gutter.set_enabled(Settings.get_value("show_blame", false))
	blame_gutter.commit_clicked.connect(_show_commit)
	blame_gutter.toggle_requested.connect(_set_blame_enabled)
	script_menu = ScriptMenu.new()
	script_menu.diff_gutter = diff_gutter
	script_menu.blame_gutter = blame_gutter
	script_menu.show_commit = _show_commit
	script_menu.show_file_history = _show_file_history
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, script_menu)
	diff_gutter.text_tab_refreshed.connect(script_menu.hook_text_editor)
	dock_instance.file_history_requested.connect(_show_file_history)

	filesystem_colors = FilesystemColors.new()
	add_child(filesystem_colors)
	filesystem_menu = FilesystemMenu.new()
	filesystem_menu.colors = filesystem_colors
	filesystem_menu.dock = dock_instance
	filesystem_menu.show_file_history = _show_file_history
	filesystem_menu.show_change = _show_main_diff
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, filesystem_menu)
	history_dock_instance.changes_requested.connect(_show_changes)
	_connect_history_diff()
	EditorOpen.open_raw_file = _show_main_diff

	tools_menu = PopupMenu.new()
	tools_menu.add_check_item("Auto-save scripts and working-file comparisons (350 ms)", 0)
	tools_menu.set_item_checked(0, Settings.get_value("auto_save_scripts", true))
	tools_menu.add_check_item("Show blame in the script editor", 1)
	tools_menu.set_item_checked(1, Settings.get_value("show_blame", false))
	tools_menu.add_check_item("Fetch remotes in the background", 2)
	tools_menu.set_item_checked(2, Settings.get_value("auto_fetch", false))
	tools_menu.add_separator()
	tools_menu.add_item("Open Commit", 3)
	tools_menu.add_item("Open Git Log", 4)
	tools_menu.id_pressed.connect(_on_tool)
	add_tool_submenu_item("GittyDot", tools_menu)

	autosave = ScriptAutosave.new()
	add_child(autosave)
	autosave.scripts_saved.connect(_queue_poll)
	resource_saved.connect(_on_resource_saved)
	scene_saved.connect(_on_scene_saved)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_queue_poll)


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "GittyDot"


func _get_plugin_icon() -> Texture2D:
	# Keep the full-resolution artwork while sizing its toolbar texture for editor DPI.
	var image: Image
	if ResourceLoader.exists(PluginIconPath, "Texture2D"):
		var texture := load(PluginIconPath) as Texture2D
		if texture != null:
			image = texture.get_image()
	# On first installation the PNG importer may not have run yet. Decode the
	# packaged editor-only artwork without Image.load_from_file's export warning.
	if image == null and FileAccess.file_exists(PluginIconPath):
		image = Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(PluginIconPath)) != OK:
			image = null
	if image == null or image.is_empty():
		return EditorInterface.get_base_control().get_theme_icon("VCSBranches", "EditorIcons")
	if image.is_compressed():
		image.decompress()
	var side := maxi(1, roundi(16 * EditorInterface.get_editor_scale()))
	image.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _make_visible(value: bool) -> void:
	if is_instance_valid(main_screen):
		main_screen.visible = value


func _show_main_diff(path: String, line := 1) -> void:
	if not dock_instance.has_repo():
		return
	if main_screen.repo == null:
		main_screen.set_repo(dock_instance._repo)
	main_screen.open_path(path, line)
	EditorInterface.set_main_screen_editor("GittyDot")


func _connect_history_diff() -> void:
	if not is_instance_valid(history_dock_instance):
		return
	var history: Control = history_dock_instance._history_panel
	# Also bind after source reloads, without rebuilding editor docks or buffers.
	if history.has_signal("diff_requested") and not history.is_connected("diff_requested", _show_history_diff):
		history.connect("diff_requested", _show_history_diff)
	if history.has_signal("amend_requested") and not history.is_connected("amend_requested", _prepare_amend):
		history.connect("amend_requested", _prepare_amend)
	if not dock_instance._changes_panel.is_connected("amend_log_requested", _show_amend_log):
		dock_instance._changes_panel.connect("amend_log_requested", _show_amend_log)


func _prepare_amend(oid: String) -> void:
	_reveal_commit()
	dock_instance.show_changes("")
	dock_instance._changes_panel.prepare_amend(oid)


func _show_amend_log() -> void:
	make_bottom_panel_item_visible(history_dock_instance)
	history_dock_instance.show_commit(dock_instance._repo.get_head_oid())


func _show_console(entry_id: int) -> void:
	make_bottom_panel_item_visible(history_dock_instance)
	history_dock_instance.show_console(entry_id)


func _show_history_diff(context: Dictionary) -> void:
	if not dock_instance.has_repo():
		return
	main_screen.open_comparison(context)
	EditorInterface.set_main_screen_editor("GittyDot")


func _show_commit(oid: String) -> void:
	make_bottom_panel_item_visible(history_dock_instance)
	history_dock_instance.show_commit(oid)


func _show_file_history(path: String) -> void:
	make_bottom_panel_item_visible(history_dock_instance)
	history_dock_instance.show_file_history(path)


func _set_blame_enabled(value: bool) -> void:
	Settings.set_value("show_blame", value)
	tools_menu.set_item_checked(1, value)
	blame_gutter.set_enabled(value)


func _show_changes(action: String) -> void:
	_reveal_commit()
	dock_instance.show_changes(action)


func _reveal_commit() -> void:
	var parent := dock_instance.get_parent()
	while parent != null:
		if parent.is_class("EditorDock"):
			parent.call("open")
			parent.call("make_visible")
			return
		if parent is TabContainer:
			parent.current_tab = dock_instance.get_index()
			return
		parent = parent.get_parent()


func _on_tool(id: int) -> void:
	match id:
		0:
			var value := not tools_menu.is_item_checked(0)
			tools_menu.set_item_checked(0, value)
			Settings.set_value("auto_save_scripts", value)
			autosave.set_enabled(value)
			WorkingDiff.apply_auto_save_policy()
		1:
			_set_blame_enabled(not tools_menu.is_item_checked(1))
		2:
			var value := not tools_menu.is_item_checked(2)
			tools_menu.set_item_checked(2, value)
			Settings.set_value("auto_fetch", value)
			dock_instance.apply_auto_fetch_setting()
		3:
			_reveal_commit()
		4:
			make_bottom_panel_item_visible(history_dock_instance)


func _on_resource_saved(_resource: Resource) -> void:
	_queue_poll()


func _on_scene_saved(_path: String) -> void:
	_queue_poll()


func _queue_poll() -> void:
	_connect_history_diff()
	if _poll_queued:
		return
	_poll_queued = true
	(func() -> void:
		_poll_queued = false
		if is_instance_valid(watcher):
			watcher.poll_now()
	).call_deferred()


func _exit_tree() -> void:
	# Disconnect first: no callback may save/repaint while the controls are being destroyed.
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_queue_poll)
	resource_saved.disconnect(_on_resource_saved)
	scene_saved.disconnect(_on_scene_saved)
	EditorOpen.open_raw_file = Callable()
	Dialogs.reveal_console = Callable()
	autosave.free()
	GitCli.shutdown()
	diff_gutter.disable()
	script_menu.unhook_text_editors()
	remove_context_menu_plugin(script_menu)
	remove_context_menu_plugin(filesystem_menu)
	filesystem_colors.free()
	blame_gutter.disable()
	diff_gutter.free()
	blame_gutter.free()
	remove_control_from_docks(dock_instance)
	dock_instance.free()
	remove_control_from_bottom_panel(history_dock_instance)
	history_dock_instance.free()
	main_screen.queue_free()
	watcher.free()
	remove_tool_menu_item("GittyDot")
	# remove_tool_menu_item frees the registered submenu in Godot 4.7.
	GitCli.restore_environment()
