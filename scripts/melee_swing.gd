extends Node2D
## A player's melee swing (started by Player._try_melee in
## scripts/player/character_body.gd): the weapon's image appears at one edge
## of the swing's arc, sweeps across it and disappears.
##
## It hits as it goes: each frame, every enemy in the slice of the arc the
## weapon just passed through (and within reach) is hit, once per swing. So
## enemies are hit where the weapon is drawn, even if they (or the player)
## moved since the swing began.
##
## Weapon images are drawn pointing up-right: handle in the bottom-left
## corner, business end in the top-right (see assets/weapons/).

## Each enemy this swing hits, right after the hit (it may have died).
signal hit_enemy(enemy: Node)

const BossBody := preload("res://scripts/bosses/boss_body.gd")

## Longest a swing is shown, in seconds. Faster weapons swing faster, so the
## image never outlasts the weapon's interval.
const MAX_DURATION := 0.2
## Share of the weapon's interval the swing may take, at most.
const INTERVAL_SHARE := 0.4
## Each melee type's image is assets/weapons/melee/<type id>.png (e.g.
## knife.png). Types without one yet use this.
const DEFAULT_TEXTURE := preload("res://assets/weapons/melee/sledgehammer.png")
const TEXTURE_PATH := "res://assets/weapons/melee/%s.png"

## Pixels from the player's centre, and the arc's width in radians. Set
## (with rotation, the direction faced) before adding it as a child.
var reach := 30.0
## Pixels from the player's centre to the edge of their body: the handle
## starts here, so the weapon swings through the air in front of the player.
var inner := 0.0
var arc := PI / 2.0
## Seconds between the weapon's swings (caps how long this one lasts).
var interval := 0.5
## The weapon's type id (scripts/melee.gd), picks the image.
var weapon_type := ""
## Sweeps clockwise (on screen) when true, counter-clockwise when false.
var clockwise := true
## Who swings (credited with the hits; knockback pushes away from them), and
## what each hit does.
var attacker: Node2D
var damage := 1
var knockback := 0.0
## Optional: func(enemy, damage) -> int, the damage a hit on that enemy does
## instead (Braid Class Mods). Unset: `damage`.
var damage_for := Callable()

var _age := 0.0
var _duration := MAX_DURATION
var _sprite: Sprite2D
## Texture pixels along the image's diagonal where the handle starts.
var _base := 0.0
## Where the weapon pointed last frame (radians, relative to `rotation`).
var _last_angle := 0.0
## Instance ids of enemies this swing has already hit.
var _hit := {}

## Texture -> Vector2(handle start, tip): how far the nearest and furthest
## opaque pixels lie along the up-right diagonal from the bottom-left corner,
## in texture pixels (see _extent).
static var _extents := {}


static func texture_for(type_id: String) -> Texture2D:
	var path := TEXTURE_PATH % type_id
	if not type_id.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return DEFAULT_TEXTURE


func _ready() -> void:
	z_index = 5
	_duration = minf(MAX_DURATION, interval * INTERVAL_SHARE)
	var texture := texture_for(weapon_type)
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Pivot on the image's bottom-left corner (the handle end).
	_sprite.centered = false
	_sprite.offset = Vector2(0.0, -texture.get_height())
	# Scale the image (evenly) so the weapon itself, not the empty corners of
	# the image, spans from the edge of the body out to the swing's reach,
	# where hits stop.
	var extent := _extent(texture)
	_base = extent.x
	_sprite.scale = Vector2.ONE * (maxf(reach - inner, 1.0) / maxf(extent.y - extent.x, 1.0))
	add_child(_sprite)
	_last_angle = _angle_at(0.0)
	_place(0.0)
	_hit_between(_last_angle, _last_angle)


func _process(delta: float) -> void:
	_age += delta
	var t := minf(_age / _duration, 1.0)
	var angle := _angle_at(t)
	# Hit whatever the weapon passed through since last frame, finishing the
	# arc on the last frame even if it was a long one.
	_hit_between(_last_angle, angle)
	_last_angle = angle
	if t >= 1.0:
		queue_free()
		return
	_place(t)


## Hits every enemy not hit yet this swing that's within reach and overlaps
## the slice of the arc between angles `a` and `b` (relative to `rotation`).
## Enemies overlapping the player always count.
func _hit_between(a: float, b: float) -> void:
	if not is_instance_valid(attacker):
		return
	var low := minf(a, b)
	var high := maxf(a, b)
	var centre := attacker.global_position
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if _hit.has(enemy.get_instance_id()):
			continue
		if not enemy.has_method("take_damage") or enemy.is_dead():
			continue
		var to_enemy := enemy.global_position - centre
		var dist := to_enemy.length()
		var enemy_half := Deployable.half_extent(enemy, to_enemy)
		if dist - enemy_half > reach:
			continue
		# The slice is widened by however much of it the enemy's body covers.
		if dist > enemy_half:
			var slack := atan2(enemy_half, dist)
			var at := wrapf(to_enemy.angle() - global_rotation, -PI, PI)
			if at + slack < low or at - slack > high:
				continue
		_hit[enemy.get_instance_id()] = true
		var away := to_enemy.normalized() if dist > 0.0 else Vector2.from_angle(global_rotation)
		var amount := int(damage_for.call(enemy, damage)) if damage_for.is_valid() else damage
		BossBody.deal(enemy, amount, attacker, away * knockback, centre)
		hit_enemy.emit(enemy)


## Where the weapon points `t` (0..1) of the way through the swing, in
## radians relative to `rotation` (the direction the player faced).
func _angle_at(t: float) -> float:
	var eased := ease(t, -1.6)  # quick through the middle, like a real swing
	var from := -arc / 2.0 if clockwise else arc / 2.0
	return lerpf(from, -from, eased)


## Vector2(handle start, tip): how far the image's nearest and furthest
## opaque pixels lie along the up-right diagonal, measured from the
## bottom-left corner (the pivot).
static func _extent(texture: Texture2D) -> Vector2:
	if _extents.has(texture):
		return _extents[texture]
	# Fallback: the whole diagonal.
	var extent := Vector2(0.0, texture.get_size().length())
	var image := texture.get_image()
	if image:
		if image.is_compressed():
			image.decompress()
		var h := image.get_height()
		var near := INF
		var far := 0.0
		for y in h:
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.1:
					# This pixel's nearest and furthest corners, projected
					# onto the diagonal.
					near = minf(near, (x + (h - 1.0 - y)) / sqrt(2.0))
					far = maxf(far, (x + 1.0 + (h - y)) / sqrt(2.0))
		if far > 0.0:
			extent = Vector2(near, far)
	_extents[texture] = extent
	return extent


## Points the image `t` (0..1) of the way across the arc.
func _place(t: float) -> void:
	var angle := _angle_at(t)
	# The image points up-right (-45 degrees); turn it to point along `angle`.
	_sprite.rotation = angle + PI / 4.0
	# Slide the pivot out so the handle's end sits at the edge of the body.
	_sprite.position = Vector2.from_angle(angle) * (inner - _base * _sprite.scale.x)
	# Pop in and out instead of blinking.
	_sprite.modulate.a = clampf(minf(t, 1.0 - t) * 8.0, 0.0, 1.0)
