# oh-darling
A project for the 2026 Videogame Design and Programming (VDP) course at the Politecnico di Milano.

# Oh Darling: Project Guide

This file explains how to work in the Godot project. Read it before you add code.

Game design: see `gdd.md`. Engine: **Godot 4.7**. Language: typed GDScript.
Open the project, wait for the first import, and press Play. The main scene is `scenes/test/test_scene.tscn`.

---

## 1. Folders

```
core/        the autoloads (managers) and core/debug_panel/
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

## 2. Autoloads

An autoload is a script that Godot loads first and keeps for the whole game. Each one has ONE task. **Read the comment at the top of each script before you change it.** It lists the task, the data, the signals and the rules.

| Autoload | Task |
| --- | --- |
| `GameManager` | Runs the game state (`MAIN_MENU`, `EXPLORATION`, `DIALOGUE`, `PAUSED`). Opens dialogues. |
| `TimeManager` | Keeps the clock. It moves only in dialogues. |
| `EmotionManager` | Keeps the hidden emotions. Gives the mood and the Distortion level. |
| `SaveManager` | Writes and reads the one autosave file. |
| `AudioManager` | Plays the music stems. Follows the mood. |
| `UiManager` | Shows and hides menus and HUD. (The name is `UiManager`.) |
| `DebugPanel` | Debug tool. Not a game manager. |

`DialogueManager` is the plugin autoload. Only `GameManager` talks to it.

---

## 3. Rules

1. **Data changes in ONE place.** Only `EmotionManager` changes emotion values. Only `TimeManager` changes the clock. Other scripts ask, or listen.
2. **Managers do not call each other. They send signals.** Connect to a signal in `_ready()`. Do not read a manager in `_process()`.
```gdscript
func _ready() -> void:
	EmotionManager.mood_changed.connect(_on_mood_changed)
```
3. **Only `GameManager` opens a dialogue.** Call `GameManager.start_dialogue(resource, "start")`. Do not call `DialogueManager` directly.
4. **World input works only in `EXPLORATION`.** A script that reads input in the world must check `GameManager.state`, or listen to `state_changed`. Do not pause the tree for a dialogue.
5. **Data goes in `.tres` files, not in code.** Schedules and mood presets are Resources.
6. **Do not show hidden numbers to the player.** The player reads the world. (Only the debug panel may show them.)
7. **Components do not use `get_parent()`.** A component knows only what you give it (an export).

Moods are strings: `"fog"`, `"overcast"`, `"clear"`, `"bright"`, `"storm"`. Distortion is an integer from 0 to 3.

---

## 4. Basic scene structure

A level scene looks like `scenes/test/test_scene.tscn`:

```
Level (Node3D)
├── Player                 instance of player.tscn (has its own camera)
├── Item / NPC ...         instances of item.tscn and npc.tscn
├── Structure (Node3D)     floor and walls
├── Furniture (Node3D)     props that never change, invisible walls
├── DirectionalLight3D
└── WorldEnvironment
```

- One scene for each place. Do not copy a scene for each day or time.
- The player is in the group `player`. Objects use this group to measure the distance.
- Do not edit the same `.tscn` file as another person at the same time.

### Player

`player.tscn` is a `CharacterBody3D`. It moves with **WASD**, relative to the camera, and stops outside `EXPLORATION`. The camera is a child of the player.

### Input Map

| Action | Key |
| --- | --- |
| `move_left`, `move_right`, `move_up`, `move_down` | A, D, W, S |
| `pause` | Escape |
| `debug_toggle` | F1 |
| `highlight_interactables` | Alt, or right mouse button |

---

## 5. How to add things

### Add an item

1. Drag `scenes/interactables/item.tscn` into the scene.
2. Right-click it and choose **Editable Children**.
3. On `MeshInstance3D`, set the mesh.
4. On `InteractionComponent`, set `dialogue_resource` and `dialogue_title`.

### Add an NPC

1. Do not edit `npc.tscn`. Choose *Scene → New Inherited Scene* from `scenes/interactables/npc.tscn`.
2. Set the mesh on `MeshInstance3D`. Set `target_mesh` (the `MeshInstance3D`), `dialogue_resource` and `dialogue_title` on `InteractionComponent`.
3. Save it in `scenes/characters/npcs/` (see `scenes/characters/test_npc/test_npc.tscn` for an example).
4. Put the dialogue files in the folder of the character in `dialogue/`.

### Add a new kind of object

Make a scene with a `Node3D` root, a `MeshInstance3D` and an instance of `interaction_component.tscn`. Set `target_mesh` on the component.

### How `InteractionComponent` works

It makes one object clickable. The mouse is over the object and the player is close enough: the object shows an outline. A left click sends the signal `interacted` and starts the dialogue (if one is set). While the player holds `highlight_interactables`, all usable objects show a highlight. It works only in `EXPLORATION`.

| Field | Meaning |
| --- | --- |
| `target_mesh` | The `MeshInstance3D` that gets the overlays. The collision shape is made from it. |
| `dialogue_resource`, `dialogue_title` | What a click starts. The default title is `start`. |
| `interaction_range` | The player must be this close (meters). Default 6. `0` means no limit. |
| `hover_material`, `highlight_material` | The two overlays. |
| `enabled` | The owner's switch. |

Another component stops the object with `block(source)` and frees it with `unblock(source)`. Do not use `enabled` for this. Each source has its own block, so two sources cannot remove each other's block.

Limits: do not scale the target mesh in a non-uniform way. Call `refresh()` after you change `target_mesh.mesh` in code. A wall or a `Control` in front of the object blocks the mouse.

### Make something depend on the mood

1. Connect to `EmotionManager.mood_changed` in `_ready()`.
2. Read `EmotionManager.get_mood()` once, to set the first state.
3. Do **not** change an object while the player looks at it (GDD: Staging Rule). Change it when it leaves the frame, or after a dialogue.

### Write a dialogue

Files use the Dialogue Manager plugin format (`.dialogue`). Use tabs. The title (`~ start`) must match `dialogue_title`.

```
~ start
Roger: You come to my shelter again.
if EmotionManager.get_mood() == "storm"
	Roger: You see it too. The pig watches us.
