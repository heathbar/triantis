extends Area2D
## A resource dropped by an eliminated enemy: a small dark blue dot with a
## white rim. The first living player to touch it collects it; the game
## (game_base.gd) then gives every player a copy.
## Living players also pull nearby pickups in (a magnet whose reach grows with
## their harvesting attribute); once caught, a pickup chases that player,
## speeding up, until it reaches them.

signal collected

const RADIUS := 3.0
## White rim so the dot stands out against the ground.
const OUTLINE_WIDTH := 1.0
const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")
## Magnet reach (pixels, from the player's centre) at average harvesting. It
## scales with the square root of the player's harvest rate: about 16px at
## -100 harvesting, 51px at +50, 72px at +100.
const MAGNET_RADIUS := 36.0
## A caught pickup starts at this speed (px/s) and keeps speeding up, so it
## always catches even a fast player running away.
const MAGNET_START_SPEED := 40.0
const MAGNET_ACCEL := 500.0

var _taken := false
## The player this pickup is flying to (null until one comes in range).
var _target: Node2D
var _speed := 0.0


func _ready() -> void:
	add_to_group("pickups")
	z_index = 5
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false

	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# Knocked-out players leave the "players" group: let go of them.
	if _target and (not is_instance_valid(_target) or not _target.is_in_group("players")):
		_target = null
	if not _target:
		_target = _player_in_reach()
		if not _target:
			return
		_speed = MAGNET_START_SPEED
	_speed += MAGNET_ACCEL * delta
	global_position = global_position.move_toward(_target.global_position, _speed * delta)


## The nearest living player whose magnet reaches this pickup, or null.
func _player_in_reach() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for player: Node2D in get_tree().get_nodes_in_group("players"):
		var rate: float = player.harvest_rate if player is Player else 1.0
		var dist := global_position.distance_to(player.global_position)
		if dist <= MAGNET_RADIUS * sqrt(maxf(rate, 0.0)) and dist < best_dist:
			best = player
			best_dist = dist
	return best


func _on_body_entered(body: Node) -> void:
	# Only living players (knocked-out ones leave the "players" group).
	if body.is_in_group("players"):
		collect()


## Gives this pickup out (also used to sweep up leftovers when a wave ends).
func collect() -> void:
	if _taken:
		return
	_taken = true
	collected.emit()
	queue_free()


func _draw() -> void:
	ResourceIcon.draw_dot(self, Vector2.ZERO, RADIUS, OUTLINE_WIDTH)
