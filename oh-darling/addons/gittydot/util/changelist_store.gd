## Persists changelists per repo — named groups for organizing changed files.
## Pure IDE-side bookkeeping, git has no concept of this. "Default" always
## exists and can't be deleted/renamed. Keyed by repo root. No class_name:
## internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const DEFAULT_NAME := "Default"
const CONFIG_PATH := "res://.godot/gittydot/changelists.cfg"


static func _section(repo_root: String) -> String:
	return "repo:" + repo_root.md5_text()


## Loaded state per repo root, shared by every panel so a change made in one (e.g. Branches restoring a shelved stash) is seen by the others.
static var _cache: Dictionary = {}


## {"names": Array[String], "assignments": Dictionary[path, name], "active": String, "shelved": Dictionary[stash oid, Dictionary[path, name]], "messages": Dictionary[name, draft commit message]}. A path missing from assignments is just in Default.
static func load_state(repo_root: String) -> Dictionary:
	if _cache.has(repo_root):
		return _cache[repo_root]
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH) # missing file is fine, falls through to defaults
	var section := _section(repo_root)

	var names: Array = cfg.get_value(section, "names", [])
	if not names.has(DEFAULT_NAME):
		names.push_front(DEFAULT_NAME)

	var active: String = cfg.get_value(section, "active", DEFAULT_NAME)
	if not names.has(active):
		active = DEFAULT_NAME

	var state := {
		"names": names,
		"assignments": cfg.get_value(section, "assignments", {}),
		"active": active,
		"shelved": cfg.get_value(section, "shelved", {}),
		"messages": cfg.get_value(section, "messages", {}),
	}
	_cache[repo_root] = state
	return state


static func save_state(repo_root: String, state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir()))
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var section := _section(repo_root)
	cfg.set_value(section, "names", state["names"])
	cfg.set_value(section, "assignments", state["assignments"])
	cfg.set_value(section, "active", state["active"])
	cfg.set_value(section, "shelved", state.get("shelved", {}))
	cfg.set_value(section, "messages", state.get("messages", {}))
	cfg.save(CONFIG_PATH)


## Remembers which changelist each stashed path was in, keyed by the stash's commit oid (stable, unlike stash@{n}).
static func remember_shelved(repo_root: String, stash_oid: String, paths: Array) -> void:
	var state := load_state(repo_root)
	var snapshot := {}
	for path in paths:
		snapshot[path] = state["assignments"].get(path, DEFAULT_NAME)
	state["shelved"][stash_oid] = snapshot
	save_state(repo_root, state)


## Puts a re-applied stash's files back into the changelists they were stashed from (recreating any that were deleted since). drop=true forgets the record (pop/drop).
static func restore_shelved(repo_root: String, stash_oid: String, drop: bool) -> void:
	var state := load_state(repo_root)
	var shelved: Dictionary = state["shelved"]
	if not shelved.has(stash_oid):
		return
	var snapshot: Dictionary = shelved[stash_oid]
	for path in snapshot:
		var name: String = snapshot[path]
		if name == DEFAULT_NAME:
			state["assignments"].erase(path)
			continue
		if not state["names"].has(name):
			state["names"].append(name)
		state["assignments"][path] = name
	if drop:
		shelved.erase(stash_oid)
	save_state(repo_root, state)


static func forget_shelved(repo_root: String, stash_oid: String) -> void:
	var state := load_state(repo_root)
	if state["shelved"].erase(stash_oid):
		save_state(repo_root, state)
