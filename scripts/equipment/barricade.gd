extends Deployable
## Barricade: a wall put down just in front of the player, across the way
## they face. Enemies can't walk through it (they slide along it, or push
## against it), but every enemy touching it wears it down: each one costs it
## its barricade_wear (1 for most; brutes far more) of `health` every
## WEAR_TICK seconds until it breaks. Players and
## shots pass straight through. Engineering makes it tougher
## (scripts/equipment.gd).

## Physics layer 3: enemies collide with it (chasesplayer.gd adds it to their
## mask); players don't.
const THICKNESS := 10.0
## The wall art: drawn along the wall (its length runs along the art's
## width, repeating if the wall is longer) and ART_THICKNESS thick, a little
## wider than the collision.
const TEXTURE := preload("res://assets/weapons/equipment/barricade.png")
const ART_THICKNESS := 16.0
const HIT_FLASH := Color(1.6, 1.6, 1.6)
## How far in front of the player's centre the wall goes up.
const OFFSET := 34.0
const WEAR_TICK := 0.5

var health := 1
var _wear_timer := WEAR_TICK
var _touch: Area2D
var _hit_flash := 0.0


func _ready() -> void:
	super()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	health = int(stats.get("health", 40))
	if is_instance_valid(owner_player):
		rotation = owner_player.body.rotation
		position += Vector2.from_angle(rotation) * OFFSET
	var size := Vector2(THICKNESS, stats.get("length", 100.0))

	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.BARRICADES
	wall.collision_mask = 0
	wall.add_child(_rect_shape(size))
	add_child(wall)

	# Notices enemies pressed up against it.
	_touch = Area2D.new()
	_touch.collision_layer = 0
	_touch.collision_mask = PhysicsLayers.ENEMIES
	_touch.monitorable = false
	_touch.add_child(_rect_shape(size + Vector2(6, 6)))
	add_child(_touch)


func _rect_shape(size: Vector2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	return shape


func _tick(delta: float) -> void:
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_wear_timer -= delta
	if _wear_timer <= 0.0:
		_wear_timer = WEAR_TICK
		var touching := 0
		for body in _touch.get_overlapping_bodies():
			if body.is_in_group("enemies"):
				var wear: Variant = body.get("barricade_wear")
				touching += int(wear) if wear != null else 1
		if touching > 0:
			health -= touching
			_hit_flash = 0.1
			if health <= 0:
				expire()
				return
	queue_redraw()


func _draw() -> void:
	var length: float = stats.get("length", 100.0)
	# The wall: the art turned to run along local y (the wall's length).
	draw_set_transform(Vector2.ZERO, PI / 2.0)
	draw_texture_rect(TEXTURE, Rect2(-length / 2.0, -ART_THICKNESS / 2.0, length, ART_THICKNESS), true,
		HIT_FLASH if _hit_flash > 0.0 else Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0)
	# Health along the wall, then time left.
	var full := int(stats.get("health", 40))
	var left := clampf(float(health) / full, 0.0, 1.0)
	var side := ART_THICKNESS / 2.0
	draw_rect(Rect2(-side - 4.0, -length / 2.0, 2.0, length), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(-side - 4.0, length / 2.0 - length * left, 2.0, length * left),
		Color(0.4, 0.9, 0.4))
	var time_left := time_left_fraction()
	draw_rect(Rect2(side + 2.0, length / 2.0 - length * time_left, 2.0, length * time_left),
		Color(1, 1, 1, 0.5))

