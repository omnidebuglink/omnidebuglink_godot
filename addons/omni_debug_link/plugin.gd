@tool
extends EditorPlugin


func _enter_tree() -> void:
	# The runtime is a plain autoload; enabling the plugin registers it so
	# projects get OmniDebugLink.* without touching Project Settings by hand.
	add_autoload_singleton("OmniDebugLink", "res://addons/omni_debug_link/runtime/omnidebug_link.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("OmniDebugLink")
