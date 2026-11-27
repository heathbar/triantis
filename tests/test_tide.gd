extends "res://tests/test_case.gd"
## The Campaign's tide (scripts/braid/braid_tide.gd) and players.

const BraidTide := preload("res://scripts/braid/braid_tide.gd")
const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")


func test_tide_hurts_but_never_moves_players() -> void:
	var tide := BraidTide.new()
	add_child(tide)
	var deep := _FakePlayer.new()
	deep.position = Vector2(100, 0)  # far inside: once it would be knocked out
	add_child(deep)
	var clear := _FakePlayer.new()
	clear.position = Vector2(900, 0)
	add_child(clear)
	var players: Array[Node] = [deep, clear]
	var steps := int((BraidTide.FIRST_TOUCH_GRACE + BraidTuning.TIDE_DAMAGE_INTERVAL * 2.0) / 0.05) + 1
	for i in steps:
		tide.update(500.0, 0.05, players)
	check_eq(deep.position, Vector2(100, 0), "not pushed along")
	check_eq(deep.hits, 3 * BraidTuning.TIDE_DAMAGE, "a hit after the grace, then every interval")
	check_eq(clear.hits, 0, "a player ahead of it is untouched")
	tide.free()
	deep.free()
	clear.free()


## Just enough of a Player for the tide.
class _FakePlayer:
	extends Node2D
	var hits := 0
	var health := 10

	func is_dead() -> bool:
		return false

	func take_hit(amount: int, _at: Vector2) -> void:
		hits += amount
