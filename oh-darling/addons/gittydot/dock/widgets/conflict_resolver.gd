## Merge-conflict editor for one file: every <<<<<<< / ======= / >>>>>>> block is shown as Ours | Theirs with one-click choices (ours, theirs, both in either order) and an editable result, then the file is written back and optionally marked resolved.
@tool
extends ConfirmationDialog

const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")

## Emitted after the file was saved; marked is true when it was also `git add`-ed.
signal saved(path: String, marked: bool)

const COLOR_OURS := Color(0.35, 0.55, 0.95, 0.16)
const COLOR_THEIRS := Color(0.3, 0.8, 0.45, 0.14)

var _repo: RefCounted
var _path := ""
var _crlf := false
## Parsed file: Array of {"text": PackedStringArray} (unconflicted lines) or {"ours", "base", "theirs": PackedStringArray, "ours_label", "theirs_label"}.
var _segments: Array = []
## Per conflict segment index: the result CodeEdit.
var _results := {}
var _status_label: Label


func _init() -> void:
	title = "Resolve Conflicts"
	ok_button_text = "Save and Mark Resolved"
	unresizable = false
	exclusive = false
	min_size = UiScale.size_i(720, 460)
	add_button("Save Only", true, "save")
	confirmed.connect(func() -> void: _save(true))
	custom_action.connect(func(action: StringName) -> void:
		if action == &"save":
			_save(false)
			hide()
	)
	visibility_changed.connect(func() -> void:
		if not visible:
			queue_free.call_deferred()
	)


## Loads path (repo-relative) and pops the dialog up. Returns false if the file has no conflict markers to resolve.
func open(repo: RefCounted, path: String) -> bool:
	_repo = repo
	_path = path
	var abs_path: String = repo.get_repo_root().path_join(path)
	if not FileAccess.file_exists(abs_path):
		return false
	var text := FileAccess.get_file_as_string(abs_path)
	_crlf = text.contains("\r\n")
	_segments = parse(text.replace("\r\n", "\n"))
	var conflict_count := _segments.filter(func(s: Dictionary) -> bool: return s.has("ours")).size()
	if conflict_count == 0:
		return false
	title = "Resolve Conflicts — %s" % path
	_build(conflict_count)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	popup_centered(Vector2i(mini(int(UiScale.px(1200)), int(screen.x * 0.85)), mini(int(UiScale.px(820)), int(screen.y * 0.85))))
	_update_status()
	return true


## Splits text into plain and conflict segments (supports diff3 "|||||||" base sections).
static func parse(text: String) -> Array:
	var segments: Array = []
	var plain := PackedStringArray()
	var state := "" # "", "ours", "base", "theirs"
	var current := {}
	for line in text.split("\n"):
		if state.is_empty() and line.begins_with("<<<<<<<"):
			if not plain.is_empty():
				segments.append({ "text": plain })
				plain = PackedStringArray()
			current = { "ours": PackedStringArray(), "base": PackedStringArray(), "theirs": PackedStringArray(),
					"ours_label": line.substr(7).strip_edges(), "theirs_label": "" }
			state = "ours"
		elif state == "ours" and line.begins_with("|||||||"):
			state = "base"
		elif (state == "ours" or state == "base") and line.begins_with("======="):
			state = "theirs"
		elif state == "theirs" and line.begins_with(">>>>>>>"):
			current["theirs_label"] = line.substr(7).strip_edges()
			segments.append(current)
			state = ""
		elif state.is_empty():
			plain.append(line)
		else:
			var part: PackedStringArray = current[state]
			part.append(line)
			current[state] = part
	if not state.is_empty():
		# Unterminated block — keep it verbatim rather than guessing.
		plain.append("<<<<<<< " + current["ours_label"])
		plain.append_array(current["ours"])
		plain.append("=======")
		plain.append_array(current["theirs"])
	if not plain.is_empty():
		segments.append({ "text": plain })
	return segments


static func _marker_text(segment: Dictionary) -> String:
	var lines := PackedStringArray(["<<<<<<< " + segment["ours_label"]])
	lines.append_array(segment["ours"])
	lines.append("=======")
	lines.append_array(segment["theirs"])
	lines.append(">>>>>>> " + segment["theirs_label"])
	return "\n".join(lines)


func _build(conflict_count: int) -> void:
	var layout := VBoxContainer.new()
	add_child(layout)

	var top := HBoxContainer.new()
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status_label)
	for choice in [["All Ours", "ours"], ["All Theirs", "theirs"]]:
		var b := Button.new()
		b.text = choice[0]
		b.pressed.connect(func() -> void:
			for idx in _results:
				_apply_choice(idx, choice[1])
		)
		top.add_child(b)
	layout.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	var number := 0
	for idx in _segments.size():
		var segment: Dictionary = _segments[idx]
		if not segment.has("ours"):
			continue
		number += 1
		list.add_child(_conflict_block(idx, segment, number, conflict_count))


