extends Deployable
## Adrenaline Shot: a boost to its user, not something left in the world.
## While it lasts the owner's speed, fire rate and armor attributes go up by
## the item's "speed", "fire_rate" and "armor" (Player.add_boost); they drop
## back when it runs out or the wave ends. Fire rate speeds up melee swings
## too. A second shot while one is still going replaces it (the clock starts
## over; boosts don't stack). Its cooldown only starts
## counting once it wears off. It rides along with the owner as a pulsing
## ring. Engineering makes it stronger and last longer (scripts/equipment.gd).

const COLOR := Color(1.0, 0.35, 0.45)
const RING_RADIUS := 13.0

var _pulse := 0.0


func _ready() -> void:
	super()
	# The group also holds things that aren't Deployables (blasts, spike traps).
	for other in get_tree().get_nodes_in_group("deployables"):
		if other != self and other is Deployable and other.kind == kind \
				and other.owner_player == owner_player:
			other.expire()
	if is_instance_valid(owner_player):
		owner_player.add_boost(self, {
			"speed": int(stats.get("speed", 0)),
			"fire_rate": int(stats.get("fire_rate", 0)),
			"armor": int(stats.get("armor", 0)),
		})


func _exit_tree() -> void:
	if is_instance_valid(owner_player):
		owner_player.remove_boost(self)


func _tick(delta: float) -> void:
	_pulse += delta
	if is_instance_valid(owner_player):
		global_position = owner_player.global_position
		# The recharge only starts once the boost wears off.
		owner_player.equipment_cooldown = owner_player.equipment_cooldown_total
	queue_redraw()


func _draw() -> void:
	var beat := 0.5 + 0.5 * sin(_pulse * 12.0)
	var glow := COLOR
	glow.a = 0.12 + 0.12 * beat
	draw_circle(Vector2.ZERO, RING_RADIUS + beat * 2.0, glow)
	draw_time_ring(RING_RADIUS + 3.0, COLOR, 1.0)
