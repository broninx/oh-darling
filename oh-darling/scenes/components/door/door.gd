# ==============================================================================
#  DOOR
# ==============================================================================
#  TASK
#    A clickable door. A valid click moves the player to "destination".
#    The click rules (range, EXPLORATION only, block()) come from the
#    InteractionComponent of the item prefab. This script adds only the move.
#
#  HOW TO USE IT
#    Add an instance of door.tscn to the level. Set "Destination" (a world
#    position, where the player stands after the click).
#    The default mesh is a visible door panel. For a door that is part of a
#    building model, turn on Editable Children and give MeshInstance3D a box
#    with an invisible material. The overlay still shows on hover.
#
#  RULES
#    - It does not use get_parent(). It finds the player in the group "player".
#    - It only moves the player. It does not change the game state.
# ==============================================================================
extends Node3D
## Moves the player to [member destination] when the door is clicked.

## Where the player stands after the click (world position).
@export var destination: Vector3 = Vector3.ZERO

@onready var _interaction: InteractionComponent = $InteractionComponent


func _ready() -> void:
	_interaction.interacted.connect(_on_interacted)


func _on_interacted() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.global_position = destination
	var body := player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
