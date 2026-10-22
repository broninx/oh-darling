@tool
extends Control

const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")
const RepoWatcher := preload("res://addons/gittydot/util/repo_watcher.gd")
const TreeFolders := preload("res://addons/gittydot/util/tree_folders.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const Settings := preload("res://addons/gittydot/util/settings.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const WebLinks := preload("res://addons/gittydot/util/web_links.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")
const GitErrors := preload("res://addons/gittydot/util/git_errors.gd")
const ChangesetDialog := preload("res://addons/gittydot/dock/widgets/changeset_dialog.gd")
const CommitGraph := preload("res://addons/gittydot/dock/widgets/commit_graph.gd")
const GitStatusFlags := preload("res://addons/gittydot/util/git_status_flags.gd")
const WORKTREE_OID := CommitGraph.WORKTREE_OID

## From the "Uncommitted changes" row; plugin.gd brings the Changes tab to front and runs action there ("", "commit", "stash", "revert").
signal changes_requested(action: String)
## Open a selected historical or working-file comparison in the central workspace.
signal diff_requested(context: Dictionary)
signal amend_requested(oid: String)

const DETAILS_VISIBLE_SETTING_KEY := "history_details_visible"
const SHOW_REMOTES_SETTING_KEY := "history_show_remotes"
const SHOW_STASHES_SETTING_KEY := "history_show_stashes"
const SEARCH_LIMIT := 500
const MERGE_MODES := {
	"Default (fast-forward when possible)": "",
	"Always create a merge commit (--no-ff)": "no-ff",
	"Fast-forward only": "ff-only",
	"Squash (stage the changes, commit them yourself)": "squash",
}

const DETAIL_PANE_RATIO := 1.0 / 3.0


## Commits loaded at first, and added each time the list is scrolled to its end.
const PAGE_SIZE := 300

enum {
	ID_COPY_HASH = 1, ID_COPY_MESSAGE, ID_CREATE_BRANCH, ID_CHECKOUT_COMMIT, ID_RESET_TO_HERE,
	ID_CREATE_TAG, ID_CHERRY_PICK, ID_CHERRY_PICK_NO_COMMIT, ID_REVERT_COMMIT, ID_COMPARE_WORKTREE,
	ID_COMPARE_SELECTED, ID_REWORD, ID_FIXUP, ID_SQUASH, ID_DROP, ID_UNDO_LAST, ID_SHOW_CHANGES, ID_OPEN_ON_WEB,
	ID_AMEND,
}
enum { ID_WORKTREE_COMMIT = 200, ID_WORKTREE_STASH, ID_WORKTREE_REVERT }
enum { ID_STASH_SHOW = 300, ID_STASH_APPLY, ID_STASH_POP, ID_STASH_DROP, ID_STASH_COMPARE_WORKTREE }
enum { ID_FILE_OPEN = 100, ID_FILE_HISTORY, ID_FILE_RESTORE_THIS, ID_FILE_RESTORE_BEFORE, ID_FILE_COPY_PATH, ID_FILE_OPEN_ON_WEB, ID_FILE_DIFF }

@onready var _search_edit: LineEdit = %SearchEdit
var _search_mode: OptionButton
## Whole-history matches after Enter in the search box, or null while only the loaded commits are filtered.
var _search_results: Variant = null
@onready var _split: HSplitContainer = %Split
@onready var _graph_split: VSplitContainer = %GraphSplit
@onready var _graph_scroll: ScrollContainer = %GraphScroll
@onready var _graph: Control = %CommitGraph
@onready var _detail_margin: Control = %DetailMargin
@onready var _details_toggle: CheckButton = %DetailsToggle
@onready var _files_tree: Tree = %FilesTree
@onready var _detail_separator: Control = %DetailSeparator
@onready var _detail_label: RichTextLabel = %DetailLabel
@onready var _context_menu: PopupMenu = %ContextMenu
@onready var _error_dialog: AcceptDialog = %ErrorDialog
@onready var _checkout_confirm_dialog: ConfirmationDialog = %CheckoutConfirmDialog
@onready var _reset_dialog: ConfirmationDialog = %ResetDialog
@onready var _reset_message_label: Label = %ResetMessageLabel
@onready var _reset_hard_check: CheckBox = %ResetHardCheck
@onready var _new_branch_dialog: ConfirmationDialog = %NewBranchDialog
@onready var _new_branch_name_edit: LineEdit = %NewBranchNameEdit
@onready var _new_branch_checkout_check: CheckBox = %NewBranchCheckoutCheck

## Set by godit_dock.gd; a git_cli_repo.gd instance.
var _repo: RefCounted
var _all_commits: Array = []
var _commits_by_oid: Dictionary = {}
var _limit := PAGE_SIZE

## The commit the context menu was last opened for, for the dialogs'
## confirmed handlers (same pattern as changes_panel.gd's _context_target).
var _context_oid := ""
## Every commit the context menu acts on (multi-selection), newest first.
var _context_oids := PackedStringArray()
## The commit whose files are listed in the detail pane.
var _detail_oid := ""
var _file_context_path := ""

## Refs + HEAD at the last refresh, so a poll only reloads the graph when history moved.
var _last_refs_signature := ""
## `git status` output at the last refresh, so the "Uncommitted changes" row follows edits too.
var _last_status_signature := ""
## get_status() entries behind the "Uncommitted changes" row.
var _worktree_files: Array = []
## list_stash_commits(), drawn next to the commits they were made on.
var _stashes: Array = []

var _branch_option: OptionButton
var _remotes_check: CheckBox
var _stashes_check: CheckBox
var _path_chip: HBoxContainer
var _path_label: Label
var _path_filter := ""
var _count_label: Label
var _undo_button: Button
## last_head_operation() at the last refresh.
var _undo_op: Dictionary = {}

var _file_diff_box: VBoxContainer
var _file_menu: PopupMenu


func _ready() -> void:
	if UiScale.is_in_edited_scene(self):
		return # opened in the scene editor, not running in a dock
	UiScale.scale_scene(self)
	_split.resized.connect(_update_split_offset)
	_update_split_offset()
	_files_tree.item_activated.connect(_on_files_tree_item_activated)
	_files_tree.item_selected.connect(_on_files_tree_item_selected)
	_files_tree.allow_rmb_select = true
	_files_tree.item_mouse_selected.connect(_on_files_tree_item_mouse_selected)
	_details_toggle.button_pressed = Settings.get_value(DETAILS_VISIBLE_SETTING_KEY, true)
	_build_toolbar()
	_build_file_diff()
	_graph.commits_dropped.connect(_on_commits_dropped)
	_graph.refs_dropped.connect(_on_refs_dropped)
	_graph.commit_activated.connect(func(oid: String) -> void:
		if oid == WORKTREE_OID:
			changes_requested.emit("commit")
	)

	_file_menu = PopupMenu.new()
	_file_menu.id_pressed.connect(_on_file_menu_id_pressed)
	add_child(_file_menu)

	var v_bar := _graph_scroll.get_v_scroll_bar()
	v_bar.value_changed.connect(func(value: float) -> void:
		_graph.queue_redraw()
		# Scrolled to the end of a full page: there's probably more history, fetch the next page.
		if value + v_bar.page >= v_bar.max_value - 4.0 and _all_commits.size() >= _limit and _search_edit.text.is_empty():
			_limit += PAGE_SIZE
			refresh.call_deferred()
	)


func _build_toolbar() -> void:
	var toolbar: HBoxContainer = $Layout/Toolbar

	_branch_option = OptionButton.new()
	_branch_option.tooltip_text = "Which branches to show"
	_branch_option.fit_to_longest_item = false
	_branch_option.custom_minimum_size.x = UiScale.px(150)
	_branch_option.clip_text = true
	_branch_option.item_selected.connect(func(_i: int) -> void: refresh())
	toolbar.add_child(_branch_option)
	toolbar.move_child(_branch_option, 1)

	_remotes_check = CheckBox.new()
	_remotes_check.text = "Remotes"
	_remotes_check.tooltip_text = "Also show commits that are only on remote-tracking branches (e.g. fetched but not pulled)"
	_remotes_check.button_pressed = Settings.get_value(SHOW_REMOTES_SETTING_KEY, true)
	_remotes_check.toggled.connect(func(on: bool) -> void:
		Settings.set_value(SHOW_REMOTES_SETTING_KEY, on)
		refresh()
	)
	toolbar.add_child(_remotes_check)
	toolbar.move_child(_remotes_check, 2)

	_stashes_check = CheckBox.new()
	_stashes_check.text = "Stashes"
	_stashes_check.tooltip_text = "Show stashes next to the commits they were made on"
	_stashes_check.button_pressed = Settings.get_value(SHOW_STASHES_SETTING_KEY, true)
	_stashes_check.toggled.connect(func(on: bool) -> void:
		Settings.set_value(SHOW_STASHES_SETTING_KEY, on)
		refresh()
	)
	toolbar.add_child(_stashes_check)
	toolbar.move_child(_stashes_check, 3)

	_path_chip = HBoxContainer.new()
	_path_chip.visible = false
	_path_label = Label.new()
	_path_label.modulate = Color(0.95, 0.85, 0.55)
	_path_label.clip_text = true
	_path_label.custom_minimum_size.x = UiScale.px(60)
	_path_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_path_chip.add_child(_path_label)
	var clear := Button.new()
	clear.text = "✕"
	clear.flat = true
	clear.tooltip_text = "Show all files again"
	clear.pressed.connect(func() -> void: set_path_filter(""))
	_path_chip.add_child(clear)
	toolbar.add_child(_path_chip)
	toolbar.move_child(_path_chip, 4)

	_search_mode = OptionButton.new()
	_search_mode.add_item("Message", 0)
	_search_mode.add_item("Author", 1)
	_search_mode.add_item("Code", 2)
	_search_mode.tooltip_text = "What the search box matches. Typing filters the loaded commits; Enter searches the whole history (Code: commits that added or removed the text)."
	_search_mode.item_selected.connect(func(_i: int) -> void:
		_update_search_placeholder()
		_on_search_edit_text_changed(_search_edit.text)
	)
	toolbar.add_child(_search_mode)
	toolbar.move_child(_search_mode, _search_edit.get_index() + 1)
	_search_edit.text_submitted.connect(func(_t: String) -> void: _run_full_search())
	_update_search_placeholder()

	_count_label = Label.new()
	_count_label.modulate.a = 0.6
	toolbar.add_child(_count_label)
	toolbar.move_child(_count_label, toolbar.get_child_count() - 2)

	_undo_button = Button.new()
	_undo_button.text = "Undo"
	_undo_button.pressed.connect(_on_undo_pressed)
	toolbar.add_child(_undo_button)
	toolbar.move_child(_undo_button, 1)

	var columns_button := MenuButton.new()
	columns_button.text = "Columns"
	columns_button.flat = false
	columns_button.tooltip_text = "Which columns the log shows"
	var popup := columns_button.get_popup()
	popup.hide_on_checkable_item_selection = false
	var columns: Array = CommitGraph.COLUMNS
	for i in columns.size():
		popup.add_check_item(CommitGraph.COLUMN_TITLES[columns[i]], i)
	popup.add_separator()
	popup.add_check_item("Absolute Dates", columns.size())
	popup.about_to_popup.connect(func() -> void:
		for i in columns.size():
			popup.set_item_checked(popup.get_item_index(i), _graph.is_column_visible(columns[i]))
		popup.set_item_checked(popup.get_item_index(columns.size()), _graph.uses_absolute_dates())
		popup.set_item_disabled(popup.get_item_index(columns.size()), not _graph.is_column_visible("date"))
	)
	popup.id_pressed.connect(func(id: int) -> void:
		var index := popup.get_item_index(id)
		var checked := not popup.is_item_checked(index)
		popup.set_item_checked(index, checked)
		if id < columns.size():
			_graph.set_column_visible(columns[id], checked)
			popup.set_item_disabled(popup.get_item_index(columns.size()), not _graph.is_column_visible("date"))
		else:
			_graph.set_absolute_dates(checked)
	)
	toolbar.add_child(columns_button)
	toolbar.move_child(columns_button, _details_toggle.get_index())


func _build_file_diff() -> void:
	# Retire an existing inline preview after a source reload. Fresh docks never create it.
	_hide_inline_diff()


func _hide_inline_diff() -> void:
	if is_instance_valid(_file_diff_box):
		_file_diff_box.hide()


## split_offset is a pixel offset from the container's midpoint, not a
## fraction, so it's recomputed on every resize to keep the detail pane at
## a constant ~1/3 width.
func _update_split_offset() -> void:
	var total := _split.size.x
	if total <= 0.0:
		return
	_split.split_offset = int(total * (0.5 - DETAIL_PANE_RATIO))


func set_repo(repo: RefCounted) -> void:
	_repo = repo
	_update_branch_option()
	refresh()
	RepoWatcher.watch(self, _on_polled)


## Limits the log to commits touching path ("" = no filter) — the Changes panel's "Show History".
## Selects oid in the graph (e.g. from a click in the blame column), looking it up by hash if it isn't among the loaded commits.
func show_commit(oid: String) -> void:
	if _repo == null:
		return
	var shown: Array = _search_results if _search_results != null else _all_commits
	if not shown.any(func(c: Dictionary) -> bool: return c["oid"] == oid):
		_search_mode.select(0)
		_update_search_placeholder()
		_search_edit.text = oid.substr(0, 12)
		_on_search_edit_text_changed(_search_edit.text)
		await _run_full_search()
	_graph.select_oid(oid)


func set_path_filter(path: String) -> void:
	_path_filter = path
	_path_chip.visible = not path.is_empty()
	_path_label.text = "File: " + path.get_file()
	_path_label.tooltip_text = path
	_limit = PAGE_SIZE
	refresh()


func _log_options() -> Dictionary:
	var ref := ""
	if _branch_option.selected > 0:
		ref = _branch_option.get_item_text(_branch_option.selected)
	return { "remotes": _remotes_check.button_pressed, "ref": ref, "path": _path_filter }


func _update_branch_option() -> void:
	var current := _branch_option.get_item_text(_branch_option.selected) if _branch_option.selected >= 0 else ""
	_branch_option.clear()
	_branch_option.add_item("All branches")
	for b in _repo.list_branches(false):
		_branch_option.add_item(b["name"])
		if b["name"] == current:
			_branch_option.select(_branch_option.item_count - 1)
	if _branch_option.selected < 0:
		_branch_option.select(0)


## Reloads the graph only when a ref, HEAD or the uncommitted files changed; hidden, it waits for the poll that comes with being shown.
func _on_polled(snapshot: Dictionary) -> void:
	if _repo == null or _repo.is_busy() or not is_visible_in_tree():
		return
	var status: Array = _repo.parse_status(snapshot["status"])
	if _refs_signature(snapshot) == _last_refs_signature and _status_signature(status) == _last_status_signature:
		return
	_update_branch_option()
	refresh(status)


## status_entries: a get_status() result the caller already has, to skip fetching it again.
func refresh(status_entries: Variant = null) -> void:
	if _repo == null:
		return

	var status: Array = status_entries if status_entries != null else _repo.get_status()
	_graph.current_branch = _repo.get_current_branch()
	_update_undo_button()
	_last_refs_signature = _refs_signature(_repo.read_snapshot())
	_last_status_signature = _status_signature(status)
	_stashes = _repo.list_stash_commits() if _path_filter.is_empty() and _stashes_check.button_pressed else []
	_worktree_files = status.filter(func(e: Dictionary) -> bool:
		return not e["status"] & GitStatusFlags.IGNORED and (_path_filter.is_empty() or e["path"] == _path_filter or e["path"].begins_with(_path_filter.trim_suffix("/") + "/")))
	_all_commits = _repo.get_commit_graph(_limit, _log_options())
	_commits_by_oid.clear()
	for c in _all_commits + _stashes + (_search_results if _search_results != null else []):
		_commits_by_oid[c["oid"]] = c
	if not _worktree_files.is_empty():
		_commits_by_oid[WORKTREE_OID] = _worktree_entry()
	if _search_results == null:
		_count_label.text = "%d%s commits" % [_all_commits.size(), "+" if _all_commits.size() >= _limit else ""]

	_apply_filter()
	# Keep the detail pane if its commit is still listed (auto-refresh after an unrelated change).
	if not _commits_by_oid.has(_detail_oid):
		_detail_oid = ""
		_files_tree.clear()
		_detail_label.text = ""
		_detail_separator.visible = false
		_hide_inline_diff()
	elif _detail_oid == WORKTREE_OID:
		var selected := _files_tree.get_selected()
		var selected_path: String = selected.get_metadata(0).get("path", "") if selected != null and selected.get_metadata(0) is Dictionary else ""
		_on_commit_graph_commit_selected(WORKTREE_OID)
		_build_files_tree(WORKTREE_OID, selected_path)


## Refs plus the stash reflog, which changes on drops that leave refs/stash alone.
func _refs_signature(snapshot: Dictionary) -> String:
	return snapshot["refs"] + snapshot["stash_log"]


func _update_undo_button() -> void:
	_undo_op = _repo.last_head_operation() if _repo.get_operation_state()["kind"].is_empty() else {}
	_undo_button.disabled = _undo_op.is_empty()
	_undo_button.tooltip_text = _undo_op.get("label", "Nothing to undo") + ("\n(the last git operation that moved HEAD: commit, checkout, merge, pull, rebase, reset…)" if not _undo_op.is_empty() else "")


func _on_undo_pressed() -> void:
	var op := _undo_op
	if op.is_empty():
		return
	var what: String = {
		"soft": "The commit goes away; its changes stay staged, so you can fix them and commit again.",
		"keep": "The branch moves back to where it was before. Uncommitted changes are kept (git refuses if they'd be overwritten).",
		"checkout": "Switches back to %s." % op["target"],
	}[op["mode"]]
	var warning := _pushed_warning(_repo.get_head_oid(), true) if op["mode"] != "checkout" else ""
	if not await Dialogs.confirm(self, "Undo", "%s?\n\n%s%s" % [op["label"], what, warning], "Undo") \
			or not await SaveGuard.ensure_saved(self, "Undo"):
		return
	_after_operation(_repo.undo_head_operation(op), "Undo")


func _status_signature(status: Array) -> String:
	return "|".join(status.map(func(e: Dictionary) -> String: return "%s:%d" % [e["path"], e["status"]]))


func _worktree_entry() -> Dictionary:
	var staged := _worktree_files.filter(func(e: Dictionary) -> bool: return GitStatusFlags.is_staged(e["status"])).size()
	var note := "%d file%s" % [_worktree_files.size(), "" if _worktree_files.size() == 1 else "s"]
	if staged > 0:
		note += " · %d staged" % staged
	return {
		"note": note,
		"oid": WORKTREE_OID, "parents": PackedStringArray([_repo.get_head_oid()]), "summary": "Uncommitted changes",
		"message": "", "refs": PackedStringArray(), "tags": PackedStringArray(), "author_name": "", "author_email": "", "time": 0,
	}


## commits with each stash just above the commit it was made on, and the "Uncommitted changes" row on top, linked to HEAD — or, in a file's history (which may skip HEAD), to the file's latest commit.
func _with_pseudo_rows(commits: Array, head: String) -> Array:
	var rows: Array = []
	for c in commits:
		for st in _stashes:
			if st["parents"][0] == c["oid"]:
				rows.append(st)
		rows.append(c)
	if _worktree_files.is_empty() or commits.is_empty():
		return rows
	var entry: Dictionary = _commits_by_oid[WORKTREE_OID]
	if not commits.any(func(c: Dictionary) -> bool: return c["oid"] == head):
		if _path_filter.is_empty():
			return rows
		entry["parents"] = PackedStringArray([commits[0]["oid"]])
	return [entry] + rows


func _on_refresh_button_pressed() -> void:
	_update_branch_option()
	refresh()


func _on_search_edit_text_changed(_new_text: String) -> void:
	_search_results = null
	_repo.cancel_search()
	_apply_filter()


func _search_mode_key() -> String:
	return ["message", "author", "code"][_search_mode.selected]


func _update_search_placeholder() -> void:
	_search_edit.placeholder_text = {
		"message": "Search message or hash (Enter: whole history)",
		"author": "Search author (Enter: whole history)",
		"code": "Text added/removed by a commit, then Enter",
	}[_search_mode_key()]


func _run_full_search() -> void:
	var query := _search_edit.text.strip_edges()
	if query.is_empty() or _repo == null:
		return
	_count_label.text = "searching…"
	var results: Variant = await _repo.search_commits(query, _search_mode_key(), SEARCH_LIMIT, _log_options())
	if results == null or _search_edit.text.strip_edges() != query:
		return # superseded by further typing or another search
	_search_results = results
	for c in results:
		_commits_by_oid[c["oid"]] = c
	_count_label.text = "%d%s matches" % [results.size(), "+" if results.size() >= SEARCH_LIMIT else ""]
	_apply_filter()


func _on_details_toggle_toggled(pressed: bool) -> void:
	_detail_margin.visible = pressed
	Settings.set_value(DETAILS_VISIBLE_SETTING_KEY, pressed)


## Whole-history search results if there are any, else a case-insensitive filter of the loaded commits by the search mode.
func _apply_filter() -> void:
	var query := _search_edit.text.strip_edges().to_lower()
	var head: String = _repo.get_head_oid()
	if _search_results != null:
		_graph.set_commits(_search_results, head)
		return
	# Code search needs git (Enter); there's nothing to match locally.
	if query.is_empty() or _search_mode_key() == "code":
		_graph.set_commits(_with_pseudo_rows(_all_commits, head), head)
		return

	var by_author := _search_mode_key() == "author"
	var filtered: Array = []
	for c in _all_commits:
		var hit := (String(c["author_name"]).to_lower().contains(query) or String(c["author_email"]).to_lower().contains(query)) if by_author \
				else (String(c["oid"]).to_lower().begins_with(query) or String(c["summary"]).to_lower().contains(query) or String(c["message"]).to_lower().contains(query))
		if hit:
			filtered.append(c)
	_graph.set_commits(filtered, head)


func _on_commit_graph_commit_selected(oid: String) -> void:
	if not _commits_by_oid.has(oid):
		return
	var c: Dictionary = _commits_by_oid[oid]
	var same_commit := oid == _detail_oid
	_detail_oid = oid

	if not same_commit:
		_build_files_tree(oid)
		_hide_inline_diff()
	_detail_separator.visible = true

	if oid == WORKTREE_OID:
		var staged := _worktree_files.filter(func(e: Dictionary) -> bool: return GitStatusFlags.is_staged(e["status"])).size()
		_detail_label.text = "[b]Uncommitted changes[/b]\n\n%d changed file%s, %d staged. Double-click the row to commit them in the Changes tab." % [
			_worktree_files.size(), "" if _worktree_files.size() == 1 else "s", staged,
		]
		return

	var when := Time.get_datetime_string_from_unix_time(int(c["time"]), true)
	var summary_line := "[b]%s[/b]" % _escape(String(c["summary"]).strip_edges())
	var byline := "%s %s [color=#8cbff2]<%s>[/color] on %s" % [
		String(c["oid"]).substr(0, 8), _escape(c["author_name"]), _escape(c["author_email"]), when,
	]

	var refs: PackedStringArray = c["refs"]
	var tags: PackedStringArray = c.get("tags", PackedStringArray())
	var badges: Array = []
	if c.has("stash"):
		badges.append("[bgcolor=#3a3a3f] %s [/bgcolor]  right-click to apply, pop or drop" % c["stash"])
	for r in refs:
		badges.append("[bgcolor=#3a3a3f] %s [/bgcolor]" % r)
	for t in tags:
		badges.append("[bgcolor=#3a3a3f] tag: %s [/bgcolor]" % t)
	var badges_line := ("\n" + "  ".join(badges)) if not badges.is_empty() else ""

	var branches: PackedStringArray = _repo.branches_containing(oid)
	var branches_line := ""
	if not branches.is_empty():
		branches_line = "\n\nIn %d branch%s: %s" % [
			branches.size(), "" if branches.size() == 1 else "es", ", ".join(Array(branches)),
		]

	var parents: PackedStringArray = c["parents"]
	var parents_line := ""
	if parents.size() > 1:
		parents_line = "\nMerge of " + " + ".join(Array(parents).map(func(p: String) -> String: return p.substr(0, 8)))

	# message is the full raw commit message (subject + body) — drop the
	# subject line since it's already shown above as the heading.
	var message_lines := String(c["message"]).strip_edges().split("\n")
	var body := "\n".join(Array(message_lines.slice(1))).strip_edges() if message_lines.size() > 1 else ""
	var body_line := ("\n\n" + _escape(body)) if not body.is_empty() else ""

	_detail_label.text = "%s\n\n%s%s%s%s%s" % [summary_line, byline, parents_line, badges_line, body_line, branches_line]


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Select the requested path without opening a diff; activation opens the central viewer.
func _build_files_tree(oid: String, select_path := "") -> void:
	_files_tree.clear()
	var root := _files_tree.create_item()
	var folder_cache: Dictionary = {}

	var files: Array
	if oid == WORKTREE_OID:
		files = _worktree_delta_files()
	elif _commits_by_oid.get(oid, {}).has("stash"):
		files = _stash_files(oid)
	else:
		files = _repo.get_commit_files(oid)
	for f in files:
		var path: String = f["path"]
		var status: int = f["status"]

		var parent := TreeFolders.get_or_create_folder(_files_tree, root, folder_cache, path.get_base_dir())
		var item := _files_tree.create_item(parent)
		item.set_text(0, "%s  %s" % [GitIcons.delta_letter(status), path.get_file()])
		item.set_custom_color(0, GitIcons.delta_color(status))
		item.set_metadata(0, { "path": path, "old_path": f.get("old_path", path), "status": status, "base": f.get("base", ""), "target": f.get("target", "") })
		item.set_tooltip_text(0, "%s\nDouble-click or press Enter to open its diff in GittyDot; right-click for more" % path)
		if f.has("staged"):
			item.set_suffix(0, f["staged"])
		if path == (select_path if not select_path.is_empty() else _path_filter) and not path.is_empty():
			item.select(0)

	if files.is_empty():
		var empty_item := _files_tree.create_item(root)
		empty_item.set_text(0, "(no file changes)")
		empty_item.set_selectable(0, false)


## A stash's files, each with the "base"/"target" revisions its diff is between (untracked ones live in a separate commit).
func _stash_files(oid: String) -> Array:
	var files: Array = _repo.get_changed_files_between(oid + "^", oid)
	for f in files:
		f["base"] = oid + "^"
		f["target"] = oid
	var untracked_rev: String = _repo.stash_untracked_rev(oid)
	if not untracked_rev.is_empty():
		for f in _repo.get_changed_files_between(_repo.empty_tree_oid(), untracked_rev):
			f["base"] = _repo.empty_tree_oid()
			f["target"] = untracked_rev
			files.append(f)
	return files


## _worktree_files in get_commit_files()' shape.
func _worktree_delta_files() -> Array:
	var files: Array = []
	for e in _worktree_files:
		var status: int = e["status"]
		var delta := GitIcons.DELTA_MODIFIED
		if status & (GitStatusFlags.WT_NEW | GitStatusFlags.INDEX_NEW):
			delta = GitIcons.DELTA_ADDED
		elif status & (GitStatusFlags.WT_DELETED | GitStatusFlags.INDEX_DELETED):
			delta = GitIcons.DELTA_DELETED
		elif status & (GitStatusFlags.WT_RENAMED | GitStatusFlags.INDEX_RENAMED):
			delta = GitIcons.DELTA_RENAMED
		var f := { "path": e["path"], "status": delta }
		if GitStatusFlags.is_staged(status):
			f["staged"] = "partly staged" if GitStatusFlags.is_unstaged(status) else "staged"
		if not String(e.get("renamed_from", "")).is_empty():
			f["old_path"] = e["renamed_from"]
		files.append(f)
	return files


func _on_files_tree_item_selected() -> void:
	# Selecting a row must leave the central editor and log layout alone.
	_hide_inline_diff()


func _on_files_tree_item_activated() -> void:
	_hide_inline_diff()
	var item := _files_tree.get_selected()
	if item == null or _detail_oid.is_empty():
		return
	var meta: Variant = item.get_metadata(0)
	if not meta is Dictionary or not meta.has("path"):
		return
	var path: String = meta["path"]
	if _detail_oid == WORKTREE_OID:
		diff_requested.emit({"kind": "worktree", "path": path})
		return
	var target: String = meta.get("target", "")
	var is_stash := not target.is_empty()
	diff_requested.emit({
		"kind": "revisions" if is_stash else "commit",
		"path": path, "old_path": meta.get("old_path", path),
		"old_rev": meta["base"] if is_stash else _repo.parent_or_empty_tree(_detail_oid),
		"new_rev": target if is_stash else _detail_oid,
		"oid": _detail_oid,
		"note": "stash changes" if is_stash else "parent → selected commit",
	})


## Opens a file listed for _detail_oid, at wherever it lives now (it may have been renamed since).
func _open_historical_file(path: String, line := 0) -> void:
	var current: String = path if _detail_oid == WORKTREE_OID else _repo.current_path(_detail_oid, path)
	if current.is_empty():
		Dialogs.error(self, "Can't open file", "\"%s\" no longer exists in the working tree." % path)
		return
	var error := EditorOpen.open_file_at_line(_repo.get_repo_root(), current, line) if line > 0 else EditorOpen.open_file(_repo.get_repo_root(), current)
	if not error.is_empty():
		Dialogs.error(self, "Can't open file", error)


func _on_files_tree_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _files_tree.get_item_at_position(mouse_position)
	if item == null or not item.get_metadata(0) is Dictionary or not item.get_metadata(0).has("path"):
		return
	_file_context_path = item.get_metadata(0)["path"]
	_file_menu.clear()
	_file_menu.add_item("Show Diff", ID_FILE_DIFF)
	_file_menu.add_item("Open in Editor", ID_FILE_OPEN)
	_file_menu.add_item("Show History of This File", ID_FILE_HISTORY)
	_file_menu.add_item("Copy Path", ID_FILE_COPY_PATH)
	if _detail_oid == WORKTREE_OID:
		_file_menu.position = _files_tree.get_screen_position() + mouse_position.round()
		_file_menu.reset_size()
		_file_menu.popup()
		return
	_add_web_item(_file_menu, ID_FILE_OPEN_ON_WEB, _detail_oid)
	_file_menu.add_separator()
	_file_menu.add_item("Restore File to This Commit's Version…", ID_FILE_RESTORE_THIS)
	_file_menu.add_item("Restore File to Before This Commit…", ID_FILE_RESTORE_BEFORE)
	_file_menu.set_item_disabled(_file_menu.get_item_index(ID_FILE_RESTORE_BEFORE), not _repo.has_parent(_detail_oid))
	_file_menu.position = _files_tree.get_screen_position() + mouse_position.round()
	_file_menu.reset_size()
	_file_menu.popup()


func _on_file_menu_id_pressed(id: int) -> void:
	var path := _file_context_path
	match id:
		ID_FILE_DIFF:
			_on_files_tree_item_activated()
		ID_FILE_OPEN:
			_open_historical_file(path)
		ID_FILE_HISTORY:
			set_path_filter(path)
		ID_FILE_COPY_PATH:
			DisplayServer.clipboard_set(path)
		ID_FILE_OPEN_ON_WEB:
			OS.shell_open(WebLinks.file_url(WebLinks.site(_repo), _detail_oid, path))
		ID_FILE_RESTORE_THIS, ID_FILE_RESTORE_BEFORE:
			var rev := _detail_oid if id == ID_FILE_RESTORE_THIS else _detail_oid + "^"
			var label := "as of %s" % _detail_oid.substr(0, 7) if id == ID_FILE_RESTORE_THIS else "as it was before %s" % _detail_oid.substr(0, 7)
			if await Dialogs.confirm(self, "Restore File",
					"Replace \"%s\" in your working tree with its version %s?\n\nThe result shows up as an uncommitted change; your current edits to the file are lost." % [path, label], "Restore"):
				var result: Dictionary = _repo.restore_file_from(rev, path)
				if not result["ok"]:
					await Dialogs.error(self, "Restore failed", result["error"])
				EditorOpen.refresh_external_change(_repo.get_repo_root(), path)


func _on_commit_graph_commit_context_requested(oid: String, screen_position: Vector2) -> void:
	if oid == WORKTREE_OID:
		_show_worktree_menu(screen_position)
		return
	if _commits_by_oid.get(oid, {}).has("stash"):
		_context_oid = oid
		_context_oids = PackedStringArray([oid])
		_show_stash_menu(screen_position)
		return
	_context_oid = oid
	_context_oids = _graph.get_selected_oids()
	if not _context_oids.has(oid):
		_context_oids = PackedStringArray([oid])
	_context_oids = PackedStringArray(Array(_context_oids).filter(func(o: String) -> bool: return o != WORKTREE_OID and not _commits_by_oid.get(o, {}).has("stash")))
	var many := _context_oids.size() > 1
	var current: String = _repo.get_current_branch()
	var target := current if not current.is_empty() else "HEAD"
	var head: String = _repo.get_head_oid()
	var in_head_history: bool = _repo.is_ancestor_of_head(oid)
	var can_rewrite := not many and in_head_history and not current.is_empty()
	var has_merges_after: bool = can_rewrite and _repo.has_merges_since(oid)
	var has_parent: bool = _repo.has_parent(oid)

	var m := _context_menu
	m.clear()
	m.add_item("Copy Commit Hash%s" % ("es" if many else ""), ID_COPY_HASH)
	m.add_item("Copy Commit Message", ID_COPY_MESSAGE)
	if not many:
		_add_web_item(m, ID_OPEN_ON_WEB, oid)
	m.add_separator()
	if not many:
		m.add_item("Show Changes…", ID_SHOW_CHANGES)
		m.add_item("Compare with Working Tree…", ID_COMPARE_WORKTREE)
	if _context_oids.size() == 2:
		m.add_item("Compare the Two Selected Commits…", ID_COMPARE_SELECTED)
	m.add_separator()
	if not many:
		m.add_item("Create Branch from Here...", ID_CREATE_BRANCH)
		m.add_item("Create Tag Here...", ID_CREATE_TAG)
		m.add_item("Checkout This Commit...", ID_CHECKOUT_COMMIT)
	m.add_separator()
	m.add_item("Cherry-pick %sinto %s" % ["%d Commits " % _context_oids.size() if many else "", target], ID_CHERRY_PICK)
	m.add_item("Cherry-pick without Committing", ID_CHERRY_PICK_NO_COMMIT)
	if in_head_history and not many:
		m.set_item_disabled(m.get_item_index(ID_CHERRY_PICK), true)
		m.set_item_tooltip(m.get_item_index(ID_CHERRY_PICK), "Already part of %s" % target)
	if not many:
		m.add_item("Revert Commit (new commit undoing it)", ID_REVERT_COMMIT)

	if can_rewrite:
		m.add_separator("Rewrite %s's history" % current)
		m.add_item("Amend This Commit…", ID_AMEND)
		m.set_item_disabled(m.get_item_index(ID_AMEND), has_merges_after)
		m.set_item_tooltip(m.get_item_index(ID_AMEND), "Choose staged changes and edit this commit's message in the Commit dock")
		m.add_item("Reword Message…", ID_REWORD)
		m.add_item("Fixup: Fold Staged Changes into This Commit", ID_FIXUP)
		m.set_item_disabled(m.get_item_index(ID_FIXUP), has_merges_after or not _repo.has_staged_changes())
		# Both replay the commits after it with a rebase, which would flatten merges (the head commit is just amended).
		m.set_item_disabled(m.get_item_index(ID_REWORD), has_merges_after)
		if has_merges_after:
			var no_merges := "A merge commit lies after it — rewriting through merges would flatten them"
			m.set_item_tooltip(m.get_item_index(ID_REWORD), no_merges)
			m.set_item_tooltip(m.get_item_index(ID_FIXUP), no_merges)
		m.add_item("Squash This and Newer Commits into One…", ID_SQUASH)
		m.set_item_disabled(m.get_item_index(ID_SQUASH), has_merges_after or not has_parent or oid == head)
		m.add_item("Drop Commit…", ID_DROP)
		m.set_item_disabled(m.get_item_index(ID_DROP), has_merges_after or not has_parent)
		if oid == head:
			m.add_item("Undo Commit (keep its changes staged)", ID_UNDO_LAST)
			m.set_item_disabled(m.get_item_index(ID_UNDO_LAST), not has_parent)
	if not many:
		m.add_separator()
		m.add_item("Reset Current Branch to Here...", ID_RESET_TO_HERE)

	m.position = screen_position
	m.reset_size()
	m.popup()


## "Open on GitHub" (or GitLab/Bitbucket) for oid, disabled until it's pushed; nothing for other hosts.
func _add_web_item(menu: PopupMenu, id: int, oid: String) -> void:
	var site := WebLinks.site(_repo)
	if site.is_empty():
		return
	menu.add_item("Open on %s" % site["name"], id)
	if not WebLinks.is_pushed(_repo, oid):
		menu.set_item_disabled(menu.get_item_index(id), true)
		menu.set_item_tooltip(menu.get_item_index(id), "Not pushed yet")


func _show_worktree_menu(screen_position: Vector2) -> void:
	var m := _context_menu
	m.clear()
	m.add_item("Commit…", ID_WORKTREE_COMMIT)
	m.add_item("Stash Changes…", ID_WORKTREE_STASH)
	m.add_separator()
	m.add_item("Revert All Changes…", ID_WORKTREE_REVERT)
	m.position = screen_position
	m.reset_size()
	m.popup()


func _show_stash_menu(screen_position: Vector2) -> void:
	var m := _context_menu
	m.clear()
	m.add_item("Show Changes…", ID_STASH_SHOW)
	m.add_item("Compare with Working Tree…", ID_STASH_COMPARE_WORKTREE)
	m.add_item("Apply", ID_STASH_APPLY)
	m.add_item("Pop (apply and drop)", ID_STASH_POP)
	m.add_item("Copy Commit Hash", ID_COPY_HASH)
	m.add_separator()
	m.add_item("Drop…", ID_STASH_DROP)
	m.position = screen_position
	m.reset_size()
	m.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	var stash_ref: String = _commits_by_oid.get(_context_oid, {}).get("stash", "")
	var verbs := {
		ID_STASH_APPLY: "Apply", ID_STASH_POP: "Pop", ID_CHERRY_PICK: "Cherry-pick", ID_CHERRY_PICK_NO_COMMIT: "Cherry-pick",
		ID_REVERT_COMMIT: "Revert", ID_REWORD: "Reword", ID_FIXUP: "Fixup", ID_SQUASH: "Squash", ID_DROP: "Drop", ID_UNDO_LAST: "Undo",
		ID_CHECKOUT_COMMIT: "Checkout", ID_RESET_TO_HERE: "Reset",
	}
	if verbs.has(id) and not await SaveGuard.ensure_saved(self, verbs[id]):
		return
	match id:
		ID_AMEND:
			amend_requested.emit(_context_oid)
		ID_STASH_SHOW:
			_open_changeset("%s  %s" % [stash_ref, _summary(_context_oid)], stash_ref + "^", stash_ref)
		ID_STASH_COMPARE_WORKTREE:
			_open_changeset("%s ↔ working tree" % stash_ref, _context_oid, "")
		ID_STASH_APPLY, ID_STASH_POP:
			_after_operation(_repo.stash_apply(stash_ref, id == ID_STASH_POP), "Pop" if id == ID_STASH_POP else "Apply")
		ID_STASH_DROP:
			if await Dialogs.confirm(self, "Drop Stash", "Delete %s \"%s\"? This can't be undone." % [stash_ref, _summary(_context_oid)], "Drop"):
				_after(_repo.stash_drop(stash_ref), "Drop stash failed")
		ID_WORKTREE_COMMIT:
			changes_requested.emit("commit")
		ID_WORKTREE_STASH:
			changes_requested.emit("stash")
		ID_WORKTREE_REVERT:
			changes_requested.emit("revert")
		ID_COPY_HASH:
			DisplayServer.clipboard_set("\n".join(_context_oids) if _context_oids.size() > 1 else _context_oid)
		ID_OPEN_ON_WEB:
			OS.shell_open(WebLinks.commit_url(WebLinks.site(_repo), _context_oid))
		ID_COPY_MESSAGE:
			if _commits_by_oid.has(_context_oid):
				var c: Dictionary = _commits_by_oid[_context_oid]
				DisplayServer.clipboard_set(String(c["message"]).strip_edges())
		ID_SHOW_CHANGES:
			_open_changeset("%s  %s" % [_context_oid.substr(0, 8), _summary(_context_oid)],
					_repo.parent_or_empty_tree(_context_oid), _context_oid)
		ID_COMPARE_WORKTREE:
			_open_changeset("%s ↔ working tree" % _context_oid.substr(0, 8), _context_oid, "")
		ID_COMPARE_SELECTED:
			# Older one as the base, so additions read as additions.
			_open_changeset("%s ↔ %s" % [_context_oids[1].substr(0, 8), _context_oids[0].substr(0, 8)], _context_oids[1], _context_oids[0])
		ID_CREATE_BRANCH:
			_new_branch_name_edit.text = ""
			_new_branch_checkout_check.button_pressed = false
			_new_branch_dialog.popup_centered()
			_new_branch_name_edit.grab_focus()
		ID_CREATE_TAG:
			var answer: Variant = await Dialogs.form(self, "New Tag at %s" % _context_oid.substr(0, 7), [
				{ "key": "name", "label": "Tag name", "placeholder": "v1.0.0" },
				{ "key": "message", "label": "Message (leave empty for a lightweight tag)", "type": "multiline" },
			], "Create")
			if answer != null and not String(answer["name"]).strip_edges().is_empty():
				_after(_repo.create_tag(String(answer["name"]).strip_edges(), _context_oid, String(answer["message"]).strip_edges()), "Create tag failed")
		ID_CHECKOUT_COMMIT:
			_checkout_confirm_dialog.dialog_text = "Checkout commit %s?\nThis leaves HEAD detached (not on a branch)." % _context_oid.substr(0, 7)
			_checkout_confirm_dialog.popup_centered()
		ID_RESET_TO_HERE:
			_reset_hard_check.button_pressed = false
			_reset_message_label.text = "Move the current branch to %s?%s" % [_context_oid.substr(0, 7), _pushed_warning(_context_oid, false)]
			_reset_dialog.popup_centered()
		ID_CHERRY_PICK, ID_CHERRY_PICK_NO_COMMIT:
			_after_operation(_repo.cherry_pick(_context_oids, id == ID_CHERRY_PICK_NO_COMMIT), "Cherry-pick")
		ID_REVERT_COMMIT:
			if await Dialogs.confirm(self, "Revert Commit",
					"Create a new commit that undoes %s \"%s\"?\n\nHistory isn't rewritten — safe for commits that were already pushed." % [_context_oid.substr(0, 7), _summary(_context_oid)], "Revert"):
				_after_operation(_repo.revert_commit(_context_oid), "Revert")
		ID_REWORD:
			var old_message := String(_commits_by_oid.get(_context_oid, {}).get("message", "")).strip_edges()
			var answer: Variant = await Dialogs.form(self, "Reword %s" % _context_oid.substr(0, 7), [
				{ "key": "message", "label": "Commit message" + _pushed_warning(_context_oid, true), "type": "multiline", "default": old_message },
			], "Reword")
			if answer != null and not String(answer["message"]).strip_edges().is_empty() and String(answer["message"]).strip_edges() != old_message:
				_after_operation(_repo.reword_commit(_context_oid, String(answer["message"]).strip_edges()), "Reword")
		ID_FIXUP:
			if await Dialogs.confirm(self, "Fixup",
					"Fold the staged changes into %s \"%s\"?%s" % [_context_oid.substr(0, 7), _summary(_context_oid), _pushed_warning(_context_oid, true)], "Fixup"):
				_after_operation(_repo.fixup_commit(_context_oid), "Fixup")
		ID_SQUASH:
			var answer: Variant = await Dialogs.form(self, "Squash into One Commit", [
				{ "type": "label", "label": "Combine %s and every newer commit on %s into a single commit.%s" % [_context_oid.substr(0, 7), _repo.get_current_branch(), _pushed_warning(_context_oid, true)] },
				{ "key": "message", "label": "Message for the combined commit", "type": "multiline", "default": _repo.get_messages_since(_context_oid) },
			], "Squash")
			if answer != null and not String(answer["message"]).strip_edges().is_empty():
				_after_operation(_repo.squash_to_head(_context_oid, String(answer["message"]).strip_edges()), "Squash")
		ID_DROP:
			if await Dialogs.confirm(self, "Drop Commit",
					"Remove %s \"%s\" from %s? Newer commits are replayed without it.%s" % [_context_oid.substr(0, 7), _summary(_context_oid), _repo.get_current_branch(), _pushed_warning(_context_oid, true)], "Drop"):
				_after_operation(_repo.drop_commit(_context_oid), "Drop")
		ID_UNDO_LAST:
			_after(_repo.undo_last_commit(), "Undo commit failed", true)


## Dragged onto the current branch's row: cherry-pick the ones it doesn't have yet.
func _on_commits_dropped(oids: PackedStringArray, _target_oid: String) -> void:
	var branch: String = _repo.get_current_branch()
	var missing := PackedStringArray(Array(oids).filter(func(o: String) -> bool: return not _repo.is_ancestor_of_head(o)))
	if missing.is_empty():
		Dialogs.error(self, "Nothing to Cherry-pick", "%s already contains %s." % [branch, "these commits" if oids.size() > 1 else "this commit"])
		return
	if not await SaveGuard.ensure_saved(self, "Cherry-pick"):
		return
	var what := "%d commits" % missing.size() if missing.size() > 1 else "%s \"%s\"" % [missing[0].substr(0, 7), _summary(missing[0])]
	if await Dialogs.confirm(self, "Cherry-pick", "Cherry-pick %s into %s?" % [what, branch], "Cherry-pick"):
		_after_operation(_repo.cherry_pick(missing), "Cherry-pick")


## A branch dragged onto another, one of them checked out: merge the other into it, or rebase it onto the other.
func _on_refs_dropped(refs: PackedStringArray, target_oid: String) -> void:
	var current: String = _repo.get_current_branch()
	var others: Array = Array(_commits_by_oid.get(target_oid, {}).get("refs", PackedStringArray())) if refs.has(current) else Array(refs)
	others = others.filter(func(r: String) -> bool: return r != current)
	if others.is_empty():
		return
	var actions: Array = []
	for other in others:
		actions.append("Merge %s into %s" % [other, current])
		actions.append("Rebase %s onto %s" % [current, other])
	var answer: Variant = await Dialogs.form(self, "Merge or Rebase", [
		{ "key": "action", "label": "Action", "type": "option", "options": actions, "default": actions[0] },
		{ "key": "mode", "label": "Merge mode", "type": "option", "options": MERGE_MODES.keys(), "default": MERGE_MODES.keys()[0] },
		{ "type": "label", "label": "Rebase rewrites %s's history — don't do it to commits others already pulled." % current },
	], "Run")
	if answer == null or not await SaveGuard.ensure_saved(self, "Merge" if actions.find(answer["action"]) % 2 == 0 else "Rebase"):
		return
	var index := actions.find(answer["action"])
	var other: String = others[index / 2]
	if index % 2 == 0:
		_after_operation(_repo.merge(other, MERGE_MODES[answer["mode"]]), "Merge")
	else:
		_after_operation(_repo.rebase(other), "Rebase")


func _summary(oid: String) -> String:
	return String(_commits_by_oid.get(oid, {}).get("summary", ""))


## Extra warning line when oid is already on a remote branch — rewriting it means a force-push.
func _pushed_warning(oid: String, rewrites: bool) -> String:
	for name in _repo.branches_containing(oid):
		if name.contains("/") and _repo.list_remotes().any(func(r: Dictionary) -> bool: return name.begins_with(r["name"] + "/")):
			return "\n\n⚠ This commit is already on %s — %s" % [name, "rewriting it means you'll have to force-push." if rewrites else "moving the branch behind it means you'll have to force-push."]
	return ""


func _open_changeset(title: String, base: String, target: String) -> void:
	var dialog := ChangesetDialog.new()
	add_child(dialog)
	dialog.open(_repo, title, base, target)


func _after(result: Dictionary, error_title: String, reload_editor: bool = false) -> void:
	if reload_editor:
		EditorOpen.refresh_all_external_changes()
	if not result["ok"]:
		Dialogs.error(self, error_title, GitErrors.explain(result["error"]))
	refresh()


## A stop on conflicts isn't an error — it points to the Changes panel, where they're resolved.
func _after_operation(result: Dictionary, verb: String) -> void:
	EditorOpen.refresh_all_external_changes()
	if result.get("conflicts", false):
		Dialogs.error(self, "%s Stopped on Conflicts" % verb,
				"%s hit conflicts. Resolve them in the Changes tab (Accept Ours/Theirs, or edit and Mark Resolved), then press Continue there — or Abort to undo." % verb)
	elif not result["ok"]:
		Dialogs.error(self, "%s failed" % verb, GitErrors.explain(result["error"]))
	refresh()


func _on_new_branch_dialog_confirmed() -> void:
	var name := _new_branch_name_edit.text.strip_edges()
	if name.is_empty():
		_show_error("Invalid name", "Branch name can't be empty.")
		return
	var result: Dictionary = _repo.create_branch(name, _context_oid, _new_branch_checkout_check.button_pressed)
	if not result["ok"]:
		_show_error("Couldn't create branch", result["error"])
		return
	if _new_branch_checkout_check.button_pressed:
		EditorOpen.refresh_all_external_changes()
	_update_branch_option()
	refresh()


func _on_checkout_confirm_dialog_confirmed() -> void:
	var result: Dictionary = _repo.checkout_commit(_context_oid)
	if not result["ok"]:
		_show_error("Checkout failed", GitErrors.explain(result["error"]))
		return
	EditorOpen.refresh_all_external_changes()
	refresh()


func _on_reset_dialog_confirmed() -> void:
	var result: Dictionary = _repo.reset_branch_to(_context_oid, _reset_hard_check.button_pressed)
	if not result["ok"]:
		_show_error("Reset failed", result["error"])
		return
	if _reset_hard_check.button_pressed:
		EditorOpen.refresh_all_external_changes()
	refresh()


func _show_error(title: String, message: String) -> void:
	_error_dialog.title = title
	_error_dialog.dialog_text = message
	Dialogs.add_console_details(_error_dialog, title, message)
	_error_dialog.popup_centered()
