extends "res://tests/test_case.gd"
## Braid level generation: every squad's game must build the same level from
## the same seed, or the lanes won't line up between them.

const BraidGenerator := preload("res://scripts/braid/braid_generator.gd")


func test_same_seed_same_layout() -> void:
	for lanes in [1, 2, 4]:
		for act in 3:
			var a := BraidGenerator.act_layout(12345, act, 3, lanes)
			var b := BraidGenerator.act_layout(12345, act, 3, lanes)
			check(not a.is_empty(), "%d lanes, act %d: a layout" % [lanes, act + 1])
			check(a == b, "%d lanes, act %d: the same layout twice" % [lanes, act + 1])


func test_seeds_differ() -> void:
	var layouts := {}
	for seed in 8:
		layouts[var_to_str(BraidGenerator.act_layout(seed * 7777, 0, 3, 2))] = true
	check(layouts.size() > 1, "different seeds give different layouts")


func test_catalog_is_sorted() -> void:
	var names: Array[String] = []
	for strip in BraidGenerator.catalog():
		names.append(strip["name"])
	check(not names.is_empty(), "there are strips")
	var sorted := names.duplicate()
	sorted.sort()
	check(names == sorted, "strips are listed by name, the same on every machine")
