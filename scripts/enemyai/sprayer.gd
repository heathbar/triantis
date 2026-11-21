extends Enemy
## Sprayer: never hurts by touch. Its straw points sideways, so it only shoots
## sideways: it walks to a spot level with its target, a little to one side
## (whichever side it's already on), with the straw's tip at the target's
## height. Once lined up it sprays straight away (no warning): a thick stream
## straight out of the straw for a moment. Players in the stream take
## spray_damage; a Barricade stops the stream. It stands still while it
## sprays, and faces its target the whole time (the art faces right; it's mirrored to face left).
##
## Art (meadow: a soda cup): sprayer-1.png (33x60) is the cup. In Braid
## act 1 the body is a fire extinguisher and in act 4 a robot canister
## instead (THEMED_LAYOUTS).
## sprayer-spray-1..9.png (131x26) are the stream, drawn pointing right from
## its left edge: 1-3 start, 4-6 flow (looped), 7-9 wind down.

enum Phase { CHASE, SPRAY }

const ActTheme := preload("res://scripts/act_theme.gd")

## The straw's tip, from the enemy's centre, facing right (in the cup art:
## pixel (33, 2), with the sprite offset by SPRITE_OFFSET).
const NOZZLE := Vector2(17.0, -35.0)
const SPRITE_OFFSET := Vector2(-16.0, -37.0)
## Act-themed bodies (ActTheme), by theme: where the art sits ("offset"),
## where the stream comes out ("nozzle", facing right) and the collision
## rectangle ("body", centred on the enemy). The stream art stays the same.
## Robot (act 4, 40x55): the canister is x 2-23, y 8-54 of the art; the
## cannon's muzzle ends at x 40, rows 25-30.
## Junkyard (act 1, 24x44): the extinguisher's cylinder and valve are
## x 6-21, y 4-43; the nozzle points right, ending at x 23, rows 0-2.
const THEMED_LAYOUTS := {
	"junkyard": {"offset": Vector2(-13.0, -24.0), "nozzle": Vector2(10.0, -23.0), "body": Vector2(16.0, 40.0)},
	"robot": {"offset": Vector2(-13.0, -31.0), "nozzle": Vector2(27.0, -3.0), "body": Vector2(22.0, 44.0)},
}
## The stream art's row that lines up with the straw (middle of its root).
const SPRAY_ROOT_Y := 12.5
## Where it stands: this many pixels of gap between the straw tip and its
## target's centre.
const STANDOFF := 70.0
## It sprays when its target is this close to the straw's height
## and between these gaps from the straw tip (along the way it faces).
const AIM_TOLERANCE := 6.0
const MIN_GAP := 8.0
const MAX_GAP := 115.0
## Close enough to the spot it wants: stands still.
const ARRIVED := 3.0
## Its target has to be this far past its middle before it turns round (so
## it doesn't flicker back and forth while a player stands on top of it).
const TURN_MARGIN := 10.0
## Seconds per start / flow / wind-down frame, and how long the flow lasts.
const START_FRAME_TIME := 0.07
const FLOW_FRAME_TIME := 0.08
const END_FRAME_TIME := 0.07
const FLOW_TIME := 1.1
## Walking time after a spray before it can spray again.
const SPRAY_COOLDOWN := 1.4
## Each stream frame's wet part, in art pixels: x from, x to (from the
## straw). Its height is SPRAY_HALF_HEIGHT either side of the straw.
const SPRAY_SPANS := [
	Vector2(0, 56), Vector2(0, 85), Vector2(0, 108),
	Vector2(0, 131), Vector2(0, 130), Vector2(0, 125),
	Vector2(31, 125), Vector2(57, 131), Vector2(95, 131),
]
const SPRAY_HALF_HEIGHT := 7.0
## A player's body counts as reaching this far from their centre.
const PLAYER_HALF := Vector2(13.0, 12.0)
const SPRAY_FRAMES := [
	preload("res://assets/meadow/enemies/sprayer-spray-1.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-2.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-3.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-4.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-5.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-6.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-7.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-8.png"),
	preload("res://assets/meadow/enemies/sprayer-spray-9.png"),
]

## Half hearts the stream costs a player it hits (once per hit: a player
## standing in it is hit again whenever their post-hit invulnerability ends).
@export var spray_damage := 1

var _phase: int = Phase.CHASE
var _timer := 0.0
## Seconds since the spray began (picks its frame).
var _spray_t := 0.0
var _cooldown := 0.8  # Lines up a little before its first spray.
## 1 facing right, -1 facing left.
var _facing := 1.0
## How far the stream gets this frame before a Barricade stops it (art
## pixels; see _spray_reach).
var _reach := 131.0
var _visual: Node2D
var _sprite: Sprite2D
var _spray: Sprite2D
## Where the stream comes out (NOZZLE, or the act-themed body's).
var _nozzle_at := NOZZLE


func _ready() -> void:
	super()
	_visual = get_node_or_null("Visual") as Node2D
	_sprite = get_node_or_null("Visual/Sprite2D") as Sprite2D
	_spray = get_node_or_null("Visual/Spray") as Sprite2D
	var sprite_offset := SPRITE_OFFSET
	var look := ActTheme.enemy_look("sprayer")
	var layout: Dictionary = THEMED_LAYOUTS.get(ActTheme.current, {})
	if look and not layout.is_empty():
		sprite_offset = layout["offset"]
		_nozzle_at = layout["nozzle"]
		if _sprite:
			_sprite.texture = look
		var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node:
			var rect := RectangleShape2D.new()  # Own copy: the scene's is shared.
			rect.size = layout["body"]
			shape_node.shape = rect
			shape_node.position = Vector2.ZERO
	if _sprite:
		_sprite.offset = sprite_offset
	if _spray:
		_spray.position = _nozzle_at
		_spray.offset = Vector2(0.0, -SPRAY_ROOT_Y)
		_spray.visible = false


