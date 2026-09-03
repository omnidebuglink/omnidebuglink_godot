extends RefCounted
## ui_click / tap_screen / swipe / long_press / input_text / send_key / send_action.
##
## Mouse/touch events are pushed through Viewport.push_input(ev, true) — canvas
## coordinates, the same GUI pipeline real input takes (works under stretch
## modes). Key and action events go through Input.parse_input_event, so they
## reach _input/_unhandled_input and Input.is_action_pressed polling alike.
##
## Normalized coordinates (0-1) always use a TOP-LEFT origin, matching the
## screenshot orientation and every non-Unity OmniDebugLink client.

const SceneUtil := preload("./scene_util.gd")


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("ui_click",
		Callable(self, "ui_click"),
		"Clicks a UI Control through the real GUI event pipeline. Locate it by node path, or by the text it displays (resolves to the nearest clickable ancestor, e.g. the Button above a Label); use index when the text matches several nodes. Returns clicked = path of the control that actually received the click — use that path for follow-up actions.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "NodePath of the control (takes priority over text)"},
				"text": {"type": "string", "description": "displayed text to locate the element by"},
				"index": {"type": "integer", "minimum": 0, "description": "which match to use when text matches several nodes (default 0)"},
			},
		})
	reg.register("tap_screen",
		Callable(self, "tap_screen"),
		"Taps normalized screen coordinates: x/y in 0-1 with origin at the TOP-LEFT, matching the screenshot orientation. Set touch=true to additionally send touch events for touch-driven games.",
		{
			"type": "object",
			"properties": {
				"x": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"y": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"touch": {"type": "boolean", "description": "also send InputEventScreenTouch (default false)"},
			},
			"required": ["x", "y"],
		})
	reg.register("swipe",
		Callable(self, "swipe"),
		"Swipes between two normalized points (0-1, origin top-left) over duration_ms, sending per-frame motion events with deltas so drag targets and inertia-driven containers respond. Set touch=true to use screen touch/drag events instead of mouse.",
		{
			"type": "object",
			"properties": {
				"from_x": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"from_y": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"to_x": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"to_y": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"duration_ms": {"type": "integer", "minimum": 50, "default": 300},
				"touch": {"type": "boolean", "default": false},
			},
			"required": ["from_x", "from_y", "to_x", "to_y"],
		})
	reg.register("long_press",
		Callable(self, "long_press"),
		"Presses and holds (default 800ms) then releases, at normalized x/y (origin top-left) or at a node's clickable center. Use it to exercise long-press interactions.",
		{
			"type": "object",
			"properties": {
				"x": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"y": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"path": {"type": "string", "description": "alternative to x/y: node to press (its clickable ancestor's center)"},
				"hold_ms": {"type": "integer", "minimum": 100, "default": 800},
				"touch": {"type": "boolean", "default": false},
			},
		})
	reg.register("input_text",
		Callable(self, "input_text"),
		"Types text into a LineEdit or TextEdit (or any node with a text property) and fires its change signals: text_changed, plus text_submitted when submit=true.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "NodePath of the LineEdit/TextEdit"},
				"text": {"type": "string"},
				"submit": {"type": "boolean", "default": false, "description": "also emit text_submitted (LineEdit only)"},
			},
			"required": ["path", "text"],
		})
	reg.register("send_key",
		Callable(self, "send_key"),
		"Injects a key event through Input.parse_input_event — the full input pipeline, so Escape/Back reach _unhandled_input and Input actions bound to the key. key is a name like 'Escape' / 'Up' / 'Enter' or a Godot Key numeric code; mode is tap (press+release), press or release.",
		{
			"type": "object",
			"properties": {
				"key": {"description": "key name string or Godot Key code integer"},
				"mode": {"type": "string", "enum": ["tap", "press", "release"], "default": "tap"},
				"hold_ms": {"type": "integer", "minimum": 10, "default": 50},
				"text": {"type": "string", "description": "single character forwarded as unicode (e.g. for text fields)"},
			},
			"required": ["key"],
		})
	reg.register("send_action",
		Callable(self, "send_action"),
		"Injects an InputMap action by name (press+release by default, hold_ms controls the gap). Reaches both polled consumers (Input.is_action_pressed / get_vector) and event-driven handlers, so menu and gameplay code both respond. Prefer this over send_key when the game is driven by input actions.",
		{
			"type": "object",
			"properties": {
				"action": {"type": "string", "description": "InputMap action name"},
				"mode": {"type": "string", "enum": ["tap", "press", "release"], "default": "tap"},
				"hold_ms": {"type": "integer", "minimum": 10, "default": 50},
			},
			"required": ["action"],
		})


