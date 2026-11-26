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
             (scenes/components/ = reusable parts: interactables, condition_gate,
              interior_zone)
             (scenes/world/ = the town, the places, the props)
             (scenes/characters/ = the player and the NPCs in npcs/)
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

- One sub-scene for each place. Do not copy a scene for each day or time.
- The player is in the group `player`. Objects use this group to measure the distance.
- Do not edit the same `.tscn` file as another person at the same time.

### The town scene (prototype)

For the prototype, all of day 1 is in ONE scene: `scenes/world/town.tscn` (T08). Each place is a sub-scene with its own file. The town scene has an instance of each one.

```
Town (Node3D)
├── DirectionalLight3D
├── WorldEnvironment
├── Streets                instance of streets/streets.tscn (roads, square, park, other buildings)
├── Places (Node3D)
│   ├── Home               instance of places/home/home.tscn
│   ├── TownHall           instance of places/town_hall/town_hall.tscn
│   ├── NeonPadma          instance of places/neon_padma/neon_padma.tscn
│   └── RogerShelter       instance of places/roger_shelter/roger_shelter.tscn
├── Player
├── MoodFilter
└── DistortionFilter
```

- Edit only the sub-scene of your place. Only the T08 owner edits `town.tscn`.
- **Open map.** There is no level loading and there are no doors. The player walks from place to place.
- The town is a greybox: CSG boxes with `use_collision`. Small props that repeat (tree, market stall) are in `scenes/world/props/`.
- The camera looks from the south-east. So the north and west walls of a building are 3 m high, and the south and east walls are 1 m high (a cutaway).

A building (home, Town Hall, Neon Padma) has this structure:

```
Home (Node3D)
├── Floor, Walls           visible, with collision. Window holes are CSG subtractions.
├── Furniture              props, items and NPCs
├── Exterior (Node3D)      roof and upper south and east walls, no collision
├── Lights                 OmniLight3D lamps, no shadows
├── InteriorAmbient        ReflectionProbe, "interior" on: a dark ambient light inside
└── InteriorZone           hides Exterior while the player is inside (see section 5)
```

The roof and the upper walls block the sun, so the room is dark. Light comes in only through the windows and from the lamps.
- An NPC that is in two places during the day has one instance in each place. A `ConditionGate` with hours shows the correct one.

### Player

The game runs at 1920 x 1080 (`project.godot`, display settings).


`player.tscn` is a `CharacterBody3D`. It moves with **WASD**, relative to the camera, and stops outside `EXPLORATION`. The camera is a child of the player.

### Input Map

| Action | Key |
| --- | --- |
| `move_left`, `move_right`, `move_up`, `move_down` | A, D, W, S |
| `pause` | Escape |
| `debug_toggle` | F1 |
| `highlight_interactables` | Alt, or right mouse button |
| `jog` | Shift (hold) |

---

## 5. How to add things

### Add an item

1. Drag `scenes/components/interactables/item.tscn` into the scene.
2. Right-click it and choose **Editable Children**.
3. On `MeshInstance3D`, set the mesh.
4. On `InteractionComponent`, set `dialogue_resource` and `dialogue_title`.

### Add an NPC

1. Do not edit `npc.tscn`. Choose *Scene → New Inherited Scene* from `scenes/components/interactables/npc.tscn`.
2. On `InteractionComponent`, set `dialogue_resource` and `dialogue_title`. `target_mesh` and the click shape (a capsule) are already set.
3. For a colour, set `surface_material_override/0` on `Model/Character/Armature/GeneralSkeleton/Mannequin`. For a real model, see "Add a character model".
4. Save it in `scenes/characters/npcs/` (see `scenes/characters/npcs/mayor.tscn` for an example).
5. Put the dialogue files in the folder of the character in `dialogue/`.

### Add a character model

The player and every NPC have the same model setup:

```
Player / Npc
├── Model                  CharacterModel: turns toward the walk direction, sends the speed
│   ├── Character          the model (now: the UAL mannequin, art/models/characters/ual/)
│   └── AnimationTree      blends the animations by speed (locomotion.tres)
└── ...
```

