@tool
extends VBoxContainer

const HUNK_HEADER_PATTERN := "^@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@(.*)$"
const DiffHunks := preload("res://addons/gittydot/util/diff_hunks.gd")
const GitCli := preload("res://addons/gittydot/util/git_cli.gd")
const SyntaxColors := preload("res://addons/gittydot/util/syntax_colors.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")
const SceneText := preload("res://addons/gittydot/util/scene_text.gd")
const WorkingDiff := preload("res://addons/gittydot/dock/widgets/working_diff.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]
## Godot rewrites these on save without any real change; with "Hide Godot noise" on, a -/+ pair differing only here is dimmed.
const NOISE_PATTERNS := [" uid=\"uid://[a-z0-9]+\"", " load_steps=\\d+", " unique_id=\\d+"]

const OPT_SIDE_BY_SIDE := 0
const OPT_IGNORE_WHITESPACE := 1
const OPT_SYNTAX := 2
const OPT_HIDE_NOISE := 3
const OPT_CONTEXT_3 := 10
const OPT_CONTEXT_10 := 11
const OPT_CONTEXT_25 := 12
const OPT_CONTEXT_FULL := 13
const CONTEXT_BY_ID := { OPT_CONTEXT_3: 3, OPT_CONTEXT_10: 10, OPT_CONTEXT_25: 25, OPT_CONTEXT_FULL: -1 }

## A hunk (or just its selected lines) should be staged/unstaged/reverted. action: "stage"|"unstage"|"revert"; patch is ready for GitCliRepo.apply_patch().
signal hunk_action_requested(action: String, patch: String)
## A diff option changed (context lines, whitespace) — the owner should re-fetch the diff with get_options() and call show_diff() again.
signal options_changed
signal layout_changed(side_by_side: bool)
## Double-click on a line: open the file there (new_line is 1-based, in the new version).
signal open_location_requested(path: String, new_line: int)
## One of the tabs set with set_tabs() was clicked.
signal tab_selected(index: int)
signal working_file_saved

var _tabs: TabBar
var _header_bar: PanelContainer
var _header_label: Label
var _stats_added: Label
var _stats_removed: Label
var _options_button: MenuButton
var _empty_label: Label
var _scroll: ScrollContainer
var _rows_view: Control
var _split: HSplitContainer
var _panes: Array[ScrollContainer] = []
var _pane_rows: Array[Control] = []
var _syncing_scroll := false
var _aligning_panes := false
var _image_view: HBoxContainer
var _scene_toggle: Button
## Node-by-node view of a .tscn/.tres change, instead of the text diff.
var _scene_tree: Tree
var _working_view: Control

var _diff_text := ""
var _context: Dictionary = {}
var _hunks: Array = []
var _file_header := ""


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	_tabs = TabBar.new()
	_tabs.visible = false
	_tabs.clip_tabs = false
	_tabs.tab_clicked.connect(func(index: int) -> void: tab_selected.emit(index))
	add_child(_tabs)

	_header_bar = PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(1, 1, 1, 0.045)
	header_style.content_margin_left = 8.0
	header_style.content_margin_right = 4.0
	header_style.content_margin_top = 2.0
	header_style.content_margin_bottom = 2.0
	_header_bar.add_theme_stylebox_override("panel", header_style)
	_header_bar.visible = false

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)

	_header_label = Label.new()
	_header_label.clip_text = true
	_header_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_header_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
	_header_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(_header_label)

	_stats_added = Label.new()
	_stats_added.add_theme_color_override("font_color", DiffRows.COLOR_ADDED_TEXT)
	header_row.add_child(_stats_added)

	_stats_removed = Label.new()
	_stats_removed.add_theme_color_override("font_color", DiffRows.COLOR_REMOVED_TEXT)
	header_row.add_child(_stats_removed)

	_scene_toggle = Button.new()
	_scene_toggle.text = "Scene"
	_scene_toggle.toggle_mode = true
	_scene_toggle.flat = true
	_scene_toggle.visible = false
	_scene_toggle.toggled.connect(func(on: bool) -> void:
		Settings.set_value("diff_scene_view", on)
		_rerender(true)
	)
	header_row.add_child(_scene_toggle)

	_options_button = MenuButton.new()
	_options_button.text = "⋯"
	_options_button.tooltip_text = "Diff options"
	_options_button.flat = true
	_build_options_menu()
	header_row.add_child(_options_button)

	_header_bar.add_child(header_row)
	add_child(_header_bar)

	_empty_label = Label.new()
	_empty_label.text = "No diff to show."
	_empty_label.modulate.a = 0.6
	_empty_label.size_flags_vertical = SIZE_EXPAND_FILL
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_label)

	_image_view = HBoxContainer.new()
	_image_view.size_flags_vertical = SIZE_EXPAND_FILL
	_image_view.visible = false
	add_child(_image_view)

	_scene_tree = Tree.new()
	_scene_tree.hide_root = true
	_scene_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_scene_tree.visible = false
	add_child(_scene_tree)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.visible = false
	add_child(_scroll)

	_rows_view = DiffRows.new()
	_rows_view.action_pressed.connect(_on_rows_action_pressed)
	_rows_view.row_double_clicked.connect(func(new_line: int) -> void:
		if new_line > 0 and not String(_context.get("path", "")).is_empty():
			open_location_requested.emit(_context["path"], new_line)
	)
	_scroll.add_child(_rows_view)
	_scroll.resized.connect(func() -> void:
		_rows_view._recalculate_layout()
		_rows_view.queue_redraw()
	)
	_scroll.get_h_scroll_bar().value_changed.connect(func(_v: float) -> void: _rows_view.queue_redraw())
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _rows_view.queue_redraw())
	_build_split_panes()
	_working_view = WorkingDiff.new()
	_working_view.visible = false
	_working_view.file_saved.connect(working_file_saved.emit)
	add_child(_working_view)


func _build_split_panes() -> void:
	_split = HSplitContainer.new()
	_split.size_flags_horizontal = SIZE_EXPAND_FILL
	_split.size_flags_vertical = SIZE_EXPAND_FILL
	_split.visible = false
	add_child(_split)
	for side in 2:
		var pane := ScrollContainer.new()
		pane.size_flags_horizontal = SIZE_EXPAND_FILL
		pane.size_flags_vertical = SIZE_EXPAND_FILL
		pane.custom_minimum_size.x = UiScale.px(120)
		pane.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		pane.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_split.add_child(pane)
		_panes.append(pane)
		var view := DiffRows.new()
		view._side_index = side
		view.action_pressed.connect(_on_rows_action_pressed)
		view.row_double_clicked.connect(func(line: int) -> void:
			if line > 0 and not String(_context.get("path", "")).is_empty():
				open_location_requested.emit(_context["path"], line)
		)
		view.selection_changed.connect(func(anchor: int) -> void:
			for sibling in _pane_rows:
				sibling._anchor = anchor
				sibling.queue_redraw()
		)
		pane.add_child(view)
		_pane_rows.append(view)
		pane.resized.connect(_resize_panes)
		pane.get_h_scroll_bar().visibility_changed.connect(_align_panes.call_deferred)
		pane.get_v_scroll_bar().visibility_changed.connect(_align_panes.call_deferred)
		pane.get_h_scroll_bar().value_changed.connect(_sync_pane_scroll.bind(side, true))
		pane.get_v_scroll_bar().value_changed.connect(_sync_pane_scroll.bind(side, false))
	_split.dragged.connect(func(_offset: int) -> void: _resize_panes())


