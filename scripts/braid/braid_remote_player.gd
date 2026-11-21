extends "res://scripts/net/remote_player.gd"
## Another squad's player in a Braid game (scripts/braid/braid_link.gd moves
## it). Unlike the arena's version it's shown wherever it is (all squads share
## one world: we see them through windows and in junctions), and our enemies
## only chase it inside a junction room (`chase_rects`): elsewhere each squad's
## enemies are after that squad alone.

## Junction rooms (world rects) where our enemies may go after it.
var chase_rects: Array[Rect2] = []


func _physics_process(delta: float) -> void:
	position = _follow.step(position, delta)
	visible = true
	var chaseable := _alive and chase_rects.any(func(r: Rect2) -> bool: return r.has_point(position))
	if chaseable != is_in_group("remote_players"):
		if chaseable:
			add_to_group("remote_players")
		else:
			remove_from_group("remote_players")
