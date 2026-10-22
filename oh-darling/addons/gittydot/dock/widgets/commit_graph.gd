@tool
extends Control

signal commit_selected(oid: String)
signal commit_context_requested(oid: String, screen_position: Vector2)
signal commit_activated(oid: String)
## Commits dragged onto the current branch's row (cherry-pick), newest first.
signal commits_dropped(oids: PackedStringArray, target_oid: String)
## A branch badge dragged onto another branch's row, one of them the current branch (merge / rebase).
signal refs_dropped(refs: PackedStringArray, target_oid: String)

const Settings := preload("res://addons/gittydot/util/settings.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")

## Pixel metrics, scaled by the editor's display scale (vars, not consts, for that reason).
var ROW_HEIGHT := UiScale.px(28.0)
var LANE_WIDTH := UiScale.px(16.0)
var DOT_RADIUS := UiScale.px(4.5)
var LEFT_MARGIN := UiScale.px(12.0)
var TEXT_GAP := UiScale.px(14.0)
var COLUMN_GAP := UiScale.px(16.0)
var DEFAULT_HASH_COL_WIDTH := UiScale.px(64.0)
var DEFAULT_AUTHOR_COL_WIDTH := UiScale.px(110.0)
var DEFAULT_DATE_COL_WIDTH := UiScale.px(150.0)
var MIN_COL_WIDTH := UiScale.px(50.0)
var DIVIDER_HIT_MARGIN := UiScale.px(4.0)
var BADGE_PADDING := UiScale.px(5.0)
var BADGE_GAP := UiScale.px(8.0)

const MERGE_MESSAGE_COLOR := Color(0.62, 0.62, 0.66)
const BADGE_BG_COLOR := Color(0.42, 0.58, 0.92, 0.28)
const BADGE_TEXT_COLOR := Color(0.68, 0.78, 1.0)
const TAG_BADGE_BG_COLOR := Color(0.86, 0.7, 0.22, 0.28)
const TAG_BADGE_TEXT_COLOR := Color(0.95, 0.85, 0.55)
const AUTHOR_COLOR := Color(0.85, 0.85, 0.88)
const DATE_COLOR := Color(0.58, 0.58, 0.62)
const HASH_COLOR := Color(0.55, 0.58, 0.66)
const DIVIDER_COLOR := Color(1, 1, 1, 0.08)
const WORKTREE_COLOR := Color(0.62, 0.62, 0.66)
const STASH_COLOR := Color(0.72, 0.6, 0.9)
const STASH_BADGE_BG_COLOR := Color(0.72, 0.6, 0.9, 0.25)

## Pseudo-oid of the "Uncommitted changes" row, whose only parent is HEAD.
const WORKTREE_OID := "worktree"

const LANE_COLORS := [
	Color(0.36, 0.66, 0.96),
	Color(0.96, 0.56, 0.26),
	Color(0.46, 0.82, 0.44),
	Color(0.86, 0.38, 0.58),
	Color(0.66, 0.52, 0.92),
	Color(0.90, 0.78, 0.26),
]

## Laid-out entries: each is the raw GitRepo.get_commit_graph() dictionary
## plus "lane" and "row". See compute_layout().
var _commits: Array = []
var _by_oid: Dictionary = {}
var _selected_row := -1
## Rows in the (Ctrl/Cmd/Shift-click) multi-selection, _selected_row included.
var _selected_rows := {}
var _head_oid := ""
## Checked-out branch ("" when detached), set by the owner; drops only make sense onto or from it.
var current_branch := ""
## Row -> Rect2 of its branch badge, from the last _draw(), so a drag can start on a badge.
var _badge_rects := {}
## Row a drag is hovering as a valid drop target, or -1.
var _drop_row := -1
## Row pressed inside a multi-selection: it becomes the only selection on release unless a drag started.
var _pending_single_row := -1

## Optional columns right of the message, in display order.
const COLUMNS := ["hash", "author", "date"]
const COLUMN_TITLES := { "hash": "Hash", "author": "Author", "date": "Date" }
const VISIBLE_COLUMNS_SETTING_KEY := "history_visible_columns"
const ABSOLUTE_DATES_SETTING_KEY := "history_absolute_dates"