func make_elite(scaling: PlayerScaling) -> void:
	super(scaling)
	# Elites tint the sprite (no ColorRect for the base class to recolour).
	# self_modulate, so it stacks with the Freeze Ray's modulate.
	var sprite := get_node_or_null("Visual/Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = elite_color


## The sprayer is after players (or a Decoy) only: objectives are left to the
## enemies that can touch them.
func _objective_target() -> Node2D:
	return null


## The straw's tip, in global coordinates.
func _nozzle() -> Vector2:
	return global_position + Vector2(_nozzle_at.x * _facing, _nozzle_at.y) * scale


func _desired_velocity(target: Node2D, delta: float) -> Vector2:
	_timer -= delta
	match _phase:
		Phase.SPRAY:
			if _timer <= 0.0:
				_set_phase(Phase.CHASE, 0.0)
				_cooldown = SPRAY_COOLDOWN
			return Vector2.ZERO
	# Phase.CHASE
	_cooldown -= delta
	if target == null:
		return Vector2.ZERO
	var to_target := target.global_position.x - global_position.x
	if absf(to_target) > TURN_MARGIN * scale.x and signf(to_target) != _facing:
		_facing = signf(to_target)
	var nozzle := _nozzle()
	var gap := (target.global_position.x - nozzle.x) * _facing
	if _cooldown <= 0.0 and absf(target.global_position.y - nozzle.y) <= AIM_TOLERANCE \
			and gap >= MIN_GAP and gap <= MAX_GAP * scale.x:
		_set_phase(Phase.SPRAY, _spray_length())
		return Vector2.ZERO
	# The spot: straw tip level with the target, STANDOFF out to our side.
	var spot := target.global_position \
			- Vector2((STANDOFF + _nozzle_at.x) * _facing, _nozzle_at.y) * scale
	var to_spot := spot - global_position
	if to_spot.length() <= ARRIVED:
		return Vector2.ZERO
	if steering.is_valid() and to_spot.length() > STANDOFF:
		return super(target, delta)  # Braid mode: round walls first.
	# Ease in on the last few pixels so it doesn't jitter past the spot.
	var step := minf(speed * _slow_mult, to_spot.length() / maxf(delta, 0.001))
	return to_spot.normalized() * step


func _set_phase(phase: int, seconds: float) -> void:
	_phase = phase
	_timer = seconds
	if phase == Phase.SPRAY:
		_spray_t = 0.0


static func _spray_length() -> float:
	return 3.0 * START_FRAME_TIME + FLOW_TIME + 3.0 * END_FRAME_TIME


## Which stream frame (0-8) shows `t` seconds into a spray, or -1 once it's
## over.
static func _spray_frame(t: float) -> int:
	var start := 3.0 * START_FRAME_TIME
	if t < start:
		return int(t / START_FRAME_TIME)
	t -= start
	if t < FLOW_TIME:
		return 3 + int(t / FLOW_FRAME_TIME) % 3
	t -= FLOW_TIME
	if t < 3.0 * END_FRAME_TIME:
		return 6 + int(t / END_FRAME_TIME)
	return -1


func _physics_process(delta: float) -> void:
	super(delta)
	if _phase != Phase.SPRAY:
		return
	if is_mirror:  # Its owner doesn't send timings: play the spray ourselves.
		_spray_t += delta
	elif not is_dead():
		_spray_t = _spray_length() - maxf(_timer, 0.0)
	_reach = _spray_reach()
	_spray_hits()


## How far the stream can go before a Barricade stops it (art pixels).
func _spray_reach() -> float:
	var from := _nozzle()
	var to := from + Vector2(131.0 * _facing, 0.0) * scale
	var query := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.BARRICADES)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 131.0
	return from.distance_to(hit.position) / maxf(scale.x, 0.01)


## Hurts our players in this frame's stream. Mirrors do it too: each
## squad's game sprays its own players (as bomber blasts do).
func _spray_hits() -> void:
	var frame := _spray_frame(_spray_t)
	if frame < 0:
		return
	var span: Vector2 = SPRAY_SPANS[frame]
	var reach := _reach
	if span.x >= reach:
		return
	var nozzle := _nozzle()
	var near := nozzle.x + span.x * scale.x * _facing
	var far := nozzle.x + minf(span.y, reach) * scale.x * _facing
	var wet := Rect2(minf(near, far), nozzle.y - SPRAY_HALF_HEIGHT * scale.y,
			absf(far - near), 2.0 * SPRAY_HALF_HEIGHT * scale.y)
	for player: Node2D in get_tree().get_nodes_in_group("players"):
		if not player is Player:
			continue
		var body := Rect2(player.global_position - PLAYER_HALF, PLAYER_HALF * 2.0)
		if wet.intersects(body):
			player.hurt_by(spray_damage, Vector2(
					clampf(player.global_position.x, wet.position.x, wet.end.x), nozzle.y))


func net_state() -> int:
	return _phase | (int(_facing < 0.0) << 2)


func mirror_state(state: int) -> void:
	var phase := state & 3
	_facing = -1.0 if state & 4 else 1.0
	if phase != _phase:
		_set_phase(phase, 0.0)


func _process(_delta: float) -> void:
	if _visual:
		_visual.scale.x = _facing
	if _spray == null:
		return
	var frame := _spray_frame(_spray_t) if _phase == Phase.SPRAY else -1
	_spray.visible = frame >= 0
	if frame >= 0:
		_spray.texture = SPRAY_FRAMES[frame]
		# Cut the stream off at a Barricade.
		_spray.region_enabled = true
		_spray.region_rect = Rect2(0.0, 0.0, ceilf(_reach), 26.0)
