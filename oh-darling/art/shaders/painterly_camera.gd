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
#    plane_height (the height of the player, or 0 without a player).
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

## The ShaderMaterials that use painterly.gdshader.
@export var materials: Array[ShaderMaterial] = []

var _player: Node3D


func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(_send_camera)


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
