extends Control
## Boss Test setup (scripts/waves/boss_test.gd), opened from the custom game
## screen: which boss, which wave's kit to start with, and how many resources
## and how much boss health. Start saves it to Global.boss_test and arms it
## (the title screen then goes to character select); Cancel / Escape / B
## leaves it unchanged.
##
## Built in code, like the sandbox loadout screen; driven by the mouse, or the
## keyboard / a controller through normal focus navigation.

const BossTest := preload("res://scripts/waves/boss_test.gd")

## true = Start (Global.boss_test updated and armed), false = cancelled.
signal finished(confirmed: bool)

const FONT_SIZE := 44
const HEADING_COLOR := Color(1.0, 0.85, 0.5)

## How many players to describe the kit for (the joined count).
var player_count := 1

var _base: WaveSet
var _bosses: Array[Dictionary] = []
var _boss_option: OptionButton
var _wave_option: OptionButton
var _resources_option: OptionButton
var _health_option: OptionButton
var _info: Label
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var theme_res := Theme.new()
	theme_res.default_font_size = FONT_SIZE
	theme = theme_res
	_base = load("res://data/waves/standard_run.tres")
	_bosses = BossTest.bosses(_base)
	_build()
	_load(BossTest.settings())
	_boss_option.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	# Escape / B backs out, unless a dropdown popup is open (it closes itself).
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not _popup_open():
		get_viewport().set_input_as_handled()
		_finish(false)


func _popup_open() -> bool:
	for option in [_boss_option, _wave_option, _resources_option, _health_option]:
		if option.get_popup().visible:
			return true
	return false


# --- Building ---------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.set_border_width_all(8)
	style.border_color = Color(0.45, 0.45, 0.5)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(48)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 32)
	panel.add_child(root)

	var title := _label(root, "Boss Test", 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(root, "Skip straight to one boss, kitted out as if you'd played up to it.", 36)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 20)
	root.add_child(grid)

	_boss_option = _row(grid, "Boss")
	for boss in _bosses:
		var where := "wave %d" % (boss["wave"] + 1) if boss["wave"] >= 0 else "not in the run yet"
		_boss_option.add_item("%s  (%s)" % [boss["name"], where])

	_wave_option = _row(grid, "Kit as of")
	_wave_option.add_item("The boss's own wave")
	for i in _base.waves.size():
		_wave_option.add_item("Wave %d" % (i + 1))

	_resources_option = _row(grid, "Resources")
	for scale in BossTest.RESOURCE_SCALES:
		_resources_option.add_item("None (no shop)" if scale == 0.0 else
			"%d%% of a run's" % roundi(scale * 100))

	_health_option = _row(grid, "Boss health")
	for scale in BossTest.HEALTH_SCALES:
		_health_option.add_item("%d%%" % roundi(scale * 100))

	_info = _label(root, "", 38)
	_info.modulate = Color(0.75, 1.0, 0.75)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(1300, 150)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	root.add_child(buttons)
	_button(buttons, "Cancel", _finish.bind(false))
	_start_button = _button(buttons, "Start", _finish.bind(true))


func _row(grid: GridContainer, text: String) -> OptionButton:
	_label(grid, text, 52).modulate = HEADING_COLOR
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(820, 80)
	option.get_popup().add_theme_font_size_override("font_size", FONT_SIZE)
	option.item_selected.connect(func(_i: int) -> void: _update_info())
	grid.add_child(option)
	return option


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 90)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


# --- Values -------------------------------------------------------------------

func _load(s: Dictionary) -> void:
	_boss_option.select(0)
	for i in _bosses.size():
		if _bosses[i]["id"] == s["boss"]:
			_boss_option.select(i)
	var wave := int(s["wave"])
	_wave_option.select(wave + 1 if wave >= 0 and wave < _base.waves.size() else 0)
	_resources_option.select(_closest(BossTest.RESOURCE_SCALES, float(s["resources"])))
	_health_option.select(_closest(BossTest.HEALTH_SCALES, float(s["health"])))
	_update_info()


func _collect() -> Dictionary:
	return {
		"active": true,
		"boss": _bosses[maxi(_boss_option.selected, 0)]["id"],
		"wave": _wave_option.selected - 1,
		"resources": BossTest.RESOURCE_SCALES[_resources_option.selected],
		"health": BossTest.HEALTH_SCALES[_health_option.selected],
	}


static func _closest(values: Array, v: float) -> int:
	var best := 0
	for i in values.size():
		if absf(values[i] - v) < absf(values[best] - v):
			best = i
	return best


func _update_info() -> void:
	if _health_option == null or _info == null:
		return
	_info.text = BossTest.describe(_base, _collect(), player_count)


func _finish(confirmed: bool) -> void:
	if confirmed:
		Global.boss_test = _collect()
	finished.emit(confirmed)
	queue_free()
