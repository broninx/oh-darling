# ==============================================================================
#  PAINTERLY CAMERA  (task T05)
# ==============================================================================
#  TASK
#    Give the camera data to the painterly materials every frame, so the
#    brush strokes stay on the world when the camera moves or zooms
#    (see the banner of painterly.gdshader).
#
#  HOW TO USE
#    It is the node "PainterlyCamera" in mood_filter.tscn. "Materials" has
#    the painterly ShaderMaterials of clear, overcast and bright. If you add
#    a mood that uses painterly.gdshader, add its material to the list.
#
#  DATA IT SENDS (shader uniforms)
#    cam_valid, cam_origin, cam_right, cam_up, cam_back, cam_tan_half_fov,
#    plane_height (the height of the player, or 0 without a player),
#    quality (0 = low, 1 = medium, 2 = high).
#
#  QUALITY
#    "Quality" is the highest quality. With "Auto Quality" on, the quality
#    goes down one step when the game runs below "Min Fps" for 2 seconds
#    (after 3 seconds of warm-up). It never goes up again (no flicker
#    between two qualities). The change is printed in the Output.
#      high:   2 layers of large strokes, small strokes, long octave fade.
#      medium: the same, with a shorter smear and a short octave fade.
#      low:    1 layer of large strokes, no small strokes, no octave fade.
#
#  RULES
#    - It only reads the camera and the player. It changes nothing in the world.
#    - It sends the data in RenderingServer.frame_pre_draw, after all the
#      _process() calls, so the camera has already moved. (In _process() the
#      strokes can be one frame late and shake.)
#    - It does not use get_parent(). It finds the camera in the viewport and
#      the player in the group "player".
#    - Without a perspective camera that looks down, it sends
#      cam_valid = false, and the shader uses screen space.
# ==============================================================================
extends Node
## Sends the active camera to the painterly shader, so the strokes stay on the world.

enum Quality { LOW, MEDIUM, HIGH }

const WARMUP_TIME: float = 3.0
const MEASURE_TIME: float = 2.0

## The ShaderMaterials that use painterly.gdshader.
@export var materials: Array[ShaderMaterial] = []
## The highest quality of the painterly filter.
@export var quality: Quality = Quality.HIGH:
	set(value):
		quality = value
		_current_quality = value
		_send_quality()
## Lower the quality when the game is slow.
@export var auto_quality: bool = true
## Below this frame rate, auto quality goes down one step.
@export_range(20, 144) var min_fps: int = 50

var _player: Node3D
var _current_quality: Quality = Quality.HIGH
var _warmup: float = WARMUP_TIME
var _time: float = 0.0
var _frames: int = 0


func _ready() -> void:
	_current_quality = quality
	_send_quality()
	RenderingServer.frame_pre_draw.connect(_send_camera)


# Auto quality: measures the frame rate over MEASURE_TIME seconds.
func _process(delta: float) -> void:
	if not auto_quality or _current_quality == Quality.LOW:
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	_time += delta
	_frames += 1
	if _time < MEASURE_TIME:
		return
	var fps: float = _frames / _time
	_time = 0.0
	_frames = 0
	if fps < min_fps:
		_current_quality = (_current_quality - 1) as Quality
		_send_quality()
		print("PainterlyCamera: %.0f FPS, painterly quality is now %s." % [fps, Quality.keys()[_current_quality]])


func _send_quality() -> void:
	for material: ShaderMaterial in materials:
		if material != null:
			material.set_shader_parameter("quality", int(_current_quality))


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_send_camera):
		RenderingServer.frame_pre_draw.disconnect(_send_camera)


func _send_camera() -> void:
	if not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		_set_valid(false)
		return
	var xform: Transform3D = camera.get_global_transform_interpolated()
	var back: Vector3 = xform.basis.z.normalized()
	if back.y < 0.05:
		_set_valid(false) # The camera does not look down at the ground.
		return
	var tan_half_fov: float = tan(deg_to_rad(camera.fov) * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		# fov is horizontal: change it to vertical.
		var size: Vector2 = get_viewport().get_visible_rect().size
		tan_half_fov /= size.x / maxf(size.y, 1.0)
	for material: ShaderMaterial in materials:
		if material == null:
			continue
		material.set_shader_parameter("cam_valid", true)
		material.set_shader_parameter("cam_origin", xform.origin)
		material.set_shader_parameter("cam_right", xform.basis.x.normalized())
		material.set_shader_parameter("cam_up", xform.basis.y.normalized())
		material.set_shader_parameter("cam_back", back)
		material.set_shader_parameter("cam_tan_half_fov", tan_half_fov)
		material.set_shader_parameter("plane_height", _plane_height())


func _set_valid(valid: bool) -> void:
	for material: ShaderMaterial in materials:
		if material != null:
			material.set_shader_parameter("cam_valid", valid)


# The ground plane goes through the feet of the player.
func _plane_height() -> float:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return 0.0
	return _player.get_global_transform_interpolated().origin.y
