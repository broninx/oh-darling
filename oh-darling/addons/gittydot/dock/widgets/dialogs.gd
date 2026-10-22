## Awaitable one-off dialogs built in code, so every new git action doesn't need its own node in a .tscn. Each call creates the dialog under `parent`, pops it up, and frees it once answered. No class_name: internal helper, addressed via preload.
@tool
extends RefCounted
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")
const GitCli := preload("res://addons/gittydot/util/git_cli.gd")

## Bound by plugin.gd; cleared on disable so dialogs cannot call freed docks.
static var reveal_console := Callable()
const CONSOLE_ACTION := "gittydot_console_details"

const TEXT_WIDTH := 420


## Plain error/info message.
static func error(parent: Node, title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.add_child(_message_label(message))
	add_console_details(dialog, title, message)
	await _run(parent, dialog)


## Includes validation errors that never launched Git, with a stable log entry id.
static func add_console_details(dialog: AcceptDialog, title: String, message: String) -> void:
	if not reveal_console.is_valid():
		return
	var entry_id := GitCli.record([], 1, message, title)
	dialog.set_meta("console_entry_id", entry_id)
	if dialog.has_meta("console_details_added"):
		return
	dialog.set_meta("console_details_added", true)
	dialog.add_button("Show details in Console", true, CONSOLE_ACTION)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == CONSOLE_ACTION:
			dialog.hide()
			if reveal_console.is_valid():
				reveal_console.call(int(dialog.get_meta("console_entry_id")))
	)


## true on OK, false on Cancel/close.
static func confirm(parent: Node, title: String, message: String, ok_text: String = "OK") -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = ok_text
	dialog.add_child(_message_label(message))
	return await _run(parent, dialog) == true


## Error with extra action buttons (e.g. "Pull" after a rejected push). Returns the chosen action id, or "" if just dismissed.
static func error_with_actions(parent: Node, title: String, message: String, actions: Dictionary) -> String:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Close"
	dialog.add_child(_message_label(message))
	for action_id in actions:
		dialog.add_button(actions[action_id], true, action_id)
	add_console_details(dialog, title, message)
	var answer: Variant = await _run(parent, dialog)
	return answer if answer is String and answer != CONSOLE_ACTION else ""


## Single line of text input; null on cancel.
static func prompt(parent: Node, title: String, label: String, default_text: String = "", ok_text: String = "OK") -> Variant:
	var answer: Variant = await form(parent, title, [{ "key": "value", "label": label, "type": "text", "default": default_text }], ok_text)
	return null if answer == null else String(answer["value"]).strip_edges()


## Small form. fields: [{"key", "label", "type": "text"|"multiline"|"check"|"option"|"label", "default", "options": Array[String], "placeholder", "tooltip"}]. Returns {key: value} (option -> selected text) or null on cancel.
static func form(parent: Node, title: String, fields: Array, ok_text: String = "OK") -> Variant:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = ok_text

	var layout := VBoxContainer.new()
	layout.custom_minimum_size = UiScale.size(TEXT_WIDTH, 0)
	dialog.add_child(layout)

	var inputs := {}
	var first_input: Control = null
	for field in fields:
		var type: String = field.get("type", "text")
		var label_text: String = field.get("label", "")
		match type:
			"label":
				layout.add_child(_message_label(label_text))
			"check":
				var check := CheckBox.new()
				check.text = label_text
				check.button_pressed = field.get("default", false)
				check.tooltip_text = field.get("tooltip", "")
				layout.add_child(check)
				inputs[field["key"]] = check
			"option":
				if not label_text.is_empty():
					layout.add_child(_caption(label_text))
				var option := OptionButton.new()
				var options: Array = field.get("options", [])
				for i in options.size():
					option.add_item(options[i])
					if options[i] == field.get("default", ""):
						option.select(i)
				option.tooltip_text = field.get("tooltip", "")
				layout.add_child(option)
				inputs[field["key"]] = option
			"multiline":
				if not label_text.is_empty():
					layout.add_child(_caption(label_text))
				var edit := TextEdit.new()
				edit.custom_minimum_size = UiScale.size(0, 110)
				edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				edit.text = field.get("default", "")
				edit.placeholder_text = field.get("placeholder", "")
				layout.add_child(edit)
				inputs[field["key"]] = edit
				if first_input == null:
					first_input = edit
			_:
				if not label_text.is_empty():
					layout.add_child(_caption(label_text))
				var line := LineEdit.new()
				line.text = field.get("default", "")
				line.placeholder_text = field.get("placeholder", "")
				line.tooltip_text = field.get("tooltip", "")
				layout.add_child(line)
				dialog.register_text_enter(line)
				inputs[field["key"]] = line
				if first_input == null:
					first_input = line

	if first_input != null:
		dialog.about_to_popup.connect(func() -> void:
			first_input.grab_focus.call_deferred()
			if first_input is LineEdit:
				(first_input as LineEdit).select_all.call_deferred()
		)
	else:
		# Nothing to type into: focus OK so Enter confirms.
		dialog.about_to_popup.connect(func() -> void: dialog.get_ok_button().grab_focus.call_deferred())

	# Values are read before _run() frees the dialog.
	var values := {}
	dialog.confirmed.connect(func() -> void:
		for key in inputs:
			var input: Control = inputs[key]
			if input is CheckBox:
				values[key] = (input as CheckBox).button_pressed
			elif input is OptionButton:
				var ob := input as OptionButton
				values[key] = ob.get_item_text(ob.selected) if ob.selected >= 0 else ""
			elif input is TextEdit:
				values[key] = (input as TextEdit).text
			else:
				values[key] = (input as LineEdit).text
	)
	if await _run(parent, dialog) != true:
		return null
	return values


## Pops the dialog up and waits for an answer: true (OK), false (cancel/close), or the custom action's String id.
static func _run(parent: Node, dialog: AcceptDialog) -> Variant:
	var waiter := _Waiter.new()
	dialog.confirmed.connect(waiter.finish.bind(true))
	dialog.canceled.connect(waiter.finish.bind(false))
	dialog.custom_action.connect(func(action: StringName) -> void:
		dialog.hide()
		waiter.finish(String(action))
	)
	parent.add_child(dialog)
	dialog.popup_centered(UiScale.size_i(TEXT_WIDTH + 40, 0))
	var answer: Variant = await waiter.done
	dialog.queue_free()
	return answer


static func _message_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = UiScale.size(TEXT_WIDTH, 0)
	return label


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate.a = 0.75
	return label


class _Waiter:
	extends RefCounted

	signal done(answer: Variant)

	var _finished := false


	func finish(answer: Variant) -> void:
		if _finished:
			return
		_finished = true
		done.emit(answer)
