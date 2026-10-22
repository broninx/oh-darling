## Builds/caches nested folder TreeItems from repo-relative paths, so a flat
## file list can be shown as a directory tree. Shared by changes_panel.gd
## and history_panel.gd. No class_name: internal helper, addressed via
## preload (see git_status_flags.gd for why).
extends RefCounted


## text_column: which column holds the folder name (changes_panel keeps
## column 0 checkbox-only, so it passes 1).
## checkbox_column >= 0 makes the folder itself checkable and cascadable;
## -1 (default) means no checkbox. The caller still fills in the checked
## state and file count once all children exist.
static func get_or_create_folder(tree: Tree, group_root: TreeItem, cache: Dictionary, dir_path: String, text_column: int = 0, checkbox_column: int = -1) -> TreeItem:
	if dir_path.is_empty() or dir_path == ".":
		return group_root
	if cache.has(dir_path):
		return cache[dir_path]

	var parent_item := get_or_create_folder(tree, group_root, cache, dir_path.get_base_dir(), text_column, checkbox_column)
	var folder_item := tree.create_item(parent_item)
	var folder_name := dir_path.get_file()
	folder_item.set_text(text_column, folder_name)
	folder_item.set_icon(text_column, tree.get_theme_icon(&"Folder", &"EditorIcons"))
	for col in tree.columns:
		folder_item.set_selectable(col, false)
	folder_item.set_metadata(0, { "kind": "folder", "name": folder_name, "dir": dir_path })
	if checkbox_column >= 0:
		folder_item.set_cell_mode(checkbox_column, TreeItem.CELL_MODE_CHECK)
		folder_item.set_editable(checkbox_column, true)
	cache[dir_path] = folder_item
	return folder_item


## Tree keeps its scrollbars as internal children with no getter; restoring the scroll position after a rebuild needs the vertical one.
static func v_scroll_bar(tree: Tree) -> VScrollBar:
	for child in tree.get_children(true):
		if child is VScrollBar:
			return child
	return null
