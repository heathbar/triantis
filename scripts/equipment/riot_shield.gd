extends Deployable
## Riot Shield: carried in front of its owner for its duration. Enemies that
## come within `reach` are shoved aside (`push`, pixels per second, sideways
## from the way the owner is going, like a bow wave) and bashed for `damage`
## every BASH_INTERVAL, and while it's up enemies can't hurt the owner by
## touching them (Player.set_contact_shield). Bosses still can, and aren't
## shoved. Other squads' enemies (mirrors) can't be shoved either, but can't
## hurt the owner. Engineering raises the reach and the damage
## (scripts/equipment.gd).

const COLOR := Color(0.55, 0.75, 1.0)
## Seconds between bashes of the same enemy.
const BASH_INTERVAL := 0.5
## How far in front of the owner the shield is drawn.
const SHIELD_OFFSET := 11.0
const SHIELD_ARC := deg_to_rad(110.0)

var _facing := Vector2.RIGHT
## Enemy instance id -> seconds until it can be bashed again.
var _bashed := {}


func _ready() -> void:
	super()
	z_index = 5
	for other in get_tree().get_nodes_in_group("deployables"):
		if other != self and other.get("kind") == kind and other.get("owner_player") == owner_player:
			other.expire()
	if is_instance_valid(owner_player):
		owner_player.set_contact_shield(self, true)


func _exit_tree() -> void:
	if is_instance_valid(owner_player):
		owner_player.set_contact_shield(self, false)


func _tick(delta: float) -> void:
	if not is_instance_valid(owner_player) or owner_player.is_dead():
		expire()
		return
	global_position = owner_player.global_position
	var moving: Vector2 = owner_player.velocity
	if moving.length() > 10.0:
		_facing = moving.normalized()
	else:
		_facing = Vector2.from_angle(owner_player.body.rotation)
	for id in _bashed.keys():
		_bashed[id] -= delta
		if _bashed[id] <= 0.0:
			_bashed.erase(id)
	for enemy in enemies_within(global_position, stats["reach"]):
		var away := global_position.direction_to(enemy.global_position)
		if away == Vector2.ZERO:
			away = _facing.orthogonal()
		# Mostly sideways, out of the owner's path, a little forward.
		var side := _facing.orthogonal()
		if side.dot(away) < 0.0:
			side = -side
		var shove := (side * 0.8 + away * 0.6).normalized()
		if not enemy is BossBody and enemy.has_method("apply_pull"):
			enemy.apply_pull(shove * stats["push"])
		var id := enemy.get_instance_id()
		if not _bashed.has(id):
			_bashed[id] = BASH_INTERVAL
			BossBody.deal(enemy, int(stats["damage"]), credit(), shove * 6.0, enemy.global_position, true)
	queue_redraw()


func _draw() -> void:
	var angle := _facing.angle()
	var glow := COLOR
	glow.a = 0.18
	draw_circle(Vector2.ZERO, stats.get("reach", 30.0), glow)
	draw_arc(Vector2.ZERO, SHIELD_OFFSET, angle - SHIELD_ARC / 2.0, angle + SHIELD_ARC / 2.0, 12,
		Color.BLACK, 4.0)
	draw_arc(Vector2.ZERO, SHIELD_OFFSET, angle - SHIELD_ARC / 2.0, angle + SHIELD_ARC / 2.0, 12,
		COLOR, 2.0)
	draw_time_ring(SHIELD_OFFSET + 5.0, COLOR, 1.0)
