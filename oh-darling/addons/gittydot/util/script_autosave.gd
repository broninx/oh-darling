@tool
extends Node
## Native ScriptEditor saves keep undo history, resource source, and saved markers in sync.
## A short debounce avoids writing a half keystroke sequence on every text_changed signal.

signal scripts_saved
signal save_blocked(path: String)

const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")
const DELAY := 0.35
static var instance: Node

var enabled := true
var _timer: Timer
var _tabs := {}
var _discovery_elapsed := 0.0
var _saving := false
var _announced := {}


func _ready() -> void:
	instance = self
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DELAY
	_timer.timeout.connect(flush_pending)
	add_child(_timer)
	set_enabled(Settings.get_value("auto_save_scripts", true))
	discover_tabs()


func set_enabled(value: bool) -> void:
	enabled = value
	if _timer == null:
		return
	if enabled:
		discover_tabs()
		_timer.start()
	else:
		_timer.stop()


func _process(delta: float) -> void:
	_discovery_elapsed += delta
	if _discovery_elapsed >= 0.1:
		_discovery_elapsed = 0.0
		discover_tabs()


func discover_tabs() -> void:
	var editor := EditorInterface.get_script_editor()
	if editor == null:
		return
	var present := {}
	for tab: Dictionary in EditorOpen._open_tabs(editor):
		var path: String = tab["path"]
		var code := (tab["editor"] as ScriptEditorBase).get_base_editor() as CodeEdit
		if code == null or not path.begins_with("res://") or path.contains("::"):
			continue
		var id := code.get_instance_id()
		present[id] = true
		if not _tabs.has(id) or _tabs[id]["path"] != path:
			_disconnect_tab(id)
			var callback := _on_text_changed.bind(id)
			_tabs[id] = {"code": code, "path": path, "disk": _disk_text(path), "callback": callback}
			code.text_changed.connect(callback)
			if enabled and _dirty(code):
				_timer.start()
		else:
			var disk := _disk_text(path)
			# Native reload/save completed; this is a new baseline, not a user edit.
			if normalized(code.text) == normalized(disk):
				_tabs[id]["disk"] = disk
				_announced.erase(path)
	for id in _tabs.keys():
		if not present.has(id):
			_disconnect_tab(id)


func _on_text_changed(_id: int) -> void:
	if enabled and not _saving:
		_timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and enabled and _timer != null:
		flush_pending()


## Also called before Git operations. False leaves every dirty buffer untouched.
func flush_pending() -> bool:
	if _saving:
		return false
	discover_tabs()
	var dirty := false
	for tab: Dictionary in _tabs.values():
		var code: CodeEdit = tab["code"]
		if not is_instance_valid(code) or not _dirty(code):
			continue
		dirty = true
		var path: String = tab["path"]
		var disk := _disk_text(path)
		if not can_save(tab["disk"], disk, code.text, FileAccess.file_exists(path)):
			if not _announced.has(path):
				_announced[path] = true
				EditorInterface.get_editor_toaster().push_toast(
					"GittyDot paused auto-save: %s changed on disk. Resolve Godot's reload prompt or save it manually." % path,
					EditorToaster.SEVERITY_WARNING)
				save_blocked.emit(path)
			return false
	if not dirty:
		return true
	_saving = true
	EditorInterface.get_script_editor().save_all_scripts()
	_saving = false
	var saved := true
	for tab: Dictionary in _tabs.values():
		var code: CodeEdit = tab["code"]
		if not is_instance_valid(code):
			continue
		var disk := _disk_text(tab["path"])
		if normalized(disk) == normalized(code.text):
			tab["disk"] = disk
		else:
			if _dirty(code):
				saved = false
	if saved:
		scripts_saved.emit()
	return saved


static func normalized(text: String) -> String:
	return text.replace("\r\n", "\n")


static func can_save(baseline: String, disk: String, buffer: String, exists: bool) -> bool:
	return exists and (normalized(disk) == normalized(baseline) or normalized(disk) == normalized(buffer))


static func _dirty(code: CodeEdit) -> bool:
	return code.get_version() != code.get_saved_version()


static func _disk_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _disconnect_tab(id: int) -> void:
	if not _tabs.has(id):
		return
	var tab: Dictionary = _tabs[id]
	if is_instance_valid(tab["code"]) and tab["code"].text_changed.is_connected(tab["callback"]):
		tab["code"].text_changed.disconnect(tab["callback"])
	_tabs.erase(id)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	for id in _tabs.keys():
		_disconnect_tab(id)
