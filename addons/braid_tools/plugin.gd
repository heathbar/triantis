@tool
extends EditorPlugin
## Adds the Braid dock (braid_dock.gd). Turn it on in
## Project > Project Settings > Plugins.

const BraidDock := preload("res://addons/braid_tools/braid_dock.gd")

var _dock: EditorDock


func _enter_tree() -> void:
	_dock = BraidDock.new()
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
