# ==============================================================================
#  GRAPHICS DEMO  (test tool: an overview of the graphics features)
# ==============================================================================
#  TASK
#    An automatic tour of the graphics features in the town: the painterly
#    mood filters, the world-anchored strokes, the outline of interactable
#    objects, the storm Distortion (the vortex) and the painterly quality
#    levels. Each stop sets the emotions, moves the player and the camera,
#    and shows a caption.
#
#  HOW TO USE
#    Open graphics_demo.tscn and press F6 (Run Current Scene).
#      Right arrow : next stop        Left arrow : previous stop
#      P           : pause / resume the automatic tour
#    The mouse still moves the camera, like in the game. F1 shows the debug
#    panel. Add a stop: add a Dictionary to _stops (keys below).
#
#  RULES
#    - It is a test tool. No game scene uses it.
#    - It changes the emotions only through the public API of EmotionManager
#      (reset, shift).
#    - It reads the private zoom of the player camera (_target_zoom), because
#      the camera has no public zoom function. If that name changes, the
#      zoom of the tour stops working, and nothing else breaks.
# ==============================================================================
extends Node3D
## An automatic tour of the graphics features (test tool).

## The time of each stop, when a stop does not give its own time.
@export_range(2.0, 60.0, 0.5, "suffix:s") var stop_time: float = 9.0
## Go to the next stop by itself.
@export var auto_advance: bool = true
## The NPCs that show the outline of interactable objects.
@export var outline_npcs: Array[PackedScene] = [
	preload("res://scenes/characters/npcs/mayor.tscn"),
	preload("res://scenes/characters/npcs/neha.tscn"),
]

const HIGHLIGHT_ACTION: StringName = &"highlight_interactables"
const OUTLINE_SPOT: Vector3 = Vector3(-14.0, 0.0, -1.3)

# Keys of a stop:
#   title, text  : the caption
#   axes         : emotion axis -> value (after EmotionManager.reset())
#   spot         : where the player stands
#   zoom         : camera zoom (1 = default); zoom_to: zoom at the end
#   quality      : painterly quality (0 low, 1 medium, 2 high); none = auto
#   highlight    : hold the "highlight interactables" key
#   time         : the time of this stop (s)
var _stops: Array[Dictionary] = [
	{
		"title": "Painterly filter: clear",
		"text": "Every frame is repainted with brush strokes, in the style of Van Gogh.\nThe strokes follow the edges of the objects. The paint has relief (impasto).",
		"axes": {}, "spot": Vector3(-14, 0, -1.3), "zoom": 0.8,
	},
	{
		"title": "Strokes anchored to the world",
		"text": "The strokes stay on the world, like in Return of the Obra Dinn.\nZoom and walk: the paint does not swim on the screen.",
		"axes": {}, "spot": Vector3(0, 0, 12), "zoom": 0.5, "zoom_to": 1.4, "time": 10.0,
	},
	{
		"title": "Mood: overcast",
		"text": "Low energy. Calm strokes and soft colours.",
		"axes": {"energy": -0.8}, "spot": Vector3(0, 0, 28), "zoom": 1.1,
	},
	{
		"title": "Mood: bright",
		"text": "High energy. More saturation, more swirls, more complementary colours.",
		"axes": {"energy": 0.8}, "spot": Vector3(0, 0, 12), "zoom": 0.9,
	},
	{
		"title": "Mood: fog",
		"text": "Very low energy. A washed-out, grey-blue sketch.",
		"axes": {"energy": -1.0, "dereism": 0.1}, "spot": Vector3(30, 0, 12), "zoom": 1.2,
	},
	{
		"title": "Outline of interactable objects",
		"text": "Hold Alt (or the right mouse button): all usable objects glow green.\nPoint the mouse at one in range: it gets a thick yellow outline (screen pixels,\nso the painterly filter does not hide it). Try it now.",
		"axes": {}, "spot": OUTLINE_SPOT, "zoom": 0.6, "highlight": true,
	},
	{
		"title": "Mood: storm",
		"text": "Very high energy. Long strokes, strong swirls, ultramarine shadows,\nchrome yellow lights, lightning.",
		"axes": {"energy": 1.0, "dereism": 0.1}, "spot": Vector3(0, 0, 12), "zoom": 1.0,
	},
	{
		"title": "Storm Distortion 1",
		"text": "The storm breaks the fourth wall: it rains on the glass of your screen.\nNo new colours: the mist and the drops only adjust the image (like Photoshop layers).",
		"axes": {"energy": 1.0, "dereism": 0.3}, "spot": Vector3(0, 0, 12), "zoom": 1.0,
	},
	{
		"title": "Storm Distortion 2",
		"text": "Mist blurs and greys the image. Each drop is a lens: the image in it is upside down,\nmuch more saturated, with a colour split at the edge.",
		"axes": {"energy": 1.0, "dereism": 0.55}, "spot": Vector3(0, 0, 12), "zoom": 0.7,
	},
	{
		"title": "Storm Distortion 3",
		"text": "Heavy rain on the glass. Big drops slide down in jerks and wipe clear,\nsaturated trails through the mist.",
		"axes": {"energy": 1.0, "dereism": 0.8}, "spot": Vector3(30, 0, 12), "zoom": 1.3, "time": 12.0,
	},
	{
		"title": "Painterly quality: low",
		"text": "For weak GPUs (GTX 750 Ti). One stroke layer, fast directions.\nThe quality goes down by itself when the game runs under 50 FPS.",
		"axes": {}, "spot": Vector3(0, 0, 12), "zoom": 0.6, "quality": 0, "time": 6.0,
	},
	{
		"title": "Painterly quality: medium",
		"text": "Two stroke layers, fast directions.",
		"axes": {}, "spot": Vector3(0, 0, 12), "zoom": 0.6, "quality": 1, "time": 6.0,
	},
	{
		"title": "Painterly quality: high",
		"text": "Two stroke layers, full directions and swirls.",
		"axes": {}, "spot": Vector3(0, 0, 12), "zoom": 0.6, "quality": 2, "time": 6.0,
	},
]

