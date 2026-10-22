## Fetch/Pull/Push flows shared by the Changes and Branches panels: runs the operation in the background (with an OperationBar showing progress and Cancel), then turns the usual failures into a question with the obvious fix — set upstream, pull first, force-with-lease, merge vs rebase, autostash. Every function is a coroutine returning whether it succeeded. No class_name: internal helper, addressed via preload.
extends RefCounted

const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const SaveGuard := preload("res://addons/gittydot/dock/widgets/save_guard.gd")
const GitErrors := preload("res://addons/gittydot/util/git_errors.gd")
const EditorOpen := preload("res://addons/gittydot/util/editor_open.gd")


static func fetch(parent: Control, repo: RefCounted, bar: Control, remote: String = "", prune: bool = false) -> bool:
	if not _check_idle(parent, repo):
		return false
	bar.busy("Fetching %s…" % (remote if not remote.is_empty() else "all remotes"), repo)
	var r: Dictionary = await repo.fetch(remote, prune)
	if r["ok"]:
		bar.done("Fetched.")
		return true
	bar.done("Fetch cancelled." if r["cancelled"] else "Fetch failed.", not r["cancelled"])
	if not r["cancelled"]:
		await Dialogs.error(parent, "Fetch failed", GitErrors.explain(r["error"]))
	return false


static func pull(parent: Control, repo: RefCounted, bar: Control, strategy: String = "", autostash: bool = false) -> bool:
	if not _check_idle(parent, repo) or not await SaveGuard.ensure_saved(parent, "Pull"):
		return false
	bar.busy("Pulling…", repo)
	var r: Dictionary = await repo.pull(strategy, autostash)
	EditorOpen.refresh_all_external_changes()
	if r["ok"]:
		bar.done("Pulled." if not r["output"].contains("Already up to date") else "Already up to date.")
		return true
	if r["cancelled"]:
		bar.done("Pull cancelled.")
		return false
	bar.done("Pull failed.", true)

	match GitErrors.classify(r["error"]):
		GitErrors.DIVERGED:
			var choice := await Dialogs.error_with_actions(parent, "Pull needs a strategy", GitErrors.explain(r["error"]),
					{ "merge": "Pull (Merge)", "rebase": "Pull (Rebase)" })
			if not choice.is_empty():
				return await pull(parent, repo, bar, choice, autostash)
		GitErrors.DIRTY:
			var choice := await Dialogs.error_with_actions(parent, "Pull blocked by local changes", GitErrors.explain(r["error"]),
					{ "autostash": "Stash, Pull, Re-apply" })
			if choice == "autostash":
				return await pull(parent, repo, bar, strategy, true)
		_:
			await Dialogs.error(parent, "Pull failed", GitErrors.explain(r["error"]))
	return false


## options: see GitCliRepo.push().
static func push(parent: Control, repo: RefCounted, bar: Control, options: Dictionary = {}) -> bool:
	if not _check_idle(parent, repo):
		return false
	bar.busy("Pushing…", repo)
	var r: Dictionary = await repo.push(options)
	if r["ok"]:
		bar.done("Pushed." if not r["output"].contains("Everything up-to-date") else "Everything up to date.")
		return true
	if r["cancelled"]:
		bar.done("Push cancelled.")
		return false
	bar.done("Push failed.", true)

	match GitErrors.classify(r["error"]):
		GitErrors.NO_UPSTREAM:
			var branch: String = repo.get_current_branch()
			var remote := default_remote(repo)
			if branch.is_empty() or remote.is_empty():
				await Dialogs.error(parent, "Push failed", GitErrors.explain(r["error"]))
				return false
			if await Dialogs.confirm(parent, "Publish Branch",
					"\"%s\" doesn't track a remote branch yet.\n\nPush it to %s/%s and track it from now on?" % [branch, remote, branch], "Push"):
				var next := options.duplicate()
				next.merge({ "remote": remote, "branch": branch, "set_upstream": true }, true)
				return await push(parent, repo, bar, next)
		GitErrors.NON_FAST_FORWARD:
			var choice := await Dialogs.error_with_actions(parent, "Push rejected", GitErrors.explain(r["error"]),
					{ "pull": "Pull, then Push", "force": "Force Push…" })
			if choice == "pull":
				if await pull(parent, repo, bar):
					return await push(parent, repo, bar, options)
			elif choice == "force":
				if await Dialogs.confirm(parent, "Force Push",
						"Overwrite the remote branch with your local one?\n\nUses --force-with-lease: it still refuses if someone pushed commits you haven't fetched.", "Force Push"):
					var next := options.duplicate()
					next["force_with_lease"] = true
					return await push(parent, repo, bar, next)
		_:
			await Dialogs.error(parent, "Push failed", GitErrors.explain(r["error"]))
	return false


## "origin" if it exists, otherwise the first configured remote, or "".
static func default_remote(repo: RefCounted) -> String:
	var remotes: Array = repo.list_remotes()
	for remote in remotes:
		if remote["name"] == "origin":
			return "origin"
	return remotes[0]["name"] if not remotes.is_empty() else ""


static func _check_idle(parent: Control, repo: RefCounted) -> bool:
	if repo.is_busy():
		Dialogs.error(parent, "Busy", "Another git operation is still running — wait for it or cancel it first.")
		return false
	return true
