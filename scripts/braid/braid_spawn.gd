@tool
extends Node2D
## A spawn vent in a Braid level piece: enemies can come out here once the
## squad is close (scripts/braid/braid_game.gd picks which). Invisible in
## game; the editor draws a grate and a marker so level pieces can place it.
##
## Place it in open floor, to the side of the main path.

const GRATE := Color(0.08, 0.08, 0.1, 0.85)
const BARS := Color(0.35, 0.35, 0.4, 0.9)
const EDITOR_MARK := Color(1.0, 0.3, 0.8)


func _ready() -> void:
	z_index = -10


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(-7, -5, 14, 10), GRATE)
	for i in 4:
		draw_rect(Rect2(-5 + i * 3, -4, 1, 8), BARS)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 16, EDITOR_MARK, 1.0)
