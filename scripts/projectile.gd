extends Node2D
## A simple projectile: a small white rectangle that flies in a straight line
## and disappears after a while.

const SPEED := 560.0
## Seconds a shot lasts by default (SPEED x LIFETIME = 420 px of range).
const LIFETIME := 0.75
const SIZE := Vector2(6, 2)
const DAMAGE := 10
const BossBody := preload("res://scripts/bosses/boss_body.gd")
## Most enemies one shot can hit in a single physics frame (overkill shots
## going through a tight crowd).
const MAX_HITS_PER_FRAME := 16

var direction := Vector2.RIGHT
## Damage dealt on hit (the shooter sets this from its upgrades).
var damage := DAMAGE
## Pixels the hit enemy is shoved along the shot's direction.
var knockback := 0.0
## Seconds before the shot vanishes, which sets its range (the shooter scales
## it by their range attribute).
var lifetime := LIFETIME
## Pixels per second and rectangle size (the shooter sets these from their gun).
var speed := SPEED
var size := SIZE
## The player who fired this shot; credited with any kill it makes.
var shooter: Node = null
## Fired by equipment (a turret or drone), not the player's own gun: bosses
## take less from it (scripts/bosses/boss_body.gd).
var from_equipment := false
## Overkill (the sniper rifle, Guns "overkill"): when the shot kills an
## enemy it flies on with the damage that enemy didn't need, until it runs
## out or meets one it can't kill. Bosses always stop it.
var overkill := false
## Squads game: another squad's shot, just for show (scripts/net/squad_link.gd).
## It stops at the first enemy it meets but doesn't hurt it (the real shot, in
## their game, does that), and vanishes on leaving `cosmetic_bounds` if set.
var cosmetic := false
var cosmetic_bounds := Rect2()

var _age := 0.0
## The swept rectangle _find_hit queries with, made once and resized per frame.
var _sweep_shape: RectangleShape2D
var _sweep_query: PhysicsShapeQueryParameters2D


func _ready() -> void:
	add_to_group("projectiles")
	rotation = direction.angle()
	z_index = 10


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta

	for _i in MAX_HITS_PER_FRAME:
		var enemy := _find_hit(from, to)
		if not enemy:
			break
		if cosmetic:
			queue_free()
			return
		var left := deal_overkill(enemy, damage, shooter, direction * knockback, global_position,
			from_equipment)
		if not overkill or left <= 0:
			queue_free()
			return
		# A killed enemy leaves the "enemies" group at once, so the next
		# _find_hit skips it and finds whatever is behind it.
		damage = left

	global_position = to
	_age += delta
	if _age >= lifetime or (cosmetic_bounds.has_area() and not cosmetic_bounds.has_point(to)):
		queue_free()


## Deals `amount` to `enemy` (BossBody.deal) and returns the damage it
## didn't need if that killed it, else 0. Bosses and other squads' mirrored
## enemies (whose health lives in another game) always give 0.
static func deal_overkill(enemy: Node, amount: int, source: Node, knockback: Vector2, at: Vector2,
		from_equipment := false) -> int:
	var needed := -1
	if not enemy is BossBody and not enemy.get("is_mirror") and enemy.has_method("is_dead") \
			and enemy.get("health") is int:
		var mult := 1.0
		if enemy.get("damage_taken_multiplier") is float:
			mult = maxf(enemy.damage_taken_multiplier, 0.01)
		needed = ceili(enemy.health / mult)
	BossBody.deal(enemy, amount, source, knockback, at, from_equipment)
	if needed < 0 or not is_instance_valid(enemy) or not enemy.is_dead():
		return 0
	return maxi(amount - needed, 0)


## Sweep the projectile's full rectangle along this frame's path, so that:
## - fast shots can't skip past an enemy between frames,
## - shots that start inside an enemy (point-blank, enemy touching the
##   shooter) still hit; a ray cast would ignore a shape it starts inside,
## - glancing shots hit wherever the visible rectangle overlaps the enemy.
## Returns the hit enemy closest to `from`, or null.
func _find_hit(from: Vector2, to: Vector2) -> Node:
	var best: Node = null
	var best_dist := INF
	for result in get_world_2d().direct_space_state.intersect_shape(_sweep(from, to)):
		var collider: Node2D = result.collider
		if not (collider.is_in_group("enemies") and collider.has_method("take_damage")):
			continue
		var d := from.distance_squared_to(collider.global_position)
		if d < best_dist:
			best_dist = d
			best = collider
	return best


## The query for the shot's rectangle swept from `from` to `to`, against the
## enemy layer (one query object per shot, reused every frame).
func _sweep(from: Vector2, to: Vector2) -> PhysicsShapeQueryParameters2D:
	if _sweep_query == null:
		_sweep_shape = RectangleShape2D.new()
		_sweep_query = PhysicsShapeQueryParameters2D.new()
		_sweep_query.shape = _sweep_shape
		_sweep_query.collision_mask = PhysicsLayers.ENEMIES
	_sweep_shape.size = Vector2(from.distance_to(to) + size.x, size.y)
	_sweep_query.transform = Transform2D(direction.angle(), (from + to) / 2.0)
	return _sweep_query


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), Color.WHITE)
