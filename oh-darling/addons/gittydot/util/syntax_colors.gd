## Tiny line-by-line syntax highlighter for the diff view — not a full parser, just enough (comments, strings, numbers, keywords, types, calls, annotations) that a diff reads like the script editor. Colors come from the editor's own text theme. No class_name: internal helper, addressed via preload.
extends RefCounted

const GD_KEYWORDS := [
	"func", "var", "const", "class", "class_name", "extends", "signal", "static", "enum", "tool",
	"in", "not", "and", "or", "is", "as", "self", "super", "true", "false", "null", "void",
	"preload", "load", "await", "yield", "setget", "set", "get", "PI", "TAU", "INF", "NAN",
]
const GD_CONTROL := ["if", "elif", "else", "for", "while", "match", "return", "break", "continue", "pass", "when"]
const SHADER_KEYWORDS := [
	"shader_type", "render_mode", "uniform", "varying", "const", "void", "in", "out", "inout",
	"true", "false", "struct", "float", "int", "uint", "bool", "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4",
	"mat2", "mat3", "mat4", "sampler2D", "samplerCube", "group_uniforms", "global", "instance",
]
const SHADER_CONTROL := ["if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "discard"]
const C_LIKE_KEYWORDS := [
	"public", "private", "protected", "internal", "static", "readonly", "class", "struct", "interface",
	"namespace", "using", "new", "void", "var", "int", "float", "double", "bool", "string", "true", "false",
	"null", "this", "base", "override", "virtual", "partial", "async", "await", "const", "enum",
]
const C_LIKE_CONTROL := ["if", "else", "for", "foreach", "while", "do", "switch", "case", "default", "return", "break", "continue", "try", "catch", "finally", "throw"]

static var _colors: Dictionary = {}


## Language id for a path, or "" when it shouldn't be highlighted.
static func language_for(path: String) -> String:
	match path.get_extension().to_lower():
		"gd": return "gdscript"
		"gdshader", "gdshaderinc", "shader": return "shader"
		"cs": return "csharp"
		"tscn", "tres", "cfg", "godot", "import", "ini": return "ini"
		"json": return "json"
	return ""


## Array of [start: int, length: int, color: Color] spans covering the highlighted parts of text; anything not covered uses the row's default color.
static func spans(text: String, language: String) -> Array:
	if language.is_empty() or text.is_empty():
		return []
	_ensure_colors()
	if language == "ini":
		return _ini_spans(text)
	return _code_spans(text, language)


static func color(key: String) -> Color:
	_ensure_colors()
	return _colors.get(key, Color(0.8, 0.8, 0.8))


static func _ensure_colors() -> void:
	if not _colors.is_empty():
		return
	var defaults := {
		"keyword": Color(1.0, 0.44, 0.52),
		"control": Color(1.0, 0.55, 0.8),
		"type": Color(0.26, 1.0, 0.76),
		"comment": Color(0.8, 0.81, 0.82, 0.5),
		"string": Color(1.0, 0.93, 0.63),
		"number": Color(0.63, 1.0, 0.88),
		"function": Color(0.34, 0.7, 1.0),
		"annotation": Color(1.0, 0.7, 0.45),
		"symbol": Color(0.67, 0.79, 1.0),
		"section": Color(0.68, 0.85, 1.0),
	}
	var settings_keys := {
		"keyword": "text_editor/theme/highlighting/keyword_color",
		"control": "text_editor/theme/highlighting/control_flow_keyword_color",
		"type": "text_editor/theme/highlighting/engine_type_color",
		"comment": "text_editor/theme/highlighting/comment_color",
		"string": "text_editor/theme/highlighting/string_color",
		"number": "text_editor/theme/highlighting/number_color",
		"function": "text_editor/theme/highlighting/function_color",
		"annotation": "text_editor/theme/highlighting/gdscript/annotation_color",
		"symbol": "text_editor/theme/highlighting/symbol_color",
	}
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings() if Engine.is_editor_hint() else null
	for key in defaults:
		var c: Color = defaults[key]
		if editor_settings != null and settings_keys.has(key) and editor_settings.has_setting(settings_keys[key]):
			c = editor_settings.get_setting(settings_keys[key])
		_colors[key] = c


static func _code_spans(text: String, language: String) -> Array:
	var keywords: Array = GD_KEYWORDS
	var control: Array = GD_CONTROL
	var line_comment := "#"
	match language:
		"shader":
			keywords = SHADER_KEYWORDS
			control = SHADER_CONTROL
			line_comment = "//"
		"csharp":
			keywords = C_LIKE_KEYWORDS
			control = C_LIKE_CONTROL
			line_comment = "//"
		"json":
			keywords = ["true", "false", "null"]
			control = []
			line_comment = ""

	var result: Array = []
	var n := text.length()
	var i := 0
	while i < n:
		var ch := text[i]
		if not line_comment.is_empty() and text.substr(i, line_comment.length()) == line_comment:
			result.append([i, n - i, _colors["comment"]])
			break
		if ch == "\"" or ch == "'":
			var end := _string_end(text, i)
			result.append([i, end - i, _colors["string"]])
			i = end
			continue
		if ch == "@" and language == "gdscript":
			var end := _ident_end(text, i + 1)
			result.append([i, end - i, _colors["annotation"]])
			i = end
			continue
		if language == "gdscript" and (ch == "$" or ch == "%") and i + 1 < n and _is_ident_start(text[i + 1]):
			var end := _ident_end(text, i + 1)
			while end < n and text[end] == "/" and end + 1 < n and _is_ident_start(text[end + 1]):
				end = _ident_end(text, end + 1)
			result.append([i, end - i, _colors["string"]])
			i = end
			continue
		if ch.is_valid_int() or (ch == "." and i + 1 < n and text[i + 1].is_valid_int() and (i == 0 or not _is_ident_char(text[i - 1]))):
			if i == 0 or not _is_ident_char(text[i - 1]):
				var end := i + 1
				while end < n and (_is_ident_char(text[end]) or text[end] == "."):
					end += 1
				result.append([i, end - i, _colors["number"]])
				i = end
				continue
		if _is_ident_start(ch):
			var end := _ident_end(text, i)
			var word := text.substr(i, end - i)
			var next := end
			while next < n and text[next] == " ":
				next += 1
			if control.has(word):
				result.append([i, end - i, _colors["control"]])
			elif keywords.has(word):
				result.append([i, end - i, _colors["keyword"]])
			elif next < n and text[next] == "(":
				result.append([i, end - i, _colors["function"]])
			elif word[0] == word[0].to_upper() and word[0] != "_" and word.length() > 1:
				result.append([i, end - i, _colors["type"]])
			i = end
			continue
		i += 1
	return result


## .tscn/.tres/.cfg: [section headers], key = value, strings, numbers.
static func _ini_spans(text: String) -> Array:
	var stripped := text.strip_edges(true, false)
	var indent := text.length() - stripped.length()
	if stripped.begins_with(";") or stripped.begins_with("#"):
		return [[0, text.length(), _colors["comment"]]]
	if stripped.begins_with("["):
		var result: Array = [[indent, 1, _colors["section"]]]
		var i := indent + 1
		var end := _ident_end(text, i)
		result.append([i, end - i, _colors["keyword"]])
		result.append_array(_value_spans(text, end))
		return result
	var eq := text.find("=")
	if eq > 0:
		return [[indent, eq - indent, _colors["symbol"]]] + _value_spans(text, eq + 1)
	return _value_spans(text, 0)


static func _value_spans(text: String, from: int) -> Array:
	var result: Array = []
	var n := text.length()
	var i := from
	while i < n:
		var ch := text[i]
		if ch == "\"":
			var end := _string_end(text, i)
			result.append([i, end - i, _colors["string"]])
			i = end
			continue
		if (ch.is_valid_int() or ch == "-") and (i == 0 or not _is_ident_char(text[i - 1])):
			var end := i + 1
			while end < n and (text[end].is_valid_int() or text[end] == "." or text[end] == "e"):
				end += 1
			if end > i + 1 or ch.is_valid_int():
				result.append([i, end - i, _colors["number"]])
			i = end
			continue
		if _is_ident_start(ch):
			var end := _ident_end(text, i)
			if end < n and text[end] == "(":
				result.append([i, end - i, _colors["type"]])
			elif text.substr(i, end - i) in ["true", "false", "null"]:
				result.append([i, end - i, _colors["keyword"]])
			i = end
			continue
		i += 1
	return result


static func _string_end(text: String, start: int) -> int:
	var quote := text[start]
	var i := start + 1
	while i < text.length():
		if text[i] == "\\":
			i += 2
			continue
		if text[i] == quote:
			return i + 1
		i += 1
	return text.length()


static func _ident_end(text: String, start: int) -> int:
	var i := start
	while i < text.length() and _is_ident_char(text[i]):
		i += 1
	return i


static func _is_ident_start(ch: String) -> bool:
	return ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")


static func _is_ident_char(ch: String) -> bool:
	return _is_ident_start(ch) or (ch >= "0" and ch <= "9")
