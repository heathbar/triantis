extends RefCounted
## Braid: the little "press X" bubble drawn over things a player can use
## (airstrike pads, scripts/braid/braid_favour.gd; mounted turrets,
## scripts/braid/braid_turret.gd). Drawn in world pixels, so it's pixel art
## rather than the menus' button icons: a blue X button for controllers, an
## E key for the keyboard player.

const X_BLUE := Color(0.22, 0.47, 0.92)
const OUTLINE := Color(0.06, 0.06, 0.1)
const KEY_FACE := Color(0.88, 0.86, 0.8)
## Pixels the bubble bobs up and down, and how fast.
const BOB := 1.5
const BOB_SPEED := 5.0


## Draws the bubble on `canvas` centred on `at` (canvas-local), for the
## keyboard player if `keyboard`.
static func draw_button(canvas: CanvasItem, at: Vector2, keyboard: bool) -> void:
	at.y += roundf(sin(Time.get_ticks_msec() / 1000.0 * BOB_SPEED) * BOB)
	if keyboard:
		var r := Rect2(at - Vector2(6, 6), Vector2(12, 12))
		canvas.draw_rect(r.grow(1.0), OUTLINE)
		canvas.draw_rect(r, KEY_FACE)
		canvas.draw_rect(Rect2(r.position + Vector2(0, 10), Vector2(12, 2)), KEY_FACE.darkened(0.3))
		# A pixel "E".
		var c := OUTLINE
		canvas.draw_rect(Rect2(at + Vector2(-3, -4), Vector2(2, 7)), c)
		for y in [-4, -1, 2]:
			canvas.draw_rect(Rect2(at + Vector2(-1, y), Vector2(4 if y != -1 else 3, 1)), c)
		return
	canvas.draw_circle(at, 7.0, OUTLINE)
	canvas.draw_circle(at, 6.0, X_BLUE)
	canvas.draw_line(at + Vector2(-3, -3), at + Vector2(3, 3), Color.WHITE, 2.0)
	canvas.draw_line(at + Vector2(3, -3), at + Vector2(-3, 3), Color.WHITE, 2.0)


## A progress ring (0..1, clockwise from the top) round `at`.
static func draw_ring(canvas: CanvasItem, at: Vector2, radius: float, fraction: float,
		color := Color.WHITE, width := 2.0) -> void:
	canvas.draw_arc(at, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.55), width + 1.0)
	if fraction > 0.0:
		canvas.draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(fraction, 0.0, 1.0),
			24, color, width)
