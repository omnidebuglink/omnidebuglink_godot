extends Node
## OmniDebugLink — autoload entry point.
##
## Usage:
##     OmniDebugLink.start("<clientToken>")
##     OmniDebugLink.stop()
##     OmniDebugLink.actions_enabled = false   # read-only observation mode
##     OmniDebugLink.tasks.register("my_task", handler, "description", schema)
##     OmniDebugLink.log("reachable via read_logs")
##
## The whole SDK runs on the main thread: _process polls the WebSocketPeer,
## heartbeat/watchdog/backoff timers and the log-file tail. No threads, so the
## same code works on desktop, mobile and web exports.

signal state_changed(connected: bool)

const LIB_VERSION := "0.1.1"
const DEFAULT_WS_URL := "wss://api.omnidebuglink.dev/ws"

const ConnectionScript := preload("./connection.gd")
const TaskRegistryScript := preload("./task_registry.gd")
const LogBufferScript := preload("./log_buffer.gd")
const JsonUtil := preload("./json_util.gd")
const BuiltinTasks := preload("./tasks/register_builtins.gd")

## Master switch for every task that mutates game state. When false, write
## tasks fail with ACTION_DISABLED and the flag is reported in hello.
var actions_enabled := true:
	set(value):
		if actions_enabled == value:
			return
		actions_enabled = value
		_request_hello_resend()

var tasks
var logs

var _conn = null
var _connected := false
var _start_ticks_ms := 0
## Builtin task module instances — Callables do not keep RefCounted receivers
## alive in 4.2, so the autoload owns the lifeline.
var _task_modules: Array = []


func _ready() -> void:
	# Keep pumping while the game is paused (pause menus are common): a frozen
	# _process would stall the WebSocket poll too, deferring the close-4000
	# detection and the fail-loud exit indefinitely (pitfall 14's intent).
	process_mode = Node.PROCESS_MODE_ALWAYS
	tasks = TaskRegistryScript.new()
	logs = LogBufferScript.new()
	tasks.on_changed = Callable(self, "_request_hello_resend")
	_task_modules = BuiltinTasks.register_all(self, tasks)
	set_process(false)


func _exit_tree() -> void:
	stop()


## client_token comes from the device console (device_detail). One token pair
## equals one device seat — never share a token between two running instances.
## url overrides the relay endpoint (defaults to the OmniDebugLink cloud).
func start(client_token: String, url := "") -> void:
	var full_url := url if url != "" else "%s?token=%s" % [DEFAULT_WS_URL, client_token.uri_encode()]
	_start_ticks_ms = Time.get_ticks_msec()
	if _conn != null:
		_conn.stop()
	_conn = ConnectionScript.new(
		full_url,
		Callable(self, "_build_hello"),
		Callable(self, "_on_task"),
		Callable(self, "_on_state"),
		Callable(self, "_on_log"),
		Callable(self, "_on_replaced")
	)
	_conn.start()
	set_process(true)


func stop() -> void:
	set_process(false)
	if _conn != null:
		_conn.stop()
		_conn = null
	_set_connected(false)


## Connection state. (Named `connected`, not `is_connected`, to avoid clashing
## with Object's built-in is_connected(signal, callable).)
func connected() -> bool:
	return _connected


func uptime_ms() -> int:
	return Time.get_ticks_msec() - _start_ticks_ms if _start_ticks_ms > 0 else 0


func _process(delta: float) -> void:
	if _conn != null:
		_conn.poll(delta * 1000.0)
	logs.poll(delta)


## User-facing logging helpers; entries are readable through the read_logs task.
func log(message: String) -> void:
	logs.add_user("info", message)


func log_warning(message: String) -> void:
	logs.add_user("warning", message)


func log_error(message: String) -> void:
	logs.add_user("error", message)


## Marker returned by task handlers to report failure (GDScript has no
## exceptions; the registry unwraps this into an error result).
static func task_error(message: String, code := "TASK_FAILED") -> Dictionary:
	return {"__odl_error": true, "code": code, "message": message}


func gate_writes() -> Dictionary:
	if not actions_enabled:
		return task_error("write actions disabled (set OmniDebugLink.actions_enabled = true)", "ACTION_DISABLED")
	return {}


