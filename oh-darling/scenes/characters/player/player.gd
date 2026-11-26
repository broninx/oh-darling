extends CharacterBody3D

# Constants
# The speeds are the real speeds of the animations in locomotion.tres, for a
# 1.80 m model. So the feet do not slide. If you change one, change the
# matching point in locomotion.tres too.
# Walk: 1.28 m per cycle, one cycle in 0.95 s (1.4x faster than the file).
const SPEED = 1.35
# Jog (hold the "jog" action, Shift): 4.92 m per cycle, one cycle in 1.23 s
# (0.76x slower than the file).
const JOG_SPEED = 4.0

@onready var camera_3d: Camera3D = $Camera3D
# The model slot. It turns the model and plays idle and walk. The body itself
# never turns, because the camera is its child.
@onready var _model: CharacterModel = $Model

func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	set_input_enabled(GameManager.state == GameManager.State.EXPLORATION)


func _on_state_changed(new_state: int, _old_state: int) -> void:
	set_input_enabled(new_state == GameManager.State.EXPLORATION)


func set_input_enabled(enabled: bool) -> void:
	set_process_unhandled_input(enabled)  # No more click or key events.
	if not enabled:
		_stop()  # Cancel the walk that is in progress.


func _stop() -> void:
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Camera basis, flattened to XZ so the ise tilt doesn't affect speed
	var cam_basis := camera_3d.global_transform.basis
	var cam_forward := -cam_basis.z
	var cam_right := cam_basis.x
	cam_forward.y = 0.0
	cam_right.y = 0.0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	if GameManager.state != GameManager.State.EXPLORATION:
		_stop()
		_model.play_idle()
		return
	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var direction := (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()

	
	var speed: float = JOG_SPEED if Input.is_action_pressed("jog") else SPEED
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	# The real velocity: against a wall the player stands, it does not walk in place.
	_model.set_motion(get_real_velocity(), delta)
