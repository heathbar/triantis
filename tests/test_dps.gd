extends "res://tests/test_case.gd"
## The debug menu's per-player DPS readout (Player.record_damage / dps()).

const PLAYER_SCENE := "res://scenenodethings/player.tscn"
const ENEMY_SCENE := "res://scenenodethings/enemy.tscn"


func test_hits_credit_the_player_without_overkill() -> void:
	var player: Player = load(PLAYER_SCENE).instantiate()
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	enemy.damage_taken_multiplier = 1.0
	enemy.health = 10
	enemy.take_damage(4, player)
	check_eq(player.damage_total, 4.0, "a hit counts toward its player")
	enemy.take_damage(50, player)
	check_eq(player.damage_total, 10.0, "the killing blow counts only the health it took")
	check_eq(player.dps(), 10.0 / Player.DPS_WINDOW, "dps averages over the window")
	var other: Enemy = load(ENEMY_SCENE).instantiate()
	other.health = 10
	other.take_damage(3, null)
	check_eq(player.damage_total, 10.0, "an uncredited hit counts for no one")
	player.free()
	enemy.free()
	other.free()
