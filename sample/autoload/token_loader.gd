extends Node
## Sample glue: registers the demo input actions in code (keeps project.godot
## free of verbose InputEventKey serialization) and starts OmniDebugLink from
## the ODL_TOKEN environment variable, falling back to user://odl_token.txt
## (the practical option for double-clicked exports, which have no env vars).

const ACTIONS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W],
	"move_down": [KEY_DOWN, KEY_S],
}

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
		token = _read_token_file()
	if token == "":
		push_warning("[sample] no ODL_TOKEN env var and no user://odl_token.txt — OmniDebugLink stays offline")
		return
	OmniDebugLink.start(token)


func _read_token_file() -> String:
	if not FileAccess.file_exists("user://odl_token.txt"):
		return ""
	var f := FileAccess.open("user://odl_token.txt", FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text().strip_edges()
	f.close()
	return text if text.begins_with("odl-dev-") else ""
