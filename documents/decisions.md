# Oh Darling: Decision Log

This file records technical and design decisions for the team and for Claude Code.
The GDD (`documents/gdd.md`) says WHAT the game is. This file says WHY we built it this way.

**How to use this file**

- Add a new entry when the team makes a decision. Put the newest entries at the end of its section.
- Do not delete an old entry. Change its status to `Replaced` and write the new entry number.
- Each entry has a status:

| Status | Meaning |
| --- | --- |
| **In code** | The decision is in the code in the snapshot of 2026-11-24. |
| **Planned** | The team agreed on it. The code does not have it yet. |
| **Check** | It is only in a chat, or the code and the README disagree. Ask the team before you rely on it. |
| **Replaced** | A later entry changed it. |

Sources: the design chats of 2026-11-06 to 2026-11-09, the README, the code snapshot of 2026-11-24, and the group chat of 2026-11-25 (section 7).

---

## 1. Project setup

### D01. Engine and tools
**Status:** In code
- Godot **4.7**, Forward Plus renderer, Jolt Physics, typed GDScript.
- Dialogue: the **Dialogue Manager** plugin (`.dialogue` files).
- The game has a 3D world, an isometric camera, and a painterly look.

**Check:** `project.godot` also turns on the editor plugins `gittydot` and `godot_vim`. They were not in the snapshot. If they are not in the repository, other people get an error when they open the project. Commit them, or turn them off.

### D02. Folders: by feature, and snake_case
**Status:** In code
- Scenes and scripts stay together, grouped by feature. Raw assets go by type (`art/`, `audio/`).
- Each person owns a folder. This gives fewer Git conflicts.
- All names use `snake_case`.

`scenes/world/` exists since 2026-11-25 (D27). Planned folders that do not exist yet: `scenes/ui/`, `scenes/camera/`, `scenes/main/`.

### D03. Language of the team documents
**Status:** In code
README and code banners use short sentences and simple words (mostly ASD-STE100). Each autoload starts with a banner comment: task, data, signals, public functions, and a "MUST NOT" list. Read it before you change the script.

### D32. Resolution 1920 x 1080
**Status:** In code (2026-11-26)
`project.godot` sets the viewport to 1920 x 1080. The stretch mode stays `canvas_items` with aspect `expand`. On a 1080p screen with a taskbar, the window can be larger than the free space. Then use full screen or maximize the window.

---

## 2. Architecture

### D04. Autoloads: one task each
**Status:** In code

| Autoload | Task |
| --- | --- |
| `GameManager` | Game state: `MAIN_MENU`, `EXPLORATION`, `DIALOGUE`, `PAUSED`. Opens dialogues. |
| `TimeManager` | The clock. |
| `EmotionManager` | The hidden emotions, the mood, the Distortion level. |
| `SaveManager` | One autosave file. |
| `AudioManager` | Music stems. |
| `UiManager` | Menus and HUD. The name is `UiManager`, not `UIManager`. |
| `DebugPanel` | Debug tool. It is not a game manager. |

`DialogueManager` is the plugin autoload. Only `GameManager` talks to it.

### D05. Managers send signals. They do not call each other.
**Status:** In code
- Only `EmotionManager` changes emotion values. Only `TimeManager` changes the clock.
- Other scripts ask, or listen. Connect to a signal in `_ready()`, and read the first state once.
- Do not read a manager in `_process()`.

### D06. Only `GameManager` opens a dialogue
**Status:** In code
- Call `GameManager.start_dialogue(resource, title)`.
- Reason: the state must change to `DIALOGUE` BEFORE the balloon opens. Then the player cannot click the world during a dialogue.
- The plugin signal `dialogue_ended` was not sure to exist in every version. So `GameManager` listens to it if it exists. If the balloon does not send it, the balloon calls `GameManager.end_dialogue()`.

### D07. World input works only in `EXPLORATION`
**Status:** In code
- Continuous movement is polled in `_physics_process()`, with a state check at the top.
- One-shot actions (interact, pause) use `_unhandled_input()`.
- Reason for polling: with events only, a key released during a dialogue is never seen, and the player runs when input comes back.
- Do not pause the tree for a dialogue.
- The balloon must stop its own mouse and key input, so a click on it does not reach the world.

