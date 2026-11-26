# ==============================================================================
#  ENVIRONMENT CONTROLLER  (task T05)
# ==============================================================================
#  TASK
#    Change the weather of the 3D world when the mood changes:
#    fog, rain and lightning.
#    The weather of each mood is a MoodPreset file:
#    res://data/moods/<mood>.tres (fog.tres, overcast.tres, ...).
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.mood_changed
#
#  HOW TO USE
#    Add environment_controller.tscn to a level scene that has a
#    WorldEnvironment. Set "Rain Bounds" to the outside area of the level.
#    It changes the Environment of that WorldEnvironment while the game runs
#    (the .tscn file does not change).
#
#  CHILD NODES (in environment_controller.tscn)
#    - Rain (GPUParticles3D): it follows the player. The drop count, the
#      speed and the look are set on this node.
#    - Lightning (DirectionalLight3D): it is on only during a flash.
#    - LightningTimer (Timer): the time to the next flash.
#
#  RAIN AREA
#    Rain and lightning work only while the player is inside rain_bounds.
#    The interiors are outside it, so it does not rain in a room.
#
#  RULES
#    - It only reads the mood. It never changes emotion values.
#    - It does not use get_parent(). It finds the Environment in the World3D
#      and the player in the group "player".
#    - Fog, rain and lightning stay off when no mood needs them.
#
#  MUST NOT
#    - Put weather values in code. They are in the .tres files.
#    - Call create_tween() before it knows that it adds a tweener.
# ==============================================================================
extends Node3D
## Tweens fog and rain, and makes lightning, from the MoodPreset of the current mood.

## The folder of the MoodPreset files. Each file is named <mood>.tres.
@export_dir var presets_folder: String = "res://data/moods"
## The time of the change from one weather to the next.
@export_range(0.0, 5.0, 0.1, "suffix:s") var transition_time: float = 1.5

@export_group("Rain")
## The outside area (world space). Rain and lightning work only while the
## player is in it.
@export var rain_bounds: AABB = AABB(Vector3(-85, -20, -85), Vector3(175, 60, 175))
## The height of the rain emitter above the player.
@export_range(5.0, 40.0, 0.5, "suffix:m") var rain_height: float = 18.0

@onready var _rain: GPUParticles3D = $Rain
@onready var _lightning: DirectionalLight3D = $Lightning
@onready var _lightning_timer: Timer = $LightningTimer

var _environment: Environment
var _tween: Tween
var _flash_tween: Tween
var _presets: Dictionary = { }  # mood name -> MoodPreset
var _preset: MoodPreset  # The preset of the current mood.
var _player: Node3D
var _rain_on: bool = false  # A mood with rain is on, or its rain is fading out.


func _ready() -> void:
	set_process(false)  # Turned on only while it rains.
	_rain.emitting = false
	_rain.amount_ratio = 0.0
	_lightning.visible = false
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_on_lightning_timer_timeout)
	EmotionManager.mood_changed.connect(_on_mood_changed)
	# The WorldEnvironment gives its Environment to the World3D when it enters
	# the tree. Wait one frame, so the order of the nodes does not matter.
	_setup.call_deferred()


func _setup() -> void:
	_environment = get_world_3d().environment
	if _environment == null:
		push_warning("EnvironmentController: the scene has no WorldEnvironment.")
		return
	_apply(EmotionManager.get_mood(), true)  # First state: we missed the old signals.


func _on_mood_changed(new_mood: String, _old_mood: String) -> void:
	_apply(new_mood, false)


func _get_preset(mood: String) -> MoodPreset:
	if not _presets.has(mood):
		var path: String = "%s/%s.tres" % [presets_folder, mood]
		var preset: MoodPreset = null
		if ResourceLoader.exists(path):
			preset = load(path) as MoodPreset
		if preset == null:
			push_warning("EnvironmentController: no MoodPreset at '%s'." % path)
		_presets[mood] = preset
	return _presets[mood]


# --- Fog and rain ---------------------------------------------------------------

