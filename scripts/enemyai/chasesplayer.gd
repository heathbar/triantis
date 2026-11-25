class_name Enemy
extends CharacterBody2D
## Base for every enemy type (scripts/enemyai/): walks at its target (a lure,
## an objective after it, or the nearest player), takes damage and knockback,
## and dies with `died`. Enemy scenes set the stats below; types override
## _desired_velocity, _after_move, _on_death and the squads-game mirror hooks.

## Emitted once when this enemy's health reaches 0 (just before it's removed).
## `killer` is the player whose shot finished it off (null if unknown), and
## `at` is where the enemy was when it died.
signal died(killer: Node, at: Vector2)

const STOP_DISTANCE = 9.0
## How fast a shove dies away (per second). A knockback of N pixels starts at
## N * KNOCKBACK_DECAY px/s and slows exponentially, so it covers ~N pixels.
const KNOCKBACK_DECAY := 12.0
const ELITE_COLOR := Color(0.55, 0.0, 0.2)
## Half hearts an elite's hits always take, at least (a full heart): its
## contact_damage here, and its subclass's bullets, spray or blast.
const ELITE_DAMAGE := 2
const EliteCrown := preload("res://scripts/enemyai/elite_crown.gd")
## Tint while slowed (see apply_slow), and while frozen solid (slowed to 0,
## the Freeze Ray): light blue, over 1 so it lightens dark sprites too.
const SLOW_TINT := Color(0.55, 0.8, 1.0)
const FROZEN_TINT := Color(0.8, 1.3, 1.9)
## Stuck checks (Braid, see _track_stuck): every STUCK_SAMPLE seconds, it's
## stuck if it moved less than STUCK_PROGRESS of the way it meant to walk; it
## then steers carefully for UNSTICK_TIME seconds. Not when it's within
## STUCK_NEAR of what it's after (pressing on a player is the point).
const STUCK_SAMPLE := 0.25
const STUCK_PROGRESS := 0.3
const UNSTICK_TIME := 1.5
const STUCK_NEAR := 40.0
const STUCK_COUNT_MAX := 20
const NO_REMOTE_KILLER := Vector2i(-1, -1)
const NetFollow := preload("res://scripts/net/net_follow.gd")
## Hit flash: like the player's (character_body.gd FLASH_COLOR, FLASH_HOLD,
## FLASH_FADE; player_sprite.gd FLASH_STRENGTH), when a hit doesn't kill it.
const HIT_FLASH_SHADER := preload("res://scripts/enemyai/hit_flash.gdshader")
const HIT_FLASH_COLOR := Color(1, 0, 0)
const HIT_FLASH_HOLD := 0.1
const HIT_FLASH_FADE := 0.2
const HIT_FLASH_STRENGTH := 0.8

## Per-type stats. A new enemy type can be a scene that overrides these.
@export var max_health := 10
@export var speed := 30.0
## Points awarded to the player who finishes it off.
@export var points_value := 10
## Resource pickups dropped when it dies.
@export var resource_drops := 1
## Chance it drops them at all (rolled once, when it spawns).
@export_range(0.0, 1.0, 0.05) var drop_chance := 1.0
## Knockback is divided by this (elites are heavier: see make_elite).
@export var mass := 1.0
## Half hearts a player loses when this touches them (1 = half a heart).
@export var contact_damage := 1
## Barricade health this wears off every wear tick while pushing on one
## (scripts/equipment/barricade.gd).
@export var barricade_wear := 1
## Its colour as an elite (see make_elite).
@export var elite_color := ELITE_COLOR

var health := 0
## The health multiplier it was spawned with (apply_modifiers), for types
## whose damage to other enemies should keep up with the wave.
var health_scale := 1.0
## Elites are tougher, bigger, darker versions (see make_elite).
var is_elite := false

