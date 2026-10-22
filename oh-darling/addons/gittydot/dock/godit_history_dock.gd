@tool
extends Control

const RepoOpener := preload("res://addons/gittydot/util/repo_opener.gd")
const GitConsole := preload("res://addons/gittydot/dock/widgets/git_console.gd")
const RepoInitView := preload("res://addons/gittydot/dock/widgets/repo_init_view.gd")

@onready var _message_label: Label = %MessageLabel
@onready var _history_panel: Control = %HistoryPanel

## A git_cli_repo.gd instance, or null if this project isn't a git repo.
var _repo: RefCounted
var _tabs: TabContainer
var _console: Control

## Forwarded from the Log panel; plugin.gd brings the Changes tab to front.
signal changes_requested(action: String)


func _ready() -> void:
	var opened := RepoOpener.open_current_project_repo()
	if opened["repo"] == null:
		_history_panel.visible = false
		add_child(RepoInitView.new("This project isn't a git repository yet, so there's no history to show."))
		return

	_repo = opened["repo"]
	_message_label.visible = false
	_history_panel.visible = true
	_history_panel.set_repo(_repo)
	_history_panel.changes_requested.connect(changes_requested.emit)
	_add_console_tab()


## Log and Console share the bottom panel as tabs — the console lists every git command the plugin ran and can run your own.
func _add_console_tab() -> void:
	var tabs := TabContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tabs)
	remove_child(_history_panel)
	_history_panel.name = "Log"
	tabs.add_child(_history_panel)
	var console := GitConsole.new()
	console.name = "Console"
	tabs.add_child(console)
	console.set_repo(_repo)
	_tabs = tabs
	_console = console


## Pulls Log and Console out of the tab bar for the combined dock ({} without a repo: nothing to show there).
func detach_panels() -> Dictionary:
	if _tabs == null:
		return {}
	_tabs.remove_child(_history_panel)
	_tabs.remove_child(_console)
	return {"history": _history_panel, "console": _console}


## Reverses detach_panels(); the combined dock has already let go of them.
func reattach_panels() -> void:
	if _tabs != null:
		_tabs.add_child(_history_panel)
		_tabs.add_child(_console)


## Brings the Log tab to front with oid selected.
func show_commit(oid: String) -> void:
	if _repo == null:
		return
	if _history_panel.get_parent() == _tabs:
		_tabs.current_tab = _history_panel.get_index()
	_history_panel.show_commit(oid)


## Filters the log to one file and brings the Log tab to front (Changes panel → Show History).
func show_file_history(path: String) -> void:
	if _repo == null:
		return
	if _history_panel.get_parent() == _tabs:
		_tabs.current_tab = _history_panel.get_index()
	_history_panel.set_path_filter(path)


func show_console(entry_id: int) -> void:
	if _tabs == null or _console == null:
		return
	_tabs.current_tab = _console.get_index()
	_console.reveal_entry(entry_id)
