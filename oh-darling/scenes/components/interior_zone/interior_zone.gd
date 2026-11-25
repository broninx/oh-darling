# ==============================================================================
#  INTERIOR ZONE  (component)
# ==============================================================================
#  TASK
#    Show the inside of a building when the player goes in. While the player
#    is in the zone, the outer walls and the roof are not visible, but they
#    still cast their shadows. So the light inside does not change.
#
#  HOW TO USE
#    1. Add interior_zone.tscn to a place scene.
#    2. Give the instance a CollisionShape3D child that fills the room.
#    3. Set "exterior" to the node that holds the outer walls and the roof.
#       Each GeometryInstance3D under it (CSG shapes, meshes) is switched.
#
#  WHAT IT DOES
#    - Outside: the exterior parts are visible and cast shadows.
#    - Inside:  the exterior parts cast shadows only (you cannot see them).
#    - It finds the player with the group "player".
#    - It does not take mouse clicks (input_ray_pickable is off), so the
#      objects inside the room stay clickable.
#
#  SIGNALS IT SENDS
#    - player_inside_changed(inside) : when the player goes in or out.
#
#  MUST NOT
#    - Change game data or the game state. It is visual only.
#    - Use get_parent(). It knows only the "exterior" export.
# ==============================================================================
class_name InteriorZone
extends Area3D
## Hides the outer walls and the roof of a building while the player is inside.

signal player_inside_changed(inside: bool)

## The node that holds the outer walls and the roof.
@export var exterior: Node3D

var is_inside: bool = false

var _parts: Array[GeometryInstance3D] = []


func _ready() -> void:
	# The zone fills the room. If it took mouse rays, it would hide every
	# clickable object inside the room.
	input_ray_pickable = false
	if exterior == null:
		push_warning("InteriorZone '%s': set 'exterior' in the Inspector." % name)
		return
	_collect_parts(exterior)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply()


func _collect_parts(node: Node) -> void:
	if node is GeometryInstance3D:
		_parts.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		_collect_parts(child)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_set_inside(true)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_set_inside(false)


func _set_inside(inside: bool) -> void:
	if inside == is_inside:
		return
	is_inside = inside
	_apply()
	player_inside_changed.emit(is_inside)


func _apply() -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_inside:
		mode = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for part: GeometryInstance3D in _parts:
		part.cast_shadow = mode
