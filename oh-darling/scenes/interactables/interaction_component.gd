# ==============================================================================
#  INTERACTION COMPONENT  (task T06)
# ==============================================================================
#  TASK
#    Make ONE object clickable. It does these things:
#      1. Hover: show an overlay on the target mesh while the mouse is over it,
#         but ONLY if the player is close enough.
#      2. Click: on a left click, send the signal "interacted" and, if there is
#         a dialogue, start it with GameManager.start_dialogue().
#         This also works ONLY if the player is close enough.
#      3. Highlight: while the player holds the key "highlight_interactables",
#         show a different overlay on every object that can be used. The
#         distance does not matter. This helps the player find things.
#      4. Rules: it works only in EXPLORATION, and only if nobody blocks it.
#
#  SETUP (once for the project)
#    - Input Map: add the action "highlight_interactables" (for example Alt).
#    - The player scene must be in the group "player".
#
#  HOW TO USE IT
#    Use the prefabs npc.tscn and item.tscn. They already have this component,
#    wired to their mesh. To make a new kind of object, make a scene with a
#    root node, a MeshInstance3D, and an instance of interaction_component.tscn.
#    Set "Target Mesh" to the MeshInstance3D.
#
#  RULES FOR COMPONENTS
#    - It does not use get_parent(). It knows only what you give it
#      (target_mesh). Move it anywhere in the scene and it still works.
#    - Other components change it through its PUBLIC properties and functions.
#    - It tells others with a signal. It does not call them.
#
#  PUBLIC API
#    - dialogue_resource, dialogue_title : what the click starts (can change at runtime)
#    - enabled                           : the owner's switch
#    - interaction_range                 : the distance limit (0 = no limit)
#    - block(source) / unblock(source)   : switch from other components (see below)
#    - is_available() -> bool
#    - interact()                        : the same as a click (tests, other code).
#                                          It does NOT check the distance.
#    - refresh()                         : call it after you change target_mesh.mesh
#    - signal interacted
#
#  WHY block() AND NOT "enabled = false"
#    Two components may want to block the same object (a schedule says "the NPC
#    is away", a location says "closed"). If both set "enabled", the second one
#    that turns it ON removes the block of the first. With block(source) each
#    source has its own block, and the object is free only when there is none.
#
#  SIGNALS IT LISTENS TO
#    - GameManager.state_changed
#
#  HOW THE DISTANCE WORKS
#    The distance is flat (X and Z only, height is ignored). It goes from the
#    player to the origin of the target mesh. For a very big object, make the
#    range bigger, or the player cannot reach the origin.
#    The distance is checked when the player clicks, and every frame while the
#    mouse is over the object (so the overlay goes off if the player walks away).
#    No other time. Most objects never cost anything.
#
#  MUST NOT
#    - Open a dialogue in another way than GameManager.start_dialogue().
#    - Keep its own copy of the game state. It asks GameManager.state.
#    - Scale the target mesh in a non-uniform way. The collision shape copies
#      the transform of the mesh, and Godot does not support such a shape.
# ==============================================================================
@tool
class_name InteractionComponent
extends Area3D
## Makes an object clickable: hover overlay, left click, dialogue start, highlight key.

## Sent on every valid click (and on interact()).
signal interacted

## Input Map action that shows every usable object while it is held.
const HIGHLIGHT_ACTION: StringName = &"highlight_interactables"

## The mesh that gets the overlays. The collision is made from its shape.
@export var target_mesh: MeshInstance3D:
	set(value):
		target_mesh = value
		update_configuration_warnings()

@export var dialogue_resource: DialogueResource
@export var dialogue_title: String = "start"

## The owner's switch. Other components use block() instead.
@export var enabled: bool = true

## Turn this off if you made the CollisionShape3D by hand.
@export var fit_collision_to_mesh: bool = true

@export_group("Range")
## The player must be this close (flat distance, in meters) to hover and click.
## 0 means no limit.
@export_range(0.0, 50.0, 0.1, "suffix:m") var interaction_range: float = 6.0

@export_group("Materials")
## Shown while the mouse is over the object and the player is close enough.
@export var hover_material: Material = preload("res://scenes/interactables/outline.tres")
## Shown while the highlight key is held. If empty, a yellow default is used.
@export var highlight_material: Material

# One default material for all components.
static var _default_highlight: StandardMaterial3D

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _hovered: bool = false
var _highlight_held: bool = false
var _blockers: Array[StringName] = []
var _player: Node3D


