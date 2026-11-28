extends Enemy
## Charger: walks in like any enemy, but once its target is within
## CHARGE_RANGE it stops and winds up (it flashes, and a lane shows where
## it's headed), then dashes in a straight line at charge_speed for
## CHARGE_DISTANCE, overshooting. Its aim locks just before it goes, so
## sidestep late. Running into a Barricade ends the charge and stuns it.
## Drawn as a horned ram (the meadow's, the default; dark-outlined so it
## stands out on the grass): trotting through its
## walk frames (charger-1a..d), head down and shaking side to side while it
## winds up, galloping through its charge frames (charger-charge-1a..d) with
## a puff of dust (charger-dust-1) kicked up behind as it goes. It never
## turns, just faces left or right (its aim, from winding up until it
## recovers). Act-themed art is one still image. In Braid act 2 it's a swordfish
## (ActTheme): lying flat, facing the way it walks, and pointing its sword
## along its aim while it charges. Act-themed art taller than it is wide
## (Braid act 4's rocket) stands upright and tips over along its aim while it
## charges, its top leading (the collision rectangle turns with it).

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
## The default (meadow) ram: walk frames, charge frames, and the dust it
## kicks up as a charge starts.
const WALK_FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/charger-1a.png"),
	preload("res://assets/meadow/enemies/charger-1b.png"),
	preload("res://assets/meadow/enemies/charger-1c.png"),
	preload("res://assets/meadow/enemies/charger-1d.png"),
]
const CHARGE_FRAMES: Array[Texture2D] = [
	preload("res://assets/meadow/enemies/charger-charge-1a.png"),
	preload("res://assets/meadow/enemies/charger-charge-1b.png"),
	preload("res://assets/meadow/enemies/charger-charge-1c.png"),
	preload("res://assets/meadow/enemies/charger-charge-1d.png"),
]
const DUST := preload("res://assets/meadow/enemies/charger-dust-1.png")
## Seconds per walk / charge frame, and how long the dust takes to fade.
const WALK_FRAME_TIME := 0.15
const CHARGE_FRAME_TIME := 0.06
const DUST_TIME := 0.45

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
## flat, rather than standing upright like the rocket.
var _lies_flat := false
## Drawn with the default (meadow) ram's frames, not a still themed image.
var _animated := false
## Seconds into the current walk / charge animation.
var _anim := 0.0
## The phase _process last drew (kicks up dust as a charge starts, mirrors too).
var _drawn_phase: int = Phase.CHASE


func _ready() -> void:
	var look := ActTheme.enemy_look("charger")
	_animated = look == null
	ActTheme.apply_look(self, look if look else WALK_FRAMES[0])
	if look:
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
	if _animated:
		_animate(delta)
		return
	# The top of the image points along the charge; upright otherwise.
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


## The ram (default art): picks its frame for the phase and faces left or
## right, and kicks up dust as a charge starts.
func _animate(delta: float) -> void:
	if _phase != _drawn_phase:
		_anim = 0.0
		if _phase == Phase.CHARGE:
			_kick_up_dust()
		_drawn_phase = _phase
	_anim += delta
	var aiming := _phase == Phase.WINDUP or _phase == Phase.CHARGE
	var facing := signf(_aim.x) if aiming else facing_x()
	if facing != 0.0:
		_sprite.flip_h = facing < 0.0
	match _phase:
		Phase.WINDUP:
			_sprite.texture = CHARGE_FRAMES[0]  # Head down, shaking.
		Phase.CHARGE:
			_sprite.texture = ActTheme.frame_at(CHARGE_FRAMES, _anim, CHARGE_FRAME_TIME)
		Phase.RECOVER:
			_sprite.texture = WALK_FRAMES[0]
		_:
			_sprite.texture = ActTheme.frame_at(WALK_FRAMES, _anim, WALK_FRAME_TIME)


## A puff of dust at its hooves, behind it, that fades out where it is.
func _kick_up_dust() -> void:
	var world := get_parent() as Node2D
	if world == null:
		return
	var dust := Sprite2D.new()
	dust.texture = DUST
	dust.flip_h = _aim.x < 0.0
	dust.scale = scale
	var feet := Vector2(-_aim.x * 10.0, ActTheme.used_rect(WALK_FRAMES[0]).size.y / 2.0 - 6.0)
	dust.position = world.to_local(global_position + feet * scale)
	world.add_child(dust)
	world.move_child(dust, get_index())  # Under the ram.
	var tween := dust.create_tween()
	tween.tween_property(dust, "modulate:a", 0.0, DUST_TIME)
	tween.tween_callback(dust.queue_free)


## While winding up: the lane it's about to charge down.
func _draw() -> void:
	if _phase != Phase.WINDUP:
		return
	var width := half_extent() * 2.0 / maxf(absf(scale.x), 0.01)
	var length := CHARGE_DISTANCE / maxf(absf(scale.x), 0.01)
	draw_set_transform(Vector2.ZERO, _aim.angle() - rotation, Vector2.ONE)
	draw_rect(Rect2(0.0, -width / 2.0, length, width), LANE_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
