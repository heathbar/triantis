extends Deployable
## Gravity Well: drags every enemy within `radius` towards its centre at up to
## `pull` pixels per second, on top of their own walking (enough to overpower
## most of it). Bunches them up for mines, goo and grenades. Players aren't
## affected. Engineering makes it reach further (scripts/equipment.gd).

## Inside this distance the pull eases off, so enemies don't jitter about
## the exact centre.
const CORE := 18.0
const COLOR := Color(0.6, 0.35, 1.0)
## The vortex, stretched to fill the radius and turning.
const TEXTURE := preload("res://assets/weapons/equipment/gravity_well.png")
const TEXTURE_ALPHA := 0.6
## Radians per second (negative: anticlockwise, the way the art's arms curl in).
const SPIN := -1.2

var _anim := 0.0


func _tick(delta: float) -> void:
	_anim += delta
	var pull: float = stats["pull"]
	for enemy in enemies_within(global_position, stats["radius"]):
		if not enemy.has_method("apply_pull"):
			continue
		var to_center := global_position - enemy.global_position
		var dist := to_center.length()
		if dist < 1.0:
			continue
		enemy.apply_pull(to_center / dist * pull * minf(dist / CORE, 1.0))
	queue_redraw()


func _draw() -> void:
	var radius: float = stats.get("radius", 0.0)
	if radius > 0.0:
		var s := radius * 2.0 / TEXTURE.get_width()
		draw_set_transform(Vector2.ZERO, _anim * SPIN, Vector2(s, s))
		draw_texture(TEXTURE, -TEXTURE.get_size() / 2.0, Color(1, 1, 1, TEXTURE_ALPHA))
		draw_set_transform(Vector2.ZERO, 0.0)
	draw_time_ring(radius + 2.0, Color(1, 1, 1, 0.5), 1.0)