# --- Squads game (see scripts/net/squad_link.gd) ---
## The area (our squad's map) this enemy must stay inside. Empty = no limit.
var move_bounds := Rect2()
## Identifies this enemy to the other squads' games.
var net_id := -1
## Which enemy scene (and whether elite), for other squads to mirror it.
var net_kind := 0
## Who landed the final blow, when it was another squad's player:
## Vector2i(squad, player slot). Check it when `died` fires (killer is null).
var remote_killer := NO_REMOTE_KILLER
## True for a mirror: a copy of another squad's enemy that's near our map.
## It doesn't move on its own (mirror_report does that) and hits on it go to
## forward_hit (amount, source, knockback) instead of being applied here. Set before it
## enters the tree.
var is_mirror := false
var forward_hit := Callable()
var _follow: NetFollow
## Velocity from being shoved by hits; decays each physics frame.
var _knockback_velocity := Vector2.ZERO
## Freeze Ray (scripts/equipment/freeze_ray.gd): x speed while slowed, and
## seconds the slow has left.
var _slow_mult := 1.0
var _slow_left := 0.0
## Gravity Well (scripts/equipment/gravity_well.gd): velocity it adds this
## physics frame (see apply_pull).
var _pull := Vector2.ZERO
## See base_color.
var _base_color := Color.WHITE
## Its own walking velocity this physics frame (before knockback and pulls),
## so sprites face where it's going rather than where a hit shoved it.
var walk_velocity := Vector2.ZERO
## Mirrors: x last time facing_x() was asked (see there).
var _facing_last_x := NAN
## Objective waves: a 0..1 roll fixed for this enemy's life, which objectives
## use to split enemies between their targets (scripts/objectives/).
var objective_roll := randf()
## Braid mode (scripts/braid/braid_game.gd): which way to walk to reach a
## target around walls, as func(enemy, target: Node2D) -> Vector2 (a unit
## vector). Unset (the arena game): straight at it.
var steering := Callable()
## Braid mode (only while `steering` is set): seconds left of steering more
## carefully round walls, set whenever it's found to be stuck (pushing on but
## hardly moving: see _track_stuck), and how many times in a row that's been.
var unstick_left := 0.0
var stuck_count := 0
## The steering's notes while it's unsticking: where it's heading, and the
## physics frame it picked that.
var unstick_waypoint := Vector2.INF
var unstick_planned := -1000
var _stuck_from := Vector2.INF
var _stuck_clock := 0.0
var _stuck_want := 0.0
## Braid mode: damage it takes is multiplied by this (a Spotter's mark,
## scripts/braid/braid_class_mod.gd). Always 1 in the arena game.
var damage_taken_multiplier := 1.0
## The hit flash material (made on the first hit) and its fade.
var _flash_material: ShaderMaterial
var _flash_tween: Tween
## The CollisionShape2D child, looked up once (see _collision_shape).
var _shape_node: CollisionShape2D
var _shape_looked_up := false

## Every enemy looks for its targets each physics frame. The groups it reads
## are fetched once per physics frame for all of them (see _group).
static var _group_frame := -1
static var _group_cache := {}


func _ready() -> void:
	# Top-down: no floors. In the default (platformer) mode an enemy pushed
	# from below thinks it's standing on that player and rides along with them.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health = max_health
	add_to_group("enemies")
	var rect := get_node_or_null("ColorRect") as ColorRect
	if rect:
		_base_color = rect.color  # (already the elite colour, for an elite)
	if is_mirror:
		collision_mask = 0  # Moved by its owner's updates, never by physics.
	else:
		collision_mask |= PhysicsLayers.BARRICADES
		if randf() >= drop_chance:
			resource_drops = 0


## Called by game.gd before the enemy enters the tree, to scale it for the
## current wave.
func apply_modifiers(health_multiplier: float, speed_multiplier: float) -> void:
	max_health = maxi(roundi(max_health * health_multiplier), 1)
	health_scale = health_multiplier
	speed *= speed_multiplier


## Called by game.gd (after apply_modifiers, before entering the tree) to turn
## this enemy into a bigger, tougher, more rewarding elite: a full heart a
## hit (ELITE_DAMAGE), and a crown over its head (elite_crown.gd).
func make_elite(scaling: PlayerScaling) -> void:
	is_elite = true
	if contact_damage > 0:  # (some only hurt with their attack: see subclasses)
		contact_damage = maxi(contact_damage, ELITE_DAMAGE)
	add_child(EliteCrown.new())
	max_health = maxi(roundi(max_health * scaling.elite_health_multiplier), 1)
	speed *= scaling.elite_speed_multiplier
	points_value *= scaling.elite_reward_multiplier
	resource_drops *= scaling.elite_reward_multiplier
	scale *= scaling.elite_size_multiplier
	mass *= scaling.elite_size_multiplier
	var rect := get_node_or_null("ColorRect") as ColorRect
	if rect:
		rect.color = elite_color


## Its normal colour (as an elite too), for types that flash or change colour.
func base_color() -> Color:
	return _base_color


func is_dead() -> bool:
	return health <= 0


## `knockback` shoves the enemy: its direction, and its length in pixels
## (before mass).
func take_damage(amount: int, source: Node = null, knockback := Vector2.ZERO) -> void:
	if is_mirror:
		forward_hit.call(amount, source, knockback)
		flash_hit()  # (its owner's copy decides if it dies; if so it vanishes)
		return
	if is_dead():
		return
	apply_knockback(knockback)
	if damage_taken_multiplier != 1.0:
		amount = maxi(roundi(amount * damage_taken_multiplier), 1)
	health = maxi(health - amount, 0)
	if is_dead():
		_die(source)
	else:
		flash_hit()


