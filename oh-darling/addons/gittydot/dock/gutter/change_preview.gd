## Compact inline HEAD preview, anchored under the changed lines. Actions and temporary shading stay inside the native script editor.
@tool
extends PanelContainer

signal navigate_requested(delta: int)
signal rollback_requested
signal show_in_changes_requested
signal closed

const DiffHunks := preload("res://addons/gittydot/util/diff_hunks.gd")
const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const SyntaxColors := preload("res://addons/gittydot/util/syntax_colors.gd")
const InlineDiff := preload("res://addons/gittydot/util/inline_diff.gd")
const InlineHighlights := preload("res://addons/gittydot/dock/gutter/inline_highlights.gd")

const MAX_VISIBLE_LINES := 8
const MAX_WIDTH := 720.0

var _code_edit: CodeEdit
## Last line (0-based) of the change; the panel sits right under it.
var _anchor_line := 0
## First line (0-based) of the change, for flipping the panel above it.
var _first_line := 0
var _opened_msec := 0
var _old_view: CodeEdit
var _layout: VBoxContainer
var _toolbar: HBoxContainer
var _scale := 1.0
var _content_width := 0.0
var _line_backgrounds := {}
var _highlight := Color.TRANSPARENT
var _old_highlights: RefCounted


func open(code_edit: CodeEdit, regions: Array, index: int, rel_path: String) -> void:
	_code_edit = code_edit
	var region: Dictionary = regions[index]
	var type := DiffHunks.region_type(region)
	_anchor_line = maxi(region["new_start"] - 1, 0) if type == "deleted" else region["new_start"] + region["new_count"] - 2
	_first_line = maxi(region["new_start"] - 1, 0)
	_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0

	var style := StyleBoxFlat.new()
	style.bg_color = _opaque_background(code_edit)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = int(6 * _scale)
	style.border_color = code_edit.get_theme_color("font_color") * Color(1, 1, 1, 0.16)
	style.set_border_width_all(1)
	style.set_content_margin_all(3 * _scale)
	style.set_corner_radius_all(int(3 * _scale))
	add_theme_stylebox_override("panel", style)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", int(3 * _scale))
	add_child(_layout)

	var old_lines: PackedStringArray = region["old_lines"]
	if not old_lines.is_empty():
		_old_view = CodeEdit.new()
		_old_view.text = "\n".join(old_lines)
		_old_view.editable = false
		_old_view.context_menu_enabled = false
		_old_view.scroll_fit_content_height = false
		_old_view.add_theme_font_override("font", code_edit.get_theme_font("font"))
		_old_view.add_theme_font_size_override("font_size", code_edit.get_theme_font_size("font_size"))
		# Native background; the layer renderer distinguishes modifications from deletions.
		_old_view.add_theme_color_override("background_color", style.bg_color)
		_old_view.add_theme_color_override("current_line_color", Color.TRANSPARENT)
		_old_view.add_theme_color_override("caret_color", Color.TRANSPARENT)
		_old_view.focus_mode = FOCUS_NONE
		_old_view.tooltip_text = "Previous version in the latest commit"
		_old_view.add_theme_color_override("font_color", code_edit.get_theme_color("font_color"))
		_old_view.add_theme_color_override("font_readonly_color", code_edit.get_theme_color("font_color"))
		var language := SyntaxColors.language_for(rel_path)
		if not language.is_empty():
			var highlighter := OldLinesHighlighter.new()
			highlighter.language = language
			highlighter.default_color = code_edit.get_theme_color("font_color")
			_old_view.syntax_highlighter = highlighter
		_old_view.size_flags_horizontal = SIZE_EXPAND_FILL
		var visible_lines := mini(old_lines.size(), MAX_VISIBLE_LINES)
		# Room for the horizontal scrollbar too, or a long line hides the last row under it.
		_old_view.custom_minimum_size.y = visible_lines * code_edit.get_line_height() + 6 * _scale + _old_view.get_h_scroll_bar().get_combined_minimum_size().y
		for line in old_lines:
			_content_width = maxf(_content_width, code_edit.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, code_edit.get_theme_font_size("font_size")).x)
		_content_width += 24 * _scale
		_layout.add_child(_old_view)
		_old_highlights = InlineHighlights.new()
		_old_highlights.attach(_old_view, true)
		var current := PackedStringArray()
		for line in range(_first_line, mini(_first_line + region["new_count"], code_edit.get_line_count())):
			current.append(code_edit.get_line(line))
		var layers := InlineDiff.build(old_lines, current)
		var rows := {}
		for line in layers["old"].size():
			rows[line] = layers["old"][line]
		_old_highlights.set_rows.call_deferred(rows)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", int(2 * _scale))
	_layout.add_child(_toolbar)
	_add_button(_toolbar, "", "ArrowUp", "Previous change", index > 0, func() -> void: navigate_requested.emit(-1))
	_add_button(_toolbar, "", "ArrowDown", "Next change", index < regions.size() - 1, func() -> void: navigate_requested.emit(1))
	_add_button(_toolbar, "", "Reload", "Rollback these lines to the latest commit (undo with Ctrl/Cmd+Z)", true, func() -> void: rollback_requested.emit())
	var separator := VSeparator.new()
	_toolbar.add_child(separator)
	_add_button(_toolbar, "Show Diff", "", "Open this change in GittyDot for comparison and staging", true, func() -> void: show_in_changes_requested.emit())
	var count := Label.new()
	count.text = "%d/%d" % [index + 1, regions.size()]
	count.tooltip_text = "Change %d of %d · %s" % [index + 1, regions.size(), _summary(region, type)]
	count.modulate.a = 0.5
	count.size_flags_horizontal = SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toolbar.add_child(count)
	_add_button(_toolbar, "", "Close", "Close (Esc)", true, close)

	# The gutter renderer owns persistent line/span shading without changing editor colors.

	code_edit.add_child(self)
	_opened_msec = Time.get_ticks_msec()
	code_edit.text_changed.connect(close)
	code_edit.lines_edited_from.connect(_on_lines_edited)
	code_edit.text_set.connect(close)
	code_edit.caret_changed.connect(_on_caret_changed)
	code_edit.gui_input.connect(_on_code_edit_gui_input)
	_reposition()


