extends StaticBody2D
## Something an objective puts in the world (scripts/objectives/objective.gd):
## the crystal, a shield generator, a nest, the hive, the VIP. It has health
## (an hp bar shows under it once hurt) and draws itself by `kind`.
##
## Touching enemies (our own, not mirrors of other squads') wear it down by
## their contact_damage x contact_multiplier every CONTACT_TICK. A `shootable`
## one is also hurt by players' shots, swings and equipment like an enemy
## is (it's in the "enemies" group; players don't take contact damage from
## it). Either way it emits `damaged`; unless `networked`, it also loses the
## health itself (otherwise the objective sets hp from the host's state).
##
## Enemies walk around it (it's on the barricade layer; a shootable one on
## the enemy layer). It's in the "objective_targets" group: with `lure` set
## (enemy -> bool), enemies it lures come for it
## (scripts/enemyai/chasesplayer.gd).

signal damaged(amount: int)

const CONTACT_TICK := 0.5
const HIT_FLASH := 0.15

## "crystal", "generator", "nest", "hive" or "vip".
var kind := ""
var max_hp := 100
var hp := 100
var radius := 16.0
var color := Color.WHITE
## (Both of these can be set after the structure is added.)
var shootable := false:
	set(value):
		shootable = value
		_apply_collision()
var networked := false
## Damage from each touching enemy per tick is its contact_damage x this.
var contact_multiplier := 1.0
## Immune to everything while true (drawn with a bubble).
var invulnerable := false
## 0..1: how strong the shield shown around it is (just for show).
var shield := 0.0
## enemy -> bool. When set, enemies it returns true for come for it (it can
## be set after the structure is added).
var lure := Callable()
## Off: no collision with anything (it just shows).
var solid := true:
	set(value):
		solid = value
		_apply_collision()

var _contact_timer := 0.0
var _flash := 0.0
var _hurtbox: Area2D
var _age := 0.0


func _ready() -> void:
	add_to_group("objective_structures")
	# (lures() is false while `lure` isn't set.)
	add_to_group("objective_targets")
	collision_mask = 0
	_apply_collision()
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * radius * 1.7
	shape.shape = rect
	add_child(shape)

	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = PhysicsLayers.ENEMIES
	_hurtbox.monitorable = false
	var touch := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + 6.0
	touch.shape = circle
	_hurtbox.add_child(touch)
	add_child(_hurtbox)


## Puts it on the right physics layer, and in "enemies" if players' shots
## and swings should hit it (projectile.gd only hits the enemy layer).
func _apply_collision() -> void:
	if is_dead():
		return  # Wrecked: set_hp took it off every layer and group.
	collision_layer = 0
	if solid:
		collision_layer = PhysicsLayers.ENEMIES if shootable else PhysicsLayers.BARRICADES
	if shootable:
		add_to_group("enemies")
	elif is_in_group("enemies"):
		remove_from_group("enemies")


func lures(enemy: Node) -> bool:
	return not is_dead() and lure.is_valid() and lure.call(enemy)


func is_dead() -> bool:
	return hp <= 0


func _physics_process(delta: float) -> void:
	_age += delta
	_flash = maxf(_flash - delta, 0.0)
	_contact_timer -= delta
	if _contact_timer <= 0.0 and not is_dead():
		_contact_timer = CONTACT_TICK
		var total := 0.0
		for body in _hurtbox.get_overlapping_bodies():
			if body == self or not body.is_in_group("enemies") \
					or body.is_in_group("objective_structures") or body.get("is_mirror"):
				continue
			var amount: Variant = body.get("contact_damage")
			total += (float(amount) if amount != null else 1.0) * contact_multiplier
		if total > 0.0:
			_hurt(maxi(roundi(total), 1))
	queue_redraw()


## Players' shots and swings, and equipment (shootable ones only).
func take_damage(amount: int, _source: Node = null, _knockback := Vector2.ZERO) -> void:
	if not shootable:
		return
	_hurt(amount)


func _hurt(amount: int) -> void:
	if is_dead():
		return
	if invulnerable:
		_flash = HIT_FLASH * 0.5
		return
	_flash = HIT_FLASH
	damaged.emit(amount)
	if not networked:
		set_hp(hp - amount)


## Sets its health; at 0 it's wrecked: it stays where it is (drawn dark) but
## stops blocking, luring and soaking up shots. Above 0 again (rebuilt), it's
## back to normal.
func set_hp(value: int) -> void:
	var was_dead := is_dead()
	hp = clampi(value, 0, max_hp)
	if hp == 0 and is_in_group("objective_structures"):
		remove_from_group("objective_structures")
		remove_from_group("objective_targets")
		remove_from_group("enemies")
		collision_layer = 0
	elif was_dead and hp > 0:
		add_to_group("objective_structures")
		add_to_group("objective_targets")
		_apply_collision()


