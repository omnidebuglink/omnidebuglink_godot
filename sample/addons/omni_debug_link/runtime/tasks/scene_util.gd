extends RefCounted
## Shared scene-tree helpers used by the builtin tasks (and available to
## custom tasks via preload).


const TRAVERSE_CAP := 3000
const SCAN_CAP := 20000


## DFS pre-order flatten, capped. Returns {"nodes": Array[Node], "truncated": bool}.
static func flatten(root: Node, cap: int) -> Dictionary:
	var nodes: Array = []
	var truncated := false
	if root == null:
		return {"nodes": nodes, "truncated": truncated}
	var stack: Array = [root]
	while not stack.is_empty():
		if nodes.size() >= cap:
			truncated = true
			break
		var n: Node = stack.pop_back()
		nodes.append(n)
		var children := n.get_children()
		children.reverse()
		for child in children:
			stack.push_back(child)
	return {"nodes": nodes, "truncated": truncated}


## Nearest Control (self or ancestor) that looks interactive.
static func click_target_of(node: Node) -> Control:
	var cur: Node = node
	while cur != null:
		if cur is Control and is_clickable(cur):
			return cur as Control
		cur = cur.get_parent()
	return null


static func is_clickable(c: Control) -> bool:
	if c.is_class("BaseButton") or c.is_class("Slider") or c.is_class("LineEdit") or c.is_class("TextEdit") or c.is_class("ItemList") or c.is_class("GraphNode"):
		return true
	return not c.get_signal_connection_list("gui_input").is_empty()


static func name_matches(node: Node, pattern: String, regex: RegEx) -> bool:
	var n := String(node.name)
	if regex != null:
		return regex.search(n) != null
	return n.to_lower().contains(pattern.to_lower())


## Native class (with subclass matching), case-insensitive class name, or
## script file basename.
static func type_matches(node: Node, type_str: String) -> bool:
	if node.is_class(type_str):
		return true
	if node.get_class().to_lower() == type_str.to_lower():
		return true
	var script = node.get_script()
	if script != null and script.resource_path != "":
		if script.resource_path.get_file().get_basename().to_lower() == type_str.to_lower():
			return true
	return false


## Exact-text matches first; falls back to substring matches when none match
## exactly (both case-insensitive).
static func find_by_text(odl: Node, text: String) -> Array:
	var flat := flatten(odl.get_tree().root, SCAN_CAP)
	var exact: Array = []
	var partial: Array = []
	var needle := text.to_lower()
	for n in flat["nodes"]:
		var t: String = odl.display_text(n)
		if t == "":
			continue
		var lower := t.to_lower()
		if lower == needle:
			exact.append(n)
		elif lower.contains(needle):
			partial.append(n)
	if not exact.is_empty():
		return exact
	return partial


static func node_hit_info(odl: Node, node: Node) -> Dictionary:
	var info := {"path": str(node.get_path()), "name": String(node.name), "type": node.get_class()}
	var script = node.get_script()
	if script != null and script.resource_path != "":
		info["script"] = script.resource_path.get_file()
	var t: String = odl.display_text(node)
	if t != "":
		info["text"] = t
	if node is Control:
		var c := node as Control
		var rect := c.get_global_rect()
		var center := rect.get_center()
		info["center_px"] = [center.x, center.y]
		info["center_norm"] = odl.normalize_pos(center)
		info["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		var target := click_target_of(node)
		if target != null and target != node:
			info["click_target"] = str(target.get_path())
	elif node is Node2D:
		var n2 := node as Node2D
		var pos := n2.get_global_position()
		info["position_px"] = [pos.x, pos.y]
	var vis = node.get("visible")
	if typeof(vis) == TYPE_BOOL:
		info["visible"] = vis
	return info


## Property type via get_property_list (includes script variables), TYPE_NIL if absent.
static func property_type(node: Node, prop: String) -> int:
	for p in node.get_property_list():
		if String(p.get("name", "")) == prop:
			return int(p.get("type", TYPE_NIL))
	return TYPE_NIL


## Best-effort coercion of JSON values into engine value types for set_prop.
static func coerce_value(value: Variant, target_type: int) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var a: Array = value
		match target_type:
			TYPE_VECTOR2:
				if a.size() == 2:
					return Vector2(float(a[0]), float(a[1]))
			TYPE_VECTOR2I:
				if a.size() == 2:
					return Vector2i(int(a[0]), int(a[1]))
			TYPE_VECTOR3:
				if a.size() == 3:
					return Vector3(float(a[0]), float(a[1]), float(a[2]))
			TYPE_VECTOR3I:
				if a.size() == 3:
					return Vector3i(int(a[0]), int(a[1]), int(a[2]))
			TYPE_RECT2:
				if a.size() == 4:
					return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			TYPE_RECT2I:
				if a.size() == 4:
					return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
			TYPE_COLOR:
				if a.size() >= 3:
					return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	match target_type:
		TYPE_INT:
			if typeof(value) == TYPE_FLOAT:
				return int(value)
		TYPE_FLOAT:
			if typeof(value) == TYPE_INT:
				return float(value)
		TYPE_STRING:
			if typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_NODE_PATH:
				return str(value)
	return value
