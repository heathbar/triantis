extends Enemy
## Charger: walks in like any enemy, but once its target is within
## CHARGE_RANGE it stops and winds up (it flashes, and a lane shows where
## it's headed), then dashes in a straight line at charge_speed for
## CHARGE_DISTANCE, overshooting. Its aim locks just before it goes, so
## sidestep late. Running into a Barricade ends the charge and stuns it.
## Drawn as a pineapple (27x45): upright normally, shaking side to side while
## it winds up, and tipped over leaves-first along its aim while it charges
## (the collision rectangle turns with it). In Braid act 2 it's a swordfish
## (ActTheme): lying flat, facing the way it walks, and pointing its sword
## along its aim while it charges. Act-themed art taller than it is wide
## (Braid act 4's rocket) behaves like the pineapple: its top leads the charge.

const ActTheme := preload("res://scripts/act_theme.gd")

enum Phase { CHASE, WINDUP, CHARGE, RECOVER }

## Starts winding up when its target is this close (centre to centre).
const CHARGE_RANGE := 150.0
const WINDUP_TIME := 0.8
## For the last this-many seconds of the windup its aim is locked.
const AIM_LOCK := 0.25
## How far one charge goes (if nothing stops it).
const CHARGE_DISTANCE := 220.0
## Standing still after a charge.
const RECOVER_TIME := 0.9
## Standing still after hitting a barricade mid-charge.
const STUN_TIME := 2.0
## Walking time before it can charge again.
const CHARGE_COOLDOWN := 1.5
## Sprite tint on its flashes (above 1 brightens the art).
const WINDUP_COLOR := Color(1.9, 1.9, 1.5)
## Windup shake: pixels either side, and shakes per second.
const SHAKE_PIXELS := 1.0
const SHAKE_RATE := 14.0
## How fast it turns to face its charge / rights itself (radians per second).
const TURN_SPEED := 30.0
const UPRIGHT_SPEED := 10.0
const LANE_COLOR := Color(1.0, 0.95, 0.5, 0.18)
## Aim is sent to mirrors as one of this many directions (see net_state).
const AIM_STEPS := 64

## Pixels per second while charging (scaled with the wave's speed).
@export var charge_speed := 300.0

var _phase: int = Phase.CHASE
var _timer := 0.0
var _cooldown := 1.0  # Walks in a little before its first charge.
var _aim := Vector2.RIGHT
var _blink := 0.0
var _sprite: Sprite2D
var _shape: CollisionShape2D
## The sprite's normal tint (the elite colour, for an elite).
var _sprite_color := Color.WHITE
## Its art is wider than tall (act 2's swordfish): it faces right and lies
## flat, rather than standing upright like the pineapple.
var _lies_flat := false


func _ready() -> void:
	var look := ActTheme.enemy_look("charger")
	if look:
		ActTheme.apply_look(self, look)
		_lies_flat = look.get_width() > look.get_height()
	super()
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D


func apply_modifiers(health_multiplier: float, speed_multiplier: float) -> void:
	super(health_multiplier, speed_multiplier)
	charge_speed *= speed_multiplier


func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	charge_speed *= scaling.elite_speed_multiplier
	# Elites tint the sprite (no ColorRect for the base class to recolour).
	# self_modulate, so it stacks with the Freeze Ray's modulate.
	_sprite_color = elite_color
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