### D08. Data goes in `.tres` files, not in code
**Status:** Planned
Mood presets, schedules, and NPC data are Resources. The code has only the Resource scripts that exist so far. `data/` is empty in the snapshot.

### D09. The player never sees hidden numbers
**Status:** In code
Only the debug panel shows them. The player reads the world.

---

## 3. World objects

### D10. Composition, not inheritance
**Status:** In code (this replaces an earlier answer that said "inheritance")
- Objects are made from small components. Each component has one job.
- Reason: objects may change shape, dialogue and interaction mode by mood and Distortion level. Many optional behaviours need composition.
- `item.tscn` and `npc.tscn` are prefabs with the wiring already done. Make an NPC with *New Inherited Scene* from `npc.tscn`. Do not edit `npc.tscn`.
- A component never uses `get_parent()`. It knows only what an export gives it.
- If NPCs walk later, a wrapper scene (`CharacterBody3D`) holds the `npc` scene as a child.

### D11. `InteractionComponent` rules
**Status:** In code
- Hover outline and click work only if the player is in range. Default 6 m. `0` means no limit.
- A key (Alt, or right mouse button) shows a highlight on all usable objects.
- Other components stop it with `block(source)` and free it with `unblock(source)`. They do not use `enabled`. Each source has its own block, so two sources cannot remove each other's block.
- It sends the signal `interacted`. It works only in `EXPLORATION`.
- `target_mesh` is a node export. Open the instance with **Editable Children**, so the default mesh stays set.

**Check:** In a nested scene, `target_mesh` can show as null. An old chat gave a fix: change it to `@export_node_path` and find the node in `_ready()`. The team did not use it. Use it if the bug comes back.

### D12. One scene for each place. Data decides what is visible.
**Status:** In code (`ConditionGate`). Replaces the first idea (`StateLayer`).
- Do not make one scene for each day or time. 10 days x 3 times x 5 moods is too many files.
- Three axes, three tools:

| Axis | Tool |
| --- | --- |
| Mood and Distortion | Screen filters and shader presets (D15) |
| Time of day | Light presets (`TimeOfDayPreset`, planned) |
| Day and story | `ConditionGate` |

- First try an `if` in the `.dialogue` file. Use a `ConditionGate` only when an object must appear, disappear, or stop being clickable.
- `ConditionGate` conditions: day range, hour range, moods, minimum Distortion, story flags, invert. Effects: hide target, block interaction, locked dialogue title.
- A gate checks when the scene loads. After that it checks only in `EXPLORATION` (see D13).
- For the prototype, each place is a sub-scene inside one town scene (D24). The rule "do not make one scene for each day or time" stays.

### D13. Staging Rule: an object never changes while the player looks at it
**Status:** Planned (partly in code)
- The `ConditionGate` already waits for the end of a dialogue.
- The reusable node `OffscreenSwapper` (change when the object is out of view) is not in the code yet. It belongs to T11.

### D14. NPCs change place only through one function
**Status:** Planned (T07)
- The function is `go_to_spot(spot)`. It teleports now.
- Reason: the clock moves only during dialogues, so the player never watches an NPC walk. If NPCs walk later, only this function changes.
- Not in the prototype (D26).

### D27. Greybox town
**Status:** In code (2026-11-25)
- `scenes/world/town.tscn` holds `Streets` and the 4 places under `Places`. Each place has its own file in `scenes/world/places/<place>/`. Repeated props are in `scenes/world/props/`.
- The town is 60 x 60 m (it was 100 x 100 until 2026-11-26; made smaller because the player only walks, at 1.35 m/s). Home to Town Hall takes about 27 s. The square is in the centre, home north-west, Town Hall north-east, Neon Padma south-west, the park and Roger's shelter south-east.
- Everything is CSG (`CSGBox3D`, `CSGCylinder3D`) with `use_collision`. Reason: it is fast to change. Artists replace it later, place by place.
- The camera looks from the south-east. So the north and west walls are 3 m high, and the south and east walls are 1 m high (cutaway).
- Test NPCs: `scenes/characters/npcs/` (mayor, pr_agent, neha, roger), inherited from `npc.tscn`. Test items use the files in `dialogue/test_characters/`.
- The NPCs have no physics body, so the player can walk through them. A body belongs in `npc.tscn` (T06) if the team wants it.

