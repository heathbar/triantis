extends Deployable
## Decoy: a dummy that stands still and draws every enemy within `lure`
## pixels away from the players (scripts/enemyai/chasesplayer.gd asks
## lures()). Enemies touching it knock off one of its `lives`, then it's
## invulnerable for `invulnerable` seconds; it falls apart when they're gone.
## It never does damage.

const SIZE := Vector2(24, 24)
const HIT_FLASH := 0.15
## Lives shown as separate pips up to this many (else as a bar).
const MAX_PIPS := 12

var lives := 10
var _invulnerable := 0.0
var _hurtbox: Area2D
var _flash := 0.0


func _ready() -> void:
	super()
	add_to_group("decoys")
	lives = int(stats.get("lives", lives))
	# Like the player's hurtbox: notices enemy bodies touching it.
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = PhysicsLayers.ENEMIES
	_hurtbox.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE + Vector2(4, 4)
	shape.shape = rect
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


## True if an enemy at `pos` should come for this decoy instead of a player.
func lures(pos: Vector2) -> bool:
	return lives > 0 and global_position.distance_to(pos) <= stats.get("lure", 0.0)


func _tick(delta: float) -> void:
	_invulnerable = maxf(_invulnerable - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	if _invulnerable == 0.0:
		for body in _hurtbox.get_overlapping_bodies():
			if body.is_in_group("enemies"):
				_hit()
				break
	queue_redraw()


func _hit() -> void:
	lives -= 1
	_invulnerable = stats.get("invulnerable", 2.0)
	_flash = HIT_FLASH
	if lives <= 0:
		remove_from_group("decoys")
		expire()


func _draw() -> void:
	var color := owner_color().lerp(Color(0.6, 0.6, 0.6), 0.6)
	if _flash > 0.0:
		color = Color(1, 0.3, 0.3)
	elif _invulnerable > 0.0 and fmod(_invulnerable, 0.3) < 0.15:
		color = color.lightened(0.4)
	var rect := Rect2(-SIZE / 2.0, SIZE)
	draw_rect(rect.grow(1.0), Color.BLACK)
	draw_rect(rect, color)
	# A target on its chest.
	draw_circle(Vector2.ZERO, 7.0, Color(0.85, 0.1, 0.1))
	draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
	draw_circle(Vector2.ZERO, 2.0, Color(0.85, 0.1, 0.1))
	# Lives left, as pips along the top.
	# (A plain bar once there are too many to tell apart: they grow with the wave.)
	var total := int(stats.get("lives", 10))
	if total > MAX_PIPS:
		var bar := Rect2(-SIZE.x / 2.0 + 1.0, -SIZE.y / 2.0 - 5.0, SIZE.x - 2.0, 3.0)
		draw_rect(bar, Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * lives / total, bar.size.y)),
			Color(1, 0.25, 0.3))
	else:
		var pip := (SIZE.x - 2.0) / total
		for i in total:
			var pip_color := Color(1, 0.25, 0.3) if i < lives else Color(0.2, 0.2, 0.2)
			draw_rect(Rect2(-SIZE.x / 2.0 + 1.0 + i * pip, -SIZE.y / 2.0 - 5.0, pip - 0.6, 3.0), pip_color)
	draw_time_ring(SIZE.x * 0.75, Color(1, 1, 1, 0.5), 1.0)


## Saboteurs go after it (see Deployable.can_be_sabotaged).
func can_be_sabotaged() -> bool:
	return true
