extends RefCounted
## scene_traverse / find_objects / view_component / get_prop / wait_for.

const SceneUtil := preload("./scene_util.gd")


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("scene_traverse",
		Callable(self, "scene_traverse"),
		"Dumps the scene tree as a flat list of nodes (default root /root, capped at 3000 nodes, set root to dump a subtree). Each node carries its path, native type, script path, displayed text (Label/Button/LineEdit and any node exposing a text property) and visibility. Use it to understand what is currently on screen; the paths feed directly into ui_click / view_component / set_prop.",
		{
			"type": "object",
			"properties": {
				"root": {"type": "string", "description": "NodePath to start from (default /root)"},
				"max_nodes": {"type": "integer", "minimum": 1, "maximum": 20000, "description": "cap, default 3000"},
			},
		})
	reg.register("find_objects",
		Callable(self, "find_objects"),
		"Searches the scene tree by node name substring (or regex via use_regex), displayed text or node type, and returns matches with path, center coordinates and the nearest clickable ancestor (click_target). Prefer this over scene_traverse when looking for something specific in a large scene.",
		{
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "node name substring (case-insensitive) or regex"},
				"text": {"type": "string", "description": "displayed text substring (case-insensitive), e.g. the label on a button"},
				"type": {"type": "string", "description": "native class (subclass-aware, e.g. Button matches CheckBox) or script file basename"},
				"use_regex": {"type": "boolean", "description": "treat name as a regular expression (default false)"},
				"limit": {"type": "integer", "minimum": 1, "maximum": 200, "description": "max matches returned, default 50"},
			},
		})
	reg.register("view_component",
		Callable(self, "view_component"),
		"Returns full details of one node: stored property names/types/values (script variables included), incoming signal connections, groups and direct children. Use it after scene_traverse or find_objects to inspect a specific node.",
		{
			"type": "object",
			"properties": {"path": {"type": "string"}},
			"required": ["path"],
		})
	reg.register("get_prop",
		Callable(self, "get_prop"),
		"Reads a single property value of a node.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"prop": {"type": "string", "description": "property name, e.g. text, visible, position"},
			},
			"required": ["path", "prop"],
		})
	reg.register("wait_for",
		Callable(self, "wait_for"),
		"Polls until a node path exists, or until a property on it equals the given value (omit equals to just wait for the node). Returns found=true/false — a timeout is not an error. Default interval 200ms, default timeout 10s; polling ignores Engine.time_scale and works while the tree is paused.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"prop": {"type": "string", "description": "property to watch on the node"},
				"equals": {"description": "value the property must reach (JSON)"},
				"timeout_ms": {"type": "integer", "minimum": 100, "default": 10000},
				"interval_ms": {"type": "integer", "minimum": 50, "default": 200},
			},
			"required": ["path"],
		})


func scene_traverse(payload: Dictionary) -> Dictionary:
	var max_nodes := int(payload.get("max_nodes", SceneUtil.TRAVERSE_CAP))
	if max_nodes <= 0 or max_nodes > SceneUtil.SCAN_CAP:
		max_nodes = SceneUtil.TRAVERSE_CAP
	var root_path := String(payload.get("root", ""))
	var root: Node = odl.get_tree().root if root_path == "" else odl.node_from_path(root_path)
	if root == null:
		return odl.task_error("root node not found: " + root_path)
	var flat := SceneUtil.flatten(root, max_nodes)
	var nodes: Array = []
	for n in flat["nodes"]:
		var entry := {"path": str(n.get_path()), "type": n.get_class()}
		var script = n.get_script()
		if script != null and script.resource_path != "":
			entry["script"] = script.resource_path
		var t: String = odl.display_text(n)
		if t != "":
			entry["text"] = t
		var vis = n.get("visible")
		if typeof(vis) == TYPE_BOOL:
			entry["visible"] = vis
		var child_count: int = n.get_child_count()
		if child_count > 0:
			entry["children"] = child_count
		nodes.append(entry)
	return {"root": str(root.get_path()), "node_count": nodes.size(), "truncated": flat["truncated"], "nodes": nodes}


