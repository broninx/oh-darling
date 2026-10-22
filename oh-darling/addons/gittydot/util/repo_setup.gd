## Turns a project without git into a repo: `git init`, Godot's ignore/attributes files, first commit, optional GitHub publish.
## No class_name: internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const GitCli := preload("res://addons/gittydot/util/git_cli.gd")
const PLUGIN_PATH := "res://addons/gittydot/plugin.cfg"

## Same lines Godot's project manager writes for a new project with "Version control metadata: Git".
const GITIGNORE_LINES := [".godot/", "/android/", "/*-temp-chatgpt/"]
const GITATTRIBUTES_LINES := ["* text=auto eol=lf"]
## Binary assets worth keeping out of the regular history once they add up.
const LFS_PATTERNS := ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.exr", "*.hdr", "*.psd", "*.wav", "*.ogg", "*.mp3",
		"*.glb", "*.fbx", "*.blend", "*.obj", "*.ttf", "*.otf", "*.mp4", "*.ogv"]
## GUI apps on macOS don't always get the shell's PATH.
const MACOS_GH_DIRECTORIES := ["/opt/homebrew/bin", "/usr/local/bin"]


static func git_available() -> bool:
	return OS.execute("git", ["--version"], [], false, false) == 0


static func lfs_available() -> bool:
	return OS.execute("git", ["lfs", "version"], [], false, false) == 0


## Path of a logged-in GitHub CLI, or "". Coroutine: `gh auth status` asks the network, so it runs on a thread.
static func find_gh() -> String:
	for candidate in gh_candidates(OS.get_name(), OS.get_environment("PATH")):
		var run := _ProgramRun.new()
		run.start(candidate, ["auth", "status"])
		var result: Dictionary = await run.finished
		if result["exit_code"] == 0:
			return candidate
	return ""


## Optional CLI discovery must not launch missing programs (Godot logs an error).
## Resolve PATH directly, without a shell, keeping paths with spaces intact.
static func gh_candidates(platform: String, search_path: String) -> PackedStringArray:
	var directories := Array(search_path.split(";" if platform == "Windows" else ":", false))
	if platform == "macOS":
		directories.append_array(MACOS_GH_DIRECTORIES)
	var result := PackedStringArray()
	for directory: String in directories:
		var folder := directory.strip_edges().trim_prefix("\"").trim_suffix("\"")
		if folder.is_empty():
			continue
		var candidate := folder.path_join("gh.exe" if platform == "Windows" else "gh").simplify_path()
		if FileAccess.file_exists(candidate) and not result.has(candidate):
			result.append(candidate)
	return result


## True if git has a user.name and user.email to commit with.
static func has_identity(root: String) -> bool:
	return not GitCli.run(root, ["config", "user.name"])["text"].strip_edges().is_empty() \
			and not GitCli.run(root, ["config", "user.email"])["text"].strip_edges().is_empty()


## options: {"lfs": bool, "commit": bool, "name": String, "email": String (both only set when git has no identity yet)} -> {"ok", "error"}. Coroutine: staging and the first commit of a big project run in the background.
static func init_repo(root: String, options: Dictionary) -> Dictionary:
	var r := GitCli.run(root, ["init"], true)
	if r["exit_code"] != 0:
		return { "ok": false, "error": r["text"].strip_edges() }
	_append_missing_lines(root.path_join(".gitignore"), GITIGNORE_LINES)
	var attributes: Array = GITATTRIBUTES_LINES.duplicate()
	if options.get("lfs", false):
		GitCli.run(root, ["lfs", "install", "--local"], true)
		for pattern in LFS_PATTERNS:
			attributes.append("%s filter=lfs diff=lfs merge=lfs -text" % pattern)
	_append_missing_lines(root.path_join(".gitattributes"), attributes)
	if not String(options.get("name", "")).is_empty():
		GitCli.run(root, ["config", "user.name", options["name"]], true)
	if not String(options.get("email", "")).is_empty():
		GitCli.run(root, ["config", "user.email", options["email"]], true)
	if options.get("commit", true):
		r = await GitCli.start(root, ["add", "-A"]).finished
		if r["exit_code"] == 0:
			r = await GitCli.start(root, ["commit", "-m", "Initial commit"]).finished
		if r["exit_code"] != 0:
			return { "ok": false, "error": "The repository was created, but the first commit failed:\n" + r["text"].strip_edges() }
	return { "ok": true, "error": "" }


## Creates a GitHub repo from root with the gh CLI and pushes to it. Coroutine: gh talks to the network, so it runs on a thread.
static func publish_to_github(gh: String, root: String, repo_name: String, private: bool) -> Dictionary:
	var run := _ProgramRun.new()
	run.start(gh, ["repo", "create", repo_name, "--private" if private else "--public", "--source=" + root, "--remote=origin", "--push"])
	var result: Dictionary = await run.finished
	GitCli.record(["(gh) repo", "create", repo_name], result["exit_code"], result["text"])
	return { "ok": result["exit_code"] == 0, "error": result["text"].strip_edges() }


## A GitHub-safe name from the project's name ("My Game!" -> "My-Game").
static func suggested_repo_name() -> String:
	var name := String(ProjectSettings.get_setting("application/config/name", "godot-project")).strip_edges()
	var safe := ""
	for c in name:
		safe += c if c.is_valid_identifier() or c.is_valid_int() or c in "-." else "-"
	while safe.contains("--"):
		safe = safe.replace("--", "-")
	safe = safe.trim_prefix("-").trim_suffix("-")
	return safe if not safe.is_empty() else "godot-project"


## Re-enables the plugin, so both docks open the new repo.
static func reload_plugin() -> void:
	EditorInterface.set_plugin_enabled.call_deferred(PLUGIN_PATH, false)
	EditorInterface.set_plugin_enabled.call_deferred(PLUGIN_PATH, true)


static func _append_missing_lines(path: String, wanted: Array) -> void:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var existing := Array(text.split("\n")).map(func(l: String) -> String: return l.strip_edges())
	var missing := wanted.filter(func(l: String) -> bool: return not existing.has(l))
	if missing.is_empty():
		return
	if not text.is_empty() and not text.ends_with("\n"):
		text += "\n"
	text += "\n".join(missing) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## Runs a non-git program on a thread; finished carries {"exit_code", "text"} (stderr included).
class _ProgramRun:
	extends RefCounted

	signal finished(result: Dictionary)

	var _thread := Thread.new()


	func start(program: String, args: Array) -> void:
		_thread.start(func() -> void:
			var r := GitCli.execute(program, PackedStringArray(args))
			_done.call_deferred(r["exit_code"], (r["out"] + r["err"]).get_string_from_utf8())
		)


	func _done(code: int, text: String) -> void:
		_thread.wait_to_finish()
		finished.emit({ "exit_code": code, "text": text })
