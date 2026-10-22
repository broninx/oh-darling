## Bitmask for GitRepo.get_status() entries, mirroring libgit2's git_status_t
## (git2/status.h) — kept as the shared encoding even though the CLI backend
## computes it itself now. No class_name: internal helper, addressed via
## preload (matches this project's no-global-namespace-pollution convention).
extends RefCounted

const INDEX_NEW := 1 << 0
const INDEX_MODIFIED := 1 << 1
const INDEX_DELETED := 1 << 2
const INDEX_RENAMED := 1 << 3
const INDEX_TYPECHANGE := 1 << 4

const WT_NEW := 1 << 7
const WT_MODIFIED := 1 << 8
const WT_DELETED := 1 << 9
const WT_TYPECHANGE := 1 << 10
const WT_RENAMED := 1 << 11
const WT_UNREADABLE := 1 << 12

const IGNORED := 1 << 14
const CONFLICTED := 1 << 15

const INDEX_MASK := INDEX_NEW | INDEX_MODIFIED | INDEX_DELETED | INDEX_RENAMED | INDEX_TYPECHANGE
const WT_MASK := WT_NEW | WT_MODIFIED | WT_DELETED | WT_TYPECHANGE | WT_RENAMED | WT_UNREADABLE


static func is_staged(status: int) -> bool:
	return (status & INDEX_MASK) != 0


static func is_unstaged(status: int) -> bool:
	# WT_NEW is untracked, not an unstaged change to a tracked file.
	return (status & WT_MASK) != 0 and (status & WT_NEW) == 0


static func is_untracked(status: int) -> bool:
	return (status & WT_NEW) != 0


## Short label for the dominant change kind, preferring the worktree side
## since that's what the Changes list shows.
static func short_label(status: int) -> String:
	if status & WT_DELETED or status & INDEX_DELETED:
		return "Deleted"
	if status & WT_NEW:
		return "Untracked"
	if status & INDEX_NEW:
		return "Added"
	if status & WT_RENAMED or status & INDEX_RENAMED:
		return "Renamed"
	if status & WT_TYPECHANGE or status & INDEX_TYPECHANGE:
		return "Type changed"
	if status & WT_MODIFIED or status & INDEX_MODIFIED:
		return "Modified"
	return "Changed"
