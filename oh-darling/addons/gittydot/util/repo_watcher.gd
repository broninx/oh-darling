## Polls the project's repo once for every panel (`git status` plus refs, config and stash reflog) on a worker thread, only while the editor has focus.
@tool
extends Node

const GitCliRepo := preload("res://addons/gittydot/util/git_cli_repo.gd")
const RepoOpener := preload("res://addons/gittydot/util/repo_opener.gd")

## Saves, rescans and refocusing the editor poll right away, so the timer only catches the rest.
const INTERVAL := 10.0

## A GitCliRepo.snapshot_of() dictionary; subscribers parse "status" with their own repo's parse_status().
signal polled(snapshot: Dictionary)

## The plugin's watcher while it's enabled, so panels can subscribe via watch() without having it passed down.
static var instance: Node

## The watcher's own repo instance, null outside a git repo.
var repo: RefCounted
var _timer: Timer
var _thread: Thread
## poll_now() came in while a poll was running: poll again once it's done.
var _again := false


## Calls on_polled with every snapshot; a CanvasItem also polls right away whenever it's shown again (it may have skipped snapshots while hidden).
static func watch(node: Node, on_polled: Callable) -> void:
	if instance == null or instance.polled.is_connected(on_polled):
		return
	instance.polled.connect(on_polled)
	if node is CanvasItem:
		node.visibility_changed.connect(func() -> void:
			if node.is_visible_in_tree() and is_instance_valid(instance):
				instance.poll_now()
		)


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	repo = RepoOpener.open_current_project_repo()["repo"]
	if repo == null:
		return
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.timeout.connect(poll_now)
	add_child(_timer)
	_timer.start()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _timer != null:
		_timer.stop()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _notification(what: int) -> void:
	if repo == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_timer.start()
		poll_now()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_timer.stop()


## Polls now (a running poll is followed by one more), e.g. after a save.
func poll_now() -> void:
	if repo == null or not is_inside_tree():
		return
	if _thread != null:
		_again = true
		return
	if not _timer.is_stopped():
		_timer.start() # the next tick a full interval from now
	var root: String = repo.get_repo_root()
	var git_dir: String = repo.get_git_dir()
	var common_dir: String = repo.get_common_dir()
	_thread = Thread.new()
	_thread.start(func() -> Dictionary: return GitCliRepo.snapshot_of(root, git_dir, common_dir, true))
	_collect()


## Joins the worker once it's done, without blocking the editor meanwhile.
func _collect() -> void:
	while _thread != null and _thread.is_alive():
		if not is_inside_tree():
			return # _exit_tree() joins it
		await get_tree().process_frame
	if _thread == null:
		return
	var snapshot: Dictionary = _thread.wait_to_finish()
	_thread = null
	polled.emit(snapshot)
	if _again:
		_again = false
		poll_now()
