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
#    do EmotionManager.shift("energy", 15)
#
#  MUST NOT
#    - Show numbers in the UI. The player reads the world, not a stat bar.
#    - Call other managers. Others listen to mood_changed.
#    - Put thresholds anywhere else. Dialogue files ask for the mood NAME only.
#      If we change a threshold, we change it here, in one place.
#
#  TODO (team decision)
#    - Now there is one axis ("energy", from -100 to 100). The GDD says "a set
#      of hidden values". Add more axes to _axes if the writers need them
#      (for example "paranoia"), and change _calculate_*() to use them.
#    - Move thresholds to MoodPreset .tres files (data/moods/).
#    - Distortion now comes from the axis only.
# ==============================================================================
extends Node
## Hidden emotion values. Sends [signal mood_changed] and [signal distortion_changed].

signal mood_changed(new_mood: String, old_mood: String)
signal distortion_changed(new_level: int, old_level: int)

const MOOD_FOG: String = "fog"
const MOOD_OVERCAST: String = "overcast"
const MOOD_CLEAR: String = "clear"
const MOOD_BRIGHT: String = "bright"
const MOOD_STORM: String = "storm"

const AXIS_MIN: float = -100.0
const AXIS_MAX: float = 100.0

var _axes: Dictionary = { "energy": 0.0 }
var _mood: String = MOOD_CLEAR
var _distortion: int = 0


func get_mood() -> String:
	return _mood


func get_distortion() -> int:
	return _distortion


## Change one hidden value by [param amount]. The result is clamped.
func shift(axis: String, amount: float) -> void:
	if not _axes.has(axis):
		push_error("EmotionManager.shift(): unknown axis '%s'." % axis)
		return
	_axes[axis] = clampf(_axes[axis] + amount, AXIS_MIN, AXIS_MAX)
	_recalculate()


func reset() -> void:
	_axes = { "energy": 0.0 }
	_recalculate(true)


func get_save_data() -> Dictionary:
	return { "axes": _axes.duplicate() }


func load_save_data(data: Dictionary) -> void:
	var saved: Dictionary = data.get("axes", { })
	for axis: String in _axes:
		_axes[axis] = clampf(float(saved.get(axis, 0.0)), AXIS_MIN, AXIS_MAX)
	_recalculate(true) # Force the signals, so all listeners get the loaded state.


func _recalculate(force_emit: bool = false) -> void:
	var energy: float = _axes["energy"]
	var old_mood: String = _mood
	var old_distortion: int = _distortion
	_mood = _calculate_mood(energy)
	_distortion = _calculate_distortion(energy)
	if force_emit or _mood != old_mood:
		mood_changed.emit(_mood, old_mood)
	if force_emit or _distortion != old_distortion:
		distortion_changed.emit(_distortion, old_distortion)


# Placeholder thresholds. Tune them with the writers.
func _calculate_mood(energy: float) -> String:
	if energy < -60.0:
		return MOOD_FOG
	if energy < -20.0:
		return MOOD_OVERCAST
	if energy <= 20.0:
		return MOOD_CLEAR
	if energy <= 60.0:
		return MOOD_BRIGHT
	return MOOD_STORM


# GDD: Distortion exists only in Fog and Storm.
func _calculate_distortion(energy: float) -> int:
	var distance: float = absf(energy)
	if distance >= 95.0:
		return 3
	if distance >= 80.0:
		return 2
	if distance >= 60.0:
		return 1
	return 0
