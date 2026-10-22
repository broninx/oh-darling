## One-line status strip with a Cancel button for background git operations (fetch/pull/push...). Shared by the Changes and Branches panels.
@tool
extends HBoxContainer

const DONE_CLEAR_SECS := 8.0

var _label: Label
var _cancel_button: Button
var _repo: RefCounted
var _clear_timer: Timer
var _busy_text := ""


func _init() -> void:
	visible = false
	_label = Label.new()
	_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.flat = true
	_cancel_button.pressed.connect(func() -> void:
		if _repo != null:
			_repo.cancel_current()
	)
	add_child(_cancel_button)

	_clear_timer = Timer.new()
	_clear_timer.one_shot = true
	_clear_timer.timeout.connect(clear)
	add_child(_clear_timer)


## Shows text with a working Cancel button until done()/clear().
func busy(text: String, repo: RefCounted) -> void:
	_disconnect_progress()
	_repo = repo
	_busy_text = text
	_repo.job_progress.connect(_on_progress)
	_clear_timer.stop()
	_label.text = "⟳ " + text
	_label.tooltip_text = text
	_label.modulate = Color(1, 1, 1)
	_cancel_button.visible = true
	visible = true


## Final result line, auto-hidden after a few seconds.
func done(text: String, is_error: bool = false) -> void:
	_disconnect_progress()
	_repo = null
	_label.text = text
	_label.tooltip_text = text
	_label.modulate = Color(1, 0.6, 0.6) if is_error else Color(0.7, 0.95, 0.7)
	_cancel_button.visible = false
	visible = true
	_clear_timer.start(DONE_CLEAR_SECS)


func clear() -> void:
	_disconnect_progress()
	_repo = null
	_clear_timer.stop()
	visible = false


func _on_progress(progress_text: String) -> void:
	_label.text = "⟳ %s  %s" % [_busy_text, progress_text]


func _disconnect_progress() -> void:
	if _repo != null and _repo.job_progress.is_connected(_on_progress):
		_repo.job_progress.disconnect(_on_progress)