## Washes its sprites red for a moment, then fades back (as a hurt player
## does). The flash is a shader on each of _flash_targets(), so it stacks with the slow tint (modulate) and elite or
## wind-up colours (self_modulate). Children that have their own material
## are left alone.
func flash_hit() -> void:
	if not is_inside_tree():
		return
	if _flash_material == null:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = HIT_FLASH_SHADER
		_flash_material.set_shader_parameter("flash_color", HIT_FLASH_COLOR)
	# Checked every hit: some types add sprites after spawning.
	for item in _flash_targets():
		if item.material == null:
			item.material = _flash_material
	if _flash_tween:
		_flash_tween.kill()
	_set_flash(HIT_FLASH_STRENGTH)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(HIT_FLASH_HOLD)
	_flash_tween.tween_method(_set_flash, HIT_FLASH_STRENGTH, 0.0, HIT_FLASH_FADE)


func _set_flash(amount: float) -> void:
	_flash_material.set_shader_parameter("flash_amount", amount)


## What flash_hit washes red: its Sprite2D / AnimatedSprite2D / ColorRect
## children. Types that keep their body art elsewhere override this.
func _flash_targets() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D or child is ColorRect:
			out.append(child)
	return out


## Removes it, announcing `died` (killer = `source`). Subclasses hook in
## through _on_death.
func _die(source: Node) -> void:
	health = 0
	# Leave the group right away so players stop taking contact damage
	# from it this frame, then disappear.
	remove_from_group("enemies")
	_on_death(source)
	died.emit(source, global_position)
	queue_free()


## Called once as it dies, before `died` is emitted (owner's copy only).
func _on_death(_killer: Node) -> void:
	pass


## Mirror: its owner says it died at `at` (our coordinates). Types with a
## death effect players nearby should feel (e.g. the bomber's blast) play it
## here for our side of the strip.
func mirror_died(_at: Vector2) -> void:
	pass


## Squads game: a small number (0-255) describing what it's doing right now,
## sent along with its position so mirrors can show it (e.g. a charger
## winding up). 0 = nothing special.
func net_state() -> int:
	return 0


## Mirror: the owner's net_state() for it.
func mirror_state(_state: int) -> void:
	pass


## Squads game: a hit from another squad's player, sent by their game.
func take_remote_damage(amount: int, squad: int, slot: int,
		knockback := Vector2.ZERO) -> void:
	remote_killer = Vector2i(squad, slot)
	take_damage(amount, null, knockback)
	if not is_dead():
		remote_killer = NO_REMOTE_KILLER


## Shoves the enemy `knockback.length()` pixels (divided by mass) along it.
func apply_knockback(knockback: Vector2) -> void:
	if knockback == Vector2.ZERO or is_mirror:
		return
	_knockback_velocity += knockback / maxf(mass, 0.01) * KNOCKBACK_DECAY


## Slows the enemy to `mult` x its speed for `seconds` (the strongest slow
## wins while several overlap). Mirrors ignore it: their owner moves them.
func apply_slow(mult: float, seconds: float) -> void:
	if is_mirror or is_dead():
		return
	_slow_mult = mult if _slow_left <= 0.0 else minf(_slow_mult, mult)
	_slow_left = maxf(_slow_left, seconds)
	_set_tint(FROZEN_TINT if _slow_mult <= 0.0 else SLOW_TINT)


## Sets the slow/freeze tint, keeping the current alpha (Braid fades enemies).
func _set_tint(tint: Color) -> void:
	modulate = Color(tint, modulate.a)


## Drags the enemy along `pull` (pixels per second) for the next physics
## frame, on top of its own movement. Call every frame to keep pulling.
## Mirrors ignore it: their owner moves them.
func apply_pull(pull: Vector2) -> void:
	if not is_mirror:
		_pull += pull


func _update_slow(delta: float) -> void:
	if _slow_left <= 0.0:
		return
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_mult = 1.0
		_set_tint(Color.WHITE)


## Mirror: its owner says it's now at `pos` (in our coordinates).
func mirror_report(pos: Vector2) -> void:
	if _follow == null:
		_follow = NetFollow.new()
	if _follow.report(pos):
		position = pos


func _physics_process(delta: float) -> void:
	if is_mirror:
		if _follow:
			global_position = _follow.step(global_position, delta)
		return

	_update_slow(delta)
	var target := _pick_target()
	walk_velocity = _desired_velocity(target, delta)
	velocity = walk_velocity

	velocity += _knockback_velocity + _pull
	_pull = Vector2.ZERO
	_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO

	move_and_slide()
	_stay_in_bounds()
	if steering.is_valid():
		_track_stuck(target, delta)
	_after_move(delta)


