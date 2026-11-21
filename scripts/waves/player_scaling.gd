class_name PlayerScaling
extends Resource
## How much harder a run gets for each player beyond the first. One of these
## hangs off the WaveSet, so the whole run is tuned in one place.
##
## Every "per extra player" value is linear: with N players the bonus is
## value * (N - 1). Solo play is never affected, except by a wave's own
## base_elite_chance.

@export_group("More Enemies")
## Extra enemies, as a fraction of each group's count
## (0.5 = +50% per extra player, so 4 players face 2.5x the enemies).
@export_range(0.0, 2.0, 0.05) var enemy_count_per_player := 0.5
## Extra enemies in the opening burst, as a fraction of the wave's opening_spawn.
@export_range(0.0, 2.0, 0.05) var opening_spawn_per_player := 0.5

@export_group("Tougher Enemies")
## Extra enemy health (0.2 = +20% per extra player, so 4 players face 1.6x).
@export_range(0.0, 2.0, 0.05) var health_per_player := 0.2
## Extra enemy speed (0.03 = +3% per extra player, so 4 players face 1.09x).
@export_range(0.0, 0.5, 0.01) var speed_per_player := 0.03

@export_group("Elites")
## Chance for each enemy to spawn as an elite, added per extra player and on
## top of the wave's base_elite_chance.
@export_range(0.0, 1.0, 0.01) var elite_chance_per_player := 0.06
## Elite chance never goes above this, however many players there are.
@export_range(0.0, 1.0, 0.01) var max_elite_chance := 0.5
## Elites multiply their (already scaled) health by this.
@export_range(1.0, 20.0, 0.1) var elite_health_multiplier := 3.0
## Elites multiply their (already scaled) speed by this.
@export_range(0.5, 3.0, 0.05) var elite_speed_multiplier := 1.15
## Elites are drawn (and collide) this much bigger.
@export_range(1.0, 3.0, 0.05) var elite_size_multiplier := 1.35
## Elites award this many times the points and resource drops.
@export_range(1, 10, 1) var elite_reward_multiplier := 3


func extra_players(player_count: int) -> int:
	return maxi(player_count - 1, 0)


func count_multiplier(player_count: int) -> float:
	return 1.0 + enemy_count_per_player * extra_players(player_count)


func opening_multiplier(player_count: int) -> float:
	return 1.0 + opening_spawn_per_player * extra_players(player_count)


func health_multiplier(player_count: int) -> float:
	return 1.0 + health_per_player * extra_players(player_count)


func speed_multiplier(player_count: int) -> float:
	return 1.0 + speed_per_player * extra_players(player_count)


func elite_chance(base_chance: float, player_count: int) -> float:
	return clampf(base_chance + elite_chance_per_player * extra_players(player_count),
		0.0, max_elite_chance)
