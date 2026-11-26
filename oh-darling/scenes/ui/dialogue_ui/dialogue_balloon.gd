# ==============================================================================
#  DIALOGUE BALLOON  (task T02) - first simple version, to refine later
# ==============================================================================
#  TASK
#    Show a dialogue in the style of Disco Elysium:
#      - A dark panel on the right side of the screen.
#      - A log that scrolls. Old lines stay, dimmed. New lines type out.
#      - "SPEAKER — text". The narrator has no name. Each inner voice has its
#        own colour (speaker_colors).
#      - Numbered choices. Keys 1 to 9 choose too. A locked choice (its
#        [if ... /] is false) is shown grey and cannot be chosen.
#      - The chosen line goes into the log.
#      - A line with no choices waits for CONTINUE (click, Space or Enter).
#
#  HOW IT OPENS
#    GameManager.start_dialogue() -> DialogueManager.show_dialogue_balloon(),
#    which uses the project setting dialogue_manager/runtime/balloon_path.
#    The plugin calls start() on this scene.
#
#  RULES
#    - It stops its own input, so a click on it does not reach the world
#      (the full-screen Blocker and _unhandled_input).
#    - The "pause" action passes through, so the pause menu still works.
#    - When the dialogue ends it calls GameManager.end_dialogue(). That does
#      nothing if GameManager already got the plugin signal dialogue_ended.
#    - It does NOT call GameManager.on_choice_made() (that saves, and the
#      prototype does not save).
#
#  TODO (later)
#    - A theme that follows the mood.
#    - Portraits, sounds, a nicer font.
# ==============================================================================
extends CanvasLayer
## Disco Elysium style dialogue panel: a scrolling log with numbered choices.


## Colour of the name, for each speaker. Other speakers use default_speaker_color.
@export var speaker_colors: Dictionary[String, Color] = {}
@export var default_speaker_color: Color = Color(0.95, 0.8, 0.5)
## BBCode opening tags put around every line of a speaker (font, effects).
## The closing tags are made automatically. Example for "The Fog":
## [font=res://art/fonts/voice_fog.tres][wave amp=10 freq=1.5]
@export var speaker_styles: Dictionary[String, String] = {}
## Custom text effects that writers can use as BBCode tags ([glitch]...).
@export var custom_effects: Array[RichTextEffect] = [GlitchTextEffect.new()]
## Extra space (pixels) before a line that starts a title (~ title) again, for
## example "=> letter" back to a menu. The player sees that a branch ended.
@export var title_gap: int = 48
## Moving effects stop when a line becomes old, so the log calms down and only
## the newest line moves.
@export var calm_old_lines: bool = true
const _MOVING_TAGS: String = "shake|wave|tornado|pulse|rainbow|glitch|fade"
## Option colours. An option can set its own colour with BBCode.
@export var response_color: Color = Color(0.88, 0.45, 0.25)
@export var locked_color: Color = Color(0.38, 0.38, 0.38)
## Colour multiplier while the mouse is over an option.
@export var hover_tint: Color = Color(1.35, 1.3, 1.2)
## Colour of the line that the player chose, when it goes into the log.
@export var chosen_color: Color = Color(0.6, 0.55, 0.5)
## Transparency of old lines in the log (1 = no change).
@export_range(0.1, 1.0, 0.05) var old_line_alpha: float = 0.55
## Seconds for each typed character (0 = show the line at once).
@export_range(0.0, 0.1, 0.005) var seconds_per_step: float = 0.01
@export var next_action: StringName = &"ui_accept"
@export var skip_action: StringName = &"ui_cancel"

var _resource: DialogueResource
var _game_states: Array = []
var _line: DialogueLine
var _typing_label: DialogueLabel
var _waiting_for_continue: bool = false
var _title_line_ids: Dictionary = {}  # line id -> true

@onready var _panel: Control = %Panel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _log: VBoxContainer = %Log
@onready var _responses: VBoxContainer = %Responses
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	_continue_button.hide()
	_continue_button.pressed.connect(_continue)
	_panel.gui_input.connect(_on_panel_gui_input)
	# Keep the newest line in view while the log grows.
	_scroll.get_v_scroll_bar().changed.connect(_scroll_to_bottom)


## Called by the Dialogue Manager plugin.
func start(resource: DialogueResource, cue: String = "", extra_game_states: Array = []) -> void:
	_resource = resource
	_game_states = [self] + extra_game_states
	_collect_title_lines()
	_show_line(await _resource.get_next_dialogue_line(cue, _game_states))


func _show_line(line: DialogueLine) -> void:
	if line == null:
		_close()
		return
	_line = line
	_waiting_for_continue = false
	_continue_button.hide()
	_clear_responses()
	_dim_old_lines()

	# The plugin returns ids like "<file key>@58|<trail>". Keep only "58".
	var local_id: String = line.id.get_slice("|", 0).get_slice("@", line.id.count("@"))
	if _log.get_child_count() > 0 and _title_line_ids.has(local_id):
		var gap := Control.new()
		gap.custom_minimum_size.y = title_gap
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_log.add_child(gap)

	if not line.text.is_empty():
		var label: DialogueLabel = _make_log_line(line)
		_typing_label = label
		label.type_out()
		if label.is_typing:
			await label.finished_typing
		_typing_label = null

	if line != _line:
		return  # Another line started while this one was typing.
	if line.responses.size() > 0:
		_show_responses(line.responses)
	elif not line.time.is_empty():
		# [next=auto] or [next=2]: go on without CONTINUE (a voice that interrupts).
		var seconds: float = line.text.length() * 0.02 if line.time == "auto" else line.time.to_float()
		await get_tree().create_timer(seconds).timeout
		if line == _line:
			_show_line(await _resource.get_next_dialogue_line(line.next_id, _game_states))
	else:
		_waiting_for_continue = true
		_continue_button.show()


