## Character edits and ordered line pairing for native script-editor decorations.
extends RefCounted

const MAX_CELLS := 65536


static func edits(old: String, current: String) -> Array:
	var prefix := 0
	var limit := mini(old.length(), current.length())
	while prefix < limit and old[prefix] == current[prefix]:
		prefix += 1
	var suffix := 0
	while suffix < limit - prefix and old[old.length() - suffix - 1] == current[current.length() - suffix - 1]:
		suffix += 1
	var a := old.substr(prefix, old.length() - prefix - suffix)
	var b := current.substr(prefix, current.length() - prefix - suffix)
	if a.is_empty() and b.is_empty():
		return []
	if a.is_empty() or b.is_empty() or a.length() * b.length() > MAX_CELLS:
		return [_edit(prefix, a.length(), prefix, b.length())]
	var cols := b.length() + 1
	var table := PackedInt32Array()
	table.resize((a.length() + 1) * cols)
	for x in range(a.length() - 1, -1, -1):
		for y in range(b.length() - 1, -1, -1):
			table[x * cols + y] = table[(x + 1) * cols + y + 1] + 1 if a[x] == b[y] else maxi(table[(x + 1) * cols + y], table[x * cols + y + 1])
	var result := []
	var x := 0
	var y := 0
	while x < a.length() or y < b.length():
		if x < a.length() and y < b.length() and a[x] == b[y]:
			x += 1
			y += 1
			continue
		var start_x := x
		var start_y := y
		while x < a.length() or y < b.length():
			if x < a.length() and y < b.length() and a[x] == b[y]:
				break
			if y >= b.length() or (x < a.length() and table[(x + 1) * cols + y] >= table[x * cols + y + 1]):
				x += 1
			else:
				y += 1
		result.append(_edit(prefix + start_x, x - start_x, prefix + start_y, y - start_y))
	return result


static func _edit(old_start: int, old_length: int, new_start: int, new_length: int) -> Dictionary:
	return {"old_start": old_start, "old_length": old_length, "new_start": new_start, "new_length": new_length}


static func build(old: PackedStringArray, current: PackedStringArray) -> Dictionary:
	var before := []
	var after := []
	for text in old:
		before.append({"text": text, "kind": "removed", "spans": []})
	for text in current:
		after.append({"text": text, "kind": "added", "spans": []})
	for pair: Vector2i in _pair_lines(old, current):
		before[pair.x]["kind"] = "modified_old"
		after[pair.y]["kind"] = "modified"
		for change: Dictionary in edits(old[pair.x], current[pair.y]):
			if change["old_length"] > 0:
				before[pair.x]["spans"].append({"start": change["old_start"], "length": change["old_length"], "kind": "replaced"})
			if change["new_length"] > 0:
				after[pair.y]["spans"].append({"start": change["new_start"], "length": change["new_length"], "kind": "inserted" if change["old_length"] == 0 else "replaced"})
			elif change["old_length"] > 0 and not current[pair.y].is_empty():
				# A character removed inside a modified line has no new glyph. Mark
				# the surviving character at that boundary so the change stays visible.
				after[pair.y]["spans"].append({"start": maxi(0, change["new_start"] - 1), "length": 1, "kind": "replaced"})
	return {"old": before, "new": after}


static func _pair_lines(a: PackedStringArray, b: PackedStringArray) -> Array:
	var pairs := []
	if a.size() * b.size() > MAX_CELLS:
		for i in mini(a.size(), b.size()):
			pairs.append(Vector2i(i, i))
		return pairs
	var cols := b.size() + 1
	var table := PackedFloat32Array()
	table.resize((a.size() + 1) * cols)
	for x in range(a.size(), -1, -1):
		for y in range(b.size(), -1, -1):
			if x == a.size():
				table[x * cols + y] = b.size() - y
			elif y == b.size():
				table[x * cols + y] = a.size() - x
			else:
				table[x * cols + y] = minf(_pair_cost(a[x], b[y]) + table[(x + 1) * cols + y + 1], minf(1 + table[(x + 1) * cols + y], 1 + table[x * cols + y + 1]))
	var x := 0
	var y := 0
	while x < a.size() and y < b.size():
		var paired := _pair_cost(a[x], b[y]) + table[(x + 1) * cols + y + 1]
		if paired <= minf(1 + table[(x + 1) * cols + y], 1 + table[x * cols + y + 1]) + 0.0001:
			pairs.append(Vector2i(x, y))
			x += 1
			y += 1
		elif table[(x + 1) * cols + y] < table[x * cols + y + 1]:
			x += 1
		else:
			y += 1
	return pairs


static func _pair_cost(a: String, b: String) -> float:
	var limit := mini(a.length(), b.length())
	var prefix := 0
	while prefix < limit and a[prefix] == b[prefix]:
		prefix += 1
	var suffix := 0
	while suffix < limit - prefix and a[a.length() - suffix - 1] == b[b.length() - suffix - 1]:
		suffix += 1
	return 2.0 - 1.8 * float(prefix + suffix) / maxi(1, maxi(a.length(), b.length()))