## Widths are user-resizable by dragging the dividers and persisted via util/settings.gd.
var _col_width := {}
var _visible_columns: Array = COLUMNS.duplicate()
var _absolute_dates := false
## Visible column whose left divider is being dragged, or "".
var _dragging_column := ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)
	focus_mode = Control.FOCUS_CLICK
	var defaults := { "hash": DEFAULT_HASH_COL_WIDTH, "author": DEFAULT_AUTHOR_COL_WIDTH, "date": DEFAULT_DATE_COL_WIDTH }
	for column in COLUMNS:
		_col_width[column] = Settings.get_value("history_%s_col_width" % column, defaults[column])
	_visible_columns = COLUMNS.filter(func(c: String) -> bool: return Settings.get_value(VISIBLE_COLUMNS_SETTING_KEY, COLUMNS).has(c))
	_absolute_dates = Settings.get_value(ABSOLUTE_DATES_SETTING_KEY, false)


func is_column_visible(column: String) -> bool:
	return _visible_columns.has(column)


func set_column_visible(column: String, shown: bool) -> void:
	_visible_columns = COLUMNS.filter(func(c: String) -> bool: return c == column and shown or c != column and _visible_columns.has(c))
	Settings.set_value(VISIBLE_COLUMNS_SETTING_KEY, _visible_columns)
	queue_redraw()


func uses_absolute_dates() -> bool:
	return _absolute_dates


func set_absolute_dates(on: bool) -> void:
	_absolute_dates = on
	Settings.set_value(ABSOLUTE_DATES_SETTING_KEY, on)
	queue_redraw()


## Left edge of each visible column, laid out from the right edge.
func _column_x() -> Dictionary:
	var xs := {}
	var x := size.x
	for i in range(_visible_columns.size() - 1, -1, -1):
		x -= _col_width[_visible_columns[i]]
		xs[_visible_columns[i]] = x
	return xs


func _columns_left() -> float:
	var xs := _column_x()
	return xs[_visible_columns[0]] if not _visible_columns.is_empty() else size.x


## head_oid gets a ring around its dot. Selection survives if the selected commits are still listed.
func set_commits(raw_commits: Array, head_oid: String = "") -> void:
	var previously_selected := get_selected_oids()
	var primary := get_selected_oid()
	_commits = compute_layout(raw_commits)
	_head_oid = head_oid
	_by_oid.clear()
	for entry in _commits:
		_by_oid[entry["oid"]] = entry

	# Width follows the parent container (see _init); only height is forced.
	custom_minimum_size.y = _commits.size() * ROW_HEIGHT
	_selected_rows.clear()
	_selected_row = -1
	for oid in previously_selected:
		if _by_oid.has(oid):
			_selected_rows[_by_oid[oid]["row"]] = true
	if _by_oid.has(primary):
		_selected_row = _by_oid[primary]["row"]
	queue_redraw()


## Primary (last clicked) selected commit, or "".
func get_selected_oid() -> String:
	return _commits[_selected_row]["oid"] if _selected_row >= 0 and _selected_row < _commits.size() else ""


## Every selected oid, in graph order (newest first).
func get_selected_oids() -> PackedStringArray:
	var rows := _selected_rows.keys()
	rows.sort()
	var oids := PackedStringArray()
	for row in rows:
		if row < _commits.size():
			oids.append(_commits[row]["oid"])
	return oids


func select_oid(oid: String) -> void:
	if not _by_oid.has(oid):
		return
	_select_single(_by_oid[oid]["row"])


func _select_single(row: int) -> void:
	_selected_row = row
	_selected_rows = { row: true }
	queue_redraw()
	commit_selected.emit(_commits[row]["oid"])
	_scroll_row_into_view(row)


func _scroll_row_into_view(row: int) -> void:
	var sc := get_parent() as ScrollContainer
	if sc == null:
		return
	var top := row * ROW_HEIGHT
	if top < sc.scroll_vertical:
		sc.scroll_vertical = int(top)
	elif top + ROW_HEIGHT > sc.scroll_vertical + sc.size.y:
		sc.scroll_vertical = int(top + ROW_HEIGHT - sc.size.y)


