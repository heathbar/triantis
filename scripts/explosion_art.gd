extends RefCounted
## The explosion art (assets/misc/explosion-1..6.png, 176 px frames): a flash,
## a fireball swelling, then smoke breaking up. draw() paints it onto any
## CanvasItem at a given age, so effects with their own node (blast.gd) and
## boss hazards drawn from the boss's clock (shells, mortars) show the same
## thing.

const FRAMES: Array[Texture2D] = [
	preload("res://assets/misc/explosion-1.png"),
	preload("res://assets/misc/explosion-2.png"),
	preload("res://assets/misc/explosion-3.png"),
	preload("res://assets/misc/explosion-4.png"),
	preload("res://assets/misc/explosion-5.png"),
	preload("res://assets/misc/explosion-6.png"),
]
## Seconds each frame shows: quick to the fireball, slower through the smoke.
const FRAME_TIMES: Array[float] = [0.06, 0.07, 0.1, 0.1, 0.12, 0.15]
const DURATION := 0.6
## How wide the fireball is at its biggest (frames 3-4), drawn 1:1: draw()
## scales the art so that's 2 x the radius it's given.
const SIZE := 150.0


## The frame showing `t` seconds in (-1 before it starts or once it's over).
static func frame_at(t: float) -> int:
	if t < 0.0:
		return -1
	var end := 0.0
	for i in FRAME_TIMES.size():
		end += FRAME_TIMES[i]
		if t < end:
			return i
	return -1


## Paints the explosion on `c`, centred on `at` (c's coordinates), `t` seconds
## after it went off, sized so its fireball is `radius` across at its
## biggest. Nothing before it starts or once it's over.
static func draw(c: CanvasItem, at: Vector2, t: float, radius: float, modulate := Color.WHITE) -> void:
	var i := frame_at(t)
	if i < 0:
		return
	var tex := FRAMES[i]
	var k := radius * 2.0 / SIZE
	c.draw_set_transform(at, 0.0, Vector2(k, k))
	c.draw_texture(tex, -(tex.get_size() / 2.0).floor(), modulate)
	c.draw_set_transform(Vector2.ZERO)
