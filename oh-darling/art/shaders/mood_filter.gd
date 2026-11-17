# ==============================================================================
#  MOOD FILTER
# ==============================================================================
#  TASK
#    Show the painted screen filter of the current mood.
#    One child for each mood. The child NAME is the mood name:
#    fog, overcast, clear, bright, storm.
#
#  SIGNALS IT LISTENS TO
#    - EmotionManager.mood_changed
#
#  HOW TO USE
#    Add mood_filter.tscn to a level scene. Nothing else.
#
#    The new filter fades in on top of the old one (transition_time).
#    Filter shaders must end with COLOR = vec4(..., COLOR.a);

extends CanvasLayer
func _ready() -> void:
	EmotionManager.mood_changed.connect(_on_mood_changed)
	_show_mood(EmotionManager.get_mood()) # First state: we missed the old signals.
@export var transition_time: float = 1.5

var _current: CanvasItem
var _target: String = ""
var _tween: Tween

func _on_mood_changed(new_mood: String, _old_mood: String) -> void:
		_fade_to(new_mood)
		
func _show_mood(mood: String) -> void:
	_target = mood
	for child: Node in get_children():
		if child is CanvasItem:
			child.visible = (child.name == mood)
			child.modulate.a = 1.0
			if child.visible:
				_current = child
				
func _fade_to(mood: String) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
		_show_mood(_target) # A new mood during a fade: finish the old fade at once.
	var next: CanvasItem = get_node_or_null(NodePath(mood)) as CanvasItem
	if next == null or next == _current:
		return
	_target = mood
	move_child(next, get_child_count() - 1)
	next.modulate.a = 0.0
	next.visible = true
	_tween = create_tween()
	_tween.tween_property(next, "modulate:a", 1.0, transition_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_show_mood.bind(mood))
