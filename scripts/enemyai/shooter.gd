extends Enemy
## Shooter: keeps its distance and fires slow bullets
## (scripts/enemyai/enemy_bullet.gd) at its target. It walks in until it's
## within FIRE_RANGE with a clear line (no wall, window glass or Barricade in
## the way), backs off if a player gets closer than KEEP_AWAY, and otherwise
## stands its ground. Before each shot it stops and blinks for WINDUP seconds,
## then fires at where its target is; RELOAD seconds later it can fire again.
## Frozen, it doesn't shoot; slowed, its timers run slower too. Touching it
## still hurts (contact_damage).
##
## Art: assets/<theme>/enemies/shooter-1.png (ActTheme.ENEMY_LOOKS "shooter";
## the meadow's is the default), facing right and mirrored to face its aim.
## The scene's ColorRect is only a fallback.

const ActTheme := preload("res://scripts/act_theme.gd")
const EnemyBullet := preload("res://scripts/enemyai/enemy_bullet.gd")

## Fires at targets this close (pixels, centre to centre).
const FIRE_RANGE := 170.0
## Backs away from targets closer than this.
const KEEP_AWAY := 90.0
## Seconds of warning (standing still, blinking) before each shot.
const WINDUP := 0.3
## Seconds between shots (plus up to RELOAD_JITTER at random, so a crowd of
## them doesn't fire in step).
const RELOAD := 2.0
const RELOAD_JITTER := 0.5
## Seconds after spawning before its first shot can start.
const FIRST_SHOT := 1.2
const BULLET_SPEED := 130.0
## Bullets start this far out from its centre, towards the target.
const MUZZLE := 10.0
const BLINK_COLOR := Color(1.0, 0.95, 0.7)
const LINE_BLOCKERS := PhysicsLayers.WALLS | PhysicsLayers.WINDOWS | PhysicsLayers.BARRICADES
## Aim directions sent to mirrors (net_state has 5 bits for it).
const AIM_STEPS := 32

## Half hearts each bullet costs.
@export var bullet_damage := 1

var _reload := FIRST_SHOT
## Seconds left of the wind-up (0 = not winding up).
var _windup := 0.0
var _aim := Vector2.RIGHT
## Counts shots (mod 4) so mirrors see each new one.
var _shots := 0
var _blink := 0.0
var _sprite: Sprite2D
## Mirrors: false until the owner's first state (its shot count then is
## where we start counting, not a new shot).
var _synced := false


func _ready() -> void:
	super()
	var look := ActTheme.enemy_look("shooter")
	if look:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
		ActTheme.apply_look(self, look)
		var rect := get_node_or_null("ColorRect") as CanvasItem
		if rect:
			rect.visible = false


func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	bullet_damage = maxi(bullet_damage, ELITE_DAMAGE)
	if _sprite:
		_sprite.self_modulate = elite_color


## Players (or a Decoy) only: objectives are left to enemies that can touch them.
func _objective_target() -> Node2D:
	return null


func _desired_velocity(target: Node2D, delta: float) -> Vector2:
	if target == null:
		_windup = 0.0
		return Vector2.ZERO
	# Faces its target (mirrors face the aim they're sent).
	if global_position.distance_squared_to(target.global_position) > 0.01:
		_aim = global_position.direction_to(target.global_position)
	# Frozen: nothing happens. Slowed: its timers run slower too.
	var pace := _slow_mult
	var dist := global_position.distance_to(target.global_position)
	var clear := dist <= FIRE_RANGE and _clear_line(target.global_position)
	if _windup > 0.0:
		_windup -= delta * pace
		_aim = global_position.direction_to(target.global_position)
		if _windup <= 0.0:
			_windup = 0.0
			if clear:
				_fire(_aim)
			_reload = RELOAD + randf() * RELOAD_JITTER
		return Vector2.ZERO
	_reload -= delta * pace
	if clear and _reload <= 0.0 and pace > 0.0:
		_windup = WINDUP
		return Vector2.ZERO
	if not clear:
		return super(target, delta)  # Walk in (round walls in Braid).
	if dist < KEEP_AWAY:
		return target.global_position.direction_to(global_position) * speed * _slow_mult
	return Vector2.ZERO


## Nothing that stops bullets between it and `point`.
func _clear_line(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point, LINE_BLOCKERS)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _fire(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	_shots = (_shots + 1) % 4
	var bullet := EnemyBullet.new()
	bullet.direction = direction
	bullet.speed = BULLET_SPEED
	bullet.damage = bullet_damage
	bullet.position = global_position + direction * MUZZLE
	get_parent().add_child(bullet)


## Bit 0: winding up; bits 1-2: shot count (mod 4); bits 3-7: aim.
func net_state() -> int:
	var step := posmod(roundi(_aim.angle() / TAU * AIM_STEPS), AIM_STEPS)
	return int(_windup > 0.0) | (_shots << 1) | (step << 3)


## Mirrors fire their own copy of each new shot (it hurts our players).
func mirror_state(state: int) -> void:
	_windup = WINDUP if state & 1 else 0.0
	_aim = Vector2.RIGHT.rotated(float((state >> 3) & 31) / AIM_STEPS * TAU)
	var shots := (state >> 1) & 3
	if not _synced:
		_synced = true
		_shots = shots
	elif shots != _shots:
		_shots = (shots + 3) % 4  # _fire counts it back up.
		_fire(_aim)


func _process(delta: float) -> void:
	var item: CanvasItem = _sprite if _sprite else get_node_or_null("ColorRect") as CanvasItem
	if item == null:
		return
	if _windup > 0.0:
		_blink += delta
		var on := fmod(_blink, 0.12) < 0.06
		if _sprite:
			_sprite.self_modulate = BLINK_COLOR if on else (elite_color if is_elite else Color.WHITE)
		else:
			(item as ColorRect).color = BLINK_COLOR if on else base_color()
	else:
		_blink = 0.0
		if _sprite:
			_sprite.self_modulate = elite_color if is_elite else Color.WHITE
		else:
			(item as ColorRect).color = base_color()
	if _sprite and _aim.x != 0.0:
		_sprite.flip_h = _aim.x < 0.0