func _resize_panes() -> void:
	for view in _pane_rows:
		view._recalculate_layout()
		view.queue_redraw()
	_align_panes.call_deferred()


func _align_panes() -> void:
	if not _split.visible or _aligning_panes:
		return
	_aligning_panes = true
	# One shared pixel range keeps corresponding columns aligned, even with
	# unequal pane widths or one version having much longer lines.
	var viewport_widths := []
	var overflow := 0.0
	for side in 2:
		var width := _panes[side].size.x
		if _panes[side].get_v_scroll_bar().visible:
			width -= _panes[side].get_v_scroll_bar().size.x
		viewport_widths.append(width)
		overflow = maxf(overflow, _pane_rows[side]._natural_width - width)
	for side in 2:
		var view := _pane_rows[side]
		var minimum: Vector2 = view.custom_minimum_size
		minimum.x = viewport_widths[side] + overflow if overflow > 0 else view._natural_width
		view.custom_minimum_size = minimum
		view.queue_redraw()
		# 4.7 caches the largest child independently of the ScrollContainer's
		# own minimum (which stays constant). Refresh it before sorting a
		# smaller diff, or the old scroll range can survive the content change.
		_panes[side].get_minimum_size()
		_panes[side].queue_sort()
	_aligning_panes = false


func _sync_pane_scroll(value: float, source: int, horizontal: bool) -> void:
	if _syncing_scroll or not _split.visible:
		return
	_syncing_scroll = true
	var target := _panes[1 - source]
	if horizontal:
		target.get_h_scroll_bar().value = value
	else:
		target.get_v_scroll_bar().value = value
	for view in _pane_rows:
		view.queue_redraw()
	_syncing_scroll = false


# --- options -----------------------------------------------------------------


static func _setting(key: String, default: Variant) -> Variant:
	return Settings.get_value("diff_" + key, default)


## {"context": int, "ignore_whitespace": bool} — pass to GitCliRepo's diff getters.
func get_options() -> Dictionary:
	return { "context": _setting("context", 3), "ignore_whitespace": _setting("ignore_whitespace", false) }


func set_side_by_side(enabled: bool) -> void:
	if not flush_working_editor():
		layout_changed.emit(_setting("side_by_side", true))
		return
	Settings.set_value("diff_side_by_side", enabled)
	_rerender()
	_sync_options_menu()
	layout_changed.emit(enabled)


func _build_options_menu() -> void:
	var popup := _options_button.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.about_to_popup.connect(_sync_options_menu)
	popup.add_check_item("Side by side", OPT_SIDE_BY_SIDE)
	popup.add_check_item("Ignore whitespace", OPT_IGNORE_WHITESPACE)
	popup.add_check_item("Syntax highlighting", OPT_SYNTAX)
	popup.add_check_item("Dim Godot noise (uid / load_steps)", OPT_HIDE_NOISE)
	popup.add_separator("Context")
	popup.add_radio_check_item("3 lines", OPT_CONTEXT_3)
	popup.add_radio_check_item("10 lines", OPT_CONTEXT_10)
	popup.add_radio_check_item("25 lines", OPT_CONTEXT_25)
	popup.add_radio_check_item("Whole file", OPT_CONTEXT_FULL)
	popup.id_pressed.connect(_on_option_pressed)


func _sync_options_menu() -> void:
	var popup := _options_button.get_popup()
	popup.set_item_checked(popup.get_item_index(OPT_SIDE_BY_SIDE), _setting("side_by_side", true))
	popup.set_item_checked(popup.get_item_index(OPT_IGNORE_WHITESPACE), _setting("ignore_whitespace", false))
	popup.set_item_checked(popup.get_item_index(OPT_SYNTAX), _setting("syntax", true))
	popup.set_item_checked(popup.get_item_index(OPT_HIDE_NOISE), _setting("hide_noise", true))
	var context: int = _setting("context", 3)
	var editing: bool = _working_view != null and _working_view.visible
	for id in [OPT_IGNORE_WHITESPACE, OPT_HIDE_NOISE] + CONTEXT_BY_ID.keys():
		popup.set_item_disabled(popup.get_item_index(id), editing)
		popup.set_item_tooltip(popup.get_item_index(id), "Editable comparisons show the complete file without filtering. Switch to Unified for the inspection options." if editing else "")
	for id in CONTEXT_BY_ID:
		popup.set_item_checked(popup.get_item_index(id), CONTEXT_BY_ID[id] == context)


func _on_option_pressed(id: int) -> void:
	match id:
		OPT_SIDE_BY_SIDE:
			set_side_by_side(not _setting("side_by_side", true))
		OPT_SYNTAX:
			Settings.set_value("diff_syntax", not _setting("syntax", true))
			_rerender()
		OPT_HIDE_NOISE:
			Settings.set_value("diff_hide_noise", not _setting("hide_noise", true))
			_rerender()
		OPT_IGNORE_WHITESPACE:
			Settings.set_value("diff_ignore_whitespace", not _setting("ignore_whitespace", false))
			options_changed.emit()
		_:
			if CONTEXT_BY_ID.has(id):
				Settings.set_value("diff_context", CONTEXT_BY_ID[id])
				options_changed.emit()
	_sync_options_menu()


# --- content -----------------------------------------------------------------


## context (all optional): {"actions": hunk buttons ("stage"/"unstage"/"revert"), "path", "repo", "old_rev"/"new_rev" for image previews ("" = working tree, ":" = index), "note"}.
func show_diff(diff_text: String, context: Dictionary = {}) -> void:
	if _working_view != null and _working_view.is_dirty() and (context.get("path", "") != _context.get("path", "") or not context.get("editable_worktree", false)):
		if not flush_working_editor():
			return
	var previous_path: String = _context.get("path", "")
	var keep_scroll: bool = previous_path == context.get("path", "") and not previous_path.is_empty() and _diff_text != ""
	_diff_text = diff_text
	_context = context
	_rerender(keep_scroll)


