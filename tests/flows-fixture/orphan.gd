# A screen that makes a control and never adds it to the tree or frees it, as a settings screen once did: Godot reports the
# leak only when it exits, after every flow has ended. Used by test/flows/exitleak.
extends Node

var _orphan: Label


func _ready() -> void:
	_orphan = Label.new()
	_orphan.text = "never added"
