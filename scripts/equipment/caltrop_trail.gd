extends Deployable
## Caltrop Trail: for its duration, a patch of spikes drops behind the owner
## every `spacing` pixels they move. Each patch lasts `linger` seconds; every
## `tick` it hurts each enemy within `radius` of it for `damage` and slows it
## to `slow` x its speed. Standing still drops nothing, so it rewards keeping
## on the move. The item stays until its last patch is gone. Engineering
## raises the damage and how long patches last (scripts/equipment.gd).

const COLOR := Color(0.75, 0.75, 0.8)

## Each patch: [world position, seconds left].
var _patches := []
## How long it keeps dropping (its duration; the node outlives it while
## patches remain, so Deployable's own expiry is switched off).
var _drop_time := 0.0
var _last_drop := Vector2.INF
var _tick_left := 0.0


func _ready() -> void:
	super()
	_drop_time = duration
	duration = 0.0
	# Not following the owner: patches are kept in world positions.
	top_level = true
	global_position = Vector2.ZERO


func _tick(delta: float) -> void:
	if _age < _drop_time and is_instance_valid(owner_player) and not owner_player.is_dead():
		var at: Vector2 = owner_player.global_position
		if _last_drop == Vector2.INF or at.distance_to(_last_drop) >= stats.get("spacing", 14.0):
			_last_drop = at
			_patches.append([at, float(stats.get("linger", 6.0))])
	for patch in _patches:
		patch[1] -= delta
	_patches = _patches.filter(func(p: Array) -> bool: return p[1] > 0.0)
	if _patches.is_empty() and _age >= _drop_time:
		expire()
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = stats.get("tick", 0.5)
		_hurt()
	queue_redraw()


## Each enemy touching any patch is hurt once and slowed.
func _hurt() -> void:
	var radius: float = stats.get("radius", 10.0)
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("take_damage") or enemy.is_dead():
			continue
		var reach := radius + half_extent(enemy)
		for patch in _patches:
			if enemy.global_position.distance_to(patch[0]) <= reach:
				BossBody.deal(enemy, int(stats["damage"]), credit(), Vector2.ZERO, enemy.global_position, true)
				if enemy.has_method("apply_slow"):
					enemy.apply_slow(stats.get("slow", 0.6), stats.get("tick", 0.5) + 0.1)
				break


func _draw() -> void:
	var tint := owner_color().lerp(COLOR, 0.6)
	for patch in _patches:
		var at: Vector2 = patch[0]
		var c := tint
		c.a = clampf(patch[1], 0.0, 1.0)
		# Three little spikes.
		for i in 3:
			var d := Vector2.from_angle(i * TAU / 3.0 + at.x) * 3.0
			draw_line(at + d, at - d * 0.4, Color(0, 0, 0, c.a), 2.0)
			draw_line(at + d, at - d * 0.4, c, 1.0)
