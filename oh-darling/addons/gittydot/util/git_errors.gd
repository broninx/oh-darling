## Recognizes common git failure messages so the UI can explain them and offer the obvious next step instead of just dumping stderr. No class_name: internal helper, addressed via preload.
extends RefCounted

const NO_UPSTREAM := "no_upstream"
const NON_FAST_FORWARD := "non_fast_forward"
const AUTH := "auth"
const HOST_KEY := "host_key"
const CONFLICT := "conflict"
const DIRTY := "dirty"
const DIVERGED := "diverged"
const NO_REMOTE := "no_remote"


static func classify(text: String) -> String:
	var t := text.to_lower()
	if t.contains("has no upstream branch") or t.contains("no upstream configured") or t.contains("there is no tracking information"):
		return NO_UPSTREAM
	if t.contains("non-fast-forward") or t.contains("fetch first") or (t.contains("[rejected]") and t.contains("behind")):
		return NON_FAST_FORWARD
	if t.contains("not possible to fast-forward") or t.contains("divergent branches") or t.contains("need to specify how to reconcile"):
		return DIVERGED
	if t.contains("host key verification failed"):
		return HOST_KEY
	if t.contains("permission denied") or t.contains("authentication failed") or t.contains("could not read username") \
			or t.contains("terminal prompts disabled") or t.contains("could not read password"):
		return AUTH
	if t.contains("conflict") and (t.contains("automatic merge failed") or t.contains("could not apply") or t.contains("fix conflicts")):
		return CONFLICT
	if t.contains("would be overwritten by") or t.contains("please commit your changes or stash them") \
			or t.contains("your local changes") or t.contains("unstaged changes"):
		return DIRTY
	if t.contains("no configured push destination") or t.contains("does not appear to be a git repository"):
		return NO_REMOTE
	return ""


## Short human explanation prepended to git's own output.
static func explain(text: String) -> String:
	var hint := ""
	match classify(text):
		NO_UPSTREAM:
			hint = "This branch isn't tracking a remote branch yet."
		NON_FAST_FORWARD:
			hint = "The remote has commits you don't have yet. Pull first, then push again."
		DIVERGED:
			hint = "Your branch and its upstream have diverged. Pull with Merge or Rebase to reconcile them."
		HOST_KEY:
			hint = "SSH doesn't know this host yet. Connect once from a terminal (e.g. `ssh -T git@host`) to accept its key."
		AUTH:
			hint = "Authentication failed. Godit can't answer password prompts — set up an SSH agent or a credential helper, then retry."
		CONFLICT:
			hint = "There are conflicts. Resolve them in the Changes panel, then Continue (or Abort)."
		DIRTY:
			hint = "Uncommitted changes are in the way. Commit or stash them first."
		NO_REMOTE:
			hint = "No usable remote is configured. Add one in the Branches panel (Remotes)."
	if hint.is_empty():
		return text
	return "%s\n\n%s" % [hint, text]
