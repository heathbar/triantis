extends "res://scripts/equipment/turret.gd"
## Drone: a little flying gun that circles its owner and shoots the nearest
## enemy in range, like a Turret that comes along. Its shots are the owner's.
## If the owner is knocked out it keeps guarding where they fell.
## Engineering raises its range and fire rate (scripts/equipment.gd).

const ORBIT_RADIUS := 30.0
## Radians per second around the owner.
const ORBIT_SPEED := 1.6
## How quickly it catches up with its spot (higher = snappier).
const FOLLOW := 8.0
const DRONE_SIZE := 5.0

var _orbit := 0.0
var _spin := 0.0


func _ready() -> void:
	super()
	_orbit = randf() * TAU
	z_index = 15  # Flies over everything on the ground.


func _tick(delta: float) -> void:
	_orbit += ORBIT_SPEED * delta
	_spin += delta * 30.0
	if is_instance_valid(owner_player):
		var spot: Vector2 = owner_player.global_position + Vector2.from_angle(_orbit) * ORBIT_RADIUS
		global_position = global_position.lerp(spot, 1.0 - exp(-FOLLOW * delta))
	super(delta)


func _draw() -> void:
	var color := owner_color()
	var range_color := color
	range_color.a = 0.15
	draw_arc(Vector2.ZERO, stats.get("range", 0.0), 0.0, TAU, 64, range_color, 1.0)
	# Four rotors on arms, a body, and a little gun pointing at the target.
	for i in 4:
		var arm := Vector2.from_angle(PI / 4.0 + i * PI / 2.0) * DRONE_SIZE
		draw_line(Vector2.ZERO, arm, Color.BLACK, 2.0)
		draw_circle(arm, 3.0, Color(0.1, 0.1, 0.1, 0.6))
		var blade := Vector2.from_angle(_spin + i) * 3.0
		draw_line(arm - blade, arm + blade, Color(0.9, 0.9, 0.9, 0.8), 1.0)
	draw_set_transform(Vector2.ZERO, _aim)
	draw_rect(Rect2(0, -1, DRONE_SIZE + 2.0, 2), Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0)
	draw_circle(Vector2.ZERO, DRONE_SIZE * 0.6, Color.BLACK)
	draw_circle(Vector2.ZERO, DRONE_SIZE * 0.6 - 1.0, color)
	draw_time_ring(DRONE_SIZE + 4.0, color.lightened(0.3), 1.0)


## Too quick for saboteurs to catch, unlike a Turret.
func can_be_sabotaged() -> bool:
	return false
