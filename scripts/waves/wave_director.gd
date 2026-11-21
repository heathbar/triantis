extends Node
## Runs one wave at a time: counts down its duration and asks for enemies to
## be spawned on schedule. game.gd does the actual spawning and decides what
## happens between waves.
##
## Pauses with the scene tree, so the clock stops while the game is paused.
##
## In a squads game only the host's director is `authoritative`. The others
## follow the host's clock (sync_to) and wait for the host to end the wave.

## `count` enemies from `group` should appear now, together. `elite` means
## tougher versions.
signal spawn_requested(group: WaveEnemyGroup, wave: WaveDefinition, elite: bool, count: int)
## The wave is over: its time ran out, or its objective was done (or failed:
## `failed`).
signal wave_finished(index: int, failed: bool)

## Drift (seconds) allowed before sync_to() snaps to the other clock.
const SYNC_TOLERANCE := 0.1
## Objective waves that outlast their spawn schedule start it again this many
## seconds after it ran out.
const SCHEDULE_RESTART_DELAY := 3.0

var wave_set: WaveSet
var index := -1
var wave: WaveDefinition
var time_left := 0.0
var running := false
## How many players this wave was scaled for.
var player_count := 1
## False: never end the wave on our own; wait for stop() from outside.
var authoritative := true
## Objective waves: the wave's objective (scripts/objectives/objective.gd),
## set before start_wave, else null. It decides when the wave ends and what
## the clock shows; if it doesn't run on the wave clock, the spawn schedule
## starts over whenever it runs out, so the pressure keeps up.
var objective: Objective = null

var _schedule: Array[Dictionary] = []
var _next_spawn := 0
var _elapsed := 0.0


func start_wave(wave_index: int, players: int) -> void:
	index = wave_index
	player_count = players
	wave = wave_set.waves[wave_index]
	_schedule = wave.build_spawn_schedule(player_count, wave_set.get_player_scaling())
	_next_spawn = 0
	_elapsed = 0.0
	time_left = wave.duration
	running = true


## True if the schedule should start over once it runs out: objective waves
## that don't end on the wave clock, if the wave has any enemies to loop.
func _loops_spawns() -> bool:
	return objective != null and not objective.uses_wave_clock() and not _schedule.is_empty()


## Objective waves that outlast their schedule: the same enemies again,
## starting a few seconds from now.
func _restart_schedule() -> void:
	var offset := _elapsed + SCHEDULE_RESTART_DELAY
	_schedule = wave.build_spawn_schedule(player_count, wave_set.get_player_scaling())
	for entry in _schedule:
		entry["time"] += offset
	_next_spawn = 0


func stop() -> void:
	running = false


## Seconds since the current wave started.
func elapsed() -> float:
	return _elapsed


## Jump to another clock's time if we've drifted from it noticeably. Spawns
## that are now due happen on the next tick; none are repeated.
func sync_to(other_elapsed: float) -> void:
	if running and absf(other_elapsed - _elapsed) > SYNC_TOLERANCE:
		_elapsed = other_elapsed
		time_left = maxf(wave.duration - _elapsed, 0.0)
		if objective != null:
			time_left = objective.display_time(_elapsed)


func _physics_process(delta: float) -> void:
	if not running:
		return
	_elapsed += delta
	time_left = maxf(wave.duration - _elapsed, 0.0)

	while _next_spawn < _schedule.size() and _schedule[_next_spawn]["time"] <= _elapsed:
		var entry: Dictionary = _schedule[_next_spawn]
		spawn_requested.emit(entry["group"], wave, entry["elite"], entry["count"])
		_next_spawn += 1
	if _next_spawn >= _schedule.size() and _loops_spawns():
		_restart_schedule()

	if objective != null:
		objective.elapsed = _elapsed
		time_left = objective.display_time(_elapsed)
		if not authoritative:
			return
		var outcome: int = objective.outcome()
		if outcome == Objective.Outcome.RUNNING and objective.uses_wave_clock() \
				and _elapsed >= wave.duration:
			outcome = Objective.Outcome.SUCCESS
		if outcome != Objective.Outcome.RUNNING:
			running = false
			wave_finished.emit(index, outcome == Objective.Outcome.FAILED)
		return

	if time_left <= 0.0 and authoritative:
		running = false
		wave_finished.emit(index, false)
