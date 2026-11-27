extends RefCounted
## The Vault's lasers (scripts/bosses/vault.gd).
##
## The corridor (its keypad stage): two static beams CORRIDOR_WIDTH apart,
## running straight out from the keypad in the Vault's wall for a random
## CORRIDOR_REACH (from the wall), with the keypad's standing spot between
## them at the wall end. Players can only reach the keypad down the corridor,
## from its far end; at the keypad itself they're well clear of both beams. It's on while our keypad
## is waiting for its code, and off during a burn window. Every squad's copy
## runs its own round its own keypad, hurting only its own players, so none
## of it goes over the network.
##
## Sweep lines (walking): the host's "sweep" hazards, drawn and played out
## by the vault; the helpers for them are here. Each is a line right across
## the map (horizontal, vertical or diagonal), a pale flashing red for its
## warning, then a solid deep red and burning.
##
## A live beam takes DAMAGE from a player touching it (the usual hit
## cooldown applies, so standing in one keeps hurting), with the fence
## buzzer (vault.laser_hurt).

## The corridor: beams this far apart, reaching a random distance in this
## range out from the wall (px).
const CORRIDOR_WIDTH := 64.0
const CORRIDOR_REACH := Vector2(160.0, 256.0)
## Half hearts a live beam takes, and how close (player's centre to the beam)
## counts as touching.
const DAMAGE := 1
const TOUCH := 8.0
## A warning flashes this many times a second, rising to WARN_FLASH_END
## as it gets close to going live.
const WARN_FLASH := 6.0
const WARN_FLASH_END := 10.0

## A live beam is a fully saturated red with a wide red glow; a warning is
## a paler red, so the two are easy to tell apart.
const BEAM := Color(1.0, 0.0, 0.0)
const BEAM_GLOW := Color(1.0, 0.0, 0.0, 0.45)
const WARN := Color(1.0, 0.45, 0.45)
const POST := Color(0.25, 0.27, 0.3)
const POST_DARK := Color(0.12, 0.13, 0.15)

## The Vault (scripts/bosses/vault.gd).
var vault: Node2D
## The corridor's beams, each [from, to] (our coordinates).
var beams: Array = []
var active := false


func _init(owner_vault: Node2D) -> void:
	vault = owner_vault


## A new corridor for the keypad standing at `keypad`, `back` px out from
## the wall along `out` (the wall side's outward direction), kept on `map`.
func build(keypad: Vector2, out: Vector2, map: Rect2, back := 0.0) -> void:
	var side := out.orthogonal()
	var wall := keypad - out * back
	var reach := randf_range(CORRIDOR_REACH.x, CORRIDOR_REACH.y)
	beams.clear()
	for s in [-1.0, 1.0]:
		var start: Vector2 = wall + side * s * CORRIDOR_WIDTH / 2.0
		beams.append([start.clamp(map.position, map.end),
			(start + out * reach).clamp(map.position, map.end)])


func clear() -> void:
	beams.clear()
	active = false


func set_active(on: bool) -> void:
	active = on and not beams.is_empty()


func tick() -> void:
	if not active:
		return
	vault.laser_hurt(func(p: Vector2) -> bool:
		for beam: Array in beams:
			if touches(beam[0], beam[1], p):
				return true
		return false)


## Whether a player at `pos` is touching the beam from `a` to `b`.
static func touches(a: Vector2, b: Vector2, pos: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos) <= TOUCH


## The line through `through` at `angle`, clipped to `rect`: [from, to], or
## empty if it misses the rect.
static func line_across(through: Vector2, angle: float, rect: Rect2) -> PackedVector2Array:
	var dir := Vector2.from_angle(angle)
	var t0 := -INF
	var t1 := INF
	for axis in 2:
		var d := dir[axis]
		var lo := rect.position[axis] - through[axis]
		var hi := rect.end[axis] - through[axis]
		if absf(d) < 0.0001:
			if lo > 0.0 or hi < 0.0:
				return PackedVector2Array()
			continue
		t0 = maxf(t0, minf(lo / d, hi / d))
		t1 = minf(t1, maxf(lo / d, hi / d))
	if t0 > t1:
		return PackedVector2Array()
	return PackedVector2Array([through + dir * t0, through + dir * t1])


## Draws the corridor on `c` (the Vault's canvas).
func draw(c: CanvasItem, now: float) -> void:
	if not active:
		return
	for beam: Array in beams:
		draw_beam(c, beam[0], beam[1], now)
		for end: Vector2 in beam:
			var box := Rect2(end - Vector2(3, 3), Vector2(6, 6))
			c.draw_rect(box, POST)
			c.draw_rect(box, POST_DARK, false, 1.0)
			c.draw_circle(end, 1.5, BEAM)


## A live beam: a flickering glow and a bright core, `width` px wide.
static func draw_beam(c: CanvasItem, a: Vector2, b: Vector2, now: float, width := 1.0) -> void:
	var glow := Color(BEAM_GLOW, BEAM_GLOW.a + 0.1 * sin(now * 20.0))
	c.draw_line(a, b, glow, width + 4.0)
	c.draw_line(a, b, BEAM, width)


## A beam's warning, `k` (0..1) of the way to going live: a pale red line
## flashing hard on and off the whole time, quicker as it gets close.
## `_left` (seconds till live) is unused since the flash runs throughout.
static func draw_warning(c: CanvasItem, a: Vector2, b: Vector2, k: float, _left: float,
		now: float) -> void:
	var rate := lerpf(WARN_FLASH, WARN_FLASH_END, k)
	var lit := fposmod(now * rate, 1.0) < 0.5
	c.draw_line(a, b, Color(WARN, 0.25 if lit else 0.08), 3.0)
	c.draw_line(a, b, Color(WARN, 0.9 if lit else 0.25), 1.0)
