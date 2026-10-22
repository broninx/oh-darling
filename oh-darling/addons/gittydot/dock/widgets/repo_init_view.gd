## Shown by both docks when the project isn't a git repo yet: explains why and offers to create one.
@tool
extends CenterContainer

const RepoSetup := preload("res://addons/gittydot/util/repo_setup.gd")
const Dialogs := preload("res://addons/gittydot/dock/widgets/dialogs.gd")
const UiScale := preload("res://addons/gittydot/util/ui_scale.gd")

var _label: Label
var _button: Button


func _init(message: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = UiScale.px(220)
	add_child(box)
	_label = Label.new()
	_label.text = message
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	if not RepoSetup.git_available():
		_label.text = "GittyDot needs git, and the `git` command isn't on PATH. Install it from git-scm.com, then restart the editor."
		return
	_button = Button.new()
	_button.text = "Initialize Repository…"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_init_pressed)
	box.add_child(_button)


func _on_init_pressed() -> void:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var fields: Array = [
		{ "type": "label", "label": "Creates a git repository in %s, with Godot's .gitignore (.godot/, /android/) and .gitattributes (LF line endings)." % root },
		{ "key": "commit", "label": "Commit the project as it is now (\"Initial commit\")", "type": "check", "default": true },
	]
	if not RepoSetup.has_identity(root):
		fields.append({ "type": "label", "label": "Who you are, for your commits (saved for this repository only):" })
		fields.append({ "key": "name", "label": "Name", "placeholder": "Jane Doe" })
		fields.append({ "key": "email", "label": "Email", "placeholder": "jane@example.com" })
	if RepoSetup.lfs_available():
		fields.append({ "key": "lfs", "label": "Store images, audio, models and fonts with Git LFS", "type": "check", "default": false,
				"tooltip": "Keeps big binary files out of the regular history. Everyone who clones the repo needs Git LFS installed too." })
	_button.disabled = true # the lookup below takes a moment
	var gh: String = await RepoSetup.find_gh()
	_button.disabled = false
	if not gh.is_empty():
		fields.append({ "key": "publish", "label": "Publish to GitHub", "type": "check", "default": false, "tooltip": "Needs the first commit." })
		fields.append({ "key": "repo_name", "label": "GitHub repository name", "default": RepoSetup.suggested_repo_name() })
		fields.append({ "key": "private", "label": "Private repository", "type": "check", "default": true })
	var answer: Variant = await Dialogs.form(self, "Initialize Repository", fields, "Create")
	if answer == null:
		return

	_button.disabled = true
	_label.text = "Creating the repository…"
	var result: Dictionary = await RepoSetup.init_repo(root, {
		"commit": answer["commit"], "lfs": answer.get("lfs", false),
		"name": String(answer.get("name", "")).strip_edges(), "email": String(answer.get("email", "")).strip_edges(),
	})
	if not result["ok"]:
		await Dialogs.error(self, "Couldn't create the repository", result["error"])
	elif answer.get("publish", false) and answer["commit"]:
		_label.text = "Publishing to GitHub…"
		var published: Dictionary = await RepoSetup.publish_to_github(gh, root, String(answer["repo_name"]).strip_edges(), answer["private"])
		if not published["ok"]:
			await Dialogs.error(self, "Couldn't publish to GitHub", "The local repository is ready; publishing failed:\n" + published["error"])
	RepoSetup.reload_plugin()
