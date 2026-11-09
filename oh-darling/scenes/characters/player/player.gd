extends CharacterBody3D

# Constants
const SPEED = 5.0
const SPRINT_SPEED = 8.0

@onready var camera_3d: Camera3D = $Camera3D

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
		return
	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var direction := (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()

	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
