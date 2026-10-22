@tool
extends Control

const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")
const RepoWatcher := preload("res://addons/gittydot/util/repo_watcher.gd")
const TreeFolders := preload("res://addons/gittydot/util/tree_folders.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")
const SyncBar := preload("res://addons/gittydot/dock/widgets/sync_bar.gd")
const RemoteActions := preload("res://addons/gittydot/dock/widgets/remote_actions.gd")
const WebLinks := preload("res://addons/gittydot/util/web_links.gd")
const GitErrors := preload("res://addons/gittydot/util/git_errors.gd")


enum {
	ID_CHECKOUT, ID_NEW_BRANCH_FROM, ID_MERGE, ID_REBASE, ID_PUSH_BRANCH, ID_SET_UPSTREAM,
	ID_UNSET_UPSTREAM, ID_RENAME, ID_DELETE, ID_DELETE_REMOTE_BRANCH, ID_COPY_NAME,
	ID_PUSH_TAG, ID_DELETE_TAG, ID_DELETE_REMOTE_TAG, ID_FETCH_REMOTE, ID_EDIT_REMOTE_URL,
	ID_RENAME_REMOTE, ID_REMOVE_REMOTE, ID_ADD_REMOTE, ID_FETCH_PRUNE, ID_NEW_TAG,
	ID_COMPARE, ID_STASH_APPLY, ID_STASH_POP, ID_STASH_DROP, ID_STASH_SHOW, ID_STASH_BRANCH,
	ID_OPEN_ON_WEB, ID_PULL_REQUEST,
}

## Opens the changeset dialog, wired up by godit_dock.gd: (title, base_ref, target_ref). target "" means the working tree.
signal compare_requested(title: String, base: String, target: String)
## A branch, tag or stash was selected: its full ref name, for the combined dock to show it in History.
signal ref_selected(ref: String)

@onready var _tree: Tree = %BranchesTree
@onready var _filter_edit: LineEdit = %FilterEdit
@onready var _context_menu: PopupMenu = %ContextMenu

## Set by godit_dock.gd; a git_cli_repo.gd instance.
var _repo: RefCounted
var _operation_bar: HBoxContainer
var _sync_bar: VBoxContainer
## Below this width the tree drops to a single column (side-dock mode).
const WIDE_MIN_WIDTH := 520.0
var _wide := true
var _last_signature := ""

## {"kind": "local"|"remote_branch"|"tag"|"remote"|"stash"|"section", ...} for whatever the context menu was opened on.
var _context: Dictionary = {}

## What the section headers say, where it isn't their key.
const SECTION_TITLES := { "Local": "Branches", "Remote": "Remote Branches" }

## Section headers' collapsed state, kept across refreshes (keyed by section title).
var _collapsed_sections := { "Tags": true, "Stashes": false }
## Frame of the last ref_selected(), so a click that also changed the selection emits it once.
var _ref_selected_frame := -1


