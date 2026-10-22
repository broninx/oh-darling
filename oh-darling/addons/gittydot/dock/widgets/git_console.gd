## "Console" tab next to the Git Log: every mutating git command the plugin ran (with its output), plus a prompt for running your own for anything the UI doesn't cover.
@tool
extends VBoxContainer

const GitCli := preload("res://addons/gittydot/util/git_cli.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")

const POLL_INTERVAL := 0.5
## Commands whose output can rewrite the working tree, so the editor reloads open files after them.
const TREE_CHANGING := ["checkout", "switch", "reset", "merge", "rebase", "pull", "cherry-pick", "revert", "stash", "restore", "apply", "am", "clean", "rm", "mv"]

var _repo: RefCounted
var _output: RichTextLabel
var _input: LineEdit
var _run_button: Button
var _timer: Timer
var _shown_revision := -1
var _entry_paragraphs := {}
## Command-line history for Up/Down in the prompt.
var _history: PackedStringArray = []
var _history_index := 0


func _init() -> void:
	var bar := HBoxContainer.new()
	var hint := Label.new()
	hint.text = "Every git command GittyDot runs is logged here."
	hint.modulate.a = 0.6
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	hint.clip_text = true
	bar.add_child(hint)
	var copy := Button.new()
	copy.text = "Copy"
	copy.flat = true
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_output.get_parsed_text()))
	bar.add_child(copy)
	var clear := Button.new()
	clear.text = "Clear"
	clear.flat = true
	clear.pressed.connect(GitCli.clear_log)
	bar.add_child(clear)
	add_child(bar)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.context_menu_enabled = true
	_output.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_output)

	var prompt_row := HBoxContainer.new()
	var prompt := Label.new()
	prompt.text = "git"
	prompt.modulate = Color(0.6, 0.8, 1.0)
	prompt_row.add_child(prompt)
	_input = LineEdit.new()
	_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.placeholder_text = "status, log --oneline -5, reflog, bisect start … (runs in the repo root; no interactive commands)"
	_input.text_submitted.connect(func(_t: String) -> void: _run())
	_input.gui_input.connect(_on_input_gui_input)
	prompt_row.add_child(_input)
	_run_button = Button.new()
	_run_button.text = "Run"
	_run_button.pressed.connect(_run)
	prompt_row.add_child(_run_button)
	add_child(prompt_row)

	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL
	_timer.timeout.connect(_update)
	add_child(_timer)