func _conflict_block(idx: int, segment: Dictionary, number: int, total: int) -> Control:
	var box := VBoxContainer.new()
	var context := _context_line(idx)
	var header := Label.new()
	header.text = "Conflict %d of %d%s" % [number, total, ("   · after: " + context) if not context.is_empty() else ""]
	header.modulate = Color(0.95, 0.75, 0.45)
	header.clip_text = true
	box.add_child(header)

	var sides := HBoxContainer.new()
	sides.add_child(_side_pane("Ours — " + segment["ours_label"], segment["ours"], COLOR_OURS))
	sides.add_child(_side_pane("Theirs — " + segment["theirs_label"], segment["theirs"], COLOR_THEIRS))
	box.add_child(sides)

	var buttons := HBoxContainer.new()
	for choice in [["Use Ours", "ours"], ["Use Theirs", "theirs"], ["Ours, then Theirs", "ours_theirs"], ["Theirs, then Ours", "theirs_ours"]]:
		var b := Button.new()
		b.text = choice[0]
		b.pressed.connect(_apply_choice.bind(idx, choice[1]))
		buttons.add_child(b)
	if not (segment["base"] as PackedStringArray).is_empty():
		var b := Button.new()
		b.text = "Use Base"
		b.tooltip_text = "The common ancestor's version (from the ||||||| section)"
		b.pressed.connect(_apply_choice.bind(idx, "base"))
		buttons.add_child(b)
	box.add_child(buttons)

	var result_label := Label.new()
	result_label.text = "Result (editable):"
	result_label.modulate.a = 0.7
	box.add_child(result_label)
	var result := _code_edit(_marker_text(segment), true)
	result.text_changed.connect(_update_status)
	box.add_child(result)
	_results[idx] = result
	return box


## Last non-empty unconflicted line before segment idx, as a "where is this" hint.
func _context_line(idx: int) -> String:
	if idx == 0 or not _segments[idx - 1].has("text"):
		return ""
	var lines: PackedStringArray = _segments[idx - 1]["text"]
	for i in range(lines.size() - 1, -1, -1):
		if not lines[i].strip_edges().is_empty():
			return lines[i].strip_edges()
	return ""


func _side_pane(caption: String, lines: PackedStringArray, tint: Color) -> Control:
	var pane := VBoxContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = caption
	label.clip_text = true
	label.modulate.a = 0.75
	pane.add_child(label)
	var edit := _code_edit("\n".join(lines), false)
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	edit.add_theme_stylebox_override("read_only", style)
	edit.add_theme_stylebox_override("normal", style)
	pane.add_child(edit)
	return pane


func _code_edit(text: String, editable: bool) -> CodeEdit:
	var edit := CodeEdit.new()
	edit.text = text
	edit.editable = editable
	edit.gutters_draw_line_numbers = true
	edit.scroll_fit_content_height = true
	edit.custom_minimum_size = UiScale.size(0, 48)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Engine.is_editor_hint() and EditorInterface.get_editor_theme() != null and EditorInterface.get_editor_theme().has_font("source", "EditorFonts"):
		edit.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("source", "EditorFonts"))
	return edit


func _apply_choice(idx: int, choice: String) -> void:
	var segment: Dictionary = _segments[idx]
	var lines := PackedStringArray()
	match choice:
		"ours": lines = segment["ours"]
		"theirs": lines = segment["theirs"]
		"base": lines = segment["base"]
		"ours_theirs":
			lines.append_array(segment["ours"])
			lines.append_array(segment["theirs"])
		"theirs_ours":
			lines.append_array(segment["theirs"])
			lines.append_array(segment["ours"])
	(_results[idx] as CodeEdit).text = "\n".join(lines)
	_update_status()


func _unresolved_count() -> int:
	var count := 0
	for idx in _results:
		var text: String = (_results[idx] as CodeEdit).text
		if text.contains("<<<<<<<") or text.contains(">>>>>>>"):
			count += 1
	return count


func _update_status() -> void:
	var left := _unresolved_count()
	_status_label.text = "%d of %d conflicts still unresolved" % [left, _results.size()] if left > 0 else "All conflicts resolved — save to finish."
	get_ok_button().disabled = left > 0
	get_ok_button().tooltip_text = "Resolve every conflict first (or use Save Only)" if left > 0 else ""


## Rebuilds the file from the plain segments plus each conflict's result.
func _compose() -> String:
	var parts := PackedStringArray()
	for idx in _segments.size():
		var segment: Dictionary = _segments[idx]
		if segment.has("text"):
			parts.append("\n".join(segment["text"]))
		else:
			var chosen: String = (_results[idx] as CodeEdit).text
			if not chosen.is_empty(): # an emptied result removes the lines instead of leaving a blank one
				parts.append(chosen)
	var text := "\n".join(parts)
	return text.replace("\n", "\r\n") if _crlf else text


func _save(mark_resolved: bool) -> void:
	var abs_path: String = _repo.get_repo_root().path_join(_path)
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		EditorInterface.get_editor_toaster().push_toast("GittyDot: couldn't write %s" % _path, EditorToaster.SEVERITY_ERROR)
		return
	file.store_string(_compose())
	file.close()
	var marked := false
	if mark_resolved:
		marked = _repo.mark_resolved(_path)["ok"]
	EditorOpen.refresh_external_change(_repo.get_repo_root(), _path)
	saved.emit(_path, marked)
