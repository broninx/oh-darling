## Thin wrapper around OS.execute_with_pipe() for running `git` in a given repo root.
## No class_name: internal helper, addressed via preload (see
## git_status_flags.gd for why).
@tool
extends RefCounted

## Record/unit separators for multi-field git log output, instead of -z's NUL, which the String output would truncate at.
const RS := "\u001e"
const US := "\u001f"

const LOG_LIMIT := 400

## Env vars set for the whole editor process while the plugin is enabled, so no git command can ever block on an interactive prompt (there's no terminal to answer it) — see prepare_environment().
const ENV_OVERRIDES := {
	"GIT_TERMINAL_PROMPT": "0",
	"GIT_EDITOR": "true",
	"GIT_SEQUENCE_EDITOR": "true",
	"GIT_MERGE_AUTOEDIT": "no",
}

## Every mutating/async command run, newest last: {"time": int, "args": PackedStringArray, "exit_code": int, "text": String}. Shared by all repo instances (static), read by the Git Console tab.
static var _command_log: Array = []
## Bumped on every append, so the console can cheaply tell whether to redraw.
static var _command_log_revision := 0
static var _log_mutex := Mutex.new()

static var _saved_env: Dictionary = {}
## Jobs whose thread hasn't been joined yet; shutdown() kills and joins them.
static var _active_jobs: Array = []


## Runs `git <args>` in repo_root: {"exit_code", "text"}. include_stderr appends stderr (and logs to command_log) — for mutating commands whose error text matters; parsed read-only output leaves it off.
static func run(repo_root: String, args: Array, include_stderr: bool = false) -> Dictionary:
	var result := execute("git", argv(repo_root, args))
	var text: String = result["out"].get_string_from_utf8()
	if include_stderr:
		var err: String = result["err"].get_string_from_utf8()
		text += ("\n" if not text.is_empty() and not text.ends_with("\n") and not err.is_empty() else "") + err
		record(args, result["exit_code"], text)
	return { "exit_code": result["exit_code"], "text": text }


## Starts `git <args>` on a worker thread and returns a Job; `await job.finished` yields the same {"exit_code", "text", "cancelled"} shape as run() (stderr always included). For network operations, which would otherwise freeze the editor.
static func start(repo_root: String, args: Array, log_to_console := true) -> Job:
	var job := Job.new()
	job.finished.connect(func(result: Dictionary) -> void:
		_active_jobs.erase(job)
		if log_to_console:
			record(args, result["exit_code"], result["text"])
	)
	_active_jobs.append(job)
	job.start(argv(repo_root, args))
	return job


## Called by plugin.gd on disable/editor quit: kills every running git process and joins its thread, without emitting finished (the UI awaiting it is being freed).
static func shutdown() -> void:
	for job in _active_jobs:
		job.abandon()
	_active_jobs.clear()


## Like run(), but returns stdout as raw bytes, e.g. for image blobs.
static func run_bytes(repo_root: String, args: Array) -> PackedByteArray:
	return execute("git", argv(repo_root, args))["out"]


## Runs program with argv passed straight through: {"exit_code", "out", "err"} as bytes. OS.execute() with output goes through `sh -c` on macOS/Linux with args only wrapped in "…", so quotes break it and $() or backticks in a message or file name would run.
static func execute(program: String, args: PackedStringArray) -> Dictionary:
	var info := OS.execute_with_pipe(program, args, true)
	if info.is_empty():
		return { "exit_code": -1, "out": PackedByteArray(), "err": PackedByteArray() }
	var stderr: FileAccess = info["stderr"]
	# Both pipes drained at once, so a chatty stderr can't fill up and stall the process.
	var err_thread := Thread.new()
	err_thread.start(func() -> PackedByteArray: return _read_all(stderr))
	var out := _read_all(info["stdio"])
	var err: PackedByteArray = err_thread.wait_to_finish()
	var pid: int = info["pid"]
	while OS.is_process_running(pid):
		OS.delay_usec(100)
	return { "exit_code": OS.get_process_exit_code(pid), "out": out, "err": err }


## Reads a blocking pipe until the process closes it.
static func _read_all(pipe: FileAccess) -> PackedByteArray:
	var bytes := PackedByteArray()
	while pipe.is_open():
		var chunk := pipe.get_buffer(65536)
		if chunk.is_empty():
			break
		bytes.append_array(chunk)
	pipe.close()
	return bytes


