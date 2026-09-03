extends RefCounted
## set_prop / set_time_scale — generic property writes and time control.

const SceneUtil := preload("./scene_util.gd")


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("set_prop",
		Callable(self, "set_prop"),
		"Sets any node property (visible, disabled, text, position, ...) with automatic type coercion: JSON arrays become Vector2/Vector3/Color/Rect2 as needed. Returns value_now, the read-back value, so you can confirm the write took effect.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"prop": {"type": "string", "description": "property name, e.g. visible, disabled, text, position, value"},
				"value": {"description": "new value (JSON); arrays are coerced to engine value types"},
			},
			"required": ["path", "prop", "value"],
		})
	reg.register("set_time_scale",
		Callable(self, "set_time_scale"),
		"Sets Engine.time_scale and/or SceneTree.paused (pass either or both). Slow motion and freezing the game make inspection easier.",
		{
			"type": "object",
			"properties": {
				"scale": {"type": "number", "minimum": 0.0, "description": "new Engine.time_scale (1.0 = normal)"},
				"paused": {"type": "boolean", "description": "new SceneTree.paused"},
			},
		})


func set_prop(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var path := String(payload.get("path", ""))
	var node: Node = odl.node_from_path(path)
	if node == null:
		return odl.task_error("node not found: " + path)
	var prop := String(payload.get("prop", ""))
	if prop == "":
		return odl.task_error("prop is required")
	if not payload.has("value"):
		return odl.task_error("value is required")
	var target_type := SceneUtil.property_type(node, prop)
	if target_type == TYPE_NIL:
		return odl.task_error('node has no property "%s"' % prop)
	var value = payload.get("value")
	node.set(prop, SceneUtil.coerce_value(value, target_type))
	return {"path": str(node.get_path()), "prop": prop, "value_now": odl.jsonable(node.get(prop))}


func set_time_scale(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	if payload.has("scale"):
		var scale := float(payload.get("scale"))
		if scale < 0.0:
			scale = 0.0
		Engine.time_scale = scale
	if payload.has("paused"):
		odl.get_tree().paused = bool(payload.get("paused"))
	return {"time_scale": Engine.time_scale, "paused": odl.get_tree().paused}
