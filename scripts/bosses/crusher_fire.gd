extends RefCounted
## The Crusher's fire (scripts/bosses/crusher.gd): it leaves a strip of fire
## down the middle of every charge, and a ring of fire where it did donuts.
## None while it has more than FIRE_FROM of its health; below LONG_BURN_BELOW
## it burns LONG_BURN_MULT times as long (see burn_time).
## Fire burns for BURN_TIME (ENRAGED_BURN_TIME enraged), costing anyone
## standing in it DAMAGE (half a heart; the player's hit cooldown makes that
## half a heart a second), then leaves a scorch mark fading over SCORCH_TIME.
## It doesn't hurt enemies.
##
## The strip is HALF_WIDTH x 2 wide, narrower than the truck, so a player who
## sidestepped a charge isn't standing in it.
##
## Fire is boss hazards (Boss.emit_hazard), so in a squads game the host lays
## it and every copy burns its own players:
##   TRAIL: a straight stretch of road, "pos" to "pos" + "d", one every STEP
##     pixels driven (fewer hazards to send than one per flame).
##   RING: round "pos" at radius "r", catching all the way round over
##     RING_LIGHT seconds (one turn of the spin).
## Both burn until "out", then scorch until their "end".
##
## Art: assets/misc/fire-trail-1..6.png (12x23 frames, the flame standing on
## the bottom row, played at FPS, each flame starting on its own frame) and
## assets/misc/fire-scorch.png (16x5, under each flame and left behind).

const TRAIL := "fire"
const RING := "fire_ring"

## Half the strip's width (pixels).
const HALF_WIDTH := 8.0
## Pixels of road per TRAIL hazard, and between flames drawn along it.
const STEP := 32.0
const SPACING := 12.0
## How far behind the truck's centre the fire starts (its rear axle).
const REAR := 27.0
const BURN_TIME := 5.0
const ENRAGED_BURN_TIME := 8.0
const DAMAGE := 1
## Seconds a flame takes to grow in, and to die down before going out.
const GROW := 0.15
const SHRINK := 0.5
const SCORCH_TIME := 8.0
const RING_RADIUS := 35.0
const RING_LIGHT := 0.7
## Health (fraction of its max) above which it lays no fire, and below which
## fire burns LONG_BURN_MULT times as long.
const FIRE_FROM := 0.75
const LONG_BURN_BELOW := 0.4
const LONG_BURN_MULT := 5.0

const FRAMES: Array[Texture2D] = [
	preload("res://assets/misc/fire-trail-1.png"),
	preload("res://assets/misc/fire-trail-2.png"),
	preload("res://assets/misc/fire-trail-3.png"),
	preload("res://assets/misc/fire-trail-4.png"),
	preload("res://assets/misc/fire-trail-5.png"),
	preload("res://assets/misc/fire-trail-6.png"),
]
const SCORCH_TEXTURE := preload("res://assets/misc/fire-scorch.png")
const FPS := 10.0

## Host: where the stretch of road being laid started, or null.
var _from: Variant = null


## Seconds new fire burns, with the truck at `health` (fraction of its max):
## 0 (no fire) above FIRE_FROM.
static func burn_time(health: float, enraged: bool) -> float:
	if health > FIRE_FROM:
		return 0.0
	var seconds := ENRAGED_BURN_TIME if enraged else BURN_TIME
	return seconds * LONG_BURN_MULT if health < LONG_BURN_BELOW else seconds


## Host, every frame: lays fire behind the truck while `burning` (it's
## charging fast); `rear` is where the fire starts.
func lay(boss: Boss, burning: bool, rear: Vector2, seconds: float) -> void:
	if burning:
		if _from == null:
			_from = rear
		elif rear.distance_to(_from) >= STEP:
			_emit_trail(boss, _from, rear, seconds)
			_from = rear
	elif _from != null:
		if rear.distance_to(_from) >= 4.0:
			_emit_trail(boss, _from, rear, seconds)
		_from = null


static func _emit_trail(boss: Boss, from: Vector2, to: Vector2, seconds: float) -> void:
	var out := boss.elapsed + seconds
	boss.emit_hazard(TRAIL, from, out + SCORCH_TIME, {"d": to - from, "out": out})


