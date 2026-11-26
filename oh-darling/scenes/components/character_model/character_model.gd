# ==============================================================================
#  CHARACTER MODEL  (component)
# ==============================================================================
#  TASK
#    The slot for the 3D model of a character (the player or an NPC).
#      1. It turns toward the walk direction. Only this node turns, so the
#         body and the camera of the player do not turn.
#      2. It gives the speed to an AnimationTree. The tree blends the
#         animations (idle, walk, jog...) by speed.
#
#  HOW TO USE
#    - Put this script on a Node3D named "Model". The model is its child.
#      The model must face +Z (the Godot and glTF default).
#    - Add an AnimationTree as a child of Model. Set its "Anim Player" to the
#      AnimationPlayer of the model, and its "Root Node" to the model root.
#      The default tree is locomotion.tres (a BlendSpace1D on speed, m/s).
#    - Set "animation_tree" in the Inspector.
#    - A character that moves calls set_motion(velocity, delta) in each
#      physics frame. A character that does not call it stays at speed 0.
#
#  PUBLIC API
#    - set_motion(velocity, delta)
#    - play_idle()                 : speed 0 at once
#
#  MUST NOT
#    - Move the character. It only turns itself and sets the blend value.
#    - Use get_parent(). The owner calls set_motion().
# ==============================================================================
class_name CharacterModel
extends Node3D
## The slot for a character model. Turns toward the walk direction and blends the animations by speed.

## The AnimationTree that plays the model animations.
@export var animation_tree: AnimationTree
## The tree parameter that receives the speed (m/s).
@export var speed_parameter: StringName = &"parameters/blend_position"

@export_group("Motion")
## Below this speed (m/s) the model does not turn.
@export_range(0.0, 1.0, 0.01, "suffix:m/s") var turn_min_speed: float = 0.1
## How fast the model turns. Higher is faster.
@export_range(1.0, 40.0, 0.5) var turn_speed: float = 14.0
## How fast the blend follows the real speed. Higher is faster.
@export_range(1.0, 40.0, 0.5) var blend_speed: float = 10.0
## Start the animation at a random time, so NPCs do not breathe all together.
@export var random_start: bool = true

var _speed: float = 0.0


func _ready() -> void:
	if animation_tree == null:
		push_warning("CharacterModel '%s': set 'animation_tree' in the Inspector." % name)
		return
	animation_tree.set(speed_parameter, 0.0)
	if random_start:
		animation_tree.advance(randf() * 3.0)


## Call it in each physics frame with the velocity of the character.
func set_motion(velocity: Vector3, delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed > turn_min_speed:
		# The model faces +Z: the yaw is atan2(x, z).
		var target_yaw: float = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	_speed = lerpf(_speed, speed, 1.0 - exp(-blend_speed * delta))
	_apply()


func play_idle() -> void:
	_speed = 0.0
	_apply()


func _apply() -> void:
	if animation_tree != null:
		animation_tree.set(speed_parameter, _speed)
