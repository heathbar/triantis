extends Deployable
## Healing Bubble: a dome where it was placed.
## - A knocked-out player inside it is revived with 1 heart (once per player
##   per bubble, and only while a teammate is still up: once the whole squad
##   is down the run, or the squad's wave, is already lost).
## - A player who stays inside for `heal_time` seconds straight (3s) gets half
##   a heart back, again every `heal_time` while they stay and are missing
##   health. Their HUD flashes the half heart that's coming back
##   (Player.set_healing).
## Engineering makes it bigger and last longer (scripts/equipment.gd).

const COLOR := Color(0.35, 1.0, 0.55)
## The first-aid kit in the middle.
const TEXTURE := preload("res://assets/weapons/equipment/healing.png")

## Player -> seconds spent inside without leaving (only while missing hearts).
var _inside := {}
## Players this bubble has revived (each only once).
var _revived := {}
var _pulse := 0.0


func _exit_tree() -> void:
	for player in _inside:
		if is_instance_valid(player):
			player.set_healing(self, false)
	_inside.clear()


func _tick(delta: float) -> void:
	_pulse += delta
	var radius: float = stats["radius"]
	var squad_up := not get_tree().get_nodes_in_group("players").is_empty()
	for player: Node2D in get_tree().get_nodes_in_group("all_players"):
		var inside := global_position.distance_to(player.global_position) <= radius
		if inside and player.is_dead():
			if squad_up and not _revived.has(player):
				_revived[player] = true
				player.revive()  # with 1 heart
			_stop_healing(player)
			continue
		if not inside or player.is_dead() or player.health >= player.max_health:
			_stop_healing(player)
			continue
		_inside[player] = _inside.get(player, 0.0) + delta
		player.set_healing(self, true)
		if _inside[player] >= stats["heal_time"]:
			_inside[player] = 0.0
			player.heal(1)
			if player.health >= player.max_health:
				_stop_healing(player)
	queue_redraw()


func _stop_healing(player: Node) -> void:
	if _inside.has(player):
		_inside.erase(player)
		player.set_healing(self, false)


func _draw() -> void:
	var radius: float = stats.get("radius", 0.0)
	var fill := COLOR
	fill.a = 0.13 + 0.04 * sin(_pulse * 3.0)
	draw_circle(Vector2.ZERO, radius, fill)
	var edge := COLOR
	edge.a = 0.7
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, edge, 1.0)
	# The kit in the middle, and the time left around the edge.
	draw_centered(TEXTURE)
	draw_time_ring(radius - 3.0, Color(1, 1, 1, 0.6), 1.0)


## Saboteurs go after it (see Deployable.can_be_sabotaged).
func can_be_sabotaged() -> bool:
	return true
