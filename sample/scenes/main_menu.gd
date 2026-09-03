extends Control


func _ready() -> void:
	OmniDebugLink.state_changed.connect(_update_status)
	_update_status()
	$StartButton.pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	var entered: String = $NameInput.text.strip_edges()
	OdlSample.player_name = entered if entered != "" else "Player"
	OmniDebugLink.log("starting game as %s" % OdlSample.player_name)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _update_status(_connected: bool = false) -> void:
	$StatusLabel.text = "OmniDebugLink: " + ("connected" if OmniDebugLink.connected() else "offline")
