@tool
extends Node2D
## A door in the top or bottom wall of a Braid lane (the level puts them
## there: scripts/braid/braid_level.gd). Enemies come through it: the door
## slides open onto a black void (open()), then they step out of it at
## exit_point().
## Lets enemies arrive from the sides of the lane, not only from ahead.
##
## The node sits on the wall's inner face, centred on the doorway.
##
## Art: the act's door-1.png (assets/<theme>/environment, ActTheme), drawn as
## a door in a top wall (the lane below it), DOOR_WIDTH x OUTER_WALL. Its left
## and right halves are the two leaves, which slide apart into the wall as it
## opens. An act without one gets the drawn door.

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const ActTheme := preload("res://scripts/act_theme.gd")

const FRAME := Color(0.2, 0.18, 0.22)
const SHUT := Color(0.42, 0.33, 0.24)
const SHUT_LINE := Color(0.3, 0.23, 0.16)
const DARK := Color.BLACK

## The lane it opens into.
var lane := 0
## +1: drawn opening downward (in a top wall); -1: upward. The level uses +1
## and turns the door (its rotation) to face into its lane.
var face := 1
## Progress along its lane where it is (BraidLevel.progress).
var s := 0.0

## 0 shut .. 1 wide open.
var _open := 0.0
var _warn_left := 0.0
var _tween: Tween


func _ready() -> void:
	z_index = 1


## Where enemies step out: just inside the lane.
func exit_point() -> Vector2:
	return global_position + global_transform.basis_xform(Vector2(0.0, face * BraidTuning.DOOR_EXIT_DEPTH))


## True while it's opening or open (don't pick it again yet).
func is_busy() -> bool:
	return _open > 0.0 or _warn_left > 0.0


## Opens over `warning` seconds, stays open a moment for enemies to
## come through, then shuts.
func open(warning: float) -> void:
	if _tween:
		_tween.kill()
	_warn_left = warning
	set_process(true)
	_tween = create_tween()
	_tween.tween_property(self, "_open", 1.0, warning)
	_tween.tween_interval(BraidTuning.DOOR_HOLD_OPEN)
	_tween.tween_property(self, "_open", 0.0, 0.3)


func _process(delta: float) -> void:
	_warn_left = maxf(_warn_left - delta, 0.0)
	queue_redraw()
	if _open <= 0.0 and _warn_left <= 0.0 and not (_tween and _tween.is_running()):
		set_process(false)


func _draw() -> void:
	var w := BraidTuning.DOOR_WIDTH
	var depth := BraidTuning.OUTER_WALL
	# Drawn into the wall: upward for a top door, downward for a bottom one.
	var rect := Rect2(-w / 2.0, -depth if face > 0 else 0.0, w, depth)
	var art := ActTheme.optional_environment("door")
	if art == null:
		draw_rect(rect.grow(2.0), FRAME)
	draw_rect(rect, DARK)
	# The two leaves slide apart as it opens.
	var leaf := (w / 2.0) * (1.0 - _open)
	if art != null:
		# Each leaf slides out towards its side of the doorway, its inner edge
		# showing last. (The art's halves scaled to the doorway, should it be
		# drawn at another size.)
		if leaf > 0.0:
			var art_size := art.get_size()
			var src_w := art_size.x / 2.0 * leaf / (w / 2.0)
			draw_texture_rect_region(art, Rect2(rect.position, Vector2(leaf, depth)),
				Rect2(art_size.x / 2.0 - src_w, 0.0, src_w, art_size.y))
			draw_texture_rect_region(art, Rect2(rect.end.x - leaf, rect.position.y, leaf, depth),
				Rect2(art_size.x / 2.0, 0.0, src_w, art_size.y))
	elif leaf > 0.5:
		draw_rect(Rect2(rect.position, Vector2(leaf, depth)), SHUT)
		draw_rect(Rect2(rect.end.x - leaf, rect.position.y, leaf, depth), SHUT)
		draw_line(Vector2(rect.position.x + leaf, rect.position.y),
			Vector2(rect.position.x + leaf, rect.end.y), SHUT_LINE, 1.0)
		draw_line(Vector2(rect.end.x - leaf, rect.position.y),
			Vector2(rect.end.x - leaf, rect.end.y), SHUT_LINE, 1.0)