func close() -> void:
	if is_queued_for_deletion():
		return
	if _old_highlights != null:
		_old_highlights.detach()
		_old_highlights = null
	if is_instance_valid(_code_edit):
		_restore_line_backgrounds()
		for pair in [[_code_edit.text_changed, close], [_code_edit.lines_edited_from, _on_lines_edited], [_code_edit.text_set, close], [_code_edit.caret_changed, _on_caret_changed], [_code_edit.gui_input, _on_code_edit_gui_input]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	if _old_highlights != null:
		_old_highlights.detach()
		_old_highlights = null
	_restore_line_backgrounds()


func _on_lines_edited(from_line: int, to_line: int) -> void:
	# This signal precedes text_changed, after TextEdit has moved the line data.
	var shifted := {}
	var delta := to_line - from_line
	for line: int in _line_backgrounds:
		if delta >= 0:
			shifted[line + delta if line > from_line else line] = _line_backgrounds[line]
		elif line > from_line:
			shifted[line + delta] = _line_backgrounds[line]
		elif line <= to_line:
			shifted[line] = _line_backgrounds[line]
	_line_backgrounds = shifted
	close()


func _restore_line_backgrounds() -> void:
	if is_instance_valid(_code_edit):
		for line: int in _line_backgrounds:
			if line < _code_edit.get_line_count() and _code_edit.get_line_background_color(line).is_equal_approx(_highlight):
				_code_edit.set_line_background_color(line, _line_backgrounds[line])
	_line_backgrounds.clear()


func _summary(region: Dictionary, type: String) -> String:
	match type:
		"added":
			return "%d line%s added" % [region["new_count"], "" if region["new_count"] == 1 else "s"]
		"deleted":
			return "%d line%s deleted" % [region["old_count"], "" if region["old_count"] == 1 else "s"]
	return "%d → %d line%s" % [region["old_count"], region["new_count"], "" if region["new_count"] == 1 else "s"]


## Solid, like a tooltip: the script editor's background_color is often transparent (the panel behind it paints the color).
static func _opaque_background(code_edit: CodeEdit) -> Color:
	var bg := code_edit.get_theme_color("background_color")
	if bg.a < 0.9 and Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		var setting := "text_editor/theme/highlighting/background_color"
		bg = settings.get_setting(setting) if settings.has_setting(setting) else EditorInterface.get_editor_theme().get_color("base_color", "Editor")
	bg.a = 1.0
	return bg.lightened(0.025)


func _add_button(parent: Control, text: String, icon_name: String, tooltip: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	if not icon_name.is_empty() and Engine.is_editor_hint():
		var theme := EditorInterface.get_editor_theme()
		if theme.has_icon(icon_name, "EditorIcons"):
			b.icon = theme.get_icon(icon_name, "EditorIcons")
	if b.text.is_empty() and b.icon == null:
		b.text = {"ArrowUp": "▲", "ArrowDown": "▼", "Reload": "↶", "Close": "✕"}.get(icon_name, "?")
	b.flat = true
	b.custom_minimum_size = Vector2(24, 24) * _scale
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.set_content_margin_all(3 * _scale)
	normal.set_corner_radius_all(int(2 * _scale))
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.5, 0.5, 0.5, 0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.5, 0.5, 0.5, 0.2)
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", _code_edit.get_theme_color("font_color") * Color(1, 1, 1, 0.8))
	b.tooltip_text = tooltip
	b.disabled = not enabled
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


## Every frame: scrolling (wheel, minimap, code) and resizing have no single signal to hook, and this is one cheap lookup.
func _process(_delta: float) -> void:
	_reposition()


func _reposition() -> void:
	if not is_instance_valid(_code_edit):
		return
	# An open preview from the previous version can survive a live script reload.
	if not is_instance_valid(_toolbar):
		close()
		return
	var pos := _code_edit.get_pos_at_line_column(clampi(_anchor_line, 0, _code_edit.get_line_count() - 1), 0)
	var first_pos := _code_edit.get_pos_at_line_column(_first_line, 0)
	visible = pos.y >= 0 or first_pos.y >= 0
	if not visible:
		return
	var left := maxf(float(_code_edit.get_total_gutter_width()), first_pos.x)
	var right_margin := _code_edit.get_v_scroll_bar().size.x + 6.0 * _scale
	if _code_edit.is_drawing_minimap():
		right_margin += _code_edit.get_minimap_width()
	var available := maxf(_code_edit.size.x - _code_edit.get_total_gutter_width() - right_margin, 0)
	var desired := maxf(_toolbar.get_combined_minimum_size().x + 8 * _scale, _content_width)
	custom_minimum_size.x = minf(desired, minf(MAX_WIDTH * _scale, available))
	reset_size()
	left = clampf(left, float(_code_edit.get_total_gutter_width()), maxf(_code_edit.size.x - right_margin - size.x, _code_edit.get_total_gutter_width()))
	var below := pos.y + 2.0 if pos.y >= 0 else _code_edit.size.y
	var y := below
	# Flip above the change when there's no room below it.
	if below + size.y > _code_edit.size.y and first_pos.y >= 0:
		y = maxf(first_pos.y - _code_edit.get_line_height() - size.y - 2.0, 0.0)
	position = Vector2(left, minf(y, maxf(_code_edit.size.y - size.y, 0.0)))


## The click that opened this (or prev/next) may move the caret right away; anything later means the user moved on.
func _on_caret_changed() -> void:
	if Time.get_ticks_msec() - _opened_msec > 150:
		close()


func _on_code_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		_code_edit.accept_event()


## Colors the old lines like the diff view does (SyntaxColors), since the script editor's own highlighter is bound to its CodeEdit.
class OldLinesHighlighter:
	extends SyntaxHighlighter

	var language := ""
	var default_color := Color.WHITE


	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var text := get_text_edit().get_line(line)
		var result := {}
		for span in SyntaxColors.spans(text, language):
			result[span[0]] = { "color": span[2] }
			result[span[0] + span[1]] = { "color": default_color }
		return result
