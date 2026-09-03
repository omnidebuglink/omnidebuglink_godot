extends RefCounted
## screenshot — viewport capture as JPEG via the __odl_file envelope.


var odl: Node


func register(odl: Node, reg) -> void:
	self.odl = odl
	reg.register("screenshot",
		Callable(self, "screenshot"),
		"Captures the viewport as a JPEG image (long side capped at 1920px, quality auto-adjusted to fit the relay frame budget). Waits for the end of the current frame so the image matches what is on screen. Coordinate origin for tap/swipe tasks is the TOP-LEFT, matching this image.",
		{
			"type": "object",
			"properties": {
				"quality": {"type": "number", "minimum": 0.1, "maximum": 1.0, "description": "initial JPEG quality, default 0.8 (reduced automatically if too large)"},
				"max_side": {"type": "integer", "minimum": 200, "maximum": 4096, "description": "long-side pixel cap, default 1920"},
				"viewport": {"type": "string", "description": "NodePath of a Viewport to capture instead of the root"},
			},
		})


func screenshot(payload: Dictionary) -> Dictionary:
	var quality := float(payload.get("quality", 0.8))
	var max_side := int(payload.get("max_side", 1920))
	var vp: Viewport = odl.get_viewport()
	var vp_path := String(payload.get("viewport", ""))
	if vp_path != "":
		var candidate: Node = odl.node_from_path(vp_path)
		if candidate == null or not (candidate is Viewport):
			return odl.task_error("viewport not found: " + vp_path)
		vp = candidate as Viewport
	# Grab the last drawn frame by polling: minimized/occluded desktop windows
	# stop rendering, and awaiting RenderingServer.frame_post_draw would hang
	# the task forever (real-machine finding 2026-09). Polling also covers
	# headless, where the signal never fires and get_image() stays empty.
	var img: Image = vp.get_texture().get_image()
	if DisplayServer.get_name() != "headless":
		var deadline := Time.get_ticks_msec() + 3000
		while (img == null or img.is_empty()) and Time.get_ticks_msec() < deadline:
			await odl.wait(0.1)
			img = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return odl.task_error("failed to capture viewport image (no frame available — window minimized, or headless rendering without GPU)")
	var w := img.get_width()
	var h := img.get_height()
	var longest := maxi(w, h)
	if max_side > 0 and longest > max_side:
		var scale := float(max_side) / float(longest)
		img.resize(maxi(1, int(w * scale)), maxi(1, int(h * scale)), Image.INTERPOLATE_BILINEAR)
		w = img.get_width()
		h = img.get_height()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	# base64 inflates by 4/3; keep the source JPEG under ~675KB.
	var buf := img.save_jpg_to_buffer(quality)
	while buf.size() > 675000 and quality > 0.35:
		quality -= 0.15
		buf = img.save_jpg_to_buffer(quality)
	return {"width": w, "height": h, "__odl_file": {"mime": "image/jpeg", "data": Marshalls.raw_to_base64(buf)}}
