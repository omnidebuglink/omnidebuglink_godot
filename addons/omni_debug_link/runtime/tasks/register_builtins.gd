extends RefCounted
## Registers every builtin task into the autoload's registry.
## (Task modules are instantiable RefCounteds, not pure statics, because their
## handlers are bound via Callable(self, ...) — GDScript <4.3 forbids `self`
## inside static functions.)

const Basics := preload("./basics.gd")
const SceneTasks := preload("./scene.gd")
const ScreenshotTask := preload("./screenshot.gd")
const LogsTask := preload("./logs_task.gd")
const PerfTask := preload("./perf.gd")
const InputTasks := preload("./input_tasks.gd")
const PropTasks := preload("./prop_tasks.gd")
const AdvancedTasks := preload("./advanced.gd")
const FileTasks := preload("./files.gd")


## Creates the module instances, registers their tasks and returns the
## instances — the caller MUST keep them (Callables do not keep RefCounted
## receivers alive in Godot 4.2, so the instances double as the handlers'
## lifeline).
static func register_all(odl: Node, reg) -> Array:
	var modules: Array = []
	for script in [Basics, SceneTasks, ScreenshotTask, LogsTask, PerfTask, InputTasks, PropTasks, AdvancedTasks, FileTasks]:
		var module = script.new()
		modules.append(module)
		module.register(odl, reg)
	return modules