## Assigns each commit a lane so a git-log --graph style graph can be
## drawn. commits must be newest-first with "oid" and "parents" per entry.
##
## `lanes` tracks, per column, which oid it's waiting to see next ("" =
## free). A commit takes the lane expecting it (or the first free one, or
## a new one), then that lane starts waiting for its first parent. Extra
## parents (merges) each claim their own lane the same way.
static func compute_layout(commits: Array) -> Array:
	var lanes: Array[String] = []
	var result: Array = []

	for row in commits.size():
		var commit: Dictionary = commits[row]
		var oid: String = commit["oid"]

		var lane_index := lanes.find(oid)
		if lane_index == -1:
			lane_index = lanes.find("")
			if lane_index == -1:
				lane_index = lanes.size()
				lanes.append("")

		# Free any other lane also waiting for this oid (a merge point),
		# so it gets reused for the rest of the graph.
		for i in lanes.size():
			if i != lane_index and lanes[i] == oid:
				lanes[i] = ""

		var entry := commit.duplicate()
		entry["lane"] = lane_index
		entry["row"] = row
		result.append(entry)

		var parents: PackedStringArray = commit["parents"]
		if parents.is_empty():
			lanes[lane_index] = ""
		else:
			lanes[lane_index] = parents[0]
			for i in range(1, parents.size()):
				var parent_oid: String = parents[i]
				if lanes.find(parent_oid) == -1:
					var free_index := lanes.find("")
					if free_index == -1:
						lanes.append(parent_oid)
					else:
						lanes[free_index] = parent_oid

	return result


func _lane_color(lane: int) -> Color:
	return LANE_COLORS[lane % LANE_COLORS.size()]


func _lane_x(lane: int) -> float:
	return LEFT_MARGIN + lane * LANE_WIDTH + LANE_WIDTH * 0.5


func _row_y(row: int) -> float:
	return row * ROW_HEIGHT + ROW_HEIGHT * 0.5


func _max_lane() -> int:
	var m := 0
	for entry in _commits:
		m = maxi(m, int(entry["lane"]))
	return m


## "main & dev", or "main +3" once there are more than two, so a badge
## never grows unbounded with a heavily-tagged/branched commit.
static func _badge_label(names: PackedStringArray) -> String:
	if names.size() <= 2:
		return " & ".join(Array(names))
	return "%s +%d" % [names[0], names.size() - 1]


