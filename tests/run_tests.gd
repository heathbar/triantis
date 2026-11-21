extends SceneTree
## Runs every test in tests/ headless and exits non-zero if any fail:
##   godot --headless --path . -s res://tests/run_tests.gd
## Or only some files:  ... -s res://tests/run_tests.gd -- test_waves test_data
##
## A test file is tests/test_*.gd extending tests/test_case.gd; each of its
## methods named test_* is one test. No addon needed.
##
## This script names no project classes itself: it's compiled before the
## autoloads (Global, Squads) exist, so it loads the tests once they do.

const TEST_DIR := "res://tests/"

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var only := OS.get_cmdline_user_args()
	var failed := 0
	var passed := 0
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if not only.is_empty() and file.get_basename() not in only:
			continue
		var script: GDScript = load(TEST_DIR + file)
		if script == null:
			print("FAIL %s: doesn't compile" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: Node = script.new()
			root.add_child(test)
			await test.call(name)
			if test.failures.is_empty():
				passed += 1
				print("  ok   %s.%s" % [file.get_basename(), name])
			else:
				failed += 1
				print("  FAIL %s.%s" % [file.get_basename(), name])
				for line in test.failures:
					print("         ", line)
			test.queue_free()
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return false
