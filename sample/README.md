# OmniDebugLink Godot Sample

A tiny two-scene game (main menu → item-collecting screen) demonstrating the [OmniDebugLink Godot SDK](../). It is intentionally plain GDScript + Control nodes, so you can see the minimum needed to make a game remotely debuggable and AI-drivable.

> `addons/omni_debug_link/` here is a verbatim copy of the SDK. When you update the SDK in your own project, re-copy it — this sample does not reference the parent directory.

## Run it

1. Open this folder in Godot 4.2+.
2. Give the sample a device token, one of:
   - set the `ODL_TOKEN` environment variable to your client token (from the OmniDebugLink console / `device_detail`), or
   - create `odl_token.txt` containing the token next to the game's `user://` data:
     - Windows: `%APPDATA%\Godot\app_userdata\OmniDebugLink Godot Sample\odl_token.txt`
     - Linux/macOS: `~/.local/share/godot/app_userdata/OmniDebugLink Godot Sample/odl_token.txt` (`~/Library/Application Support/Godot/app_userdata/...` on macOS)
3. Press F5. The bottom label should read `OmniDebugLink: connected`.

One token pair = one device seat. Do not share a token between two running instances (the newer connection replaces the older one, and the SDK stops reconnecting with close code 4000 by design).

## What an AI tool can do with it

Once connected, any MCP client logged into the same OmniDebugLink account can:

```
scene_traverse  → see /root/MainMenu, its buttons and the connection label
ui_click {"text": "Start Game"}  → real GUI click, switches to the game scene
input_text {"path": "/root/MainMenu/NameInput", "text": "Ada"}  → type a name
send_action {"action": "move_right"}  → move the blue player square (WASD/arrows too)
swipe  → the player square is draggable: swipe from its center and its position changes
long_press {"path": "/root/Game/CollectButton", "hold_ms": 600}  → holding Collect Item adds +1 per 0.25s
read_logs  → everything logged via OmniDebugLink.log()
screenshot  → see the 800x600 window
```

All input tasks inject real engine input events at screen coordinates — the controls react exactly as they would for a human (nothing calls button signals directly).

## Export from the command line (no editor GUI)

The bundled `export_presets.cfg` defines a Windows Desktop preset (with an embedded .pck) and a Web preset. With export templates installed for your Godot version:

```bash
godot --headless --path sample --export-release "Windows Desktop"
godot --headless --path sample --export-release "Web"
```

Outputs land in `build/windows/` and `build/web/`. Cross-exporting works everywhere: a Linux machine happily produces the Windows build — the export templates ship a prebuilt Windows runtime, no cross toolchain involved. (`build/` contains a `.gdignore` file so the editor does not try to import the exported PNGs as project resources — recreate it if you delete the folder.)

For the exported Windows exe, use the `odl_token.txt` variant (double-clicked exes have no environment variables).

## License

MIT, same as the SDK.
