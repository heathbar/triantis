extends RefCounted
## The explosion art: a flash, a fireball swelling, then smoke breaking up.
## Two sets with the same six-frame timing: the big one
## (assets/misc/explosion-1..6.png, 176 px frames) and a small one
## (assets/misc/small-explosion-1..6.png, 48 px frames) for blasts of
## SMALL_MAX_RADIUS or less: draw() picks by the radius it's given. draw()
## paints it onto any CanvasItem at a given age, so effects with their own
## node (blast.gd) and boss hazards drawn from the boss's clock (shells,
## mortars) show the same thing.
##
## Small blasts also have a sound (play_small_sound), played where each one
## goes off; the big ones' sounds are their owners' (bomber.gd...).

const FRAMES: Array[Texture2D] = [
	preload("res://assets/misc/explosion-1.png"),
	preload("res://assets/misc/explosion-2.png"),
	preload("res://assets/misc/explosion-3.png"),
	preload("res://assets/misc/explosion-4.png"),
	preload("res://assets/misc/explosion-5.png"),
	preload("res://assets/misc/explosion-6.png"),
]
const SMALL_FRAMES: Array[Texture2D] = [
	preload("res://assets/misc/small-explosion-1.png"),
	preload("res://assets/misc/small-explosion-2.png"),
	preload("res://assets/misc/small-explosion-3.png"),
	preload("res://assets/misc/small-explosion-4.png"),
	preload("res://assets/misc/small-explosion-5.png"),
	preload("res://assets/misc/small-explosion-6.png"),
]
## Seconds each frame shows: quick to the fireball, slower through the smoke.
const FRAME_TIMES: Array[float] = [0.06, 0.07, 0.1, 0.1, 0.12, 0.15]
const DURATION := 0.6
## How wide the fireball is at its biggest (frames 3-4), drawn 1:1: draw()
## scales the art so that's 2 x the radius it's given.
const SIZE := 150.0
const SMALL_SIZE := 42.0
## Blasts this radius (world px) or smaller use the small art and sound:
## Class Mod grenades, rivet mortars and the like, Cluster Grenade bomblets,
## boss shells and mortars.
const SMALL_MAX_RADIUS := 36.0

const SMALL_SOUND := preload("res://assets/misc/small-explosion-1.ogg")
## Quieter than the bomber's blast (0.35): the clip is louder, and small
## blasts come often.
const SMALL_VOLUME := 0.2
## Small blasts closer together than this (seconds) share one sound, so a
## burst of bomblets doesn't stack up into a roar.
const SMALL_SOUND_GAP := 0.06

static var _last_small_sound_ms := -1000000


## True if a blast of `radius` uses the small art and sound.
static func is_small(radius: float) -> bool:
	return radius <= SMALL_MAX_RADIUS


## Plays the small blast sound (at most once every SMALL_SOUND_GAP s).
static func play_small_sound() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_small_sound_ms < int(SMALL_SOUND_GAP * 1000.0):
		return
	_last_small_sound_ms = now
	Global.play_sfx(SMALL_SOUND, SMALL_VOLUME)


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
## biggest (the small art if that's SMALL_MAX_RADIUS or less). Nothing before
## it starts or once it's over.
static func draw(c: CanvasItem, at: Vector2, t: float, radius: float, modulate := Color.WHITE) -> void:
	var i := frame_at(t)
	if i < 0:
		return
	var small := is_small(radius)
	var tex := SMALL_FRAMES[i] if small else FRAMES[i]
	var k := radius * 2.0 / (SMALL_SIZE if small else SIZE)
	c.draw_set_transform(at, 0.0, Vector2(k, k))
	c.draw_texture(tex, -(tex.get_size() / 2.0).floor(), modulate)
	c.draw_set_transform(Vector2.ZERO)
