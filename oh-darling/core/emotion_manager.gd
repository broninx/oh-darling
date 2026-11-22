# ==============================================================================
#  EMOTION MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Hold the HIDDEN emotional values of the protagonist. Turn them into a
#    mood (fog, overcast, clear, bright, storm) and a Distortion level (0 to 3).
#    This is the most important script in the game: almost all systems
#    (visuals, audio, dialogue, NPCs) react to what it says.
#
#  OWNS (no other script may change these values)
#    - _axes       : the hidden numbers. The player NEVER sees them.
#    - _mood       : the current mood, calculated from the axes
#    - _distortion : the current Distortion level, calculated from the axes
#
#  SIGNALS IT SENDS
#    - mood_changed(new_mood, old_mood)
#    - distortion_changed(new_level, old_level)
#    Both signals are sent ONLY when the value really changes.
#
#  SIGNALS IT LISTENS TO
#    - none
#
#  PUBLIC API
#    - get_mood() -> String        : "fog" | "overcast" | "clear" | "bright" | "storm"
#    - get_distortion() -> int     : 0 to 3
#    - shift(axis, amount)         : change one hidden value
#    - get_save_data() / load_save_data(data) / reset()
#
#  HOW DIALOGUE FILES USE IT (wip)
#    [if EmotionManager.get_mood() == "storm"]
#    do EmotionManager.shift("energy", 0.15)
#
#  MUST NOT
#    - Show numbers in the UI. The player reads the world, not a stat bar.
#    - Call other managers. Others listen to mood_changed.
#    - Put thresholds anywhere else. Dialogue files ask for the mood NAME only.
#      If we change a threshold, we change it here, in one place.
#
#  TODO (team decision)
#    - Move thresholds to MoodPreset .tres files (data/moods/).
# ==============================================================================
extends Node

signal mood_changed(new_mood: String, old_mood: String)
signal distortion_changed(new_level: int, old_level: int)

const MOOD_FOG: String = "fog"
const MOOD_OVERCAST: String = "overcast"
const MOOD_CLEAR: String = "clear"
const MOOD_BRIGHT: String = "bright"
const MOOD_STORM: String = "storm"

const AXIS_MIN: float = -1.0
const AXIS_MAX: float = 1.0
const AXIS_CENTER: float = 0.0

## Hidden axes. They go from AXIS_MIN to AXIS_MAX, except POSITIVE_AXES (0 to 1).
## To add an axis, add its name here: start and reset() use this list.
const AXES: Array[String] = ["dereism", "energy", "paranoia", "self_perception"]

## Axes that go only from 0 to 1: they say "how much", not a side.
## The side (fog or storm) is given by the mood.
const POSITIVE_AXES: Array[String] = ["dereism", "paranoia"]

## Weights of the mental state formula.
const W_ENERGY: float = 0.5
const W_DEREISM: float = 0.35
const W_PARANOIA: float = 0.15


const CLEAR_MAX: float = 0.25
const OVERCAST_BRIGHT_MAX: float = 0.5
const FOG_STORM_MAX: float = 0.75
# From -0.75 to -1 and from 0.75 to 1: ECHO zone (still fog / storm for now).

var _axes: Dictionary = _default_axes()
var _mood: String = MOOD_CLEAR
var _distortion: int = 0
## Last side: -1 overcast / fog, +1 bright / storm. Negative at game start.
var _branch: int = -1


func get_mood() -> String:
	return _mood


func get_distortion() -> int:
	return _distortion


func shift(axis: String, amount: float) -> void:
	if not _axes.has(axis):
		push_error("EmotionManager.shift(): unknown axis '%s'." % axis)
		return
	_axes[axis] = clampf(_axes[axis] + amount, _axis_min(axis), AXIS_MAX)
	_recalculate()


func reset() -> void:
	_axes = _default_axes()
	_branch = -1
	_recalculate(true)


func get_save_data() -> Dictionary:
	return { "axes": _axes.duplicate() }


func load_save_data(data: Dictionary) -> void:
	var saved: Dictionary = data.get("axes", { })
	for axis: String in _axes:
		_axes[axis] = clampf(saved.get(axis, AXIS_CENTER), _axis_min(axis), AXIS_MAX)
	_recalculate(true) 


static func _default_axes() -> Dictionary:
	var axes: Dictionary = { }
	for axis: String in AXES:
		axes[axis] = 0.0
	return axes


# The lowest value an axis can have.
func _axis_min(axis: String) -> float:
	return 0.0 if axis in POSITIVE_AXES else AXIS_MIN


func _recalculate(force_emit: bool = false) -> void:
	var mental_state: float = _calculate_mental_state()
	var old_mood: String = _mood
	var old_distortion: int = _distortion
	_mood = _calculate_mood(mental_state)
	_distortion = _calculate_distortion()
	if force_emit or _mood != old_mood:
		mood_changed.emit(_mood, old_mood)
	if force_emit or _distortion != old_distortion:
		distortion_changed.emit(_distortion, old_distortion)


# THE FORMULA
# side = sign of (self_perception + energy), if 0 the last side
# intensity = W_ENERGY * side * e*|e| + W_DEREISM * d + W_PARANOIA * p^2, from 0 to 1
# mental = side * intensity
# Energy the same way as the side pushes, against it brakes.
func _calculate_mental_state() -> float:
	var energy: float = _axes["energy"]
	var direction: float = _axes["self_perception"] + energy
	if direction > 0.0:
		_branch = 1
	elif direction < 0.0:
		_branch = -1
	# direction == 0: keep the last side
	var paranoia: float = _axes["paranoia"]
	var intensity: float = clampf(
			W_ENERGY * _branch * energy * absf(energy)
			+ W_DEREISM * _axes["dereism"]
			+ W_PARANOIA * paranoia * paranoia,
			0.0, 1.0)
	return _branch * intensity


# The mental state chooses the mood. The sign says the side, the size how far.
func _calculate_mood(mental_state: float) -> String:
	var distance: float = absf(mental_state)
	if distance <= CLEAR_MAX:
		return MOOD_CLEAR
	if distance <= OVERCAST_BRIGHT_MAX:
		return MOOD_OVERCAST if mental_state < 0.0 else MOOD_BRIGHT
	if distance <= FOG_STORM_MAX:
		return MOOD_FOG if mental_state < 0.0 else MOOD_STORM
	# ECHO zone: the mood stays fog / storm for now.
	return MOOD_FOG if mental_state < 0.0 else MOOD_STORM


# Distortion comes from dereism (loss of contact with reality, 0 to 1),
# and exists only in fog and storm (GDD).
func _calculate_distortion() -> int:
	if _mood != MOOD_FOG and _mood != MOOD_STORM:
		return 0
	var dereism: float = _axes["dereism"]
	if dereism >= 0.75:
		return 3
	if dereism >= 0.5:
		return 2
	if dereism >= 0.25:
		return 1
	return 0


## Debug functions
## DEBUG ONLY. Used by the debug panel. Game code must not call this.
func debug_get_axis(axis: String) -> float:
	return _axes.get(axis, 0.0)


## DEBUG ONLY. Used by the debug panel. Game code must not call this.
func debug_get_mental_state() -> float:
	return _calculate_mental_state()
