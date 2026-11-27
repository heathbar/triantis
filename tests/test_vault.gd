extends "res://tests/test_case.gd"
## The Vault's rules (scripts/bosses/vault.gd, scripts/bosses/vault_lasers.gd).

const Vault := preload("res://scripts/bosses/vault.gd")
const VaultLasers := preload("res://scripts/bosses/vault_lasers.gd")


func test_codes_are_five_and_engineering_shortens_them() -> void:
	check_eq(Vault.code_length(0), 5, "a plain code: 5")
	check_eq(Vault.code_length(40), 4, "engineering over 30 shortens it")
	check_eq(Vault.code_length(60), 3, "engineering over 50 shortens it more")


func test_codes_never_repeat_a_button_three_times() -> void:
	var longest := 0
	var pairs := 0
	for n in 2000:
		var code: Array = Vault.make_code(5)
		var run := 1
		for i in range(1, code.size()):
			run = run + 1 if code[i] == code[i - 1] else 1
			longest = maxi(longest, run)
			if run == 2:
				pairs += 1
	check_eq(longest, 2, "two in a row happens, three never does")
	check(pairs > 0, "pairs are still allowed")


func test_stages_end_at_75_and_50() -> void:
	check_eq(Vault.STAGE_MARKS.size(), Vault.WALK_PHASE, "it walks after the last mark")
	check_near(Vault.STAGE_MARKS[0], 0.75, "the lock ends at 75%")
	check_near(Vault.STAGE_MARKS[1], 0.5, "the keypad ends at 50%")
	check_near(Vault.WINDOW_CUT, 0.25, "a window takes at most a quarter")


func test_pins_get_harder_and_engineering_helps() -> void:
	for pin in Vault.PINS - 1:
		check(Vault.pin_arc(0, pin) > Vault.pin_arc(0, pin + 1), "each pin's arc is smaller")
		check(Vault.pin_speed(pin) < Vault.pin_speed(pin + 1), "each pin's needle is faster")
	check(Vault.pin_arc(40, 0) > Vault.pin_arc(0, 0), "engineering over 30 widens the arc")
	check(Vault.pin_arc(60, 0) > Vault.pin_arc(40, 0), "engineering over 50 widens it more")


func test_needle_in_arc_wraps_round() -> void:
	check(Vault.needle_in_arc(0.1, 0.0, 0.4), "inside")
	check(not Vault.needle_in_arc(0.3, 0.0, 0.4), "outside")
	check(Vault.needle_in_arc(PI - 0.05, -PI + 0.05, 0.4), "across the wrap")


func test_burst_bullets_fly_in_order_and_fan_out() -> void:
	var line := {"pos": Vector2.ZERO, "dir": Vector2.RIGHT, "fire": 1.0, "n": 4, "gap": 0.15,
		"spread": 0.0}
	check(Vault.bullet_position(line, 0, 0.9) == null, "nothing before it fires")
	check(Vault.bullet_position(line, 0, 1.1) != null, "the first bullet's out")
	check(Vault.bullet_position(line, 1, 1.1) == null, "the second waits its turn")
	check(Vault.bullet_position(line, 0, 1.0 + Vault.BULLET_LIFE + 0.1) == null, "gone after its range")
	var fan := line.duplicate()
	fan["gap"] = 0.0
	fan["n"] = 7
	fan["spread"] = 1.2
	check_near(Vault.bullet_dir(fan, 0).angle(), -0.6, "the fan's first edge")
	check_near(Vault.bullet_dir(fan, 6).angle(), 0.6, "the fan's other edge")
	check_near(Vault.bullet_dir(fan, 3).angle(), 0.0, "the middle goes straight")