@onready var _town: Node3D = $Town
@onready var _title: Label = %Title
@onready var _text: Label = %Text
@onready var _status: Label = %Status

var _index: int = -1
var _time_left: float = 0.0
var _paused: bool = false
var _zoom_tween: Tween
var _highlight_on: bool = false
var _painterly_camera: Node
var _start_quality: int = 2
var _start_auto_quality: bool = true


func _ready() -> void:
	_painterly_camera = _town.get_node_or_null("MoodFilter/PainterlyCamera")
	if _painterly_camera != null:
		_start_quality = _painterly_camera.get("quality")
		_start_auto_quality = _painterly_camera.get("auto_quality")
	# A clean view: the debug panel comes back with F1.
	var debug_panel: CanvasLayer = get_node_or_null("/root/DebugPanel") as CanvasLayer
	if debug_panel != null:
		debug_panel.visible = false
	_spawn_outline_npcs()
	_go_to.call_deferred(0)


func _process(delta: float) -> void:
	if _paused or not auto_advance:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_go_to(_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_RIGHT:
			_go_to(_index + 1)
		KEY_LEFT:
			_go_to(_index - 1)
		KEY_P:
			_paused = not _paused
			_update_status()
		_:
			return
	get_viewport().set_input_as_handled()


func _go_to(index: int) -> void:
	_index = posmod(index, _stops.size())
	var stop: Dictionary = _stops[_index]
	_time_left = stop.get("time", stop_time)
	_title.text = stop["title"]
	_text.text = stop["text"]
	_update_status()
	_set_emotions(stop.get("axes", {}))
	_move_player(stop["spot"])
	_set_zoom(stop.get("zoom", 1.0), stop.get("zoom_to", -1.0), _time_left)
	_set_quality(stop.get("quality", -1))
	_set_highlight(stop.get("highlight", false))


func _update_status() -> void:
	_status.text = "%d / %d   |   Left / Right: stop   P: %s" % [
			_index + 1, _stops.size(), "resume" if _paused else "pause"]


func _set_emotions(axes: Dictionary) -> void:
	EmotionManager.reset()
	for axis: String in axes:
		EmotionManager.shift(axis, axes[axis])


func _move_player(spot: Vector3) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# A little above the ground: the player falls onto it.
	player.global_position = spot + Vector3(0.0, 2.0, 0.0)
	var body: CharacterBody3D = player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO


func _set_zoom(zoom: float, zoom_to: float, time: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not "_target_zoom" in camera:
		return
	if _zoom_tween != null and _zoom_tween.is_running():
		_zoom_tween.kill()
	camera.set("_target_zoom", zoom)
	if zoom_to > 0.0:
		_zoom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_zoom_tween.tween_property(camera, "_target_zoom", zoom_to, time * 0.5).set_delay(1.0)
		_zoom_tween.tween_property(camera, "_target_zoom", zoom, time * 0.5 - 1.0)


func _set_quality(quality: int) -> void:
	if _painterly_camera == null:
		return
	if quality < 0:
		_painterly_camera.set("auto_quality", _start_auto_quality)
		_painterly_camera.set("quality", _start_quality)
	else:
		_painterly_camera.set("auto_quality", false)
		_painterly_camera.set("quality", quality)


func _set_highlight(on: bool) -> void:
	if on == _highlight_on or not InputMap.has_action(HIGHLIGHT_ACTION):
		return
	_highlight_on = on
	var event: InputEventAction = InputEventAction.new()
	event.action = HIGHLIGHT_ACTION
	event.pressed = on
	Input.parse_input_event(event)


func _spawn_outline_npcs() -> void:
	var offsets: Array[Vector3] = [Vector3(-1.6, 0.0, 1.2), Vector3(1.8, 0.0, 0.6)]
	for i: int in mini(outline_npcs.size(), offsets.size()):
		var npc: Node3D = outline_npcs[i].instantiate() as Node3D
		_town.add_child(npc)
		npc.global_position = OUTLINE_SPOT + offsets[i]
		# Face the camera (it looks from the south-east).
		npc.look_at(npc.global_position + Vector3(1.0, 0.0, 1.0), Vector3.UP, true)
