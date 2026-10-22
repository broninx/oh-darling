## Per-project editor preferences, kept in Godot's ignored local data folder.
## No class_name:
## internal helper, addressed via preload (see git_status_flags.gd for why).
extends RefCounted

const CONFIG_PATH := "res://.godot/gittydot/settings.cfg"
const SECTION := "gittydot"


static func get_value(key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH) # missing file is fine: falls through to `default` below
	# ConfigFile.get_value() logs an error for a missing key when default is null.
	return cfg.get_value(SECTION, key) if cfg.has_section_key(SECTION, key) else default


static func set_value(key: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONFIG_PATH.get_base_dir()))
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(CONFIG_PATH)
