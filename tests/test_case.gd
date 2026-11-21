extends Node
## Base for a test file (see run_tests.gd). Each test_* method runs on a fresh
## instance, added to the tree; the check helpers record failures instead of
## stopping, so one run reports everything that's wrong.

var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(got: Variant, want: Variant, message: String) -> void:
	if typeof(got) != typeof(want) or got != want:
		failures.append("%s: got %s, want %s" % [message, var_to_str(got), var_to_str(want)])


func check_near(got: float, want: float, message: String, tolerance := 0.0001) -> void:
	if absf(got - want) > tolerance:
		failures.append("%s: got %s, want %s" % [message, got, want])
