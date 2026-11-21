extends StaticBody2D
## A boss's body in the world (scripts/bosses/boss.gd): the Lighthouse, or
## the Quartet's core and each of its pieces. It's shot, swung at and hit by
## equipment like an enemy (it's in the "enemies" group, on the enemy layer),
## hurts players who touch it (contact_damage), and blocks players and
## enemies. It holds no health itself: every hit goes to its boss, which
## decides what it's worth (`boss.on_body_hit`).
##
## Where a hit came from matters to some bosses (the Lighthouse's armoured
## front), so damage dealers call BossBody.deal() instead of take_damage():
## it passes the hit's position, and whether it came from equipment, which
## bosses shrug off more of. Anything else calling take_damage still works;
## the position is then guessed from the knockback or the source.
##
## Freeze Ray slows, gravity pulls and knockback reach the boss through
## on_body_slow / on_body_pull; it decides how much of them to feel.

const HIT_FLASH := 0.12

## The boss this belongs to (set before it enters the tree).
var boss: Node2D
## Which of the boss's bodies this is (the boss's own numbering).
var part := 0
var radius := 30.0
## A box instead of a circle (full size, along its rotation), or zero.
var box_size := Vector2.ZERO
## Half hearts a player loses touching it.
var contact_damage := 2
## Barricades it leans on don't wear down (it isn't trying to get through).
var barricade_wear := 0
## Draws it: painter.call(self) from _draw. The boss sets it.
var painter := Callable()
## Seconds left of the red flash from the last hit.
var flash := 0.0
## Out of the fight (a cracked Quartet piece): shots pass through, it
## doesn't hurt to touch, and nothing targets it.
var dormant := false:
	set(value):
		dormant = value
		_apply_state()
## Seconds alive, for animation.
var age := 0.0


## Hurts `enemy` by `amount` from `source` (credited player, may be null):
## a boss body gets where the hit landed and whether it was equipment, any
## other enemy a plain take_damage.
static func deal(enemy: Node, amount: int, source: Node, knockback: Vector2, at: Vector2,
		from_equipment := false) -> void:
	if enemy.has_method("boss_hit"):
		enemy.boss_hit(amount, source, at, from_equipment)
	else:
		enemy.take_damage(amount, source, knockback)


func _ready() -> void:
	z_as_relative = false
	z_index = 0
	collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	if box_size != Vector2.ZERO:
		var rect := RectangleShape2D.new()
		rect.size = box_size * 0.9
		shape.shape = rect
	else:
		var circle := CircleShape2D.new()
		circle.radius = radius * 0.9
		shape.shape = circle
	add_child(shape)
	_apply_state()


func _apply_state() -> void:
	if not is_inside_tree():
		return
	if dormant:
		collision_layer = 0
		remove_from_group("enemies")
	else:
		collision_layer = PhysicsLayers.ENEMIES
		add_to_group("enemies")


func _physics_process(delta: float) -> void:
	age += delta
	flash = maxf(flash - delta, 0.0)
	queue_redraw()


func is_dead() -> bool:
	return dormant or not is_instance_valid(boss)


func half_extent() -> float:
	return radius * 0.85


func boss_hit(amount: int, source: Node, at: Vector2, from_equipment := false) -> void:
	if is_dead() or amount <= 0:
		return
	flash = HIT_FLASH
	boss.on_body_hit(self, amount, source, at, from_equipment)


## A plain hit (a bomber's blast, or anything not using deal()).
func take_damage(amount: int, source: Node = null, knockback := Vector2.ZERO) -> void:
	var at := global_position
	if knockback != Vector2.ZERO:
		at = global_position - knockback.normalized() * radius
	elif is_instance_valid(source) and source is Node2D:
		at = (source as Node2D).global_position
	# Only players' own guns and swings go through deal(): anything else
	# counts as equipment.
	boss_hit(amount, source, at, true)


func apply_slow(mult: float, seconds: float) -> void:
	if not is_dead():
		boss.on_body_slow(self, mult, seconds)


func apply_pull(pull: Vector2) -> void:
	if not is_dead():
		boss.on_body_pull(self, pull)


func apply_knockback(_knockback: Vector2) -> void:
	pass  # Far too heavy.


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
