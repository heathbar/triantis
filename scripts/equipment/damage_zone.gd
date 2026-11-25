extends Deployable
## A patch of ground that hurts enemies standing in it, every `tick` seconds.
## Used by two items (scripts/equipment.gd):
##   Spike Trap    - a square `size` pixels across: steady damage each tick,
##                   and enemies on it move at `slow` x their speed.
##   Corrosive Goo - wider, starts weak but each tick an enemy stays in it
##                   does `ramp` more damage to it (it builds back up from
##                   nothing if the enemy leaves).

const SPIKE_COLOR := Color(0.75, 0.75, 0.8)
const GOO_COLOR := Color(0.45, 0.9, 0.15)
## The hazard sign in the middle of the goo.
const GOO_TEXTURE := preload("res://assets/weapons/equipment/corrosive.png")
## Seconds an enemy stays slowed after stepping off the spikes.
const SLOW_LINGER := 0.25

var _tick_timer := 0.0
## Enemy instance id -> ticks it's spent inside in a row (goo).
var _exposure := {}
var _anim := 0.0
## Goo: bubble positions (unit disc) and phases, for the look.
var _bubbles := []


func _ready() -> void:
	super()
	for i in 9:
		_bubbles.append([Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 0.8, randf() * TAU])


func _tick(delta: float) -> void:
	_anim += delta
	if stats.has("slow"):
		for enemy in _enemies_inside():
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(stats["slow"], SLOW_LINGER)
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = stats["tick"]
		_hurt()
	queue_redraw()


func _hurt() -> void:
	var ramp := int(stats.get("ramp", 0))
	var still_inside := {}
	for enemy in _enemies_inside():
		var id := enemy.get_instance_id()
		var ticks: int = _exposure.get(id, 0)
		still_inside[id] = ticks + 1
		BossBody.deal(enemy, int(stats["damage"]) + ramp * ticks, credit(), Vector2.ZERO,
			global_position, true)
	_exposure = still_inside


## Enemies touching the zone: the square (spikes) or the circle (goo).
func _enemies_inside() -> Array[Node2D]:
	if not stats.has("size"):
		return enemies_within(global_position, stats["radius"])
	var half: float = stats["size"] / 2.0
	var found: Array[Node2D] = []
	for enemy in enemies_within(global_position, INF):
		var reach := half + half_extent(enemy)
		var offset := enemy.global_position - global_position
		if absf(offset.x) <= reach and absf(offset.y) <= reach:
			found.append(enemy)
	return found


func _draw() -> void:
	if kind == "corrosive_goo":
		_draw_goo(stats.get("radius", 0.0))
	else:
		_draw_spikes(stats.get("size", 0.0) / 2.0)


func _draw_spikes(half: float) -> void:
	var square := Rect2(-half, -half, half * 2.0, half * 2.0)
	draw_rect(square, Color(0.2, 0.18, 0.15, 0.55))
	draw_rect(square, Color(0.1, 0.1, 0.1, 0.8), false, 1.0)
	# A grid of little spikes, every other row shifted half a step.
	var count := maxi(int(half * 2.0 / 14.0), 1)
	var step := half * 2.0 / count
	for row in count:
		for col in count:
			var at := Vector2(-half + (col + 0.5) * step, -half + (row + 0.5) * step)
			if row % 2 == 1:
				at.x += step / 4.0
			else:
				at.x -= step / 4.0
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(-3, 2), at + Vector2(3, 2), at + Vector2(0, -4),
			]), SPIKE_COLOR)
	draw_time_ring(half * sqrt(2.0) + 2.0, Color(1, 1, 1, 0.5), 1.0)


func _draw_goo(radius: float) -> void:
	var color := GOO_COLOR
	color.a = 0.35
	draw_circle(Vector2.ZERO, radius, color)
	color.a = 0.25
	draw_circle(Vector2(radius * 0.2, -radius * 0.15), radius * 0.6, color)
	for b in _bubbles:
		var size := 2.0 + 1.6 * sin(_anim * 3.0 + b[1])
		var bubble := GOO_COLOR.lightened(0.3)
		bubble.a = 0.6
		draw_circle(b[0] * radius, maxf(size, 1.0), bubble)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.25, 0.6, 0.05, 0.8), 1.0)
	draw_centered(GOO_TEXTURE)
	draw_time_ring(radius + 2.0, Color(1, 1, 1, 0.5), 1.0)