## Full argv for `git <args>` in repo_root; quotePath off so non-ASCII paths come out as UTF-8, not "\304\215" escapes.
static func argv(repo_root: String, args: Array) -> PackedStringArray:
	var full_args := PackedStringArray(["-C", repo_root, "-c", "core.quotePath=false"])
	# Per-invocation config: do not copy an executable shell command out of a
	# repository's core.sshCommand into the entire editor environment.
	# Explicit user GIT_SSH_COMMAND remains Git's higher-priority override.
	full_args.append_array(["-c", "core.sshCommand=ssh -o BatchMode=yes", "-c", "ssh.variant=ssh"])
	full_args.append_array(PackedStringArray(args))
	return full_args


## Undoes git's C-style quoting of a path ("a b.txt" in status, "q\"x.txt" everywhere); unquoted paths pass through.
static func unquote(path: String) -> String:
	if path.length() >= 2 and path.begins_with("\"") and path.ends_with("\""):
		return path.substr(1, path.length() - 2).c_unescape()
	return path


static func record(args: Array, exit_code: int, text: String, diagnostic_title := "") -> int:
	var entry := {
		"time": int(Time.get_unix_time_from_system()),
		"args": PackedStringArray(args),
		"exit_code": exit_code,
		"text": text,
	}
	_log_mutex.lock()
	entry["id"] = _command_log_revision + 1
	entry["diagnostic_title"] = diagnostic_title
	_command_log.append(entry)
	if _command_log.size() > LOG_LIMIT:
		_command_log = _command_log.slice(_command_log.size() - LOG_LIMIT)
	_command_log_revision += 1
	var id: int = entry["id"]
	_log_mutex.unlock()
	return id


## Atomic detached snapshot; the UI never iterates a worker-owned Array.
static func log_snapshot(previous_revision := -1) -> Dictionary:
	_log_mutex.lock()
	var snapshot := {} if previous_revision == _command_log_revision else {"revision": _command_log_revision, "entries": _command_log.duplicate(true)}
	_log_mutex.unlock()
	return snapshot


static func clear_log() -> void:
	_log_mutex.lock()
	_command_log.clear()
	_command_log_revision += 1
	_log_mutex.unlock()