- The mannequin and its 43 animations come from the **Universal Animation Library** by Quaternius (CC0). It is imported with a humanoid `BoneMap` (`SkeletonProfileHumanoid`), so the bones have the standard humanoid names.
- `scenes/components/character_model/locomotion.tres` is a `BlendSpace1D` on speed (m/s): `Idle` at 0, `Walk` at 1.35, `Jog_Fwd` at 4.0. `Walk` plays 1.4x faster than in the file (custom timeline 0.95 s), `Jog_Fwd` 0.76x slower (custom timeline 1.23 s). Open it in the AnimationTree editor to change it.
- The player walks (`SPEED` in `player.gd`, 1.35 m/s) and jogs while Shift is held (`JOG_SPEED`, 4.0 m/s). No sprint. Each speed is the real speed of its animation. If you change one, change the other, or the feet slide.
- The mannequin is scaled to 1.80 m (0.984; the file is 1.83 m). The scale is on the `Character` node.
- Only `Model` turns. The player body does not turn, because the camera is its child.
- Other useful animations in the file: `Idle_Talking`, `Sitting_Idle`, `Sitting_Talking`, `Interact`, `PickUp_Table`, `Walk_Formal`.

**Import settings of a character `.glb`** (Advanced Import Settings, select `Skeleton3D`):

1. Retarget → Bone Map: New BoneMap. Then Profile: New SkeletonProfileHumanoid. Check that all bones are mapped.
2. Retarget → Remove Tracks: leave **"Except Bone Transform" off**. In Godot 4.7.2 it deletes almost all animation tracks (errors "Index p_track is out of bounds").
3. Reimport.

**To put in a new model:**

1. Export it as glTF (`.glb`), facing +Z. Import it with the settings above.
2. In the character scene, delete `Character` and add the new model as a child of `Model`. Name it `Character`.
3. On `AnimationTree`, set `Anim Player` to the AnimationPlayer of the model, and `Root Node` to the model.
4. If the model has no animations, it can use the animations of the mannequin, because the bone names are the same. Copy the mannequin's AnimationPlayer, or save its animations as an Animation Library.
5. On an NPC, set `target_mesh` of `InteractionComponent` to the `MeshInstance3D` of the model.

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

Another component (or a `ConditionGate`) stops the object with `block(source)` and frees it with `unblock(source)`. Do not use `enabled` for this. Each source has its own block, so two sources cannot remove each other's block.

Limits: do not scale the target mesh in a non-uniform way. Call `refresh()` after you change `target_mesh.mesh` in code. A wall or a `Control` in front of the object blocks the mouse.

### Show the inside of a building: `InteriorZone`

`scenes/components/interior_zone/interior_zone.tscn` is an `Area3D`. While the player is inside it, every `GeometryInstance3D` under its `exterior` node casts shadows only. You cannot see the roof and the front walls, but the light inside does not change.

1. Put the roof and the upper walls under one node (`Exterior`).
2. Add `interior_zone.tscn` to the place scene. Give it a `CollisionShape3D` child that fills the room.
3. Set `exterior` in the Inspector.

It sends `player_inside_changed(inside)` (for example, for audio).

**Rule for all big `Area3D` nodes** (zones, triggers): set `input_ray_pickable` to off. If not, the area catches the mouse clicks, and the objects inside it cannot be clicked.

### Lock or hide something: `ConditionGate`

First try the dialogue file. If an object only needs a different line (closed shop, line for one mood), use an `if` in the `.dialogue` file. No node is needed.

Use a `ConditionGate` (`scenes/components/condition_gate/condition_gate.tscn`) when an object must appear, disappear, or stop being clickable.

1. Add the gate as a child of the object (use **Editable Children** on an instance).
2. In **Conditions**, fill in only what you need. All must be true. A field with its default value is ignored.
3. In **Effects**, drag in the nodes to change. Do not write these node fields by hand in a `.tscn` file.

| Conditions | Meaning |
| --- | --- |
| Min Day / Max Day | Day range. Max 0 = no limit. |
| From Hour / To Hour | Hour range. 22 to 4 crosses midnight. 0 to 24 = any time. |
| Moods | Ticked moods only. None ticked = any mood. |
| Min Distortion | Lowest Distortion level. |
| Required Flags | Story flags (T15). Always false until `StoryFlags` exists. |
| Invert | Reverse the result. |

| Effects | Meaning |
| --- | --- |
| Hide Target | Shown when true. Hidden and disabled (not clickable) when false. |
| Interaction | The `InteractionComponent` is blocked when false. |
| Locked Title | With Interaction: the object is not blocked. A click starts this dialogue title. |

Examples: a note from day 2 = Min Day 2 + Hide Target. An NPC away at night = From 7, To 22 + Hide Target. A shop closed after 19:00 = From 9, To 19 + Interaction + Locked Title.

