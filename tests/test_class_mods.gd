extends "res://tests/test_case.gd"
## Class Mods shared by the arena and the Campaign (scripts/class_mods/).

const ClassMod := preload("res://scripts/class_mods/class_mod.gd")
const ModShot := preload("res://scripts/class_mods/mod_shot.gd")
const ClassModFx := preload("res://scripts/class_mods/class_mod_fx.gd")
const BraidTide := preload("res://scripts/braid/braid_tide.gd")
const ExplosionArt := preload("res://scripts/explosion_art.gd")
const Blast := preload("res://scripts/equipment/blast.gd")


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


func test_small_blasts_use_the_small_explosion() -> void:
	check(ExplosionArt.is_small(24.0), "an Underbarrel burst (24 px) is small")
	check(ExplosionArt.is_small(36.0), "Underbarrel II-III bursts (36 px) are small")
	check(not ExplosionArt.is_small(60.0), "a bomber's blast (60 px) is big")
	var world := Node2D.new()
	add_child(world)
	var shot := ModShot.new()
	shot.fx = Node.new()  # (only checked for null: no spikes, lines or bomblets)
	shot.burst_radius = 24.0
	shot.position = Vector2(40, 30)
	world.add_child(shot)
	shot._stop()
	var blasts := world.get_children().filter(func(n: Node) -> bool: return n.get_script() == Blast)
	check_eq(blasts.size(), 1, "the grenade burst leaves one explosion")
	if blasts.size() == 1:
		check_eq(blasts[0].radius, 24.0, "sized to the burst")
		check_eq(blasts[0].position, Vector2(40, 30), "where the grenade stopped")
	shot.fx.free()
	world.free()


## Just enough of a Player for ClassMod.offer and the Salvage tide hook.
class _FakePlayer:
	extends Node
	var class_id := ""
	var class_mod_picks := {}
	var harvested := 0
	var global_position := Vector2.ZERO

	func harvest(amount: int) -> void:
		harvested += amount
