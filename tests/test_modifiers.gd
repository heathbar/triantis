extends "res://tests/test_case.gd"
## Campaign modifiers (scripts/braid/braid_modifiers.gd) and their page.

const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")
const BraidLevel := preload("res://scripts/braid/braid_level.gd")
const BraidGenerator := preload("res://scripts/braid/braid_generator.gd")
const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const ModifiersMenu := preload("res://scripts/ui/modifiers_menu.gd")


func test_every_modifier_is_complete() -> void:
	var ids := {}
	for m: Dictionary in BraidModifiers.LIST:
		var id: String = m["id"]
		check(not ids.has(id), "%s: listed once" % id)
		ids[id] = true
		check(str(m.get("name", "")) != "", "%s: has a name" % id)
		check(str(m.get("blurb", "")) != "", "%s: has a description" % id)
		check(float(m.get("score", 0.0)) > 0.0, "%s: adds to the score" % id)
		check(BraidModifiers.icon(id) != null, "%s: has an icon" % id)
	check_eq(BraidModifiers.LIST.size(), 8, "eight modifiers")


func test_score_multiplier_adds_up() -> void:
	check_near(BraidModifiers.score_multiplier([]), 1.0, "none: x1")
	var all := []
	var sum := 1.0
	for m: Dictionary in BraidModifiers.LIST:
		all.append(m["id"])
		sum += float(m["score"])
	check_near(BraidModifiers.score_multiplier(all), sum, "all: 1 + every score")
	check_near(BraidModifiers.score_multiplier(["riptide", "nonsense"]), 1.25, "unknown ids add nothing")
	check_eq(BraidModifiers.names(["horde", "riptide"]), "Riptide, Horde", "names in page order")


func test_riptide_speeds_the_tide_not_the_layout() -> void:
	var layout := BraidGenerator.act_layout(4242, 0, BraidTuning.SEGMENTS_PER_ACT, 1)
	var level := BraidLevel.new()
	add_child(level)
	level.build(layout, true)
	var from := level.segment_start(0) - BraidTuning.TIDE_START_GAP
	var to := level.gate_x(0) - BraidTuning.TIDE_GATE_STOP
	var normal: float = level.tide_time(from, to)
	var where: float = level.tide_after(from, 10.0, to)
	level.tide_speed_scale = BraidModifiers.TIDE_SPEED_MULT
	check_near(level.tide_time(from, to), normal / BraidModifiers.TIDE_SPEED_MULT,
		"the segment takes 1/1.25 the time", 0.01)
	check_near(level.tide_after(from, 10.0 / BraidModifiers.TIDE_SPEED_MULT, to), where,
		"the tide gets as far in 1/1.25 the time", 0.01)
	check_eq(level.gate_x(0), to + BraidTuning.TIDE_GATE_STOP, "the gate hasn't moved")


func test_page_toggles_and_keeps_picks() -> void:
	var before: Array = Global.campaign_modifiers
	Global.campaign_modifiers = []
	var page: Control = ModifiersMenu.new()
	add_child(page)
	var results := []
	page.finished.connect(func(ok: bool) -> void: results.append(ok))
	check_eq(page.cursor, BraidModifiers.LIST.size(), "the page opens on BEGIN")
	page._toggle(0)
	page._toggle(3)
	page._toggle(0)
	check_eq(page.selected, ["tyrants"], "toggling twice switches it back off")
	page._finish(true)
	check_eq(results, [true], "begin confirms")
	check_eq(Global.campaign_modifiers, ["tyrants"], "picks are kept")
	Global.campaign_modifiers = before
