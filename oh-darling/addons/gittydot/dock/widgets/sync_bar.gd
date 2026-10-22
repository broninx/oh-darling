## Header shared by the Changes and Branches panels: a branch switcher, upstream + ahead/behind, and compact Fetch / Pull / Push (with their option menus) over an OperationBar for progress.
@tool
extends VBoxContainer

const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")
const OperationBar := preload("res://addons/gittydot/dock/widgets/operation_bar.gd")
const RemoteActions := preload("res://addons/gittydot/dock/widgets/remote_actions.gd")
const WebLinks := preload("res://addons/gittydot/util/web_links.gd")
const GitErrors := preload("res://addons/gittydot/util/git_errors.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")

## Something this bar did (checkout, fetch, pull, push…) may have changed the repo — the owning panel should refresh.
signal changed

enum { PULL_DEFAULT, PULL_MERGE, PULL_REBASE, PULL_FF_ONLY, PULL_AUTOSTASH }
enum { PUSH_DEFAULT, PUSH_WITH_TAGS, PUSH_TO, PUSH_FORCE, PUSH_PULL_REQUEST }
const ID_NEW_BRANCH := 100000

## Where progress and results go: its own strip, or the one use_operation_bar() pointed it to.
var operation_bar: HBoxContainer
var _own_operation_bar: HBoxContainer

var _repo: RefCounted
var _branch_button: MenuButton
var _upstream_label: Label
var _fetch_button: Button
var _pull_button: Button
var _pull_menu: MenuButton
var _push_button: Button
var _push_menu: MenuButton
var _pull_autostash := false
## Local branch names in the switcher popup, by item id.
var _menu_branches: Array = []


func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	_branch_button = MenuButton.new()
	_branch_button.flat = false
	_branch_button.tooltip_text = "Current branch — click to switch"
	_branch_button.about_to_popup.connect(_fill_branch_menu)
	_branch_button.get_popup().id_pressed.connect(_on_branch_menu_id_pressed)
	row.add_child(_branch_button)

	_upstream_label = Label.new()
	_upstream_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_upstream_label.clip_text = true
	_upstream_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_upstream_label.modulate.a = 0.7
	_upstream_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_upstream_label)

	_fetch_button = _button(row, "Fetch", "Fetch all remotes — updates remote branches and tags, never touches your files", _on_fetch_pressed)

	_pull_button = _button(row, "Pull", "", _on_pull_pressed)
	_pull_menu = _menu_button(row, "Pull options")
	var pull_popup := _pull_menu.get_popup()
	pull_popup.add_item("Pull (git config default)", PULL_DEFAULT)
	pull_popup.add_item("Pull — Merge", PULL_MERGE)
	pull_popup.add_item("Pull — Rebase", PULL_REBASE)
	pull_popup.add_item("Pull — Fast-forward only", PULL_FF_ONLY)
	pull_popup.add_separator()
	pull_popup.add_check_item("Stash local changes around pull (autostash)", PULL_AUTOSTASH)
	pull_popup.hide_on_checkable_item_selection = false
	pull_popup.id_pressed.connect(_on_pull_menu_id_pressed)

	_push_button = _button(row, "Push", "", _on_push_pressed)
	_push_menu = _menu_button(row, "Push options")
	var push_popup := _push_menu.get_popup()
	push_popup.add_item("Push", PUSH_DEFAULT)
	push_popup.add_item("Push with Annotated Tags", PUSH_WITH_TAGS)
	push_popup.set_item_tooltip(push_popup.get_item_index(PUSH_WITH_TAGS), "Also pushes the annotated tags on the pushed commits (--follow-tags). A lightweight tag is pushed from Branches: right-click it, Push Tag.")
	push_popup.add_item("Push to…", PUSH_TO)
	push_popup.add_separator()
	push_popup.add_item("Force Push (with lease)…", PUSH_FORCE)
	push_popup.id_pressed.connect(_on_push_menu_id_pressed)
	push_popup.about_to_popup.connect(_update_pull_request_item.bind(push_popup))

	var refresh := _button(row, "", "Refresh", func() -> void: changed.emit())
	refresh.flat = true
	refresh.set_meta("icon_name", &"Reload")

	operation_bar = OperationBar.new()
	_own_operation_bar = operation_bar
	add_child(operation_bar)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		# Editor icons are only reachable once the bar is in the editor's theme.
		_set_icon(_branch_button, &"GuiTreeArrowDown")
		_set_icon(_fetch_button, &"Reload")
		_set_icon(_pull_button, &"ArrowDown")
		_set_icon(_push_button, &"ArrowUp")
		for child in get_child(0).get_children():
			if child.has_meta("icon_name"):
				_set_icon(child, child.get_meta("icon_name"))


func _set_icon(button: Button, icon_name: StringName) -> void:
	if has_theme_icon(icon_name, &"EditorIcons"):
		button.icon = get_theme_icon(icon_name, &"EditorIcons")


