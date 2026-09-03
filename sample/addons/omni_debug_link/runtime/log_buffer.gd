extends RefCounted
## Ring buffer for read_logs.
##
## Godot has no engine-level log callback, so logs are collected from two
## sources:
##  1. SDK entries: OmniDebugLink.log()/log_warning()/log_error() plus SDK
##     internal events (connection state, 4000, handler failures). When the
##     engine's file logging is NOT active these are added to the buffer
##     directly (and mirrored to the console via push_*).
##  2. File tail: when the project writes user://logs/godot.log (enable
##     "debug/file_logging" in Project Settings), every print/push_error from
##     the game and the engine lands there and this buffer tails it. In that
##     mode SDK entries are only push_*'d (the tail picks them up), which keeps
##     read_logs free of duplicates.


const CAPACITY := 1000
const TAIL_INTERVAL_SEC := 0.5

var _entries: Array = []
var _dropped_count := 0
var _log_path := "user://logs/godot.log"
var _file_pos := 0
var _tailing := false
var _accum_sec := 0.0


func _init() -> void:
	var configured = ProjectSettings.get_setting("debug/file_logging/log_path", _log_path)
	if configured != null and String(configured) != "":
		_log_path = String(configured)


func add_sdk(level: String, message: String) -> void:
	_add_via_engine(level, message, "[odl] ")


## For OmniDebugLink.log()/log_warning()/log_error() — user-facing, no prefix.
func add_user(level: String, message: String) -> void:
	_add_via_engine(level, message, "")


func _add_via_engine(level: String, message: String, prefix: String) -> void:
	var full := prefix + message
	if not _tailing:
		_push(level, full)
	else:
		# Tailing is active: push_* writes into the tailed file, so the entry
		# arrives through the tail. Avoid buffering it twice.
		_console(level, full)


func _console(level: String, text: String) -> void:
	match level:
		"error":
			push_error(text)
		"warning":
			push_warning(text)
		_:
			print(text)


func _push(level: String, text: String) -> void:
	_console(level, text)
	_append(level, text)


func _append(level: String, message: String) -> void:
	_entries.append({"ts_ms": _unix_msec(), "level": level, "message": message})
	# Trim in batches: slicing on every overflow entry is O(n) per append.
	if _entries.size() > CAPACITY + 32:
		_dropped_count += _entries.size() - CAPACITY
		_entries = _entries.slice(_entries.size() - CAPACITY)


func is_tailing() -> bool:
	return _tailing


func entries() -> Array:
	return _entries


## Called every frame from the autoload's _process.
func poll(delta_sec: float) -> void:
	_accum_sec += delta_sec
	if _accum_sec < TAIL_INTERVAL_SEC:
		return
	_accum_sec = 0.0
	_tail_file()


func _tail_file() -> void:
	if not FileAccess.file_exists(_log_path):
		return
	var f := FileAccess.open(_log_path, FileAccess.READ)
	if f == null:
		return
	var length := f.get_length()
	if length == _file_pos:
		f.close()
		return
	var first_activation := not _tailing
	_tailing = true
	if length < _file_pos:
		# Rotated or truncated (another instance sharing user://): start over.
		_file_pos = 0
	elif _file_pos == 0 and length > 262144:
		# First tail on a large existing log: only ingest the last 256KB.
		_file_pos = length - 262144
	if first_activation and _file_pos == 0:
		# The pass below re-reads the whole file, including lines that were
		# already buffered directly before tailing kicked in — drop those to
		# avoid duplicates.
		_entries.clear()
	f.seek(_file_pos)
	var chunk := f.get_buffer(length - _file_pos).get_string_from_utf8()
	_file_pos = length
	f.close()
	for line in chunk.split("\n"):
		_parse_line(String(line))


func _parse_line(line: String) -> void:
	if line.is_empty():
		return
	# Continuation lines (stack frames etc.) fold into the previous entry.
	if line.begins_with(" ") or line.begins_with("\t"):
		if not _entries.is_empty():
			var last: Dictionary = _entries[_entries.size() - 1]
			last["message"] = String(last["message"]) + "\n" + line
			return
	if line.begins_with("ERROR:"):
		_append("error", line.substr(6).strip_edges())
	elif line.begins_with("WARNING:"):
		_append("warning", line.substr(9).strip_edges())
	else:
		_append("info", line.strip_edges())


static func _unix_msec() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