### D28. Dark interiors
**Status:** In code (2026-11-25)
- Problem: the rooms have no roof, so the sun lit them fully, and the 1 m walls cast odd shadows.
- Fix: each building has an `Exterior` node with the roof and the upper south and east walls. They block the sun. Window holes (CSG subtractions) let sun patches in.
- `OmniLight3D` lamps without shadows light the room. A `ReflectionProbe` with `interior` on gives a dark ambient light inside.

### D29. `InteriorZone`: the outside disappears when the player is inside
**Status:** In code (2026-11-25)
- An `Area3D` component in `scenes/components/interior_zone/`. While the player is in it, the `Exterior` parts change to "shadows only". So they are not visible, but the light inside does not change.
- An instant switch, not a fade. Reason: a fade needs transparent materials, and CSG with transparency sorts badly. A fade needs a dither shader. That can come later.
- **Rule:** a big `Area3D` must have `input_ray_pickable` off. The first version did not, and it caught every mouse click inside the building.
- Known issue: outside, a building can hide the player when the player walks behind it (north or west of it). The fix (fade the building between the camera and the player) is not done.

### D30. Character model slot, UAL mannequin and AnimationTree
**Status:** In code (2026-11-26)
- The player and `npc.tscn` have a `Model` node (`CharacterModel`) with the model (`Character`) and an `AnimationTree`. `Model` turns toward the walk direction and sends the speed to the tree. Only `Model` turns, because the camera is a child of the player body.
- Model and animations: the **Universal Animation Library** (Quaternius, CC0), `art/models/characters/ual/UAL1_Standard.glb`, without root motion (the code moves the body). It is imported with a humanoid `BoneMap`, so any humanoid model retargeted the same way can use its 43 animations.
- `locomotion.tres` is a `BlendSpace1D` on speed: `Idle` at 0, `Walk` at 1.35 m/s and `Jog_Fwd` at 4.0 m/s. Reason: the standard Godot way, and the designer can edit it in the AnimationTree editor.
- The character walks with the normal `Walk` (`Walk_Formal` was tried and looked too elegant). Holding Shift (the Input Map action `jog`) makes it jog with `Jog_Fwd` at 4.0 m/s: 4.92 m per cycle at 1.80 m, slowed to 0.76x (custom timeline 1.23 s; first 5.29 m/s, too fast) (decided on 2026-11-26). No sprint. The walk plays 1.4x faster than in the file (custom timeline 0.95 s, `stretch_time_scale`). The model is scaled to 1.80 m (0.984). So one cycle is 1.28 m in 0.95 s, and the player speed is 1.35 m/s. The distance was measured from the root-motion version of the file. If the speed, the scale or the timeline changes, the other values must change too, or the feet slide.
- First version (replaced the same day): a generated box rig with hand-made bone animations. It was removed, because a real imported model tests the real pipeline.
- The NPC click shape is a capsule (`fit_collision_to_mesh` off), because the mesh is in a T-pose and 1.9 m wide. The NPC colour is `surface_material_override/0` on the mannequin.
- Import bug: "Remove Tracks → Except Bone Transform" deletes almost all tracks in Godot 4.7.2. Keep it off.

---

## 4. Emotion, mood and look

### D15. Mood and Distortion are calculated from four axes
**Status:** In code. **Not in the GDD.** Add it to the "Technical specification" section.
- Axes (each from -1 to 1): `dereism`, `energy`, `paranoia`, `self_perception`.
- The side is the sign of `self_perception + energy`. If it is 0, the last side stays.
- Intensity = `0.5 * side * energy * |energy| + 0.35 * dereism + 0.15 * paranoia^2`, limited from 0 to 1.
- The mental state (side x intensity) chooses the mood:

| Distance from 0 | Low side | High side |
| --- | --- | --- |
| up to 0.25 | `clear` | `clear` |
| up to 0.5 | `overcast` | `bright` |
| up to 0.75 | `fog` | `storm` |
| above 0.75 | `fog` | `storm` (the "Echo zone": no extra effect yet) |

