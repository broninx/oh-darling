## Three-way merge of Godot's text scenes/resources node by node: changes on only one side merge on their own, and only a property (or node) both sides changed differently needs a choice.
## ExtResource ids are compared by the file they point to and renumbered in the result, so both sides adding resources doesn't clash.
## No class_name: internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const SceneText := preload("res://addons/gittydot/util/scene_text.gd")

## Header attributes Godot rewrites on every save; the merge takes ours instead of asking.
const NOISE_KEYS := ["(unique_id)", "(uid)", "(load_steps)", "(format)"]


## -> {"ok": false, "error"} if a version can't be read, else {"ok": true, "merge": state for result_text(), "conflicts": [{"id", "section", "label", "prop", "ours", "theirs"}], "auto": [text]}.
## A conflict's "ours"/"theirs" is a value, or null for "deleted"; "prop" is "" for a whole node deleted on one side and changed on the other.
static func merge(base_text: String, ours_text: String, theirs_text: String) -> Dictionary:
	var base := _sections(base_text)
	var ours := _sections(ours_text)
	var theirs := _sections(theirs_text)
	if ours["order"].is_empty() or theirs["order"].is_empty():
		return { "ok": false, "error": "One side of the conflict isn't a readable Godot scene/resource." }
	var merged := {}
	var conflicts: Array = []
	var auto: Array = []
	var keys: Array = ours["order"].duplicate()
	for key in theirs["order"]:
		if not keys.has(key):
			keys.append(key)
	for key in base["order"]:
		if not keys.has(key):
			keys.append(key)
	# Node key -> [kept section, side that kept it], for deletions that might strand the other side's new children.
	var deleted := {}
	for key in keys:
		var b: Variant = base["by_key"].get(key)
		var o: Variant = ours["by_key"].get(key)
		var t: Variant = theirs["by_key"].get(key)
		var label := _label(key)
		if o == null and t == null:
			continue
		if o == null or t == null:
			var present: Dictionary = o if o != null else t
			var side := "ours" if o != null else "theirs"
			if b == null:
				merged[key] = present.duplicate(true)
				auto.append("%s added %s" % [side.capitalize(), label])
			elif _props(present) == _props(b):
				if key.begins_with("node:"):
					deleted[key] = [present, side]
				else:
					auto.append("%s deleted %s" % ["Theirs" if side == "ours" else "Ours", label])
			else:
				merged[key] = present.duplicate(true)
				conflicts.append({ "id": conflicts.size(), "section": key, "label": label, "prop": "",
						"ours": "(changed)" if o != null else null, "theirs": "(changed)" if t != null else null })
			continue
		var section: Dictionary = o.duplicate(true)
		section["props"] = {}
		var base_props: Dictionary = _props(b) if b != null else {}
		var prop_keys: Array = o["props"].keys()
		for k in t["props"]:
			if not prop_keys.has(k):
				prop_keys.append(k)
		for k in base_props:
			if not prop_keys.has(k):
				prop_keys.append(k)
		for k in prop_keys:
			var bv: Variant = base_props.get(k)
			var ov: Variant = o["props"].get(k)
			var tv: Variant = t["props"].get(k)
			var value: Variant
			if ov == tv:
				value = ov
			elif k == "(id)" and key.begins_with("ext:"):
				value = ov # ids are renumbered when writing, so differing ones aren't a conflict
			elif ov == bv:
				value = tv
				auto.append("Theirs changed %s: %s" % [label, _prop_label(k)])
			elif tv == bv or NOISE_KEYS.has(k):
				value = ov
				if not NOISE_KEYS.has(k):
					auto.append("Ours changed %s: %s" % [label, _prop_label(k)])
			else:
				value = ov
				conflicts.append({ "id": conflicts.size(), "section": key, "label": label, "prop": k, "ours": ov, "theirs": tv })
			if value != null:
				section["props"][k] = value
		merged[key] = section
	# Deepest first, so a restored node counts as a child when looking at its parent.
	var deleted_keys := deleted.keys()
	deleted_keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for key in deleted_keys:
		var side: String = deleted[key][1]
		var label := _label(key)
		if merged.keys().any(func(k: String) -> bool: return k.begins_with(key + "/")):
			# Deleting it would leave the other side's new nodes without a parent: let the user choose, and a delete takes them along.
			merged[key] = deleted[key][0].duplicate(true)
			var kept := "(kept, has new child nodes)"
			conflicts.append({ "id": conflicts.size(), "section": key, "label": label, "prop": "",
					"ours": kept if side == "ours" else null, "theirs": kept if side == "theirs" else null })
		else:
			auto.append("%s deleted %s" % ["Theirs" if side == "ours" else "Ours", label])
	return { "ok": true, "conflicts": conflicts, "auto": auto,
			"merge": { "merged": merged, "ours": ours, "theirs": theirs, "ours_order": ours["order"], "theirs_order": theirs["order"] } }


## The merged file text, with choices: {conflict id: "ours"|"theirs"} (unchosen = ours).
static func result_text(result: Dictionary, choices: Dictionary) -> String:
	var state: Dictionary = result["merge"]
	var merged: Dictionary = state["merged"].duplicate(true)
	for c in result["conflicts"]:
		var side: String = choices.get(c["id"], "ours")
		var chosen: Dictionary = state[side]["by_key"]
		if c["prop"].is_empty():
			if chosen.has(c["section"]):
				merged[c["section"]] = chosen[c["section"]].duplicate(true)
			else:
				merged.erase(c["section"])
				# Its child nodes go with it.
				for key in merged.keys().filter(func(k: String) -> bool: return k.begins_with(c["section"] + "/")):
					merged.erase(key)
		elif merged.has(c["section"]):
			var value: Variant = c[side]
			if value == null:
				merged[c["section"]]["props"].erase(c["prop"])
			else:
				merged[c["section"]]["props"][c["prop"]] = value
	return _write(merged, _order(merged.keys(), state["ours_order"], state["theirs_order"]))


