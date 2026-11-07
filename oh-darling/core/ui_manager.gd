# ==============================================================================
#  UI MANAGER  (autoload)
# ==============================================================================
#  TASK
#    Show and hide the big UI screens (main menu, HUD, pause menu) when the
#    game state changes. It is the ONLY script that decides which screen
#    is visible.
#
#  OWNS
#    - The list of registered screens (id -> Control)
#
#  SIGNALS IT SENDS
#    - screen_shown(id)
#    - screen_hidden(id)
#
#  SIGNALS IT LISTENS TO
#    - GameManager.state_changed
#
#  PUBLIC API
#    - register_screen(id, control)   : a screen tells UIManager it exists
#    - show_screen(id) / hide_screen(id) / is_screen_visible(id)
#
#  HOW A SCREEN JOINS (example, in the script of the UI root scene)
#    func _ready() -> void:
#        UIManager.register_screen(&"hud", $HUD)
#        UIManager.register_screen(&"main_menu", $MainMenu)
#        UIManager.register_screen(&"pause_menu", $PauseMenu)
#
#  NOT HANDLED HERE (WIP)
#    - The dialogue box. The Dialogue Manager plugin opens our custom balloon
#      (scenes/ui/dialogue_ui/). The dialogue owner works there.
#
#  MUST NOT
#    - Use get_node("/root/...") paths to find the UI. Screens register themselves.
#    - Hold game data. A screen reads data from the managers, or listens to them.
#
#  TODO
#    - The pause menu needs process_mode = "When Paused" in its scene.
#    - Add transitions (fade) between screens.
# ==============================================================================
extends Node
## Screen visibility, driven by the game state.

signal screen_shown(id: StringName)
signal screen_hidden(id: StringName)

var _screens: Dictionary = {}  # StringName -> Control


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)


func register_screen(id: StringName, control: Control) -> void:
	_screens[id] = control
	_apply_state(GameManager.state)  # Show the correct visibility at once.


func show_screen(id: StringName) -> void:
	_set_visible(id, true)


func hide_screen(id: StringName) -> void:
	_set_visible(id, false)


func is_screen_visible(id: StringName) -> bool:
	var control: Control = _screens.get(id)
	return control != null and control.visible


func _on_state_changed(new_state: int, _old_state: int) -> void:
	_apply_state(new_state)


func _apply_state(state: int) -> void:
	var playing: bool = state == GameManager.State.EXPLORATION \
			or state == GameManager.State.DIALOGUE
	_set_visible(&"main_menu", state == GameManager.State.MAIN_MENU)
	_set_visible(&"hud", playing)
	_set_visible(&"pause_menu", state == GameManager.State.PAUSED)


func _set_visible(id: StringName, value: bool) -> void:
	var control: Control = _screens.get(id)
	if control == null or control.visible == value:
		return
	control.visible = value
	if value:
		screen_shown.emit(id)
	else:
		screen_hidden.emit(id)
