class_name Deployable
extends Node2D
## Base for everything equipment puts into the world (scripts/equipment.gd).
## It belongs to the player who used it (credited with any kills), lasts
## `duration` seconds (0 = until it removes itself) and is cleared when the
## wave ends (game.gd frees the "deployables" group).
##
## Subclasses override _tick(delta) instead of _physics_process.

const Blast := preload("res://scripts/equipment/blast.gd")
const BossBody := preload("res://scripts/bosses/boss_body.gd")
## Seconds of a saboteur's attention that wreck it (see sabotage).
const WRECK_TIME := 1.5
## How it's tinted as a saboteur wrecks it.
const WRECK_TINT := Color(1.0, 0.3, 0.25)

## Which equipment this is (an id from Equipment.LIST).
var kind := ""
## The player who used it. Their kills, their colour.
var owner_player: Node
## The item's numbers in the owner's hands (Equipment.stats()).
var stats := {}
## Seconds it lasts; 0 = until it removes itself.
var duration := 0.0

var _age := 0.0
## Seconds saboteurs have spent wrecking it (see sabotage).
var _wrecked := 0.0


func _ready() -> void:
	add_to_group("deployables")


func _physics_process(delta: float) -> void:
	_age += delta
	if duration > 0.0 and _age >= duration:
		expire()
		return
	_tick(delta)


func _tick(_delta: float) -> void:
	pass


## Gives it `seconds` more to last (never more than its full duration).
func add_time(seconds: float) -> void:
	_age = maxf(_age - seconds, 0.0)


## Saboteurs (scripts/enemyai/saboteur.gd) go after equipment that returns
## true here: things that stay put where they were placed.
func can_be_sabotaged() -> bool:
	return false


## A saboteur spent `delta` seconds wrecking it. Wrecking adds up (it's not
## undone if the saboteur is driven off) and it breaks after WRECK_TIME.
func sabotage(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_wrecked += delta
	modulate = Color.WHITE.lerp(WRECK_TINT, clampf(_wrecked / WRECK_TIME, 0.0, 1.0))
	if _wrecked >= WRECK_TIME:
		expire()


## Its owner can pack it away again by using their equipment beside it, if
## its stats say so ("pickup" > 0: the share of its unused time refunded).
## Only things with a duration (see Player._pack_up_deployable).
const PICKUP_REACH := 20.0


func can_pick_up() -> bool:
	return stats.get("pickup", 0.0) > 0.0 and duration > 0.0 and not is_queued_for_deletion()


## Packs it away: removes it and returns the share of a full cooldown to
## refund (its unused time x "pickup").
func pick_up() -> float:
	var refund := time_left_fraction() * float(stats.get("pickup", 0.0))
	expire()
	return refund


## True when its owner stands close enough to pack it away.
func owner_can_pack_up() -> bool:
	return can_pick_up() and is_instance_valid(owner_player) \
		and owner_player.global_position.distance_to(global_position) <= PICKUP_REACH


## Removes it now (time's up, it was used up, or it was replaced).
func expire() -> void:
	if is_queued_for_deletion():
		return
	queue_free()


## 1 when just placed, falling to 0 as it runs out (1 for ever if it has no
## duration).
func time_left_fraction() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(1.0 - _age / duration, 0.0, 1.0)


func owner_color() -> Color:
	if is_instance_valid(owner_player):
		return owner_player.color
	return Color.WHITE


## The owner, if they still exist (for kill credit), else null.
func credit() -> Node:
	return owner_player if is_instance_valid(owner_player) else null


## Living enemies whose bodies reach within `radius` of `center`.
func enemies_within(center: Vector2, radius: float) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("take_damage") or enemy.is_dead():
			continue
		if center.distance_to(enemy.global_position) - half_extent(enemy) <= radius:
			found.append(enemy)
	return found


## Hurts every enemy within `radius` of `center` (world position), shoving
## them outwards by `knockback` pixels, and shows the explosion.
func explode(center: Vector2, radius: float, damage: int, knockback := 0.0) -> void:
	for enemy in enemies_within(center, radius):
		var away := center.direction_to(enemy.global_position)
		if away == Vector2.ZERO:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		BossBody.deal(enemy, damage, credit(), away * knockback, center, true)
	var blast := Blast.new()
	blast.radius = radius
	var world := get_parent() as Node2D
	blast.position = world.to_local(center)  # before add_child
	world.add_child(blast)


## Roughly half an enemy's size (its collision rectangle, scaled for elites).
static func half_extent(enemy: Node2D) -> float:
	var shape_node := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size * enemy.scale.abs()
		return (size.x + size.y) / 4.0
	return 12.0


## Draws `texture` centred on `at` (whole-pixel corner, so odd sizes stay
## crisp). The equipment art is in assets/weapons/equipment/.
func draw_centered(texture: Texture2D, at := Vector2.ZERO, tint := Color.WHITE) -> void:
	draw_texture(texture, at - (texture.get_size() / 2.0).floor(), tint)


## While its owner could pack it away: a blinking dashed ring round it.
func draw_pack_up_hint() -> void:
	if not owner_can_pack_up():
		return
	if fmod(_age, 0.6) < 0.3:
		return
	var segments := 8
	for i in segments:
		var a := TAU * i / segments
		draw_arc(Vector2.ZERO, PICKUP_REACH - 4.0, a, a + TAU / segments / 2.0, 6, Color.WHITE, 1.0)


## A thin ring that empties clockwise as the time runs out.
func draw_time_ring(radius: float, color: Color, width := 2.0) -> void:
	if duration <= 0.0:
		return
	var left := time_left_fraction()
	var back := color
	back.a *= 0.25
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, back, width)
	draw_arc(Vector2.ZERO, radius, -PI / 2.0, -PI / 2.0 + TAU * left, 48, color, width)