## Section key -> {"tag", "props": {key: value}, "raw"} for one version; header attributes are folded into props as "(name)" so they merge like properties.
static func _sections(text: String) -> Dictionary:
	var by_key := {}
	var order: Array = []
	var ext := {}
	var sections := SceneText.parse_sections(text)
	for s in sections:
		if s["tag"] == "ext_resource":
			ext[s["attrs"].get("id", "")] = { "path": s["attrs"].get("path", "") }
	var root := ""
	for s in sections:
		var tag: String = s["tag"]
		var attrs: Dictionary = s["attrs"]
		var key := ""
		match tag:
			"gd_scene", "gd_resource": key = "@header"
			"ext_resource": key = "ext:" + String(attrs.get("path", ""))
			"sub_resource": key = "sub:" + String(attrs.get("id", ""))
			"resource": key = "resource"
			"node":
				if not attrs.has("parent"):
					root = attrs.get("name", "")
					key = "node:" + root
				else:
					key = "node:" + root + ("" if attrs["parent"] == "." else "/" + String(attrs["parent"])) + "/" + String(attrs.get("name", ""))
			_: key = "raw:" + String(s["header"]) # connections, [editable]: identical header = same section
		var props := {}
		for k in s["raw_attrs"]:
			props["(%s)" % k] = SceneText._resolve(s["raw_attrs"][k], ext)
		for k in s["props"]:
			props[k] = SceneText._resolve(s["props"][k], ext)
		if tag.begins_with("raw") or key.begins_with("raw:"):
			props = {}
		by_key[key] = { "tag": tag, "props": props, "header": s["header"] }
		order.append(key)
	return { "by_key": by_key, "order": order }


static func _props(section: Dictionary) -> Dictionary:
	return section["props"]


static func _label(key: String) -> String:
	if key.begins_with("node:"):
		return key.substr(5)
	if key.begins_with("ext:"):
		return key.substr(4)
	if key.begins_with("sub:"):
		return "resource " + key.substr(4)
	if key.begins_with("raw:"):
		return key.substr(4)
	return key


static func _prop_label(key: String) -> String:
	return key.trim_prefix("(").trim_suffix(")") if key.begins_with("(") else key


## Ours' order, with each section only theirs has placed right after the section before it in theirs.
static func _order(keys: Array, ours_order: Array, theirs_order: Array) -> Array:
	var order: Array = ours_order.filter(func(k: String) -> bool: return keys.has(k))
	var previous := ""
	for key in theirs_order:
		if keys.has(key) and not order.has(key):
			var at := order.find(previous) + 1 if not previous.is_empty() else _first_of_tag(order, key)
			order.insert(at, key)
		if order.has(key):
			previous = key
	for key in keys:
		if not order.has(key):
			order.append(key)
	return order


static func _first_of_tag(order: Array, key: String) -> int:
	var prefix := key.get_slice(":", 0)
	for i in order.size():
		if String(order[i]).get_slice(":", 0) == prefix:
			return i
	return order.size()


## Writes sections back in Godot's layout, renumbering ExtResource ids so both sides' resources fit together.
static func _write(merged: Dictionary, order: Array) -> String:
	var ids := {}
	var used := {}
	for key in order:
		if key.begins_with("ext:"):
			var id := String(merged[key]["props"].get("(id)", "")).trim_prefix("\"").trim_suffix("\"")
			while id.is_empty() or used.has(id):
				id = "%d_%s" % [used.size() + 1, str(randi() % 100000).pad_zeros(5)]
			used[id] = true
			ids[key.substr(4)] = id
			merged[key]["props"]["(id)"] = "\"%s\"" % id
	var sub_count := order.filter(func(k: String) -> bool: return k.begins_with("sub:")).size()
	var out := PackedStringArray()
	var previous_tag := ""
	for key in order:
		var section: Dictionary = merged[key]
		var tag: String = section["tag"]
		var compact: bool = tag == previous_tag and (tag == "ext_resource" or key.begins_with("raw:"))
		if not out.is_empty() and not compact:
			out.append("")
		if key.begins_with("raw:"):
			out.append(section["header"])
			previous_tag = tag
			continue
		var attrs := PackedStringArray()
		var body := PackedStringArray()
		for k in section["props"]:
			var value := _unresolve(String(section["props"][k]), ids)
			if k.begins_with("("):
				var name: String = _prop_label(k)
				if name == "load_steps":
					value = str(ids.size() + sub_count + 1)
				attrs.append("%s=%s" % [name, value])
			else:
				body.append("%s = %s" % [k, value])
		out.append("[%s%s]" % [tag, (" " + " ".join(attrs)) if not attrs.is_empty() else ""])
		out.append_array(body)
		previous_tag = tag
	return "\n".join(out) + "\n"


## ExtResource("res://player.gd") -> ExtResource("<its id in the merged file>").
static func _unresolve(value: String, ids: Dictionary) -> String:
	var from := value.find("ExtResource(\"")
	while from != -1:
		var start := from + 13
		var end := value.find("\"", start)
		if end == -1:
			break
		var path := value.substr(start, end - start)
		if ids.has(path):
			value = value.substr(0, start) + String(ids[path]) + value.substr(end)
		from = value.find("ExtResource(\"", start)
	return value
