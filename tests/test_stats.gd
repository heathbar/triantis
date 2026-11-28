extends "res://tests/test_case.gd"
## Attributes and shop prices.

const CharacterClasses := preload("res://scripts/character_classes.gd")
const Items := preload("res://scripts/items.gd")
const Guns := preload("res://scripts/guns.gd")


func test_stat_multiplier_ends() -> void:
	check_near(CharacterClasses.stat_multiplier(0), 1.0, "average")
	check_near(CharacterClasses.stat_multiplier(100), CharacterClasses.STAT_MULT_MAX, "+100")
	check_near(CharacterClasses.stat_multiplier(-100), CharacterClasses.STAT_MULT_MIN, "-100")
	var ends := {
		"speed": [CharacterClasses.SPEED_MULT_MIN, CharacterClasses.SPEED_MULT_MAX],
		"harvesting": [CharacterClasses.HARVEST_MULT_MIN, CharacterClasses.HARVEST_MULT_MAX],
	}
	for id in ends:
		check_near(CharacterClasses.stat_multiplier(-100, id), ends[id][0], "%s's own -100 end" % id)
		check_near(CharacterClasses.stat_multiplier(100, id), ends[id][1], "%s's own +100 end" % id)
		check_near(CharacterClasses.stat_multiplier(0, id), 1.0, "%s's average" % id)
	check_near(CharacterClasses.stat_multiplier(500), CharacterClasses.STAT_MULT_MAX,
		"out-of-range values are clamped")


func test_stat_multiplier_rises() -> void:
	var last := 0.0
	for value in range(-100, 101, 10):
		var mult := CharacterClasses.stat_multiplier(value)
		check(mult > last, "multiplier at %d is above the one before" % value)
		last = mult


func test_prices_rise_with_waves() -> void:
	var item := Items.find("extra_heart")
	check(not item.is_empty(), "extra_heart exists")
	check_eq(Items.price(item, 1), int(item["cost"]), "the first shop charges the listed cost")
	check_eq(Items.price(item, 0), int(item["cost"]), "and so does the shop before wave 1")
	var last := 0
	for waves_done in range(1, 20):
		var price := Items.price(item, waves_done)
		check(price >= last, "price after %d waves doesn't drop" % waves_done)
		last = price


func test_reroll_cost_doubles() -> void:
	var first := Items.reroll_cost(0, 1)
	check_eq(first, Items.REROLL_BASE_COST, "first re-roll")
	check_eq(Items.reroll_cost(1, 1), first * 2, "second re-roll")
	check_eq(Items.reroll_cost(2, 1), first * 4, "third re-roll")


func test_every_gun_tier_fires_slower_than_a_frame_or_at_it() -> void:
	# The player fires at most once per physics frame (character_body.gd
	# _shoot), so a gun faster than that couldn't reach its stated rate.
	var frame := 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	for gun: Dictionary in Guns.LIST:
		check(float(gun["interval"]) >= frame, "%s fires every %s s" % [gun["id"], gun["interval"]])


func test_weapons_are_never_sold() -> void:
	for item: Dictionary in Items.all():
		check(not item.has("gun") and not item.has("melee"),
			"%s: every class keeps its starting weapons" % item.get("id", "?"))
