class_name DialogueLogLine
extends DialogueLabel
## One line in the dialogue log. It types out like a normal DialogueLabel, but
## it can show the speaker name before the text ("THE FOG — ...") and wrap the
## text in the speaker's style (font, effects).
##
## The plugin counts [wait], [speed] and inline [do] by visible letters. The
## name adds letters in front, so set_prefix() moves those positions by the
## same number. Then they happen at the correct place in the text.

## BBCode put before the line text. Empty for the narrator.
var _prefix: String = ""
## BBCode around the line text (the speaker style).
var _style_open: String = ""
var _style_close: String = ""


## Call this BEFORE you set dialogue_line.
## visible_length is the number of letters the prefix shows on screen.
func setup(prefix: String, visible_length: int, style_open: String, style_close: String) -> void:
	_prefix = prefix
	_style_open = style_open
	_style_close = style_close
	_offset = visible_length


var _offset: int = 0


func _update_text() -> void:
	if not is_instance_valid(dialogue_line):
		text = ""
		return
	if _offset > 0 and not dialogue_line.has_meta(&"log_offset_done"):
		_shift_positions(dialogue_line, _offset)
		dialogue_line.set_meta(&"log_offset_done", true)
	text = _prefix + _style_open + dialogue_line.text + _style_close


static func _shift_positions(line: DialogueLine, offset: int) -> void:
	var speeds: Dictionary = {}
	for index: int in line.speeds:
		speeds[index + offset] = line.speeds[index]
	line.speeds = speeds
	for mutation: Array in line.inline_mutations:
		mutation[0] += offset