It checks when the scene loads. After that it checks only in `EXPLORATION`, so a change waits for the dialogue to end (Staging Rule). For another effect, connect to its signal `changed(met)`. For a rule the fields cannot express, extend the script and override `_extra_check() -> bool`. It saves nothing.

### Make something depend on the mood

For an object that appears or hides by mood, use a `ConditionGate`. For anything else:

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

The prototype does not save (see "Prototype" below). Use these steps after the prototype.

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

# PROTOTYPE (December 6)

Proposed in the group chat on 2026-11-25. Wait for the team to agree (see `documents/decisions.md`, D23 to D26).

- **Goal:** day 1 of the story, playable from start to end.
- **Why:** the full game is one in-game week (about 2 to 6 hours). The prototype needs only day 1. The time goes into dialogues and story, as the professors said.
- **Places:** home, Town Hall, Neon Padma, Roger's shelter, and the streets with a part of the town outside.
- **One scene:** all places are in one town scene (see section 4). There is no level loading.
- **No save:** the prototype does not save or load.
- **No NPC schedules:** put each NPC where it is on day 1. If an NPC moves, use one instance for each place and a `ConditionGate` with hours.
- **Rule:** make a system only if the game uses it 3 or more times. Otherwise, use an `if` in the `.dialogue` file or a `ConditionGate`.

The cut systems are not lost. We can add them after the prototype.

# TASKS

Each task is one unit of work for **one** programmer. The status is on the Figma board.

The column "Prototype" shows what the prototype needs:

| Value | Meaning |
| --- | --- |
| Done | The code exists. |
| Needed | The prototype needs it. |
| Smaller | The prototype needs a small version. See the task text. |
| After | Not in the prototype. |
| Ask | Not decided yet. Ask the team. |

| ID | Task | Main folder | Prototype |
| --- | --- | --- | --- |
| T00 | Foundation | `core/`, `project.godot` | Done |
| T01 | Debug panel | `core/debug_panel/` | Done |
| T02 | Dialogue balloon | `scenes/ui/dialogue_ui/` | Needed |
| T03 | Player and movement | `scenes/characters/player/` | Done |
| T04 | Isometric camera rig | `scenes/camera/` | Ask |
| T05 | Painterly shader and mood presets | `art/shaders/`, `data/moods/` | Ask |
| T06 | Interaction system | `scenes/components/interactables/` | Done |
| T07 | NPC schedules | `scenes/characters/npcs/`, `data/` | After |
| T08 | World greybox and locations | `scenes/world/` | Smaller |
| T09 | HUD and menus | `scenes/ui/` | Smaller |
| T10 | Distortion effects | `art/shaders/` | Ask |
| T11 | Echoes | `scenes/components/echoes/` | Ask |
| T12 | Sensitive objects | `scenes/components/sensitive/` | Ask |
| T13 | Audio: stems, tuning, effects | `audio/`, `core/audio_manager.gd` | Ask |
| T14 | Save and load completion | `core/save_manager.gd` | After |
| T15 | Story flags | `core/` | Ask |
| T16 | Vertical slice: one full in-game day | everyone | Needed (this is the prototype) |
| T17 | Build, export and playtest | `export_presets.cfg` | Ask |

**T02 Dialogue balloon.** A custom balloon for the Dialogue Manager plugin, in the style of Disco Elysium: a scrolling log, inner voices, numbered choices, locked choices, a theme that follows the mood. It opens only through `GameManager.start_dialogue()`. If the plugin does not send `dialogue_ended`, the balloon calls `GameManager.end_dialogue()` when it closes. It may call `GameManager.on_choice_made()` after each choice (autosave). It must stop its own input, so a click on it does not reach the world.

**T03 Player and movement.** WASD movement in `EXPLORATION` only. The player walks (1.35 m/s) and jogs with Shift (4.0 m/s). No sprint. Contract: group `player`.

**T04 Camera rig.** A fixed-angle isometric camera that follows a target. It reacts to `mood_changed`: in Storm it sways a little, in Fog it moves back. Now the camera is a child of the player, with `scenes/camera/player_camera.gd` (Disco Elysium style): the mouse wheel zooms, and the camera moves a little toward the mouse when the mouse leaves the screen centre. Both only in `EXPLORATION`. The script only moves the camera, it never turns it. If the rig becomes separate, the player movement code (which reads the camera direction) must change too.

