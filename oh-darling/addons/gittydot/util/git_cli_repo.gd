## Runs every git operation by shelling out to the system `git` binary (see
## util/git_cli.gd) — no native extension, works anywhere `git` is on PATH.
## Status is encoded as GitStatusFlags' bitmask and GitIcons' DELTA_* codes,
## same as the rest of the addon expects. No class_name: internal helper,
## addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const GitCli := preload("res://addons/gittydot/util/git_cli.gd")
const GitStatusFlags := preload("res://addons/gittydot/util/git_status_flags.gd")
const GitIcons := preload("res://addons/gittydot/util/git_icons.gd")
const ChangelistStore := preload("res://addons/gittydot/util/changelist_store.gd")

const US := GitCli.US

## Porcelain XY codes for unmerged paths (both sides touched the file, or one deleted what the other changed).
const CONFLICT_CODES := ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

## No optional locks: a poll mustn't hold index.lock while the user runs git in a terminal.
const STATUS_ARGS := ["--no-optional-locks", "status", "--porcelain=v1", "--branch", "--untracked-files=all"]
const REFS_ARGS := ["for-each-ref", "--format=%(refname) %(objectname)"]

var _repo_root: String = ""
## "## branch...upstream [ahead n, behind m]" line from the last get_status().
var status_header := ""


func open(path: String) -> bool:
	var result := GitCli.run(path, ["rev-parse", "--show-toplevel"])
	if result["exit_code"] != 0:
		return false
	var root: String = result["text"].strip_edges()
	if root.is_empty():
		return false
	_repo_root = _in_callers_spelling(path, root)
	return true


## git resolves symlinks, Godot's paths don't — so a project reached through one would never match the repo root textually. The root is rebuilt from the caller's path minus its folder inside the repo.
static func _in_callers_spelling(path: String, git_root: String) -> String:
	var prefix: String = GitCli.run(path, ["rev-parse", "--show-prefix"])["text"].strip_edges().trim_suffix("/")
	var trimmed := path.trim_suffix("/")
	if prefix.is_empty():
		return trimmed # the path is the repo root itself
	if trimmed.ends_with("/" + prefix):
		return trimmed.trim_suffix("/" + prefix)
	return git_root


func is_valid() -> bool:
	return not _repo_root.is_empty()


func get_repo_root() -> String:
	return _repo_root


func get_status() -> Array:
	return parse_status(GitCli.run(_repo_root, STATUS_ARGS)["text"])


## Entries from STATUS_ARGS output (e.g. a RepoWatcher snapshot's "status"); also sets status_header.
func parse_status(text: String) -> Array:
	var entries: Array = []
	status_header = ""
	for line in GitCli.lines(text):
		if line.begins_with("## "):
			status_header = line
			continue
		if line.length() < 4:
			continue
		var xy := line.substr(0, 2)
		var rest := line.substr(3)
		var path := GitCli.unquote(rest)
		var renamed_from := ""
		var arrow := rest.find(" -> ") if "R" in xy or "C" in xy else -1 # a file name may contain " -> " too
		if arrow != -1:
			renamed_from = GitCli.unquote(rest.substr(0, arrow))
			path = GitCli.unquote(rest.substr(arrow + 4))
		entries.append({
			"path": path,
			"status": _status_bits(xy),
			"renamed_from": renamed_from,
		})
	return entries


## Maps porcelain v1's two-letter XY status into GitStatusFlags' bitmask.
func _status_bits(xy: String) -> int:
	if xy == "??":
		return GitStatusFlags.WT_NEW
	if xy in CONFLICT_CODES:
		return GitStatusFlags.CONFLICTED | GitStatusFlags.WT_MODIFIED
	var bits := 0
	match xy[0]:
		"M": bits |= GitStatusFlags.INDEX_MODIFIED
		"A": bits |= GitStatusFlags.INDEX_NEW
		"D": bits |= GitStatusFlags.INDEX_DELETED
		"R": bits |= GitStatusFlags.INDEX_RENAMED
		"C": bits |= GitStatusFlags.INDEX_RENAMED
		"T": bits |= GitStatusFlags.INDEX_TYPECHANGE
		"U": bits |= GitStatusFlags.CONFLICTED | GitStatusFlags.INDEX_MODIFIED
	match xy[1]:
		"M": bits |= GitStatusFlags.WT_MODIFIED
		"D": bits |= GitStatusFlags.WT_DELETED
		"R": bits |= GitStatusFlags.WT_RENAMED
		"C": bits |= GitStatusFlags.WT_RENAMED
		"T": bits |= GitStatusFlags.WT_TYPECHANGE
		"U": bits |= GitStatusFlags.CONFLICTED | GitStatusFlags.WT_MODIFIED
	return bits


## options: {"context": int (lines of context, -1 = whole file), "ignore_whitespace": bool}.
func get_diff(path: String, staged: bool, options: Dictionary = {}) -> String:
	var flags := _diff_flags(options)
	if staged:
		return GitCli.run(_repo_root, ["diff", "--cached"] + flags + ["--", path])["text"]

	# Plain `git diff` shows nothing for an untracked file; diffing against
	# /dev/null renders it as a full-file addition instead.
	if is_untracked(path):
		return GitCli.run(_repo_root, ["diff", "--no-index"] + flags + ["--", "/dev/null", path])["text"]

	return GitCli.run(_repo_root, ["diff"] + flags + ["--", path])["text"]