func set_repo(repo: RefCounted) -> void:
	_repo = repo
	_notification(NOTIFICATION_VISIBILITY_CHANGED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _timer != null:
		if is_visible_in_tree() and _repo != null:
			_timer.start()
			_update()
		else:
			_timer.stop()


func _update() -> void:
	var snapshot := GitCli.log_snapshot(_shown_revision)
	if snapshot.is_empty():
		return
	_shown_revision = snapshot["revision"]
	_output.clear()
	_entry_paragraphs.clear()
	for entry in snapshot["entries"]:
		_entry_paragraphs[entry.get("id", -1)] = maxi(0, _output.get_paragraph_count() - 1)
		var time := Time.get_time_string_from_unix_time(entry["time"])
		var ok: bool = entry["exit_code"] == 0
		_output.push_color(Color(0.55, 0.55, 0.6))
		_output.add_text("[%s] " % time)
		_output.pop()
		_output.push_color(Color(0.6, 0.8, 1.0))
		var title: String = entry.get("diagnostic_title", "")
		if title.is_empty():
			_output.add_text("$ git " + " ".join(_quote_args(entry["args"])))
		else:
			_output.add_text("GittyDot: " + title)
		_output.pop()
		_output.push_color(Color(0.55, 0.85, 0.55) if ok else Color(0.95, 0.5, 0.5))
		_output.add_text("   ✓\n" if ok else "   ✗ exit %d\n" % entry["exit_code"])
		_output.pop()
		var text: String = String(entry["text"]).strip_edges(false, true)
		if not text.is_empty():
			_output.push_color(Color(0.8, 0.8, 0.82) if ok else Color(0.95, 0.7, 0.7))
			_output.add_text(text + "\n")
			_output.pop()
		_output.add_text("\n")


## Navigate to the referenced failure, even if later commands have been logged.
func reveal_entry(entry_id: int) -> void:
	_update()
	_output.scroll_to_paragraph.call_deferred(int(_entry_paragraphs.get(entry_id, maxi(0, _output.get_paragraph_count() - 1))))
	_output.grab_focus()


static func _quote_args(args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for a in args:
		out.append("\"%s\"" % a if a.contains(" ") or a.contains("\n") else a)
	return out


## Splits a command line into argv, honoring "double" and 'single' quotes (no shell is involved, so no other expansion happens).
static func split_args(line: String) -> PackedStringArray:
	var args := PackedStringArray()
	var current := ""
	var quote := ""
	var has_token := false
	for ch in line:
		if not quote.is_empty():
			if ch == quote:
				quote = ""
			else:
				current += ch
		elif ch == "\"" or ch == "'":
			quote = ch
			has_token = true
		elif ch == " " or ch == "\t":
			if has_token or not current.is_empty():
				args.append(current)
			current = ""
			has_token = false
		else:
			current += ch
	if has_token or not current.is_empty():
		args.append(current)
	return args


## Locate the command after git's global options, so -C/-c cannot bypass a gate.
static func command_index(args: PackedStringArray) -> int:
	var i := 0
	while i < args.size():
		if args[i] in ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path"]:
			i += 2
		elif args[i].begins_with("-"):
			i += 1
		else:
			return i
	return -1


static func confirmation_reason(args: PackedStringArray) -> String:
	var index := command_index(args)
	if index < 0:
		return ""
	for i in index:
		var override := ""
		if args[i] in ["-c", "--config-env"] and i + 1 < index:
			override = args[i + 1].to_lower()
		elif args[i].begins_with("-c"):
			override = args[i].substr(2).to_lower()
		elif args[i].begins_with("--config-env="):
			override = args[i].trim_prefix("--config-env=").to_lower()
		if override.begins_with("alias.") or override.begins_with("core.sshcommand="):
			return "This supplies an executable Git configuration override; review it before running."
	var command := args[index]
	var options := args.slice(index + 1)
	var delimiter := options.find("--")
	var flags := options.slice(0, delimiter) if delimiter >= 0 else options
	if command == "reset" and options.has("--hard"):
		return "This discards tracked changes and moves the current branch or index."
	if command == "clean":
		for option in flags:
			if option == "--dry-run" or (option.begins_with("-") and not option.begins_with("--") and option.contains("n")):
				return ""
		return "This deletes untracked files or directories, which Git cannot restore."
	if command == "push":
		for option in options:
			if option.begins_with("--force") or option == "--mirror" or option.begins_with("+") or (option.begins_with("-") and not option.begins_with("--") and option.contains("f")):
				return "This can replace or delete history on the remote repository."
	if command == "config" and (flags.has("--global") or flags.has("--system")):
		for option in flags:
			if option in ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"]:
				return ""
		var positional := Array(options).filter(func(option: String) -> bool: return not option.begins_with("-"))
		if not positional.is_empty() and positional[0] in ["get", "list"]:
			return ""
		if delimiter >= 0:
			return "This changes Git settings outside this project."
		if positional.size() == 1 and not positional[0] in ["edit", "set", "unset", "rename-section", "remove-section"] and not options.has("--unset") and not options.has("--unset-all") and not options.has("--remove-section"):
			return "" # legacy `git config --global key` is a read
		return "This changes Git settings outside this project."
	return ""


func _confirmation_reason(args: PackedStringArray, depth := 0) -> String:
	var reason := confirmation_reason(args)
	var index := command_index(args)
	if not reason.is_empty() or index < 0:
		return reason
	# Git aliases can hide destructive commands or execute a shell command.
	var lookup := Array(args.slice(0, index))
	lookup.append_array(["config", "--get", "alias." + args[index]])
	var alias: String = GitCli.run(_repo.get_repo_root(), lookup)["text"].strip_edges()
	if alias.is_empty():
		return ""
	if alias.begins_with("!") or depth >= 4:
		return "This alias executes a shell command or another alias; review it before running:\n" + alias
	var expanded := split_args(alias)
	expanded.append_array(args.slice(index + 1))
	return _confirmation_reason(expanded, depth + 1)


func _run() -> void:
	var line := _input.text.strip_edges()
	if line.begins_with("git "):
		line = line.substr(4)
	if line.is_empty() or _repo == null or _repo.is_busy() or _run_button.disabled:
		return
	_input.editable = false
	_run_button.disabled = true
	var args := split_args(line)
	var reason := _confirmation_reason(args)
	if not reason.is_empty() and not await Dialogs.confirm(self, "Run Git Command?", reason + "\n\ngit " + line, "Run Command"):
		_unlock_prompt()
		return
	var index := command_index(args)
	var changes_tree := index >= 0 and TREE_CHANGING.has(args[index])
	if changes_tree and not await SaveGuard.ensure_saved(self, "Run Git Command"):
		_unlock_prompt()
		return
	if _repo.is_busy():
		_unlock_prompt()
		return
	_history.append(line)
	_history_index = _history.size()
	_input.text = ""
	var job := GitCli.start(_repo.get_repo_root(), args)
	_repo.current_job = job
	await job.finished
	if _repo.current_job == job:
		_repo.current_job = null
	_unlock_prompt()
	if changes_tree:
		EditorOpen.refresh_all_external_changes()


func _unlock_prompt() -> void:
	_input.editable = true
	_run_button.disabled = false
	_input.grab_focus()


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or _history.is_empty():
		return
	if event.keycode == KEY_UP:
		_history_index = maxi(0, _history_index - 1)
	elif event.keycode == KEY_DOWN:
		_history_index = mini(_history.size(), _history_index + 1)
	else:
		return
	_input.text = _history[_history_index] if _history_index < _history.size() else ""
	_input.caret_column = _input.text.length()
	_input.accept_event()