## See unstick_left.
func _track_stuck(target: Node2D, delta: float) -> void:
	unstick_left = maxf(unstick_left - delta, 0.0)
	if _stuck_from == Vector2.INF:
		_stuck_from = global_position
	_stuck_want += walk_velocity.length() * delta
	_stuck_clock += delta
	if _stuck_clock < STUCK_SAMPLE:
		return
	var near := target != null \
		and global_position.distance_squared_to(target.global_position) < STUCK_NEAR * STUCK_NEAR
	if not near and _stuck_want > 2.0 \
			and global_position.distance_to(_stuck_from) < _stuck_want * STUCK_PROGRESS:
		unstick_left = UNSTICK_TIME
		stuck_count = mini(stuck_count + 1, STUCK_COUNT_MAX)
	elif unstick_left <= 0.0:
		stuck_count = 0
	_stuck_from = global_position
	_stuck_clock = 0.0
	_stuck_want = 0.0


## How it wants to move this frame (before knockback and pulls), given what
## it's after (`target` may be null). Subclasses override this for new
## behaviour; the default walks straight at the target.
func _desired_velocity(target: Node2D, _delta: float) -> Vector2:
	if target == null:
		return Vector2.ZERO
	if global_position.distance_to(target.global_position) <= STOP_DISTANCE:
		return Vector2.ZERO
	var dir := global_position.direction_to(target.global_position)
	if steering.is_valid():
		dir = steering.call(self, target)
	return dir * speed * _slow_mult


## Which way its sprite should face along x: -1 left, 1 right, 0 no clear
## direction (keep facing as is). Goes by its walk, so knockback and pulls
## don't turn it around. Mirrors have no walk of their own (their owner moves
## them), so they go by how they moved since the last call; call it once a
## frame.
func facing_x() -> float:
	var dx := walk_velocity.x
	if is_mirror:
		dx = 0.0 if is_nan(_facing_last_x) else global_position.x - _facing_last_x
		_facing_last_x = global_position.x
	return signf(dx) if absf(dx) > 0.1 else 0.0


## Called after it has moved each physics frame (owner's copy only).
func _after_move(_delta: float) -> void:
	pass


## Its CollisionShape2D child (looked up once), or null if it has none.
func _collision_shape() -> CollisionShape2D:
	if not _shape_looked_up:
		_shape_node = get_node_or_null("CollisionShape2D") as CollisionShape2D
		_shape_looked_up = true
	return _shape_node


## Roughly half its size (its collision rectangle, scaled for elites).
func half_extent() -> float:
	var shape_node := _collision_shape()
	if shape_node and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size * scale.abs()
		return (size.x + size.y) / 4.0
	return 12.0


## Squads game: keep the whole enemy on its own squad's map.
func _stay_in_bounds() -> void:
	if not move_bounds.has_area():
		return
	var half := Vector2.ZERO
	var shape_node := _collision_shape()
	if shape_node and shape_node.shape is RectangleShape2D:
		half = (shape_node.shape as RectangleShape2D).size / 2.0 * scale.abs()
	global_position = global_position.clamp(move_bounds.position + half, move_bounds.end - half)


## A Decoy luring us (scripts/equipment/decoy.gd), the nearest if several
## are; otherwise an objective after us (the nearest), otherwise the nearest
## player.
func _pick_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for decoy in _group(&"decoys"):
		if is_instance_valid(decoy) and decoy.lures(global_position):
			var d := global_position.distance_squared_to(decoy.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = decoy
	if nearest:
		return nearest
	var goal := _objective_target()
	return goal if goal else _nearest_player()


## Objective waves: the nearest thing in the "objective_targets" group whose
## lures(enemy) says it wants us (the crystal, the VIP, ...), or null.
func _objective_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for thing in _group(&"objective_targets"):
		if is_instance_valid(thing) and thing.lures(self):
			var d := global_position.distance_squared_to(thing.global_position)
			if d < best_dist:
				best_dist = d
				best = thing
	return best


## Distance to the nearest player (ours or another squad's), or INF.
func nearest_player_distance() -> float:
	var player := _nearest_player()
	return global_position.distance_to(player.global_position) if player else INF


## Our own players, and (squads game) other squads' players on our map.
func _nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for group: StringName in [&"players", &"remote_players"]:
		for player in _group(group):
			if not is_instance_valid(player):
				continue
			var d := global_position.distance_squared_to(player.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = player
	return nearest


## The nodes in `group` as of the start of this physics frame (shared by every
## enemy, so each frame fetches each group once instead of once per enemy).
## A node that left the group this frame may still be listed, and one freed
## with free() may be invalid: callers check. (Untyped, so a freed node can
## be looped over and checked.)
func _group(group: StringName) -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _group_frame:
		_group_frame = frame
		_group_cache.clear()
	if not _group_cache.has(group):
		_group_cache[group] = Array(get_tree().get_nodes_in_group(group))
	return _group_cache[group]
