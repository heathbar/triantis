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


func test_every_lane_gets_turrets() -> void:
	const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
	for lanes in [1, 2, 3, 4]:
		for seed in 6:
			for act in 4:
				var layout := BraidGenerator.act_layout(seed * 4243 + 11, act, BraidTuning.SEGMENTS_PER_ACT, lanes)
				var per_lane := {}
				for seg: Dictionary in layout["segments"]:
					for slot: Dictionary in seg["slots"]:
						for t: Dictionary in slot.get("turrets", []):
							per_lane[t["lane"]] = per_lane.get(t["lane"], 0) + 1
							check(absi(int(t["lane"]) - int(t["target"])) == 1,
								"a turret fires into a neighbouring lane")
							check(slot["seams"][mini(t["lane"], t["target"])] == "solid",
								"a turret's wall is plain wall")
				for lane in lanes:
					var n: int = per_lane.get(lane, 0)
					var want_min := BraidTuning.TURRET_PER_LANE_MIN if lanes > 1 else 0
					var want_max := BraidTuning.TURRET_PER_LANE_MAX if lanes > 1 else 0
					check(n >= want_min and n <= want_max, "%d lanes, seed %d, act %d, lane %d: %d turrets"
						% [lanes, seed, act + 1, lane + 1, n])
