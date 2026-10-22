## Strip above the Changes toolbar while a merge, rebase, cherry-pick or revert is in progress, with Continue/Skip/Abort.
@tool
extends PanelContainer

const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const GitErrors := preload("res://addons/gittydot/util/git_errors.gd")

## After Continue/Skip/Abort ran; ok = it went through (the Changes panel then clears the message box).
signal step_done(ok: bool)

## Set by the Changes panel along with its own.
var repo: RefCounted
## The panel's operation bar, for the short "done" feedback.
var _operation_bar: Control
var _label: Label
var _continue_button: Button
var _skip_button: Button


func _init(operation_bar: Control) -> void:
	_operation_bar = operation_bar
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.55, 0.2, 0.18)
	style.border_color = Color(0.95, 0.65, 0.25, 0.6)
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)
	visible = false

	var row := HBoxContainer.new()
	_label = Label.new()
	_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.pressed.connect(func() -> void: _after_step(repo.continue_operation(), "Continue"))
	row.add_child(_continue_button)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.tooltip_text = "Drop the commit being applied and move on to the next one"
	_skip_button.pressed.connect(_on_skip_pressed)
	row.add_child(_skip_button)

	var abort := Button.new()
	abort.text = "Abort"
	abort.tooltip_text = "Undo the whole operation and go back to how things were before it started"
	abort.pressed.connect(_on_abort_pressed)
	row.add_child(abort)
	add_child(row)


## Shows/hides the banner; returns the operation state it used.
func refresh() -> Dictionary:
	var op: Dictionary = repo.get_operation_state()
	var kind: String = op["kind"]
	visible = not kind.is_empty()
	if kind.is_empty():
		return op
	var verb: String = { "merge": "Merging", "rebase": "Rebasing", "cherry-pick": "Cherry-picking", "revert": "Reverting" }.get(kind, kind)
	var conflicts: int = op["conflicts"]
	var detail: String = op["detail"]
	_label.text = "%s%s — %s" % [verb, " " + detail if not detail.is_empty() else "", "%d conflict%s left" % [conflicts, "" if conflicts == 1 else "s"] if conflicts > 0 else "no conflicts left"]
	_label.tooltip_text = _label.text
	_continue_button.disabled = conflicts > 0
	_continue_button.tooltip_text = "Resolve every conflict first" if conflicts > 0 else "Commit the resolution and carry on"
	_skip_button.visible = kind != "merge"
	return op


func _on_skip_pressed() -> void:
	if await Dialogs.confirm(self, "Skip Commit", "Drop the commit currently being applied (its changes are discarded) and continue with the next one?", "Skip"):
		await _after_step(repo.skip_operation(), "Skip")


func _on_abort_pressed() -> void:
	if await Dialogs.confirm(self, "Abort", "Abort the %s and return to the state before it started?\nAny conflict resolutions made so far are lost." % repo.get_operation_state()["kind"], "Abort"):
		await _after_step(repo.abort_operation(), "Abort")


func _after_step(result: Dictionary, title: String) -> void:
	EditorOpen.refresh_all_external_changes()
	if result.get("conflicts", false):
		_operation_bar.done("Stopped on the next conflicts — resolve them, then Continue.", true)
	elif not result["ok"]:
		var error: String = result["error"]
		if error.contains("nothing to commit") or error.contains("is now empty"):
			error += "\n\nThe commit being applied ended up empty — use Skip to drop it."
		await Dialogs.error(self, "%s failed" % title, GitErrors.explain(error))
	else:
		_operation_bar.done("%s done." % title)
	step_done.emit(result["ok"] and not result.get("conflicts", false))