func test_corridor_runs_out_from_the_wall() -> void:
	var lasers := VaultLasers.new(null)
	var map := Rect2(0, 0, 1000, 1000)
	var keypad := Vector2(500, 500)
	for out: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		lasers.build(keypad, out, map, Vault.STATION_OUT)
		check_eq(lasers.beams.size(), 2, "two beams")
		var a: Array = lasers.beams[0]
		var b: Array = lasers.beams[1]
		check(((a[1] - a[0]) as Vector2).normalized().is_equal_approx(out), "straight out from the wall")
		check(((b[1] - b[0]) as Vector2).normalized().is_equal_approx(out), "parallel")
		check_near((a[0] as Vector2).distance_to(b[0]), VaultLasers.CORRIDOR_WIDTH, "64 px apart")
		var wall := keypad - out * Vault.STATION_OUT
		check_near(((a[0] as Vector2) - wall).dot(out), 0.0, "starting at the wall")
		var reach := (a[0] as Vector2).distance_to(a[1])
		check(reach >= VaultLasers.CORRIDOR_REACH.x - 0.01 and reach <= VaultLasers.CORRIDOR_REACH.y + 0.01,
			"160-256 out")
		for beam: Array in lasers.beams:
			check(not VaultLasers.touches(beam[0], beam[1], keypad + Vector2.ONE * Vault.KEYPAD_REACH * 0.7),
				"anywhere on the keypad is clear")
		check(VaultLasers.touches(a[0], a[1], (a[0] + a[1]) / 2.0), "the beam itself hurts")
	lasers.build(Vector2(10, 10), Vector2.UP, map)
	for beam: Array in lasers.beams:
		for end: Vector2 in beam:
			check(map.grow(0.01).has_point(end), "kept on the map")


func test_wall_is_sized_to_the_map_in_whole_cells() -> void:
	check_eq(Vault.wall_cells_for(Rect2(0, 0, 988, 912)), Vector2i(8, 7), "the arena: 384 x 336")
	check_eq(Vault.wall_cells_for(Rect2(0, 0, 200, 200)), Vector2i(5, 5), "never under 5 cells")
	var cells := Vault.wall_cells_for(Rect2(0, 0, 1728, 688))
	check_eq(cells, Vector2i(14, 5), "a two-lane Campaign room")


func test_stations_sit_in_the_wall_facing_out() -> void:
	var cells := Vector2i(8, 7)
	var half := Vector2(cells) * Vault.WALL_CELL / 2.0
	for side in 4:
		var normal: Vector2 = Vault.SIDES[side]
		check_eq(Vault.side_length(cells, side), (cells.x if side % 2 == 0 else cells.y) - 2,
			"corners left out")
		for i in Vault.side_length(cells, side):
			var cell := Vault.side_cell(cells, side, i)
			check(cell.x == 0 or cell.y == 0 or cell.x == cells.x - 1 or cell.y == cells.y - 1,
				"on the ring")
			check(not (cell.x in [0, cells.x - 1] and cell.y in [0, cells.y - 1]), "not a corner")
			var face := Vault.side_cell_centre(cells, side, i) + normal * Vault.WALL_CELL / 2.0
			check_near(face.dot(normal), half.dot(normal.abs()), "its face is the wall's outside")
	check_eq(Vault.SQUAD_SIDES.duplicate().size(), 4, "a side for every squad")
	var seen := {}
	for side: int in Vault.SQUAD_SIDES:
		seen[side] = true
	check_eq(seen.size(), 4, "every squad on its own side")


func test_sweep_lines_cross_the_whole_map() -> void:
	var map := Rect2(0, 0, 900, 600)
	var h := VaultLasers.line_across(Vector2(300, 200), 0.0, map)
	check(h.size() == 2 and h[0].is_equal_approx(Vector2(0, 200)) and h[1].is_equal_approx(Vector2(900, 200)),
		"horizontal: edge to edge")
	var v := VaultLasers.line_across(Vector2(300, 200), PI / 2.0, map)
	check(v.size() == 2 and absf(v[0].y) < 0.01 and absf(v[1].y - 600) < 0.01, "vertical: top to bottom")
	var d := VaultLasers.line_across(Vector2(300, 300), PI / 4.0, map)
	check(d.size() == 2 and d[0].is_equal_approx(Vector2(0, 0)) and d[1].is_equal_approx(Vector2(600, 600)),
		"diagonal: clipped at the edges")
	check(VaultLasers.line_across(Vector2(-50, -50), PI / 2.0, map).is_empty(), "off the map: nothing")
