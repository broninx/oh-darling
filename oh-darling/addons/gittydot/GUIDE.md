# GittyDot usage guide

Detailed workflow instructions for **GittyDot 0.1.0**. Start with the [README](README.md) for installation, requirements, features, and known limitations.

## Workflow

### Review changes

Use the normal **FileSystem** dock to see file status. Select a changed file in **Commit**, choose **Git: Show Change** from the FileSystem context menu, or use **Show Diff** in a gutter preview to open the central **GittyDot** screen.

The default comparison is **Latest commit → Working file**, including both staged and unstaged changes. New files compare against an empty baseline and appear as additions.

Use the dropdown beside **Open in Editor** to choose **Side by side** or **Unified**. The choice is remembered for the project. Supported scripts and scenes open in their native Godot editors; other text/configuration files can be reviewed in GittyDot's diff view.

In **Side by side**, **Latest commit → Working file** and **Unstaged changes** let you edit the working file on the right. The left version stays read-only. Editable comparisons show complete documents without collapsed separators or padding lines; vertical scrolling follows corresponding source lines across insertions/deletions. Use **Save**, **Ctrl/Cmd+S**, or the default 350 ms auto-save. Undo remains available after saving, and saves leave staging untouched. Selecting a different file or starting a Git operation flushes pending comparison edits first.

Hunk/line patch buttons, collapsed context, whitespace/noise filtering and the structured **Scene/Settings** view are disabled in editable comparisons. Use **Unified** for read-only inspection and applicable patch actions, or the **Commit** checkboxes to stage files. Staged snapshots, commit/stash history, images, binary files and deleted files remain read-only. Editable text must be UTF-8, within the current project, up to 2 MiB and 20,000 lines; file symlinks stay read-only.

Comparison saves preserve UTF-8 BOMs, LF/CRLF style and a missing final newline. If the file changes externally, disappears, or has another unsaved draft in Godot's Script/Scene editor, saving pauses and keeps both versions. **Reload** explicitly discards the comparison draft; blocked/unsaved drafts are stored in the project-local temporary folder for recovery after plugin reload. Clean native script tabs are synchronized after saves. **Open in Editor** reloads a clean cached scene from the working file, while preserving unsaved native scenes.

### Stage and commit

In the **Commit** dock, select the files to stage, enter a commit message, and commit. Changelists, amend, and **Commit and Push** are also available.

To amend a specific commit, use the dropdown beside **Amend**, or right-click it in **Git Log > Amend This Commit…**. The dock loads its message and displays its short hash; edit the message and stage the changes you want to include. Reword, Fixup, Squash and Drop remain separate Log menu actions. Amending an older commit asks before replaying newer commits and changing their hashes. Amendments across merge commits are refused. The Git version is checked before any amendment changes the index or history; an unsupported version leaves the draft and target intact.

If replay encounters conflicts, resolve them and use **Continue**, or **Abort** to restore the original history with the amendment changes staged. Recovery information survives plugin reload. Failures expose **Show details in Console**; later commands do not change which diagnostic that button opens. No automatic force-push is performed.

Use **Unstaged changes** for index → working-file comparisons and **Staged changes** for latest-commit → index comparisons. Read-only inspection views expose applicable hunk/line staging, unstaging and revert actions. Editable working-file panes use Commit checkboxes for staging; the default latest-commit → working-file comparison does not apply patches directly, since they may not match a partially staged index.

Automatic staging, automatic adding of new files, and background fetch are **off by default**. Auto-save does not stage, commit, or push.

Right-click a file or folder and choose **Add to .gitignore** or **Add Folder to .gitignore**. The rule is anchored to the repository root, with filename wildcard characters escaped. Existing rules and files are preserved. Already tracked files remain tracked; ignoring them does not unstage or remove them from Git.

### Inspect history

Open **Git Log** in the bottom panel. A single click selects a changed file; **double-click or Enter** opens its diff in the central editor.

Commit diffs compare the selected commit with its first parent. Initial commits show additions, deleted historical files remain viewable, and stash comparisons use their recorded revisions. Historical diffs are read-only and retain the selected revision during background refreshes.

## Auto-save and preferences

Auto-save is **enabled by default** for project-backed scripts and editable working-file comparisons. It saves after **350 ms without another edit**, and flushes pending saves when the application loses focus or before staging. Native scripts save through Godot's ScriptEditor; comparison panes save their full text to the working file using a guarded atomic replacement. The Tools toggle controls both; Save/Ctrl+S remains available with auto-save disabled.

If a script changes externally or disappears, automatic saving pauses to preserve the disk version and editor draft. Resolve Godot's reload prompt or save manually. Unsaved changes in the native Scene editor, untitled scripts and embedded scripts continue to use the native save workflow; raw scene text edited in the comparison pane follows its working-file save flow.

Toggle auto-save, blame, and background fetch in **Project > Tools > GittyDot**. Preferences and changelists are local to each project under `.godot/gittydot/`.

## Git console and authentication

The console passes arguments directly to Git. Output is rendered as literal text, and its command log uses mutex-protected snapshots.

Confirmation is required before hard resets, destructive cleans, forced pushes, global/system configuration writes, and destructive or shell aliases. Cancelling preserves the typed command. Read-only queries and clean dry runs do not require destructive-command confirmation.

SSH uses per-invocation `ssh -o BatchMode=yes`. GittyDot does not change the editor's SSH environment or adopt repository `core.sshCommand` settings. Configure keys and hosts in your SSH configuration, or explicitly supply a trusted `GIT_SSH_COMMAND`; non-OpenSSH clients may also need `GIT_SSH_VARIANT`.

Noninteractive Git prompt/editor environment variables apply while the plugin is enabled and are restored on disable. Git hooks and helpers run with your permissions; GittyDot is not a sandbox for untrusted repositories.

## Local data

- Preferences and changelists: `.godot/gittydot/`.
- Diff, blame, and patch temporary files: `<project-name>-temp-chatgpt/gittydot/`.

The temporary-folder name comes from the development convention used for this fork. It is a local directory, not an integration or callback. Godot ignores it through `.gdignore`; Git ignores it when the installation's `.gitignore` pattern is present.
