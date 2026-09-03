extends RefCounted
## list_dir / read_file — read-only access to user:// (save files etc.).
## res:// is deliberately not exposed.


const MAX_READ_BYTES := 200000


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("list_dir",
		Callable(self, "list_dir"),
		"Lists directories and files under user:// (pass a relative path like \"saves\"; '..' is rejected). Use it to discover save files.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "relative path under user:// (default the root)"},
			},
		})
	reg.register("read_file",
		Callable(self, "read_file"),
		"Reads a text file under user:// (relative path, max 200KB) and returns its content.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "relative path under user://"},
			},
			"required": ["path"],
		})


func list_dir(payload: Dictionary) -> Dictionary:
	var rel := String(payload.get("path", "")).strip_edges()
	var invalid := validate_user_path(rel)
	if invalid != "":
		return odl.task_error(invalid)
	var dir := DirAccess.open("user://" + rel)
	if dir == null:
		return odl.task_error("cannot open user://" + rel + ": " + error_string(DirAccess.get_open_error()))
	var files: Array = []
	var dirs: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			dirs.append(entry)
		else:
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	dirs.sort()
	return {"path": "user://" + rel, "dirs": dirs, "files": files}


func read_file(payload: Dictionary) -> Dictionary:
	var rel := String(payload.get("path", "")).strip_edges()
	var invalid := validate_user_path(rel)
	if invalid != "":
		return odl.task_error(invalid)
	var full := "user://" + rel
	if not FileAccess.file_exists(full):
		return odl.task_error("file not found: " + full)
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		return odl.task_error("cannot open " + full + ": " + error_string(FileAccess.get_open_error()))
	var size := f.get_length()
	if size > MAX_READ_BYTES:
		f.close()
		return odl.task_error("file is %d bytes; read_file is capped at %d" % [size, MAX_READ_BYTES])
	var content := f.get_as_text()
	f.close()
	return {"path": full, "size": size, "content": content}


func validate_user_path(rel: String) -> String:
	if rel.begins_with("/") or rel.begins_with("res://") or rel.begins_with("user://") or rel.contains(".."):
		return "path must be relative to user:// and must not contain '..'"
	return ""