- Distortion exists only in `fog` and `storm`. It comes from `dereism`: 0.25 gives level 1, 0.5 gives level 2, 0.75 gives level 3.
- Moods are strings: `"fog"`, `"overcast"`, `"clear"`, `"bright"`, `"storm"`. Distortion is an integer from 0 to 3.
- Dialogue files ask only for the mood **name**. The thresholds stay in `EmotionManager`.

### D16. Mood and Distortion visuals are screen filters
**Status:** In code. **Check:** the README says something different.
- Code: `art/shaders/mood_filter.tscn` has one child for each mood. The child name is the mood name. It fades between them when `mood_changed` comes. `distortion_filter.tscn` shows level 2 (sway) and level 3 (shatter). Add both to a level scene.
- README (T05): `MoodPreset` Resources and an `EnvironmentController` that tweens light, fog and camera values. This is not in the code.
- Ask the team: do the filters replace the presets, or do both stay? Change the README or the code to match.

### D17. Camera
**Status:** Planned (T04)
- The camera is a child of the player now. If the camera becomes a separate rig, the player movement code must change, because it reads the camera direction.
- GDD: the camera changes only in extreme moods (Storm: it sways. Fog: it moves back).

### D31. Camera controls in the style of Disco Elysium
**Status:** In code (2026-11-26). T04 has no owner yet. Tell the T04 owner.
- `scenes/camera/player_camera.gd` on the player camera. The mouse wheel zooms (0.45x to 1.4x of the default distance). When the mouse leaves the screen centre (dead zone 20%), the camera moves up to 3.5 m toward it, on the ground plane. Both are smooth.
- It only changes the camera position, never the rotation. Reason: the player movement reads the camera direction (D17).
- It works only in `EXPLORATION` (D07). In other states the view stays where it is.

---

## 5. Time, save and debug

### D18. The clock moves only in dialogues
**Status:** In code. This is in the GDD.
A new game starts on day 1 at 07:00. `TimeManager.advance(minutes)` moves the clock. `is_between(start_hour, end_hour)` supports ranges that cross midnight (22 to 4).

### D19. Autosave only, one slot
**Status:** In code, but see the check.
- One file: `user://autosave.json`, with a `SAVE_VERSION`. A temp file is used when it writes. Each person has a save on their own computer. It is not in the repository.
- Change `SAVE_VERSION` when old saves are no longer valid.
- To save new data: give the script `get_save_data()` and `load_save_data(data)`. Add one line in `SaveManager.save()` and one in `SaveManager.load_game()`.

**Check:** the autosave time.
- The GDD loop says "after each choice".
- In the code, `end_dialogue()` does not save (the call is a comment). Only `on_choice_made()` saves, and the balloon must call it. The banner of `game_manager.gd` still says "autosave when a dialogue ends".
- Open question: what does "Continue" do if the player quit in the middle of a dialogue?
- The prototype does not save (D25). This question can wait until after the prototype.

### D20. The debug panel is an autoload scene
**Status:** In code
- It is in `core/debug_panel/`. It is the last autoload. F1 opens it in any scene, also with F6.
- It removes itself in a release build. No game code may call it.
- It uses only the public API, plus `EmotionManager.debug_get_axis()` and `debug_get_mental_state()`. Game code must not call those.
- Reason: if `GameManager` loaded it, `core/` would depend on a feature folder, and the "one task" rule would break.
- In a debug build, `GameManager` starts a new game when it loads. The README says this deletes the save file.

### D21. Tweens
**Status:** In code (rule)
Do not call `create_tween()` before you know that you will add at least one tweener. An empty tween gives the error "started with no Tweeners". (The first case was in `AudioManager._apply_mood()`.)

---

## 6. Git and team

### D22. Git rules
**Status:** In code (README section 8)
- Do not commit `.godot/`. Do commit `addons/`, `project.godot`, `default_bus_layout.tres`.
- Save the audio bus layout in the Audio panel. If you do not, Git has nothing to commit.
- One branch for each task. Small commits. Merge into `main` often.
- Only the lead changes autoloads, signals, the Input Map and `project.godot`. Tell the team.
- Do not edit the same `.tscn` as another person. Say in the group chat when you take a scene.
- After a pull that changes `project.godot`, use *Project → Reload Current Project*.

