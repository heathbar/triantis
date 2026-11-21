extends "res://tests/test_case.gd"
## The hand-written data tables (scripts/data_check.gd).

const DataCheck := preload("res://scripts/data_check.gd")


func test_data_tables() -> void:
	for problem in DataCheck.problems():
		check(false, problem)


func test_data_check_catches_a_typo() -> void:
	var problems := PackedStringArray()
	DataCheck._check_keys(problems, "Gun test", {"id": "x", "name": "X", "type": "x",
		"cost": 1, "damage": 1, "intreval": 0.5, "range": 10}, DataCheck.GUN_KEYS)
	check_eq(problems.size(), 1, "one problem")
	check(problems.size() == 1 and problems[0].contains("interval"), "names the missing key")
