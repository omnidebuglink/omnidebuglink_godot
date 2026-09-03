extends RefCounted
## read_logs — ring-buffer query over SDK + engine log entries.


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("read_logs",
		Callable(self, "read_logs"),
		"Returns captured log entries (oldest first) with level / contains / limit / since_ms filtering. Sources: OmniDebugLink.log()/log_warning()/log_error() calls, SDK connection events, and the engine log file (user://logs/godot.log) when project file logging is enabled.",
		{
			"type": "object",
			"properties": {
				"level": {"type": "string", "enum": ["info", "warning", "error"], "description": "exact level filter"},
				"contains": {"type": "string", "description": "substring filter (case-insensitive)"},
				"limit": {"type": "integer", "minimum": 1, "maximum": 1000, "description": "max entries returned, default 200"},
				"since_ms": {"type": "integer", "description": "only entries with ts_ms >= this (unix milliseconds)"},
			},
		})


func read_logs(payload: Dictionary) -> Dictionary:
	var level := String(payload.get("level", ""))
	var contains := String(payload.get("contains", "")).to_lower()
	var limit := int(payload.get("limit", 200))
	if limit <= 0 or limit > 1000:
		limit = 200
	var since_ms := int(payload.get("since_ms", 0))
	var matched: Array = []
	for e in odl.logs.entries():
		var entry: Dictionary = e
		if level != "" and String(entry.get("level", "")) != level:
			continue
		if since_ms > 0 and int(entry.get("ts_ms", 0)) < since_ms:
			continue
		if contains != "" and not String(entry.get("message", "")).to_lower().contains(contains):
			continue
		matched.append(entry)
	var total := matched.size()
	if matched.size() > limit:
		matched = matched.slice(matched.size() - limit)
	return {"logs": matched, "matched": total, "returned": matched.size(), "source": "file_tail" if odl.logs.is_tailing() else "sdk_buffer"}
