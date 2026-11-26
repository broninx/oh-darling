# ==============================================================================
#  GLASS RAIN  (the Distortion of the storm mood)
# ==============================================================================
#  TASK
#    In the storm mood, the Distortion breaks the fourth wall: it rains on the
#    glass of the screen, on top of the painting (glass_rain.gdshader). It
#    adds no colour: the mist and the drops only adjust the image under them
#    (blur, saturation, refraction). More Distortion = more rain on the glass
#    (level_amounts).
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.mood_changed
#    - EmotionManager.distortion_changed
#
#  HOW TO USE
#    It is the only child of distortion_filter.tscn (the Distortion of the
#    game), so every level that has the distortion filter has it too. The
#    filter is a CanvasLayer (layer 0), UNDER the mood filter (layer 1):
#    the painterly filter repaints the drops with brush strokes too.
#    To test: set Preview Level in the Inspector (-1 = follow the game;
#    0 to 3 = that level, in any mood).
#    Today only the storm mood has a Distortion effect: fog has none.
#
#  RULES
#    - It only reads the mood and the Distortion. It never changes them.
#    - It is hidden while the amount is 0, so it costs nothing then.
#
#  MUST NOT
#    - Call create_tween() before it knows that it adds a tweener.
# ==============================================================================
extends Control
## Rain on the glass of the screen: the Distortion of the storm mood.

## The mood where this rain shows the Distortion.
@export var mood: String = "storm"
## The amount of rain for Distortion levels 0, 1, 2 and 3.
@export var level_amounts: PackedFloat32Array = PackedFloat32Array([0.0, 0.35, 0.65, 1.0])
## The time of a change of level.
@export_range(0.0, 5.0, 0.1, "suffix:s") var change_time: float = 2.0
## -1 = follow the game. 0 to 3 = show this level in any mood (test).
@export_range(-1, 3) var preview_level: int = -1

@onready var _material: ShaderMaterial = $Glass.material as ShaderMaterial

var _tween: Tween
var _amount: float = 0.0


func _ready() -> void:
	_set_amount(0.0)
	EmotionManager.mood_changed.connect(_on_mood_changed)
	EmotionManager.distortion_changed.connect(_on_distortion_changed)
	_apply(true) # First state: we missed the old signals.


func _on_mood_changed(_new_mood: String, _old_mood: String) -> void:
	_apply(false)


func _on_distortion_changed(_new_level: int, _old_level: int) -> void:
	_apply(false)


func _target_amount() -> float:
	var level: int = preview_level
	if level < 0:
		if EmotionManager.get_mood() != mood:
			return 0.0
		level = EmotionManager.get_distortion()
	level = clampi(level, 0, level_amounts.size() - 1)
	return level_amounts[level]


func _apply(instant: bool) -> void:
	var target: float = _target_amount()
	if _tween != null and _tween.is_running():
		_tween.kill()
	if instant or change_time <= 0.0 or is_equal_approx(target, _amount):
		_set_amount(target)
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_amount, _amount, target, change_time)


func _set_amount(value: float) -> void:
	_amount = value
	_material.set_shader_parameter("amount", value)
	visible = value > 0.0
