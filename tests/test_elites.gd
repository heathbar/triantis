extends "res://tests/test_case.gd"
## Elite enemies (Enemy.make_elite): a full heart a hit, and a crown.

const EliteCrown := preload("res://scripts/enemyai/elite_crown.gd")
const SCENES := [
	"res://scenenodethings/enemy.tscn",
	"res://scenenodethings/enemies/runner.tscn",
	"res://scenenodethings/enemies/brute.tscn",
	"res://scenenodethings/enemies/charger.tscn",
	"res://scenenodethings/enemies/shooter.tscn",
	"res://scenenodethings/enemies/bomber.tscn",
	"res://scenenodethings/enemies/sprayer.tscn",
	"res://scenenodethings/enemies/splitter.tscn",
	"res://scenenodethings/enemies/swarmling.tscn",
]


func test_elites_hit_for_a_full_heart_and_wear_a_crown() -> void:
	var scaling := PlayerScaling.new()
	for path: String in SCENES:
		var name := path.get_file()
		var normal: Enemy = load(path).instantiate()
		var elite: Enemy = load(path).instantiate()
		elite.make_elite(scaling)
		for key in ["contact_damage", "bullet_damage", "spray_damage", "blast_damage"]:
			var base: Variant = normal.get(key)
			if base == null or int(base) == 0:
				check_eq(elite.get(key), base, "%s: %s stays %s" % [name, key, base])
			else:
				check_eq(elite.get(key), maxi(int(base), Enemy.ELITE_DAMAGE),
					"%s: elite %s is a full heart" % [name, key])
		var crowns := elite.get_children().filter(func(c: Node) -> bool: return c.get_script() == EliteCrown)
		check_eq(crowns.size(), 1, "%s: elite wears a crown" % name)
		check(not normal.get_children().any(func(c: Node) -> bool: return c.get_script() == EliteCrown),
			"%s: a normal one doesn't" % name)
		normal.free()
		elite.free()