func clear_diff() -> void:
	set_tabs([])
	show_diff("")


## Small tab strip above the diff (e.g. Unstaged / Staged); empty hides it.
func set_tabs(labels: Array, current: int = 0) -> void:
	_tabs.visible = labels.size() > 1
	if not _tabs.visible:
		return
	_tabs.tab_count = labels.size()
	for i in labels.size():
		_tabs.set_tab_title(i, labels[i])
	_tabs.set_block_signals(true)
	_tabs.current_tab = current
	_tabs.set_block_signals(false)


## Scrolls so new-file line `line` is in view (e.g. revealing a gutter marker's hunk).
func scroll_to_line(line: int) -> void:
	if _working_view != null and _working_view.visible:
		_working_view.scroll_to_line(line)
		return
	var view: Control = _pane_rows[1] if _split.visible else _rows_view
	var scroll: ScrollContainer = _panes[1] if _split.visible else _scroll
	var y: float = view.y_for_new_line(line)
	if y >= 0.0:
		scroll.scroll_vertical = int(maxf(0.0, y - scroll.size.y * 0.3))


func _rerender(keep_scroll: bool = false) -> void:
	# Engine-owned controls survive an in-place script reload.
	if not is_instance_valid(_split):
		_build_split_panes()
	var parsed := _parse(_diff_text, _setting("hide_noise", true))
	var split := DiffHunks.split_hunks(_diff_text)
	_hunks = split["hunks"]
	_file_header = split["file_header"]

	var path: String = parsed["path"] if not String(parsed["path"]).is_empty() else _context.get("path", "")
	var rows: Array = parsed["rows"]
	var note: String = _context.get("note", "")

	_header_bar.visible = not path.is_empty()
	_header_label.text = path + ("   · " + note if not note.is_empty() else "")
	_header_label.tooltip_text = path
	_stats_added.text = ("+%d" % parsed["added"]) if parsed["added"] > 0 else ""
	_stats_removed.text = ("−%d" % parsed["removed"]) if parsed["removed"] > 0 else ""

	var show_image := _show_image_preview(path)
	var editing: bool = _setting("side_by_side", true) and not show_image and WorkingDiff.eligible(_context)
	_working_view.visible = editing
	_working_view._codes[1].editable = editing
	_scene_toggle.disabled = editing
	if editing:
		_working_view.show_file(_context)
		_scroll.hide()
		_split.hide()
		_scene_tree.hide()
		_empty_label.hide()
		_scene_toggle.visible = SceneText.is_scene_file(path) or SceneText.is_config_file(path)
		_scene_toggle.text = "Settings" if SceneText.is_config_file(path) else "Scene"
		_scene_toggle.tooltip_text = "Structured view is available in read-only comparisons"
		_sync_options_menu()
		return
	var is_config := SceneText.is_config_file(path)
	var can_show_scene: bool = (SceneText.is_scene_file(path) or is_config) and _context.get("repo", null) != null and _context.has("new_rev")
	_scene_toggle.visible = can_show_scene
	_scene_toggle.text = "Settings" if is_config else "Scene"
	_scene_toggle.tooltip_text = "Show the change setting by setting, grouped by section, instead of as text" if is_config \
			else "Show the change node by node (added/removed nodes, changed properties, connections) instead of as text"
	_scene_toggle.set_pressed_no_signal(_setting("scene_view", false))
	_scene_tree.visible = can_show_scene and _scene_toggle.button_pressed and not _diff_text.is_empty()
	if _scene_tree.visible:
		_build_scene_tree(path)
		_scroll.visible = false
		_split.visible = false
		_empty_label.visible = false
		return
	var actions: Array = _context.get("actions", [])
	var line_level: bool = not parsed["is_new"] and not parsed["is_deleted"]
	if _setting("ignore_whitespace", false):
		actions = [] # a whitespace-insensitive diff doesn't match the file closely enough to apply back
	var language := SyntaxColors.language_for(path) if _setting("syntax", true) else ""

	var side_by_side: bool = _setting("side_by_side", true)
	_rows_view.set_content(rows, actions, line_level, language, false)
	for view in _pane_rows:
		view.set_content(rows, actions, line_level, language, true)
	# Selection on either version addresses the same underlying patch rows.
	_pane_rows[1]._selected = _pane_rows[0]._selected
	var has_rows := not rows.is_empty()
	_scroll.visible = has_rows and not side_by_side
	_split.visible = has_rows and side_by_side
	_align_panes.call_deferred()
	_scroll.get_minimum_size()
	_scroll.queue_sort()
	_empty_label.visible = not has_rows and not show_image
	if not has_rows and not show_image:
		_empty_label.text = "Binary file changed." if parsed["binary"] else "No diff to show."

	if not keep_scroll:
		# Otherwise the previous file's scroll offset carries over and clips the top of the new diff.
		_scroll.scroll_horizontal = 0
		_scroll.scroll_vertical = 0
		for pane in _panes:
			pane.scroll_horizontal = 0
			pane.scroll_vertical = 0


func flush_working_editor() -> bool:
	if _working_view == null or _working_view.flush():
		return true
	Dialogs.error(self, "Comparison save paused", _working_view._block_reason)
	return false


const SCENE_ADDED_COLOR := Color(0.55, 0.85, 0.55)
const SCENE_REMOVED_COLOR := Color(0.95, 0.5, 0.5)
const SCENE_CHANGED_COLOR := Color(0.95, 0.82, 0.5)
const SCENE_VALUE_MAX := 120


func _build_scene_tree(path: String) -> void:
	var repo: RefCounted = _context["repo"]
	var old_text: String = repo.get_file_bytes(_context.get("old_rev", "HEAD"), _context.get("old_path", path)).get_string_from_utf8()
	var new_text: String = repo.get_file_bytes(_context.get("new_rev", ""), path).get_string_from_utf8()
	var is_config := SceneText.is_config_file(path)
	var d := SceneText.config_diff(old_text, new_text) if is_config else SceneText.diff(old_text, new_text)
	_scene_tree.clear()
	var root := _scene_tree.create_item()
	for n in d["nodes"]:
		_add_scene_item(root, n)
	if not d["resources"].is_empty():
		var group := _scene_group(root, "Resources")
		for r in d["resources"]:
			_add_scene_item(group, r)
	if not d["connections_added"].is_empty() or not d["connections_removed"].is_empty():
		var group := _scene_group(root, "Signal connections")
		for c in d["connections_added"]:
			_scene_line(group, "+ " + c, SCENE_ADDED_COLOR)
		for c in d["connections_removed"]:
			_scene_line(group, "− " + c, SCENE_REMOVED_COLOR)
	if root.get_child_count() == 0:
		_scene_line(root, "No setting changed — only formatting (see the text diff)." if is_config \
				else "No changes to nodes, resources or connections — only ids or formatting (see the text diff).", Color(1, 1, 1, 0.6))


