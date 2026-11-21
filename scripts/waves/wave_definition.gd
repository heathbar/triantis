class_name WaveDefinition
extends Resource
## Everything that describes a single wave. Each wave is its own .tres file in
## res://data/waves/ so it can be tuned in the Inspector.
##
## Adding a property: add an @export var with a sensible default. Existing
## .tres files pick up the default automatically, so only the waves that need
## a different value have to be edited.

## Optional flavour name shown under "WAVE N" (leave blank for none).
@export var display_name := ""
## How long the wave lasts. It ends when this runs out, whatever is left alive.
@export_range(5.0, 600.0, 1.0, "suffix:s") var duration := 30.0
## The enemies in this wave.
@export var enemy_groups: Array[WaveEnemyGroup] = []

@export_group("Spawning")
## Enemies spawned the instant the wave starts.
@export_range(0, 100, 1) var opening_spawn := 3
## The remaining enemies are spread evenly over this fraction of the wave,
## leaving the rest of the time to finish off stragglers.
@export_range(0.05, 1.0, 0.05) var spawn_window := 0.8

@export_group("Enemy Scaling")
## Multiplies every enemy's health this wave.
@export_range(0.1, 20.0, 0.05) var enemy_health_multiplier := 1.0
## Multiplies every enemy's movement speed this wave.
@export_range(0.1, 5.0, 0.05) var enemy_speed_multiplier := 1.0
## Chance for each enemy to spawn as an elite even in solo play. More players
## add to this (see PlayerScaling on the WaveSet).
@export_range(0.0, 1.0, 0.01) var base_elite_chance := 0.0

@export_group("Boss")
## Makes this a boss wave: the id of its boss (an entry in
## scripts/bosses/boss.gd BOSSES: "lighthouse", "quartet", "crusher" or "vault"), or blank for a
## normal wave. A boss wave lasts until the boss dies; its enemy groups
## become a trickle, their schedule (over `duration`) repeating until then.
@export var boss_id := ""
## The boss's health for one player (more players add to it, see
## scripts/bosses/boss.gd). 0 = the boss's own default.
@export_range(0, 100000, 10) var boss_health := 0

@export_group("Rewards")
## Resources every player receives for surviving the wave (x
## BOSS_REWARD_MULTIPLIER on a boss wave: see reward()).
@export_range(0, 1000, 1) var completion_bonus := 0
## Extra max hearts every player gains for surviving the wave (kept for the
## rest of the run; every heart is refilled between waves anyway).
@export_range(0, 10, 1) var bonus_hearts := 0


## Boss waves pay this many times their completion_bonus: players spend them
## on the boss, not on farming enemies for drops.
const BOSS_REWARD_MULTIPLIER := 3


func is_boss_wave() -> bool:
	return not boss_id.is_empty()


## Resources every player gets for surviving it.
func reward() -> int:
	return completion_bonus * (BOSS_REWARD_MULTIPLIER if is_boss_wave() else 1)


## Total number of enemies this wave spawns for `player_count` players.
func enemy_count(player_count: int, scaling: PlayerScaling) -> int:
	var total := 0
	for group in enemy_groups:
		if group and group.enemy_scene:
			total += _scaled_count(group, player_count, scaling)
	return total


## Returns when each enemy (or pack of them, for a group with a cluster)
## appears, sorted by time:
## [{"time": seconds since the wave started, "group": WaveEnemyGroup,
##   "elite": bool, "count": how many spawn together}, ...]
func build_spawn_schedule(player_count: int, scaling: PlayerScaling) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for group in enemy_groups:
		if group and group.enemy_scene:
			var left := _scaled_count(group, player_count, scaling)
			var pack := maxi(group.cluster, 1)
			while left > 0:
				pool.append({"group": group, "count": mini(pack, left)})
				left -= pack
	pool.shuffle()  # mix enemy types together

	var elite_chance := scaling.elite_chance(base_elite_chance, player_count)
	var opening := mini(roundi(opening_spawn * scaling.opening_multiplier(player_count)), pool.size())
	var rest := pool.size() - opening
	var window := duration * spawn_window
	var schedule: Array[Dictionary] = []
	for i in pool.size():
		var time := 0.0
		if i >= opening:
			time = window * float(i - opening + 1) / float(rest)
		var group: WaveEnemyGroup = pool[i]["group"]
		var elite := group.allow_elite and randf() < elite_chance
		schedule.append({"time": time, "group": group, "elite": elite, "count": pool[i]["count"]})
	return schedule


func _scaled_count(group: WaveEnemyGroup, player_count: int, scaling: PlayerScaling) -> int:
	return roundi(group.count * scaling.count_multiplier(player_count))
