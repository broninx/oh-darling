# ==============================================================================
#  CONDITION GATE  (component)
# ==============================================================================
#  TASK
#    Show, hide or lock ONE object when the world changes. The conditions are
#    plain Inspector fields. All conditions must be true (AND).
#
#  CONDITIONS (a field with its default value is ignored)
#    - min_day / max_day        : day range. max_day 0 = no limit.
#    - from_hour / to_hour      : hour range. 0 to 24 = any time.
#                                 A range across midnight is valid (22 to 4).
#    - moods                    : tick boxes. No box ticked = any mood.
#    - min_distortion           : 0 to 3.
#    - required_flags           : story flags (T15). See NOTE below.
#    - invert                   : reverse the result.
#
#  EFFECTS (set only what you need)
#    - hide_target    : a Node3D. Visible if the result is true. If false, it
#                       is hidden AND disabled, so it cannot be clicked.
#    - interaction    : an InteractionComponent. If false, it is blocked.
#    - locked_title   : if set, the interaction is NOT blocked. A click starts
#                       this dialogue title instead.
#    - signal changed : for any other effect. Your script listens to it.
#
#  WHEN IT CHECKS
#    - At once, when the scene loads.
#    - After that, only in EXPLORATION. A change during a dialogue waits until
#      the dialogue ends (GDD: Staging Rule). The debug panel works in
#      EXPLORATION, so its changes apply at once.
#
#  SIGNALS IT SENDS
#    - changed(met)   : when the result changes, and once at start.
#
#  SIGNALS IT LISTENS TO
#    - TimeManager.time_changed
#    - EmotionManager.mood_changed, EmotionManager.distortion_changed
#    - GameManager.state_changed
#    - SaveManager.game_loaded
#    - StoryFlags.flag_changed (only if StoryFlags exists)
#
#  PUBLIC API
#    - is_met                   : the last result (read only)
#    - check_now()              : check and apply at once. Ignores the staging rule.
#    - _extra_check() -> bool   : override it in a child script for a rule
#                                 that the fields cannot express.
#
#  NOTE (story flags)
#    StoryFlags (T15) does not exist yet. Until it exists, a gate with
#    required_flags is always false and prints one warning. Other gates work.
#
#  MUST NOT
#    - Save anything. The result is computed from the clock, the mood and the
#      flags, so after a load the gate only checks again.
#    - Change game data. It only reads the managers.
# ==============================================================================
@tool
class_name ConditionGate
extends Node
## Shows, hides or locks one object when the day, hour, mood, Distortion or flags change.

## Sent when the result changes, and once when the scene loads.
signal changed(met: bool)

const MOOD_NAMES: Array[String] = ["fog", "overcast", "clear", "bright", "storm"]

@export_group("Conditions")
## First day, included.
@export_range(1, 99) var min_day: int = 1
## Last day, included. 0 means no limit.
@export_range(0, 99) var max_day: int = 0
## Start hour, included. 0 to 24 means any time. 22 to 4 crosses midnight.
@export_range(0, 24) var from_hour: int = 0
## End hour, not included.
@export_range(0, 24) var to_hour: int = 24
## The moods where the gate is true. No box ticked means any mood.
@export_flags("Fog", "Overcast", "Clear", "Bright", "Storm") var moods: int = 0
## The lowest Distortion level where the gate is true.
@export_range(0, 3) var min_distortion: int = 0
## All these story flags must be set (T15).
@export var required_flags: Array[StringName] = []
## Reverse the result: true when the conditions are NOT met.
@export var invert: bool = false

@export_group("Effects")
## Shown when true. Hidden and disabled when false.
@export var hide_target: Node3D:
	set(value):
		hide_target = value
		update_configuration_warnings()
## Blocked when false (or uses Locked Title, if it is set).
@export var interaction: InteractionComponent:
	set(value):
		interaction = value
		update_configuration_warnings()
## Optional. When false, a click starts this title and the object is NOT blocked.
@export var locked_title: String = "":
	set(value):
		locked_title = value
		update_configuration_warnings()