else
	Roger: Are you well, archivist?

- Yes. The pig is a sign. [if EmotionManager.get_mood() in ["bright", "storm"]] => agree
- It is only junk. => deny

~ agree
do EmotionManager.shift("energy", 15)
do TimeManager.advance(20)
=> END
```

Dialogue files ask only for the mood **name**. The thresholds stay in `EmotionManager`. The files in `dialogue/test_characters/` are tests.

### Add a new screen

1. Make the scene in `scenes/ui/`.
2. In the UI root script: `UiManager.register_screen(&"my_screen", $MyScreen)`.
3. Add its rule in `UiManager._apply_state()`.

### Save new data

1. Give your script `get_save_data() -> Dictionary` and `load_save_data(data)`.
2. Add one line in `SaveManager.save()` and one line in `SaveManager.load_game()`.
3. Change `SAVE_VERSION` if old saves are no longer valid.

### Use a tween

Do not call `create_tween()` before you know that you will add at least one tweener. An empty tween gives the error "started with no Tweeners".

---

## 6. Debug panel

Press **F1** in any scene. It shows the state, the mood, the Distortion level, the day and the time. It has buttons to change the energy value and to move the clock. It is an autoload, so you do not add it to a scene. It does not exist in a release build.

In a debug build, `GameManager` starts a new game when it loads, and this deletes the save file.

---

## 7. Code style

- Use **static types**: `var day: int = 1`, `func advance(amount: int) -> void:`.
- Use `##` for documentation comments on public functions and signals.
- Use tabs, not spaces.
- Start private names with `_`: `_recalculate()`.
- Name signals in the past tense: `mood_changed`.
- Do not use `class_name` in an autoload script.
- Keep functions short. If a function has more than about 30 lines, split it.

---

## 8. Git

- **Each person owns a folder.** Ask the owner before you change a file in their folder.
- **Do not edit the same `.tscn` file at the same time.** Say in the group chat when you take a scene.
- **Use small commits and short branches.** Merge into `main` often.
- **Do not commit** the `.godot/` folder.
- A new autoload, a new signal or a change in `project.godot` needs the lead. Tell the team.
- If you pull a change in `project.godot`, reload the project (*Project → Reload Current Project*).

---

# TASKS

Each task is one unit of work for **one** programmer. The status is on the Figma board.

| ID | Task | Main folder |
| --- | --- | --- |
| T00 | Foundation | `core/`, `project.godot` |
| T01 | Debug panel | `core/debug_panel/` |
| T02 | Dialogue balloon | `scenes/ui/dialogue_ui/` |
| T03 | Player and movement | `scenes/characters/player/` |
| T04 | Isometric camera rig | `scenes/camera/` |
| T05 | Painterly shader and mood presets | `art/shaders/`, `data/moods/` |
| T06 | Interaction system | `scenes/interactables/` |
| T07 | NPC schedules | `scenes/characters/npcs/`, `data/` |
| T08 | World greybox and locations | `scenes/world/` |
| T09 | HUD and menus | `scenes/ui/` |
| T10 | Distortion effects | `art/shaders/` |
| T11 | Echoes | `scenes/interactables/echoes/` |
| T12 | Sensitive objects | `scenes/interactables/sensitive/` |
| T13 | Audio: stems, tuning, effects | `audio/`, `core/audio_manager.gd` |
| T14 | Save and load completion | `core/save_manager.gd` |
| T15 | Story flags | `core/` |
| T16 | Vertical slice: one full in-game day | everyone |
| T17 | Build, export and playtest | `export_presets.cfg` |

