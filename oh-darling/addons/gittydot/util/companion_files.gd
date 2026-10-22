## Godot's sidecar files (.uid next to scripts/shaders, .import next to assets) belong to the file they sit next to and should be staged, reverted, stashed and ignored with it.
## No class_name: internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const SUFFIXES := [".uid", ".import"]


## "player.gd.uid" -> "player.gd"; "" when path isn't a sidecar file.
static func owner_of(path: String) -> String:
	for suffix in SUFFIXES:
		if path.ends_with(suffix) and path.length() > suffix.length() and not path.get_file().begins_with(suffix):
			return path.trim_suffix(suffix)
	return ""


## paths plus the sidecars of each that are in changed (a collection of changed repo paths: Dictionary keys or Array), in order, without duplicates.
static func with_companions(paths: Array, changed: Variant) -> Array:
	var out: Array = []
	for path in paths:
		if not out.has(path):
			out.append(path)
		for suffix in SUFFIXES:
			var companion: String = path + suffix
			if changed.has(companion) and not out.has(companion):
				out.append(companion)
	return out
