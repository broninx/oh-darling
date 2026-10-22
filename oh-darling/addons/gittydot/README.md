<p align="center">
  <img src="icon.png" width="112" height="112" alt="GittyDot: a blue G with a coral Git branch and three nodes">
</p>

<h1 align="center">GittyDot</h1>

<p align="center"><strong>Review changes, edit diffs, and commit without leaving Godot.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-589eff" alt="Version 0.1.0">
  <img src="https://img.shields.io/badge/Godot-tested%20on%204.7.2-478cbf" alt="Tested on Godot 4.7.2">
  <img src="https://img.shields.io/badge/platform-verified%20on%20Windows-626b78" alt="Verified on Windows">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-f47c76" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="GUIDE.md">Guide</a> ·
  <a href="#limitations">Limitations</a> ·
  <a href="#testing">Testing</a> ·
  <a href="#feedback">Feedback</a>
</p>

GittyDot brings an IntelliJ-inspired Git workflow to the Godot editor: a focused **Commit** dock, a central **diff editor**, changes marked in your scripts, and a **Git Log** for reviewing history.

It is a fork of [Godit](https://github.com/rychtar/godit) 1.1.1, retaining its Git CLI backend and extending its editor integration. GittyDot runs your installed `git` from GDScript; it does not need the Godot Git GDExtension or a separate Version Control plugin.

> [!IMPORTANT]
> **0.1.0 is an early release.** The verified configuration is **Godot 4.7.2 on Windows**. Other engine versions, operating systems, and every inherited Git operation have not been validated. The known UI issues below are planned for **0.2.0**.

<a id="features"></a>

## ✨ Features

- **Commit dock:** stage and unstage files with checkboxes, organize work into changelists, write commit messages, amend, and commit or commit-and-push.
- **FileSystem status:** see modified, added, renamed, deleted, and conflicted files alongside your normal Godot files.
- **File and folder actions:** right-click to stage, unstage, add new files, move changes to a changelist, or add literal paths to `.gitignore`. Ignoring a tracked file does not remove it from Git.
- **Central diff editor:** choose **Side by side** or **Unified**, resize the split, and scroll both panes together. Scrollbars appear when content overflows.
- **Editable working-file comparisons:** edit the right pane in **Latest commit → Working file** or **Unstaged changes**. Save manually or use auto-save; staged snapshots and historical versions remain read-only.
- **Inline script changes:** grouped gutter markers and character highlights show edits in Godot's Script editor. Click a marker to inspect the previous code, navigate changes, roll back a hunk, or open its diff.
- **Automatic saving:** project-backed scripts and editable working-file comparisons save after a **350 ms editing pause**, preserving Undo and leaving staging untouched.
- **Commit history:** inspect the commit graph, search history, review file history, and double-click a changed file to open its diff in the main screen. Initial commits compare against an empty baseline.
- **Selected-commit amend:** select the latest or an earlier branch commit. Older-commit amendments require **Git 2.45.0+**, confirm the history rewrite, and support conflict Continue/Abort recovery.
- **Git console and diagnostics:** run Git commands, review their literal output, and use **Show details in Console** to jump to a failure. Destructive console operations ask for confirmation.
- **Additional Git tools:** inherited branch, tag, remote, stash, merge, rebase, cherry-pick, conflict-resolution, blame, image-diff, scene/config inspection, and optional Git LFS helpers remain available.

Read the [usage guide](GUIDE.md) for comparison modes, partial staging, draft recovery, and advanced workflows.

<a id="installation"></a>

## 🛠 Installation

1. Download a GittyDot release ZIP, or clone [this repository](https://github.com/Shinydarkraii/gittydot).
2. Place the complete `addons/gittydot/` folder in your project's `addons/` folder. Keep its `LICENSE` and `README.md` with it.
3. Disable **Godit** if it is installed, then enable **GittyDot** in **Project Settings → Plugins**.
4. Restart the editor after replacing an existing installation.

```text
your-project/
├── project.godot
└── addons/
    └── gittydot/
        ├── plugin.cfg
        ├── plugin.gd
        ├── icon.png
        ├── LICENSE
        ├── README.md
        ├── dock/
        └── util/
```

Keep the folder named **`gittydot`**, directly under `addons/`. Enable only one of Godit and GittyDot.

### Requirements

- **Godot 4.7.2 on Windows** is the tested setup.
- **Git** must be installed and available on the editor's `PATH`.
- The project must be inside a Git repository; GittyDot can initialize one through its dock.
- Configure Git authentication before using remote operations.
- **Git 2.45.0+** is required specifically for amending an older commit.
- **Git LFS** is optional, needed when using the LFS helpers.
- **GitHub CLI (`gh`)** is optional, used only to create/publish a GitHub repository from the initialization dialog. Missing installations are skipped quietly.

<a id="quick-start"></a>

## 🚀 Quick start

1. Open **Commit** and select a changed file to review it in the central **GittyDot** screen.
2. Choose **Side by side** to edit a supported working file on the right, or **Unified** to inspect the diff.
3. Tick the files you want to stage. Untick them to unstage; use a folder's context menu for actions on its displayed descendants.
4. Enter a commit message, then choose **Commit** or **Commit and Push**.
5. Open **Git Log** in the bottom panel to inspect history. Double-click or press Enter on a changed file to open its historical diff.

**Auto-save is on by default.** Automatic staging, adding new files, and background fetching are off. Saving never commits or pushes your work.

Use **Project → Tools → GittyDot** to toggle auto-save, blame, and background fetch. With auto-save off, editable comparisons still support **Save** and **Ctrl/Cmd+S**.

<details>
<summary><strong>Which comparison should I use?</strong></summary>

- **Latest commit → Working file:** includes both staged and unstaged changes. The working file is editable in Side by side.
- **Unstaged changes:** compares the index with the working file. The working file is editable in Side by side.
- **Staged changes:** compares the latest commit with the index; read-only.
- **Commit or stash history:** compares saved revisions; read-only. A commit is compared with its first parent, or an empty tree for the initial commit.

Editable panes show complete documents. Collapsed context, patch buttons, whitespace/noise filtering, and structured Scene/Settings inspection are disabled in this mode. Use the Commit checkboxes to stage files, or an applicable read-only view for patch actions.

</details>

<a id="limitations"></a>

## ⚠️ Known limitations

The [0.2.0 roadmap](ROADMAP.md) tracks these reported issues in **0.1.0**:

- A narrow Commit dock can clip filename prefixes and hide staging checkboxes.
- Editable comparisons do not yet have the change signs, change gutter, or minimap needed to find edits easily.
- Editable-diff colors still need to match the committed-diff renderer.
- **Open in Editor** can be unavailable in reported script cases; further reproduction and fixes are planned.

Editable comparisons currently support existing project-local UTF-8 files up to **2 MiB / 20,000 lines**. File symlinks, binaries, images, deleted files, staged snapshots, and historical revisions are read-only.

Multiple comparison tabs, broader keyboard shortcuts, and further image/scene workflow polish remain future work. FileSystem decorations depend on Godot's internal editor controls and need checking after engine upgrades.

<a id="authentication"></a>

## 🔑 Authentication and local data

Set up your system Git credentials first using a credential helper or SSH keys. GittyDot does not provide a password or token entry screen. Its child Git processes use noninteractive prompt/editor settings, restored when the plugin is disabled.

SSH is scoped to GittyDot's Git processes with `ssh -o BatchMode=yes`; the plugin does not change the editor's SSH environment or adopt a repository's `core.sshCommand`. A trusted user-supplied `GIT_SSH_COMMAND` takes precedence. See the [guide](GUIDE.md) for details.

Preferences and changelists live in **`.godot/gittydot/`**. Diff, blame, patch, and recovery files live in **`<project-name>-temp-chatgpt/gittydot/`**. These are local project files; the temporary-folder name is a development convention, not a callback or external service.

Git hooks and helpers run with your permissions. GittyDot does not sandbox repository code.

<a id="documentation"></a>

## 📖 Documentation

- [Usage guide](GUIDE.md) — comparisons, staging, amend, auto-save, recovery, preferences, and authentication.
- [0.2.0 roadmap](ROADMAP.md) — the next release's UI fixes and acceptance checks.
- [Maintainer notes](MAINTAINING.md) — architecture, ownership, and behavior contracts.
- [Upstream README](UPSTREAM_README.md) and [source baseline](upstream.json) — Godit provenance; upstream installation instructions describe Godit.

<a id="testing"></a>

## 🧪 Testing

The latest graphical verification on **2026-10-15** passed **233 editor integration checks**, with **0 failures**, **0 script errors**, and none of the reported Unicode, missing-process, or raw-icon startup diagnostics. It ran on **Godot 4.7.2 / Windows / Git 2.53.0**.

The checks exercise real editor saves and Undo, partial staging, editable comparisons, recovery, historical diffs, selected-commit amendments, console diagnostics, file/folder actions, gutter geometry, and split-pane scrolling. Separate first-install and restart checks verified initialization with GitHub CLI absent.

From the **standalone source repository**, with Python 3, Git, and Godot installed:

```powershell
python tools/test_gittydot.py --godot 'C:\Tools\Godot\Godot.exe'
python tools/test_gittydot.py --godot 'C:\Tools\Godot\Godot.exe' --visual
```

Replace the Godot path with your installation. Test fixtures stay inside the repository's temporary folder and do not stage or commit the source repository. These checks do not establish cross-platform support, all remote authentication setups, every inherited operation, or resolution of the UI issues listed above.

<a id="feedback"></a>

## 💬 Feedback and contributions

[Report a bug or suggest a feature](https://github.com/Shinydarkraii/gittydot/issues). For bugs, include your Godot and Git versions, operating system, reproduction steps, and relevant screenshots or errors. Remove credentials from logs before sharing them.

Contributions should preserve editor drafts, Undo, partial staging, and the Git backend's existing behavior. Read the [maintainer notes](MAINTAINING.md) and test changes in an isolated project.

<a id="credits"></a>

## © Credits and license

The GittyDot fork is maintained by [Shinydarkraii](https://github.com/Shinydarkraii). Its Git backend and many widgets originate in **Godit**, created by **Michal Rychtar**. The original copyright and attribution are retained under the [MIT License](LICENSE).

Development has used AI assistance for code, documentation, and verification work. The GittyDot icon was generated from the maintainer's sketch using an image generation tool.
