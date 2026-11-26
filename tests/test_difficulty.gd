extends "res://tests/test_case.gd"
## The shared difficulty curve (scripts/waves/difficulty_curve.gd).

const DifficultyCurve := preload("res://scripts/waves/difficulty_curve.gd")
const STANDARD_RUN := "res://data/waves/standard_run.tres"


func test_one_target_per_wave() -> void:
	var run: Resource = load(STANDARD_RUN)
	check_eq(DifficultyCurve.TARGETS.size(), run.waves.size(), "a target for every standard-run wave")


func test_normal_waves_hit_their_targets() -> void:
	var run: Resource = load(STANDARD_RUN)
	DifficultyCurve.apply(run)
	var scaling: Resource = run.get_player_scaling()
	var reference: float = DifficultyCurve.mix_health_per_second(run.waves[0], scaling)
	check_near(run.waves[0].enemy_health_multiplier, DifficultyCurve.TARGETS[0], "wave 1's entry is its multiplier")
	for i in run.waves.size():
		var wave: Resource = run.waves[i]
		if wave.is_boss_wave():
			var step: float = DifficultyCurve.TARGETS[i] / DifficultyCurve.TARGETS[i - 1]
			check_near(wave.enemy_health_multiplier, run.waves[i - 1].enemy_health_multiplier * step,
				"boss wave %d follows the wave before" % (i + 1), 0.02)
			continue
		var got: float = DifficultyCurve.mix_health_per_second(wave, scaling) \
			* wave.enemy_health_multiplier / reference
		check_near(got, DifficultyCurve.TARGETS[i], "wave %d health per second" % (i + 1),
			DifficultyCurve.TARGETS[i] * 0.01)


func test_apply_twice_changes_nothing() -> void:
	var run: Resource = load(STANDARD_RUN)
	DifficultyCurve.apply(run)
	var first: Array[float] = []
	for wave in run.waves:
		first.append(wave.enemy_health_multiplier)
	DifficultyCurve.apply(run)
	for i in run.waves.size():
		check_eq(run.waves[i].enemy_health_multiplier, first[i], "wave %d unchanged" % (i + 1))


func test_splitter_counts_its_pieces() -> void:
	var info: Dictionary = DifficultyCurve._scene_health(load("res://scenenodethings/enemies/splitter.tscn"))
	check_eq(info["pieces"], 3, "a splitter bursts into 3")
	check(info["piece_health"] > 0.0, "pieces have health")
