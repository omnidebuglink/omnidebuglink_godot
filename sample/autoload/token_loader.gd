extends Node
## Sample glue: registers the demo input actions in code (keeps project.godot
## free of verbose InputEventKey serialization) and starts OmniDebugLink from
## (in order): the ODL_TOKEN environment variable, a ?token= URL parameter
## (web builds; persisted to user:// so later runs connect without it), or
## user://odl_token.txt (the practical option for double-clicked desktop
## exports, which have no environment variables).


const ACTIONS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W],
	"move_down": [KEY_DOWN, KEY_S],
}

const TOKEN_FILE := "user://odl_token.txt"

var player_name := "Player"


func _enter_tree() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in ACTIONS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)


func _ready() -> void:
	var token := OS.get_environment("ODL_TOKEN")
	if token == "":
		token = _token_from_url()
	if token == "":
		token = _read_token_file()
	if token == "":
		push_warning("[sample] no ODL_TOKEN env var, no ?token= URL parameter and no " + TOKEN_FILE + " — OmniDebugLink stays offline")
		return
	OmniDebugLink.start(token)


## Web export: read ?token=odl-dev-… from the page URL and persist it, so the
## user only appends the parameter once.
func _token_from_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var js = Engine.get_singleton("JavaScriptBridge")
	if js == null:
		return ""
	var value: Variant = js.eval(
		"(() => { const t = new URLSearchParams(location.search).get('token'); return t ? t : ''; })()",
		true)
	if typeof(value) != TYPE_STRING or not value.begins_with("odl-dev-"):
		return ""
	_write_token_file(value)
	return value


func _read_token_file() -> String:
	if not FileAccess.file_exists(TOKEN_FILE):
		return ""
	var f := FileAccess.open(TOKEN_FILE, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text().strip_edges()
	f.close()
	return text if text.begins_with("odl-dev-") else ""


func _write_token_file(token: String) -> void:
	var f := FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(token)
		f.close()
