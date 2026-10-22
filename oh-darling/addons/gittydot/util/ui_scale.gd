## Editor display scale (2 on a Retina Mac) for sizes set in code — the editor theme scales fonts, but raw pixel minimums don't scale by themselves. No class_name: internal helper, addressed via preload.
extends RefCounted


static func factor() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0


static func px(value: float) -> float:
	return value * factor()


static func size(x: float, y: float) -> Vector2:
	return Vector2(x, y) * factor()


static func size_i(x: float, y: float) -> Vector2i:
	return Vector2i(size(x, y))


## Scales the custom_minimum_size of every Control a .tscn declared under root (call first thing in _ready, before adding code-built controls that are already scaled).
static func scale_scene(root: Node) -> void:
	var f := factor()
	if is_equal_approx(f, 1.0) or is_in_edited_scene(root):
		return
	for child in root.get_children():
		if child is Control and (child as Control).custom_minimum_size != Vector2.ZERO:
			(child as Control).custom_minimum_size *= f
		scale_scene(child)


## True when the node is part of a scene open for editing (a @tool _ready runs there too, and whatever it sets gets saved into the .tscn); edited scenes live in the editor's scene viewport.
static func is_in_edited_scene(node: Node) -> bool:
	if not Engine.is_editor_hint() or not node.is_inside_tree():
		return false
	if node.get_viewport() == EditorInterface.get_editor_viewport_2d():
		return true
	var edited := node.get_tree().edited_scene_root
	return edited != null and (edited == node or edited.is_ancestor_of(node))