func find_objects(payload: Dictionary) -> Dictionary:
	var name_pat := String(payload.get("name", ""))
	var text_pat := String(payload.get("text", ""))
	var type_pat := String(payload.get("type", ""))
	var use_regex := bool(payload.get("use_regex", false))
	var limit := int(payload.get("limit", 50))
	if name_pat == "" and text_pat == "" and type_pat == "":
		return odl.task_error("no filter given: provide at least one of name / text / type (or use scene_traverse to dump the whole tree)")
	if limit <= 0 or limit > 200:
		limit = 50
	var regex: RegEx = null
	if use_regex and name_pat != "":
		regex = RegEx.new()
		if regex.compile(name_pat) != OK:
			return odl.task_error("invalid regex: " + name_pat)
	var flat := SceneUtil.flatten(odl.get_tree().root, SceneUtil.SCAN_CAP)
	var needle := text_pat.to_lower()
	var matches: Array = []
	for n in flat["nodes"]:
		if name_pat != "" and not SceneUtil.name_matches(n, name_pat, regex):
			continue
		if text_pat != "" and not odl.display_text(n).to_lower().contains(needle):
			continue
		if type_pat != "" and not SceneUtil.type_matches(n, type_pat):
			continue
		matches.append(SceneUtil.node_hit_info(odl, n))
		if matches.size() >= limit:
			break
	return {"matches": matches, "scanned": flat["nodes"].size(), "truncated": flat["truncated"] or matches.size() >= limit}


func view_component(payload: Dictionary) -> Dictionary:
	var path := String(payload.get("path", ""))
	var node: Node = odl.node_from_path(path)
	if node == null:
		return odl.task_error("node not found: " + path)
	var out := {"path": str(node.get_path()), "type": node.get_class()}
	var script = node.get_script()
	if script != null:
		out["script"] = script.resource_path if script.resource_path != "" else "<inline script>"
	var props: Array = []
	for p in node.get_property_list():
		var usage := int(p.get("usage", 0))
		if (usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE)) == 0:
			continue
		var pname := String(p.get("name", ""))
		if pname == "":
			continue
		props.append({"name": pname, "type": type_string(int(p.get("type", TYPE_NIL))), "value": odl.jsonable(node.get(pname))})
		if props.size() >= 400:
			break
	out["properties"] = props
	var signals := {}
	for conn in node.get_incoming_connections():
		var sig_name := str(conn.get("signal", ""))
		var cb: Callable = conn.get("callable", Callable())
		var entry := {"callable": String(cb.get_method())}
		var target = cb.get_object()
		if target is Node and is_instance_valid(target):
			entry["source"] = str((target as Node).get_path())
		if not signals.has(sig_name):
			signals[sig_name] = []
		signals[sig_name].append(entry)
	out["connected_signals"] = signals
	var groups: Array = []
	for g in node.get_groups():
		groups.append(str(g))
	out["groups"] = groups
	var children: Array = []
	for c in node.get_children():
		children.append({"path": str(c.get_path()), "type": c.get_class()})
	out["children"] = children
	return out


func get_prop(payload: Dictionary) -> Dictionary:
	var path := String(payload.get("path", ""))
	var node: Node = odl.node_from_path(path)
	if node == null:
		return odl.task_error("node not found: " + path)
	var prop := String(payload.get("prop", ""))
	if prop == "":
		return odl.task_error("prop is required")
	if SceneUtil.property_type(node, prop) == TYPE_NIL:
		return odl.task_error('node has no property "%s"' % prop)
	return {"path": str(node.get_path()), "prop": prop, "value": odl.jsonable(node.get(prop))}


func wait_for(payload: Dictionary) -> Dictionary:
	var path := String(payload.get("path", ""))
	if path == "":
		return odl.task_error("path is required")
	var prop := String(payload.get("prop", ""))
	var has_equals := payload.has("equals")
	var equals: Variant = payload.get("equals", null)
	var timeout_ms := int(payload.get("timeout_ms", 10000))
	var interval_ms := int(payload.get("interval_ms", 200))
	if interval_ms < 50:
		interval_ms = 50
	var started := Time.get_ticks_msec()
	var deadline := started + timeout_ms
	var last_value: Variant = null
	while true:
		var node: Node = odl.node_from_path(path)
		var found := false
		if node != null:
			if prop == "":
				found = true
			else:
				last_value = node.get(prop)
				if not has_equals:
					found = last_value != null and (typeof(last_value) != TYPE_BOOL or bool(last_value))
				else:
					found = values_equal(last_value, equals)
		if found:
			var res := {"found": true, "elapsed_ms": Time.get_ticks_msec() - started}
			if prop != "":
				res["value"] = odl.jsonable(last_value)
			return res
		if Time.get_ticks_msec() >= deadline:
			var res_timeout := {"found": false, "elapsed_ms": Time.get_ticks_msec() - started, "path": path}
			if prop != "":
				res_timeout["prop"] = prop
				res_timeout["last_value"] = odl.jsonable(last_value)
			return res_timeout
		await odl.wait(interval_ms / 1000.0)
	# Unreachable: the while-loop only exits through return. Keeps the 4.2
	# flow analyzer happy for functions with a Dictionary return type.
	return {}


func values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b):
		return a == b
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)
