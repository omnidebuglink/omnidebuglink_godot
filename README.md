# OmniDebugLink for Godot

Remote debugging and AI-driven testing for [Godot 4](https://godotengine.org) games. Drop this addon into your project, start it with a device token, and AI tools (or your own scripts) connected to [OmniDebugLink](https://omnidebuglinkweb.pages.dev) can inspect the live scene tree, read logs, take screenshots, inject real input events and call into your game — on desktop, mobile and web exports.

- Pure GDScript, zero dependencies, no threads — one code path for every platform Godot exports to.
- Runs on the main thread through `_process`, so handlers can safely touch any Godot API.
- Input injection goes through the real event pipeline (`Viewport.push_input` / `Input.parse_input_event`), so GUI, `_unhandled_input` and `InputMap` actions all behave exactly as with a physical user.

## Requirements

- Godot 4.2 or newer.
- A device token from the OmniDebugLink console (one token pair = one device seat; never share a token between two running instances — the newer connection replaces the older one).

## Install

Requires Godot 4.2+. The Godot editor has no "install from git URL" flow (unlike Unity's UPM), so:

**Option A — copy from this repository**

1. Download the repository ([Code → Download ZIP](https://github.com/omnidebuglink/omnidebuglink_godot/archive/refs/heads/main.zip)) or `git clone https://github.com/omnidebuglink/omnidebuglink_godot.git`.
2. Copy **only the `addons/omni_debug_link/` folder** into your project, so your project contains `res://addons/omni_debug_link/plugin.cfg`. Do not drop the whole repository into `addons/` — the plugin is discovered by that exact path.

**Option B — Godot Asset Library** (once listed there): AssetLib tab → search "OmniDebugLink" → Download.

Then enable it in *Project → Project Settings → Plugins → OmniDebugLink → Enable*. Enabling registers the `OmniDebugLink` autoload in your project settings automatically. If you would rather not enable the plugin, add the autoload by hand instead: *Project Settings → Autoload* → path `res://addons/omni_debug_link/runtime/omnidebug_link.gd`.

## Quick start

```gdscript
func _ready() -> void:
    OmniDebugLink.start("your-client-token")
```

That is all. The SDK keeps a WebSocket connection to the relay, announces its capabilities, and answers tasks. When you are done (or on the release build's title screen), call `OmniDebugLink.stop()`.

### API

| Member | Meaning |
|---|---|
| `OmniDebugLink.start(client_token, url := "")` | Connect to the relay (url overrides the endpoint, for self-hosting) |
| `OmniDebugLink.stop()` | Disconnect and stop all timers |
| `OmniDebugLink.actions_enabled` | Master switch for every write task; `false` = read-only observation mode (reported in hello) |
| `OmniDebugLink.connected()` / `state_changed` signal | Connection state for your own UI |
| `OmniDebugLink.log / log_warning / log_error(msg)` | Feed your own entries into `read_logs` |
| `OmniDebugLink.tasks.register(type, handler, description, payload_schema)` | Register custom tasks (see below) |
| `OmniDebugLink.tasks.unregister(type)` | Remove a task |

Recommended for shipped builds: keep the SDK disabled unless a debug flag is set, e.g.

```gdscript
if OS.get_environment("OMNIDEBUGLINK_TOKEN") != "":
    OmniDebugLink.start(OS.get_environment("OMNIDEBUGLINK_TOKEN"))
else:
    OmniDebugLink.actions_enabled = false  # or don't start() at all
```

## Built-in tasks

Read tasks:

| Task | What it does |
|---|---|
| `scene_traverse` | Flat dump of the scene tree (paths, types, scripts, displayed text, visibility; capped at 3000 nodes) |
| `screenshot` | Viewport capture as JPEG (auto-compressed to fit the frame budget) |
| `find_objects` | Search by node name (substring or regex), displayed text, or type; returns centers and `click_target` |
| `view_component` | One node in depth: properties, signal connections, groups, children |
| `get_prop` / `set_prop` | Property read/write with type coercion (arrays → Vector2/Color/…) |
| `read_logs` | Filtered query over SDK + engine logs |
| `wait_for` | Poll until a node (or property value) appears; timeouts return `found: false`, not errors |
| `get_perf` | FPS, process/physics times, draw calls, memory, video memory, custom monitors, optional frame-time percentiles |
| `get_stats` / `echo` / `ping` | Client stats and connectivity checks |

Write tasks (all gated by `actions_enabled`):

| Task | What it does |
|---|---|
| `ui_click` | Click a Control by path or displayed text, through the real GUI event pipeline |
| `tap_screen` | Tap normalized coordinates (0–1, origin **top-left**) |
| `swipe` / `long_press` | Drag with per-frame deltas / press-and-hold |
| `input_text` | Type into LineEdit/TextEdit and fire change signals |
| `send_key` | Inject key events (Escape, arrows, Enter…) through the full input pipeline |
| `send_action` | Inject an InputMap action by name |
| `set_time_scale` | Engine.time_scale / SceneTree.paused |
| `call_method` | Call any method on any node (escape hatch) |
| `change_scene` / `reload_scene` | Scene switching |
| `list_dir` / `read_file` | Read-only access under `user://` |

The AI sees this list (with per-task schemas) through the relay; you never need to configure anything server-side.

## Custom tasks

```gdscript
func _ready() -> void:
    OmniDebugLink.start("your-client-token")
    OmniDebugLink.tasks.register(
        "give_gold",
        func(payload: Dictionary) -> Dictionary:
            var amount := int(payload.get("amount", 100))
            GameState.gold += amount
            return {"gold": GameState.gold},
        "Adds gold to the player wallet.",
        {
            "type": "object",
            "properties": {"amount": {"type": "integer", "minimum": 1}},
            "required": ["amount"],
        }
    )
```

Handlers run on the main thread, may `await` (frames, timers), and return any JSON-friendly Dictionary. Signal failure by returning `OmniDebugLink.task_error("message")`. Registering or unregistering automatically re-announces capabilities — no relay-side changes.

## Logging

`OmniDebugLink.log/log_warning/log_error` always land in `read_logs`. To also capture everything the engine prints (`print`, `push_error`, engine errors), enable *Project Settings → Debug → File Logging*; the SDK tails `user://logs/godot.log` and merges it in.

## Notes

- Token discipline: one token pair per device. If the SDK reports `close 4000`, the token was claimed by another connection, it stops reconnecting and **quits the game** by design (web exports, which cannot close their own tab, show a modal alert instead).
- The whole client is main-threaded. Do not call `start()`/task handlers from threads; if you need cross-thread logging, push messages through `call_deferred`.
- C# (Godot .NET) projects can drive the GDScript autoload via `GetNode("/root/OmniDebugLink").Call("start", token)`.

> ### ⚠️ Never call `start()` unconditionally — and never embed a token in a release build
>
> `start()` opens a debug channel that can inspect and drive your game.
> **Debug builds**: start freely — gate the call behind an `OS.is_debug_build()`
> check or an environment variable.
> **Release builds**: only behind a runtime condition — a token issued by your
> own backend to an authorized account, never one baked into the binary
> ([production pattern](https://github.com/omnidebuglink/omnidebuglink/blob/main/sdk-integration.md#production--conditional-debugging))
>
> Every connection with the same token kicks the previous one offline, and
> being kicked terminates the game by design (see above). If `start()` ships
> in a release build, your players' sessions will be terminated and any loss
> that results is on you, not on OmniDebugLink.

## License

[MIT](LICENSE)
