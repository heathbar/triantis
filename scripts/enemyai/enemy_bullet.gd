extends Node2D
## A Shooter's bullet (scripts/enemyai/shooter.gd): a slow glowing ball (or,
## given `frames`, a picture pointing its way: the meadow's thistle dart) that
## flies straight and hurts the first of our players it touches. Walls,
## window glass and Barricades stop it; it fades out after LIFETIME.
## Squads games: mirrors fire these too, so each squad's game hurts its own
## players (as the sprayer's stream and bomber blasts do).

const RADIUS := 3.0
const LIFETIME := 2.2
## A player's body counts as reaching this far from their centre (as the
## sprayer's stream sees them).
const PLAYER_HALF := Vector2(13.0, 12.0)
const CORE := Color(1.0, 0.95, 0.7)
const GLOW := Color(1.0, 0.45, 0.15, 0.55)
## Seconds per frame, drawn with `frames`.
const FRAME_TIME := 0.1
const BLOCKERS := PhysicsLayers.WALLS | PhysicsLayers.WINDOWS | PhysicsLayers.BARRICADES

var direction := Vector2.RIGHT
var speed := 130.0
## Half hearts it costs the player it hits.
var damage := 1
## Drawn as these textures in turn (facing right, turned to fly its way)
## instead of a ball, when there are any.
var frames: Array = []

var _age := 0.0


func _ready() -> void:
	add_to_group("enemy_bullets")
	z_index = 10


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, BLOCKERS)
	var wall := get_world_2d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		to = wall.position
	for player: Node2D in get_tree().get_nodes_in_group("players"):
		if player is Player and _touches(player, to):
			player.hurt_by(damage, to)
			queue_free()
			return
	global_position = to
	if not wall.is_empty():
		queue_free()


func _touches(player: Node2D, at: Vector2) -> bool:
	var body := Rect2(player.global_position - PLAYER_HALF - Vector2(RADIUS, RADIUS),
			(PLAYER_HALF + Vector2(RADIUS, RADIUS)) * 2.0)
	return body.has_point(at)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Fades over its last 0.3 s.
	var fade := clampf((LIFETIME - _age) / 0.3, 0.0, 1.0)
	if not frames.is_empty():
		var texture: Texture2D = frames[int(_age / FRAME_TIME) % frames.size()]
		var size := texture.get_size()
		draw_set_transform(Vector2.ZERO, direction.angle(), Vector2.ONE)
		draw_texture(texture, -(size / 2.0).floor(), Color(1.0, 1.0, 1.0, fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_circle(Vector2.ZERO, RADIUS + 2.0, Color(GLOW, GLOW.a * fade))
	draw_circle(Vector2.ZERO, RADIUS, Color(CORE, fade))
