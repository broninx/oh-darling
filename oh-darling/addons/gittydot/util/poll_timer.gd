## Polling timer that only ticks while active, the editor app has focus and (for a CanvasItem parent) the parent is on screen; emits poll on each tick and once on resume to catch up.
@tool
extends Timer

signal poll

var active := false:
	set(value):
		active = value
		_update()

var _app_focused := true


func _init(interval := 3.0) -> void:
	wait_time = interval
	timeout.connect(poll.emit)


func _enter_tree() -> void:
	var parent := get_parent() as CanvasItem
	if parent != null and not parent.visibility_changed.is_connected(_update):
		parent.visibility_changed.connect(_update)
	_update.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_focused = true
		_update()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_focused = false
		_update()


func _update() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent() as CanvasItem
	if active and _app_focused and (parent == null or parent.is_visible_in_tree()):
		if is_stopped():
			start()
			poll.emit()
	else:
		stop()
