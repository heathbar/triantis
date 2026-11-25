extends Deployable
## Turret: stands where it was placed and shoots the nearest enemy in range.
## Its shots are the owner's (they get the kills). Engineering raises its
## range and fire rate (scripts/equipment.gd).

const Projectile := preload("res://scripts/projectile.gd")

## The barrel art points right; it turns about PIVOT (texture pixels), which
## sits on the turret's position, and is flipped upright when it aims left.
## Shots start at its tip, BARREL px out from the pivot.
const TEXTURE := preload("res://assets/weapons/equipment/turret.png")
const PIVOT := Vector2(9, 6)
const BARREL := 14.0
## The base (a stand): static, drawn under the barrel, with the top of its
## post (BASE_ANCHOR, texture pixels) on the barrel's pivot.
const BASE_TEXTURE := preload("res://assets/weapons/equipment/turret-base.png")
const BASE_ANCHOR := Vector2(10, 2)
## For the time ring round it.
const SIZE := 22.0
const SHOT_SPEED := 480.0

var _cooldown := 0.0
var _aim := 0.0


func _ready() -> void:
	super()


func _tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var target := _nearest_target()
	if target:
		_aim = global_position.direction_to(target.global_position).angle()
		if _cooldown == 0.0:
			_fire()
	queue_redraw()


func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in enemies_within(global_position, stats["range"]):
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _fire() -> void:
	_cooldown = stats["interval"]
	var direction := Vector2.from_angle(_aim)
	var shot := Projectile.new()
	shot.direction = direction
	shot.damage = int(stats["damage"])
	shot.knockback = stats.get("knockback", 0.0)
	shot.speed = SHOT_SPEED
	# A little past the range, so it reaches an enemy at the edge of it.
	shot.lifetime = (stats["range"] + 30.0) / SHOT_SPEED
	shot.size = Vector2(4, 2)
	shot.shooter = credit()
	shot.from_equipment = true
	shot.position = global_position + direction * BARREL  # before add_child
	get_parent().add_child(shot)


func _draw() -> void:
	var color := owner_color()
	# Range: a faint line round the edge, like the Tesla Coil's.
	var range_color := color
	range_color.a = 0.15
	draw_arc(Vector2.ZERO, stats.get("range", 0.0), 0.0, TAU, 64, range_color, 1.0)
	# The base, then the barrel on top of it, towards its aim.
	draw_texture(BASE_TEXTURE, -BASE_ANCHOR)
	var flip := -1.0 if Vector2.from_angle(_aim).x < 0.0 else 1.0
	draw_set_transform(Vector2.ZERO, _aim, Vector2(1.0, flip))
	draw_texture(TEXTURE, -PIVOT)
	draw_set_transform(Vector2.ZERO, 0.0)
	draw_time_ring(SIZE / 2.0 + 3.0, color.lightened(0.3))
	draw_pack_up_hint()
