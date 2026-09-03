extends RefCounted
## echo / ping / get_stats — connectivity baseline required by the relay.


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("echo",
		Callable(self, "echo_task"),
		"Returns the payload unchanged. Useful for smoke-testing the relay loop.",
		{
			"type": "object",
			"properties": {"text": {"type": "string", "description": "arbitrary payload echoed back"}},
		})
	reg.register("ping",
		Callable(self, "ping_task"),
		"Measures round-trip time to the device. The relay computes rtt from sentAt.",
		{})
	reg.register("get_stats",
		Callable(self, "get_stats_task"),
		"Returns client stats: uptime, registered task count, connection state, Godot version, platform and the current scene path.",
		{})


func echo_task(payload: Dictionary) -> Dictionary:
	return {"echo": payload.get("text", "")}


func ping_task(payload: Dictionary) -> Dictionary:
	return {}


func get_stats_task(payload: Dictionary) -> Dictionary:
	var scene := ""
	var current = odl.get_tree().current_scene
	if current != null and is_instance_valid(current):
		scene = str(current.get_path())
	return {
		"uptimeMs": odl.uptime_ms(),
		"taskCount": odl.tasks.count(),
		"connected": odl.connected(),
		"libVersion": odl.LIB_VERSION,
		"godotVersion": String(Engine.get_version_info().get("string", "")),
		"platform": OS.get_name(),
		"scene": scene,
		"actionsEnabled": odl.actions_enabled,
	}
