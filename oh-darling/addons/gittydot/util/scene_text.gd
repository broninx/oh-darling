## Reads Godot's text scene/resource format (.tscn / .tres) into nodes, resources and connections, and compares two versions node by node.
## No class_name: internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

## Header attributes that Godot rewrites without any real change.
const NOISE_ATTRIBUTES := ["unique_id", "uid", "load_steps", "format"]


## {"nodes": {path: {"type", "props": {key: value}, "line"}}, "node_order": [paths], "ext": {id: {"type", "path"}},
##  "sub": {id: {"type", "props"}}, "sub_order": [ids], "connections": [text], "sections": [{"tag", "attrs", "props", "start", "end"}]}.
## Node paths are "Root", "Root/Child"...; a .tres's [resource] section is the node "Resource". ExtResource("id") in values is resolved to the file's path, so renumbered ids don't show as changes.
static func parse(text: String) -> Dictionary:
	var sections := parse_sections(text)
	var result := { "nodes": {}, "node_order": [], "ext": {}, "sub": {}, "sub_order": [], "connections": [], "sections": sections }
	for s in sections:
		if s["tag"] == "ext_resource":
			result["ext"][s["attrs"].get("id", "")] = { "type": s["attrs"].get("type", ""), "path": s["attrs"].get("path", "") }
	var root := ""
	for s in sections:
		var attrs: Dictionary = s["attrs"]
		var props := {}
		for key in s["props"]:
			props[key] = _resolve(s["props"][key], result["ext"])
		match s["tag"]:
			"sub_resource":
				var id: String = attrs.get("id", "")
				result["sub"][id] = { "type": attrs.get("type", ""), "props": props }
				result["sub_order"].append(id)
			"resource":
				result["nodes"]["Resource"] = { "type": "Resource", "props": props, "line": s["start"] }
				result["node_order"].append("Resource")
			"node":
				var name: String = attrs.get("name", "")
				var path := name
				if not attrs.has("parent"):
					root = name
				elif attrs["parent"] == ".":
					path = root + "/" + name
				else:
					path = root + "/" + String(attrs["parent"]) + "/" + name
				for key in attrs:
					if key not in ["name", "parent"] and key not in NOISE_ATTRIBUTES:
						props["(%s)" % key] = _resolve(attrs[key], result["ext"])
				var type: String = attrs.get("type", "")
				if type.is_empty() and attrs.has("instance"):
					type = _resolve(attrs["instance"], result["ext"]).get_file()
				result["nodes"][path] = { "type": type, "props": props, "line": s["start"] }
				result["node_order"].append(path)
			"connection":
				result["connections"].append("%s.%s → %s() on %s" % [_node_label(attrs.get("from", ""), root), attrs.get("signal", ""), attrs.get("method", ""), _node_label(attrs.get("to", ""), root)]
						+ (" (flags=%s)" % attrs["flags"] if attrs.has("flags") else "") + (" binds %s" % attrs["binds"] if attrs.has("binds") else ""))
	return result


## Every [section] with its header attributes and property lines: [{"tag", "attrs": {key: value, plain strings unquoted}, "raw_attrs": {key: value as written},
## "props": {key: value as written}, "header": the [..] line, "start", "end" (0-based line range, end exclusive)}].
static func parse_sections(text: String) -> Array:
	var sections: Array = []
	var lines := text.split("\n")
	var current: Dictionary = {}
	var i := 0
	while i < lines.size():
		var line := lines[i]
		if line.begins_with("[") and not _open_value(line):
			if not current.is_empty():
				current["end"] = i
				sections.append(current)
			current = { "tag": "", "attrs": {}, "raw_attrs": {}, "props": {}, "header": line.strip_edges(), "start": i, "end": i + 1 }
			var header := line.strip_edges().trim_prefix("[").trim_suffix("]")
			var space := header.find(" ")
			current["tag"] = header if space == -1 else header.substr(0, space)
			current["raw_attrs"] = _parse_attributes(header.substr(space + 1) if space != -1 else "", true)
			current["attrs"] = _parse_attributes(header.substr(space + 1) if space != -1 else "")
			i += 1
			continue
		var eq := line.find(" = ")
		if eq > 0 and not current.is_empty():
			var key := line.substr(0, eq)
			var value := line.substr(eq + 3)
			# Values (arrays, dictionaries, multi-line strings) may run over several lines.
			while _open_value(value) and i + 1 < lines.size():
				i += 1
				value += "\n" + lines[i]
			current["props"][key] = value
		i += 1
	if not current.is_empty():
		current["end"] = lines.size()
		sections.append(current)
	return sections