## Host: a ring of fire round `centre`, lit as donuts start, burning until
## `seconds` after they end at `donut_end`.
static func ring(boss: Boss, centre: Vector2, donut_end: float, seconds: float) -> void:
	var out := donut_end + seconds
	boss.emit_hazard(RING, centre, out + SCORCH_TIME, {"r": RING_RADIUS, "out": out})


## Plays out hazard `h` if it's fire (true), else leaves it to the boss.
static func hazard_tick(boss: Boss, h: Dictionary) -> bool:
	var kind: String = h["kind"]
	if kind != TRAIL and kind != RING:
		return false
	var now := boss.elapsed
	# Burning: once lit, until it has mostly died down.
	if now >= float(h["out"]) - SHRINK * 0.5:
		return true
	var reach := HALF_WIDTH + Boss.PLAYER_HALF * 0.5
	var at: Vector2 = h["pos"]
	if kind == TRAIL:
		var to: Vector2 = at + h["d"]
		boss.hurt_players(func(p: Vector2) -> bool:
			return p.distance_to(Geometry2D.get_closest_point_to_segment(p, at, to)) <= reach,
			DAMAGE)
	elif now >= float(h["born"]) + RING_LIGHT:
		var r := float(h["r"])
		boss.hurt_players(func(p: Vector2) -> bool:
			return absf(p.distance_to(at) - r) <= reach, DAMAGE)
	return true


## Draws hazard `h` if it's fire (true), else leaves it to the boss.
static func draw(boss: Boss, h: Dictionary) -> bool:
	var kind: String = h["kind"]
	if kind != TRAIL and kind != RING:
		return false
	var now := boss.elapsed
	var out := float(h["out"])
	var born := float(h["born"])
	var spots := _flame_spots(h, now)
	# Scorch under each flame once it's lit, fading after the fire's out.
	var scorch := 1.0 - clampf((now - out) / SCORCH_TIME, 0.0, 1.0)
	var half_scorch := (SCORCH_TEXTURE.get_size() / 2.0).floor()
	for f: Array in spots:
		if now >= float(f[2]):
			boss.draw_texture(SCORCH_TEXTURE, f[0] - half_scorch, Color(1, 1, 1, scorch))
	if now >= out:
		return true
	var size := minf(clampf((now - born) / GROW, 0.0, 1.0), clampf((out - now) / SHRINK, 0.0, 1.0))
	for f: Array in spots:
		var s: float = size * clampf((now - float(f[2])) / GROW, 0.0, 1.0)
		if s > 0.05:
			_draw_flame(boss, f[0], s, now, f[1])
	return true


## [[base, phase, lit at], ...] for each flame of hazard `h`, back to front
## (so lower flames overlap higher ones).
static func _flame_spots(h: Dictionary, _now: float) -> Array:
	var spots := []
	var at: Vector2 = h["pos"]
	var id := int(h["id"])
	var born := float(h["born"])
	if h["kind"] == TRAIL:
		var d: Vector2 = h["d"]
		var n := maxi(int(d.length() / SPACING), 1)
		for i in n:
			spots.append([(at + d * (i + 0.5) / n).round(), _phase(id, i), born])
	else:
		var r := float(h["r"])
		var n := maxi(roundi(TAU * r / SPACING), 6)
		var start := _phase(id, 99) * TAU
		for i in n:
			var a := start + i * TAU / n
			spots.append([(at + Vector2.from_angle(a) * r).round(), _phase(id, i),
				born + RING_LIGHT * i / n])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	return spots


## A steady 0..1 per flame, so each flickers out of step with its neighbours.
static func _phase(id: int, i: int) -> float:
	return fposmod(sin(id * 12.9898 + i * 78.233) * 43758.5453, 1.0)


## One flame standing on `base`, at size `s` (0..1, growing from its base).
static func _draw_flame(c: CanvasItem, base: Vector2, s: float, now: float, phase: float) -> void:
	var tex: Texture2D = FRAMES[int(now * FPS + phase * FRAMES.size()) % FRAMES.size()]
	c.draw_set_transform(base, 0.0, Vector2(s, s))
	c.draw_texture(tex, Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height()))
	c.draw_set_transform(Vector2.ZERO)
