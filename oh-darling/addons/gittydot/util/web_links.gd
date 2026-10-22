## Links to a commit, file, branch or new pull request on the remote's website (GitHub, GitLab, Bitbucket), built from the remote URL.
## No class_name: internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const GitCli := preload("res://addons/gittydot/util/git_cli.gd")


## {"kind": "github"|"gitlab"|"bitbucket", "base": "https://host/owner/repo", "name": "GitHub"...} for remote (default: the upstream's remote, else origin, else the first), or {} if it's not one of those hosts.
static func site(repo: RefCounted, remote := "") -> Dictionary:
	var remotes: Array = repo.list_remotes()
	if remotes.is_empty():
		return {}
	if remote.is_empty():
		var upstream: String = repo.get_upstream()
		remote = upstream.get_slice("/", 0) if not upstream.is_empty() else ""
	var url := ""
	for r in remotes:
		if r["name"] == remote or (remote.is_empty() and r["name"] == "origin"):
			url = r["fetch_url"]
	if url.is_empty():
		url = remotes[0]["fetch_url"]
	return site_for_url(url)


## Remote URL (scp-style, ssh:// or https://) -> site(), or {}.
static func site_for_url(url: String) -> Dictionary:
	var rest := url.strip_edges()
	if rest.contains("://"):
		rest = rest.get_slice("://", 1)
	elif rest.contains(":"): # git@host:owner/repo
		rest = rest.replace(":", "/")
	if rest.contains("@") and rest.find("@") < rest.find("/"):
		rest = rest.substr(rest.find("@") + 1)
	var host := rest.get_slice("/", 0).get_slice(":", 0).to_lower()
	var path := rest.substr(rest.find("/") + 1).trim_suffix("/").trim_suffix(".git")
	if host.is_empty() or path.is_empty() or not rest.contains("/"):
		return {}
	for kind in ["github", "gitlab", "bitbucket"]:
		if host.contains(kind):
			return { "kind": kind, "base": "https://%s/%s" % [host, path], "name": { "github": "GitHub", "gitlab": "GitLab", "bitbucket": "Bitbucket" }[kind] }
	return {}


static func commit_url(s: Dictionary, oid: String) -> String:
	return s["base"] + { "github": "/commit/", "gitlab": "/-/commit/", "bitbucket": "/commits/" }[s["kind"]] + oid


## File at ref (a commit or branch), optionally at line (1-based).
static func file_url(s: Dictionary, ref: String, path: String, line := 0) -> String:
	var prefix: String = { "github": "/blob/", "gitlab": "/-/blob/", "bitbucket": "/src/" }[s["kind"]]
	var anchor := ""
	if line > 0:
		anchor = ("#lines-%d" if s["kind"] == "bitbucket" else "#L%d") % line
	return s["base"] + prefix + _encode_path(ref) + "/" + _encode_path(path) + anchor


static func branch_url(s: Dictionary, branch: String) -> String:
	return s["base"] + { "github": "/tree/", "gitlab": "/-/tree/", "bitbucket": "/src/" }[s["kind"]] + _encode_path(branch)


## Page for opening a pull/merge request from branch (as named on the remote).
static func new_pull_request_url(s: Dictionary, branch: String) -> String:
	match s["kind"]:
		"github": return s["base"] + "/compare/" + _encode_path(branch) + "?expand=1"
		"gitlab": return s["base"] + "/-/merge_requests/new?merge_request%5Bsource_branch%5D=" + branch.uri_encode()
	return s["base"] + "/pull-requests/new?source=" + branch.uri_encode()


## True if some remote-tracking branch contains oid, i.e. the website has it.
static func is_pushed(repo: RefCounted, oid: String) -> bool:
	var r := GitCli.run(repo.get_repo_root(), ["for-each-ref", "--contains", oid, "--count=1", "--format=x", "refs/remotes"])
	return r["exit_code"] == 0 and not r["text"].strip_edges().is_empty()


## Newest commit of HEAD's history that the upstream has too ("" without an upstream): links from the working tree point there.
static func pushed_base(repo: RefCounted) -> String:
	var r := GitCli.run(repo.get_repo_root(), ["merge-base", "HEAD", "@{upstream}"])
	return r["text"].strip_edges() if r["exit_code"] == 0 else ""


static func _encode_path(path: String) -> String:
	return "/".join(Array(path.split("/")).map(func(part: String) -> String: return part.uri_encode()))