func _apply(mood: String, instant: bool) -> void:
	if _environment == null:
		return
	var preset: MoodPreset = _get_preset(mood)
	if preset == null:
		return
	_preset = preset
	if _tween != null and _tween.is_running():
		_tween.kill()
	var env: Environment = _environment
	# Turn a fog on before the fade in. It starts from 0, so it does not pop.
	if preset.fog_density > 0.0 and not env.fog_enabled:
		env.fog_density = 0.0
		env.fog_height_density = 0.0
		env.fog_enabled = true
	if preset.volumetric_fog_density > 0.0 and not env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.0
		env.volumetric_fog_enabled = true
	if preset.rain_amount > 0.0 and not _rain_on:
		_rain.amount_ratio = 0.0
		_rain_on = true
		_update_rain_position()
		set_process(true)
	_update_lightning_timer()
	if instant or transition_time <= 0.0:
		env.fog_density = preset.fog_density
		env.fog_light_color = preset.fog_light_color
		env.fog_height = preset.fog_height
		env.fog_height_density = preset.fog_height_density
		env.volumetric_fog_density = preset.volumetric_fog_density
		env.volumetric_fog_albedo = preset.volumetric_fog_albedo
		_rain.amount_ratio = preset.rain_amount
		_turn_off_unused(preset)
		return
	_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(env, "fog_density", preset.fog_density, transition_time)
	_tween.tween_property(env, "fog_light_color", preset.fog_light_color, transition_time)
	_tween.tween_property(env, "fog_height", preset.fog_height, transition_time)
	_tween.tween_property(env, "fog_height_density", preset.fog_height_density, transition_time)
	_tween.tween_property(env, "volumetric_fog_density", preset.volumetric_fog_density, transition_time)
	_tween.tween_property(env, "volumetric_fog_albedo", preset.volumetric_fog_albedo, transition_time)
	_tween.tween_property(_rain, "amount_ratio", preset.rain_amount, transition_time)
	_tween.chain().tween_callback(_turn_off_unused.bind(preset))


# After the fade out, turn off what this mood does not use.
func _turn_off_unused(preset: MoodPreset) -> void:
	if preset.fog_density <= 0.0:
		_environment.fog_enabled = false
	if preset.volumetric_fog_density <= 0.0:
		_environment.volumetric_fog_enabled = false
	if preset.rain_amount <= 0.0:
		_rain_on = false
		_rain.emitting = false
		set_process(false)


# Runs only while it rains: the rain follows the player.
func _process(_delta: float) -> void:
	_update_rain_position()


func _update_rain_position() -> void:
	var player: Node3D = _get_player()
	if player == null:
		return
	var pos: Vector3 = player.global_position
	var outside: bool = rain_bounds.has_point(pos)
	# In a room: no drops at all, at once. Back outside: the rain starts again.
	_rain.visible = outside
	var emit: bool = _rain_on and outside
	if _rain.emitting != emit:
		_rain.emitting = emit
	_rain.global_position = Vector3(pos.x, pos.y + rain_height, pos.z)


func _get_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# --- Lightning ------------------------------------------------------------------

func _update_lightning_timer() -> void:
	if _preset != null and _preset.lightning_enabled:
		if _lightning_timer.is_stopped():
			_start_lightning_timer()
	else:
		_lightning_timer.stop()


func _start_lightning_timer() -> void:
	var low: float = minf(_preset.lightning_interval_min, _preset.lightning_interval_max)
	var high: float = maxf(_preset.lightning_interval_min, _preset.lightning_interval_max)
	_lightning_timer.start(randf_range(low, high))


func _on_lightning_timer_timeout() -> void:
	if _preset == null or not _preset.lightning_enabled:
		return
	_start_lightning_timer()
	var player: Node3D = _get_player()
	if player != null and rain_bounds.has_point(player.global_position):
		_flash(_preset.lightning_energy)


# A flash: two quick pulses, then a slow fade.
func _flash(energy: float) -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_lightning.light_energy = 0.0
	_lightning.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(_lightning, "light_energy", energy, 0.04)
	_flash_tween.tween_property(_lightning, "light_energy", energy * 0.15, 0.08)
	_flash_tween.tween_property(_lightning, "light_energy", energy * 0.8, 0.05)
	_flash_tween.tween_property(_lightning, "light_energy", 0.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_lightning.hide)
