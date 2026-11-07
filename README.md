# oh-darling
A project for the 2026 Videogame Design and Programming (VDP) course at the Politecnico di Milano.

# (WIP) FOR DEVELOPERS!!!  Oh Darling: Project Guide
 
This file explains how the Godot project is built and how to work in it.
Read it before you add code. It is short on purpose and can be updated over time.
 
Game design: see `gdd.md`. Engine: Godot 4.x. Language: typed GDScript.
 
---
 
## 1. Folder map
 
```
core/        autoloads (the six managers)
data/        Resource scripts and .tres data (moods, schedules)
dialogue/    .dialogue files, one folder for each character
scenes/      scenes AND their scripts, grouped by feature
art/         models, textures, portraits, shaders
audio/       music stems and sound effects
addons/      plugins (do not edit)
```
 
Two rules:
 
- **Scene and script stay together.** `player.tscn` and `player.gd` live in the same folder.
- **All names use snake_case.** Example: `neon_padma.tscn`.
---
 
## 2. The six autoloads
 
An autoload is a script that Godot loads first and keeps for the whole game. Each one has ONE task.
 
| Autoload | Task | Owns |
| --- | --- | --- |
| `GameManager` | Runs the game state and the main loop | `state` |
| `TimeManager` | Keeps the clock. It moves only in dialogues | `day`, `minutes` |
| `EmotionManager` | Keeps the hidden emotions. Gives mood and Distortion | hidden values |
| `SaveManager` | Writes and reads the one autosave file | save file |
| `AudioManager` | Plays the music stems. Follows the mood | audio players |
| `UIManager` | Shows and hides menus and HUD | screen list |
 
Each script has a large comment at the top. It lists the task, the data, the signals and the rules. **Read that comment before you change the script.**
 
---
 
## 3. Rules for communication
 
These rules keep the code simple. They are the most important part of this file.
 
1. **Data changes in ONE place.** Only `EmotionManager` changes emotion values. Only `TimeManager` changes the clock. Other scripts ask, or listen.
2. **Managers do not call each other. They send signals.** `EmotionManager` sends `mood_changed`. The shader, the audio and the NPCs listen. `EmotionManager` does not know they exist.
3. **Do not use `_process()` to read a manager.** Connect to its signal.
4. **Listeners connect in `_ready()`.**
```gdscript
   func _ready() -> void:
       EmotionManager.mood_changed.connect(_on_mood_changed)
```
 
5. **Only `GameManager` opens a dialogue.** Call `GameManager.start_dialogue(resource, "start")`. Do not call `DialogueManager` directly. `GameManager` must set the state first.
6. **Data goes in `.tres` files, not in code.** Schedules, mood presets and similar values are Resources. Designers can then change them without a script.
7. **Do not show hidden numbers to the player.** The player reads the world.
### Who may call who
 
| From | May call |
| --- | --- |
| Dialogue files | `EmotionManager.shift()`, `TimeManager.advance()`, and the getters |
| `GameManager` | `SaveManager`, `TimeManager.reset()`, `EmotionManager.reset()` |
| `SaveManager` | `get_save_data()` and `load_save_data()` of the managers |
| Everything else | Only signals and getters |
 
---
 
## 5. Signals
 
| Signal | Sent by | Who listens |
| --- | --- | --- |
| `mood_changed(new_mood, old_mood)` | `EmotionManager` | `AudioManager`, Environment (shader), NPCs |
| `distortion_changed(new_level, old_level)` | `EmotionManager` | Environment (shader), Echoes |
| `time_changed(day, minutes)` | `TimeManager` | HUD clock, NPCs |
| `day_changed(day)` | `TimeManager` | NPCs |
| `state_changed(new_state, old_state)` | `GameManager` | `UIManager`, player controls |
| `game_saved`, `game_loaded` | `SaveManager` | nobody yet |
| `screen_shown(id)`, `screen_hidden(id)` | `UIManager` | nobody yet |
 
Mood names are strings: `"fog"`, `"overcast"`, `"clear"`, `"bright"`, `"storm"`.
 
---
 
## 6. The main loop in code
 
```
Player clicks an NPC
  └─ NPC calls GameManager.start_dialogue(resource, "start")
       ├─ state = DIALOGUE         (state_changed → UIManager)
       └─ the dialogue balloon opens
 
During the dialogue, a choice runs a mutation:
  ├─ do EmotionManager.shift("energy", 15)  → mood_changed → shader, audio, NPCs
  └─ do TimeManager.advance(20)             → time_changed → HUD, NPCs
 
The dialogue ends
  └─ GameManager.end_dialogue()
       ├─ SaveManager.save()
       └─ state = EXPLORATION
```
 
---
 
## 7. How to do common tasks
 
### Add a mood-dependent thing (for example, a new object)
 
1. Connect to `EmotionManager.mood_changed` in `_ready()`.
2. Read `EmotionManager.get_mood()` once, to set the first state.
3. Do **not** change the object while the player looks at it (GDD: Staging Rule). Swap it when it leaves the frame, or after a dialogue.
### Add an NPC
 
1. Copy the base scene `scenes/characters/npcs/npc.tscn`.
2. Make a schedule Resource in `data/schedules/`.
3. Make a folder in `dialogue/` for the character.
4. On click, call `GameManager.start_dialogue(...)`.
### Add a new screen
 
1. Make the scene in `scenes/ui/`.
2. In the UI root script: `UIManager.register_screen(&"my_screen", $MyScreen)`.
3. Add its rule in `UIManager._apply_state()`.
### Save new data
 
1. Give your script `get_save_data() -> Dictionary` and `load_save_data(data)`.
2. Add one line in `SaveManager.save()` and one line in `SaveManager.load_game()`.
3. Change `SAVE_VERSION` if old saves are no longer valid.
---
 
## 8. Code style
 
- Use **static types**: `var day: int = 1`, `func advance(amount: int) -> void:`.
- Use `##` for documentation comments on public functions and signals.
- Use tabs, not spaces.
- Start private names with `_`: `_recalculate()`.
- Name signals in the past tense: `mood_changed`, `dialogue_ended`.
- Do not use `class_name` in an autoload script. It conflicts with the autoload name.
- Keep functions short. If a function has more than about 30 lines, split it.
---
 
## 9. Working in a team (Git)
 
- **Each person owns a folder.** Suggested: one person for `core/`, one for `dialogue/`, one for `art/` and `audio/`, one for `scenes/world/`, one for `scenes/ui/`. Ask the owner before you change a file in their folder.
- **Do not edit the same `.tscn` file at the same time.** Godot scene files do not merge well. Say in the group chat when you take a scene.
- **Use small commits and short branches.** Merge into `main` often.
- **Do not commit** the `.godot/` folder.
---
 
## 10. Open questions
 
The team must decide these. They are also marked `TODO` in the scripts.
 
1. **Autosave timing.** Now: when a dialogue ends. The core loop says: after each choice. If we save after each choice, what does "Continue" do for a player who quit in the middle of a dialogue?
2. **Emotion axes.** Now there is one axis (`energy`). How many does the story need?
3. **Distortion.** For how it comes from the axis only.
4. **Midnight.** What happens when the clock passes 24:00?
5. **Mood presets.** Thresholds are constants now. They should move to `MoodPreset` `.tres` files.