## Splits git output into non-empty lines.
static func lines(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for line in text.split("\n"):
		if not line.is_empty():
			result.append(line)
	return result


## Lines of --name-only style output, unquoted.
static func paths(text: String) -> PackedStringArray:
	var result := lines(text)
	for i in result.size():
		result[i] = unquote(result[i])
	return result


## Called by plugin.gd on enable; restore_environment() undoes prompt/editor variables on disable. SSH is configured only in argv(), never in the editor environment.
static func prepare_environment() -> void:
	_saved_env.clear()
	var overrides := ENV_OVERRIDES.duplicate()
	for key in overrides:
		_saved_env[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.set_environment(key, overrides[key])


static func restore_environment() -> void:
	for key in _saved_env:
		if _saved_env[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, _saved_env[key])
	_saved_env.clear()


## One background git process. Reads its output on a Thread (OS.execute_with_pipe) so it can be killed mid-way via cancel(); finished is emitted on the main thread.
class Job:
	extends RefCounted

	# Per instance, built on the main thread: a static var here was still null on the worker thread in the editor, killing _run() so finished never fired.
	var _progress_re := RegEx.create_from_string("^(remote: )?[A-Za-z ]+:\\s+\\d+% \\(")
	## Everything --progress adds on top of the meters themselves.
	var _progress_noise_re := RegEx.create_from_string("^(remote: )?([A-Za-z ]+:\\s+\\d+% \\(|Enumerating objects: \\d+, done|Delta compression using|Total \\d+ \\(delta)")

	signal finished(result: Dictionary)
	## Latest progress line from git's stderr ("Receiving objects:  45% (9/20)"), for commands run with --progress.
	signal progress(text: String)

	var _argv: PackedStringArray
	var is_running := false
	var _thread: Thread
	var _pid := -1
	var _cancelled := false
	var _abandoned := false
	## Guards _pid/_cancelled: cancel() can arrive before the worker has the pid.
	var _mutex := Mutex.new()


	func start(full_argv: PackedStringArray) -> void:
		_argv = full_argv
		is_running = true
		_thread = Thread.new()
		_thread.start(_run)


	func cancel() -> void:
		_mutex.lock()
		if is_running and not _cancelled:
			_cancelled = true
			if _pid > 0:
				_kill_tree(_pid)
		_mutex.unlock()


	## Git's helpers (ssh, git-remote-https) inherit its pipes, so killing git alone would leave _drain() blocked until they exit on their own.
	static func _kill_tree(pid: int) -> void:
		if OS.get_name() == "Windows":
			OS.execute("taskkill", ["/T", "/F", "/PID", str(pid)])
			return
		var descendants := PackedStringArray()
		var queue := [pid]
		while not queue.is_empty():
			var out := []
			OS.execute("pgrep", ["-P", str(queue.pop_back())], out)
			for child in String(out[0]).split("\n", false):
				descendants.append(child.strip_edges())
				queue.append(child.to_int())
		OS.kill(pid)
		if not descendants.is_empty():
			OS.execute("kill", PackedStringArray(["-KILL"]) + descendants)


	## Cancels and blocks until the worker thread is done; finished is never emitted afterwards.
	func abandon() -> void:
		_abandoned = true
		cancel()
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
		is_running = false


	func _run() -> void:
		var info := OS.execute_with_pipe("git", _argv, true)
		if info.is_empty():
			_finish.call_deferred({ "exit_code": -1, "text": "Couldn't start `git` — is it on PATH?", "cancelled": false })
			return

		_mutex.lock()
		_pid = info["pid"]
		if _cancelled:
			_kill_tree(_pid)
		_mutex.unlock()
		var stdio: FileAccess = info["stdio"]
		var stderr: FileAccess = info["stderr"]
		# Both pipes drained at once, so neither can fill up and stall git; stderr here, since that's where progress arrives.
		var out_thread := Thread.new()
		out_thread.start(_drain.bind(stdio, false))
		var err := _strip_progress(_drain(stderr, true))
		var out: String = out_thread.wait_to_finish()
		if _cancelled:
			# OS.kill() already reaped the process — querying it again would only log "process does not exist".
			_finish.call_deferred({ "exit_code": -1, "text": "Cancelled.", "cancelled": true })
			return
		while OS.is_process_running(_pid):
			OS.delay_msec(5)
		var exit_code := OS.get_process_exit_code(_pid)
		var text := out + ("\n" if not out.is_empty() and not err.is_empty() else "") + err
		_finish.call_deferred({ "exit_code": exit_code, "text": text, "cancelled": false })


	## Reads until EOF. The pipe is blocking, so an empty read only happens once git has closed its end — a short read isn't EOF, and get_error() flags those too, so it can't be used here.
	func _drain(pipe: FileAccess, report_progress: bool) -> String:
		var bytes := PackedByteArray()
		var last_progress := ""
		while pipe.is_open():
			var chunk := pipe.get_buffer(4096)
			if chunk.is_empty():
				break
			bytes.append_array(chunk)
			if report_progress:
				var line := _last_progress_line(bytes)
				if line != last_progress:
					last_progress = line
					_emit_progress.call_deferred(line)
		pipe.close()
		return bytes.get_string_from_utf8()


	## Progress lines are rewritten in place with \r; only the tail is decoded (ASCII) since a chunk may end mid-UTF-8.
	func _last_progress_line(bytes: PackedByteArray) -> String:
		var tail := bytes.slice(maxi(0, bytes.size() - 256)).get_string_from_ascii()
		var pieces := tail.replace("\r", "\n").split("\n", false)
		for i in range(pieces.size() - 1, -1, -1):
			var piece := pieces[i].strip_edges()
			if _progress_re.search(piece) != null:
				return piece.trim_prefix("remote: ").trim_suffix(", done.")
		return ""


	## Drops the progress meter lines --progress adds, so the text (errors, Git Console) reads as it did without it.
	func _strip_progress(text: String) -> String:
		var kept := PackedStringArray()
		for line in text.split("\n"):
			var pieces := line.split("\r", false)
			var last := pieces[pieces.size() - 1] if not pieces.is_empty() else ""
			if _progress_noise_re.search(last) == null:
				kept.append(last)
		return "\n".join(kept)


	func _emit_progress(text: String) -> void:
		if not _abandoned and is_running:
			progress.emit(text)


	func _finish(result: Dictionary) -> void:
		if _abandoned:
			return
		_thread.wait_to_finish()
		is_running = false
		finished.emit(result)