func _ready() -> void:
	if UiScale.is_in_edited_scene(self):
		return # opened in the scene editor, not running in a dock
	UiScale.scale_scene(self)
	_sync_bar = SyncBar.new()
	$Layout/Toolbar.add_child(_sync_bar)
	$Layout/Toolbar.move_child(_sync_bar, 0)
	_sync_bar.changed.connect(refresh)
	_operation_bar = _sync_bar.operation_bar
	_tree.resized.connect(func() -> void:
		if (_tree.size.x >= UiScale.px(WIDE_MIN_WIDTH)) != _wide and _repo != null:
			refresh()
	)

	_tree.item_selected.connect(_on_tree_item_selected)
	# item_mouse_selected skips rows that can't be selected — section headers and remote folders — so their menu opens from here.
	_tree.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		var item := _tree.get_item_at_position(mb.position)
		if item != null and not item.is_selectable(0) and item.get_metadata(0) is Dictionary:
			_show_context_menu(item.get_metadata(0), _tree.get_screen_position() + mb.position)
			_tree.accept_event()
	)
	# Clicking the already selected row again shows it again too.
	_tree.item_mouse_selected.connect(func(_pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT and _ref_selected_frame != Engine.get_process_frames():
			_on_tree_item_selected()
	)
	_tree.item_collapsed.connect(func(item: TreeItem) -> void:
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary and meta.get("kind", "") == "section":
			_collapsed_sections[meta["title"]] = item.collapsed
	)
	_tree.empty_clicked.connect(func(pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_RIGHT:
			_show_context_menu({ "kind": "section", "title": "Local" }, _tree.get_screen_position() + pos)
	)


func set_repo(repo: RefCounted) -> void:
	_repo = repo
	_sync_bar.set_repo(repo)
	refresh()
	RepoWatcher.watch(self, _on_polled)


## In the combined dock's sidebar: no branch/Fetch/Pull/Push row of its own, messages in the shared toolbar's strip (shared_bar) and a frameless tree.
func set_sidebar_mode(on: bool, shared_bar: HBoxContainer = null) -> void:
	_sync_bar.set_row_visible(not on)
	_sync_bar.use_operation_bar(shared_bar if on else null)
	_operation_bar = _sync_bar.operation_bar
	for stylebox in [&"panel", &"focus"]:
		if on:
			_tree.add_theme_stylebox_override(stylebox, StyleBoxEmpty.new())
		else:
			_tree.remove_theme_stylebox_override(stylebox)
	for constant in [&"draw_relationship_lines", &"draw_guides"]:
		if on:
			_tree.add_theme_constant_override(constant, 0)
		else:
			_tree.remove_theme_constant_override(constant)


## Rebuilds the tree (losing scroll and selection) only when something changed; hidden, it waits for the poll that comes with being shown.
func _on_polled(snapshot: Dictionary) -> void:
	if _repo == null or _repo.is_busy() or not is_visible_in_tree():
		return
	if _signature(snapshot) != _last_signature:
		refresh()


## Refs and HEAD (ahead/behind can only change with them), remotes and upstreams from config, stashes from their reflog.
func _signature(snapshot: Dictionary) -> String:
	return snapshot["refs"] + snapshot["config"] + snapshot["stash_log"]


func refresh() -> void:
	if _repo == null:
		return
	_last_signature = _signature(_repo.read_snapshot())
	_sync_bar.refresh()

	var scroll := _tree.get_scroll()
	_tree.clear()
	_setup_columns()
	var root := _tree.create_item()
	var filter := _filter_edit.text.strip_edges().to_lower()
	var current: String = _repo.get_current_branch()

	var branches: Array = _repo.list_branches(false)
	var local_section := _section(root, "Local")
	var local_count := 0
	for b in branches:
		if b["is_remote"] or not _matches(filter, b["name"]):
			continue
		local_count += 1
		var item := _tree.create_item(local_section)
		var tracking := ""
		if not b["upstream"].is_empty():
			var sync := _sync_text(b["ahead"], b["behind"])
			tracking = "%s%s%s" % [b["upstream"], "  " + sync if not sync.is_empty() else "", "  (gone)" if b["gone"] else ""]
		_fill_row(item, b["name"], tracking, b)
		if not _wide: # just ↑↓ after the name; the upstream is in the tooltip
			item.set_suffix(0, _sync_text(b["ahead"], b["behind"]) + ("  gone" if b["gone"] else ""))
		item.set_icon(0, _icon(&"VcsBranches"))
		item.set_metadata(0, { "kind": "local", "name": b["name"], "upstream": b["upstream"], "is_head": b["is_head"] })
		item.set_tooltip_text(0, "%s%s — %s %s (%s)%s\nDouble-click to checkout, right-click for more" % [
				b["name"], "  (current)" if b["is_head"] else "", b["oid"], b["summary"], b["date"], "\nTracking " + tracking if not tracking.is_empty() else ""])
		if b["is_head"]:
			var success := get_theme_color(&"success_color", &"Editor")
			item.set_custom_font(0, get_theme_font(&"bold", &"EditorFonts"))
			item.set_icon_modulate(0, success)
			for col in _tree.columns:
				item.set_custom_color(col, success)
	_finish_section(local_section, local_count)

	var remote_section := _section(root, "Remote")
	var remote_folders := {}
	var remote_count := 0
	for b in branches:
		if not b["is_remote"] or not _matches(filter, b["name"]):
			continue
		var remote_name: String = b["name"].get_slice("/", 0)
		if not remote_folders.has(remote_name):
			var folder := _tree.create_item(remote_section)
			folder.set_text(0, remote_name)
			folder.set_icon(0, _icon(&"Folder"))
			folder.set_selectable(0, false)
			folder.set_metadata(0, { "kind": "remote", "name": remote_name })
			remote_folders[remote_name] = folder
		remote_count += 1
		var item := _tree.create_item(remote_folders[remote_name])
		_fill_row(item, b["name"].substr(remote_name.length() + 1), "", b)
		item.set_icon(0, _icon(&"VcsBranches"))
		item.set_icon_modulate(0, Color(1, 1, 1, 0.55))
		item.set_metadata(0, { "kind": "remote_branch", "name": b["name"], "remote": remote_name })
		item.set_tooltip_text(0, "%s — %s %s (%s)\nDouble-click to check out as a local tracking branch" % [b["name"], b["oid"], b["summary"], b["date"]])
		item.set_custom_color(0, Color(0.72, 0.78, 0.9))
	_finish_section(remote_section, remote_count)

	var tags_section := _section(root, "Tags")
	var tag_count := 0
	for t in _repo.list_tags():
		if not _matches(filter, t["name"]):
			continue
		tag_count += 1
		var item := _tree.create_item(tags_section)
		_fill_row(item, t["name"], "annotated" if t["annotated"] else "", { "oid": t["oid"], "summary": t["summary"], "date": "" })
		item.set_metadata(0, { "kind": "tag", "name": t["name"] })
		item.set_tooltip_text(0, "%s — %s %s%s" % [t["name"], t["oid"], t["summary"], "  (annotated)" if t["annotated"] else ""])
		item.set_custom_color(0, Color(0.95, 0.85, 0.55))
		item.set_icon(0, _icon(&"Pin"))
	_finish_section(tags_section, tag_count)

	var stash_section := _section(root, "Stashes")
	var stashes: Array = _repo.list_stashes()
	for st in stashes:
		var item := _tree.create_item(stash_section)
		_fill_row(item, st["message"], st["ref"], { "oid": "", "summary": "", "date": st["date"] })
		item.set_icon(0, _icon(&"VCSCommit"))
		item.set_metadata(0, { "kind": "stash", "ref": st["ref"], "message": st["message"] })
		item.set_tooltip_text(0, "%s — %s\nDouble-click to apply, right-click for more" % [st["ref"], st["message"]])
	_finish_section(stash_section, stashes.size())

	var remotes_section := _section(root, "Remotes")
	var remotes: Array = _repo.list_remotes()
	for r in remotes:
		var item := _tree.create_item(remotes_section)
		_fill_row(item, r["name"], r["fetch_url"], {})
		item.set_icon(0, _icon(&"ExternalLink"))
		item.set_metadata(0, { "kind": "remote", "name": r["name"], "url": r["fetch_url"] })
		var push_note: String = "\nPush URL: " + r["push_url"] if r["push_url"] != r["fetch_url"] else ""
		item.set_tooltip_text(0, "%s\nFetch URL: %s%s\nDouble-click to edit URL" % [r["name"], r["fetch_url"], push_note])
	_finish_section(remotes_section, remotes.size())
	if remotes.is_empty():
		var hint := _tree.create_item(remotes_section)
		hint.set_text(0, "No remotes — right-click to add one")
		hint.set_custom_color(0, Color(1, 1, 1, 0.45))
		hint.set_metadata(0, { "kind": "section", "title": "Remotes" })
		remotes_section.collapsed = false

	_restore_scroll.call_deferred(scroll)


## Branch | Tracking | Last commit when there's room (bottom panel), a single column in a narrow side dock.
func _setup_columns() -> void:
	_wide = _tree.size.x >= UiScale.px(WIDE_MIN_WIDTH)
	_tree.columns = 3 if _wide else 1
	_tree.column_titles_visible = _wide
	if not _wide:
		return
	_tree.set_column_title(0, "Name")
	_tree.set_column_title(1, "Tracking")
	_tree.set_column_title(2, "Last commit")
	for col in 3:
		_tree.set_column_title_alignment(col, HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_clip_content(col, true)
	_tree.set_column_expand_ratio(0, 3)
	_tree.set_column_expand_ratio(1, 3)
	_tree.set_column_expand_ratio(2, 5)


## Fills a row's columns; in single-column mode the tracking info is appended to the name instead.
func _fill_row(item: TreeItem, name: String, tracking: String, info: Dictionary) -> void:
	if not _wide:
		item.set_text(0, name)
		return
	item.set_text(0, name)
	item.set_text(1, tracking)
	item.set_custom_color(1, Color(0.75, 0.78, 0.85))
	var commit := ""
	if not String(info.get("oid", "")).is_empty():
		commit = "%s  %s" % [info["oid"], info.get("summary", "")]
	if not String(info.get("date", "")).is_empty():
		commit += ("   · " if not commit.is_empty() else "") + info["date"]
	item.set_text(2, commit)
	item.set_custom_color(2, Color(0.62, 0.62, 0.66))
	for col in range(1, 3):
		item.set_selectable(col, item.is_selectable(0))


func _restore_scroll(scroll: Vector2) -> void:
	var bar: VScrollBar = TreeFolders.v_scroll_bar(_tree)
	if bar != null:
		bar.value = scroll.y


func _section(root: TreeItem, title: String) -> TreeItem:
	var item := _tree.create_item(root)
	item.set_metadata(0, { "kind": "section", "title": title })
	for col in _tree.columns:
		item.set_selectable(col, false)
	# Small dimmed caps with some air above, like the combined dock's WORKSPACE header.
	item.set_custom_color(0, Color(get_theme_color(&"font_color", &"Tree"), 0.55))
	item.set_custom_font_size(0, int(get_theme_font_size(&"font_size", &"Tree") * 0.85))
	item.set_custom_minimum_height(int(UiScale.px(28)))
	item.collapsed = _collapsed_sections.get(title, false)
	return item


func _finish_section(section: TreeItem, count: int) -> void:
	var meta: Dictionary = section.get_metadata(0)
	section.set_text(0, "%s  %d" % [SECTION_TITLES.get(meta["title"], meta["title"]).to_upper(), count])


func _matches(filter: String, name: String) -> bool:
	return filter.is_empty() or name.to_lower().contains(filter)


func _icon(name: StringName) -> Texture2D:
	return get_theme_icon(name, &"EditorIcons") if has_theme_icon(name, &"EditorIcons") else null


static func _sync_text(ahead: int, behind: int) -> String:
	var parts: Array = []
	if ahead > 0:
		parts.append("↑%d" % ahead)
	if behind > 0:
		parts.append("↓%d" % behind)
	return " ".join(parts)


# --- toolbar ---------------------------------------------------------------


func _on_filter_edit_text_changed(_text: String) -> void:
	refresh()


func _new_branch_from(start_point: String) -> void:
	await _sync_bar.new_branch_dialog(start_point)


func _push_branch_to(branch: String) -> void:
	await _sync_bar.push_branch_to(branch)


# --- tree ------------------------------------------------------------------


func _on_tree_item_selected() -> void:
	var meta: Variant = _tree.get_selected().get_metadata(0)
	if not meta is Dictionary:
		return
	var prefixes := { "local": "refs/heads/", "remote_branch": "refs/remotes/", "tag": "refs/tags/" }
	var kind: String = meta.get("kind", "")
	if kind == "stash":
		ref_selected.emit(meta["ref"])
	elif prefixes.has(kind):
		ref_selected.emit(prefixes[kind] + meta["name"])
	else:
		return
	_ref_selected_frame = Engine.get_process_frames()


func _on_branches_tree_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not meta is Dictionary:
		return
	var kind: String = meta.get("kind", "")
	var rewrites_files: bool = kind in ["remote_branch", "tag", "stash"] or (kind == "local" and not meta["is_head"])
	if rewrites_files and not await SaveGuard.ensure_saved(self, "Apply" if kind == "stash" else "Checkout"):
		return
	match kind:
		"local":
			if not meta["is_head"]:
				_checkout(meta["name"])
		"remote_branch":
			_after(_repo.checkout_remote_branch(meta["name"]), "Checkout failed", true)
		"tag":
			await _checkout_detached(meta["name"])
		"stash":
			_after(_repo.stash_apply(meta["ref"], false), "Apply stash failed", true)
		"remote":
			await _edit_remote_url(meta["name"])


func _checkout(name: String) -> void:
	_after(_repo.checkout_branch(name), "Checkout failed", true)


func _checkout_detached(ref: String) -> void:
	if await Dialogs.confirm(self, "Checkout", "Checkout %s?\nThis leaves HEAD detached (not on a branch)." % ref, "Checkout"):
		_after(_repo.checkout_commit(ref), "Checkout failed", true)


func _on_branches_tree_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_item_at_position(mouse_position)
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		_show_context_menu(meta, _tree.get_screen_position() + mouse_position.round())


func _show_context_menu(meta: Dictionary, screen_position: Vector2) -> void:
	_context = meta
	var m := _context_menu
	m.clear()
	var current: String = _repo.get_current_branch()
	var current_label := current if not current.is_empty() else "HEAD"

	match meta.get("kind", ""):
		"local":
			var name: String = meta["name"]
			if not meta["is_head"]:
				m.add_item("Checkout", ID_CHECKOUT)
			m.add_item("New Branch from Here…", ID_NEW_BRANCH_FROM)
			m.add_item("New Tag Here…", ID_NEW_TAG)
			if not meta["is_head"]:
				m.add_separator()
				m.add_item("Compare with %s" % current_label, ID_COMPARE)
				m.add_item("Merge into %s…" % current_label, ID_MERGE)
				m.add_item("Rebase %s onto This…" % current_label, ID_REBASE)
				m.set_item_disabled(m.get_item_index(ID_REBASE), current.is_empty())
			m.add_separator()
			m.add_item("Push…", ID_PUSH_BRANCH)
			m.add_item("Set Upstream…", ID_SET_UPSTREAM)
			if not meta["upstream"].is_empty():
				m.add_item("Unset Upstream", ID_UNSET_UPSTREAM)
				var site := WebLinks.site(_repo, String(meta["upstream"]).get_slice("/", 0))
				if not site.is_empty():
					m.add_item("Open on %s" % site["name"], ID_OPEN_ON_WEB)
					m.add_item("Create %s on %s…" % ["Merge Request" if site["kind"] == "gitlab" else "Pull Request", site["name"]], ID_PULL_REQUEST)
			m.add_separator()
			m.add_item("Rename…", ID_RENAME)
			m.add_item("Delete…", ID_DELETE)
			m.set_item_disabled(m.get_item_index(ID_DELETE), meta["is_head"])
			m.add_item("Copy Name", ID_COPY_NAME)
		"remote_branch":
			m.add_item("Checkout (as tracking branch)", ID_CHECKOUT)
			m.add_item("New Branch from Here…", ID_NEW_BRANCH_FROM)
			m.add_separator()
			m.add_item("Compare with %s" % current_label, ID_COMPARE)
			m.add_item("Merge into %s…" % current_label, ID_MERGE)
			m.add_item("Rebase %s onto This…" % current_label, ID_REBASE)
			m.set_item_disabled(m.get_item_index(ID_REBASE), current.is_empty())
			var remote_site := WebLinks.site(_repo, String(meta.get("remote", "")))
			if not remote_site.is_empty():
				m.add_item("Open on %s" % remote_site["name"], ID_OPEN_ON_WEB)
			m.add_separator()
			m.add_item("Delete from Remote…", ID_DELETE_REMOTE_BRANCH)
			m.add_item("Copy Name", ID_COPY_NAME)
		"tag":
			m.add_item("Checkout (detached)…", ID_CHECKOUT)
			m.add_item("New Branch from Here…", ID_NEW_BRANCH_FROM)
			m.add_item("Compare with %s" % current_label, ID_COMPARE)
			m.add_item("Merge into %s…" % current_label, ID_MERGE)
			m.add_separator()
			m.add_item("Push Tag", ID_PUSH_TAG)
			m.add_item("Delete…", ID_DELETE_TAG)
			m.add_item("Delete from Remote…", ID_DELETE_REMOTE_TAG)
			m.add_item("Copy Name", ID_COPY_NAME)
		"stash":
			m.add_item("Show Changes", ID_STASH_SHOW)
			m.add_item("Apply", ID_STASH_APPLY)
			m.add_item("Pop (apply and drop)", ID_STASH_POP)
			m.add_item("New Branch from Stash…", ID_STASH_BRANCH)
			m.add_separator()
			m.add_item("Drop…", ID_STASH_DROP)
		"remote":
			m.add_item("Fetch", ID_FETCH_REMOTE)
			m.add_item("Edit URL…", ID_EDIT_REMOTE_URL)
			m.add_item("Rename…", ID_RENAME_REMOTE)
			m.add_item("Remove…", ID_REMOVE_REMOTE)
			m.add_separator()
			m.add_item("Add Remote…", ID_ADD_REMOTE)
		"section":
			match meta["title"]:
				"Remotes", "Remote":
					m.add_item("Add Remote…", ID_ADD_REMOTE)
					m.add_item("Fetch All and Prune Deleted Branches", ID_FETCH_PRUNE)
				"Tags":
					m.add_item("New Tag at HEAD…", ID_NEW_TAG)
				"Local":
					m.add_item("New Branch…", ID_NEW_BRANCH_FROM)
				_:
					return # Stashes: nothing to add from here
		_:
			return

	m.position = screen_position
	m.reset_size()
	m.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	var kind: String = _context.get("kind", "")
	var name: String = _context.get("name", "")
	var verbs := { ID_CHECKOUT: "Checkout", ID_MERGE: "Merge", ID_REBASE: "Rebase", ID_STASH_APPLY: "Apply", ID_STASH_POP: "Pop", ID_STASH_BRANCH: "Checkout" }
	if verbs.has(id) and not await SaveGuard.ensure_saved(self, verbs[id]):
		return
	match id:
		ID_CHECKOUT:
			match kind:
				"local": _checkout(name)
				"remote_branch": _after(_repo.checkout_remote_branch(name), "Checkout failed", true)
				"tag": await _checkout_detached(name)
		ID_NEW_BRANCH_FROM:
			await _new_branch_from(name if not name.is_empty() else "HEAD")
		ID_NEW_TAG:
			await _new_tag(name if kind == "local" else "HEAD")
		ID_COMPARE:
			compare_requested.emit("%s ↔ %s" % [_current_label(), name], "HEAD", name)
		ID_MERGE:
			await _merge(name)
		ID_REBASE:
			if await Dialogs.confirm(self, "Rebase",
					"Replay the commits of %s on top of %s?\n\nThis rewrites %s's history — don't do it to commits others already pulled." % [_current_label(), name, _current_label()], "Rebase"):
				_after_operation(_repo.rebase(name), "Rebase")
		ID_PUSH_BRANCH:
			await _push_branch_to(name)
		ID_SET_UPSTREAM:
			await _set_upstream(name, _context.get("upstream", ""))
		ID_UNSET_UPSTREAM:
			_after(_repo.set_upstream(name, ""), "Unset upstream failed")
		ID_RENAME:
			var new_name: Variant = await Dialogs.prompt(self, "Rename Branch", "New name for \"%s\"" % name, name, "Rename")
			if new_name != null and not new_name.is_empty() and new_name != name:
				_after(_repo.rename_branch(name, new_name), "Rename failed")
		ID_DELETE:
			await _delete_branch(name)
		ID_DELETE_REMOTE_BRANCH:
			var remote: String = _context["remote"]
			var branch := name.substr(remote.length() + 1)
			if await Dialogs.confirm(self, "Delete Remote Branch", "Delete branch \"%s\" on %s?\n\nThis affects everyone using that remote." % [branch, remote], "Delete"):
				await _push_refspec(remote, ":refs/heads/" + branch, "Deleted %s." % name)
		ID_COPY_NAME:
			DisplayServer.clipboard_set(name)
		ID_OPEN_ON_WEB, ID_PULL_REQUEST:
			# A local branch opens as its upstream; a remote one as itself.
			var remote_ref: String = _context.get("upstream", "") if kind == "local" else name
			var remote_name := remote_ref.get_slice("/", 0)
			var site := WebLinks.site(_repo, remote_name)
			var branch := remote_ref.substr(remote_name.length() + 1)
			OS.shell_open(WebLinks.branch_url(site, branch) if id == ID_OPEN_ON_WEB else WebLinks.new_pull_request_url(site, branch))
		ID_PUSH_TAG:
			var remote := RemoteActions.default_remote(_repo)
			if remote.is_empty():
				await Dialogs.error(self, "No remotes", "Add a remote first.")
			else:
				await _push_refspec(remote, "refs/tags/" + name, "Pushed tag %s." % name)
		ID_DELETE_TAG:
			if await Dialogs.confirm(self, "Delete Tag", "Delete local tag \"%s\"?" % name, "Delete"):
				_after(_repo.delete_tag(name), "Delete tag failed")
		ID_DELETE_REMOTE_TAG:
			var remote := RemoteActions.default_remote(_repo)
			if not remote.is_empty() and await Dialogs.confirm(self, "Delete Remote Tag", "Delete tag \"%s\" on %s?" % [name, remote], "Delete"):
				await _push_refspec(remote, ":refs/tags/" + name, "Deleted tag %s on %s." % [name, remote])
		ID_FETCH_REMOTE:
			await RemoteActions.fetch(self, _repo, _operation_bar, name)
			refresh()
		ID_FETCH_PRUNE:
			await RemoteActions.fetch(self, _repo, _operation_bar, "", true)
			refresh()
		ID_EDIT_REMOTE_URL:
			await _edit_remote_url(name)
		ID_RENAME_REMOTE:
			var new_name: Variant = await Dialogs.prompt(self, "Rename Remote", "New name for \"%s\"" % name, name, "Rename")
			if new_name != null and not new_name.is_empty() and new_name != name:
				_after(_repo.rename_remote(name, new_name), "Rename remote failed")
		ID_REMOVE_REMOTE:
			if await Dialogs.confirm(self, "Remove Remote", "Remove remote \"%s\"?\nIts remote-tracking branches are deleted locally; nothing on the server changes." % name, "Remove"):
				_after(_repo.remove_remote(name), "Remove remote failed")
		ID_ADD_REMOTE:
			await _add_remote()
		ID_STASH_SHOW:
			compare_requested.emit("Stash: %s" % _context["message"], _context["ref"] + "^", _context["ref"])
		ID_STASH_APPLY:
			_after(_repo.stash_apply(_context["ref"], false), "Apply stash failed", true)
		ID_STASH_POP:
			_after(_repo.stash_apply(_context["ref"], true), "Pop stash failed", true)
		ID_STASH_DROP:
			if await Dialogs.confirm(self, "Drop Stash", "Permanently delete %s (\"%s\")?" % [_context["ref"], _context["message"]], "Drop"):
				_after(_repo.stash_drop(_context["ref"]), "Drop stash failed")
		ID_STASH_BRANCH:
			var branch_name: Variant = await Dialogs.prompt(self, "Branch from Stash",
					"New branch name (created at the commit the stash was made on, with the stash applied and dropped)", "", "Create")
			if branch_name != null and not branch_name.is_empty():
				_after(_repo.stash_branch(branch_name, _context["ref"]), "Branch from stash failed", true)


func _current_label() -> String:
	var current: String = _repo.get_current_branch()
	return current if not current.is_empty() else "HEAD"


func _new_tag(target: String) -> void:
	var answer: Variant = await Dialogs.form(self, "New Tag at %s" % target, [
		{ "key": "name", "label": "Tag name", "placeholder": "v1.0.0" },
		{ "key": "message", "label": "Message (leave empty for a lightweight tag)", "type": "multiline" },
	], "Create")
	if answer == null or String(answer["name"]).strip_edges().is_empty():
		return
	_after(_repo.create_tag(String(answer["name"]).strip_edges(), target, String(answer["message"]).strip_edges()), "Create tag failed")


func _merge(ref: String) -> void:
	var modes := {
		"Default (fast-forward when possible)": "",
		"Always create a merge commit (--no-ff)": "no-ff",
		"Fast-forward only": "ff-only",
		"Squash (stage the changes, commit them yourself)": "squash",
	}
	var answer: Variant = await Dialogs.form(self, "Merge", [
		{ "type": "label", "label": "Merge %s into %s." % [ref, _current_label()] },
		{ "key": "mode", "label": "Mode", "type": "option", "options": modes.keys(), "default": modes.keys()[0] },
	], "Merge")
	if answer == null:
		return
	_after_operation(_repo.merge(ref, modes[answer["mode"]]), "Merge")


func _set_upstream(branch: String, current_upstream: String) -> void:
	var options: Array = []
	for b in _repo.list_branches(false):
		if b["is_remote"]:
			options.append(b["name"])
	if options.is_empty():
		await Dialogs.error(self, "No remote branches", "There are no remote-tracking branches to track. Fetch or push first.")
		return
	var default_choice: String = current_upstream
	if default_choice.is_empty():
		var guess := "%s/%s" % [RemoteActions.default_remote(_repo), branch]
		default_choice = guess if options.has(guess) else options[0]
	var answer: Variant = await Dialogs.form(self, "Set Upstream of \"%s\"" % branch, [
		{ "key": "upstream", "label": "Track", "type": "option", "options": options, "default": default_choice },
	], "Set")
	if answer != null:
		_after(_repo.set_upstream(branch, answer["upstream"]), "Set upstream failed")


func _delete_branch(name: String) -> void:
	if not await Dialogs.confirm(self, "Delete Branch", "Delete local branch \"%s\"?" % name, "Delete"):
		return
	var result: Dictionary = _repo.delete_branch(name, false)
	if not result["ok"] and result["error"].contains("not fully merged"):
		if await Dialogs.confirm(self, "Branch Not Merged",
				"\"%s\" has commits that aren't merged anywhere else — deleting it loses them (they stay recoverable via reflog for a while).\n\nDelete anyway?" % name, "Force Delete"):
			result = _repo.delete_branch(name, true)
		else:
			return
	_after(result, "Delete branch failed")


func _edit_remote_url(name: String) -> void:
	var current_url := ""
	for r in _repo.list_remotes():
		if r["name"] == name:
			current_url = r["fetch_url"]
	var url: Variant = await Dialogs.prompt(self, "Edit Remote URL", "URL of \"%s\"" % name, current_url, "Save")
	if url != null and not url.is_empty() and url != current_url:
		_after(_repo.set_remote_url(name, url), "Set remote URL failed")


func _add_remote() -> void:
	var has_origin: bool = _repo.list_remotes().any(func(r: Dictionary) -> bool: return r["name"] == "origin")
	var answer: Variant = await Dialogs.form(self, "Add Remote", [
		{ "key": "name", "label": "Name", "default": "upstream" if has_origin else "origin" },
		{ "key": "url", "label": "URL", "placeholder": "git@github.com:user/repo.git" },
		{ "key": "fetch", "label": "Fetch it now", "type": "check", "default": true },
	], "Add")
	if answer == null:
		return
	var name := String(answer["name"]).strip_edges()
	var url := String(answer["url"]).strip_edges()
	if name.is_empty() or url.is_empty():
		await Dialogs.error(self, "Add remote failed", "Both a name and a URL are needed.")
		return
	var result: Dictionary = _repo.add_remote(name, url)
	if not result["ok"]:
		await Dialogs.error(self, "Add remote failed", result["error"])
		return
	if answer["fetch"]:
		await RemoteActions.fetch(self, _repo, _operation_bar, name)
	refresh()


func _push_refspec(remote: String, refspec: String, success_text: String) -> void:
	if _repo.is_busy():
		await Dialogs.error(self, "Busy", "Another git operation is still running.")
		return
	_operation_bar.busy("Pushing to %s…" % remote, _repo)
	var result: Dictionary = await _repo.push_refspec(remote, refspec)
	if result["ok"]:
		_operation_bar.done(success_text)
	else:
		_operation_bar.done("Cancelled." if result["cancelled"] else "Push failed.", not result["cancelled"])
		if not result["cancelled"]:
			await Dialogs.error(self, "Push failed", GitErrors.explain(result["error"]))
	refresh()


## Shows result's error if it failed; reload_editor re-scans the project after anything that rewrote the working tree.
func _after(result: Dictionary, error_title: String, reload_editor: bool = false) -> void:
	if reload_editor:
		EditorOpen.refresh_all_external_changes()
	if not result["ok"]:
		Dialogs.error(self, error_title, GitErrors.explain(result["error"]))
	refresh()


## Like _after(), but a stop on conflicts isn't an error — it points to the Changes panel, where they're resolved.
func _after_operation(result: Dictionary, verb: String) -> void:
	EditorOpen.refresh_all_external_changes()
	if result.get("conflicts", false):
		Dialogs.error(self, "%s Stopped on Conflicts" % verb,
				"%s hit conflicts. Resolve them in the Changes tab (Accept Ours/Theirs, or edit and Mark Resolved), then press Continue there — or Abort to undo." % verb)
	elif not result["ok"]:
		Dialogs.error(self, "%s failed" % verb, GitErrors.explain(result["error"]))
	else:
		_operation_bar.done("%s done." % verb)
	refresh()
