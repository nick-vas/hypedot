# A scene on a machine that falls behind: few drawn frames and many physics ticks, so each drawn frame runs several
# physics ticks (Godot runs up to max_physics_steps_per_frame of them to catch up). It counts the presses of "jump" that
# reach it, as a game's input handler would. Used by test/flows/lag.
extends Node

var presses := 0
var _max_fps := 0
var _ticks := 0


func _ready() -> void:
	_max_fps = Engine.max_fps
	_ticks = Engine.physics_ticks_per_second
	Engine.max_fps = 10
	Engine.physics_ticks_per_second = 240


func _exit_tree() -> void:
	Engine.max_fps = _max_fps
	Engine.physics_ticks_per_second = _ticks


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		presses += 1