## The last result. Read only.
var is_met: bool = false

var _source: StringName
var _applied_once: bool = false
var _target_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _title_swapped: bool = false
var _open_title: String = ""
var _warned_no_flags: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Keep working if a parent is disabled (for example, the gate is inside
	# its own hide_target).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_source = StringName("gate_%d" % get_instance_id())
	if hide_target != null:
		_target_mode = hide_target.process_mode

	TimeManager.time_changed.connect(_on_world_changed)
	EmotionManager.mood_changed.connect(_on_world_changed)
	EmotionManager.distortion_changed.connect(_on_world_changed)
	GameManager.state_changed.connect(_on_world_changed)
	SaveManager.game_loaded.connect(_on_world_changed)
	var flags: Node = _get_story_flags()
	if flags != null and flags.has_signal(&"flag_changed"):
		flags.connect(&"flag_changed", _on_world_changed)

	# Deferred, so the targets have finished their own _ready().
	_apply.call_deferred()


## Check and apply at once. This ignores the staging rule.
func check_now() -> void:
	_apply()


## Override this in a child script for a rule that the fields cannot express.
## It is checked after all the fields.
func _extra_check() -> bool:
	return true


# One function for all signals. They have 0 to 2 arguments.
func _on_world_changed(_a: Variant = null, _b: Variant = null) -> void:
	if GameManager.state == GameManager.State.EXPLORATION:
		_apply()


func _apply() -> void:
	var met: bool = _check() != invert
	if _applied_once and met == is_met:
		return
	_applied_once = true
	is_met = met
	_apply_visual(met)
	_apply_interaction(met)
	changed.emit(met)


func _check() -> bool:
	var day: int = TimeManager.day
	if day < min_day:
		return false
	if max_day > 0 and day > max_day:
		return false
	if not TimeManager.is_between(from_hour, to_hour):
		return false
	if moods != 0:
		var index: int = MOOD_NAMES.find(EmotionManager.get_mood())
		if index == -1 or (moods & (1 << index)) == 0:
			return false
	if EmotionManager.get_distortion() < min_distortion:
		return false
	if not _has_all_flags():
		return false
	return _extra_check()


func _has_all_flags() -> bool:
	if required_flags.is_empty():
		return true
	var flags: Node = _get_story_flags()
	if flags == null:
		if not _warned_no_flags:
			_warned_no_flags = true
			push_warning("ConditionGate %s: StoryFlags does not exist yet, so this gate is false." % get_path())
		return false
	for flag: StringName in required_flags:
		if not flags.call(&"has_flag", flag):
			return false
	return true


func _apply_visual(met: bool) -> void:
	if hide_target == null:
		return
	hide_target.visible = met
	hide_target.process_mode = _target_mode if met else Node.PROCESS_MODE_DISABLED


func _apply_interaction(met: bool) -> void:
	if interaction == null:
		return
	if locked_title.is_empty():
		if met:
			interaction.unblock(_source)
		else:
			interaction.block(_source)
		return
	# Locked title: swap the title, do not block.
	if not met and not _title_swapped:
		_open_title = interaction.dialogue_title
		interaction.dialogue_title = locked_title
		_title_swapped = true
	elif met and _title_swapped:
		interaction.dialogue_title = _open_title
		_title_swapped = false


func _get_story_flags() -> Node:
	return get_node_or_null(^"/root/StoryFlags")


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if hide_target == null and interaction == null:
		warnings.append("No effect is set. The gate only sends the signal 'changed'.")
	if not locked_title.is_empty() and interaction == null:
		warnings.append("'Locked Title' needs 'Interaction'.")
	if from_hour == to_hour:
		warnings.append("'From Hour' and 'To Hour' are the same, so the gate is never true. Use 0 and 24 for any time.")
	if max_day > 0 and max_day < min_day:
		warnings.append("'Max Day' is smaller than 'Min Day', so the gate is never true.")
	return warnings
