extends Deployable
## Dash Pack: throws its owner `distance` pixels the way they're moving (or
## facing, if they're standing still) over DASH_TIME seconds
## (Player.start_dash): they pass through enemies and can't be hurt by them
## mid-dash. Every enemy they pass is hit once for `damage` and knocked aside
## (`knockback`). Rides along with the owner, drawing a streak, then goes.
## Engineering raises the distance and damage (scripts/equipment.gd).

const COLOR := Color(1.0, 0.85, 0.35)
const DASH_TIME := 0.18
## Enemies this close to the owner's path are hit.
const REACH := 14.0
## Seconds the streak lingers after the dash.
const FADE := 0.15

var _direction := Vector2.RIGHT
var _start := Vector2.ZERO
var _clock := 0.0
## Instance ids of enemies already hit.
var _hit := {}


func _ready() -> void:
	super()
	z_index = 5
	_start = global_position
	if not is_instance_valid(owner_player):
		return
	var moving: Vector2 = owner_player.velocity
	_direction = moving.normalized() if moving.length() > 10.0 \
		else Vector2.from_angle(owner_player.body.rotation)
	owner_player.start_dash(_direction * stats.get("distance", 110.0) / DASH_TIME, DASH_TIME)


func _tick(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(owner_player) or _clock > DASH_TIME + FADE:
		expire()
		return
	if _clock <= DASH_TIME + delta:
		global_position = owner_player.global_position
		for enemy in enemies_within(global_position, REACH):
			var id := enemy.get_instance_id()
			if _hit.has(id):
				continue
			_hit[id] = true
			var side := _direction.orthogonal()
			if side.dot(enemy.global_position - global_position) < 0.0:
				side = -side
			BossBody.deal(enemy, int(stats["damage"]), credit(), side * stats.get("knockback", 0.0),
				enemy.global_position, true)
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - clampf((_clock - DASH_TIME) / FADE, 0.0, 1.0)
	var c := COLOR
	c.a = 0.6 * fade
	var from := to_local(_start)
	draw_line(from, Vector2.ZERO, c, 6.0)
	c.a = 0.9 * fade
	draw_line(from.lerp(Vector2.ZERO, 0.5), Vector2.ZERO, c, 2.0)