# Find the first visible line of each title. A title can start with "do" lines
# or a goto, so follow those until a real line.
func _collect_title_lines() -> void:
	_title_line_ids.clear()
	for cue: String in _resource.cues:
		var id: String = str(_resource.cues[cue])
		for i: int in 32:
			var data: Dictionary = _resource.lines.get(id, {})
			if data.get("type", "") in ["mutation", "goto"]:
				id = str(data.get("next_id", ""))
			else:
				break
		_title_line_ids[id] = true


func _make_log_line(line: DialogueLine) -> DialogueLogLine:
	var label := DialogueLogLine.new()
	_setup_rich_label(label)
	label.seconds_per_step = seconds_per_step
	label.skip_action = skip_action
	var style_open: String = speaker_styles.get(line.character, "")
	var visible_length: int = 0 if line.character.is_empty() else line.character.length() + 3
	label.setup(_speaker_prefix(line.character), visible_length, style_open, _closing_tags(style_open))
	label.dialogue_line = line
	_log.add_child(label)
	return label


func _speaker_prefix(character: String) -> String:
	if character.is_empty():
		return ""
	var color: Color = speaker_colors.get(character, default_speaker_color)
	return "[color=#%s][b]%s[/b][/color] — " % [color.to_html(false), character.to_upper()]


# "[font=x][wave amp=3]" -> "[/wave][/font]"
static func _closing_tags(open_tags: String) -> String:
	var regex := RegEx.create_from_string("\\[([a-z_]+)")
	var closing: String = ""
	for found: RegExMatch in regex.search_all(open_tags):
		closing = "[/%s]" % found.get_string(1) + closing
	return closing


# Remove the moving effects from an old line, so only the newest line moves.
func _calm(label: RichTextLabel) -> void:
	if label.has_meta(&"calm"):
		return
	label.set_meta(&"calm", true)
	var regex := RegEx.create_from_string("\\[/?(%s)[^\\]]*\\]" % _MOVING_TAGS)
	label.text = regex.sub(label.text, "", true)
	label.visible_characters = -1


func _show_responses(responses: Array) -> void:
	for i: int in responses.size():
		var response: DialogueResponse = responses[i]
		# A RichTextLabel, not a Button, so the option text can use BBCode
		# (fonts, colours, [shake], [glitch]...) written in the .dialogue file.
		var item := RichTextLabel.new()
		_setup_rich_label(item)
		item.set_meta(&"response", response)
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		if response.is_allowed:
			item.add_theme_color_override(&"default_color", response_color)
			item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			item.text = "%d. %s" % [i + 1, response.text]
			item.mouse_entered.connect(func() -> void: item.modulate = hover_tint)
			item.mouse_exited.connect(func() -> void: item.modulate = Color.WHITE)
			item.gui_input.connect(_on_response_gui_input.bind(response))
		else:
			# Locked: plain grey text, no effects, so it reveals nothing.
			item.add_theme_color_override(&"default_color", locked_color)
			item.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
			item.text = "%d. %s" % [i + 1, _strip_bbcode(response.text)]
		_responses.add_child(item)


func _on_response_gui_input(event: InputEvent, response: DialogueResponse) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_choose(response)


static func _strip_bbcode(text: String) -> String:
	return RegEx.create_from_string("\\[[^\\]]*\\]").sub(text, "", true)


func _choose(response: DialogueResponse) -> void:
	if not response.is_allowed:
		return
	_clear_responses()
	_dim_old_lines()
	var chosen := RichTextLabel.new()
	_setup_rich_label(chosen)
	chosen.text = "[color=#%s]— %s[/color]" % [chosen_color.to_html(false), response.text]
	_log.add_child(chosen)
	_show_line(await _resource.get_next_dialogue_line(response.next_id, _game_states))


func _continue() -> void:
	if not _waiting_for_continue:
		return
	_waiting_for_continue = false
	_continue_button.hide()
	_show_line(await _resource.get_next_dialogue_line(_line.next_id, _game_states))


func _close() -> void:
	GameManager.end_dialogue()
	queue_free()


func _setup_rich_label(label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for effect: RichTextEffect in custom_effects:
		label.install_effect(effect)
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # The panel gets the clicks.
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _dim_old_lines() -> void:
	for child: Node in _log.get_children():
		(child as CanvasItem).modulate.a = old_line_alpha
		if calm_old_lines and child is RichTextLabel and child != _typing_label:
			_calm(child)


func _clear_responses() -> void:
	for child: Node in _responses.get_children():
		_responses.remove_child(child)
		child.queue_free()


func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# A click on the panel skips the typing, or continues.
func _on_panel_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_skip_or_continue()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("pause") and event.is_action("pause"):
		return  # Let the pause menu work.
	get_viewport().set_input_as_handled()  # Nothing reaches the world.

	if event.is_action_pressed(next_action) or event.is_action_pressed(skip_action):
		_skip_or_continue()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var index: int = key.physical_keycode - KEY_1
		if index >= 0 and index < 9 and index < _responses.get_child_count():
			var response: DialogueResponse = _responses.get_child(index).get_meta(&"response")
			if response.is_allowed:
				_choose(response)


func _skip_or_continue() -> void:
	if is_instance_valid(_typing_label) and _typing_label.is_typing:
		_typing_label.skip_typing()
	elif _waiting_for_continue:
		_continue()
