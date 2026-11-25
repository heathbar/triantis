extends "res://tests/test_case.gd"
## The Crusher's fire (scripts/bosses/crusher_fire.gd).

const CrusherFire := preload("res://scripts/bosses/crusher_fire.gd")


func test_fire_burn_time_follows_its_health() -> void:
	check_eq(CrusherFire.burn_time(1.0, false), 0.0, "full health: no fire")
	check_eq(CrusherFire.burn_time(0.76, true), 0.0, "above 75%: no fire, enraged or not")
	check_near(CrusherFire.burn_time(0.75, false), CrusherFire.BURN_TIME, "75%: fire")
	check_near(CrusherFire.burn_time(0.5, true), CrusherFire.ENRAGED_BURN_TIME, "enraged burns longer")
	check_near(CrusherFire.burn_time(0.4, false), CrusherFire.BURN_TIME, "40%: still normal")
	check_near(CrusherFire.burn_time(0.39, false), CrusherFire.BURN_TIME * CrusherFire.LONG_BURN_MULT,
		"below 40%: longer")
	check_near(CrusherFire.burn_time(0.1, true), CrusherFire.ENRAGED_BURN_TIME * CrusherFire.LONG_BURN_MULT,
		"below 40% enraged: longer than the enraged time")


func test_flame_art_is_sliced() -> void:
	check_eq(CrusherFire.FRAMES.size(), 6, "six flame frames")
	for tex: Texture2D in CrusherFire.FRAMES:
		check_eq(tex.get_size(), Vector2(12, 23), "flame frame is 12x23")
	check_eq(CrusherFire.SCORCH_TEXTURE.get_size(), Vector2(16, 5), "scorch is 16x5")
