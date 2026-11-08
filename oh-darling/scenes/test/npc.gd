extends StaticBody3D

@export var diaFile: DialogueResource
@export var diaID: String = "start"
var outline = preload("res://scenes/test/outline.tres")

@onready var mesh = $MeshInstance3D 
@onready var area = $Area3D 

var player_proximity: bool = false
var balloon_corrente: Node = null

func _ready() -> void:
	area.body_entered.connect(_on_area_entered)
	area.body_exited.connect(_on_area_exited)

func _on_area_entered(body: Node3D) -> void:
	if body.name == "Player":
		player_proximity = true
		if outline != null:
			mesh.material_overlay = outline

func _on_area_exited(body: Node3D) -> void:
	if body.name == "Player":
		player_proximity = false
		mesh.material_overlay = null

func _unhandled_input(event: InputEvent) -> void:
	if player_proximity and event.is_action_pressed("ui_accept"):
		if diaFile != null:
			GameManager.start_dialogue(diaFile, diaID)
			#DialogueManager.show_example_dialogue_balloon(diaFile, diaID)
