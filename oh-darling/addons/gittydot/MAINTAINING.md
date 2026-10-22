# Maintaining GittyDot

GittyDot 0.1.0 is a fork of the Godit 1.1.1 package, for Godot 4.7.2 on Windows. The original MIT license and author attribution remain in LICENSE. UPSTREAM_README.md preserves the upstream instructions. upstream.json records the source package's checksums before customization.

## Source boundaries

- `util/git_cli.gd` retains the upstream process execution backend. Its command log is private and mutex-protected; consumers use `log_snapshot()`/`clear_log()`. `@tool` initializes the static mutex in the editor. SSH options are passed only through Git's argv; do not copy repository `core.sshCommand` into the editor environment. The remaining noninteractive prompt/editor environment overrides are restored on disable.
- `dock/widgets/git_console.gd` gates hard reset, destructive clean, forced push and global/system config writes before starting Git. Resolve aliases before classification, protect shell aliases, and honor global option prefixes and the `--` delimiter. Render output with `add_text()`, never parse untrusted output as BBCode.
- `util/repo_setup.gd` reloads the full GittyDot plugin path after initialization/publishing and excludes project-local agent temp folders from new repositories.
- `util/git_cli_repo.gd` retains the Git operations, with temporary paths redirected into the project's agent temp folder.
- Selected-commit amend validates branch ancestry, operation state, merges and GittyDot's Git 2.45.0 compatibility floor before mutation. It creates an `amend! <full hash>` helper with a normal commit (preserving hooks/signing) and autosquashes it, so duplicate subjects cannot select the wrong commit. Rebase conflicts retain recovery information in the Git directory; Abort removes the helper with a soft reset, restoring amendment staging. Continue/Skip clear recovery data when replay finishes.
- `dock/widgets/dialogs.gd` records UI diagnostics with stable console entry ids and exposes Show details in Console. `plugin.gd` binds/unbinds its navigation callback. Console output remains literal; diagnostic labels must not masquerade as executed Git commands. Preserve the draft and target on failure or cancellation, and block duplicate submissions during confirmation/commit.
- `plugin.gd` owns editor integration and lifecycle.
- `util/script_autosave.gd` owns automatic saving through Godot's native ScriptEditor API.
- `dock/gittydot_screen.gd` owns the central comparison screen and patch actions.
- `dock/widgets/working_diff.gd` owns full-file working-text buffers. The right CodeEdit is editable; the baseline is read-only. Never put diff signs, collapsed-context summaries or alignment padding in the editable text. Both ScrollContainers retain a common horizontal range; vertical scrolling maps actual source lines through changed regions. Preserve native CodeEdit Undo and caret during refreshes.
- Working-file saves check the disk baseline and competing native drafts, write/verify a project-local temporary file, recheck the baseline, then atomically replace the target without touching staging. Preserve BOM, newline style and final-newline state. `save_guard.gd` flushes these buffers before Git operations; failed saves block operations/navigation and retain recovery drafts. Auto-save shares the existing preference; manual Save stays available. Native script tabs synchronize after saves; clean cached scenes reload only on the explicit Open in Editor action.
- `dock/widgets/diff_view.gd` owns the resizable comparison panes. Both panes share aligned visual rows, patch selection and pixel scroll ranges; narrower/shorter versions retain blank comparison space as needed for alignment. Switching comparisons must refresh Godot's cached child extent so obsolete scrollbars disappear. Unified, image and scene/config views remain available.
- `dock/panels/history_panel.gd` sends file activations to the central comparison screen. Single-click selects a row; double-click/Enter emits the selected commit or stash revisions. The log never creates its own inline file diff.
- `dock/gutter/change_preview.gd` owns the compact inline preview. `util/inline_diff.gd` aligns changed lines and computes bounded character edits; `dock/gutter/inline_highlights.gd` paints subtle line tints and stronger character backgrounds before native syntax and selection. Glyph geometry comes from CodeEdit; editing clears stale geometry immediately. Godot's opaque deprecated background color is temporarily moved into equivalent native style backgrounds, since its private text canvas otherwise covers custom gutter drawing. Teardown restores the original theme overrides and leaves native line colors intact.
- `dock/filesystem/filesystem_colors.gd` owns native FileSystem decorations.
- `dock/panels/changes_panel.gd` retains upstream staging/commit/changelist logic with a focused dock layout and automatic staging disabled by default.
- Folder/group rows are deliberately non-selectable. Their context menus use direct `gui_input` hit testing; do not rely solely on `item_mouse_selected`. `util/tree_folders.gd` stores the exact repository-relative folder path in row metadata. Folder stage/unstage actions affect displayed descendants and preserve unrelated staging.
- Ignore actions append anchored literal rules, escape glob characters and spaces, retain existing rules, and leave the index and disk files intact. Already tracked files stay tracked. The Commit and native FileSystem menus expose these actions for files and folders.

