extends RefCounted
## Sanitizes arbitrary Godot Variants into JSON-serializable data.
##
## Every task result goes through to_jsonable() before JSON.stringify(), so a
## handler that accidentally returns a Node, Vector2 or a cyclic object can
## never produce a frame the relay would reject.


const MAX_DEPTH := 16


static func to_jsonable(value: Variant, depth: int = 0, seen: Dictionary = {}) -> Variant:
	if depth > MAX_DEPTH:
		return "<max depth>"
	var t := typeof(value)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			return str(value)
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4:
			return [value.x, value.y, value.z, value.w]
		TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_RECT2, TYPE_RECT2I:
			return {"position": [value.position.x, value.position.y], "size": [value.size.x, value.size.y]}
		TYPE_TRANSFORM2D:
			return [to_jsonable(value.origin, depth + 1, seen), to_jsonable([value.x.x, value.x.y, value.y.x, value.y.y], depth + 1, seen)]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION:
			return str(value)
		TYPE_DICTIONARY:
			var d := {}
			for k in value:
				var key := str(k)
				d[key] = to_jsonable(value[k], depth + 1, seen)
			return d
		TYPE_ARRAY:
			var cycle := _guard(value, seen)
			if not cycle.is_empty():
				return "<cycle>"
			var a := []
			for item in value:
				a.append(to_jsonable(item, depth + 1, seen))
			_unguard(value, seen)
			return a
		TYPE_PACKED_BYTE_ARRAY:
			return "<PackedByteArray: %d bytes>" % value.size()
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var pa := []
			for item in value:
				pa.append(to_jsonable(item, depth + 1, seen))
			return pa
		TYPE_OBJECT:
			if value == null:
				return null
			var marker := _guard(value, seen)
			if not marker.is_empty():
				return "<cycle>"
			var out := _object_summary(value)
			_unguard(value, seen)
			return out
		_:
			return str(value)


static func _object_summary(obj: Object) -> Variant:
	if obj is Node:
		var node := obj as Node
		if is_instance_valid(node):
			var info := {"__node": str(node.get_path()), "type": node.get_class()}
			var script := node.get_script()
			if script != null and script.resource_path != "":
				info["script"] = script.resource_path
			return info
		return "<freed Node>"
	if obj is Resource:
		var res := obj as Resource
		if res.resource_path != "":
			return res.resource_path
		return "<%s (inline resource)>" % res.get_class()
	return "<%s>" % obj.get_class()


static func _guard(obj: Object, seen: Dictionary) -> Dictionary:
	var id := obj.get_instance_id()
	if seen.has(id):
		return {"id": id}
	seen[id] = true
	return {}


static func _unguard(obj: Object, seen: Dictionary) -> void:
	seen.erase(obj.get_instance_id())

