extends "res://tests/test_case.gd"
## Wave data: spawn schedules, player scaling, Boss Rush, the wave director.

const WaveDirector := preload("res://scripts/waves/wave_director.gd")
const BossRush := preload("res://scripts/waves/boss_rush.gd")
const STANDARD_RUN := "res://data/waves/standard_run.tres"


## An objective that never ends the wave and doesn't run on the wave clock
## (so the director loops the spawn schedule).
class EndlessObjective extends Objective:
	func display_time(at: float) -> float:
		return at


func _wave(groups: Array[WaveEnemyGroup], duration := 30.0, opening := 3) -> WaveDefinition:
	var wave := WaveDefinition.new()
	wave.enemy_groups = groups
	wave.duration = duration
	wave.opening_spawn = opening
	return wave


func _group(count: int, cluster := 1) -> WaveEnemyGroup:
	var group := WaveEnemyGroup.new()
	group.count = count
	group.cluster = cluster
	return group


func test_schedule_spawns_every_enemy_in_order() -> void:
	var scaling := PlayerScaling.new()
	var wave := _wave([_group(10), _group(6, 3)])
	for players in [1, 2, 4]:
		var schedule := wave.build_spawn_schedule(players, scaling)
		var total := 0
		var last := -1.0
		for entry in schedule:
			total += int(entry["count"])
			check(entry["time"] >= last, "%d players: spawn times go in order" % players)
			last = entry["time"]
		check_eq(total, wave.enemy_count(players, scaling), "%d players: every enemy spawns" % players)
		check(last <= wave.duration * wave.spawn_window + 0.001,
			"%d players: the last spawn is inside the spawn window" % players)


func test_opening_spawn_comes_at_once() -> void:
	var wave := _wave([_group(20)], 30.0, 5)
	var schedule := wave.build_spawn_schedule(1, PlayerScaling.new())
	var at_zero := 0
	for entry in schedule:
		if entry["time"] == 0.0:
			at_zero += 1
	check_eq(at_zero, 5, "opening spawn")


func test_solo_play_is_unscaled() -> void:
	var scaling := PlayerScaling.new()
	check_near(scaling.count_multiplier(1), 1.0, "count")
	check_near(scaling.health_multiplier(1), 1.0, "health")
	check_near(scaling.speed_multiplier(1), 1.0, "speed")
	check(scaling.health_multiplier(4) > scaling.health_multiplier(2), "more players, more health")
	check(scaling.elite_chance(0.9, 4) <= scaling.max_elite_chance, "elite chance is capped")


func test_boss_rush_is_the_boss_waves() -> void:
	var base: WaveSet = load(STANDARD_RUN)
	var run := BossRush.build(base)
	check(run.wave_count() > 0, "Boss Rush has waves")
	check_eq(run.price_waves.size(), run.wave_count(), "a price wave per wave")
	for i in run.wave_count():
		check(run.waves[i].is_boss_wave(), "wave %d is a boss wave" % i)
		check(run.waves[i] == base.waves[run.price_waves[i]], "wave %d prices as its own wave" % i)


func test_director_does_not_loop_an_empty_schedule() -> void:
	var waves := WaveSet.new()
	waves.waves.append(_wave([], 10.0, 0))
	var director := WaveDirector.new()
	director.wave_set = waves
	add_child(director)
	director.objective = EndlessObjective.new()
	var spawns := [0]
	director.spawn_requested.connect(func(_g, _w, _e, _c) -> void: spawns[0] += 1)
	director.start_wave(0, 1)
	for i in 30:
		director._physics_process(0.5)
	check_eq(spawns[0], 0, "nothing spawns")
	check(not director._loops_spawns(), "an empty schedule doesn't loop")
	director.objective.free()


func test_director_loops_an_objective_wave() -> void:
	var waves := WaveSet.new()
	waves.waves.append(_wave([_group(4)], 10.0, 0))
	var director := WaveDirector.new()
	director.wave_set = waves
	add_child(director)
	director.objective = EndlessObjective.new()
	var spawns := [0]
	director.spawn_requested.connect(func(_g, _w, _e, c: int) -> void: spawns[0] += c)
	director.start_wave(0, 1)
	for i in 60:
		director._physics_process(0.5)  # 30 s: the 8 s schedule runs more than once
	check(spawns[0] > 4, "the schedule starts over (got %d enemies)" % spawns[0])
	director.objective.free()