## Node-level differences between two versions: {"nodes": [{"path", "type", "status": "added"|"removed"|"changed", "props": [{"key", "old", "new"}]}],
## "resources": [same shape, path = "Type id"], "connections_added": [text], "connections_removed": [text]}. Unchanged nodes are left out.
static func diff(old_text: String, new_text: String) -> Dictionary:
	var old := parse(old_text)
	var new := parse(new_text)
	var result := { "nodes": [], "resources": [], "connections_added": [], "connections_removed": [] }
	for path in new["node_order"]:
		var n: Dictionary = new["nodes"][path]
		if not old["nodes"].has(path):
			result["nodes"].append({ "path": path, "type": n["type"], "status": "added", "props": _prop_changes({}, n["props"]) })
		else:
			var changes := _prop_changes(old["nodes"][path]["props"], n["props"])
			if not changes.is_empty():
				result["nodes"].append({ "path": path, "type": n["type"], "status": "changed", "props": changes })
	for path in old["node_order"]:
		if not new["nodes"].has(path):
			result["nodes"].append({ "path": path, "type": old["nodes"][path]["type"], "status": "removed", "props": _prop_changes(old["nodes"][path]["props"], {}) })
	for id in new["sub_order"]:
		var r: Dictionary = new["sub"][id]
		var label := "%s  %s" % [r["type"], id]
		if not old["sub"].has(id):
			result["resources"].append({ "path": label, "type": r["type"], "status": "added", "props": _prop_changes({}, r["props"]) })
		else:
			var changes := _prop_changes(old["sub"][id]["props"], r["props"])
			if not changes.is_empty():
				result["resources"].append({ "path": label, "type": r["type"], "status": "changed", "props": changes })
	for id in old["sub_order"]:
		if not new["sub"].has(id):
			result["resources"].append({ "path": "%s  %s" % [old["sub"][id]["type"], id], "type": old["sub"][id]["type"], "status": "removed", "props": [] })
	var old_ext := _ext_paths(old)
	var new_ext := _ext_paths(new)
	for p in new_ext:
		if not old_ext.has(p):
			result["resources"].append({ "path": p, "type": new_ext[p], "status": "added", "props": [] })
	for p in old_ext:
		if not new_ext.has(p):
			result["resources"].append({ "path": p, "type": old_ext[p], "status": "removed", "props": [] })
	for c in new["connections"]:
		if not old["connections"].has(c):
			result["connections_added"].append(c)
	for c in old["connections"]:
		if not new["connections"].has(c):
			result["connections_removed"].append(c)
	return result


## project.godot, export_presets.cfg, .import files and other ConfigFile-format text.
static func is_config_file(path: String) -> bool:
	return path.get_extension().to_lower() in ["godot", "cfg", "import"]


## ConfigFile text as {section: {key: value as written}}; keys before the first [section] go under "".
static func parse_config(text: String) -> Dictionary:
	var sections := { "": {} }
	var current := ""
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i].strip_edges(false, true)
		i += 1
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2)
			sections[current] = {}
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var value := line.substr(eq + 1)
		# Values (input events, arrays, dictionaries) may run over several lines.
		while _open_value(value) and i < lines.size():
			value += "\n" + lines[i]
			i += 1
		sections[current][line.substr(0, eq)] = value
	if sections[""].is_empty():
		sections.erase("")
	return sections


## Setting-level differences in diff()'s shape: each changed [section] is a "node" whose "props" are its changed keys.
static func config_diff(old_text: String, new_text: String) -> Dictionary:
	var old := parse_config(old_text)
	var new := parse_config(new_text)
	var result := { "nodes": [], "resources": [], "connections_added": [], "connections_removed": [] }
	for section in new:
		var label: String = section if not section.is_empty() else "(top of file)"
		var new_props := _readable_config(section, new[section])
		if not old.has(section):
			result["nodes"].append({ "path": "[%s]" % label, "type": "", "status": "added", "props": _prop_changes({}, new_props) })
			continue
		var changes := _prop_changes(_readable_config(section, old[section]), new_props)
		if not changes.is_empty():
			result["nodes"].append({ "path": "[%s]" % label, "type": "", "status": "changed", "props": changes })
	for section in old:
		if not new.has(section):
			result["nodes"].append({ "path": "[%s]" % (section if not section.is_empty() else "(top of file)"), "type": "", "status": "removed", "props": [] })
	return result


## Input actions' Object(InputEvent…) dumps shortened to "deadzone 0.2: W, Ctrl+S, Joypad button 0"; other values as written.
static func _readable_config(section: String, values: Dictionary) -> Dictionary:
	if section != "input":
		return values
	var out := {}
	for key in values:
		var value: String = values[key]
		if not value.contains("\"events\""):
			out[key] = value
			continue
		var events := PackedStringArray()
		var chunks := value.split("Object(")
		for chunk_index in range(1, chunks.size()):
			events.append(_input_event_label(chunks[chunk_index]))
		var deadzone := _int_field(value, "\"deadzone\":", true)
		out[key] = "deadzone %s: %s" % [deadzone, ", ".join(events) if not events.is_empty() else "no events"]
	return out


