# Oh Darling: Instructions for Claude Code

Oh Darling is a 3D narrative game. It is a group project for the 2026 VDP course at the Politecnico di Milano.
Engine: **Godot 4.7**. Language: **typed GDScript**. Dialogue: **Dialogue Manager** plugin (`.dialogue` files).

## Read these files first

- `documents/gdd.md`: the game design document. It says WHAT the game is. Do not change it unless the user asks.
- `README.md`: the project guide. It says HOW we work. It has the folders, the autoloads, the rules, the code style and the task list (T00 to T17). Follow it.
- The comment at the top of each autoload script. It lists the task, the data, the signals and the rules of that script. Read it before you change the script.

If the README and the code disagree, tell the user. Do not choose one by yourself.

## How you write to the user

- Use simple words. About 80% of the words must be in ASD-STE100.
- Use short sentences. One idea in each sentence.
- Use the active voice. Use one word for one thing.
- Give the result first. Then give the details.
- Use a code block for each command and each path.
- Use a table or a diagram when it makes the text easier to understand.

## Work rules

1. **Ask before you change a shared file.** Shared files are `project.godot`, any autoload in `core/`, and any `.tscn` file in a folder that the user does not own. Only the lead changes autoloads, signals and `project.godot`.
2. **Make small changes.** Change one thing. Tell the user what to test in Godot. Then continue.
3. **Do not edit these:**
   - `.godot/` (the import cache)
   - `addons/` (plugins)
   - binary files (models, textures, audio, `.import` files)
4. **Edit `.tscn` files with care.**
   - Do not write node references (`@export` of a node type) by hand. Tell the user to set them in the Inspector.
   - Do not rename or delete a node that other scenes use.
   - Keep node names stable.
5. **Do not edit the same `.tscn` file as another person.** Ask the user if somebody else has the scene.
6. **Do not guess the Godot API.** If you are not sure, say so. Godot 4.7 can differ from your memory.
7. **Prefer Godot's built-in solutions.** Use the nodes, resources, import options, project settings and Input Map that Godot already has (for example `AnimationTree` and `BlendSpace1D` for animation blending, import settings for models). Write custom code or generate assets only when no built-in fits, and tell the user why.

## Code rules (short version, see README section 3 and 7)

- Use static types and tabs. Use `snake_case` for names.
- Start private names with `_`. Name signals in the past tense (`mood_changed`).
- Managers do not call each other. They send signals.
- Only `EmotionManager` changes emotion values. Only `TimeManager` changes the clock.
- Only `GameManager` opens a dialogue: `GameManager.start_dialogue(resource, "start")`.
- World input works only in the `EXPLORATION` state.
- Put data in `.tres` files, not in code.
- Do not show hidden numbers to the player (only the debug panel can show them).
- A component does not use `get_parent()`.
- Do not use `class_name` in an autoload script.
- Do not call `create_tween()` before you add a tweener.
- The UI manager is named `UiManager`.

## Check your work

Godot must be installed on the computer. Use the same Godot version as the team.

```
godot --headless --import
godot --headless --quit
```

The first command imports the files. The second command starts the project and quits. Read the output for script errors and warnings. If the `godot` command does not exist, tell the user. Do not skip the check.

You cannot see the game window. After a change that the player can see, ask the user to press Play and tell you the result.

## Git

- Make one branch for each task. Name it with the task ID, for example `t06-interaction`.
- Make small commits. Write the message in the present tense, in English, with 72 characters or fewer in the first line.
- Do not commit `.godot/`.
- Do not push to `main`. Open a pull request.
- Do not commit the save file. It is in `user://autosave.json`, outside the project.
- After a pull that changes `project.godot`, the user must reload the project in Godot.

## Tasks

The task list is in `README.md`. The status of each task is on the team Figma board.
Until December 6, the team works on the prototype (day 1 only). The "Prototype" column in the README task list shows what is in it. Do not build a system that the column marks "After". Each task has one owner. If the user asks for work that belongs to another task, tell the user which task and which folder it is.

@documents/decisions.md