## Sanitize any Variant into JSON-safe data (used by handlers and available to
## custom tasks as OmniDebugLink.jsonable(...)).
func jsonable(value: Variant) -> Variant:
	return JsonUtil.to_jsonable(value)


## ---------- task handler helpers (shared by builtin & custom tasks) ----------

## Resolve a node path from a task payload; returns null when absent/invalid.
func node_from_path(path: String) -> Node:
	if path == "":
		return null
	var root := get_tree().root
	return root.get_node_or_null(NodePath(path))


## Screen/canvas size used to convert between normalized (0-1) and pixel
## coordinates. Accounts for canvas_item stretch modes.
func canvas_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Normalize a canvas-space pixel position to 0-1 (origin top-left).
func normalize_pos(px: Vector2) -> Array:
	var size := canvas_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return [0.0, 0.0]
	return [px.x / size.x, px.y / size.y]


## Displayed text of a node (Label/Button/LineEdit/TextEdit and scripted nodes
## exposing a `text` property). Empty string when the node shows no text.
static func display_text(node: Node) -> String:
	if node == null:
		return ""
	var value = node.get("text")
	if typeof(value) == TYPE_STRING:
		return value
	return ""


## Frame-loop timer helper that ignores Engine.time_scale and keeps running
## while the tree is paused (debugging must not freeze when the game does).
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## ---------- protocol plumbing ----------

func _build_hello() -> Dictionary:
	return {
		"v": 1,
		"type": "hello",
		"client": {
			"platform": "godot",
			"version": "%s / %s" % [String(Engine.get_version_info().get("string", "")), OS.get_name()],
			"libVersion": LIB_VERSION,
			"actionsEnabled": actions_enabled,
		},
		"tasks": tasks.snapshot(),
	}


func _request_hello_resend() -> void:
	if _conn != null:
		_conn.request_hello_resend()


func _on_task(request_id: String, task_type: String, payload: Dictionary) -> void:
	# Fire without await: each invocation is its own coroutine, so concurrent
	# tasks (e.g. a long wait_for) never block dispatching of the next one.
	_run_task_and_reply(request_id, task_type, payload)


func _run_task_and_reply(request_id: String, task_type: String, payload: Dictionary) -> void:
	var outcome: Dictionary = await tasks.run(task_type, payload)
	if _conn == null:
		return
	if bool(outcome.get("ok", false)):
		var result: Variant = outcome.get("result", {})
		_conn.send_result_ok(request_id, result)
	else:
		var err: Dictionary = outcome.get("error", {})
		_conn.send_result_error(request_id, String(err.get("code", "TASK_FAILED")), String(err.get("message", "task failed")))


func _on_state(connected: bool) -> void:
	_set_connected(connected)
	logs.add_sdk("info" if connected else "warning", "connection " + ("established" if connected else "lost"))


func _on_log(message: String, level: String) -> void:
	logs.add_sdk(level, message)


## Close code 4000 arrived: this token was claimed by a newer connection.
## Fail loud — quit the process so a token that was accidentally shipped
## inside a release build cannot keep the debug channel alive silently.
## The web export cannot close its own tab, so the equivalent loud signal
## is a modal browser alert. (Engine.get_singleton instead of the bare
## JavaScriptBridge identifier: the class does not exist in ClassDB on
## non-web builds and would break script parsing there.)
func _on_replaced() -> void:
	if OS.has_feature("web"):
		var text := "OmniDebugLink: connection replaced (close code 4000)\\n\\nAnother client just connected with the same device token.\\nEach device must use its own token pair.\\n\\nIf you are seeing this on a production site, the OmniDebugLink SDK was accidentally left enabled - remove the OmniDebugLink.start() call from your release build."
		var js: Object = Engine.get_singleton("JavaScriptBridge")
		# Browsers can suppress alert() (sandboxed iframe without allow-modals,
		# or "prevent this page from creating additional dialogs") — leave a
		# trace in the JS console too so the alert is not the only loud signal.
		js.eval("console.error('OmniDebugLink: connection replaced (close code 4000) - another client just connected with the same device token; the debug channel is stopped.')")
		js.eval("alert('%s')" % text)
	else:
		get_tree().quit()


func _set_connected(value: bool) -> void:
	if _connected == value:
		return
	_connected = value
	state_changed.emit(value)
