class_name WaveEnemyGroup
extends Resource
## One kind of enemy within a wave, and how many of it to spawn.
## A wave lists one of these per enemy type; their spawns are shuffled together.
##
## To add a per-group tweak later, add an @export var here and read it in
## game.gd's _spawn_enemy (or in WaveDefinition.build_spawn_schedule).

## The enemy to spawn. Its root script may define apply_modifiers().
@export var enemy_scene: PackedScene = preload("res://scenenodethings/enemy.tscn")
## How many to spawn with a single player (more are added per extra player,
## see PlayerScaling on the WaveSet).
@export_range(0, 1000, 1) var count := 10
## Multiplies this group's health on top of the wave's multiplier.
@export_range(0.1, 20.0, 0.05) var health_multiplier := 1.0
## Multiplies this group's speed on top of the wave's multiplier.
@export_range(0.1, 5.0, 0.05) var speed_multiplier := 1.0
## Spawn them in packs of this many, together at one spot (swarmlings).
## `count` is still the total number of enemies.
@export_range(1, 50, 1) var cluster := 1
## False: never spawn this group as elites, whatever the wave's elite chance.
@export var allow_elite := true