func _desired_velocity(target: Node2D, delta: float) -> Vector2:
	_timer -= delta
	match _phase:
		Phase.WINDUP:
			if target and _timer > AIM_LOCK:
				_aim = global_position.direction_to(target.global_position)
				queue_redraw()  # The lane follows the aim until it locks.
			if _timer <= 0.0:
				_set_phase(Phase.CHARGE, CHARGE_DISTANCE / maxf(charge_speed, 1.0))
			return Vector2.ZERO
		Phase.CHARGE:
			if _timer <= 0.0:
				_set_phase(Phase.RECOVER, RECOVER_TIME)
				return Vector2.ZERO
			return _aim * charge_speed * _slow_mult
		Phase.RECOVER:
			if _timer <= 0.0:
				_set_phase(Phase.CHASE, 0.0)
				_cooldown = CHARGE_COOLDOWN
			return Vector2.ZERO
	# Phase.CHASE
	_cooldown -= delta
	if target and _cooldown <= 0.0 \
			and global_position.distance_to(target.global_position) <= CHARGE_RANGE:
		_aim = global_position.direction_to(target.global_position)
		_set_phase(Phase.WINDUP, WINDUP_TIME)
		return Vector2.ZERO
	return super(target, delta)


func _after_move(_delta: float) -> void:
	if _phase != Phase.CHARGE:
		return
	for i in get_slide_collision_count():
		var body := get_slide_collision(i).get_collider() as CollisionObject2D
		if body and body.collision_layer & PhysicsLayers.BARRICADES:
			_set_phase(Phase.RECOVER, STUN_TIME)
			return


func _set_phase(phase: int, seconds: float) -> void:
	_phase = phase
	_timer = seconds
	queue_redraw()


func net_state() -> int:
	var step := wrapi(roundi(_aim.angle() / TAU * AIM_STEPS), 0, AIM_STEPS)
	return _phase | (step << 2)


func mirror_state(state: int) -> void:
	var phase := state & 3
	var aim := Vector2.from_angle(float(state >> 2) / AIM_STEPS * TAU)
	if phase != _phase or aim != _aim:
		_phase = phase
		_aim = aim
		queue_redraw()


func _process(delta: float) -> void:
	if _sprite == null:
		return
	var shake := 0.0
	if _phase == Phase.WINDUP:
		_blink += delta
		# Flashes, faster once its aim is locked.
		var rate := 0.08 if (is_mirror or _timer <= AIM_LOCK) else 0.16
		_sprite.self_modulate = WINDUP_COLOR if fmod(_blink, rate * 2.0) < rate else _sprite_color
		shake = roundf(sin(_blink * SHAKE_RATE * TAU) * SHAKE_PIXELS)
	elif _phase == Phase.RECOVER:
		_sprite.self_modulate = _sprite_color.darkened(0.35)
	else:
		_blink = 0.0
		_sprite.self_modulate = _sprite_color
	_sprite.position.x = shake
	# Leaves (the top of the image) point along the charge; upright otherwise.
	var turn := 0.0
	var turn_speed := UPRIGHT_SPEED
	if _lies_flat:
		# Faces right: mirrored to face left, and from winding up until it
		# recovers, its nose turns to point along the aim.
		var aiming := _phase == Phase.WINDUP or _phase == Phase.CHARGE
		var facing := signf(_aim.x) if aiming else facing_x()
		if facing != 0.0:
			_sprite.flip_h = facing < 0.0
		if aiming:
			turn = _aim.angle() + (PI if _sprite.flip_h else 0.0)
			turn = wrapf(turn, -PI, PI)
			turn_speed = TURN_SPEED
	elif _phase == Phase.CHARGE:
		turn = _aim.angle() + PI / 2.0
		turn_speed = TURN_SPEED
	var angle := _sprite.rotation
	var gap := angle_difference(angle, turn)
	angle = turn if absf(gap) <= turn_speed * delta else angle + signf(gap) * turn_speed * delta
	_sprite.rotation = angle
	if _shape:
		_shape.rotation = angle


## While winding up: the lane it's about to charge down.
func _draw() -> void:
	if _phase != Phase.WINDUP:
		return
	var width := half_extent() * 2.0 / maxf(absf(scale.x), 0.01)
	var length := CHARGE_DISTANCE / maxf(absf(scale.x), 0.01)
	draw_set_transform(Vector2.ZERO, _aim.angle() - rotation, Vector2.ONE)
	draw_rect(Rect2(0.0, -width / 2.0, length, width), LANE_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