static func _input_event_label(chunk: String) -> String:
	var type := chunk.get_slice(",", 0)
	match type:
		"InputEventKey":
			var code := _int_field(chunk, "\"physical_keycode\":").to_int()
			if code == 0:
				code = _int_field(chunk, "\"keycode\":").to_int()
			var mods := ""
			for mod in ["ctrl", "shift", "alt", "meta"]:
				if chunk.contains("\"%s_pressed\":true" % mod):
					mods += mod.capitalize() + "+"
			return mods + OS.get_keycode_string(code)
		"InputEventMouseButton":
			return "Mouse button %s" % _int_field(chunk, "\"button_index\":")
		"InputEventJoypadButton":
			return "Joypad button %s" % _int_field(chunk, "\"button_index\":")
		"InputEventJoypadMotion":
			var positive := not _int_field(chunk, "\"axis_value\":", true).begins_with("-")
			return "Joypad axis %s%s" % [_int_field(chunk, "\"axis\":"), "+" if positive else "−"]
	return type.trim_prefix("InputEvent")


## The number after field in text ("" if missing); decimals only when allow_decimal.
static func _int_field(text: String, field: String, allow_decimal := false) -> String:
	var at := text.find(field)
	if at == -1:
		return ""
	var i := at + field.length()
	while i < text.length() and text[i] == " ":
		i += 1
	var digits := ""
	while i < text.length() and (text[i].is_valid_int() or text[i] == "-" or (allow_decimal and text[i] == ".")):
		digits += text[i]
		i += 1
	return digits


## A connection's "." / "A/B" as the node path shown elsewhere ("Root", "Root/A/B").
static func _node_label(path: String, root: String) -> String:
	return root if path == "." else root + "/" + path


static func is_scene_file(path: String) -> bool:
	return path.get_extension().to_lower() in ["tscn", "tres"]


static func _ext_paths(parsed: Dictionary) -> Dictionary:
	var paths := {}
	for id in parsed["ext"]:
		paths[parsed["ext"][id]["path"]] = parsed["ext"][id]["type"]
	return paths


static func _prop_changes(old_props: Dictionary, new_props: Dictionary) -> Array:
	var changes: Array = []
	for key in new_props:
		if old_props.get(key) != new_props[key]:
			changes.append({ "key": key, "old": old_props.get(key, null), "new": new_props[key] })
	for key in old_props:
		if not new_props.has(key):
			changes.append({ "key": key, "old": old_props[key], "new": null })
	return changes


## ExtResource("1_ab") -> ExtResource("res://player.gd"), using this version's ids (ext: {id: {"path"}}).
static func _resolve(value: String, ext: Dictionary) -> String:
	var from := value.find("ExtResource(\"")
	while from != -1:
		var id_start := from + 13
		var id_end := value.find("\"", id_start)
		if id_end == -1:
			break
		var id := value.substr(id_start, id_end - id_start)
		if ext.has(id):
			value = value.substr(0, id_start) + String(ext[id]["path"]) + value.substr(id_end)
		from = value.find("ExtResource(\"", id_start)
	return value


## key=value pairs of a section header; plain strings lose their quotes unless keep_quotes.
static func _parse_attributes(text: String, keep_quotes := false) -> Dictionary:
	var attrs := {}
	var i := 0
	while i < text.length():
		while i < text.length() and text[i] == " ":
			i += 1
		var eq := text.find("=", i)
		if eq == -1:
			break
		var key := text.substr(i, eq - i).strip_edges()
		var j := eq + 1
		var depth := 0
		var in_string := false
		while j < text.length():
			var c := text[j]
			if in_string:
				if c == "\\":
					j += 1
				elif c == "\"":
					in_string = false
			elif c == "\"":
				in_string = true
			elif c in "([{":
				depth += 1
			elif c in ")]}":
				depth -= 1
			elif c == " " and depth == 0:
				break
			j += 1
		var value := text.substr(eq + 1, j - eq - 1)
		if not keep_quotes and value.length() >= 2 and value.begins_with("\"") and value.ends_with("\"") and value.count("\"") == 2:
			value = value.substr(1, value.length() - 2)
		attrs[key] = value
		i = j + 1
	return attrs


## True while value has an unclosed string or bracket, i.e. it continues on the next line.
static func _open_value(value: String) -> bool:
	var depth := 0
	var in_string := false
	var i := 0
	while i < value.length():
		var c := value[i]
		if in_string:
			if c == "\\":
				i += 1
			elif c == "\"":
				in_string = false
		elif c == "\"":
			in_string = true
		elif c in "([{":
			depth += 1
		elif c in ")]}":
			depth -= 1
		i += 1
	return in_string or depth > 0