func ui_click(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var target: Node = null
	var located_by := "path"
	var path := String(payload.get("path", ""))
	if path != "":
		target = odl.node_from_path(path)
		if target == null:
			return odl.task_error("node not found: " + path)
	else:
		var text := String(payload.get("text", ""))
		if text == "":
			return odl.task_error("provide path or text to locate the clickable element")
		var matches: Array = SceneUtil.find_by_text(odl, text)
		if matches.is_empty():
			return odl.task_error('no displayed text matches "%s"; use scene_traverse or find_objects to see what is on screen' % text)
		var index := int(payload.get("index", 0))
		if index < 0 or index >= matches.size():
			return odl.task_error('text "%s" matched %d nodes; index %d is out of range' % [text, matches.size(), index])
		target = matches[index]
		located_by = "text"
	var receiver := SceneUtil.click_target_of(target)
	if receiver == null:
		return odl.task_error("no clickable Control found at or above: " + str(target.get_path()))
	# Capture everything derived from nodes BEFORE awaiting: a pressed handler
	# may change/free the scene mid-click, leaving the receiver out of the tree.
	var center: Vector2 = receiver.get_global_rect().get_center()
	var clicked_path := str(receiver.get_path())
	var center_norm: Variant = odl.normalize_pos(center)
	var target_text: String = odl.display_text(target)
	push_motion(odl, center, Vector2.ZERO)
	push_mouse_button(odl, center, true)
	await odl.wait(0.05)
	push_mouse_button(odl, center, false)
	return {
		"clicked": clicked_path,
		"located_by": located_by,
		"center_norm": center_norm,
		"text": target_text,
	}


func tap_screen(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var x := float(payload.get("x", -1.0))
	var y := float(payload.get("y", -1.0))
	if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		return odl.task_error("x/y are normalized 0-1 with origin at the TOP-LEFT corner")
	var px: Vector2 = Vector2(x, y) * odl.canvas_size()
	push_motion(odl, px, Vector2.ZERO)
	push_mouse_button(odl, px, true)
	await odl.wait(0.05)
	push_mouse_button(odl, px, false)
	if bool(payload.get("touch", false)):
		push_touch(odl, px, true)
		await odl.wait(0.05)
		push_touch(odl, px, false)
	return {"tapped_px": [px.x, px.y], "origin": "top-left"}


func swipe(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var from = norm_point(payload, "from_x", "from_y")
	var to = norm_point(payload, "to_x", "to_y")
	if from == null or to == null:
		return odl.task_error("from_x/from_y/to_x/to_y are required, normalized 0-1 with origin at the TOP-LEFT")
	var duration_ms := int(payload.get("duration_ms", 300))
	if duration_ms < 50:
		duration_ms = 50
	var touch := bool(payload.get("touch", false))
	var start_px: Vector2 = Vector2(float(from[0]), float(from[1])) * odl.canvas_size()
	var end_px: Vector2 = Vector2(float(to[0]), float(to[1])) * odl.canvas_size()
	var delta: Vector2 = end_px - start_px
	if touch:
		push_touch(odl, start_px, true)
	else:
		push_motion(odl, start_px, Vector2.ZERO)
		push_mouse_button(odl, start_px, true)
	var started := Time.get_ticks_msec()
	var last := start_px
	while true:
		var t := float(Time.get_ticks_msec() - started) / float(duration_ms)
		var pos: Vector2 = start_px + delta * clampf(t, 0.0, 1.0)
		var rel := pos - last
		last = pos
		if touch:
			push_drag(odl, pos, rel)
		else:
			push_motion(odl, pos, rel)
		if t >= 1.0:
			break
		await odl.get_tree().process_frame
	if touch:
		push_touch(odl, end_px, false)
	else:
		push_motion(odl, end_px, Vector2.ZERO)
		push_mouse_button(odl, end_px, false)
	return {"from_px": [start_px.x, start_px.y], "to_px": [end_px.x, end_px.y], "duration_ms": duration_ms, "origin": "top-left"}


func long_press(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var hold_ms := int(payload.get("hold_ms", 800))
	if hold_ms < 100:
		hold_ms = 100
	var pos: Variant = null
	if payload.has("x") and payload.has("y"):
		var x := float(payload.get("x"))
		var y := float(payload.get("y"))
		if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
			return odl.task_error("x/y are normalized 0-1 with origin at the TOP-LEFT corner")
		pos = Vector2(x, y) * odl.canvas_size()
	elif payload.has("path"):
		var node: Node = odl.node_from_path(String(payload.get("path")))
		if node == null:
			return odl.task_error("node not found: " + String(payload.get("path")))
		var receiver := SceneUtil.click_target_of(node)
		if receiver == null:
			return odl.task_error("no clickable Control found at or above: " + str(node.get_path()))
		pos = receiver.get_global_rect().get_center()
	else:
		return odl.task_error("provide x/y (normalized, top-left origin) or path")
	var p: Vector2 = pos
	var touch := bool(payload.get("touch", false))
	push_motion(odl, p, Vector2.ZERO)
	push_mouse_button(odl, p, true)
	if touch:
		push_touch(odl, p, true)
	await odl.wait(hold_ms / 1000.0)
	push_mouse_button(odl, p, false)
	if touch:
		push_touch(odl, p, false)
	return {"pressed_px": [p.x, p.y], "hold_ms": hold_ms}


func input_text(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var path := String(payload.get("path", ""))
	var node: Node = odl.node_from_path(path)
	if node == null:
		return odl.task_error("node not found: " + path)
	if not payload.has("text"):
		return odl.task_error("text is required")
	var text := String(payload.get("text"))
	var submit := bool(payload.get("submit", false))
	if node.is_class("LineEdit"):
		var le := node as LineEdit
		le.text = text
		le.text_changed.emit(text)
		if submit:
			le.text_submitted.emit(text)
	elif node.is_class("TextEdit"):
		var te := node as TextEdit
		te.text = text
		te.text_changed.emit()
	else:
		if SceneUtil.property_type(node, "text") == TYPE_NIL:
			return odl.task_error("node has no text property: " + str(node.get_path()))
		node.set("text", text)
	return {"path": str(node.get_path()), "text": text, "submitted": submit}


func send_key(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var key = payload.get("key", null)
	var code := 0
	if typeof(key) == TYPE_STRING:
		code = int(OS.find_keycode_from_string(String(key)))
		if code == 0:
			return odl.task_error('unknown key name "%s"; use names like Escape, Space, Up, Enter, Tab, or a Godot Key numeric code' % String(key))
	elif typeof(key) == TYPE_INT or typeof(key) == TYPE_FLOAT:
		code = int(key)
	else:
		return odl.task_error("key is required: a name string like 'Escape' or a Godot Key numeric code")
	var mode := String(payload.get("mode", "tap"))
	var hold_ms := int(payload.get("hold_ms", 50))
	var unicode := 0
	var text := String(payload.get("text", ""))
	if text.length() > 0:
		unicode = text.unicode_at(0)
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	press.echo = false
	press.unicode = unicode
	Input.parse_input_event(press)
	if mode != "press":
		await odl.wait(maxf(0.01, hold_ms / 1000.0))
		var release := InputEventKey.new()
		release.keycode = code
		release.physical_keycode = code
		release.pressed = false
		release.unicode = unicode
		Input.parse_input_event(release)
	return {"key": code, "mode": mode, "unicode": unicode}


func send_action(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var action := String(payload.get("action", ""))
	if action == "":
		return odl.task_error("action is required (an InputMap action name)")
	if not InputMap.has_action(action):
		return odl.task_error('unknown InputMap action "%s"; check Project Settings > Input Map for valid names' % action)
	var mode := String(payload.get("mode", "tap"))
	var hold_ms := int(payload.get("hold_ms", 50))
	# Event-driven listeners (_unhandled_input + is_action_pressed on the event):
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	# Polled consumers (Input.is_action_pressed / get_vector): parse_input_event
	# with InputEventAction does NOT update that state, action_press does.
	Input.action_press(action)
	if mode != "press":
		await odl.wait(maxf(0.01, hold_ms / 1000.0))
		var release := InputEventAction.new()
		release.action = action
		release.pressed = false
		Input.parse_input_event(release)
		Input.action_release(action)
	return {"action": action, "mode": mode}


## ---------- event helpers ----------

func norm_point(payload: Dictionary, x_key: String, y_key: String) -> Variant:
	if not payload.has(x_key) or not payload.has(y_key):
		return null
	var x := float(payload.get(x_key))
	var y := float(payload.get(y_key))
	if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		return null
	return [x, y]


func push_mouse_button(odl: Node, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	odl.get_viewport().push_input(ev, true)


func push_motion(odl: Node, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	odl.get_viewport().push_input(ev, true)


func push_touch(odl: Node, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	odl.get_viewport().push_input(ev, true)


func push_drag(odl: Node, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = pos
	ev.relative = relative
	odl.get_viewport().push_input(ev, true)
