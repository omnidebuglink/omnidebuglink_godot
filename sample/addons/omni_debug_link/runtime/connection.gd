extends RefCounted
## WebSocket connection to the OmniDebugLink relay (wire protocol v1).
##
## Driven by poll() from the autoload's _process — single-threaded, web-export
## safe. Owns: hello on open, 55s heartbeat, 180s inbound watchdog, exponential
## backoff reconnect (1s -> 30s) and the close-code-4000 permanent stop.


const HEARTBEAT_MS := 55000.0
const WATCHDOG_MS := 180000
const BACKOFF_INITIAL_MS := 1000
const BACKOFF_CAP_MS := 30000
const CONNECT_TIMEOUT_MS := 20000
const FRAME_BUDGET_BYTES := 900000

var _url := ""
var _build_hello: Callable
var _on_task: Callable
var _on_state: Callable
var _on_log: Callable
var _on_replaced: Callable

var _ws: WebSocketPeer = null
var _stopped := true
var _replaced := false
var _hello_sent := false
var _backoff_ms := BACKOFF_INITIAL_MS
var _retry_at_ms := 0
var _last_inbound_ms := 0
var _heartbeat_accum_ms := 0.0
var _connecting_since_ms := 0
var _connected := false


func _init(url: String, build_hello: Callable, on_task: Callable, on_state: Callable, on_log: Callable, on_replaced: Callable) -> void:
	_url = url
	_build_hello = build_hello
	_on_task = on_task
	_on_state = on_state
	_on_log = on_log
	_on_replaced = on_replaced


func start() -> void:
	_stopped = false
	_replaced = false
	_backoff_ms = BACKOFF_INITIAL_MS
	_retry_at_ms = 0
	_heartbeat_accum_ms = 0.0
	_hello_sent = false


func stop() -> void:
	_stopped = true
	if _ws != null:
		_ws.close()
		_ws = null
	_set_connected(false)


func is_open() -> bool:
	return _connected


func is_stopped() -> bool:
	return _stopped


## Re-sends the hello frame while connected (registry or actionsEnabled changed).
func request_hello_resend() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send(JSON.stringify(_build_hello.call()))


func poll(delta_ms: float) -> void:
	if _stopped or _replaced:
		return
	if _ws == null:
		if Time.get_ticks_msec() >= _retry_at_ms:
			_try_connect()
		return

	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_hello_sent = true
			_backoff_ms = BACKOFF_INITIAL_MS
			_set_connected(true)
			_send(JSON.stringify(_build_hello.call()))
		_drain_packets()
		if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return
		_heartbeat_accum_ms += delta_ms
		if _heartbeat_accum_ms >= HEARTBEAT_MS:
			_heartbeat_accum_ms = 0.0
			if Time.get_ticks_msec() - _last_inbound_ms > WATCHDOG_MS:
				_log("watchdog: server silent for 180s, dropping connection", "warning")
				_drop_and_retry()
				return
			_send('{"v":1,"type":"ping"}')
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		_set_connected(false)
		if code == 4000:
			# Same token taken over by a newer connection. Reconnecting would
			# ping-pong with the server's kick mechanism forever — and a live
			# token inside a release build means the SDK shipped by mistake,
			# so the host fails loud (quit / web alert) instead of staying silent.
			_replaced = true
			_log("TOKEN REPLACED (close 4000): this token was claimed by another connection. Stopping reconnects and quitting. Use one token pair per device; never ship start() in release builds.", "error")
			if _on_replaced.is_valid():
				_on_replaced.call()
			return
		_log("connection closed (code %d), reconnecting" % code, "warning")
		_schedule_retry()
	else:
		# STATE_CONNECTING: guard against a handshake that never completes
		# (WebSocketPeer itself has no connect timeout).
		if Time.get_ticks_msec() - _connecting_since_ms > CONNECT_TIMEOUT_MS:
			_log("connect handshake timed out after 20s, retrying", "warning")
			_drop_and_retry()
	# STATE_CLOSING: just wait for the next poll.


func send_result_ok(request_id: String, result: Variant) -> void:
	var frame := {"v": 1, "type": "result", "requestId": request_id, "ok": true, "result": result}
	var text := JSON.stringify(frame)
	if text.to_utf8_buffer().size() > FRAME_BUDGET_BYTES:
		send_result_error(request_id, "PAYLOAD_TOO_LARGE", "result exceeds the 900KB frame budget")
		return
	_send(text)


func send_result_error(request_id: String, code: String, message: String) -> void:
	_send(JSON.stringify({"v": 1, "type": "result", "requestId": request_id, "ok": false, "error": {"code": code, "message": message}}))


func _try_connect() -> void:
	var ws := WebSocketPeer.new()
	var err := ws.connect_to_url(_url)
	if err != OK:
		_log("connect_to_url failed: %s" % error_string(err), "warning")
		_schedule_retry()
		return
	_ws = ws
	_hello_sent = false
	_connecting_since_ms = Time.get_ticks_msec()
	_last_inbound_ms = Time.get_ticks_msec()
	_heartbeat_accum_ms = 0.0


func _schedule_retry() -> void:
	_retry_at_ms = Time.get_ticks_msec() + _backoff_ms
	_backoff_ms = mini(_backoff_ms * 2, BACKOFF_CAP_MS)


func _drop_and_retry() -> void:
	_ws = null
	_set_connected(false)
	_schedule_retry()


func _drain_packets() -> void:
	while _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		_last_inbound_ms = Time.get_ticks_msec()
		_handle_frame(text)


func _handle_frame(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var frame: Dictionary = msg
	if int(frame.get("v", 0)) != 1:
		return
	match String(frame.get("type", "")):
		"pong":
			return
		"task":
			var request_id = frame.get("requestId")
			var task = frame.get("task")
			if typeof(request_id) != TYPE_STRING or typeof(task) != TYPE_DICTIONARY:
				return
			var task_type = task.get("type")
			if typeof(task_type) != TYPE_STRING or String(task_type) == "":
				return
			var payload = task.get("payload", {})
			if typeof(payload) != TYPE_DICTIONARY:
				payload = {}
			_on_task.call(request_id, task_type, payload)
		_:
			return


func _send(text: String) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if text.to_utf8_buffer().size() > FRAME_BUDGET_BYTES:
		_log("outgoing frame exceeds 900KB budget, dropping", "error")
		return
	var err := _ws.send_text(text)
	if err != OK:
		_log("send failed: %s" % error_string(err), "warning")


func _set_connected(value: bool) -> void:
	if _connected == value:
		return
	_connected = value
	if _on_state.is_valid():
		_on_state.call(value)


func _log(message: String, level: String) -> void:
	if _on_log.is_valid():
		_on_log.call(message, level)
