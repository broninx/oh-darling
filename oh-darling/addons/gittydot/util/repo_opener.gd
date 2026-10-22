## No class_name: internal helper, addressed via preload (matches this
## project's no-global-namespace-pollution convention, see git_status_flags.gd).
extends RefCounted

const GitCliRepo := preload("res://addons/gittydot/util/git_cli_repo.gd")

## Opens a git repo backend for the current editor project. Returns
## {"repo": RefCounted or null, "error": String}, error ready to show
## directly in a dock. Both docks call this separately and open their own
## repo instance — opening is cheap.
static func open_current_project_repo() -> Dictionary:
	var repo := GitCliRepo.new()
	if not repo.open(ProjectSettings.globalize_path("res://")):
		return {
			"repo": null,
			"error": "GittyDot: this project isn't inside a git repository, or the `git` command isn't on PATH.",
		}

	return { "repo": repo, "error": "" }
