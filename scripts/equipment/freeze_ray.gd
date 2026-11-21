extends Deployable
## Freeze Ray: a cone of cold that comes out of the owner and points wherever
## they face, for its duration. Enemies it touches can't move until `freeze`
## seconds after they leave it (players are never frozen; bosses only slow,
## at boss strength). It ends early if the owner is knocked out.
## Engineering makes it reach further and freeze for longer
## (scripts/equipment.gd).

const COLOR := Color(0.55, 0.85, 1.0)
var _anim := 0.0


func _ready() -> void:
	super()
	_follow_owner()


func _tick(delta: float) -> void:
	if not is_instance_valid(owner_player) or owner_player.is_dead():
		expire()
		return
	_anim += delta
	_follow_owner()
	var facing := Vector2.from_angle(rotation)
	var half_arc := deg_to_rad(stats["arc"]) / 2.0
	for enemy in enemies_within(global_position, stats["range"]):
		var to_enemy := enemy.global_position - global_position
		var dist := to_enemy.length()
		var half := half_extent(enemy)
		# Enemies on top of the player count; otherwise the cone is widened by
		# however much of it the enemy's body covers.
		if dist > half and absf(facing.angle_to(to_enemy)) > half_arc + atan2(half, dist):
			continue
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(0.0, stats["freeze"])
	queue_redraw()


func _follow_owner() -> void:
	if is_instance_valid(owner_player):
		global_position = owner_player.global_position
		rotation = owner_player.body.rotation


func _draw() -> void:
	var reach: float = stats.get("range", 0.0)
	var half_arc := deg_to_rad(stats.get("arc", 0.0)) / 2.0
	var points := PackedVector2Array([Vector2.ZERO])
	var steps := 20
	for i in steps + 1:
		points.append(Vector2.from_angle(lerpf(-half_arc, half_arc, i / float(steps))) * reach)
	var fill := COLOR
	fill.a = 0.22 + 0.05 * sin(_anim * 8.0)
	draw_colored_polygon(points, fill)
	# Frosty streaks rushing outwards.
	for i in 6:
		var angle := lerpf(-half_arc, half_arc, (i + 0.5) / 6.0)
		var t := fmod(_anim * 1.6 + i * 0.37, 1.0)
		var dir := Vector2.from_angle(angle)
		var streak := Color(1, 1, 1, 0.5 * (1.0 - t))
		draw_line(dir * reach * t, dir * reach * minf(t + 0.12, 1.0), streak, 1.0)
	var edge := COLOR
	edge.a = 0.6
	draw_arc(Vector2.ZERO, reach, -half_arc, half_arc, steps, edge, 1.0)
	# Time left, as a bar along the cone's far edge.
	var left := time_left_fraction()
	draw_arc(Vector2.ZERO, reach + 3.0, -half_arc, -half_arc + 2.0 * half_arc * left, steps,
		Color(1, 1, 1, 0.6), 1.0)