func _scene_group(parent: TreeItem, title: String) -> TreeItem:
	var item := _scene_tree.create_item(parent)
	item.set_text(0, title)
	item.set_custom_color(0, Color(1, 1, 1, 0.6))
	item.set_selectable(0, false)
	return item


func _scene_line(parent: TreeItem, text: String, color: Color) -> TreeItem:
	var item := _scene_tree.create_item(parent)
	var shown := text.replace("\n", " ⏎ ")
	item.set_text(0, shown if shown.length() <= SCENE_VALUE_MAX * 2 else shown.left(SCENE_VALUE_MAX * 2) + "…")
	item.set_tooltip_text(0, text)
	item.set_custom_color(0, color)
	return item


## One node or resource: "+ Root/Enemy (Sprite2D)", with its property changes underneath.
func _add_scene_item(parent: TreeItem, entry: Dictionary) -> void:
	var status: String = entry["status"]
	var color: Color = { "added": SCENE_ADDED_COLOR, "removed": SCENE_REMOVED_COLOR }.get(status, SCENE_CHANGED_COLOR)
	var sign: String = { "added": "+ ", "removed": "− " }.get(status, "")
	var type: String = entry["type"]
	var item := _scene_line(parent, "%s%s%s" % [sign, entry["path"], "  (%s)" % type if not type.is_empty() else ""], color)
	if has_theme_icon(type, "EditorIcons"):
		item.set_icon(0, get_theme_icon(type, "EditorIcons"))
	if status == "removed":
		return
	for change in entry["props"]:
		if change["key"] == "(type)" and status == "added":
			continue
		var key: String = change["key"]
		if change["old"] == null:
			_scene_line(item, "%s = %s" % [key, _short(change["new"])], SCENE_ADDED_COLOR).set_tooltip_text(0, "%s = %s" % [key, change["new"]])
		elif change["new"] == null:
			_scene_line(item, "%s (removed, was %s)" % [key, _short(change["old"])], SCENE_REMOVED_COLOR).set_tooltip_text(0, "%s was %s" % [key, change["old"]])
		else:
			_scene_line(item, "%s: %s → %s" % [key, _short(change["old"]), _short(change["new"])], Color.WHITE).set_tooltip_text(0, "%s\nbefore: %s\nafter: %s" % [key, change["old"], change["new"]])
	item.collapsed = status == "added" and entry["props"].size() > 6


static func _short(value: String) -> String:
	value = value.replace("\n", " ⏎ ")
	return value if value.length() <= SCENE_VALUE_MAX else value.left(SCENE_VALUE_MAX) + "…"


func _on_rows_action_pressed(action: String, hunk_index: int, selected: PackedInt32Array) -> void:
	if hunk_index < 0 or hunk_index >= _hunks.size():
		return
	var reverse := action != "stage"
	hunk_action_requested.emit(action, DiffHunks.build_patch(_file_header, _hunks[hunk_index], selected, reverse))


## Before/after thumbnails for image files; returns whether it's showing.
func _show_image_preview(path: String) -> bool:
	for child in _image_view.get_children():
		child.queue_free()
	var repo: RefCounted = _context.get("repo", null)
	var is_image := IMAGE_EXTENSIONS.has(path.get_extension().to_lower())
	_image_view.visible = is_image and repo != null and _context.has("new_rev")
	if not _image_view.visible:
		return false
	var old_rev: String = _context.get("old_rev", "HEAD")
	var new_rev: String = _context.get("new_rev", "")
	var old_path: String = _context.get("old_path", path)
	_image_view.add_child(_image_panel("Before", repo.get_file_bytes(old_rev, old_path), path.get_extension()))
	_image_view.add_child(_image_panel("After", repo.get_file_bytes(new_rev, path), path.get_extension()))
	return true


