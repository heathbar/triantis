extends Deployable
## Cluster Grenade: thrown `throw` pixels the way the player faces. Where it
## lands it explodes (`radius`, `damage`), scattering `bomblets` that each go
## off a moment later in smaller blasts nearby (half the radius and damage).
## Engineering raises the radius and damage (scripts/equipment.gd).

## Seconds in the air.
const FLIGHT_TIME := 0.45
## How high it arcs (drawn only).
const ARC_HEIGHT := 28.0
## Bomblets land up to this x radius from where the grenade burst.
const SCATTER := 1.4
## Seconds after the burst before the bomblets go off (each picks a time in
## this range).
const BOMBLET_DELAY := Vector2(0.3, 0.6)
const BOMBLET_SCALE := 0.5

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _flight := 0.0
var _landed := false
## Each bomblet still to go off: [world position, seconds left].
var _bomblets := []


func _ready() -> void:
	super()
	z_index = 15  # Over everything while it flies.
	_from = global_position
	var facing := Vector2.RIGHT
	var bounds := Rect2()
	if is_instance_valid(owner_player):
		facing = Vector2.from_angle(owner_player.body.rotation)
		bounds = owner_player.move_bounds
	_to = _from + facing * stats.get("throw", 140.0)
	if bounds.has_area():
		_to = _to.clamp(bounds.position, bounds.end)


func _tick(delta: float) -> void:
	if not _landed:
		_flight += delta
		var t := minf(_flight / FLIGHT_TIME, 1.0)
		global_position = _from.lerp(_to, t)
		if t >= 1.0:
			_burst()
		queue_redraw()
		return
	for b in _bomblets:
		b[1] -= delta
		if b[1] <= 0.0:
			explode(b[0], stats["radius"] * BOMBLET_SCALE,
				maxi(roundi(stats["damage"] * BOMBLET_SCALE), 1), stats.get("knockback", 0.0) * BOMBLET_SCALE)
	_bomblets = _bomblets.filter(func(b: Array) -> bool: return b[1] > 0.0)
	if _bomblets.is_empty():
		expire()
		return
	queue_redraw()


func _burst() -> void:
	_landed = true
	explode(global_position, stats["radius"], int(stats["damage"]), stats.get("knockback", 0.0))
	for i in int(stats.get("bomblets", 5)):
		var offset: Vector2 = Vector2.from_angle(randf() * TAU) * stats["radius"] * SCATTER * sqrt(randf())
		_bomblets.append([global_position + offset, randf_range(BOMBLET_DELAY.x, BOMBLET_DELAY.y)])


func _draw() -> void:
	if not _landed:
		var t := minf(_flight / FLIGHT_TIME, 1.0)
		var lift := ARC_HEIGHT * 4.0 * t * (1.0 - t)
		draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.3))  # shadow
		draw_circle(Vector2(0, -lift), 4.0, Color.BLACK)
		draw_circle(Vector2(0, -lift), 3.0, owner_color().darkened(0.3))
		return
	# Bomblets waiting to go off, blinking.
	for b in _bomblets:
		var at: Vector2 = to_local(b[0])
		var lit := fmod(b[1], 0.15) < 0.075
		draw_circle(at, 3.0, Color.BLACK)
		draw_circle(at, 2.0, Color(1, 0.3, 0.1) if lit else Color(0.5, 0.1, 0.05))
