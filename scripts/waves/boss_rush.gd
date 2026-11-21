extends RefCounted
## Boss Rush (Global.MODE_BOSS_RUSH): every boss wave of the standard run, in
## order, back to back. Players start with START_RESOURCES and a trip to the
## shop, and each boss beaten pays its usual (boss) reward plus STIPEND, to
## stand in for the waves in between they skipped. Shop prices are those of
## the standard run's shop before the same boss.
##
## All the knobs are here; expect to tune them.
##
## Score: every boss pays kill points plus a bonus for beating it quickly
## (scripts/bosses/boss.gd KILL_POINTS / SPEED_POINTS), and the final summary
## shows the total time spent fighting.

## Resources every player starts with (about what a standard run has earned
## by the first boss).
const START_RESOURCES := 150
## Extra resources for every player after each boss but the last (about what
## a standard run earns between bosses).
const STIPEND := 450


## The run for Boss Rush, built from `base` (the standard run). Its waves are
## shared with `base`, not copied. The standard run's wave index of each
## boss is kept in its price_waves, for the shop.
static func build(base: WaveSet) -> WaveSet:
	var run := WaveSet.new()
	run.display_name = "Boss Rush"
	run.player_scaling = base.get_player_scaling()
	var price_waves: Array[int] = []
	for i in base.waves.size():
		if base.waves[i].is_boss_wave():
			run.waves.append(base.waves[i])
			price_waves.append(i)
	run.price_waves = price_waves
	return run
