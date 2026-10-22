# GittyDot 0.2.0

Status: planned. The current package remains 0.1.0. This backlog records the user's reported issues with the Commit dock and editable working-file comparisons. Release 0.2.0 should address all five items below; a recorded requirement is not a completed fix.

## 1. Narrow Commit dock

- Keep the entire dock anchored to its left edge when resized. Changelist names, folder labels, filename prefixes, commit-message labels and action rows must not slide off the left side.
- Keep staging checkboxes visible and usable at the right edge, including checked, unchecked and partially checked folder/group states.
- Truncate long names at the end with an ellipsis and expose the full path in a tooltip. Preserve indentation and expand/collapse affordances.
- Reflow or compact toolbars at narrow widths rather than letting their minimum widths displace the whole layout. Match the native Scene dock's behavior as the reference.
- Investigate minimum-width propagation, centered horizontal growth and clipping in the dock layout. The screenshot establishes clipping; its precise runtime cause still needs a resize reproducer.

Acceptance: resize the dock through approximately 320, 260, 220 and 200 logical pixels, and repeat at increased editor scale. Test long names, nested folders, a long branch/changelist name and partial staging. Prefixes remain visible; checkboxes can still be toggled without a horizontal scroll workaround.

Primary implementation areas: `changes_panel.gd`, `changes_panel.tscn`, `sync_bar.gd`, and the outer dock containers.

## 2. Change signs in editable comparisons

- Add dedicated non-editable change gutters using the same +/− semantics as committed diffs: additions show +, deletions show −, and replacements show − on the previous version and + on the working version.
- Represent modified ranges and deletions that have no surviving right-hand line clearly. Keep adjacent changes grouped rather than drawing disconnected markers for each line.
- Signs, markers and any alignment decorations must never become part of the editable text or saved file.

Acceptance: compare an addition, deletion, replacement, a multi-line hunk and an initial/new file against the committed-diff renderer. Saving, Undo, copying source text and partial staging preserve the actual file contents.

Primary implementation area: `working_diff.gd`, with `diff_view.gd`/`DiffRows` as the read-only reference.

## 3. Finding edits

- Provide a visible change gutter and a minimap/overview with changed ranges, anchored to the visible editor pane.
- Clicking an overview marker or change gutter should reveal the corresponding edit without modifying the file. Include an indication of the current viewport.
- Keep navigation usable after insertions/deletions, resizing, scrolling, Undo and auto-save. Preserve synchronized horizontal scrolling and corresponding-source-line vertical scrolling.
- Account for the current full-content CodeEdits inside outer ScrollContainers. Simply enabling CodeEdit's minimap may not provide a viewport-sized overview; validate it in the real dock rather than assuming it works.

Acceptance: edits near the beginning, middle and end of a long file are discoverable and reachable. Test added/deleted ranges, narrow panes, large horizontal overflow and successive edits without stale markers or caret jumps.

Primary implementation area: `working_diff.gd` and its scroll/highlight integration.

## 4. Consistent diff colors

- Match editable working-file comparisons to the committed-diff editor's addition/deletion backgrounds and stronger intraline highlights.
- Reuse shared diff palette definitions instead of applying the script-gutter modification palette to the diff workspace.
- Keep palette changes local to diff components. Preserve the previously requested native script gutter/preview styling.

Acceptance: open equivalent content changes in working-file and committed comparisons. Addition/deletion blocks, replacement spans, unchanged text and selection contrast should match in both diff layouts. Verify actual rendered colors in a graphical Godot session.

Primary implementation areas: `working_diff.gd`, `diff_view.gd` palette constants, and configurable highlight rendering.

## 5. Open in Editor

- Enable Open in Editor for an existing project-local script and open its updated working-file contents in Godot's Script editor.
- Flush comparison edits first. Preserve competing unsaved native drafts and report save/open failures with the existing Console-details action.
- Review the current ResourceLoader.exists-based enablement condition. A normal existing .gd file is intended to be enabled; the reported disabled-script case needs reproduction before assigning its exact cause.
- Handle newly created/untracked scripts and resource-cache/import timing. Show a clear reason when the action is unavailable for an actually missing, unsupported or out-of-project file.

Acceptance: modified, partially staged, newly created and untracked .gd files open with the updated contents. Repeat immediately after editing, with auto-save disabled, and while the native script editor has an unsaved draft. Historical comparisons open the available current working file; deleted files explain why opening is unavailable.

Primary implementation areas: `gittydot_screen.gd` and `editor_open.gd`.

## Release checks

- Implement and verify both the installed addon and the standalone repository, preserving their packaging differences.
- Preserve working-file auto/manual saving, recovery, native Undo, partial staging, historical/index read-only behavior and the existing Git backend.
- Add regression coverage for the failures above, including real narrow-dock screenshots and graphical diff navigation/color checks. Existing passing tests do not establish that these reported issues are fixed.
- Set plugin metadata and release documentation to 0.2.0 when shipping the completed update.
