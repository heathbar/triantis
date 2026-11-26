extends "res://tests/test_case.gd"
## Class Mods shared by the arena and the Campaign (scripts/class_mods/).

const ClassMod := preload("res://scripts/class_mods/class_mod.gd")
const ModShot := preload("res://scripts/class_mods/mod_shot.gd")
const ClassModFx := preload("res://scripts/class_mods/class_mod_fx.gd")
const BraidTide := preload("res://scripts/braid/braid_tide.gd")


func test_every_tree_deals_three_cards() -> void:
	for class_id in ClassMod.TREES:
		var player := _FakePlayer.new()
		player.class_id = class_id
		var cards := ClassMod.offer(player, RandomNumberGenerator.new())
		check_eq(cards.size(), ClassMod.OFFER_COUNT, "%s gets %d cards" % [class_id, ClassMod.OFFER_COUNT])
		player.free()


func test_ricochet_bounces_off_the_arena_edge() -> void:
	var shot := ModShot.new()
	shot.edge_bounds = Rect2(0, 0, 100, 100)
	shot.bounces_left = 1
	shot.direction = Vector2.RIGHT
	shot.speed = 100.0
	shot.lifetime = 10.0
	shot.position = Vector2(95, 50)
	add_child(shot)
	shot._physics_process(0.1)  # would end at x 105, past the edge
	check(shot.direction.x < 0.0, "turned back from the right edge")
	check_eq(shot.bounces_left, 0, "used its bounce")
	check(shot.global_position.x <= 100.0, "kept inside the field")
	shot.free()


func test_no_bounce_without_bounces_left() -> void:
	var shot := ModShot.new()
	shot.edge_bounds = Rect2(0, 0, 100, 100)
	shot.direction = Vector2.RIGHT
	shot.speed = 100.0
	shot.lifetime = 10.0
	shot.position = Vector2(95, 50)
	add_child(shot)
	shot._physics_process(0.1)
	check(shot.direction.x > 0.0, "flies straight off the edge")
	shot.free()


func test_salvage_three_takes_what_the_tide_swallows() -> void:
	var fx := ClassModFx.new()
	fx.game = Node2D.new()
	add_child(fx.game)
	var scavenger := _FakePlayer.new()
	scavenger.class_id = "scavenger"
	scavenger.class_mod_picks = {"salvage": 3}
	var squadmate := _FakePlayer.new()
	squadmate.class_id = "scavenger"
	squadmate.class_mod_picks = {"salvage": 2}
	fx._st[scavenger] = {}
	fx._st[squadmate] = {}
	fx.on_tide_pickups(3)
	check_eq(scavenger.harvested, 3, "Salvage III collects the swallowed pickups")
	check_eq(squadmate.harvested, 0, "Salvage II (and the rest of the squad) gets none")
	scavenger.free()
	squadmate.free()
	fx.game.free()
	fx.free()


func test_tide_reports_swallowed_pickups() -> void:
	var tide := BraidTide.new()
	add_child(tide)
	var behind := Node2D.new()
	behind.add_to_group("pickups")
	behind.position = Vector2(0, 0)
	add_child(behind)
	var ahead := Node2D.new()
	ahead.add_to_group("pickups")
	ahead.position = Vector2(1000, 0)
	add_child(ahead)
	var counts: Array[int] = []
	tide.pickups_swallowed.connect(func(count: int) -> void: counts.append(count))
	tide.update(500.0, 0.016, [])
	check_eq(counts, [1] as Array[int], "one pickup swallowed, reported once")
	check(not ahead.is_queued_for_deletion(), "the pickup ahead of the tide is left alone")
	tide.free()
	behind.free()
	ahead.free()


## Just enough of a Player for ClassMod.offer and the Salvage tide hook.
class _FakePlayer:
	extends Node
	var class_id := ""
	var class_mod_picks := {}
	var harvested := 0
	var global_position := Vector2.ZERO

	func harvest(amount: int) -> void:
		harvested += amount
