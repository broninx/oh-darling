# ==============================================================================
#  DISTORTION FILTER
# ==============================================================================
#  TASK
#    Show the visual Distortion (GDD table).
#    Level 2: the room sways (child "Sway", Screen Warping shader).
#    Level 3: the scene breaks (child "Shatter", broken screen shader).
#    Levels 0 and 1: nothing on screen.
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.distortion_changed
#
#  HOW TO USE
#    Add distortion_filter.tscn to a level scene, next to mood_filter.tscn.
#    Its Layer must be higher than the mood filter's Layer.
#    To test: set Preview Level in the Inspector (-1 = follow the game).

extends CanvasLayer

## How much the room sways at level 2.
@export_range(0.0, 0.1) var sway_strength: float = 0.03
@export var change_time: float = 1.0
@export_range(-1, 3) var preview_level: int = -1

var _tween: Tween

@onready var _sway: ColorRect = $Sway
@onready var _shatter: ColorRect = $Shatter


func _ready() -> void:
	for rect: ColorRect in [_sway, _shatter]:
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_sway(0.0)
	_set_shatter(0.0)
	EmotionManager.distortion_changed.connect(_on_distortion_changed)
	if preview_level >= 0:
		_show_level(preview_level)
	else:
		_show_level(EmotionManager.get_distortion()) # First state: we missed the old signals.


func _on_distortion_changed(new_level: int, _old_level: int) -> void:
	if preview_level < 0:
		_show_level(new_level)


# Sway (level 2+) and cracks (level 3) grow or fade out in change_time seconds.
func _show_level(level: int) -> void:
	var sway_target: float = sway_strength if level >= 2 else 0.0
	var shatter_target: float = 1.0 if level >= 3 else 0.0
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_sway, _get_sway(), sway_target, change_time)
	_tween.tween_method(_set_shatter, _get_shatter(), shatter_target, change_time)


# At 0 the ColorRects are hidden
func _set_sway(value: float) -> void:
	(_sway.material as ShaderMaterial).set_shader_parameter("warp_intensity", value)
	_sway.visible = value > 0.0001


func _get_sway() -> float:
	return float((_sway.material as ShaderMaterial).get_shader_parameter("warp_intensity"))


func _set_shatter(value: float) -> void:
	(_shatter.material as ShaderMaterial).set_shader_parameter("amount", value)
	_shatter.visible = value > 0.001


func _get_shatter() -> float:
	return float((_shatter.material as ShaderMaterial).get_shader_parameter("amount"))