**T02 Dialogue balloon.** A custom balloon for the Dialogue Manager plugin, in the style of Disco Elysium: a scrolling log, inner voices, numbered choices, locked choices, a theme that follows the mood. It opens only through `GameManager.start_dialogue()`. If the plugin does not send `dialogue_ended`, the balloon calls `GameManager.end_dialogue()` when it closes. It may call `GameManager.on_choice_made()` after each choice (autosave). It must stop its own input, so a click on it does not reach the world.

**T03 Player and movement.** WASD movement in `EXPLORATION` only. Contract: group `player`. Open: sprint.

**T04 Camera rig.** A fixed-angle isometric camera that follows a target. It reacts to `mood_changed`: in Storm it sways a little, in Fog it moves back. Now the camera is a child of the player. If the rig becomes separate, the player movement code (which reads the camera direction) must change too.

**T05 Shader and mood presets.** The five painted looks with **one** shader. A `MoodPreset` Resource with five `.tres` files. An `EnvironmentController` listens to `mood_changed` and tweens the values in 1 to 2 seconds. `MoodPreset` fields: `mood`, `hue_shift`, `saturation`, `value`, `palette`, `brush_size`, `light_color`, `light_energy`, `fog_density`, `camera_sway`, `camera_distance`, `ui_theme`. The game must stay at 60 FPS on a normal laptop.

**T06 Interaction system.** The `InteractionComponent` (see section 5). Contract: `dialogue_resource`, `dialogue_title`, the signal `interacted`, `block()`, `unblock()` and `is_available()`.

**T07 NPC schedules.** `NpcData` (`id`, `display_name`, `portrait`, list of `ScheduleEntry`). `ScheduleEntry` has `start_hour`, `end_hour` and `spot_id`. A `ScheduleComponent` on the NPC finds the active entry with `TimeManager.is_between()` and puts the NPC at the matching spot (`Marker3D` in the group `spots`). With no active entry, it calls `block(&"schedule")` on the `InteractionComponent`. The NPC changes place only through one function (`go_to_spot()`). Schedules are `.tres` files.

**T08 World greybox.** A walkable town made of boxes: Town Hall with archive, Square, Neon Padma, Park and shelter, protagonist's home, two stores. Each place has a `Location` node with a `LocationData` Resource (`id`, `open_hour`, `close_hour`), and `is_open()` reads `TimeManager`. The scene holds the `spots` markers for T07. Keep node names stable.

**T09 HUD and menus.** The HUD clock listens to `time_changed`. The main menu has New Game, Continue (disabled without a save) and Quit. The pause menu has Resume and Back to menu (`process_mode` = "When Paused"). All screens register with `UiManager`. This task also makes the real `Main` scene.

**T10 Distortion effects.** The three visual levels from the GDD, driven by `distortion_changed`. Level 1: small anomalies (a signal for T11 and T12). Level 2: the room sways or tilts. Level 3: the scene breaks into fragments. Level 0 costs nothing.

**T11 Echoes.** Things the player sees that are not real. The tone follows the mood. An `EchoSpot` marker holds `echo_scene`, a `mood` filter and `min_distortion`. An Echo appears or disappears only outside the camera view, or after a dialogue. This task makes the reusable node `OffscreenSwapper` for this rule.

**T12 Sensitive objects.** The window, the mirror and the door. Each has an `InteractionComponent` and a `MoodVariants` component. `MoodVariants` holds a Resource that maps each mood (and Distortion level) to a dialogue title, a description and a visual variant. In Fog and Storm the object shows an Echo. Changes use `OffscreenSwapper`.

**T13 Audio.** Real stems in `AudioManager`, loops, the `MOOD_VOLUMES_DB` table, and `play_sfx(name)`. Fix the tween error in `_apply_mood()` first.

**T14 Save and load.** Add story flags, NPC state, player position and Dialogue Manager variables. Connect the autosave. Handle a broken save file with no crash. Autosave only: no manual save and no second slot.

**T15 Story flags.** One place for story facts. Write a half-page proposal first. The lead approves it, because it may add an autoload. Suggested API: `set_flag()`, `has_flag()`, the signal `flag_changed`, `get_save_data()` and `load_save_data()`.

**T16 Vertical slice.** One complete in-game day with Roger, Neha and the Mayor, and at least three moods. A new player must be able to play it with no crash.

**T17 Build and playtest.** Export presets for Windows and Linux, a test on a clean computer, and a playtest with someone outside the team.