func _ready() -> void:
	set_process(false)  # Turned on only while the mouse is over the object.
	if Engine.is_editor_hint():
		set_process_input(false)  # In the editor this script only shows warnings.
		return
	input_ray_pickable = true
	if highlight_material == null:
		highlight_material = _get_default_highlight()
	_highlight_held = _is_highlight_key_down()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)
	GameManager.state_changed.connect(_on_state_changed)
	refresh()
	_update_overlay()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if target_mesh == null:
		warnings.append("Set 'Target Mesh'. The overlay and the collision use it.")
	if not has_node("CollisionShape3D"):
		warnings.append("This node needs a child named CollisionShape3D.")
	return warnings


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_DISABLED:
			# A disabled Area3D gets no mouse_exited, so we reset by hand.
			_hovered = false
			set_process(false)
			_update_overlay()
		NOTIFICATION_ENABLED:
			# We got no key events while disabled. Read the real key state.
			_highlight_held = _is_highlight_key_down()
			_update_overlay()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# The key release goes to another window. Do not stay highlighted.
			_highlight_held = false
			_update_overlay()


# --- Public API ---------------------------------------------------------------

func is_available() -> bool:
	return enabled and _blockers.is_empty()


## Block this object. [param source] names who blocks (for example &"schedule").
func block(source: StringName) -> void:
	if not _blockers.has(source):
		_blockers.append(source)
	_update_overlay()


func unblock(source: StringName) -> void:
	_blockers.erase(source)
	_update_overlay()


## The same as a valid click, but without the distance check.
## Starts the dialogue if there is one.
func interact() -> void:
	interacted.emit()
	if dialogue_resource != null:
		GameManager.start_dialogue(dialogue_resource, dialogue_title)


## Make the collision shape again. Call it after you change target_mesh.mesh.
func refresh() -> void:
	if Engine.is_editor_hint():
		return
	if not fit_collision_to_mesh or target_mesh == null or target_mesh.mesh == null:
		return
	# Shape from the mesh. It is made at runtime only, so the big shape data
	# does not go into the .tscn files (fewer merge conflicts).
	var shape := target_mesh.mesh.create_convex_shape(true, true)
	if shape == null:
		return
	_collision_shape.shape = shape
	_collision_shape.global_transform = target_mesh.global_transform


# --- Input --------------------------------------------------------------------

# _input and not _unhandled_input: the dialogue balloon handles input, and we
# must still see the release of the highlight key to turn the overlay off.
func _input(event: InputEvent) -> void:
	if event.is_action(HIGHLIGHT_ACTION) and not event.is_echo():
		_highlight_held = event.is_pressed()
		_update_overlay()


func _on_mouse_entered() -> void:
	_hovered = true
	set_process(true)
	_update_overlay()


func _on_mouse_exited() -> void:
	_hovered = false
	set_process(false)
	_update_overlay()


# Runs only while the mouse is over the object. The player may walk away
# (or come close) without moving the mouse, so we check the distance again.
func _process(_delta: float) -> void:
	_update_overlay()


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3,
		_normal: Vector3, _shape_idx: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _can_use_now():
		interact()


func _on_state_changed(_new_state: int, _old_state: int) -> void:
	_update_overlay()


# --- Rules --------------------------------------------------------------------

# The object may be used at all (state and blocks). The distance is not checked.
func _is_clickable() -> bool:
	return GameManager.state == GameManager.State.EXPLORATION and is_available()


# The object may be used by this player now: clickable AND close enough.
func _can_use_now() -> bool:
	return _is_clickable() and _is_player_in_range()


func _is_player_in_range() -> bool:
	if interaction_range <= 0.0:
		return true
	var player := _get_player()
	if player == null:
		return false
	var from: Vector3 = player.global_position
	var to: Vector3 
	if target_mesh != null:
		to= target_mesh.global_position
	else:
		to = self.global_position
	return Vector2(from.x - to.x, from.z - to.z).length() <= interaction_range


func _get_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# --- Overlay ------------------------------------------------------------------

# Hover (with range) wins over the highlight key.
# We keep _hovered and _highlight_held even when the overlay is off, so the
# overlay comes back at once when a dialogue ends.
func _update_overlay() -> void:
	if target_mesh == null:
		return
	var material: Material = null
	if _hovered and _can_use_now():
		material = hover_material
	elif _highlight_held and _is_clickable():
		material = highlight_material
	if target_mesh.material_overlay != material:
		target_mesh.material_overlay = material


func _is_highlight_key_down() -> bool:
	return InputMap.has_action(HIGHLIGHT_ACTION) and Input.is_action_pressed(HIGHLIGHT_ACTION)


static func _get_default_highlight() -> StandardMaterial3D:
	if _default_highlight == null:
		_default_highlight = StandardMaterial3D.new()
		_default_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_default_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_default_highlight.albedo_color = Color(1.0, 0.85, 0.3, 0.4)
	return _default_highlight