**Check:** the snapshot has a stray file `scenes/test/test_scene.tscn3894257751.tmp`. Delete it. Add `*.tmp` to `.gitignore`.

---

## 7. Prototype (December 6)

Proposed in the group chat on 2026-11-25. The team has not answered yet. When the team agrees, change the status of D23 to D26 to **Planned**.

### D23. The prototype is day 1 only
**Status:** Check
- Deadline: 2026-12-06. The prototype is day 1 of the story, playable from start to end. It is the vertical slice (T16).
- The full game is one in-game week, about 2 to 6 hours. (The example in D12 says 10 days. The number of days is not final.)
- Places: home, Town Hall, Neon Padma, Roger's shelter, and the streets with a part of the town outside.
- Reason: the time goes into dialogues and story. The professors said that good dialogue is our main effort.
- Rule: make a system only if the game uses it 3 or more times. Otherwise, use an `if` in the `.dialogue` file or a `ConditionGate`.
- The README has a "Prototype" column in the task list.

### D24. One town scene, no level loading
**Status:** Check
- All places are in `scenes/world/town.tscn`. Each place is a sub-scene with its own file, so each person edits only their place. Only the T08 owner edits `town.tscn`.
- Open map: the player walks between the places. There are no doors (Q8, chosen on 2026-11-25).
- Reason: level loading needs a `Main` scene, spawn points, a new game state, and the level in the save. The prototype does not need this.
- After the prototype, if the town is too big for 60 FPS, the doors can load a scene. A door then changes only the way it moves the player.

### D25. No save in the prototype
**Status:** Check
- The prototype does not save or load. The main menu has no Continue button.
- The code of `SaveManager` stays. Only `on_choice_made()` saves. The dialogue balloon must not call it in the prototype.
- In a debug build, `GameManager.new_game()` deletes the save file. This is not a problem, because the prototype does not save.
- T14 and Q2 wait until after the prototype.

### D26. No NPC schedules in the prototype
**Status:** Check
- Put each NPC where it is on day 1. If an NPC moves during the day, put one instance in each place. A `ConditionGate` with hours shows the correct one.
- T07 (`NpcData`, `ScheduleEntry`, `ScheduleComponent`, `go_to_spot()`) waits until after the prototype. D14 stays for later.

---

## 8. Open questions

| # | Question | Where it matters |
| --- | --- | --- |
| Q1 | `StoryFlags` (T15) does not exist. `ConditionGate` looks for `/root/StoryFlags` and ignores flags if it is missing. Write the half-page proposal. The lead approves it, because it adds an autoload. | T15, T14, `ConditionGate` |
| Q2 | Autosave: after each choice, or at the end of a dialogue? What does "Continue" do after a quit in the middle of a dialogue? (D19) | T14, T02 |
| Q3 | Mood visuals: screen filters or `MoodPreset` Resources? (D16) | T05, T10 |
| Q4 | The GDD says exploration uses "point-and-click mouse and keyboard". The player uses WASD only. Change the GDD or the player. | GDD, T03 |
| Q5 | Above mental state 0.75, nothing new happens (the "Echo zone"). What should happen? | T11 |
| Q6 | Answered on 2026-11-26: no sprint. The player walks, and jogs while Shift is held (D30). `SPRINT_SPEED` was replaced by `JOG_SPEED`. | T03 |
| Q7 | The GDD sections "Technical specification" and "Design History" are empty. Fill them from D15 and this file. | GDD |
| Q8 | Answered on 2026-11-25: open map, no doors (D24). | T08 |
| Q9 | Does the prototype need these tasks, and how much of them: T04, T05, T10, T11, T12, T13, T15, T17? They are "Ask" in the README. | Prototype |
| Q10 | In day 1, the player asks Roger OR Neha about a name, and the afternoon dialogue changes. This needs one fact that more than one dialogue reads. Use a Dialogue Manager variable, or a small `StoryFlags` (T15)? | T15, T02, dialogues |
