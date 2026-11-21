@tool
extends Node2D
## A favour plate, beside a window (scripts/braid/braid_level.gd puts one on
## each side): stand on it for FAVOUR_HOLD seconds and a crusher drops on the
## neighbouring lane across the window (crush_rect), hurting the enemies of
## whichever squad is there. Then it recharges (FAVOUR_RECHARGE seconds) and
## can be used again; a player has to step off and back on to drop another.
##
## The plate only notices our own players (group "players"); braid_game.gd
## connects `triggered`, tells the other squad's game, and shows the crusher.

## Pressed long enough.
signal triggered(plate: Node2D)

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")

const RADIUS := 12.0
const IDLE := Color(0.95, 0.75, 0.3)
const DONE := Color(0.4, 0.38, 0.35)

## The lane it's in, and the lane it drops the crusher on.
var lane := 0
var target_lane := 1
## Progress along the lanes where it is (BraidLevel.progress), and the world y
## of the middle of the target lane there (set by the level).
var s := 0.0
var crush_y := 0.0
## Recharging after a drop.
var used := false
## Seconds until it's ready again.
var _recharge := 0.0
## Someone stayed on it since the last drop: they must step off first.
var _needs_release := false
var _held := 0.0


func _ready() -> void:
	z_index = -9
	set_physics_process(not Engine.is_editor_hint())


func _physics_process(delta: float) -> void:
	var on := false
	for p: Node2D in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(global_position) <= RADIUS + 10.0:
			on = true
			break
	if not on:
		_needs_release = false
	if used:
		_recharge = maxf(_recharge - delta, 0.0)
		queue_redraw()
		if _recharge > 0.0:
			return
		used = false
	if _needs_release:
		return
	var before := _held
	_held = clampf(_held + (delta if on else -delta * 2.0), 0.0, BraidTuning.FAVOUR_HOLD)
	if _held != before:
		queue_redraw()
	if _held >= BraidTuning.FAVOUR_HOLD:
		used = true
		_held = 0.0
		_recharge = BraidTuning.FAVOUR_RECHARGE
		_needs_release = true
		queue_redraw()
		triggered.emit(self)


## Where the crusher lands: across the window, in the target lane.
func crush_rect() -> Rect2:
	var size := BraidTuning.FAVOUR_CRUSH_SIZE
	return Rect2(Vector2(position.x - size.x / 2.0, crush_y - size.y / 2.0), size)


func _draw() -> void:
	var c := DONE if used else IDLE
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.5))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, c, 2.0)
	# An arrow pointing across the window.
	var dir := 1.0 if target_lane > lane else -1.0
	draw_line(Vector2(0, -5 * dir), Vector2(0, 5 * dir), c, 2.0)
	draw_line(Vector2(0, 5 * dir), Vector2(-4, 1 * dir), c, 2.0)
	draw_line(Vector2(0, 5 * dir), Vector2(4, 1 * dir), c, 2.0)
	if used:
		# Recharging: a ring filling back up.
		var filled := 1.0 - _recharge / BraidTuning.FAVOUR_RECHARGE
		draw_arc(Vector2.ZERO, RADIUS + 3.0, -PI / 2.0, -PI / 2.0 + TAU * filled, 20, IDLE.darkened(0.3), 1.0)
	elif _held > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + 3.0, -PI / 2.0, -PI / 2.0 + TAU * _held / BraidTuning.FAVOUR_HOLD,
			20, Color.WHITE, 2.0)


## A crusher slamming down on `rect` (world), drawn under `parent`: a block
## that drops in and fades. Just for show.
static func show_crush(parent: Node, rect: Rect2) -> void:
	var crush := Crush.new()
	crush.rect = rect
	crush.position = rect.position
	parent.add_child(crush)


class Crush extends Node2D:
	var rect := Rect2()
	var t := 0.0

	func _ready() -> void:
		z_index = 40

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
		if t > 0.9:
			queue_free()

	func _draw() -> void:
		var fall := clampf(t / 0.15, 0.0, 1.0)
		var fade := 1.0 - clampf((t - 0.3) / 0.6, 0.0, 1.0)
		var r := Rect2(Vector2(0, -rect.size.y * (1.0 - fall)), rect.size)
		draw_rect(r, Color(0.35, 0.33, 0.38, 0.9 * fade))
		draw_rect(r, Color(0.1, 0.1, 0.12, fade), false, 2.0)
		if fall >= 1.0:
			draw_rect(Rect2(Vector2(-8, rect.size.y - 6), Vector2(rect.size.x + 16, 10)),
				Color(0.8, 0.75, 0.6, 0.6 * fade))
