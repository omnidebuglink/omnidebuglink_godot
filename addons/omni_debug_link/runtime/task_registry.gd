extends RefCounted
## Task registry: type -> handler/description/schema, plus async dispatch.
##
## Handlers are Callables taking a payload Dictionary and returning any Variant
## (usually a Dictionary). A handler signals failure by returning the marker
## built by OmniDebugLink.task_error(); anything else is treated as success.
## Returning null is treated as a script error so broken handlers fail loudly
## instead of silently reporting success.


var _tasks := {}
var on_changed: Callable


func register(task_type: String, handler: Callable, description := "", payload_schema: Dictionary = {}) -> void:
	_tasks[task_type] = {"handler": handler, "description": description, "payload_schema": payload_schema}
	if on_changed.is_valid():
		on_changed.call()


func unregister(task_type: String) -> void:
	if _tasks.erase(task_type) and on_changed.is_valid():
		on_changed.call()


func has(task_type: String) -> bool:
	return _tasks.has(task_type)


func count() -> int:
	return _tasks.size()


func snapshot() -> Array:
	var out := []
	for task_type in _tasks:
		var entry: Dictionary = _tasks[task_type]
		var spec := {"type": task_type}
		if String(entry["description"]) != "":
			spec["description"] = entry["description"]
		if not (entry["payload_schema"] as Dictionary).is_empty():
			spec["payloadSchema"] = entry["payload_schema"]
		out.append(spec)
	return out


## Async: awaits the handler (which may itself await frames/timers) and returns
## {"ok": true, "result": ...} or {"ok": false, "error": {code, message}}.
func run(task_type: String, payload: Dictionary) -> Dictionary:
	var entry: Dictionary = _tasks.get(task_type, {})
	if entry.is_empty():
		return {"ok": false, "error": {"code": "TASK_UNKNOWN", "message": 'no handler for "%s"' % task_type}}
	var handler: Callable = entry["handler"]
	var result: Variant = await handler.call(payload)
	if result == null:
		return {"ok": false, "error": {"code": "TASK_FAILED", "message": "handler returned null (script error or missing return value)"}}
	if typeof(result) == TYPE_DICTIONARY and result.has("__odl_error"):
		var err: Dictionary = result
		return {"ok": false, "error": {"code": String(err.get("code", "TASK_FAILED")), "message": String(err.get("message", "task failed"))}}
	return {"ok": true, "result": result}
