# Godit

A git client inside the Godot editor. Stage, commit, switch branches and browse history without leaving the editor.

![Godit](https://github.com/rychtar/godit/blob/main/media/thumbnail.webp?raw=true)

## Features

- **Changes panel**: stage files, folders or single lines with a checkbox, then commit or push.
- **Changelists**: group changes and commit or shelve them separately.
- **Diff view**: side-by-side or unified, with syntax colors and image previews.
- **Branches**: switch, merge and rebase. Fetch, pull and push run in the background.
- **Git Log**: commit graph with search, cherry-pick and history editing.
- **Conflict resolver**: pick Ours, Theirs or both, side by side.
- **Script editor**: changed lines in the gutter with one-click rollback, plus optional blame.
- **GitHub, GitLab, Bitbucket**: open a commit, file line or branch in the browser, or start a pull request.
- **FileSystem dock**: changed, new and conflicted files are colored; right-click for history, revert, add or ignore.

## Install

1. Install Godit from the Asset Library, or copy `addons/godit/` into your project's `addons/` folder.
2. Enable **Godit** in Project Settings > Plugins.

You need Godot 4.4+, `git` on your `PATH`, and a project inside a git repository.

For push and pull, git has to log in without asking: use a credential helper for HTTPS or `ssh-agent` for SSH. If `git push` works in a terminal without a prompt, it works in Godit.

## Usage

- **Where**: Godit opens as one SourceTree-style dock in the bottom panel: File Status, History and Console on the left with your branches under them. On Godot 4.6+ drag it to a side dock or make it floating, e.g. on a second monitor, and it stays there.
- **Commit**: tick files in **File Status**, type a message and press `Ctrl/Cmd+Enter`. Add `Shift` to also push.
- **Stage part of a file**: open its diff and stage a hunk or selected lines.
- **Changelists**: double-click one to make it active and drag files between them.
- **Branches**: double-click one to switch; right-click it to merge, rebase or push, or right-click a section header to add a branch, tag or remote.
- **History**: the commit graph, with search, cherry-pick and history editing.
- **Everything else**: right-click a file, branch or commit.

## Settings

Project > Tools > Godit: auto-reload changed files, auto-save scripts, background fetch, blame column, whether to confirm keyboard commits, a faster `git status` for large projects (git's file system monitor), and the layout: one combined dock (default), a Git dock plus Git Log, or both in the bottom panel.

The ⋮ menu in the Changes panel controls auto-staging, auto-adding new files and the masks for files to skip (for example `*.psd` source art). `.import` and `.uid` files are added with the file they belong to, since Godot needs them in the repo.

## License

MIT, see [LICENSE](LICENSE).
