extends Control

const SPEED := 260.0
# While Collect Item is held down, +1 every 0.25s (hold-to-repeat). A quick
# click still counts exactly once.
const HOLD_REPEAT_SEC := 0.25

var items := 0
var _holding := false
var _hold_accum := 0.0
var _hold_repeats := 0
var _dragging := false


func _ready() -> void:
	OmniDebugLink.log("game scene ready, player=%s" % OdlSample.player_name)
	$CollectButton.button_down.connect(_on_collect_down)
	$CollectButton.button_up.connect(_on_collect_up)
	$Player.gui_input.connect(_on_player_gui_input)
	$BackButton.pressed.connect(_on_back_pressed)


func _process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		$Player.position += dir * SPEED * delta
		$Player.position = $Player.position.clamp(Vector2.ZERO, size - $Player.size)
	if _holding:
		_hold_accum += delta
		while _hold_accum >= HOLD_REPEAT_SEC:
			_hold_accum -= HOLD_REPEAT_SEC
			_hold_repeats += 1
			_on_collect()


func _on_collect() -> void:
	items += 1
	$CountLabel.text = "Items: %d" % items
	OmniDebugLink.log("collected item %d" % items)


func _on_collect_down() -> void:
	_holding = true
	_hold_accum = 0.0
	_hold_repeats = 0


func _on_collect_up() -> void:
	if _holding and _hold_repeats == 0:
		_on_collect()  # plain click
	_holding = false


func _on_player_gui_input(event: InputEvent) -> void:
	# Drag the square with the left button (relative deltas, like any editor
	# canvas) — this is what makes swipe testable end to end.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		$Player.position += event.relative
		$Player.position = $Player.position.clamp(Vector2.ZERO, size - $Player.size)


func _on_back_pressed() -> void:
	OmniDebugLink.log("back to menu")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