Changes to Git operations should be narrowly scoped. Do not replace the backend with shell command strings: argv must remain separate arguments. Preserve partial staging and unsaved buffers. Never auto-commit, auto-push, or auto-stage by default.

## Observable behaviour

Auto-save is enabled by default. Editing an open, project-backed script schedules a native save after 350 milliseconds without another edit. Losing application focus flushes pending edits. Explicit staging and Git operations flush pending script saves first. The native editor owns serialization, saved markers and Undo; the plugin does not write editor buffers directly.

If a file disappears or changes on disk after its editor baseline was captured, automatic saving pauses. A matching editor reload adopts the new baseline. An external change to a clean but stale editor buffer must also block its next save. Saving automatically does not stage any changes. Unsaved changes in the native Scene editor and untitled or embedded scripts still require the native save workflow before Git operations; raw scene text in the working-file pane uses its guarded text-save flow.

The central diff defaults to HEAD versus the working file. This includes staged and unstaged changes together. New files compare against an empty baseline. Side-by-side working-file comparisons expose full text editing with filtered/context/structured views and hunk actions disabled. Unified, staged and historical comparisons remain read-only; applicable inspection modes expose stage, unstage and revert actions. Applying a patch must fail safely when its context no longer matches. HEAD comparison does not apply patches because its patch is not necessarily valid against a partially staged index.

FileSystem badges decorate suffixes, preserving filenames and metadata. Disable/re-enable must remove hooks without losing editor buffers, removing engine UI, or freeing a registered submenu twice.

## Verification

From the project root:

```powershell
python tools/test_gittydot.py --godot 'C:\Tools\Godot\Godot.exe'
```

The runner creates an isolated project and Git repository inside `<project-name>-temp-chatgpt/gittydot`, copies the addon, and executes the editor checks on a portable headless Godot. It never stages or commits the game repository. Every fixture retains its result JSON and editor log for inspection.

The checks cover real editor saves and Undo, external-change protection, partial staging, central patch staging/unstaging, configuration-file opening, FileSystem suffixes, commit/amend, preference persistence, and plugin teardown/re-enable. Inline-preview checks exercise layout, narrow-editor bounds, previous-code display, rollback and Undo, Show Diff routing, Escape, character edits, continuous bars, native glyph geometry, clipping and cleanup. Split-pane checks cover alignment, divider resizing, two-way scrolling on both axes, common end ranges, patch selection and overflow-to-short scrollbar cleanup. Add `--visual` for hidden graphical editor captures and pixel checks of actual insertion/replacement backgrounds, including the final character and modification colors in the previous version. These checks do not prove visual polish, remote authentication, every upstream branch operation, or compatibility with other Godot versions.

## Updating upstream

Read upstream changes against upstream.json and the original package. Port backend fixes individually; avoid overwriting GittyDot's integration files with the upstream plugin entry point. Re-run the editor checks and inspect the Commit dock, central diff and FileSystem in a graphical Godot session. Update plugin.cfg, README.md and the baseline manifest when deliberately adopting a new upstream package.

## Remaining work

This first release establishes the integrated workflow. Exact IntelliJ toolbar matching, multiple concurrent diff tabs, broader keyboard shortcuts, image/scene workflow polish remain future work. Godot's internal FileSystem controls need verification when upgrading the engine.

## Repository layout

Runtime resources are under `addons/gittydot/`; the unused upstream combined dock is omitted. Verification code lives in `tests/editor_checks.gd`, and `tools/test_gittydot.py` creates disposable test projects. Repository documentation, provenance and license files are kept once at the root. When distributing the addon alone, include the root LICENSE with it. The root .gdignore prevents duplicate imports when the repository is placed inside another Godot project.
