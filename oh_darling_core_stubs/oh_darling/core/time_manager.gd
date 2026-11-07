# ==============================================================================
#  TIME MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Keep the game clock. The clock moves ONLY when a dialogue or a story
#    event asks for it (see GDD: "Time Management System"). Real time does
#    not move the clock. Walking does not move the clock.
#
#  OWNS (no other script may change these values)
#    - day      : the day number, starts at 1
#    - minutes  : minutes since 00:00 of the current day
#
#  SIGNALS IT SENDS
#    - time_changed(day, minutes) : after every change of the clock
#    - day_changed(day)           : when the clock passes midnight
#
#  SIGNALS IT LISTENS TO
#    - none
#
#  PUBLIC API
#    - advance(amount)            : move the clock forward (minutes)
#    - get_hour() / get_time_string()
#    - is_between(start, end)     : true if the hour is in a range (NPC schedules)
#    - get_save_data() / load_save_data(data) / reset()
#
#  HOW DIALOGUE FILES USE IT
#    do TimeManager.advance(20)
#
#  MUST NOT
#    - Call other managers. NPCs and the HUD listen to time_changed instead.
#    - Move backward in time. Every choice is permanent (no save-scumming).
#
#  TODO (team decision)
#    - What happens at midnight? Now the clock only goes to the next day.
#      The GDD says a day lasts 20 to 40 minutes of real play. Tune the
#      "minutes" cost of each dialogue so this is true.
# ==============================================================================
extends Node
## Game clock. Moves only through [method advance].

signal time_changed(day: int, minutes: int)
signal day_changed(day: int)

const MINUTES_PER_DAY: int = 24 * 60
const START_MINUTES: int = 7 * 60  # A new game starts at 07:00.

var day: int = 1
var minutes: int = START_MINUTES


## Move the clock forward. Only positive values are valid.
func advance(amount: int) -> void:
	if amount <= 0:
		push_warning("TimeManager.advance() needs a positive value. Got %d." % amount)
		return
	minutes += amount
	while minutes >= MINUTES_PER_DAY:
		minutes -= MINUTES_PER_DAY
		day += 1
		day_changed.emit(day)
	time_changed.emit(day, minutes)


func get_hour() -> int:
	return floori(minutes / 60.0)


func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), minutes % 60]


## True if the current hour is in [start_hour, end_hour).
## A range that crosses midnight is valid: is_between(22, 4).
func is_between(start_hour: int, end_hour: int) -> bool:
	var hour: int = get_hour()
	if start_hour <= end_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour


func reset() -> void:
	day = 1
	minutes = START_MINUTES
	time_changed.emit(day, minutes)


func get_save_data() -> Dictionary:
	return {"day": day, "minutes": minutes}


func load_save_data(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	minutes = int(data.get("minutes", START_MINUTES))
	time_changed.emit(day, minutes)
