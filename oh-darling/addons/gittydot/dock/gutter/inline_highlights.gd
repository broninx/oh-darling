## Paints layered diff backgrounds during the native gutter pass, before syntax and selection.
## Native glyph bounds are captured after drawing; no editor text, highlighter or line colors are changed.
@tool
extends RefCounted

const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const META := "gittydot_inline_highlights"

var code: CodeEdit
var rows := {}
var geometry := {}
var _view_signature := ""
var _owns_gutter := false
var _background_overrides := {}
const GUTTER := "gittydot_inline_preview"


func attach(editor: CodeEdit, own_gutter := false) -> void:
	code = editor
	_owns_gutter = own_gutter
	_move_legacy_background()
	code.draw.connect(_capture_geometry)
	code.text_changed.connect(clear)
	code.text_set.connect(clear)
	code.lines_edited_from.connect(_on_lines_edited)
	if own_gutter:
		code.add_gutter()
		var index := code.get_gutter_count() - 1
		code.set_gutter_name(index, GUTTER)
		code.set_gutter_width(index, 1)
		code.set_gutter_draw(index, true)
		code.set_gutter_type(index, TextEdit.GUTTER_TYPE_CUSTOM)
		code.set_gutter_custom_draw(index, func(line: int, _index: int, cell: Rect2) -> void: draw_line(line, cell))


func set_rows(value: Dictionary) -> void:
	rows = value
	geometry.clear()
	code.queue_redraw()


func clear() -> void:
	rows.clear()
	geometry.clear()
	if is_instance_valid(code):
		code.queue_redraw()


func _on_lines_edited(_from: int, _to: int) -> void:
	clear()


