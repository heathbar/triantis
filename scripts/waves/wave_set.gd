class_name WaveSet
extends Resource
## An ordered list of waves making up one run. Surviving the last wave wins.
## The standard run is res://data/waves/standard_run.tres.

@export var display_name := "Standard"
@export var waves: Array[WaveDefinition] = []
## How the run gets harder with more players. Left empty, the defaults in
## scripts/waves/player_scaling.gd are used.
@export var player_scaling: PlayerScaling
## Runs built from the standard run that skip waves (Boss Rush, Boss Test):
## for each of its waves, the standard run's wave index it stands for, so the
## shop prices as if the waves in between had been played. Empty = each
## wave's own index.
var price_waves: Array[int] = []


func get_player_scaling() -> PlayerScaling:
	if player_scaling == null:
		player_scaling = PlayerScaling.new()
	return player_scaling


func wave_count() -> int:
	return waves.size()


func is_final_wave(index: int) -> bool:
	return index >= waves.size() - 1