func _button(row: HBoxContainer, text: String, tooltip: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.pressed.connect(on_pressed)
	row.add_child(b)
	return b


func _menu_button(row: HBoxContainer, tooltip: String) -> MenuButton:
	var m := MenuButton.new()
	m.text = "▾"
	m.flat = false
	m.tooltip_text = tooltip
	row.add_child(m)
	return m


func set_repo(repo: RefCounted) -> void:
	_repo = repo
	refresh()


## The combined dock's window-wide toolbar: no branch switcher (the sidebar lists and switches branches) and Fetch/Pull/Push at the left instead of far off at the right.
func set_toolbar_mode(on: bool) -> void:
	var row := get_child(0)
	_branch_button.visible = not on
	row.move_child(_upstream_label, row.get_child_count() - 1 if on else 1)
	refresh()


## Hides the branch/Fetch/Pull/Push row, for the Branches sidebar under the combined dock's shared row.
func set_row_visible(on: bool) -> void:
	get_child(0).visible = on


## Reports into other's strip instead of its own (the combined dock's toolbar, so messages don't pop up in the sidebar); null goes back to its own.
func use_operation_bar(other: HBoxContainer) -> void:
	_own_operation_bar.visible = false
	operation_bar = other if other != null else _own_operation_bar


## Re-reads branch, upstream and ahead/behind (cheap: a few rev-parse calls).
func refresh() -> void:
	if _repo == null:
		return
	var s: Dictionary = _repo.get_sync_status()
	var detached: bool = s["branch"].is_empty()
	_branch_button.text = ("⎇ " + s["branch"]) if not detached else "⎇ detached HEAD"
	_branch_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var op: Dictionary = _repo.get_operation_state()
	var parts: Array = []
	if not op["kind"].is_empty():
		parts.append("%s in progress" % op["kind"].capitalize())
	if detached:
		parts.append("not on a branch")
	elif s["upstream"].is_empty():
		parts.append("not published yet")
	else:
		parts.append("→ " + s["upstream"] + ("  ✓ up to date" if s["ahead"] == 0 and s["behind"] == 0 else ""))
	if not _branch_button.visible and not detached:
		parts.push_front(s["branch"]) # toolbar mode: the switcher that names it is hidden
	_upstream_label.text = " · ".join(parts)
	_upstream_label.tooltip_text = _upstream_label.text
	if not detached and s["upstream"].is_empty():
		_upstream_label.tooltip_text += "\n%s exists only here, no remote branch tracks it. Push publishes it and sets that up." % s["branch"]

	_pull_button.text = "Pull ↓%d" % s["behind"] if s["behind"] > 0 else "Pull"
	_pull_button.tooltip_text = "Fetch and integrate %s's upstream%s" % [s["branch"], " (%d new commit%s)" % [s["behind"], "" if s["behind"] == 1 else "s"] if s["behind"] > 0 else ""]
	_push_button.text = "Push ↑%d" % s["ahead"] if s["ahead"] > 0 else "Push"
	_push_button.tooltip_text = "Push %s%s" % [s["branch"], " (%d commit%s)" % [s["ahead"], "" if s["ahead"] == 1 else "s"] if s["ahead"] > 0 else "" if not s["upstream"].is_empty() else " — publishes it, since it has no upstream yet"]
	for control in [_pull_button, _pull_menu, _push_button, _push_menu]:
		control.disabled = detached
	if detached:
		_push_button.tooltip_text = "HEAD is detached — checkout a branch to push"


func _fill_branch_menu() -> void:
	var popup := _branch_button.get_popup()
	popup.clear()
	_menu_branches.clear()
	popup.add_separator("Switch to branch")
	for b in _repo.list_branches(true):
		var id := _menu_branches.size()
		_menu_branches.append(b["name"])
		popup.add_radio_check_item(b["name"], id)
		popup.set_item_checked(popup.get_item_index(id), b["is_head"])
		if b["is_head"]:
			popup.set_item_disabled(popup.get_item_index(id), true)
	popup.add_separator()
	popup.add_item("New Branch…", ID_NEW_BRANCH)


func _on_branch_menu_id_pressed(id: int) -> void:
	if id == ID_NEW_BRANCH:
		await new_branch_dialog("HEAD")
		return
	if id < 0 or id >= _menu_branches.size() or not await SaveGuard.ensure_saved(self, "Checkout"):
		return
	var result: Dictionary = _repo.checkout_branch(_menu_branches[id])
	EditorOpen.refresh_all_external_changes()
	if not result["ok"]:
		await Dialogs.error(self, "Checkout failed", GitErrors.explain(result["error"]))
	else:
		operation_bar.done("Switched to %s." % _menu_branches[id])
	_finish()


## Shared with the Branches panel's "New Branch…".
func new_branch_dialog(start_point: String) -> void:
	var answer: Variant = await Dialogs.form(self, "New Branch", [
		{ "key": "name", "label": "Name", "placeholder": "feature/my-branch" },
		{ "key": "start", "label": "Start point", "default": start_point },
		{ "key": "checkout", "label": "Switch to it (uncommitted changes come along)", "type": "check", "default": true },
	], "Create")
	if answer == null or String(answer["name"]).strip_edges().is_empty():
		return
	var result: Dictionary = _repo.create_branch(String(answer["name"]).strip_edges(), String(answer["start"]).strip_edges(), answer["checkout"])
	if not result["ok"]:
		await Dialogs.error(self, "Create branch failed", GitErrors.explain(result["error"]))
	elif answer["checkout"]:
		EditorOpen.refresh_all_external_changes()
	_finish()


func _on_fetch_pressed() -> void:
	await RemoteActions.fetch(self, _repo, operation_bar)
	_finish()


func _on_pull_pressed() -> void:
	await RemoteActions.pull(self, _repo, operation_bar, "", _pull_autostash)
	_finish()


func _on_pull_menu_id_pressed(id: int) -> void:
	var popup := _pull_menu.get_popup()
	match id:
		PULL_AUTOSTASH:
			_pull_autostash = not _pull_autostash
			popup.set_item_checked(popup.get_item_index(PULL_AUTOSTASH), _pull_autostash)
			return
		PULL_MERGE: await RemoteActions.pull(self, _repo, operation_bar, "merge", _pull_autostash)
		PULL_REBASE: await RemoteActions.pull(self, _repo, operation_bar, "rebase", _pull_autostash)
		PULL_FF_ONLY: await RemoteActions.pull(self, _repo, operation_bar, "ff-only", _pull_autostash)
		_: await RemoteActions.pull(self, _repo, operation_bar, "", _pull_autostash)
	_finish()


func _on_push_pressed() -> void:
	await RemoteActions.push(self, _repo, operation_bar)
	_finish()


func _on_push_menu_id_pressed(id: int) -> void:
	match id:
		PUSH_WITH_TAGS:
			await RemoteActions.push(self, _repo, operation_bar, { "tags": true })
		PUSH_FORCE:
			if await Dialogs.confirm(self, "Force Push",
					"Overwrite the remote branch with your local one?\n\nUses --force-with-lease: it still refuses if someone pushed commits you haven't fetched.", "Force Push"):
				await RemoteActions.push(self, _repo, operation_bar, { "force_with_lease": true })
		PUSH_TO:
			await push_branch_to(_repo.get_current_branch())
		PUSH_PULL_REQUEST:
			var upstream: String = _repo.get_upstream()
			var remote := upstream.get_slice("/", 0)
			OS.shell_open(WebLinks.new_pull_request_url(WebLinks.site(_repo, remote), upstream.substr(remote.length() + 1)))
			return
		_:
			await RemoteActions.push(self, _repo, operation_bar)
	_finish()


## "Create Pull Request on GitHub" at the end of the push menu while the branch is pushed to one of the known sites.
func _update_pull_request_item(popup: PopupMenu) -> void:
	var index := popup.get_item_index(PUSH_PULL_REQUEST)
	if index != -1:
		popup.remove_item(index)
		popup.remove_item(index - 1) # its separator
	var upstream: String = _repo.get_upstream() if _repo != null else ""
	if upstream.is_empty():
		return
	var site := WebLinks.site(_repo, upstream.get_slice("/", 0))
	if site.is_empty():
		return
	popup.add_separator()
	popup.add_item("Create %s on %s…" % ["Merge Request" if site["kind"] == "gitlab" else "Pull Request", site["name"]], PUSH_PULL_REQUEST)


## Asks for remote + remote branch name, then pushes (optionally setting upstream). Shared with the Branches panel.
func push_branch_to(branch: String) -> void:
	if branch.is_empty():
		return
	var remote_names: Array = _repo.list_remotes().map(func(r: Dictionary) -> String: return r["name"])
	if remote_names.is_empty():
		await Dialogs.error(self, "No remotes", "Add a remote first (Branches → right-click Remotes).")
		return
	var answer: Variant = await Dialogs.form(self, "Push \"%s\"" % branch, [
		{ "key": "remote", "label": "Remote", "type": "option", "options": remote_names, "default": RemoteActions.default_remote(_repo) },
		{ "key": "target", "label": "Remote branch name", "default": branch },
		{ "key": "track", "label": "Track it (set as upstream)", "type": "check", "default": _repo.get_upstream(branch).is_empty() },
	], "Push")
	if answer == null:
		return
	var target := String(answer["target"]).strip_edges()
	var refspec := branch if target == branch or target.is_empty() else "%s:%s" % [branch, target]
	await RemoteActions.push(self, _repo, operation_bar, { "remote": answer["remote"], "branch": refspec, "set_upstream": answer["track"] })
	_finish()


func _finish() -> void:
	refresh()
	changed.emit()
