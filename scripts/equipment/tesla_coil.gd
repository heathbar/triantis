extends Deployable
## Tesla Coil: every `interval` seconds it zaps the nearest enemy within
## `range`, and the bolt jumps on up to `chains` more times, each time to the
## nearest enemy not yet hit within `chain_range` of the last. Every enemy
## the bolt touches takes `damage`, credited to the owner. Engineering raises
## the damage and the number of jumps (scripts/equipment.gd).

const COLOR := Color(0.55, 0.8, 1.0)
## How long a bolt stays on screen.
const BOLT_TIME := 0.18
const TEXTURE := preload("res://assets/weapons/equipment/tesla.png")
## Radians per second the coil art turns (clockwise).
const SPIN := 3.0
## For the time ring round it (the spinning art's corners reach ~20.4px, so
## the ring at SIZE + 3 clears them).
const SIZE := 18.0

var _cooldown := 0.0
## World positions of the last bolt's path (coil first), while it's showing.
var _bolt: PackedVector2Array = []
var _bolt_age := 0.0
var _anim := 0.0


func _tick(delta: float) -> void:
	_anim += delta
	_bolt_age += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown == 0.0:
		_zap()
	queue_redraw()


func _zap() -> void:
	var path := PackedVector2Array([global_position])
	var hit: Array[Node2D] = []
	var from := global_position
	var reach: float = stats["range"]
	for i in int(stats.get("chains", 0)) + 1:
		var next := _nearest(from, reach, hit)
		if next == null:
			break
		hit.append(next)
		path.append(next.global_position)
		from = next.global_position
		reach = stats["chain_range"]
	if hit.is_empty():
		return  # Nothing in range: stays charged.
	_cooldown = stats["interval"]
	for enemy in hit:
		if is_instance_valid(enemy):
			BossBody.deal(enemy, int(stats["damage"]), credit(), Vector2.ZERO, global_position, true)
	_bolt = path
	_bolt_age = 0.0


func _nearest(from: Vector2, reach: float, exclude: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in enemies_within(from, reach):
		if enemy in exclude:
			continue
		var d := from.distance_squared_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _draw() -> void:
	var range_color := COLOR
	range_color.a = 0.15
	draw_arc(Vector2.ZERO, stats.get("range", 0.0), 0.0, TAU, 64, range_color, 1.0)
	# The coil, spinning, its core flickering.
	var glow := 0.85 + 0.15 * sin(_anim * 12.0)
	draw_set_transform(Vector2.ZERO, _anim * SPIN)
	draw_centered(TEXTURE, Vector2.ZERO, Color(glow, glow, glow))
	draw_set_transform(Vector2.ZERO, 0.0)
	draw_time_ring(SIZE + 3.0, Color(1, 1, 1, 0.5), 1.0)
	draw_pack_up_hint()
	# The last bolt: a jagged line through everything it hit, fading out.
	if _bolt.size() >= 2 and _bolt_age < BOLT_TIME:
		var fade := 1.0 - _bolt_age / BOLT_TIME
		for i in _bolt.size() - 1:
			var points := _jagged(to_local(_bolt[i]), to_local(_bolt[i + 1]))
			draw_polyline(points, Color(COLOR, fade), 3.0)
			draw_polyline(points, Color(1, 1, 1, fade), 1.0)


func _jagged(a: Vector2, b: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([a])
	var side := (b - a).orthogonal().normalized()
	var steps := 6
	for i in range(1, steps):
		points.append(a.lerp(b, i / float(steps)) + side * randf_range(-5.0, 5.0))
	points.append(b)
	return points

