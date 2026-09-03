extends RefCounted
## call_method / change_scene / reload_scene — powerful write escape hatches.


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("call_method",
		Callable(self, "call_method"),
		"Calls any method on any node with the given args array and returns the method's return value. Escape hatch when no dedicated task fits — e.g. game-scripted helpers, opening menus, granting items.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"method": {"type": "string"},
				"args": {"type": "array", "description": "positional arguments (default [])"},
			},
			"required": ["path", "method"],
		})
	reg.register("change_scene",
		Callable(self, "change_scene"),
		"Switches to a scene file (path like res://scenes/main.tscn). The file must be included in the export.",
		{
			"type": "object",
			"properties": {"path": {"type": "string", "description": "scene file path, e.g. res://levels/level2.tscn"}},
			"required": ["path"],
		})
	reg.register("reload_scene",
		Callable(self, "reload_scene"),
		"Reloads the current scene from disk.",
		{})


func call_method(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var path := String(payload.get("path", ""))
	var node: Node = odl.node_from_path(path)
	if node == null:
		return odl.task_error("node not found: " + path)
	var method := String(payload.get("method", ""))
	if method == "":
		return odl.task_error("method is required")
	if not node.has_method(method):
		return odl.task_error('node has no method "%s"' % method)
	var args = payload.get("args", [])
	if typeof(args) != TYPE_ARRAY:
		return odl.task_error("args must be an array")
	var returned: Variant = node.callv(method, args)
	var result := {"returned": odl.jsonable(returned)}
	if returned == null:
		result["note"] = "returned null — the method may return nothing, or it hit a script error"
	return result


func change_scene(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var path := String(payload.get("path", ""))
	if path == "":
		return odl.task_error("path is required (e.g. res://scenes/main.tscn)")
	var err := odl.get_tree().change_scene_to_file(path)
	if err != OK:
		return odl.task_error("change_scene_to_file failed: %s (check that the path exists and is included in the build)" % error_string(err))
	return {"scene": path}


func reload_scene(payload: Dictionary) -> Dictionary:
	var gate: Dictionary = odl.gate_writes()
	if not gate.is_empty():
		return gate
	var err := odl.get_tree().reload_current_scene()
	if err != OK:
		return odl.task_error("reload_current_scene failed: %s" % error_string(err))
	var current = odl.get_tree().current_scene
	var scene := str(current.scene_file_path) if current != null and is_instance_valid(current) else ""
	return {"reloaded": true, "scene": scene}
