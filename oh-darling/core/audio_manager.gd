# ==============================================================================
#  AUDIO MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Play the layered soundtrack (GDD: "Procedural Audio"). All stems play at
#    the same time, in a loop. The mood decides the VOLUME of each stem.
#    The player hears the mood change before they understand it.
#
#  OWNS
#    - One AudioStreamPlayer for each stem
#    - The table MOOD_VOLUMES_DB (how loud each stem is in each mood)
#
#  SIGNALS IT SENDS
#    - none
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.mood_changed
#
#  PUBLIC API
#    - start_music() / stop_music()
#
#  RULES FOR THE AUDIO FILES
#    - Put stems in res://audio/music/stems/xxx/ as <name>.ogg
#    - Related stems must have the SAME length and the SAME tempo.
#      If not, they drift apart and the layers stop matching.
#    - Turn on "Loop" in the import settings of each file.
#
#  MUST NOT
#    - Read EmotionManager values in _process(). Use the signal.
#    - Change the mood. It only reacts.
#
#  TODO
#    - Use real stem names. The four names below are placeholders.
#    - Add play_sfx().
#    - Add a "Music" audio bus in the Audio tab.
# ==============================================================================
extends Node
## Layered music. Volume of each stem follows the mood.

const STEM_DIR: String = "res://audio/music/stems/"
const STEM_NAMES: Array[String] = ["base", "pad", "rhythm", "lead"]
const SILENT_DB: float = -80.0
const FADE_SECONDS: float = 2.0

# Volume in dB for each stem, for each mood. Placeholder values.
const MOOD_VOLUMES_DB: Dictionary = {
	"fog": { "base": 0.0, "pad": -6.0, "rhythm": -80.0, "lead": -80.0 },
	"overcast": { "base": 0.0, "pad": -3.0, "rhythm": -12.0, "lead": -80.0 },
	"clear": { "base": 0.0, "pad": -6.0, "rhythm": -6.0, "lead": -80.0 },
	"bright": { "base": 0.0, "pad": -3.0, "rhythm": 0.0, "lead": -6.0 },
	"storm": { "base": 0.0, "pad": 0.0, "rhythm": 0.0, "lead": 0.0 },
}

var _players: Dictionary = { } # stem name -> AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	_create_players()
	EmotionManager.mood_changed.connect(_on_mood_changed)
	_apply_mood(EmotionManager.get_mood(), true)
	start_music()


func start_music() -> void:
	# Start all stems in the same frame, so they stay in sync.
	for player: AudioStreamPlayer in _players.values():
		if not player.playing:
			player.play()


func stop_music() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()


func _create_players() -> void:
	for stem_name in STEM_NAMES:
		var path: String = "%s%s.ogg" % [STEM_DIR, stem_name]
		if not ResourceLoader.exists(path):
			continue # The file is not made yet. Skip it, no error.
		var player := AudioStreamPlayer.new()
		player.stream = load(path)
		player.bus = &"Music"
		player.volume_db = SILENT_DB
		add_child(player)
		_players[stem_name] = player


func _on_mood_changed(new_mood: String, _old_mood: String) -> void:
	_apply_mood(new_mood, false)


func _apply_mood(mood: String, instant: bool) -> void:
	var volumes: Dictionary = MOOD_VOLUMES_DB.get(mood, { })
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for stem_name: String in _players:
		var target_db: float = volumes.get(stem_name, SILENT_DB)
		var player: AudioStreamPlayer = _players[stem_name]
		if instant:
			player.volume_db = target_db
		else:
			_tween.tween_property(player, "volume_db", target_db, FADE_SECONDS)
