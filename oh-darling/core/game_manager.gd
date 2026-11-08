# ==============================================================================
#  GAME MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Own the GAME STATE and run the main loop. It is the "conductor": it does
#    not play any instrument. It tells the others when to start.
#
#        EXPLORATION --(player clicks NPC)--> DIALOGUE
#        DIALOGUE    --(dialogue ends)------> EXPLORATION  (+ autosave)
#        any state   --(pause key)----------> PAUSED
#
#  OWNS
#    - state : MAIN_MENU, EXPLORATION, DIALOGUE or PAUSED
#
#  SIGNALS IT SENDS
#    - state_changed(new_state, old_state)
#
#  SIGNALS IT LISTENS TO
#    - DialogueManager.dialogue_ended   (plugin signal, wip)
#
#  PUBLIC API
#    - start_dialogue(resource, title)  : THE only way to open a dialogue.
#                                         NPCs and objects call this on click.
#    - end_dialogue()                   : returns to EXPLORATION and autosaves
#    - on_choice_made()                 : hook for the dialogue balloon (see TODO)
#    - new_game() / continue_game()
#    - toggle_pause()
#    - change_state(new_state)
#
#  WHY start_dialogue() IS HERE
#    The state must change BEFORE the balloon opens, so the player cannot
#    click the world during a dialogue. One entry point = no mistakes.
#
#  MUST NOT
#    - Know the content of a dialogue, or any NPC.
#    - Change emotion or time values. Dialogue files do that.
#
#  TODO (team decision)
#    - Autosave now happens when a dialogue ENDS. The core loop says "after
#      each choice". If we want that, the balloon calls on_choice_made().
#      Then we must decide what "Continue" does if the player quit in the
#      middle of a dialogue.
#    - If our dialogue implementation does not send dialogue_ended, the balloon must
#      call GameManager.end_dialogue() itself when it closes.
#    - new_game() / continue_game() must also load MainScene. Main does this.
# ==============================================================================
extends Node
## Game state and main loop.

signal state_changed(new_state: State, old_state: State)

enum State {
	MAIN_MENU,
	EXPLORATION,
	DIALOGUE,
	PAUSED,
}

var state: State = State.MAIN_MENU
var _state_before_pause: State = State.EXPLORATION


func _ready() -> void:
	# This node must still work when the tree is paused (to unpause).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The plugin is an autoload too. We look for it by path, so the project
	# still runs before the plugin is installed.
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager and dialogue_manager.has_signal("dialogue_ended"):
		dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	_debug_ready()

func _debug_ready()->void:
	state = State.EXPLORATION

func _unhandled_input(event: InputEvent) -> void:
	# Add the action "pause" in Project Settings > Input Map.
	if InputMap.has_action("pause") and event.is_action_pressed("pause"):
		toggle_pause()


func change_state(new_state: State) -> void:
	if new_state == state:
		return
	var old_state: State = state
	state = new_state
	state_changed.emit(new_state, old_state)


func new_game() -> void:
	SaveManager.delete_save()
	TimeManager.reset()
	EmotionManager.reset()
	change_state(State.EXPLORATION)
	# TODO, load start scene (from a default save?)



func continue_game() -> void:
	if SaveManager.load_game():
		change_state(State.EXPLORATION)


## Open a dialogue. The only valid entry point.
func start_dialogue(resource: Resource, title: String = "start") -> void:
	if state != State.EXPLORATION:
		push_warning("start_dialogue() works only in EXPLORATION.")
		return
	# TODO WIP!
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		push_error("The Dialogue Manager plugin is not enabled.")
		return
	change_state(State.DIALOGUE)
	dialogue_manager.show_dialogue_balloon(resource, title)


func end_dialogue() -> void:
	if state != State.DIALOGUE:
		return
	SaveManager.save()
	change_state(State.EXPLORATION)


## Hook for the dialogue balloon. Call it after each player choice
## if the team wants autosave after each choice.
func on_choice_made() -> void:
	SaveManager.save()


func toggle_pause() -> void:
	if state == State.PAUSED:
		print("paused")
		get_tree().paused = false
		change_state(_state_before_pause)
	elif state == State.EXPLORATION or state == State.DIALOGUE:
		_state_before_pause = state
		get_tree().paused = true
		change_state(State.PAUSED)


func _on_dialogue_ended(_resource: Resource = null) -> void:
	end_dialogue()
