# ==============================================================================
#  DEBUG PANEL  (task T01)
# ==============================================================================
#  TASK
#    Let every programmer test their work without playing the game:
#    change the mood, move the clock, and see the hidden state.
#
#  HOW TO USE
#    - F1 shows or hides the panel.
#    - It exists ONLY in debug builds. In an export build it removes itself.
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.mood_changed, EmotionManager.distortion_changed
#    - TimeManager.time_changed
#    - GameManager.state_changed
#
#  MUST NOT
#    - Hold game logic or game data. It only calls the PUBLIC API of the
#      managers and shows what they say.
#    - Read the managers in _process(). It updates on signals (README rule).
#
#  NOTE
#    The panel shows the hidden energy number. This is allowed ONLY here,
#    because it is a debug tool. The real game UI never shows it.
# ==============================================================================
extends CanvasLayer
## Debug overlay. F1 toggles it. Debug builds only.

const ENERGY_STEP: float = 20.0
const PANEL_WIDTH: float = 280.0

@export var start_visible: bool = false

var _panel: PanelContainer
var _info: Label
var _slider: HSlider


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100  # Above all other UI.
	process_mode = Node.PROCESS_MODE_ALWAYS  # Still works when the game is paused.
	_build_ui()
	_panel.visible = start_visible
	# Signals to listen to
	EmotionManager.mood_changed.connect(_on_manager_changed)
	EmotionManager.distortion_changed.connect(_on_manager_changed)
	TimeManager.time_changed.connect(_on_manager_changed)
	GameManager.state_changed.connect(_on_manager_changed)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _is_toggle_event(event):
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


# Use the Input Map action "debug_toggle" if it exists. If not, use F1 directly.
func _is_toggle_event(event: InputEvent) -> bool:
	if InputMap.has_action("debug_toggle"):
		return event.is_action_pressed("debug_toggle")
	return event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()  # Stops mouse clicks: the world below does not get them.
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size.x = PANEL_WIDTH
	add_child(_panel)

	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	_add_label(box, "DEBUG (F1 to hide)")
	_info = _add_label(box, "")

	_add_label(box, "Energy (hidden emotion value)")
	_slider = HSlider.new()
	_slider.min_value = EmotionManager.AXIS_MIN
	_slider.max_value = EmotionManager.AXIS_MAX
	_slider.step = 1.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(_on_slider_changed)
	box.add_child(_slider)

	var emotion_row := _add_row(box)
	_add_button(emotion_row, "-%d" % ENERGY_STEP, _shift_energy.bind(-ENERGY_STEP))
	_add_button(emotion_row, "+%d" % ENERGY_STEP, _shift_energy.bind(ENERGY_STEP))
	_add_button(emotion_row, "Reset emotion", _reset_emotion)

	_add_label(box, "Time")
	var time_row := _add_row(box)
	_add_button(time_row, "+10 min", _advance_time.bind(10))
	_add_button(time_row, "+60 min", _advance_time.bind(60))
	_add_button(time_row, "Reset time", _reset_time)


func _add_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _add_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	# No keyboard focus: Space or Enter must not press a button during play.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# --- Actions (only calls to the public API) -----------------------------------

# TODO, temporarily only put functions for shifting energy, should have one
# for each hidden emotion value
func _shift_energy(amount: float) -> void:
	EmotionManager.shift("energy", amount)
	_refresh()


func _on_slider_changed(value: float) -> void:
	# The slider sets an exact value. EmotionManager only has shift(),
	# so we shift by the difference.
	_shift_energy(value - EmotionManager.debug_get_axis("energy"))


func _reset_emotion() -> void:
	EmotionManager.reset()
	_refresh()


func _advance_time(minutes: int) -> void:
	TimeManager.advance(minutes)
	_refresh()


func _reset_time() -> void:
	TimeManager.reset()
	_refresh()


# --- Display ------------------------------------------------------------------

# All four manager signals have two arguments, so one function can listen to all.
func _on_manager_changed(_new_value: Variant, _old_value: Variant) -> void:
	_refresh()


func _refresh() -> void:
	var energy: float = EmotionManager.debug_get_axis("energy")
	_info.text = "State: %s\nMood: %s\nDistortion: %d\nEnergy: %d\nDay %d, %s" % [
		GameManager.State.keys()[GameManager.state],
		EmotionManager.get_mood(),
		EmotionManager.get_distortion(),
		roundi(energy),
		TimeManager.day,
		TimeManager.get_time_string(),
	]
	_slider.set_value_no_signal(energy)  # No signal, so no loop.
