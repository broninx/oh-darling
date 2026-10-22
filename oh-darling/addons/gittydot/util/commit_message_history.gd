## Recent commit messages for a message box: Up/Down in an empty box steps through them, and a History button lists them.
extends RefCounted

const SIZE := 20

## Set by the Changes panel along with its own.
var repo: RefCounted
var _box: TextEdit
## Called after a recalled message is put in the box (the panel re-enables its Commit button).
var _on_changed: Callable
## Loaded when browsing starts; -1 = not browsing.
var _messages := PackedStringArray()
var _index := -1


func _init(box: TextEdit, on_changed: Callable) -> void:
	_box = box
	_on_changed = on_changed


## The History button, listing the messages when opened.
func make_button() -> MenuButton:
	var button := MenuButton.new()
	button.icon = _box.get_theme_icon("History", "EditorIcons")
	button.flat = true
	button.tooltip_text = "Recent commit messages"
	var popup := button.get_popup()
	popup.about_to_popup.connect(func() -> void:
		popup.clear()
		_messages = repo.recent_commit_messages(SIZE)
		for i in _messages.size():
			popup.add_item(_messages[i].get_slice("\n", 0).left(80), i)
		if _messages.is_empty():
			popup.add_item("(no commits yet)")
			popup.set_item_disabled(0, true)
	)
	popup.id_pressed.connect(func(id: int) -> void:
		_box.text = _messages[id]
		_box.grab_focus()
		_on_changed.call()
	)
	return button


## Up (step 1) in an empty box, or one still showing a recalled message, steps back through previous messages; Down steps forward, back to empty. False when the key isn't for it.
func browse(step: int) -> bool:
	var browsing := _index >= 0 and _index < _messages.size() and _box.text == _messages[_index]
	if not browsing:
		if step < 0 or not _box.text.is_empty():
			return false
		_messages = repo.recent_commit_messages(SIZE)
		_index = -1
	var next := _index + step
	if next >= _messages.size():
		return browsing
	_index = maxi(next, -1)
	_box.text = _messages[_index] if _index >= 0 else ""
	_on_changed.call()
	return true
