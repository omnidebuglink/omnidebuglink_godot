extends RefCounted
## get_perf — engine performance counters, plus the game's custom monitors.


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("get_perf",
		Callable(self, "get_perf"),
		"Returns performance counters: fps, process/physics times, draw calls, object/node counts, engine memory, video memory, OS memory and any custom monitors the game registered with Performance.add_custom_monitor. Set sample_frames (>0) to also get frame-time percentiles p50/p95/p99 measured over that many frames.",
		{
			"type": "object",
			"properties": {
				"sample_frames": {"type": "integer", "minimum": 0, "maximum": 600, "description": "0 = skip percentile sampling (default)"},
			},
		})


func get_perf(payload: Dictionary) -> Dictionary:
	var out := {
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"os_memory": odl.jsonable(OS.get_memory_info()),
	}
	var custom := {}
	for monitor_name in Performance.get_custom_monitor_names():
		var n := String(monitor_name)
		if Performance.has_custom_monitor(n):
			custom[n] = odl.jsonable(Performance.get_custom_monitor(n))
		else:
			custom[n] = null
	out["custom_monitors"] = custom
	var sample_frames := int(payload.get("sample_frames", 0))
	if sample_frames > 0:
		# process_frame fires every engine iteration (headless included);
		# consecutive-stamp deltas give the frame period.
		var stamps: Array = []
		for i in sample_frames:
			await odl.get_tree().process_frame
			stamps.append(Time.get_ticks_usec())
		var frame_times: Array = []
		for i in range(1, stamps.size()):
			frame_times.append((stamps[i] - stamps[i - 1]) / 1000.0)
		out["frame_time_ms"] = {
			"sampled_frames": frame_times.size(),
			"p50": percentile(frame_times, 0.5),
			"p95": percentile(frame_times, 0.95),
			"p99": percentile(frame_times, 0.99),
		}
	return out


func percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := int(clampf(q, 0.0, 1.0) * float(sorted.size() - 1))
	return float(sorted[idx])
