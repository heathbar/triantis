extends RefCounted
## The run's difficulty curve, shared by the arena and the Campaign: how much
## enemy health per second each standard-run wave throws at you. Arena wave n
## and the Campaign's round n (act a's chapters 1-4 are waves 5a+1 .. 5a+4,
## its boss fight wave 5a+5) read the same entry, so both modes get harder
## at the same pace.
##
## Each wave's enemy_health_multiplier is worked out from this table and the
## wave's own enemy mix (apply()), so a wave's mix can be edited without
## bending the curve: more enemies in a wave means less health each. The
## multiplier written in the wave's .tres file is replaced at run start.
##
## The shape (a sawtooth per act of 4 chapters and a boss):
##   - Inside an act each chapter is about 5% harder than the shop makes you
##     stronger, so the act climbs toward its boss.
##   - After a boss (the Class Mod pick, the prize and two shops) the next
##     act starts about 10% easier, relative to you, than the last chapter
##     before the boss, then climbs again. Each act ends a little harder
##     than the one before.
## "Stronger" is a modeled typical player (unplaytested, 2026-11-26):
## balanced shop spending, +20% from each Class Mod pick (the same in both
## modes: everyone keeps their starting weapons and picks mods after bosses).

## Enemy health per second for standard-run waves 1..20, in units of wave 1's
## enemy mix at a health multiplier of 1 (so wave 1's entry is its health
## multiplier). Boss waves' entries set their trickle of adds (see apply()).
## Scaling the whole table scales every enemy's health in both modes.
## 2026-11-27: whole table x1.1 after playtesting (it felt slightly easy).
const TARGETS: Array[float] = [
	# Act 1 (chapters 1-4, boss)
	1.10, 1.49, 2.00, 2.70, 2.84,
	# Act 2
	4.21, 5.38, 6.88, 8.78, 9.22,
	# Act 3
	12.04, 14.32, 17.02, 20.23, 21.24,
	# Act 4
	25.98, 30.04, 34.73, 40.15, 42.16,
]

## Base health of each enemy scene (with what it splits into), by path.
static var _health_cache := {}


## Sets every wave's enemy_health_multiplier in `wave_set` (the standard run)
## from TARGETS. Safe to call again: it only ever writes the same numbers.
##
## A normal wave's multiplier makes its mix's health per second hit its
## target. A boss wave's adds are a trickle, not a wave, so its multiplier is
## the wave before's, times the step between their two targets.
static func apply(wave_set: WaveSet) -> void:
	if wave_set == null or wave_set.waves.size() != TARGETS.size():
		return
	var scaling := wave_set.get_player_scaling()
	var reference := mix_health_per_second(wave_set.waves[0], scaling)
	if reference <= 0.0:
		return
	var previous := 1.0
	for i in wave_set.waves.size():
		var wave := wave_set.waves[i]
		if wave == null:
			continue
		var mult := previous
		if wave.is_boss_wave() and i > 0:
			mult = previous * TARGETS[i] / TARGETS[i - 1]
		else:
			var mix := mix_health_per_second(wave, scaling)
			if mix > 0.0:
				mult = TARGETS[i] * reference / mix
		wave.enemy_health_multiplier = snappedf(mult, 0.01)
		previous = mult


## Enemy health per second `wave` spawns for one player at a health
## multiplier of 1: every group's enemies (elites at the wave's own elite
## chance, splitters with their pieces) over the wave's duration.
static func mix_health_per_second(wave: WaveDefinition, scaling: PlayerScaling) -> float:
	var total := 0.0
	for group in wave.enemy_groups:
		if group == null or group.enemy_scene == null or group.count <= 0:
			continue
		var elite := wave.base_elite_chance if group.allow_elite else 0.0
		var info := _scene_health(group.enemy_scene)
		var one: float = info["health"] * (1.0 + elite * (scaling.elite_health_multiplier - 1.0))
		# Pieces aren't elites, but an elite splitter bursts into 2 more.
		one += (info["pieces"] + 2.0 * elite * float(info["pieces"] > 0)) * info["piece_health"]
		total += group.count * group.health_multiplier * one
	return total / maxf(wave.duration, 1.0)


## {"health", "pieces", "piece_health"} of an enemy scene (pieces: what a
## splitter bursts into).
static func _scene_health(scene: PackedScene) -> Dictionary:
	if _health_cache.has(scene.resource_path):
		return _health_cache[scene.resource_path]
	var info := {"health": 0.0, "pieces": 0, "piece_health": 0.0}
	var enemy := scene.instantiate()
	if "max_health" in enemy:
		info["health"] = float(enemy.max_health)
	if "split_count" in enemy and "child_scene" in enemy and enemy.child_scene:
		info["pieces"] = int(enemy.split_count)
		info["piece_health"] = _scene_health(enemy.child_scene)["health"]
	enemy.free()
	_health_cache[scene.resource_path] = info
	return info
