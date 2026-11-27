extends Deployable
## Barricade: a ring of wall put up all the way round the player, `radius`
## from where they stand, guarding them from every side. Enemies can't walk
## through it (they slide along it, or push against it), but every enemy
## touching it wears it down: each one costs it its barricade_wear (1 for
## most; brutes far more) of `health` every WEAR_TICK seconds until it breaks.
## Players and shots pass straight through. Engineering makes it bigger and
## tougher (scripts/equipment.gd).
##
## Enemies already inside when it goes up stay inside with the player.

## Physics layer 3: enemies collide with it (chasesplayer.gd adds it to their
## mask); players don't. The ring is SEGMENTS straight pieces this thick.
const THICKNESS := 10.0
const SEGMENTS := 32
## The wall art: drawn along the ring (its length runs along the art's
## width, repeating) and ART_THICKNESS thick, a little wider than the
## collision.
const TEXTURE := preload("res://assets/weapons/equipment/barricade.png")
const ART_THICKNESS := 16.0
const HIT_FLASH := Color(1.6, 1.6, 1.6)
const WEAR_TICK := 0.5

var health := 1
var _wear_timer := WEAR_TICK
var _touch: Area2D
var _hit_flash := 0.0


func _ready() -> void:
	super()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	health = int(stats.get("health", 40))
	var radius := _radius()
	# Each piece a little longer than its share of the ring, so they meet.
	var piece := TAU * radius / SEGMENTS + THICKNESS

	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.BARRICADES
	wall.collision_mask = 0
	add_child(wall)
	# Notices enemies pressed up against it.
	_touch = Area2D.new()
	_touch.collision_layer = 0
	_touch.collision_mask = PhysicsLayers.ENEMIES
	_touch.monitorable = false
	add_child(_touch)
	for i in SEGMENTS:
		var angle := TAU * i / SEGMENTS
		wall.add_child(_piece(Vector2(THICKNESS, piece), angle, radius))
		_touch.add_child(_piece(Vector2(THICKNESS + 6.0, piece), angle, radius))


func _radius() -> float:
	return float(stats.get("radius", 120.0))


## One straight piece of the ring, `angle` round it, its length along the ring.
func _piece(size: Vector2, angle: float, radius: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = Vector2.from_angle(angle) * radius
	shape.rotation = angle
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
	var radius := _radius()
	var piece := TAU * radius / SEGMENTS
	var tint := HIT_FLASH if _hit_flash > 0.0 else Color.WHITE
	var art_w := TEXTURE.get_size().x
	# The wall: one stretch of art per piece, carrying on where the last one
	# left off so the pattern runs unbroken round the ring.
	for i in SEGMENTS:
		var angle := TAU * (i + 0.5) / SEGMENTS
		draw_set_transform(Vector2.from_angle(angle) * radius, angle + PI / 2.0)
		draw_texture_rect_region(TEXTURE,
			Rect2(-piece / 2.0 - 0.5, -ART_THICKNESS / 2.0, piece + 1.0, ART_THICKNESS),
			Rect2(fmod(i * piece, art_w), 0.0, piece + 1.0, TEXTURE.get_size().y), tint)
	draw_set_transform(Vector2.ZERO, 0.0)
	# Health just inside the ring, time left just outside, both counting
	# down clockwise from the top.
	var side := ART_THICKNESS / 2.0
	var full := int(stats.get("health", 40))
	var left := clampf(float(health) / full, 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius - side - 3.0, 0.0, TAU, 96, Color(0.15, 0.15, 0.15), 2.0)
	if left > 0.0:
		draw_arc(Vector2.ZERO, radius - side - 3.0, -PI / 2.0, -PI / 2.0 + TAU * left, 96,
			Color(0.4, 0.9, 0.4), 2.0)
	var time_left := time_left_fraction()
	if time_left > 0.0:
		draw_arc(Vector2.ZERO, radius + side + 3.0, -PI / 2.0, -PI / 2.0 + TAU * time_left, 96,
			Color(1, 1, 1, 0.5), 2.0)