## For a conflicted file: its working-tree content (with conflict markers) against "ours".
func get_conflict_diff(path: String) -> String:
	return GitCli.run(_repo_root, ["diff", "--ours", "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "--", path])["text"]


func is_untracked(path: String) -> bool:
	var status_result := GitCli.run(_repo_root, ["status", "--porcelain=v1", "--", path])
	return status_result["text"].strip_edges().begins_with("??")


static func _diff_flags(options: Dictionary) -> Array:
	# Fixed prefixes: diff.noprefix / diff.mnemonicPrefix in the user's config would break `git apply` and the header parsing.
	var flags: Array = ["--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/"]
	var context: int = options.get("context", 3)
	flags.append("--unified=%d" % (context if context >= 0 else 1000000))
	if options.get("ignore_whitespace", false):
		flags.append("--ignore-all-space")
	return flags


## Files that differ between two revisions; target "" = the working tree. Same shape as get_commit_files().
func get_changed_files_between(base: String, target: String) -> Array:
	var args := ["diff", "--name-status", "-M", base]
	if not target.is_empty():
		args.append(target)
	return _parse_name_status(GitCli.run(_repo_root, args)["text"])


## Diff of one file between two revisions; target "" = the working tree.
func get_diff_between(base: String, target: String, path: String, options: Dictionary = {}) -> String:
	var args := ["diff"] + _diff_flags(options) + [base]
	if not target.is_empty():
		args.append(target)
	args.append_array(["--", path])
	return GitCli.run(_repo_root, args)["text"]


## One file's changes in a single commit (against its first parent, or the empty tree for a root commit).
func get_commit_file_diff(oid: String, path: String, options: Dictionary = {}) -> String:
	var args := ["show", "--format=", "-M", "--first-parent"] + _diff_flags(options) + [oid, "--", path]
	return GitCli.run(_repo_root, args)["text"]


## Raw bytes of path at rev ("" = the file on disk, ":" = the index); empty if it doesn't exist there. For image previews.
func get_file_bytes(rev: String, path: String) -> PackedByteArray:
	if rev.is_empty():
		var abs_path := _repo_root.path_join(path)
		return FileAccess.get_file_as_bytes(abs_path) if FileAccess.file_exists(abs_path) else PackedByteArray()
	# rev ":" means the index (":path" in git's syntax).
	var spec := ":" + path if rev == ":" else "%s:%s" % [rev, path]
	if GitCli.run(_repo_root, ["cat-file", "-e", spec])["exit_code"] != 0:
		return PackedByteArray()
	return GitCli.run_bytes(_repo_root, ["cat-file", "blob", spec])


## path's text in HEAD for the script editor gutter: "" for an untracked or newly added file (all of it counts as added), null when there's nothing to compare against (ignored, renamed).
func get_head_text(path: String) -> Variant:
	var shown := GitCli.run(_repo_root, ["show", "HEAD:" + path], false)
	if shown["exit_code"] == 0:
		return shown["text"]
	var status: String = GitCli.run(_repo_root, ["status", "--porcelain=v1", "--", path])["text"].strip_edges()
	if status.begins_with("??") or status.begins_with("A"):
		return ""
	return null


## Zero-context diff between two texts (e.g. HEAD and the editor's unsaved buffer), for DiffHunks.parse_regions().
func diff_texts(old_text: String, new_text: String) -> String:
	var stamp := Time.get_ticks_usec()
	var old_path := _temp_dir().path_join("godit_old_%d.tmp" % stamp)
	var new_path := _temp_dir().path_join("godit_new_%d.tmp" % stamp)
	for pair in [[old_path, old_text], [new_path, new_text]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		if f == null:
			DirAccess.remove_absolute(old_path)
			return ""
		f.store_string(pair[1])
		f.close()
	var r := GitCli.run(_repo_root, ["diff", "--no-index", "--no-color", "-U0", "--", old_path, new_path])
	DirAccess.remove_absolute(old_path)
	DirAccess.remove_absolute(new_path)
	return r["text"]


## Applies a patch built by DiffHunks.build_patch(). cached=true targets the index (stage/unstage), false the working tree (revert); reverse undoes the patch instead of applying it. --recount means partial-hunk patches needn't have exact line counts in their headers.
func apply_patch(patch: String, cached: bool, reverse: bool, check_only := false) -> Dictionary:
	var patch_path := _temp_dir().path_join("godit_patch_%d.patch" % Time.get_ticks_usec())
	var patch_file := FileAccess.open(patch_path, FileAccess.WRITE)
	if patch_file == null:
		return { "ok": false, "error": "couldn't write a temp patch file at %s" % patch_path, "output": "" }
	patch_file.store_string(patch)
	patch_file.close()

	var args := ["apply", "--recount", "--whitespace=nowarn"]
	if cached:
		args.append("--cached")
	if reverse:
		args.append("--reverse")
	if check_only:
		args.append("--check")
	args.append(patch_path)
	var result := _simple(args)
	DirAccess.remove_absolute(patch_path)
	return result


## Discards a staged hunk (patch from the staged diff) from both the index and the working tree; checks both first so a failure leaves nothing half-reverted.
func discard_staged_patch(patch: String) -> Dictionary:
	var worktree_check := apply_patch(patch, false, true, true)
	if not worktree_check["ok"]:
		return { "ok": false, "output": "", "error": "The working tree has further changes on these lines — revert or stage those first.\n\n" + worktree_check["error"] }
	var index_check := apply_patch(patch, true, true, true)
	if not index_check["ok"]:
		return index_check
	var result := apply_patch(patch, false, true)
	if not result["ok"]:
		return result
	return apply_patch(patch, true, true)


## Overwrites path in the working tree with its content at rev (deleting it if it didn't exist there). The index is left alone, so it shows up as an ordinary unstaged change.
func restore_file_from(rev: String, path: String) -> Dictionary:
	if GitCli.run(_repo_root, ["cat-file", "-e", "%s:%s" % [rev, path]])["exit_code"] != 0:
		var abs_path := _repo_root.path_join(path)
		if FileAccess.file_exists(abs_path) and DirAccess.remove_absolute(abs_path) != OK:
			return { "ok": false, "error": "couldn't delete %s" % path, "output": "" }
		return { "ok": true, "error": "", "output": "" }
	return _simple(["restore", "--source=" + rev, "--worktree", "--", path])


## Stages many paths in one `git add` (adding new files one by one is slow in big folders).
func stage_files(paths: Array) -> Dictionary:
	if paths.is_empty():
		return { "ok": true, "error": "", "output": "" }
	return _simple(["add", "--"] + paths)


func stage_file(path: String) -> bool:
	# `rm --cached` is the fallback for whatever `add` doesn't cover.
	if GitCli.run(_repo_root, ["add", "--", path])["exit_code"] == 0:
		return true
	return GitCli.run(_repo_root, ["rm", "--cached", "--", path])["exit_code"] == 0


func unstage_file(path: String) -> bool:
	if GitCli.run(_repo_root, ["reset", "--", path])["exit_code"] == 0:
		return true
	# Unborn branch, no HEAD to reset to — just drop it from the index.
	return GitCli.run(_repo_root, ["rm", "--cached", "--", path])["exit_code"] == 0


## Discards uncommitted changes to path. Restores from HEAD if committed,
## otherwise deletes it (nothing to restore to).
func revert_file(path: String) -> Dictionary:
	var result := { "ok": false, "error": "" }

	if GitCli.run(_repo_root, ["cat-file", "-e", "HEAD:" + path])["exit_code"] == 0:
		var checkout_result := GitCli.run(_repo_root, ["checkout", "HEAD", "--", path], true)
		if checkout_result["exit_code"] != 0:
			result["error"] = checkout_result["text"].strip_edges()
			return result
		result["ok"] = true
		return result

	var renamed_from := _staged_rename_source(path)
	GitCli.run(_repo_root, ["rm", "-f", "--cached", "--", path], true) # ok if not staged
	var abs_path := _repo_root.path_join(path)
	if FileAccess.file_exists(abs_path):
		var dir := DirAccess.open(_repo_root)
		if dir == null or dir.remove(abs_path) != OK:
			result["error"] = "couldn't delete %s from disk" % path
			return result
	if not renamed_from.is_empty():
		# Undoing a staged rename brings the old file back too, or its content would be gone from disk.
		var restore_result := GitCli.run(_repo_root, ["checkout", "HEAD", "--", renamed_from], true)
		if restore_result["exit_code"] != 0:
			result["error"] = restore_result["text"].strip_edges()
			return result
	result["ok"] = true
	return result


## The path path was staged as a rename of, or "".
func _staged_rename_source(path: String) -> String:
	for entry in _parse_name_status(GitCli.run(_repo_root, ["diff", "--cached", "--name-status", "-M"])["text"]):
		if entry["path"] == path and entry["status"] == GitIcons.DELTA_RENAMED:
			return entry["old_path"]
	return ""


## Deletes path from disk and stages the removal (`git rm -f`) in one step —
## unlike revert_file(), which restores the file instead of removing it.
func remove_file(path: String) -> Dictionary:
	var result := { "ok": false, "error": "" }
	var rm_result := GitCli.run(_repo_root, ["rm", "-f", "--", path], true)
	if rm_result["exit_code"] != 0:
		result["error"] = rm_result["text"].strip_edges()
		return result
	result["ok"] = true
	return result


func commit(message: String, amend: bool = false) -> Dictionary:
	var result := { "ok": false, "oid": "", "error": "" }
	var args := ["commit", "-m", message]
	if amend:
		args.append("--amend")
	var commit_result := GitCli.run(_repo_root, args, true)
	if commit_result["exit_code"] != 0:
		result["error"] = commit_result["text"].strip_edges()
		return result

	result["ok"] = true
	result["oid"] = GitCli.run(_repo_root, ["rev-parse", "HEAD"])["text"].strip_edges()
	return result


func get_head_info() -> Dictionary:
	var fmt := "%H" + GitCli.US + "%B" + GitCli.US + "%an" + GitCli.US + "%ae" + GitCli.US + "%at"
	var result := GitCli.run(_repo_root, ["log", "-1", "--format=" + fmt])
	if result["exit_code"] != 0:
		return {} # unborn branch, no commits yet

	var text: String = result["text"]
	var fields := text.split(GitCli.US)
	if fields.size() < 5:
		return {}
	return {
		"oid": fields[0],
		"message": fields[1],
		"author_name": fields[2],
		"author_email": fields[3],
		"time": int(fields[4].strip_edges()),
	}


func git_version_text() -> String:
	var r := GitCli.execute("git", PackedStringArray(["--version"]))
	return r["out"].get_string_from_utf8().strip_edges() if r["exit_code"] == 0 else "unknown"


## GittyDot's compatibility floor for rewriting a selected older commit.
static func selected_amend_version_supported(text: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^git version ([0-9]+)\\.([0-9]+)\\.([0-9]+)(.*)$")
	var found := regex.search(text.strip_edges())
	if found == null:
		return false
	var major := found.get_string(1).to_int()
	var minor := found.get_string(2).to_int()
	var patch := found.get_string(3).to_int()
	if major > 2 or (major == 2 and minor > 45):
		return true
	return major == 2 and minor == 45 and (patch > 0 or not (found.get_string(4).begins_with("-rc") or found.get_string(4).begins_with(".rc")))


## Pure preflight: no helper commit, index change or working-tree rewrite on failure.
func check_amend_target(oid: String) -> Dictionary:
	var head := get_head_oid()
	var target := head if oid.is_empty() else oid
	var error := ""
	if target.length() not in [40, 64] or not target.is_valid_hex_number():
		error = "Select an existing commit to amend."
	elif get_current_branch().is_empty():
		error = "Check out a branch before amending a selected commit."
	elif not get_operation_state()["kind"].is_empty():
		error = "Finish or abort the current Git operation before amending a commit."
	elif not is_ancestor_of_head(target):
		error = "The selected commit is no longer in the current branch's history. Select it again in Git Log."
	elif target != head:
		var version := git_version_text()
		if not selected_amend_version_supported(version):
			error = "Amending a specific older commit requires Git 2.45.0 or newer in GittyDot. Detected: %s." % version
		elif has_merges_since(target) or GitCli.run(_repo_root, ["rev-list", "--parents", "-n", "1", target])["text"].strip_edges().split(" ").size() > 2:
			error = "This amendment would replay a merge commit. Choose a commit after the merge."
	return {"ok": error.is_empty(), "error": error, "output": "", "oid": target}


## Fold staged changes and a replacement message into exactly this commit.
## Newer commits are replayed; the full hash avoids ambiguous duplicate subjects.
func amend_commit(oid: String, message: String) -> Dictionary:
	var checked := check_amend_target(oid)
	if not checked["ok"]:
		return checked
	if message.strip_edges().is_empty():
		return {"ok": false, "error": "Commit message can't be empty.", "output": "", "oid": ""}
	var target: String = checked["oid"]
	if target == get_head_oid():
		return commit(message, true)
	var original := get_head_oid()
	# A normal commit preserves hooks/signing; autosquash uses its body as the
	# replacement message, just like an amend! helper produced by --fixup=amend:.
	var made := _simple(["commit", "--allow-empty", "-m", "amend! " + target + "\n\n" + message])
	if not made["ok"]:
		return made
	var journal := FileAccess.open(_amend_recovery_path(), FileAccess.WRITE)
	if journal == null:
		var rollback := _simple(["reset", "--soft", original])
		return {"ok": false, "error": "Couldn't save amendment recovery information." + ("\n" + rollback["error"] if not rollback["ok"] else " Staged changes were restored."), "output": "", "oid": ""}
	journal.store_string(JSON.stringify({"original": original, "helper": get_head_oid(), "branch": get_current_branch()}))
	journal.close()
	var result := _autosquash_onto(target, original)
	if not result.get("conflicts", false):
		_clear_amend_recovery()
	result["oid"] = get_head_oid() if result["ok"] else ""
	return result


func _amend_recovery_path() -> String:
	return get_git_dir().path_join("gittydot-amend-recovery.json")


func _clear_amend_recovery() -> void:
	if FileAccess.file_exists(_amend_recovery_path()):
		DirAccess.remove_absolute(_amend_recovery_path())


func _after_rebase_step(result: Dictionary) -> Dictionary:
	if get_operation_state()["kind"].is_empty():
		_clear_amend_recovery()
	return _with_conflict_flag(result)


## Array[{name, is_head, is_remote, track ("[ahead 2, behind 1]" or ""), upstream, ahead, behind, gone, oid, summary, date (relative)}].
func list_branches(local_only: bool = true) -> Array:
	var patterns := ["refs/heads"]
	if not local_only:
		patterns.append("refs/remotes")
	var fmt := US.join(["%(refname)", "%(HEAD)", "%(upstream:track)", "%(upstream:short)",
			"%(objectname:short)", "%(contents:subject)", "%(committerdate:relative)"])
	var args := ["for-each-ref", "--format=" + fmt]
	args.append_array(patterns)
	var result := GitCli.run(_repo_root, args)

	var entries: Array = []
	for line in GitCli.lines(result["text"]):
		var fields := line.split(US)
		if fields.size() < 7:
			continue
		var refname: String = fields[0]
		if refname.ends_with("/HEAD"):
			continue # refs/remotes/origin/HEAD isn't a real branch
		var is_remote := refname.begins_with("refs/remotes/")
		var short_name := refname.trim_prefix("refs/remotes/" if is_remote else "refs/heads/")
		var track: String = fields[2]
		entries.append({
			"name": short_name,
			"is_head": fields[1].strip_edges() == "*",
			"is_remote": is_remote,
			"track": track,
			"upstream": fields[3],
			"ahead": _track_count(track, "ahead"),
			"behind": _track_count(track, "behind"),
			"gone": track.contains("gone"),
			"oid": fields[4],
			"summary": fields[5],
			"date": fields[6],
		})
	return entries


static func _track_count(track: String, word: String) -> int:
	var at := track.find(word + " ")
	if at == -1:
		return 0
	return track.substr(at + word.length() + 1).to_int()


## Array[{"name", "oid", "summary", "annotated"}], newest first.
func list_tags() -> Array:
	var fmt := US.join(["%(refname:short)", "%(objectname:short)", "%(*objectname:short)", "%(contents:subject)", "%(objecttype)"])
	var r := GitCli.run(_repo_root, ["for-each-ref", "--sort=-creatordate", "--format=" + fmt, "refs/tags"])
	var tags: Array = []
	for line in GitCli.lines(r["text"]):
		var f := line.split(US)
		if f.size() < 5:
			continue
		tags.append({
			"name": f[0],
			"oid": f[2] if not f[2].is_empty() else f[1],
			"summary": f[3],
			"annotated": f[4] == "tag",
		})
	return tags


## message non-empty makes an annotated tag.
func create_tag(name: String, target: String, message: String = "") -> Dictionary:
	var args := ["tag"]
	if not message.is_empty():
		args.append_array(["-a", "-m", message])
	args.append_array([name, target if not target.is_empty() else "HEAD"])
	return _simple(args)


func delete_tag(name: String) -> Dictionary:
	return _simple(["tag", "-d", name])


## force=true deletes even if it isn't merged anywhere (-D).
func delete_branch(name: String, force: bool = false) -> Dictionary:
	return _simple(["branch", "-D" if force else "-d", name])


func rename_branch(old_name: String, new_name: String) -> Dictionary:
	return _simple(["branch", "-m", old_name, new_name])


## upstream "" unsets it.
func set_upstream(branch: String, upstream: String) -> Dictionary:
	if upstream.is_empty():
		return _simple(["branch", "--unset-upstream", branch])
	return _simple(["branch", "--set-upstream-to=" + upstream, branch])


## Checks out remote_branch ("origin/foo") as a local branch tracking it — or just switches to the local branch if one with that name already exists.
func checkout_remote_branch(remote_branch: String) -> Dictionary:
	var slash := remote_branch.find("/")
	var local_name := remote_branch.substr(slash + 1) if slash != -1 else remote_branch
	if GitCli.run(_repo_root, ["rev-parse", "--verify", "-q", "refs/heads/" + local_name])["exit_code"] == 0:
		return _checkout(local_name)
	return _simple(["checkout", "--track", "-b", local_name, remote_branch])


## Relays the running job's progress line ("Receiving objects:  45% (9/20)") for OperationBar.
signal job_progress(text: String)

## The background job currently running for this repo (fetch/pull/push...), or null. See cancel_current().
var current_job: RefCounted = null
## True while current_job is an automatic fetch nobody is waiting on — it doesn't count as busy, and gives way to any user operation.
var _current_job_is_auto := false


## Kills whatever network operation is in flight; its awaiting caller gets {"ok": false, "cancelled": true}.
func cancel_current() -> void:
	if current_job != null:
		current_job.cancel()


func is_busy() -> bool:
	return current_job != null and not _current_job_is_auto


## Runs git on a worker thread (see GitCli.start()). Coroutine — callers must await it. {"ok", "error", "output", "cancelled"}.
func _run_async(args: Array, auto := false) -> Dictionary:
	if current_job != null and _current_job_is_auto:
		var running: RefCounted = current_job
		running.cancel()
		await running.finished
	var job := GitCli.start(_repo_root, args)
	job.progress.connect(job_progress.emit)
	current_job = job
	_current_job_is_auto = auto
	var r: Dictionary = await job.finished
	if current_job == job:
		current_job = null
		_current_job_is_auto = false
	var text: String = String(r["text"]).strip_edges()
	return {
		"ok": r["exit_code"] == 0,
		"error": "" if r["exit_code"] == 0 else text,
		"output": text,
		"cancelled": r.get("cancelled", false),
	}


## Updates remote-tracking refs from remote_name, or every remote if empty.
## Doesn't touch any local branch or the working tree — see pull() for that.
## Coroutine (runs in the background).
func fetch(remote_name: String = "", prune: bool = false) -> Dictionary:
	var args := ["fetch", "--progress", "--all"] if remote_name.is_empty() else ["fetch", "--progress", remote_name]
	if prune:
		args.append("--prune")
	args.append("--tags")
	return await _run_async(args)


## Periodic fetch of all remotes: skipped (returns {}) while anything else runs, and cancelled by any user operation. Coroutine.
func auto_fetch() -> Dictionary:
	if current_job != null or list_remotes().is_empty():
		return {}
	return await _run_async(["fetch", "--all", "--tags", "--quiet"], true)


## Fetches and integrates the upstream; strategy "" (git config), "merge", "rebase" or "ff-only". Conflicts leave the repo mid-merge. Coroutine.
func pull(strategy: String = "", autostash: bool = false) -> Dictionary:
	var args := ["pull", "--progress"]
	match strategy:
		"merge": args.append("--no-rebase")
		"rebase": args.append("--rebase")
		"ff-only": args.append("--ff-only")
	if autostash:
		args.append("--autostash")
	return await _run_async(args)


## options (all optional): {"remote", "branch", "set_upstream", "force_with_lease", "tags"}; empty = plain `git push`. Coroutine.
func push(options: Dictionary = {}) -> Dictionary:
	var args := ["push", "--progress"]
	if options.get("set_upstream", false):
		args.append("--set-upstream")
	if options.get("force_with_lease", false):
		args.append("--force-with-lease")
	if options.get("tags", false):
		args.append("--follow-tags")
	var remote: String = options.get("remote", "")
	var branch: String = options.get("branch", "")
	if not remote.is_empty():
		args.append(remote)
		if not branch.is_empty():
			args.append(branch)
	return await _run_async(args)


## Pushes a single ref (tag or `:branch` deletion etc.) to remote. Coroutine.
func push_refspec(remote: String, refspec: String) -> Dictionary:
	return await _run_async(["push", "--progress", remote, refspec])


## Current branch's short name, or "" on a detached HEAD.
func get_current_branch() -> String:
	var r := GitCli.run(_repo_root, ["symbolic-ref", "--short", "-q", "HEAD"])
	return r["text"].strip_edges() if r["exit_code"] == 0 else ""


## Short name of branch's upstream (e.g. "origin/main"), or "" if it has none. Empty branch = current.
func get_upstream(branch: String = "") -> String:
	var r := GitCli.run(_repo_root, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", branch + "@{upstream}"])
	return r["text"].strip_edges() if r["exit_code"] == 0 else ""


## {"branch", "upstream", "ahead", "behind"} for the current HEAD; ahead/behind are 0 without an upstream.
func get_sync_status() -> Dictionary:
	var info := { "branch": get_current_branch(), "upstream": "", "ahead": 0, "behind": 0 }
	if info["branch"].is_empty():
		return info
	info["upstream"] = get_upstream()
	if info["upstream"].is_empty():
		return info
	var r := GitCli.run(_repo_root, ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
	var counts: PackedStringArray = r["text"].strip_edges().split("\t")
	if r["exit_code"] == 0 and counts.size() == 2:
		info["ahead"] = counts[0].to_int()
		info["behind"] = counts[1].to_int()
	return info


## "HEAD oid\nupstream oid" the incoming/outgoing file lists below were read for.
var _overlap_key := ""
var _incoming_files := {}
var _outgoing_files: Array = []


## Files the upstream changed since this branch forked off that are changed here too, so pulling may conflict:
## {path: "uncommitted" (one of local_paths) | "committed" (in an unpushed commit)}; empty when there's nothing to pull.
func incoming_overlap(local_paths: Array) -> Dictionary:
	var r := GitCli.run(_repo_root, ["rev-parse", "HEAD", "@{upstream}"])
	var oids := GitCli.lines(r["text"])
	if r["exit_code"] != 0 or oids.size() != 2 or oids[0] == oids[1]:
		return {}
	var key := "\n".join(oids)
	if key != _overlap_key:
		_overlap_key = key
		_incoming_files = {}
		for path in GitCli.paths(GitCli.run(_repo_root, ["diff", "--name-only", "HEAD...@{upstream}"])["text"]):
			_incoming_files[path] = true
		_outgoing_files = Array(GitCli.paths(GitCli.run(_repo_root, ["diff", "--name-only", "@{upstream}...HEAD"])["text"]))
	var overlap := {}
	for path in local_paths:
		if _incoming_files.has(path):
			overlap[path] = "uncommitted"
	for path in _outgoing_files:
		if _incoming_files.has(path) and not overlap.has(path):
			overlap[path] = "committed"
	return overlap


## Array[{"name", "fetch_url", "push_url"}].
func list_remotes() -> Array:
	var r := GitCli.run(_repo_root, ["remote", "-v"])
	var by_name := {}
	var order: Array = []
	for line in GitCli.lines(r["text"]):
		var parts := line.split("\t")
		if parts.size() < 2:
			continue
		var name := parts[0]
		var url_and_kind := parts[1].split(" ")
		if not by_name.has(name):
			by_name[name] = { "name": name, "fetch_url": "", "push_url": "" }
			order.append(name)
		if url_and_kind.size() > 1 and url_and_kind[1] == "(push)":
			by_name[name]["push_url"] = url_and_kind[0]
		else:
			by_name[name]["fetch_url"] = url_and_kind[0]
	var result: Array = []
	for name in order:
		result.append(by_name[name])
	return result


func add_remote(name: String, url: String) -> Dictionary:
	return _simple(["remote", "add", name, url])


func remove_remote(name: String) -> Dictionary:
	return _simple(["remote", "remove", name])


func rename_remote(old_name: String, new_name: String) -> Dictionary:
	return _simple(["remote", "rename", old_name, new_name])


func set_remote_url(name: String, url: String) -> Dictionary:
	return _simple(["remote", "set-url", name, url])


## Array[{"ref": "stash@{0}", "message", "date"}], newest first.
func list_stashes() -> Array:
	var r := GitCli.run(_repo_root, ["stash", "list", "--format=%gd" + US + "%gs" + US + "%cr"])
	var stashes: Array = []
	for line in GitCli.lines(r["text"]):
		var f := line.split(US)
		if f.size() < 3:
			continue
		stashes.append({ "ref": f[0], "message": f[1], "date": f[2] })
	return stashes


## Stashes as Git Log rows: [{"oid", "parents" (just the commit it was made on), "stash" (its stash@{n} ref), "summary", "message", "author_name", "author_email", "time"}], newest first.
func list_stash_commits() -> Array:
	var r := GitCli.run(_repo_root, ["stash", "list", "--format=%H" + US + "%P" + US + "%gd" + US + "%gs" + US + "%an" + US + "%ae" + US + "%at"])
	var stashes: Array = []
	for line in GitCli.lines(r["text"]):
		var f := line.split(US)
		if f.size() < 7:
			continue
		stashes.append({
			"oid": f[0], "parents": PackedStringArray([f[1].get_slice(" ", 0)]), "stash": f[2], "summary": f[3], "message": f[3],
			"author_name": f[4], "author_email": f[5], "time": f[6].to_int(), "refs": PackedStringArray(), "tags": PackedStringArray(),
		})
	return stashes


## Stashes uncommitted changes. paths empty = everything; include_untracked also stashes new files.
func stash_push(message: String, include_untracked: bool, paths: PackedStringArray = PackedStringArray(), keep_index: bool = false) -> Dictionary:
	var args := ["stash", "push"]
	if include_untracked:
		args.append("--include-untracked")
	if keep_index:
		args.append("--keep-index")
	if not message.is_empty():
		args.append_array(["-m", message])
	if not paths.is_empty():
		args.append("--")
		args.append_array(paths)
	var stashed: Array = Array(paths) if not paths.is_empty() else get_status().map(func(e: Dictionary) -> String: return e["path"])
	var result := _simple(args)
	if result["ok"] and not result["output"].contains("No local changes"):
		ChangelistStore.remember_shelved(_repo_root, _stash_oid("stash@{0}"), stashed)
	return result


func _stash_oid(ref: String) -> String:
	return GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", ref])["text"].strip_edges()


## pop=true also drops the stash if it applied cleanly. --index restores what was staged as staged.
func stash_apply(ref: String, pop: bool) -> Dictionary:
	var oid := _stash_oid(ref)
	var result := _simple(["stash", "pop" if pop else "apply", "--index", ref])
	if not result["ok"] and result["error"].contains("--index"):
		result = _simple(["stash", "pop" if pop else "apply", ref]) # index can't be restored (conflicts there) — apply to the working tree only
	result = _with_conflict_flag(result)
	if result["ok"] or result["conflicts"]:
		# A pop that stopped on conflicts keeps the stash, so its record stays too.
		ChangelistStore.restore_shelved(_repo_root, oid, pop and result["ok"])
	return result


func stash_drop(ref: String) -> Dictionary:
	var oid := _stash_oid(ref)
	var result := _simple(["stash", "drop", ref])
	if result["ok"]:
		ChangelistStore.forget_shelved(_repo_root, oid)
	return result


func stash_branch(branch: String, ref: String) -> Dictionary:
	var oid := _stash_oid(ref)
	var result := _simple(["stash", "branch", branch, ref])
	if result["ok"]:
		ChangelistStore.restore_shelved(_repo_root, oid, true)
	return result


## Runs a quick mutating command synchronously -> {"ok", "error", "output"}.
func _simple(args: Array) -> Dictionary:
	var r := GitCli.run(_repo_root, args, true)
	var text: String = r["text"].strip_edges()
	return { "ok": r["exit_code"] == 0, "error": "" if r["exit_code"] == 0 else text, "output": text }


## True when this repo uses git's built-in file system monitor (see set_fast_status()).
func is_fast_status_on() -> bool:
	return GitCli.run(_repo_root, ["config", "--local", "--bool", "--get", "core.fsmonitor"])["text"].strip_edges() == "true"


## Turns on git's built-in file system monitor plus the untracked cache in this repo's config, so `git status` asks a daemon what changed instead of scanning every file.
func set_fast_status(on: bool) -> Dictionary:
	if not on:
		GitCli.run(_repo_root, ["fsmonitor--daemon", "stop"])
		GitCli.run(_repo_root, ["config", "--local", "--unset", "core.untrackedCache"])
		return _simple(["config", "--local", "--unset", "core.fsmonitor"])
	if not fast_status_supported():
		return { "ok": false, "error": "Needs git 2.37 or newer on macOS or Windows.", "output": "" }
	var r := _simple(["config", "--local", "core.fsmonitor", "true"])
	if r["ok"]:
		r = _simple(["config", "--local", "core.untrackedCache", "true"])
	GitCli.run(_repo_root, ["status", "--porcelain"]) # starts the daemon and writes both into the index now, not on the next commit
	return r


## Older git reads core.fsmonitor=true as a hook to run, which would hide every change, so the version matters.
static func fast_status_supported() -> bool:
	if OS.get_name() not in ["macOS", "Windows"]:
		return false
	var r := GitCli.execute("git", PackedStringArray(["--version"]))
	var version: PackedStringArray = r["out"].get_string_from_utf8().get_slice("git version ", 1).split(".")
	return version.size() >= 2 and (version[0].to_int() > 2 or (version[0].to_int() == 2 and version[1].to_int() >= 37))


var _git_dir := ""


## Absolute .git directory (per-worktree for linked worktrees). Cached — it can't move while the repo is open.
func get_git_dir() -> String:
	if _git_dir.is_empty():
		_git_dir = GitCli.run(_repo_root, ["rev-parse", "--absolute-git-dir"])["text"].strip_edges()
	return _git_dir


var _common_dir := ""


## Directory shared by all worktrees (refs, config, logs). Cached like get_git_dir().
func get_common_dir() -> String:
	if _common_dir.is_empty():
		var dir: String = GitCli.run(_repo_root, ["rev-parse", "--git-common-dir"])["text"].strip_edges()
		_common_dir = dir if dir.is_absolute_path() or dir.is_empty() else _repo_root.path_join(dir).simplify_path()
	return _common_dir


## In-progress operation from git's marker files: {"kind": "merge"|"rebase"|"cherry-pick"|"revert"|"", "conflicts": int, "detail": e.g. "main, step 2/5"}.
func get_operation_state() -> Dictionary:
	var state := { "kind": "", "conflicts": 0, "detail": "" }
	var git_dir := get_git_dir()
	if git_dir.is_empty():
		return state

	for rebase_dir in ["rebase-merge", "rebase-apply"]:
		var dir_path := git_dir.path_join(rebase_dir)
		if DirAccess.dir_exists_absolute(dir_path):
			state["kind"] = "rebase"
			var step := _read_small(dir_path.path_join("msgnum" if rebase_dir == "rebase-merge" else "next"))
			var total := _read_small(dir_path.path_join("end" if rebase_dir == "rebase-merge" else "last"))
			var head_name := _read_small(dir_path.path_join("head-name")).trim_prefix("refs/heads/")
			var parts: Array = []
			if not head_name.is_empty():
				parts.append(head_name)
			if not step.is_empty() and not total.is_empty():
				parts.append("step %s/%s" % [step, total])
			state["detail"] = ", ".join(parts)
			break

	if state["kind"].is_empty():
		for marker in [["MERGE_HEAD", "merge"], ["CHERRY_PICK_HEAD", "cherry-pick"], ["REVERT_HEAD", "revert"]]:
			if FileAccess.file_exists(git_dir.path_join(marker[0])):
				state["kind"] = marker[1]
				state["detail"] = _read_small(git_dir.path_join("MERGE_MSG")).get_slice("\n", 0)
				break

	if not state["kind"].is_empty():
		state["conflicts"] = list_conflicts().size()
	return state


func _read_small(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


## The message git prepared for the pending merge commit (MERGE_MSG), without its # comment lines.
func get_merge_message() -> String:
	var lines: Array = []
	for line in _read_small(get_git_dir().path_join("MERGE_MSG")).split("\n"):
		if not line.begins_with("#"):
			lines.append(line)
	return "\n".join(lines).strip_edges()


## Repo-relative paths git still considers unmerged.
func list_conflicts() -> PackedStringArray:
	var r := GitCli.run(_repo_root, ["diff", "--name-only", "--diff-filter=U"])
	return GitCli.paths(r["text"])


## Finishes the in-progress operation once all conflicts are resolved (a merge is concluded with its prepared message).
func continue_operation() -> Dictionary:
	match get_operation_state()["kind"]:
		"merge": return _with_conflict_flag(_simple(["commit", "--no-edit"]))
		"rebase": return _after_rebase_step(_simple(["rebase", "--continue"]))
		"cherry-pick": return _with_conflict_flag(_simple(["cherry-pick", "--continue"]))
		"revert": return _with_conflict_flag(_simple(["revert", "--continue"]))
	return { "ok": false, "error": "Nothing to continue.", "output": "", "conflicts": false }


## Drops the commit currently being applied and moves on (rebase / cherry-pick / revert only).
func skip_operation() -> Dictionary:
	var kind: String = get_operation_state()["kind"]
	if kind in ["rebase", "cherry-pick", "revert"]:
		var result := _simple([kind, "--skip"])
		return _after_rebase_step(result) if kind == "rebase" else _with_conflict_flag(result)
	return { "ok": false, "error": "Only a rebase, cherry-pick or revert can skip a commit.", "output": "", "conflicts": false }


## Returns the repo to how it was before the operation started.
func abort_operation() -> Dictionary:
	var kind: String = get_operation_state()["kind"]
	if kind.is_empty():
		return { "ok": false, "error": "Nothing to abort.", "output": "" }
	var recovery: Variant = JSON.parse_string(_read_small(_amend_recovery_path())) if kind == "rebase" else null
	var result := _simple([kind, "--abort"])
	if result["ok"] and recovery is Dictionary:
		# Git abort restores the helper commit. Remove that helper with a soft
		# reset so the user's amendment returns to its original staged state.
		var original: String = recovery.get("original", "")
		var helper: String = recovery.get("helper", "")
		if get_head_oid() != helper or get_current_branch() != recovery.get("branch", "") or GitCli.run(_repo_root, ["rev-parse", helper + "^"])["text"].strip_edges() != original:
			return {"ok": false, "error": "Rebase aborted, but amendment recovery no longer matches this branch. The helper commit was kept; inspect Console and Git Log.", "output": ""}
		result = _simple(["reset", "--soft", original])
		if result["ok"]:
			_clear_amend_recovery()
	return result


## Takes one side ("ours"/"theirs"; in a rebase ours = onto, theirs = replayed commit) wholesale and marks it resolved — a deletion if that side deleted it.
func resolve_conflict(path: String, side: String) -> Dictionary:
	var checkout := GitCli.run(_repo_root, ["checkout", "--" + side, "--", path], true)
	if checkout["exit_code"] != 0:
		return _simple(["rm", "--quiet", "--", path])
	return _simple(["add", "--", path])


## Marks a conflicted file resolved as it currently is on disk (after fixing the markers by hand).
func mark_resolved(path: String) -> Dictionary:
	if FileAccess.file_exists(_repo_root.path_join(path)):
		return _simple(["add", "--", path])
	return _simple(["rm", "--quiet", "--", path])


## True if the file on disk still contains conflict markers.
func has_conflict_markers(path: String) -> bool:
	var abs_path := _repo_root.path_join(path)
	if not FileAccess.file_exists(abs_path):
		return false
	var text := FileAccess.get_file_as_string(abs_path)
	return text.contains("\n<<<<<<< ") or text.begins_with("<<<<<<< ") or text.contains("\n>>>>>>> ")


## mode: "" (fast-forward when possible), "no-ff", "ff-only" or "squash" (stages the result without committing). A conflict leaves the repo mid-merge — see get_operation_state().
func merge(ref: String, mode: String = "") -> Dictionary:
	var args := ["merge"]
	match mode:
		"no-ff": args.append("--no-ff")
		"ff-only": args.append("--ff-only")
		"squash": args.append("--squash")
	args.append(ref)
	return _with_conflict_flag(_simple(args))


## Replays the current branch's commits on top of onto.
func rebase(onto: String) -> Dictionary:
	return _with_conflict_flag(_simple(["rebase", onto]))


## Adds "conflicts": true when a failed command left the repo in an in-progress state with unmerged files, so the UI can say "resolve them" instead of showing a raw error.
func _with_conflict_flag(result: Dictionary) -> Dictionary:
	result["conflicts"] = not result["ok"] and not get_operation_state()["kind"].is_empty()
	return result


## Checks out a local branch, moving HEAD and updating the working tree.
## `git checkout` already refuses rather than clobbering local changes.
func checkout_branch(name: String) -> Dictionary:
	return _checkout(name)


## Checks out an arbitrary commit, leaving HEAD detached.
func checkout_commit(oid: String) -> Dictionary:
	return _checkout(oid)


func _checkout(target: String) -> Dictionary:
	var result := { "ok": false, "error": "" }
	var checkout_result := GitCli.run(_repo_root, ["checkout", target], true)
	if checkout_result["exit_code"] != 0:
		result["error"] = checkout_result["text"].strip_edges()
		return result
	result["ok"] = true
	return result


## Moves the current branch's tip to oid. hard=false leaves the working
## tree untouched (mixed reset); hard=true also discards uncommitted
## changes to match oid. Refuses on a detached HEAD.
func reset_branch_to(oid: String, hard: bool) -> Dictionary:
	var result := { "ok": false, "error": "" }
	if GitCli.run(_repo_root, ["symbolic-ref", "-q", "HEAD"])["exit_code"] != 0:
		result["error"] = "HEAD is detached — nothing to reset (checkout a branch first)"
		return result

	var reset_result := GitCli.run(_repo_root, ["reset", "--hard" if hard else "--mixed", oid], true)
	if reset_result["exit_code"] != 0:
		result["error"] = reset_result["text"].strip_edges()
		return result
	result["ok"] = true
	return result


func create_branch(name: String, start_point: String, checkout: bool) -> Dictionary:
	var result := { "ok": false, "error": "" }
	var point := start_point if not start_point.is_empty() else "HEAD"
	var args := ["checkout", "-b", name, point] if checkout else ["branch", name, point]
	var branch_result := GitCli.run(_repo_root, args, true)
	if branch_result["exit_code"] != 0:
		result["error"] = branch_result["text"].strip_edges()
		return result
	result["ok"] = true
	return result


## Flat parent-linked commit list (HEAD + local branches, lanes laid out in commit_graph.gd); options: {"remotes": bool, "ref": only this ref, "path": only commits touching it, "skip": int}.
func get_commit_graph(limit: int = 200, options: Dictionary = {}) -> Array:
	return _parse_commit_graph(GitCli.run(_repo_root, _commit_graph_args(limit, options))["text"])


## Searches the whole history (same options as get_commit_graph()) instead of just the loaded page. mode: "message" (also matches a hash), "author", or "code" (commits that add/remove query, git's -S). Coroutine, off the main thread — -S diffs every commit. null if superseded by cancel_search().
func search_commits(query: String, mode: String, limit: int, options: Dictionary = {}) -> Variant:
	var args := _commit_graph_args(limit, options)
	match mode:
		"author": args.insert(1, "--author=" + query)
		"code": args.insert(1, "-S" + query)
		_: args.insert(1, "--grep=" + query)
	args.insert(1, "-i")
	if mode != "code":
		args.insert(1, "--fixed-strings") # "fix(" is text here, not a broken regex
	cancel_search()
	var job := GitCli.start(_repo_root, args)
	_search_job = job
	var r: Dictionary = await job.finished
	if _search_job == job:
		_search_job = null
	if r["cancelled"]:
		return null
	var commits := _parse_commit_graph(r["text"]) if r["exit_code"] == 0 else []
	if mode == "message" and query.length() >= 4 and query.is_valid_hex_number():
		var hit := GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", query + "^{commit}"])
		if hit["exit_code"] == 0 and not commits.any(func(c: Dictionary) -> bool: return c["oid"] == hit["text"].strip_edges()):
			commits = _parse_commit_graph(GitCli.run(_repo_root, _commit_graph_args(1, { "ref": query }))["text"]) + commits
	return commits


var _search_job: RefCounted = null


## Per-line blame of path as it reads in contents (the editor's possibly unsaved text): [{"oid", "author", "time", "summary"}], 0-based by line; "oid" is "" for uncommitted lines. null if git failed. Coroutine (background thread).
func blame(path: String, contents: String) -> Variant:
	var tmp_path := _temp_dir().path_join("godit_blame_%d.tmp" % Time.get_ticks_usec())
	var tmp := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp == null:
		return null
	tmp.store_string(contents)
	tmp.close()
	var job := GitCli.start(_repo_root, ["blame", "--porcelain", "--contents", tmp_path, "--", path], false)
	var r: Dictionary = await job.finished
	DirAccess.remove_absolute(tmp_path)
	if r["exit_code"] != 0:
		return null
	return _parse_blame(r["text"])


## --porcelain: a "<oid> <orig> <final> [count]" header per line, commit details only the first time an oid appears, then a tab-prefixed content line.
func _parse_blame(text: String) -> Array:
	var commits := {}
	var lines: Array = []
	var oid := ""
	for line in text.split("\n"):
		if line.begins_with("\t"):
			var c: Dictionary = commits.get(oid, {})
			var committed := not oid.is_empty() and oid.lstrip("0") != ""
			lines.append({
				"oid": oid if committed else "",
				"author": c.get("author", "") if committed else "",
				"time": c.get("time", 0) if committed else 0,
				"summary": c.get("summary", "") if committed else "",
			})
			continue
		var space := line.find(" ")
		if space == -1:
			continue
		var key := line.substr(0, space)
		var value := line.substr(space + 1)
		if key.length() >= 40 and key.is_valid_hex_number():
			oid = key
			if not commits.has(oid):
				commits[oid] = {}
		elif key == "author":
			commits[oid]["author"] = value
		elif key == "author-time":
			commits[oid]["time"] = value.to_int()
		elif key == "summary":
			commits[oid]["summary"] = value
	return lines


func cancel_search() -> void:
	if _search_job != null:
		_search_job.cancel()
		_search_job = null


func _commit_graph_args(limit: int, options: Dictionary) -> Array:
	var fmt := "%H" + GitCli.US + "%P" + GitCli.US + "%s" + GitCli.US + "%B" + GitCli.US + "%an" + GitCli.US + "%ae" + GitCli.US + "%at" + GitCli.RS
	var args := ["log", "--topo-order", "--date-order", "--format=" + fmt, "--max-count=%d" % limit]
	if options.get("skip", 0) > 0:
		args.append("--skip=%d" % options["skip"])
	var ref: String = options.get("ref", "")
	if not ref.is_empty():
		args.append(ref)
	else:
		args.append_array(["HEAD", "--branches"])
		if options.get("remotes", false):
			args.append("--remotes")
	var path: String = options.get("path", "")
	if not path.is_empty():
		# --parents rewrites %P to the nearest commit that also touched path, so the filtered graph stays connected.
		args.append_array(["--parents", "--", path])
	return args


func _parse_commit_graph(log_text: String) -> Array:
	var branch_refs := _refs_by_oid(["refs/heads", "refs/remotes"])
	var tag_refs := _tags_by_oid()
	var entries: Array = []
	for record in log_text.split(GitCli.RS):
		if record.strip_edges().is_empty():
			continue
		var fields := record.lstrip("\n").split(GitCli.US) # leading \n from the previous record's terminator
		if fields.size() < 7:
			continue
		var oid: String = fields[0]
		var parents := PackedStringArray()
		if not fields[1].strip_edges().is_empty():
			for p in fields[1].split(" "):
				if not p.is_empty():
					parents.append(p)
		entries.append({
			"oid": oid,
			"parents": parents,
			"summary": fields[2],
			"message": fields[3],
			"author_name": fields[4],
			"author_email": fields[5],
			"time": int(fields[6].strip_edges()),
			"refs": branch_refs.get(oid, PackedStringArray()),
			"tags": tag_refs.get(oid, PackedStringArray()),
		})
	return entries


func get_head_oid() -> String:
	var r := GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", "HEAD"])
	return r["text"].strip_edges() if r["exit_code"] == 0 else ""


## The commit a full ref name ("refs/heads/main", "stash@{1}", a tag) points to, or "" if it doesn't resolve.
func resolve_commit(ref: String) -> String:
	var r := GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", ref + "^{commit}"])
	return r["text"].strip_edges() if r["exit_code"] == 0 else ""


## get_head_oid() read straight from .git's files where possible, for polling without spawning git.
func read_head_oid() -> String:
	var head := _read_small(get_git_dir().path_join("HEAD"))
	if head.begins_with("ref: "):
		head = _read_small(get_common_dir().path_join(head.substr(5)))
	return head if head.length() >= 40 and not head.contains(" ") else get_head_oid()


## The refs, config and stash reflog parts of a RepoWatcher snapshot, read now; with_status adds `git status` too.
func read_snapshot(with_status := false) -> Dictionary:
	return snapshot_of(_repo_root, get_git_dir(), get_common_dir(), with_status)


## Every ref and its target plus HEAD, so pollers can cheaply tell whether history moved. Static and free of static vars, so RepoWatcher can run it on a worker thread.
static func refs_signature_of(root: String, git_dir: String) -> String:
	return GitCli.execute("git", GitCli.argv(root, REFS_ARGS))["out"].get_string_from_utf8() + read_text(git_dir.path_join("HEAD"))


## {"status" (raw STATUS_ARGS output, "" without with_status), "refs", "config", "stash_log"}; worker-thread safe like refs_signature_of().
static func snapshot_of(root: String, git_dir: String, common_dir: String, with_status: bool) -> Dictionary:
	return {
		"status": GitCli.execute("git", GitCli.argv(root, STATUS_ARGS))["out"].get_string_from_utf8() if with_status else "",
		"refs": refs_signature_of(root, git_dir),
		"config": read_text(common_dir.path_join("config")),
		"stash_log": read_text(common_dir.path_join("logs/refs/stash")),
	}


static func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func is_ancestor_of_head(oid: String) -> bool:
	return GitCli.run(_repo_root, ["merge-base", "--is-ancestor", oid, "HEAD"])["exit_code"] == 0


## The empty tree's id in this repo's hash format — the "parent" to diff a root commit against.
func empty_tree_oid() -> String:
	if GitCli.run(_repo_root, ["rev-parse", "--show-object-format"])["text"].strip_edges() == "sha256":
		return "6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321"
	return "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


## rev's first parent, or the empty tree if it has none.
func parent_or_empty_tree(oid: String) -> String:
	return oid + "^" if has_parent(oid) else empty_tree_oid()


## Untracked files saved by `stash push -u` live in a third, parentless commit; "" if the stash has none.
func stash_untracked_rev(ref: String) -> String:
	var rev := ref + "^3"
	return rev if GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", rev])["exit_code"] == 0 else ""


## Where path (as of commit oid) lives in the working tree now, following renames made since; "" if it was deleted.
func current_path(oid: String, path: String) -> String:
	if FileAccess.file_exists(_repo_root.path_join(path)):
		return path
	for entry in _parse_name_status(GitCli.run(_repo_root, ["diff", "--name-status", "-M", oid])["text"]):
		if entry.get("old_path", "") == path and entry["status"] == GitIcons.DELTA_RENAMED:
			return entry["path"]
	return ""


func has_parent(oid: String) -> bool:
	return GitCli.run(_repo_root, ["rev-parse", "-q", "--verify", oid + "^"])["exit_code"] == 0


## True if any merge commit lies between oid (exclusive) and HEAD — history rewriting through merges would flatten them, so those actions refuse.
func has_merges_since(oid: String) -> bool:
	var r := GitCli.run(_repo_root, ["rev-list", "--merges", "%s..HEAD" % oid])
	return not r["text"].strip_edges().is_empty()


func has_staged_changes() -> bool:
	return GitCli.run(_repo_root, ["diff", "--cached", "--quiet"])["exit_code"] != 0


## Staged added/modified files bigger than limit_bytes that Git LFS doesn't already take care of: [{"path", "size"}].
func large_staged_files(limit_bytes: int) -> Array:
	var large: Array = []
	for path in GitCli.paths(GitCli.run(_repo_root, ["diff", "--cached", "--name-only", "--diff-filter=AM"])["text"]):
		var f := FileAccess.open(_repo_root.path_join(path), FileAccess.READ)
		if f != null and f.get_length() > limit_bytes:
			large.append({ "path": path, "size": f.get_length() })
	if large.is_empty():
		return large
	var lfs := {}
	var attrs: String = GitCli.run(_repo_root, ["check-attr", "filter", "--"] + large.map(func(e: Dictionary) -> String: return e["path"]))["text"]
	for line in GitCli.lines(attrs):
		if line.ends_with(": filter: lfs"):
			lfs[GitCli.unquote(line.trim_suffix(": filter: lfs"))] = true
	return large.filter(func(e: Dictionary) -> bool: return not lfs.has(e["path"]))


## Tracks every file with the same extension as one of paths with Git LFS ("*.png"), and re-stages paths so they're stored as LFS pointers.
func lfs_track(paths: Array) -> Dictionary:
	var patterns: Array = []
	for path in paths:
		var pattern: String = "*." + String(path).get_extension() if not path.get_extension().is_empty() else path
		if not patterns.has(pattern):
			patterns.append(pattern)
	var r := GitCli.run(_repo_root, ["lfs", "track"] + patterns, true)
	if r["exit_code"] != 0:
		return { "ok": false, "error": r["text"].strip_edges() }
	GitCli.run(_repo_root, ["add", ".gitattributes"], true)
	# The blobs are already staged as regular files; --renormalize runs them through the new LFS filter.
	return _simple(["add", "--renormalize", "--"] + paths)


## Applies commits (given newest first, as the log shows them) on top of HEAD, oldest first. no_commit leaves the result staged instead.
func cherry_pick(oids: PackedStringArray, no_commit: bool = false) -> Dictionary:
	var args := ["cherry-pick"]
	if no_commit:
		args.append("--no-commit")
	var ordered := Array(oids)
	ordered.reverse()
	if ordered.size() == 1 and _parent_count(ordered[0]) > 1:
		args.append_array(["-m", "1"]) # a merge: take the changes relative to its first parent
	args.append_array(ordered)
	return _with_conflict_flag(_simple(args))


## Creates a new commit undoing oid (-m 1 for merges: undo what the merge brought in).
func revert_commit(oid: String, no_commit: bool = false) -> Dictionary:
	var args := ["revert"]
	if no_commit:
		args.append("--no-commit")
	if _parent_count(oid) > 1:
		args.append_array(["-m", "1"])
	args.append(oid)
	return _with_conflict_flag(_simple(args))


func _parent_count(oid: String) -> int:
	var r := GitCli.run(_repo_root, ["rev-list", "--parents", "-n", "1", oid])
	return maxi(0, r["text"].strip_edges().split(" ").size() - 1)


## Moves the branch back one commit, keeping that commit's changes staged.
## The latest thing that moved HEAD (per its reflog) and how to take it back: {"label": "Undo commit “Fix jump”", "mode": "soft"|"keep"|"checkout", "target": rev to go back to}, or {} when there's nothing to undo.
## Entries that didn't move HEAD (a stash's "reset: moving to HEAD") are skipped; a finished rebase goes back to before its start.
func last_head_operation() -> Dictionary:
	var entries: Array = []
	for line in GitCli.lines(GitCli.run(_repo_root, ["reflog", "-n", "200", "--format=%H" + US + "%gs"])["text"]):
		var f := line.split(US)
		if f.size() >= 2:
			entries.append({ "oid": f[0], "subject": f[1] })
	for i in entries.size() - 1:
		var subject: String = entries[i]["subject"]
		var action := subject.get_slice(": ", 0)
		var detail := subject.substr(action.length() + 2).strip_edges()
		var target: String = entries[i + 1]["oid"]
		# A rebase's finish and a checkout -b to a new branch switch branches without moving HEAD's commit.
		var switched := action.ends_with("(finish)") or action == "checkout" and detail.get_slice(" to ", 0) != "moving from " + detail.get_slice(" to ", 1)
		if entries[i]["oid"] == target and not switched:
			continue
		if action.ends_with("(finish)"):
			var start := action.replace("(finish)", "(start)")
			for j in range(i + 1, entries.size() - 1):
				if String(entries[j]["subject"]).begins_with(start):
					target = entries[j + 1]["oid"]
					break
			return { "label": "Undo %s" % action.trim_suffix(" (finish)"), "mode": "keep", "target": target }
		if action == "commit (initial)" or action.contains("(start)") or action.contains("(pick)") or action.contains("(continue)"):
			return {} # nothing before the first commit; a rebase still in progress is aborted instead
		if action == "commit (amend)":
			return { "label": "Undo amend of “%s”" % detail, "mode": "soft", "target": target }
		if action.begins_with("commit"):
			return { "label": "Undo commit “%s”" % detail, "mode": "soft", "target": target }
		if action == "checkout":
			var from := detail.trim_prefix("moving from ").get_slice(" to ", 0)
			return { "label": "Undo checkout of %s (back to %s)" % [detail.get_slice(" to ", 1), from], "mode": "checkout", "target": from }
		if action == "cherry-pick" or action == "revert":
			return { "label": "Undo %s “%s”" % [action, detail], "mode": "keep", "target": target }
		return { "label": "Undo %s" % action, "mode": "keep", "target": target }
	return {}


## Takes back last_head_operation(): "soft" keeps the undone commit's changes staged, "keep" moves the branch back but refuses to overwrite local changes.
func undo_head_operation(op: Dictionary) -> Dictionary:
	match op.get("mode", ""):
		"soft": return _simple(["reset", "--soft", op["target"]])
		"keep": return _simple(["reset", "--keep", op["target"]])
		"checkout": return _checkout(op["target"])
	return { "ok": false, "error": "Nothing to undo.", "output": "" }


## Full messages of the latest commits on HEAD, newest first, duplicates dropped — yours only when git knows your email.
func recent_commit_messages(limit: int) -> PackedStringArray:
	var args := ["log", "-n", str(limit * 2), "--format=%B" + GitCli.RS]
	var email: String = GitCli.run(_repo_root, ["config", "user.email"])["text"].strip_edges()
	if not email.is_empty():
		args.append("--author=" + email)
	var messages := PackedStringArray()
	for message in GitCli.run(_repo_root, args)["text"].split(GitCli.RS):
		message = message.strip_edges()
		if not message.is_empty() and not messages.has(message):
			messages.append(message)
	return messages.slice(0, limit)


func undo_last_commit() -> Dictionary:
	if not has_parent("HEAD"):
		return { "ok": false, "error": "This is the first commit — there's nothing before it to go back to.", "output": "" }
	return _simple(["reset", "--soft", "HEAD~1"])


## Changes a commit's message. HEAD is simply amended (message only — staged changes stay staged); an older commit goes through an autosquashed "amend!" fixup, rewriting everything after it.
func reword_commit(oid: String, message: String) -> Dictionary:
	if oid == get_head_oid():
		return _simple(["commit", "--amend", "--only", "--allow-empty", "-m", message])
	if has_merges_since(oid):
		return { "ok": false, "error": "A merge commit lies after it — rewriting through merges would flatten them.", "output": "" }
	# The same "amend! <subject>" commit `git commit --fixup=reword:` would make (autosquash then swaps the message in), built with commit-tree so it neither needs an editor nor picks up anything staged.
	var subject: String = GitCli.run(_repo_root, ["log", "-1", "--format=%s", oid])["text"].strip_edges()
	var made := _simple(["commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "amend! " + subject, "-m", message])
	if not made["ok"]:
		return made
	var original := get_head_oid()
	var moved := _simple(["update-ref", "-m", "godit: reword " + oid.substr(0, 7), "HEAD", made["output"]])
	if not moved["ok"]:
		return moved
	return _autosquash_onto(oid, original)


## Folds the currently staged changes into commit oid (rewrites everything after it).
func fixup_commit(oid: String) -> Dictionary:
	if not has_staged_changes():
		return { "ok": false, "error": "Nothing is staged — stage the changes to fold in first.", "output": "" }
	if oid == get_head_oid():
		return _simple(["commit", "--amend", "--no-edit"])
	if has_merges_since(oid):
		return { "ok": false, "error": "A merge commit lies after it — rewriting through merges would flatten them.", "output": "" }
	var original := get_head_oid()
	var fixup := _simple(["commit", "--fixup=" + oid])
	if not fixup["ok"]:
		return fixup
	return _autosquash_onto(oid, original)


## original: HEAD before the helper (amend!/fixup!) commit was made; a rebase that fails outright (not on conflicts) is moved back there, keeping the staged changes.
func _autosquash_onto(oid: String, original: String) -> Dictionary:
	var base := oid + "^" if has_parent(oid) else "--root"
	var args := ["rebase", "--interactive", "--autosquash", "--autostash"]
	args.append(base)
	var result := _with_conflict_flag(_simple(args))
	if not result["ok"] and not result["conflicts"] and not original.is_empty() and get_operation_state()["kind"].is_empty():
		_simple(["reset", "--soft", original])
	return result


## Squashes oid and every commit after it up to HEAD into one commit with message.
func squash_to_head(oid: String, message: String) -> Dictionary:
	if has_staged_changes():
		return { "ok": false, "error": "There are staged changes — commit or unstage them first, or they'd end up in the squashed commit.", "output": "" }
	if not has_parent(oid):
		return { "ok": false, "error": "Can't squash down to the very first commit.", "output": "" }
	var reset := _simple(["reset", "--soft", oid + "^"])
	if not reset["ok"]:
		return reset
	return _simple(["commit", "-m", message])


## Removes commit oid from the current branch, replaying the ones after it.
func drop_commit(oid: String) -> Dictionary:
	if not has_parent(oid):
		return { "ok": false, "error": "Can't drop the very first commit.", "output": "" }
	return _with_conflict_flag(_simple(["rebase", "--autostash", "--onto", oid + "^", oid]))


## Messages of oid..HEAD (oldest first), for prefilling a squash message.
func get_messages_since(oid: String) -> String:
	var r := GitCli.run(_repo_root, ["log", "--reverse", "--format=%B" + GitCli.RS, "%s^..HEAD" % oid])
	var parts: Array = []
	for m in r["text"].split(GitCli.RS):
		if not m.strip_edges().is_empty():
			parts.append(m.strip_edges())
	return "\n\n".join(parts)


## Files changed by this commit, diffed against its first parent (--root
## diffs a parentless commit against the empty tree, so its files show as
## additions). -M folds a delete+add pair into a single rename entry.
func get_commit_files(oid: String) -> Array:
	var result := GitCli.run(_repo_root, ["diff-tree", "--no-commit-id", "--name-status", "-r", "--root", "-M", oid])
	return _parse_name_status(result["text"])


func _parse_name_status(text: String) -> Array:
	var entries: Array = []
	for line in GitCli.lines(text):
		var fields := Array(line.split("\t")).map(func(f: String) -> String: return GitCli.unquote(f))
		if fields.size() < 2:
			continue
		var letter: String = fields[0].substr(0, 1) # strip the similarity score off R100/C100
		var path: String = fields[2] if (letter == "R" or letter == "C") and fields.size() > 2 else fields[1]
		var entry := { "path": path, "status": _delta_status(letter) }
		if letter == "R" or letter == "C":
			entry["old_path"] = fields[1]
		entries.append(entry)
	return entries


func _delta_status(letter: String) -> int:
	match letter:
		"A": return GitIcons.DELTA_ADDED
		"D": return GitIcons.DELTA_DELETED
		"R": return GitIcons.DELTA_RENAMED
		"C": return GitIcons.DELTA_COPIED
		"T": return GitIcons.DELTA_TYPECHANGE
		_: return GitIcons.DELTA_MODIFIED


## Branch names whose history contains oid, "HEAD" first if it qualifies
## too (a detached checkout has no branch name of its own).
func branches_containing(oid: String) -> PackedStringArray:
	var names := PackedStringArray()

	if GitCli.run(_repo_root, ["symbolic-ref", "-q", "HEAD"])["exit_code"] != 0:
		if GitCli.run(_repo_root, ["merge-base", "--is-ancestor", oid, "HEAD"])["exit_code"] == 0:
			names.append("HEAD")

	var result := GitCli.run(_repo_root, ["for-each-ref", "--contains", oid, "--format=%(refname:short)", "refs/heads", "refs/remotes"])
	for line in GitCli.lines(result["text"]):
		if line.ends_with("/HEAD"):
			continue
		names.append(line)
	return names


func _refs_by_oid(ref_prefixes: Array) -> Dictionary:
	var fmt := "%(objectname)" + GitCli.US + "%(refname:short)" + GitCli.US + "%(refname)"
	var args := ["for-each-ref", "--format=" + fmt]
	args.append_array(ref_prefixes)
	var result := GitCli.run(_repo_root, args)

	var map := {}
	for line in GitCli.lines(result["text"]):
		var fields := line.split(GitCli.US)
		if fields.size() < 2:
			continue
		var oid: String = fields[0]
		var name: String = fields[1]
		# refs/remotes/origin/HEAD shortens to just "origin", so check the full name.
		if fields[fields.size() - 1].ends_with("/HEAD"):
			continue
		# Mutating a PackedStringArray fetched from a Dictionary in place
		# doesn't write back (COW) — reassign it instead.
		var arr: PackedStringArray = map.get(oid, PackedStringArray())
		arr.append(name)
		map[oid] = arr
	return map


func _tags_by_oid() -> Dictionary:
	# %(*objectname) is the peeled oid for an annotated tag, empty for a
	# lightweight one (falls back to %(objectname)).
	var fmt := "%(objectname)" + GitCli.US + "%(*objectname)" + GitCli.US + "%(refname:short)"
	var result := GitCli.run(_repo_root, ["for-each-ref", "--format=" + fmt, "refs/tags"])

	var map := {}
	for line in GitCli.lines(result["text"]):
		var fields := line.split(GitCli.US)
		if fields.size() < 3:
			continue
		var oid: String = fields[1] if not fields[1].is_empty() else fields[0]
		var name: String = fields[2]
		var arr: PackedStringArray = map.get(oid, PackedStringArray())
		arr.append(name)
		map[oid] = arr
	return map


func _temp_dir() -> String:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var temp := project_root.path_join(project_root.get_file() + "-temp-chatgpt/gittydot")
	DirAccess.make_dir_recursive_absolute(temp)
	var ignore := temp.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var marker := FileAccess.open(ignore, FileAccess.WRITE)
		if marker != null:
			marker.close()
	return temp
