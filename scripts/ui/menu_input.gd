extends RefCounted
## Turns raw input events into per-device menu intents, so several players can
## each drive their own part of a screen at once (character select, shop).
##
## Intents: "accept", "start", "back", "bank", "reroll", "prev_tab",
##          "next_tab", "up", "down", "left", "right".
##   Keyboard:   Enter / Space, Escape, X, R, Q / E, arrows / WASD
##   Controller: A, Start, B, X, Y, LB / RB, D-pad / left stick
## The buttons are InputMap actions (INTENTS, set up in
## Global._setup_controller_ui_input); the left stick is read here.

const STICK_PRESS := 0.6
const STICK_RELEASE := 0.3
## [action, intent], checked in order. The keyboard's directions are "up" etc.
## (arrows and WASD); a controller's D-pad is in "ui_up" etc.
const INTENTS := [
	[&"escape", "back"],
	[&"menu_start", "start"],
	[&"ui_accept", "accept"],
	[&"menu_bank", "bank"],
	[&"menu_reroll", "reroll"],
	[&"menu_prev_tab", "prev_tab"],
	[&"menu_next_tab", "next_tab"],
	[&"up", "up"], [&"down", "down"], [&"left", "left"], [&"right", "right"],
	[&"ui_up", "up"], [&"ui_down", "down"], [&"ui_left", "left"], [&"ui_right", "right"],
]

## Last left-stick direction (-1, 0, 1) per [device, axis], for edge detection.
var _stick := {}


## Returns {"device": int, "intent": String}, or {} if the event isn't a menu press.
func read(event: InputEvent) -> Dictionary:
	var device: int
	if event is InputEventKey:
		device = Global.KEYBOARD
	elif event is InputEventJoypadButton:
		device = event.device
	else:
		return _read_stick(event)
	if not event.is_pressed() or event.is_echo():
		return {}
	for pair: Array in INTENTS:
		if event.is_action_pressed(pair[0]):
			return _result(device, pair[1])
	return {}


## Left-stick pushes, as up / down / left / right presses (once per push).
func _read_stick(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var key := [event.device, event.axis]
		var prev: int = _stick.get(key, 0)
		var dir := prev
		if event.axis_value <= -STICK_PRESS:
			dir = -1
		elif event.axis_value >= STICK_PRESS:
			dir = 1
		elif absf(event.axis_value) < STICK_RELEASE:
			dir = 0
		_stick[key] = dir
		if dir == prev or dir == 0:
			return {}
		if event.axis == JOY_AXIS_LEFT_X:
			return _result(event.device, "left" if dir < 0 else "right")
		return _result(event.device, "up" if dir < 0 else "down")

	return {}


## Drop remembered stick state for a disconnected controller.
func forget(device: int) -> void:
	for key in _stick.keys():
		if key[0] == device:
			_stick.erase(key)


func _result(device: int, intent: String) -> Dictionary:
	return {"device": device, "intent": intent}