## Longest prefix of text (plus an ellipsis) that fits within max_width at
## the given font/size, or text unchanged if it already fits.
static func _truncate_to_width(font: Font, font_size: int, text: String, max_width: float) -> String:
	if max_width <= 0.0:
		return ""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text

	var ellipsis_width := font.get_string_size("…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var w := font.get_string_size(text.substr(0, mid), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + ellipsis_width
		if w <= max_width:
			lo = mid
		else:
			hi = mid - 1

	return (text.substr(0, lo) + "…") if lo > 0 else "…"


## "25 minutes ago", falling back to a "DD.MM.YYYY, HH:MM" stamp once
## it's more than a week old.
static func format_absolute_time(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d.%02d.%04d, %02d:%02d" % [dt["day"], dt["month"], dt["year"], dt["hour"], dt["minute"]]


static func format_relative_time(unix_time: int, now: int = -1) -> String:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var delta := now - unix_time
	if delta < 0:
		delta = 0

	if delta < 60:
		return "just now"
	if delta < 3600:
		var m := delta / 60
		return "%d minute%s ago" % [m, "" if m == 1 else "s"]
	if delta < 86400:
		var h := delta / 3600
		return "%d hour%s ago" % [h, "" if h == 1 else "s"]
	if delta < 7 * 86400:
		var d := delta / 86400
		return "%d day%s ago" % [d, "" if d == 1 else "s"]

	return format_absolute_time(unix_time)


func _draw() -> void:
	if _commits.is_empty():
		return

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	_badge_rects.clear()

	# Only rows inside the scroll viewport are drawn — the log can be thousands of commits long once "load more" kicks in.
	var sc := get_parent() as ScrollContainer
	var view_top := float(sc.scroll_vertical) if sc != null else 0.0
	var view_bottom := view_top + (sc.size.y if sc != null else size.y)
	var first_row := maxi(0, int(view_top / ROW_HEIGHT) - 1)
	var last_row := mini(_commits.size() - 1, int(view_bottom / ROW_HEIGHT) + 1)

	for row in _selected_rows:
		if row >= first_row and row <= last_row:
			draw_rect(Rect2(0, row * ROW_HEIGHT, size.x, ROW_HEIGHT), Color(1, 1, 1, 0.08 if row == _selected_row else 0.05))
	if _selected_rows.size() > 1 and _selected_row >= first_row and _selected_row <= last_row:
		draw_rect(Rect2(0, _selected_row * ROW_HEIGHT, 3.0, ROW_HEIGHT), BADGE_TEXT_COLOR)
	if _drop_row >= 0:
		draw_rect(Rect2(1, _drop_row * ROW_HEIGHT + 1, size.x - 2, ROW_HEIGHT - 2), BADGE_TEXT_COLOR, false, 2.0)

	# Connectors first (dots draw on top); a line spanning many rows is drawn whenever it crosses the view.
	for entry in _commits:
		if int(entry["row"]) > last_row:
			break
		var from := Vector2(_lane_x(entry["lane"]), _row_y(entry["row"]))
		var parents: PackedStringArray = entry["parents"]
		for parent_oid in parents:
			if _by_oid.has(parent_oid):
				var parent_entry: Dictionary = _by_oid[parent_oid]
				if int(parent_entry["row"]) < first_row:
					continue
				var to := Vector2(_lane_x(parent_entry["lane"]), _row_y(parent_entry["row"]))
				if entry["oid"] == WORKTREE_OID or entry.has("stash"):
					draw_dashed_line(from, to, STASH_COLOR if entry.has("stash") else WORKTREE_COLOR, 2.0, 4.0)
				else:
					draw_line(from, to, _lane_color(entry["lane"]), 2.0, true)

	var graph_width := LEFT_MARGIN + (_max_lane() + 1) * LANE_WIDTH + TEXT_GAP
	var text_x := graph_width
	var col_x := _column_x()
	var message_max_width := maxf(0.0, _columns_left() - (COLUMN_GAP if not _visible_columns.is_empty() else 0.0) - text_x)
	var now := int(Time.get_unix_time_from_system())

	for column in _visible_columns:
		var divider_x: float = col_x[column] - COLUMN_GAP * 0.5
		draw_line(Vector2(divider_x, 0), Vector2(divider_x, size.y), DIVIDER_COLOR, 1.0)

	for row in range(first_row, last_row + 1):
		var entry: Dictionary = _commits[row]
		var dot := Vector2(_lane_x(entry["lane"]), _row_y(entry["row"]))
		if entry["oid"] == WORKTREE_OID:
			draw_circle(dot, DOT_RADIUS, WORKTREE_COLOR, false, 1.5, true)
			var worktree_baseline := _row_y(row) + font_size * 0.35
			var bold := get_theme_font("bold", "EditorFonts")
			var title_font: Font = bold if bold != null else font
			var title := _truncate_to_width(title_font, font_size, entry["summary"], message_max_width)
			draw_string(title_font, Vector2(text_x, worktree_baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
			var note_x := text_x + title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + BADGE_GAP
			draw_string(font, Vector2(note_x, worktree_baseline), _truncate_to_width(font, font_size, entry.get("note", ""), text_x + message_max_width - note_x),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WORKTREE_COLOR)
			continue
		if entry.has("stash"):
			draw_rect(Rect2(dot - Vector2.ONE * DOT_RADIUS, Vector2.ONE * DOT_RADIUS * 2.0), STASH_COLOR, false, 1.5)
		else:
			draw_circle(dot, DOT_RADIUS, _lane_color(entry["lane"]))
		if entry["oid"] == _head_oid:
			draw_arc(dot, DOT_RADIUS + 3.0, 0.0, TAU, 20, Color.WHITE, 1.5, true)

		var baseline_y := _row_y(entry["row"]) + font_size * 0.35
		var is_merge: bool = (entry["parents"] as PackedStringArray).size() > 1
		var message_color := MERGE_MESSAGE_COLOR if is_merge else Color.WHITE

		# Branches and tags get separate colored pills (tags gold-ish) since
		# both can be present on the same commit.
		var badges: Array = []
		if entry.has("stash"):
			badges.append({"text": entry["stash"], "bg": STASH_BADGE_BG_COLOR, "fg": STASH_COLOR})
			message_color = MERGE_MESSAGE_COLOR
		var refs: PackedStringArray = entry["refs"]
		if not refs.is_empty():
			badges.append({"text": _badge_label(refs), "bg": BADGE_BG_COLOR, "fg": BADGE_TEXT_COLOR, "branches": true})
		var tags: PackedStringArray = entry.get("tags", PackedStringArray())
		if not tags.is_empty():
			badges.append({"text": _badge_label(tags), "bg": TAG_BADGE_BG_COLOR, "fg": TAG_BADGE_TEXT_COLOR})

		var total_badge_width := 0.0
		for b in badges:
			b["width"] = font.get_string_size(b["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + BADGE_PADDING * 2
			total_badge_width += b["width"] + BADGE_GAP

		var summary: String = entry["summary"]
		var message_width_budget := message_max_width - total_badge_width
		var shown_summary := _truncate_to_width(font, font_size, summary, message_width_budget)

		draw_string(font, Vector2(text_x, baseline_y), shown_summary, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, message_color)

		if not badges.is_empty():
			var shown_width := font.get_string_size(shown_summary, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var badge_x := text_x + shown_width + BADGE_GAP
			for b in badges:
				var badge_rect := Rect2(badge_x, _row_y(entry["row"]) - font_size * 0.65, b["width"], font_size * 1.3)
				draw_rect(badge_rect, b["bg"])
				if b.get("branches", false):
					_badge_rects[row] = badge_rect
				draw_string(font, Vector2(badge_x + BADGE_PADDING, baseline_y), b["text"],
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, b["fg"])
				badge_x += b["width"] + BADGE_GAP

		for column in _visible_columns:
			var width: float = _col_width[column]
			var cell_pos := Vector2(col_x[column], baseline_y)
			match column:
				"hash":
					draw_string(font, cell_pos, String(entry["oid"]).substr(0, 7), HORIZONTAL_ALIGNMENT_LEFT, width - COLUMN_GAP, font_size, HASH_COLOR)
				"author":
					draw_string(font, cell_pos, _truncate_to_width(font, font_size, entry.get("author_name", ""), width - COLUMN_GAP),
							HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AUTHOR_COLOR)
				"date":
					var time := int(entry.get("time", 0))
					var date_text := format_absolute_time(time) if _absolute_dates else format_relative_time(time, now)
					draw_string(font, cell_pos, _truncate_to_width(font, font_size, date_text, width), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, DATE_COLOR)


## Visible column whose left divider is within DIVIDER_HIT_MARGIN of local x, or "".
func _divider_at_x(x: float) -> String:
	var col_x := _column_x()
	for column in _visible_columns:
		if absf(x - (col_x[column] - COLUMN_GAP * 0.5)) <= DIVIDER_HIT_MARGIN:
			return column
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _dragging_column.is_empty():
			var index := _visible_columns.find(_dragging_column)
			var after := 0.0
			var others := 0.0
			for i in _visible_columns.size():
				if i > index:
					after += _col_width[_visible_columns[i]]
				if i != index:
					others += _col_width[_visible_columns[i]]
			_col_width[_dragging_column] = clampf(size.x - after - COLUMN_GAP * 0.5 - event.position.x, MIN_COL_WIDTH, maxf(MIN_COL_WIDTH, size.x - others - MIN_COL_WIDTH))
			queue_redraw()
		else:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if not _divider_at_x(event.position.x).is_empty() else Control.CURSOR_ARROW
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var divider := _divider_at_x(event.position.x)
			if not divider.is_empty():
				_dragging_column = divider
				return

			var row := int(event.position.y / ROW_HEIGHT)
			if row >= 0 and row < _commits.size():
				if event.shift_pressed and _selected_row >= 0:
					if not (event.ctrl_pressed or event.meta_pressed):
						_selected_rows.clear()
					for r in range(mini(_selected_row, row), maxi(_selected_row, row) + 1):
						_selected_rows[r] = true
					queue_redraw()
				elif event.ctrl_pressed or event.meta_pressed:
					if _selected_rows.has(row) and _selected_rows.size() > 1:
						_selected_rows.erase(row)
						if _selected_row == row:
							_selected_row = _selected_rows.keys()[0]
					else:
						_selected_rows[row] = true
						_selected_row = row
						commit_selected.emit(_commits[row]["oid"])
					queue_redraw()
				elif _selected_rows.has(row) and _selected_rows.size() > 1 and not event.double_click:
					_pending_single_row = row # keep the selection for a drag of all of it
				else:
					_select_single(row)
					if event.double_click:
						commit_activated.emit(_commits[row]["oid"])
		elif _pending_single_row >= 0:
			if _pending_single_row < _commits.size():
				_select_single(_pending_single_row)
			_pending_single_row = -1
		elif not _dragging_column.is_empty():
			Settings.set_value("history_%s_col_width" % _dragging_column, _col_width[_dragging_column])
			_dragging_column = ""
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var row := int(event.position.y / ROW_HEIGHT)
		if row < 0 or row >= _commits.size():
			return
		# Right-click inside a multi-selection keeps it (the menu acts on all of them).
		if not _selected_rows.has(row):
			_selected_rows = { row: true }
		_selected_row = row
		queue_redraw()
		commit_context_requested.emit(_commits[row]["oid"], get_screen_position() + event.position.round())
		return

	if event is InputEventKey and event.pressed and not _commits.is_empty():
		var step := 0
		match event.keycode:
			KEY_UP: step = -1
			KEY_DOWN: step = 1
			KEY_PAGEUP: step = -10
			KEY_PAGEDOWN: step = 10
		if step != 0:
			_select_single(clampi(_selected_row + step, 0, _commits.size() - 1))
			accept_event()


static func _is_pseudo(entry: Dictionary) -> bool:
	return entry["oid"] == WORKTREE_OID or entry.has("stash")


func _row_at(y: float) -> int:
	var row := int(y / ROW_HEIGHT)
	return row if row >= 0 and row < _commits.size() else -1


## A branch badge drags its branches; any other spot drags the commit (or the whole selection it's part of).
func _get_drag_data(at_position: Vector2) -> Variant:
	var row := _row_at(at_position.y)
	if not _dragging_column.is_empty() or row < 0 or _is_pseudo(_commits[row]):
		return null
	_pending_single_row = -1
	var preview := Label.new()
	preview.add_theme_color_override("font_color", BADGE_TEXT_COLOR)
	if _badge_rects.has(row) and (_badge_rects[row] as Rect2).grow(2.0).has_point(at_position):
		var refs: PackedStringArray = _commits[row]["refs"]
		preview.text = _badge_label(refs)
		set_drag_preview(preview)
		return { "godit_refs": refs, "from_row": row }
	if not _selected_rows.has(row):
		_select_single(row)
	var oids := PackedStringArray(Array(get_selected_oids()).filter(func(o: String) -> bool: return not _is_pseudo(_by_oid[o])))
	preview.text = "%d commits" % oids.size() if oids.size() > 1 else "%s  %s" % [oids[0].substr(0, 7), _commits[row]["summary"]]
	set_drag_preview(preview)
	return { "godit_commits": oids, "from_row": row }


## Commits drop onto the current branch's row; a branch drops onto another branch's row when one of the two is the current branch.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var row := _row_at(at_position.y)
	var ok: bool = row >= 0 and data is Dictionary and row != data.get("from_row", -1) and not _is_pseudo(_commits[row]) and _accepts(_commits[row], data)
	var shown := row if ok else -1
	if shown != _drop_row:
		_drop_row = shown
		queue_redraw()
	return ok


func _accepts(target: Dictionary, data: Dictionary) -> bool:
	if current_branch.is_empty():
		return false
	var target_refs: PackedStringArray = target["refs"]
	if data.has("godit_commits"):
		return (target_refs.has(current_branch) or target["oid"] == _head_oid) and not (data["godit_commits"] as PackedStringArray).has(target["oid"])
	if data.has("godit_refs"):
		var refs: PackedStringArray = data["godit_refs"]
		if refs.has(current_branch):
			return Array(target_refs).any(func(r: String) -> bool: return r != current_branch)
		return target_refs.has(current_branch)
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target_oid: String = _commits[_row_at(at_position.y)]["oid"]
	_drop_row = -1
	queue_redraw()
	if data.has("godit_commits"):
		commits_dropped.emit(data["godit_commits"], target_oid)
	else:
		refs_dropped.emit(data["godit_refs"], target_oid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drop_row >= 0:
		_drop_row = -1
		queue_redraw()
	# _draw() only covers the rows the scroll viewport showed then; a taller viewport (bigger panel, floating window) must redraw, though this control's own size stays the same.
	elif what == NOTIFICATION_READY and get_parent() is ScrollContainer:
		get_parent().resized.connect(queue_redraw)
