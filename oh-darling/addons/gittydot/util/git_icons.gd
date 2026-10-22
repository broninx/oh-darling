## Status letter + color for a git_status_t bitmask, mirroring the common
## single-letter convention (M/A/D/R/T/U) used by `git status --short` and
## most git GUIs. No class_name: internal helper, addressed via preload
## (see git_status_flags.gd for why).
extends RefCounted

const GitStatusFlags := preload("res://addons/gittydot/util/git_status_flags.gd")

const COLOR_ADDED := Color(0.55, 0.85, 0.55)
const COLOR_MODIFIED := Color(0.92, 0.78, 0.45)
const COLOR_DELETED := Color(0.92, 0.5, 0.5)
const COLOR_RENAMED := Color(0.55, 0.75, 0.95)
const COLOR_TYPECHANGE := Color(0.8, 0.6, 0.9)
const COLOR_UNTRACKED := Color(0.65, 0.65, 0.68)
const COLOR_DEFAULT := Color(0.85, 0.85, 0.88)


## Single-letter status code, preferring the worktree side since that's
## what the Changes list shows.
static func status_letter(status: int) -> String:
	if status & GitStatusFlags.WT_DELETED or status & GitStatusFlags.INDEX_DELETED:
		return "D"
	if status & GitStatusFlags.WT_NEW:
		return "?" # git's own mark for untracked; "U" means unmerged
	if status & GitStatusFlags.INDEX_NEW:
		return "A"
	if status & GitStatusFlags.WT_RENAMED or status & GitStatusFlags.INDEX_RENAMED:
		return "R"
	if status & GitStatusFlags.WT_TYPECHANGE or status & GitStatusFlags.INDEX_TYPECHANGE:
		return "T"
	if status & GitStatusFlags.WT_MODIFIED or status & GitStatusFlags.INDEX_MODIFIED:
		return "M"
	return "?"


static func status_color(status: int) -> Color:
	match status_letter(status):
		"A":
			return COLOR_ADDED
		"M":
			return COLOR_MODIFIED
		"D":
			return COLOR_DELETED
		"R":
			return COLOR_RENAMED
		"T":
			return COLOR_TYPECHANGE
		"?":
			return COLOR_UNTRACKED
		_:
			return COLOR_DEFAULT


## Used by GitRepo.get_commit_files() — a per-commit delta code (A/M/D/R/C/T),
## separate from the status bitmask above, so it gets its own mapping.
const DELTA_ADDED := 1
const DELTA_DELETED := 2
const DELTA_MODIFIED := 3
const DELTA_RENAMED := 4
const DELTA_COPIED := 5
const DELTA_TYPECHANGE := 8


static func delta_letter(delta_status: int) -> String:
	match delta_status:
		DELTA_ADDED:
			return "A"
		DELTA_DELETED:
			return "D"
		DELTA_MODIFIED:
			return "M"
		DELTA_RENAMED:
			return "R"
		DELTA_COPIED:
			return "C"
		DELTA_TYPECHANGE:
			return "T"
		_:
			return "?"


static func delta_color(delta_status: int) -> Color:
	match delta_letter(delta_status):
		"A":
			return COLOR_ADDED
		"M":
			return COLOR_MODIFIED
		"D":
			return COLOR_DELETED
		"R", "C":
			return COLOR_RENAMED
		"T":
			return COLOR_TYPECHANGE
		_:
			return COLOR_DEFAULT