static func _image_panel(caption: String, bytes: PackedByteArray, extension: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if not bytes.is_empty():
		match extension.to_lower():
			"png": err = image.load_png_from_buffer(bytes)
			"jpg", "jpeg": err = image.load_jpg_from_buffer(bytes)
			"webp": err = image.load_webp_from_buffer(bytes)
			"svg": err = image.load_svg_from_buffer(bytes)
			"bmp": err = image.load_bmp_from_buffer(bytes)
			"tga": err = image.load_tga_from_buffer(bytes)
	if bytes.is_empty():
		label.text = "%s — (none)" % caption
		return box
	if err != OK:
		label.text = "%s — can't preview (%s)" % [caption, String.humanize_size(bytes.size())]
		return box

	label.text = "%s — %d×%d, %s" % [caption, image.get_width(), image.get_height(), String.humanize_size(bytes.size())]
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = SIZE_EXPAND_FILL
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if maxi(image.get_width(), image.get_height()) < 128 else CanvasItem.TEXTURE_FILTER_LINEAR
	box.add_child(rect)
	return box


## {"path", "added", "removed", "binary", "is_new", "is_deleted", "rows"}; rows are line rows {"type", "old_no"/"new_no" (-1 = none), "text", "hl" (changed ranges), "hunk", "li" (index in hunk body)} or hunk rows {"type": "hunk", "hunk", "gap", "heading", "header"}.
static func _parse(diff_text: String, hide_noise: bool) -> Dictionary:
	var result := {"path": "", "added": 0, "removed": 0, "binary": false, "is_new": false, "is_deleted": false, "rows": []}
	var rows: Array = result["rows"]
	if diff_text.is_empty():
		return result

	var lines := diff_text.split("\n")
	var n := lines.size()

	var hunk_regex := RegEx.new()
	hunk_regex.compile(HUNK_HEADER_PATTERN)
	var noise_regex: RegEx = null
	if hide_noise:
		noise_regex = RegEx.new()
		noise_regex.compile("|".join(NOISE_PATTERNS))

	var prev_new_end := 0
	var hunk_index := -1

	var i := 0
	while i < n:
		var line: String = lines[i]

		if line.begins_with("Binary files "):
			result["binary"] = true
		if line.begins_with("new file mode"):
			result["is_new"] = true
		if line.begins_with("deleted file mode"):
			result["is_deleted"] = true

		if (line.begins_with("+++ ") or line.begins_with("--- ")) and String(result["path"]).is_empty():
			var p := line.substr(4).strip_edges()
			if p != "/dev/null":
				result["path"] = _strip_ab_prefix(p)
			i += 1
			continue

		var header_match := hunk_regex.search(line)
		if header_match == null:
			i += 1
			continue

		hunk_index += 1
		var old_start := header_match.get_string(1).to_int()
		var new_start := header_match.get_string(3).to_int()
		rows.append({
			"type": "hunk", "hunk": hunk_index, "header": line,
			"gap": maxi(0, new_start - prev_new_end - 1) if hunk_index > 0 or new_start > 1 else 0,
			"heading": header_match.get_string(5).strip_edges(),
		})

		var old_line := old_start
		var new_line := new_start
		i += 1
		var body_start := i

		while i < n and not lines[i].begins_with("@@") and not lines[i].begins_with("diff --git"):
			var body_line: String = lines[i]

			if body_line.length() > 0 and body_line[0] == "\\": # "\ No newline at end of file"
				i += 1
				continue
			if body_line.is_empty() and i == n - 1:
				break # trailing newline of the whole diff

			if body_line.begins_with("-"):
				var removed_start := i
				while i < n and lines[i].begins_with("-") or (i < n and lines[i].begins_with("\\")):
					i += 1
				var added_start := i
				while i < n and lines[i].begins_with("+") or (i < n and lines[i].begins_with("\\")):
					i += 1
				var removed_idx := _indices(lines, removed_start, added_start, "-")
				var added_idx := _indices(lines, added_start, i, "+")

				var pair_count: int = mini(removed_idx.size(), added_idx.size())
				for k in pair_count:
					var old_text: String = lines[removed_idx[k]].substr(1)
					var new_text: String = lines[added_idx[k]].substr(1)
					if noise_regex != null and noise_regex.sub(old_text, "", true) == noise_regex.sub(new_text, "", true):
						rows.append(_line_row("noise", old_line, -1, old_text, [], hunk_index, removed_idx[k] - body_start))
						rows.append(_line_row("noise", -1, new_line, new_text, [], hunk_index, added_idx[k] - body_start))
					else:
						var hl := _word_diff(old_text, new_text)
						var removed_row := _line_row("removed", old_line, -1, old_text, hl[0], hunk_index, removed_idx[k] - body_start)
						var added_row := _line_row("added", -1, new_line, new_text, hl[1], hunk_index, added_idx[k] - body_start)
						# A modified line is one -/+ pair: partial stage/revert must always take both halves.
						removed_row["pair_li"] = added_row["li"]
						added_row["pair_li"] = removed_row["li"]
						rows.append(removed_row)
						rows.append(added_row)
						result["removed"] += 1
						result["added"] += 1
					old_line += 1
					new_line += 1

				for k in range(pair_count, removed_idx.size()):
					rows.append(_line_row("removed", old_line, -1, lines[removed_idx[k]].substr(1), [], hunk_index, removed_idx[k] - body_start))
					old_line += 1
					result["removed"] += 1
				for k in range(pair_count, added_idx.size()):
					rows.append(_line_row("added", -1, new_line, lines[added_idx[k]].substr(1), [], hunk_index, added_idx[k] - body_start))
					new_line += 1
					result["added"] += 1
				continue

			if body_line.begins_with("+"):
				rows.append(_line_row("added", -1, new_line, body_line.substr(1), [], hunk_index, i - body_start))
				new_line += 1
				result["added"] += 1
				i += 1
				continue

			var content := body_line.substr(1) if body_line.length() > 0 else ""
			rows.append(_line_row("context", old_line, new_line, content, [], hunk_index, i - body_start))
			old_line += 1
			new_line += 1
			i += 1

		prev_new_end = new_line - 1

	return result


static func _indices(lines: PackedStringArray, from: int, to: int, marker: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(from, to):
		if lines[k].begins_with(marker):
			out.append(k)
	return out


static func _line_row(type: String, old_no: int, new_no: int, text: String, hl: Array, hunk: int, li: int) -> Dictionary:
	return {"type": type, "old_no": old_no, "new_no": new_no, "text": text, "hl": hl, "hunk": hunk, "li": li}


static func _strip_ab_prefix(path: String) -> String:
	path = GitCli.unquote(path)
	if path.begins_with("a/") or path.begins_with("b/"):
		return path.substr(2)
	return path


## Word-level diff of a changed line pair: [old_ranges, new_ranges], each an Array of Vector2i(start, length) to highlight. Tokens are words, runs of whitespace and single punctuation chars, matched with an LCS; lines that changed almost entirely get no highlight (it'd just be noise).
static func _word_diff(old_text: String, new_text: String) -> Array:
	var a := _tokenize(old_text)
	var b := _tokenize(new_text)
	if a.size() * b.size() > 90000:
		return _prefix_suffix_diff(old_text, new_text)

	var rows := a.size() + 1
	var cols := b.size() + 1
	var table := PackedInt32Array()
	table.resize(rows * cols)
	for x in range(a.size() - 1, -1, -1):
		for y in range(b.size() - 1, -1, -1):
			if a[x] == b[y]:
				table[x * cols + y] = table[(x + 1) * cols + y + 1] + 1
			else:
				table[x * cols + y] = maxi(table[(x + 1) * cols + y], table[x * cols + y + 1])

	var old_keep := PackedByteArray()
	old_keep.resize(a.size())
	var new_keep := PackedByteArray()
	new_keep.resize(b.size())
	var x := 0
	var y := 0
	while x < a.size() and y < b.size():
		if a[x] == b[y]:
			old_keep[x] = 1
			new_keep[y] = 1
			x += 1
			y += 1
		elif table[(x + 1) * cols + y] >= table[x * cols + y + 1]:
			x += 1
		else:
			y += 1

	var old_ranges := _ranges(a, old_keep)
	var new_ranges := _ranges(b, new_keep)
	if _covered(old_ranges) > old_text.length() * 0.7 and _covered(new_ranges) > new_text.length() * 0.7:
		return [[], []]
	return [old_ranges, new_ranges]


static func _tokenize(text: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		var j := i + 1
		if ch == " " or ch == "\t":
			while j < n and (text[j] == " " or text[j] == "\t"):
				j += 1
		elif ch == "_" or ch.to_lower() != ch.to_upper() or ch.is_valid_int():
			while j < n and (text[j] == "_" or text[j].to_lower() != text[j].to_upper() or text[j].is_valid_int()):
				j += 1
		tokens.append(text.substr(i, j - i))
		i = j
	return tokens


## Merges adjacent non-kept tokens into (start, length) character ranges.
static func _ranges(tokens: PackedStringArray, keep: PackedByteArray) -> Array:
	var ranges: Array = []
	var pos := 0
	for t in tokens.size():
		var length := tokens[t].length()
		if keep[t] == 0:
			if not ranges.is_empty() and ranges[-1].x + ranges[-1].y == pos:
				ranges[-1] = Vector2i(ranges[-1].x, ranges[-1].y + length)
			else:
				ranges.append(Vector2i(pos, length))
		pos += length
	return ranges


static func _covered(ranges: Array) -> int:
	var total := 0
	for r in ranges:
		total += r.y
	return total


static func _prefix_suffix_diff(a: String, b: String) -> Array:
	var max_len: int = mini(a.length(), b.length())
	var prefix := 0
	while prefix < max_len and a[prefix] == b[prefix]:
		prefix += 1
	var suffix := 0
	while suffix < max_len - prefix and a[a.length() - 1 - suffix] == b[b.length() - 1 - suffix]:
		suffix += 1
	var old_len := a.length() - prefix - suffix
	var new_len := b.length() - prefix - suffix
	return [[Vector2i(prefix, old_len)] if old_len > 0 else [], [Vector2i(prefix, new_len)] if new_len > 0 else []]


## Custom-drawn rows (RTL's [bgcolor] can't fill a row edge-to-edge): backgrounds, gutters, word highlights, syntax, hunk buttons, line selection; only visible rows are drawn.
class DiffRows:
	extends Control

	signal action_pressed(action: String, hunk: int, selected: PackedInt32Array)
	signal row_double_clicked(new_line: int)
	signal selection_changed(anchor: int)

	## Pixel metrics, scaled by the editor's display scale (vars, not consts, for that reason).
	var GUTTER_PAD := UiScale.px(10.0)
	var MARKER_WIDTH := UiScale.px(22.0)
	var TEXT_RIGHT_PAD := UiScale.px(24.0)
	var LINE_PAD_Y := UiScale.px(6.0)
	var CONTENT_PAD_Y := UiScale.px(4.0)
	var BUTTON_PAD_X := UiScale.px(8.0)
	var BUTTON_GAP := UiScale.px(6.0)
	var SIDE_GAP := UiScale.px(6.0)

	const COLOR_ADDED_BG := Color(0.208, 0.408, 0.235, 0.35)
	const COLOR_REMOVED_BG := Color(0.443, 0.176, 0.192, 0.35)
	const COLOR_ADDED_HL := Color(0.239, 0.541, 0.267, 0.9)
	const COLOR_REMOVED_HL := Color(0.545, 0.157, 0.184, 0.9)
	const COLOR_ADDED_TEXT := Color(0.643, 0.851, 0.667)
	const COLOR_REMOVED_TEXT := Color(0.925, 0.588, 0.604)
	const COLOR_CONTEXT_TEXT := Color(0.78, 0.78, 0.8)
	const COLOR_NOISE_TEXT := Color(0.6, 0.6, 0.64, 0.55)
	const COLOR_LINE_NO := Color(0.45, 0.45, 0.5)
	const COLOR_HUNK_BG := Color(0.35, 0.5, 0.85, 0.12)
	const COLOR_HUNK_TEXT := Color(0.6, 0.68, 0.85)
	const COLOR_SELECTED_BG := Color(0.4, 0.6, 1.0, 0.22)
	const COLOR_SELECTED_BAR := Color(0.45, 0.65, 1.0)
	const COLOR_BUTTON_BG := Color(1, 1, 1, 0.1)
	const COLOR_BUTTON_HOVER := Color(1, 1, 1, 0.2)
	const COLOR_EMPTY_SIDE := Color(0, 0, 0, 0.12)

	const ACTION_LABELS := { "stage": "Stage", "unstage": "Unstage", "revert": "Revert" }

	var _rows: Array = []
	## What's drawn, one entry per visual row: {"u": row index} (unified / hunk rows) or {"l": idx, "r": idx} (side by side, -1 = blank).
	var _display: Array = []
	var _actions: Array = []
	var _line_level := true
	var _language := ""
	var _side_by_side := false
	## -1 is the unified view; 0/1 are independently clipped old/new panes.
	var _side_index := -1
	var _natural_width := 0.0
	var _gutter_width := 30.0
	var _row_height := 20.0
	var _baseline_offset := 14.0
	var _side_width := 0.0
	## Unified row indices currently selected (only added/removed rows), and the last clicked one (shift-click range anchor).
	var _selected := {}
	var _anchor := -1
	## [{"rect": Rect2, "action": String, "hunk": int}] from the last _draw().
	var _buttons: Array = []
	var _hover_button := -1


	func _init() -> void:
		size_flags_horizontal = SIZE_EXPAND_FILL
		size_flags_vertical = SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS
		focus_mode = Control.FOCUS_CLICK


	## The script editor's own monospace font, so the diff reads like code
	## instead of UI text. Falls back to the default UI font outside the
	## editor theme (e.g. when unit-testing this script standalone).
	func _code_font() -> Font:
		if has_theme_font("source", "EditorFonts"):
			return get_theme_font("source", "EditorFonts")
		return get_theme_default_font()


	func _code_font_size() -> int:
		if has_theme_font_size("source_size", "EditorFonts"):
			return get_theme_font_size("source_size", "EditorFonts")
		return get_theme_default_font_size()


	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED and not _rows.is_empty():
			_recalculate_layout()
			queue_redraw()


	func set_content(rows: Array, actions: Array, line_level: bool, language: String, side_by_side: bool) -> void:
		_rows = rows
		_actions = actions
		_line_level = line_level
		_language = language
		_side_by_side = side_by_side
		_selected.clear()
		_anchor = -1
		_build_display()
		_recalculate_layout()
		queue_redraw()


	func _build_display() -> void:
		_display.clear()
		if not _side_by_side:
			for i in _rows.size():
				_display.append({ "u": i })
			return
		# Pair each run of removed rows with the run of added rows that follows it.
		var i := 0
		while i < _rows.size():
			var type: String = _rows[i]["type"]
			if type == "hunk" or type == "context":
				_display.append({ "u": i } if type == "hunk" else { "l": i, "r": i })
				i += 1
				continue
			var left: Array = []
			var right: Array = []
			while i < _rows.size() and _rows[i]["type"] in ["removed", "added", "noise"]:
				if _rows[i]["old_no"] > 0:
					left.append(i)
				else:
					right.append(i)
				i += 1
			for k in maxi(left.size(), right.size()):
				_display.append({ "l": left[k] if k < left.size() else -1, "r": right[k] if k < right.size() else -1 })


	func _recalculate_layout() -> void:
		if _rows.is_empty():
			custom_minimum_size = Vector2.ZERO
			return

		var font := _code_font()
		var font_size := _code_font_size()
		_row_height = ceilf(font.get_height(font_size)) + LINE_PAD_Y
		_baseline_offset = font.get_ascent(font_size) + LINE_PAD_Y * 0.5

		var max_no := 1
		var max_text := 0.0
		for row in _rows:
			if row["type"] == "hunk":
				continue
			max_no = maxi(max_no, maxi(int(row["old_no"]), int(row["new_no"])))
			if _side_index >= 0 and int(row["old_no"] if _side_index == 0 else row["new_no"]) <= 0:
				continue
			max_text = maxf(max_text, font.get_string_size(row["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)

		var digits := str(max_no).length()
		_gutter_width = font.get_string_size("0".repeat(digits), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + GUTTER_PAD

		var width: float
		if _side_index >= 0:
			width = _gutter_width + MARKER_WIDTH + max_text + TEXT_RIGHT_PAD
		elif _side_by_side:
			_side_width = _gutter_width + MARKER_WIDTH + max_text + TEXT_RIGHT_PAD
			var viewport_half := (_viewport_width() - SIDE_GAP) * 0.5
			_side_width = maxf(_side_width, viewport_half)
			width = _side_width * 2 + SIDE_GAP
		else:
			width = _gutter_width * 2 + MARKER_WIDTH + max_text + TEXT_RIGHT_PAD
		_natural_width = width
		custom_minimum_size = Vector2(width, _display.size() * _row_height + CONTENT_PAD_Y * 2)


	func _scroll_container() -> ScrollContainer:
		return get_parent() as ScrollContainer


	func _viewport_width() -> float:
		var sc := _scroll_container()
		return sc.size.x if sc != null else size.x


	func _row_top(display_index: int) -> float:
		return CONTENT_PAD_Y + display_index * _row_height


	## Y of the display row showing new-file line `line`, or -1.
	func y_for_new_line(line: int) -> float:
		for d in _display.size():
			for key in ["u", "r"]:
				var idx: int = _display[d].get(key, -1)
				if idx >= 0 and _rows[idx]["type"] != "hunk" and int(_rows[idx]["new_no"]) >= line:
					return _row_top(d)
		return -1.0


	func _draw() -> void:
		_buttons.clear()
		if _rows.is_empty():
			return

		var sc := _scroll_container()
		var view_top := float(sc.scroll_vertical) if sc != null else 0.0
		var view_height := sc.size.y if sc != null else size.y
		var view_left := float(sc.scroll_horizontal) if sc != null else 0.0
		var view_width := _viewport_width()

		var first := maxi(0, int((view_top - CONTENT_PAD_Y) / _row_height) - 1)
		var last := mini(_display.size() - 1, int((view_top + view_height - CONTENT_PAD_Y) / _row_height) + 1)

		for d in range(first, last + 1):
			var y := _row_top(d)
			var entry: Dictionary = _display[d]
			if entry.has("u"):
				var row: Dictionary = _rows[entry["u"]]
				if row["type"] == "hunk":
					_draw_hunk_row(row, y, view_left, view_width)
				else:
					_draw_line(entry["u"], 0.0, size.x, y, _gutter_width, true)
				continue
			if _side_index >= 0:
				_draw_side(entry["l"] if _side_index == 0 else entry["r"], 0.0, y, _side_index == 0)
			else:
				_draw_side(entry["l"], 0.0, y, true)
				_draw_side(entry["r"], _side_width + SIDE_GAP, y, false)


	func _draw_side(idx: int, x: float, y: float, is_left: bool) -> void:
		var width := size.x if _side_index >= 0 else _side_width
		if idx < 0:
			draw_rect(Rect2(x, y, width, _row_height), COLOR_EMPTY_SIDE)
			return
		var row: Dictionary = _rows[idx]
		if row["type"] == "context":
			# Context rows are shared by both sides; each side shows its own line number.
			_draw_line(idx, x, width, y, 0.0, false, row["old_no"] if is_left else row["new_no"])
			return
		_draw_line(idx, x, width, y, 0.0, false)


	## Draws one line row starting at x with the given width. two_gutters: unified layout (old + new number columns); otherwise a single column showing only_no (or whichever number the row has).
	func _draw_line(idx: int, x: float, width: float, y: float, _gutter: float, two_gutters: bool, only_no: int = -2) -> void:
		var row: Dictionary = _rows[idx]
		var font := _code_font()
		var font_size := _code_font_size()
		var baseline := y + _baseline_offset
		var type: String = row["type"]
		var text: String = row["text"]

		var bg_color := Color(0, 0, 0, 0)
		var text_color := COLOR_CONTEXT_TEXT
		var marker := " "
		match type:
			"added":
				bg_color = COLOR_ADDED_BG
				text_color = COLOR_ADDED_TEXT
				marker = "+"
			"removed":
				bg_color = COLOR_REMOVED_BG
				text_color = COLOR_REMOVED_TEXT
				marker = "-"
			"noise":
				text_color = COLOR_NOISE_TEXT
				marker = "~"

		if bg_color.a > 0.0:
			draw_rect(Rect2(x, y, width, _row_height), bg_color)
		if _selected.has(idx):
			draw_rect(Rect2(x, y, width, _row_height), COLOR_SELECTED_BG)
			draw_rect(Rect2(x, y, 3.0, _row_height), COLOR_SELECTED_BAR)

		var number_x := x
		if two_gutters:
			if row["old_no"] > 0:
				draw_string(font, Vector2(number_x, baseline), str(row["old_no"]),
						HORIZONTAL_ALIGNMENT_RIGHT, _gutter_width - GUTTER_PAD * 0.5, font_size, COLOR_LINE_NO)
			if row["new_no"] > 0:
				draw_string(font, Vector2(number_x + _gutter_width, baseline), str(row["new_no"]),
						HORIZONTAL_ALIGNMENT_RIGHT, _gutter_width - GUTTER_PAD * 0.5, font_size, COLOR_LINE_NO)
			number_x += _gutter_width * 2
		else:
			var no: int = only_no if only_no != -2 else (row["old_no"] if row["old_no"] > 0 else row["new_no"])
			if no > 0:
				draw_string(font, Vector2(number_x, baseline), str(no),
						HORIZONTAL_ALIGNMENT_RIGHT, _gutter_width - GUTTER_PAD * 0.5, font_size, COLOR_LINE_NO)
			number_x += _gutter_width

		draw_string(font, Vector2(number_x, baseline), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		var text_x := number_x + MARKER_WIDTH

		for r in row["hl"]:
			var pre_w: float = font.get_string_size(text.substr(0, r.x), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var mid_w: float = font.get_string_size(text.substr(r.x, r.y), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_rect(Rect2(text_x + pre_w, y + 1.0, mid_w, _row_height - 2.0), COLOR_ADDED_HL if type == "added" else COLOR_REMOVED_HL)

		if _language.is_empty() or type == "noise":
			draw_string(font, Vector2(text_x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
			return

		if not row.has("syntax"):
			row["syntax"] = SyntaxColors.spans(text, _language)
		var base_color := COLOR_CONTEXT_TEXT if type == "context" else text_color.lerp(Color(0.9, 0.9, 0.92), 0.55)
		_draw_colored(font, font_size, text, text_x, baseline, row["syntax"], base_color)


	## Draws text in segments: spans' colors where covered, base_color in between.
	func _draw_colored(font: Font, font_size: int, text: String, x: float, baseline: float, spans: Array, base_color: Color) -> void:
		var pos := 0
		var cursor := x
		for span in spans:
			var start: int = span[0]
			if start > pos:
				var gap := text.substr(pos, start - pos)
				draw_string(font, Vector2(cursor, baseline), gap, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_color)
				cursor += font.get_string_size(gap, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var piece := text.substr(start, span[1])
			draw_string(font, Vector2(cursor, baseline), piece, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, span[2])
			cursor += font.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			pos = start + int(span[1])
		if pos < text.length():
			draw_string(font, Vector2(cursor, baseline), text.substr(pos), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_color)


	func _draw_hunk_row(row: Dictionary, y: float, view_left: float, view_width: float) -> void:
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var code_font := _code_font()
		var code_size := _code_font_size()
		draw_rect(Rect2(0, y, size.x, _row_height), COLOR_HUNK_BG)

		var gap: int = row["gap"]
		var label := ""
		if gap > 0:
			label = "⋯ %d unchanged line%s" % [gap, "" if gap == 1 else "s"]
		var heading: String = row["heading"]
		if not heading.is_empty():
			label += ("    " if not label.is_empty() else "") + heading
		if label.is_empty():
			label = row["header"]
		var baseline := y + _baseline_offset
		draw_string(code_font, Vector2(view_left + 8.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, code_size - 1), COLOR_HUNK_TEXT)

		if _actions.is_empty():
			return
		# Buttons stick to the right edge of the visible area, whatever the horizontal scroll.
		var hunk: int = row["hunk"]
		var selected_count := _selected_in_hunk(hunk).size()
		var right := view_left + view_width - 6.0
		for a in range(_actions.size() - 1, -1, -1):
			var action: String = _actions[a]
			var text: String = ACTION_LABELS.get(action, action)
			text += (" %d line%s" % [selected_count, "" if selected_count == 1 else "s"]) if selected_count > 0 else " hunk"
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + BUTTON_PAD_X * 2
			var rect := Rect2(right - w, y + 2.0, w, _row_height - 4.0)
			var hovered := _buttons.size() == _hover_button
			draw_style_box(_button_style(hovered, action == "revert"), rect)
			draw_string(font, Vector2(rect.position.x + BUTTON_PAD_X, y + _baseline_offset), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					Color(1, 0.75, 0.75) if action == "revert" else Color(0.9, 0.92, 1.0))
			_buttons.append({ "rect": rect, "action": action, "hunk": hunk })
			right -= w + BUTTON_GAP


	func _button_style(hovered: bool, destructive: bool) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_BUTTON_HOVER if hovered else COLOR_BUTTON_BG
		if destructive and hovered:
			style.bg_color = Color(0.8, 0.3, 0.3, 0.35)
		style.set_corner_radius_all(3)
		return style


	## hunk-local line indices (row["li"]) of the selected rows in hunk.
	## with_pairs adds each modified line's other half, so selecting just the + (or -) side of a change still reverts/stages it as a whole.
	func _selected_in_hunk(hunk: int, with_pairs := false) -> PackedInt32Array:
		var out := PackedInt32Array()
		for idx in _selected:
			var row: Dictionary = _rows[idx]
			if row["hunk"] != hunk:
				continue
			if not out.has(row["li"]):
				out.append(row["li"])
			if with_pairs and row.has("pair_li") and not out.has(row["pair_li"]):
				out.append(row["pair_li"])
		out.sort()
		return out


	func _button_at(pos: Vector2) -> int:
		for b in _buttons.size():
			if (_buttons[b]["rect"] as Rect2).has_point(pos):
				return b
		return -1


	## Unified row index under pos (in side-by-side, whichever half was clicked), or -1.
	func _row_at(pos: Vector2) -> int:
		var d := int((pos.y - CONTENT_PAD_Y) / _row_height)
		if d < 0 or d >= _display.size():
			return -1
		var entry: Dictionary = _display[d]
		if entry.has("u"):
			return entry["u"]
		if _side_index >= 0:
			return entry["l"] if _side_index == 0 else entry["r"]
		return entry["l"] if pos.x < _side_width + SIDE_GAP * 0.5 else entry["r"]


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var hover := _button_at(event.position)
			if hover != _hover_button:
				_hover_button = hover
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover >= 0 else Control.CURSOR_ARROW
				queue_redraw()
			return

		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
			return

		var button := _button_at(event.position)
		if button >= 0:
			var b: Dictionary = _buttons[button]
			action_pressed.emit(b["action"], b["hunk"], _selected_in_hunk(b["hunk"], true))
			accept_event()
			return

		var idx := _row_at(event.position)
		if event.double_click:
			if idx >= 0 and _rows[idx]["type"] != "hunk":
				var row: Dictionary = _rows[idx]
				row_double_clicked.emit(row["new_no"] if row["new_no"] > 0 else _nearest_new_line(idx))
			return

		if _actions.is_empty() or not _line_level or idx < 0 or not _rows[idx]["type"] in ["added", "removed"]:
			if not _selected.is_empty():
				_selected.clear()
				queue_redraw()
				selection_changed.emit(_anchor)
			return

		var additive: bool = event.ctrl_pressed or event.meta_pressed
		if event.shift_pressed and _anchor >= 0 and _rows[_anchor]["hunk"] == _rows[idx]["hunk"]:
			if not additive:
				_selected.clear()
			for k in range(mini(_anchor, idx), maxi(_anchor, idx) + 1):
				if _rows[k]["type"] in ["added", "removed"]:
					_selected[k] = true
		elif additive:
			if _selected.has(idx):
				_selected.erase(idx)
			else:
				_selected[idx] = true
			_anchor = idx
		else:
			var only_this := _selected.size() == 1 and _selected.has(idx)
			_selected.clear()
			if not only_this:
				_selected[idx] = true
			_anchor = idx
		accept_event()
		queue_redraw()
		selection_changed.emit(_anchor)


	## A removed line has no new-file number — use the closest following one.
	func _nearest_new_line(idx: int) -> int:
		for k in range(idx, _rows.size()):
			if _rows[k]["type"] != "hunk" and int(_rows[k]["new_no"]) > 0:
				return _rows[k]["new_no"]
		return 1


	func _get_tooltip(at_position: Vector2) -> String:
		if _button_at(at_position) >= 0:
			return "Applies to the selected lines in this hunk (click +/− lines to select; Shift/Ctrl-click to extend)." \
					if _line_level else "Applies to the whole hunk."
		return ""