**T05 Shader and mood presets.** The five painted looks with **one** shader. A `MoodPreset` Resource with five `.tres` files. An `EnvironmentController` listens to `mood_changed` and tweens the values in 1 to 2 seconds. `MoodPreset` fields: `mood`, `hue_shift`, `saturation`, `value`, `palette`, `brush_size`, `light_color`, `light_energy`, `fog_density`, `camera_sway`, `camera_distance`, `ui_theme`. The game must stay at 60 FPS on a normal laptop.

**T06 Interaction system.** The `InteractionComponent` (see section 5). Contract: `dialogue_resource`, `dialogue_title`, the signal `interacted`, `block()`, `unblock()` and `is_available()`.

**T07 NPC schedules.** `NpcData` (`id`, `display_name`, `portrait`, list of `ScheduleEntry`). `ScheduleEntry` has `start_hour`, `end_hour` and `spot_id`. A `ScheduleComponent` on the NPC finds the active entry with `TimeManager.is_between()` and puts the NPC at the matching spot (`Marker3D` in the group `spots`). With no active entry, it calls `block(&"schedule")` on the `InteractionComponent`. (A `ConditionGate` with hours can do the simple cases.) The NPC changes place only through one function (`go_to_spot()`). Schedules are `.tres` files.
*Prototype: not needed. Put one NPC instance in each place, with a `ConditionGate` for the hours.*

**T08 World greybox.** A walkable town made of boxes: Town Hall with archive, Square, Neon Padma, Park and shelter, protagonist's home, two stores. Each place has a `Location` node with a `LocationData` Resource (`id`, `open_hour`, `close_hour`), and `is_open()` reads `TimeManager`. The scene holds the `spots` markers for T07. Keep node names stable.
*Prototype: one town scene (`scenes/world/town.tscn`) with home, Town Hall, Neon Padma, Roger's shelter, the streets and a part of the town outside (see section 4). Each place is a sub-scene. Not needed yet: `LocationData` and the `spots` markers. Open map (no doors).*
*Status (2026-11-25): the greybox exists. It has the town, the 4 places, the 4 test NPCs (`scenes/characters/npcs/`) and test items that use the dialogues in `dialogue/test_characters/`.*

**T09 HUD and menus.** The HUD clock listens to `time_changed`. The main menu has New Game, Continue (disabled without a save) and Quit. The pause menu has Resume and Back to menu (`process_mode` = "When Paused"). All screens register with `UiManager`. This task also makes the real `Main` scene.
*Prototype: there is no save, so the main menu has no Continue button (New Game and Quit only).*

**T10 Distortion effects.** The three visual levels from the GDD, driven by `distortion_changed`. Level 1: small anomalies (a signal for T11 and T12). Level 2: the room sways or tilts. Level 3: the scene breaks into fragments. Level 0 costs nothing.

**T11 Echoes.** Things the player sees that are not real. The tone follows the mood. An `EchoSpot` marker holds `echo_scene`, a `mood` filter and `min_distortion`. (A `ConditionGate` can do the mood and Distortion filter.) An Echo appears or disappears only outside the camera view, or after a dialogue. This task makes the reusable node `OffscreenSwapper` for this rule.

**T12 Sensitive objects.** The window, the mirror and the door. Each has an `InteractionComponent` and a `MoodVariants` component. `MoodVariants` holds a Resource that maps each mood (and Distortion level) to a dialogue title, a description and a visual variant. In Fog and Storm the object shows an Echo. Changes use `OffscreenSwapper`.

**T13 Audio.** Real stems in `AudioManager`, loops, the `MOOD_VOLUMES_DB` table, and `play_sfx(name)`. Fix the tween error in `_apply_mood()` first.

**T14 Save and load.** Add story flags, NPC state, player position and Dialogue Manager variables. Connect the autosave. Handle a broken save file with no crash. Autosave only: no manual save and no second slot.
*Prototype: not needed. The prototype does not save. The dialogue balloon must not call `GameManager.on_choice_made()`, because that function saves.*

**T15 Story flags.** One place for story facts. Write a half-page proposal first. The lead approves it, because it may add an autoload. Suggested API: `set_flag()`, `has_flag()`, the signal `flag_changed`, `get_save_data()` and `load_save_data()`.

**T16 Vertical slice.** One complete in-game day with Roger, Neha and the Mayor, and at least three moods. A new player must be able to play it with no crash.
*Prototype: this is the prototype. Day 1, ready on December 6.*

**T17 Build and playtest.** Export presets for Windows and Linux, a test on a clean computer, and a playtest with someone outside the team.