func detach() -> void:
	if is_instance_valid(code):
		for pair in [[code.draw, _capture_geometry], [code.text_changed, clear], [code.text_set, clear], [code.lines_edited_from, _on_lines_edited]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
		if _owns_gutter:
			for index in code.get_gutter_count():
				if code.get_gutter_name(index) == GUTTER:
					# Godot 4.7.2 rejects removing a gutter whose index exceeds the line count.
					# This private preview column can simply be hidden until its CodeEdit is freed.
					code.set_gutter_custom_draw(index, Callable())
					code.set_gutter_draw(index, false)
					code.set_gutter_width(index, 0)
					break
		_restore_background()
	clear()
	code = null


func _move_legacy_background() -> void:
	# Godot's deprecated background_color fills a private text canvas ABOVE custom
	# gutter drawing. Use the equivalent native style background so glyphs and
	# selections still draw above our highlights, without replacing the highlighter.
	var color := code.get_theme_color("background_color")
	if color.a < 0.99:
		return
	_background_overrides["background_color"] = color if code.has_theme_color_override("background_color") else null
	for name in ["normal", "read_only"]:
		var original := code.get_theme_stylebox(name)
		_background_overrides[name] = original if code.has_theme_stylebox_override(name) else null
		var style := original.duplicate() as StyleBoxFlat
		if style == null:
			style = StyleBoxFlat.new()
			for side in 4:
				style.set_content_margin(side, original.get_margin(side))
		style.bg_color = color
		code.add_theme_stylebox_override(name, style)
	code.add_theme_color_override("background_color", Color.TRANSPARENT)


func _restore_background() -> void:
	if _background_overrides.is_empty():
		return
	for name in ["normal", "read_only"]:
		if _background_overrides[name] == null:
			code.remove_theme_stylebox_override(name)
		else:
			code.add_theme_stylebox_override(name, _background_overrides[name])
	if _background_overrides["background_color"] == null:
		code.remove_theme_color_override("background_color")
	else:
		code.add_theme_color_override("background_color", _background_overrides["background_color"])
	_background_overrides.clear()


func _signature() -> String:
	return "%s|%s|%s|%s|%s" % [code.size, code.get_h_scroll(), code.get_v_scroll(), code.get_theme_font_size("font_size"), code.get_total_gutter_width()]


func _capture_geometry() -> void:
	var next := {}
	var viewport := _text_bounds()
	var visible_columns := {}
	# Visit viewport columns, not the entire contents of a very long changed line.
	for row in ceili(viewport.size.y / maxf(code.get_line_height(), 1)):
		var y := minf(viewport.end.y - 1, viewport.position.y + (row + 0.5) * code.get_line_height())
		var left := code.get_line_column_at_pos(Vector2(viewport.position.x, y))
		var right := code.get_line_column_at_pos(Vector2(viewport.end.x - 1, y))
		if left.y == right.y and left.y >= 0:
			if not visible_columns.has(left.y):
				visible_columns[left.y] = []
			visible_columns[left.y].append(Vector2i(mini(left.x, right.x), maxi(left.x, right.x) + 1))
	for line: int in rows:
		if not visible_columns.has(line) or line >= code.get_line_count() or code.get_line(line) != rows[line]["text"]:
			continue
		var blocks := []
		for span: Dictionary in rows[line]["spans"]:
			var rects := []
			for visible_range: Vector2i in visible_columns[line]:
				for column in range(maxi(span["start"], visible_range.x), mini(mini(span["start"] + span["length"], visible_range.y), code.get_line(line).length())):
					# Native grapheme bounds include their END caret boundary. Asking
					# at column highlights the previous glyph; column + 1 covers this
					# character, including the final character before EOL.
					var glyph := _glyph_rect(line, column)
					if glyph.position.x < 0 or glyph.position.y < 0 or glyph.size.x <= 0:
						continue
					glyph = glyph.intersection(viewport)
					if not glyph.has_area():
						continue
					# Union consecutive graphemes, including ligatures and combining characters.
					if not rects.is_empty() and is_equal_approx(rects[-1].position.y, glyph.position.y) and rects[-1].grow(1).intersects(glyph):
						rects[-1] = rects[-1].merge(glyph)
					else:
						rects.append(glyph)
			for rect: Rect2 in rects:
				blocks.append({"rect": rect, "kind": span["kind"]})
		next[line] = blocks
	_view_signature = _signature()
	if next != geometry:
		geometry = next
		code.queue_redraw.call_deferred() # Redraw requests inside draw itself are ignored.


func _text_bounds() -> Rect2:
	var style := code.get_theme_stylebox("normal" if code.editable else "read_only")
	var left := code.get_total_gutter_width() + style.get_margin(SIDE_LEFT)
	var right := code.size.x - style.get_margin(SIDE_RIGHT)
	if code.get_v_scroll_bar().visible:
		right -= code.get_v_scroll_bar().size.x
	if code.is_drawing_minimap():
		right -= code.get_minimap_width()
	var bottom := code.size.y - style.get_margin(SIDE_BOTTOM)
	if code.get_h_scroll_bar().visible:
		bottom -= code.get_h_scroll_bar().size.y
	return Rect2(left, style.get_margin(SIDE_TOP), maxf(right - left, 0), maxf(bottom - style.get_margin(SIDE_TOP), 0))


func _glyph_rect(line: int, column: int) -> Rect2:
	var rect := Rect2(code.get_rect_at_line_column(line, column + 1))
	var previous := Rect2(code.get_rect_at_line_column(line, column))
	# At a wrap boundary, the end caret belongs to the next visual row. Keep
	# the final glyph on its own row rather than highlighting the next row.
	if previous.position.x >= 0 and (rect.position.x < 0 or rect.position.y > previous.position.y):
		var width := code.get_theme_font("font").get_string_size(code.get_line(line).substr(column, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, code.get_theme_font_size("font_size")).x
		return Rect2(previous.end.x, previous.position.y, width, code.get_line_height())
	return rect


func draw_line(line: int, cell: Rect2) -> void:
	if not rows.has(line) or line >= code.get_line_count() or rows[line]["text"] != code.get_line(line):
		return
	var bounds := _text_bounds()
	var kind: String = rows[line]["kind"]
	var base := GitIcons.COLOR_MODIFIED if kind in ["modified", "modified_old"] else (GitIcons.COLOR_ADDED if kind == "added" else GitIcons.COLOR_DELETED)
	var background := Rect2(bounds.position.x, cell.position.y, bounds.size.x, cell.size.y * (code.get_line_wrap_count(line) + 1)).intersection(bounds)
	if background.has_area():
		code.draw_rect(background, Color(base, 0.065))
	if _view_signature != _signature():
		return # Never paint stale positions during a scroll, resize or font change.
	for block: Dictionary in geometry.get(line, []):
		code.draw_rect(block["rect"], span_color(block["kind"]))


static func span_color(kind: String) -> Color:
	match kind:
		"inserted": return Color(GitIcons.COLOR_ADDED, 0.2)
		"replaced": return Color(GitIcons.COLOR_MODIFIED.lerp(GitIcons.COLOR_ADDED, 0.4), 0.3)
	return Color(GitIcons.COLOR_DELETED, 0.26)
