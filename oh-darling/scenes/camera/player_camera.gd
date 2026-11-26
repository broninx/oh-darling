# ==============================================================================
#  PLAYER CAMERA  (task T04)
# ==============================================================================
#  TASK
#    Move the isometric camera, in the style of Disco Elysium.
#      1. Zoom: the mouse wheel moves the camera nearer or farther, along its
#         view direction.
#      2. Look: when the mouse goes away from the screen centre, the camera
#         moves a little toward that side. It moves on the ground plane.
#    Both are smooth.
#
#  HOW TO USE
#    Put this script on the Camera3D, the child of the player. The position
#    set in the Inspector is the default view (zoom 1, no look offset).
#    The script only changes the position. It never turns the camera, so the
#    player movement (which reads the camera direction) does not change.
#
#  RULES
#    - Zoom works only in EXPLORATION (world input rule).
#    - The look offset follows the mouse only in EXPLORATION, and only while
#      the window has the focus. In other states it stays where it is.
#
#  MUST NOT
#    - Turn the camera.
#    - Read a manager in _process() (it reads GameManager.state once per
#      state change).
# ==============================================================================
class_name PlayerCamera
extends Camera3D
## Isometric camera with mouse-wheel zoom and a small look offset toward the mouse.

@export_group("Zoom")
## Nearest zoom (1 = the default distance).
@export_range(0.2, 1.0, 0.05) var zoom_min: float = 0.45
## Farthest zoom.
@export_range(1.0, 3.0, 0.05) var zoom_max: float = 1.4
## Zoom change for one wheel step.
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.08
## How fast the zoom follows the wheel. Higher is faster.
@export_range(1.0, 30.0, 0.5) var zoom_smooth: float = 8.0

@export_group("Look")
## The largest look offset (metres, at zoom 1). It gets smaller when you zoom in.
@export_range(0.0, 10.0, 0.1, "suffix:m") var look_distance: float = 3.5
## Part of the screen around the centre where the mouse does nothing (0 to 1).
@export_range(0.0, 0.9, 0.01) var look_dead_zone: float = 0.2
## How fast the look offset follows the mouse. Higher is faster.
@export_range(0.5, 20.0, 0.5) var look_smooth: float = 3.0

var _base_offset: Vector3
var _zoom: float = 1.0
var _target_zoom: float = 1.0
var _look: Vector3 = Vector3.ZERO
var _active: bool = false


func _ready() -> void:
	_base_offset = position
	GameManager.state_changed.connect(_on_state_changed)
	_active = GameManager.state == GameManager.State.EXPLORATION


func _on_state_changed(new_state: int, _old_state: int) -> void:
	_active = new_state == GameManager.State.EXPLORATION


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		_target_zoom = clampf(_target_zoom - zoom_step, zoom_min, zoom_max)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_target_zoom = clampf(_target_zoom + zoom_step, zoom_min, zoom_max)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_zoom = lerpf(_zoom, _target_zoom, 1.0 - exp(-zoom_smooth * delta))
	if _active and get_window().has_focus():
		_look = _look.lerp(_target_look(), 1.0 - exp(-look_smooth * delta))
	position = _base_offset * _zoom + _look


# The look offset for the mouse position, on the ground plane.
func _target_look() -> Vector3:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector3.ZERO
	# -1..1 from the centre. y is positive at the bottom of the screen.
	var mouse: Vector2 = (get_viewport().get_mouse_position() / size) * 2.0 - Vector2.ONE
	mouse = mouse.clamp(-Vector2.ONE, Vector2.ONE)
	var amount: float = clampf((mouse.length() - look_dead_zone) / (1.0 - look_dead_zone), 0.0, 1.0)
	if amount <= 0.0:
		return Vector3.ZERO
	var direction: Vector2 = mouse.normalized() * amount
	# Screen right and screen up, flattened on the ground.
	var right: Vector3 = transform.basis.x
	var up_on_ground: Vector3 = -transform.basis.z
	right.y = 0.0
	up_on_ground.y = 0.0
	var offset: Vector3 = right.normalized() * direction.x + up_on_ground.normalized() * -direction.y
	return offset * look_distance * _zoom
