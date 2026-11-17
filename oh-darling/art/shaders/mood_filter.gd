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
#  TODO
#    - Fade from one filter to the next (README: 1 to 2 seconds).

extends CanvasLayer
func _ready() -> void:
	EmotionManager.mood_changed.connect(_on_mood_changed)
	_show_mood(EmotionManager.get_mood()) # First state: we missed the old signals.


func _on_mood_changed(new_mood: String, _old_mood: String) -> void:
	_show_mood(new_mood)
func _show_mood(mood: String) -> void:
	for child: Node in get_children():
		if child is CanvasItem:
			child.visible = (child.name == mood)