## Equipment effects meant for enemies don't move it.
func apply_slow(_mult: float, _seconds: float) -> void:
	pass


func apply_pull(_pull: Vector2) -> void:
	pass


func apply_knockback(_knockback: Vector2) -> void:
	pass


func half_extent() -> float:
	return radius * 0.85


func _draw() -> void:
	var c := color
	if is_dead():
		c = c.darkened(0.7)
	elif _flash > 0.0:
		c = Color(1, 0.35, 0.3) if not invulnerable else Color(0.8, 0.9, 1.0)
	match kind:
		"crystal":
			_draw_crystal(c)
		"generator":
			_draw_generator(c)
		"nest", "hive":
			_draw_nest(c)
		"vip":
			_draw_vip(c)
		_:
			draw_circle(Vector2.ZERO, radius, c)
	if shield > 0.0 and not is_dead():
		var bubble := Color(0.5, 0.85, 1.0, 0.12 + 0.18 * shield)
		var r := radius * 1.35 + sin(_age * 3.0) * 1.2
		draw_circle(Vector2.ZERO, r, bubble)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(0.6, 0.9, 1.0, 0.4 + 0.5 * shield), 1.0)
	if hp < max_hp and not is_dead():
		_draw_hp_bar()


func _draw_hp_bar() -> void:
	var width := maxf(radius * 2.0, 28.0)
	var top := Vector2(-width / 2.0, radius + 6.0)
	draw_rect(Rect2(top - Vector2(1, 1), Vector2(width + 2, 6)), Color.BLACK)
	draw_rect(Rect2(top, Vector2(width, 4)), Color(0.25, 0.08, 0.08))
	var frac := float(hp) / float(maxi(max_hp, 1))
	var bar := Color(1, 0.3, 0.25).lerp(Color(0.35, 1, 0.4), frac)
	draw_rect(Rect2(top, Vector2(width * frac, 4)), bar)


func _draw_crystal(c: Color) -> void:
	var bob := sin(_age * 2.0) * 1.6
	var pts := PackedVector2Array([
		Vector2(0, -radius * 1.3 + bob), Vector2(radius * 0.7, bob),
		Vector2(0, radius * 1.0 + bob), Vector2(-radius * 0.7, bob)])
	draw_circle(Vector2(0, radius * 1.05), radius * 0.8, Color(0, 0, 0, 0.25))
	draw_colored_polygon(pts, c)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE.lerp(c, 0.3), 1.0)
	draw_line(pts[0], pts[2], Color(1, 1, 1, 0.5), 1.0)


func _draw_generator(c: Color) -> void:
	var r := radius
	draw_rect(Rect2(-r, -r * 0.7, r * 2.0, r * 1.4), Color(0.15, 0.17, 0.2))
	draw_rect(Rect2(-r, -r * 0.7, r * 2.0, r * 1.4), c, false, 1.0)
	if not is_dead():
		var spin := _age * 4.0
		for i in 3:
			var a := spin + i * TAU / 3.0
			draw_line(Vector2.ZERO, Vector2.from_angle(a) * r * 0.55, c, 2.0)
		draw_circle(Vector2.ZERO, r * 0.22, Color.WHITE)
	else:
		draw_line(Vector2(-r, -r * 0.7), Vector2(r, r * 0.7), Color(0.6, 0.2, 0.2), 2.0)


func _draw_nest(c: Color) -> void:
	var r := radius
	var pulse := 1.0 + sin(_age * (3.0 if kind == "nest" else 1.8)) * 0.05
	var lumps := 9 if kind == "hive" else 7
	for i in lumps:
		var a := i * TAU / lumps
		draw_circle(Vector2.from_angle(a) * r * 0.55 * pulse, r * 0.5, c.darkened(0.35))
	draw_circle(Vector2.ZERO, r * 0.7 * pulse, c)
	draw_circle(Vector2.ZERO, r * 0.3, Color(0.1, 0.02, 0.1))


func _draw_vip(c: Color) -> void:
	var r := radius
	draw_circle(Vector2.ZERO, r, Color.BLACK)
	draw_circle(Vector2.ZERO, r - 2.0, c)
	# A crown.
	var crown := PackedVector2Array([
		Vector2(-r * 0.55, -r * 0.05), Vector2(-r * 0.55, -r * 0.6), Vector2(-r * 0.27, -r * 0.3),
		Vector2(0, -r * 0.75), Vector2(r * 0.27, -r * 0.3), Vector2(r * 0.55, -r * 0.6),
		Vector2(r * 0.55, -r * 0.05)])
	draw_colored_polygon(crown, Color(1, 0.95, 0.6))
	draw_polyline(crown + PackedVector2Array([crown[0]]), Color.BLACK, 1.0)
