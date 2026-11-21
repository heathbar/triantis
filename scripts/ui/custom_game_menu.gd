extends CenterContainer
## The Custom Game setup screen on the title screen: number of waves, which
## enemy and objective types the run uses, how often an objective wave
## comes, and the art theme (scripts/waves/custom_run.gd).
## Edits Global.custom_settings; `confirmed` when the player carries on,
## `cancelled` when they back out. In a squads game only the host sees it.
##
## Its Boss Test button (`boss_test_requested`; local games, only where the
## sandbox character is offered) is for testing bosses: the title screen opens
## the setup (scripts/ui/boss_test_menu.gd) over it.

signal confirmed
signal cancelled
signal boss_test_requested

const MAX_WAVES_FALLBACK := 20
## Width of the bottom buttons: narrower when the Boss Test button is there
## too, so all three fit.
const BUTTON_WIDTH := 600
const BUTTON_WIDTH_WITH_BOSS_TEST := 500
## Heading / section colour, matching the title screen's signs.
const ACCENT := Color(1, 0.86, 0.5)
const CustomRun := preload("res://scripts/waves/custom_run.gd")

var waves_slider: HSlider
var continue_button: Button
var back_button: Button
var boss_test_button: Button

var _max_waves := MAX_WAVES_FALLBACK
var _waves_value: Label
var objective_every_slider: HSlider
var _objective_every_value: Label
var _enemy_checks := {}      # id -> CheckButton
var _objective_checks := {}  # id -> CheckButton
var _theme_checks := {}      # id -> CheckButton (one pressed at a time)
var _mode_note: Label


## `panel_style`: the title screen's panel look.
func build(panel_style: StyleBox, max_waves: int) -> void:
	_max_waves = max_waves
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1900, 0)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = "Custom Game"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 120)
	heading.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(heading)

	# Waves
	_waves_value = Label.new()
	waves_slider = _slider_row(vbox, "Waves", CustomRun.MIN_WAVES, _max_waves, _waves_value)
	waves_slider.value_changed.connect(_on_waves_changed)

	# Theme: one of them, like radio buttons, on one row like the sliders.
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 40)
	vbox.add_child(theme_row)
	var theme_label := Label.new()
	theme_label.text = "Theme"
	theme_label.custom_minimum_size = Vector2(380, 0)
	theme_row.add_child(theme_label)
	var theme_grid := _grid(CustomRun.theme_choices().size())
	theme_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_grid)
	var theme_group := ButtonGroup.new()
	for t in CustomRun.theme_choices():
		var check := _check(t["name"])
		check.button_group = theme_group
		check.toggled.connect(_on_theme_toggled.bind(t["id"]))
		theme_grid.add_child(check)
		_theme_checks[t["id"]] = check

	# Enemies
	vbox.add_child(_section_label("Enemies"))
	var enemy_grid := _grid(4)
	vbox.add_child(enemy_grid)
	for e in CustomRun.ENEMIES:
		var check := _check(e["name"])
		check.toggled.connect(_on_enemy_toggled.bind(e["id"]))
		enemy_grid.add_child(check)
		_enemy_checks[e["id"]] = check

	# Objectives
	vbox.add_child(_section_label("Objectives"))
	var objective_grid := _grid(3)
	vbox.add_child(objective_grid)
	for t in Objective.TYPES:
		var check := _check(t["name"])
		check.toggled.connect(_on_objective_toggled.bind(t["id"]))
		objective_grid.add_child(check)
		_objective_checks[t["id"]] = check

	_objective_every_value = Label.new()
	objective_every_slider = _slider_row(vbox, "Objective wave", 0,
		CustomRun.MAX_OBJECTIVE_EVERY, _objective_every_value)
	objective_every_slider.value_changed.connect(_on_objective_every_changed)

	_mode_note = Label.new()
	_mode_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_note.add_theme_font_size_override("font_size", 48)
	_mode_note.add_theme_color_override("font_color", Color(1, 0.94, 0.8, 0.8))
	vbox.add_child(_mode_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 60)
	vbox.add_child(buttons)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(BUTTON_WIDTH, 140)
	back_button.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(back_button)
	boss_test_button = Button.new()
	boss_test_button.text = "Boss Test..."
	boss_test_button.custom_minimum_size = Vector2(BUTTON_WIDTH_WITH_BOSS_TEST, 140)
	boss_test_button.pressed.connect(func() -> void: boss_test_requested.emit())
	buttons.add_child(boss_test_button)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(BUTTON_WIDTH, 140)
	continue_button.pressed.connect(_on_continue)
	buttons.add_child(continue_button)


## Show the screen with the current Global.custom_settings (all on by
## default). `hosting`: the button says what comes next.
func open(hosting: bool) -> void:
	if Global.custom_settings.is_empty():
		Global.custom_settings = CustomRun.default_settings(_max_waves)
	var settings := CustomRun.sanitize(Global.custom_settings, _max_waves)
	Global.custom_settings = settings
	waves_slider.set_value_no_signal(settings["waves"])
	for id in _enemy_checks:
		_enemy_checks[id].set_pressed_no_signal(id in settings["enemies"])
	for id in _objective_checks:
		_objective_checks[id].set_pressed_no_signal(id in settings["objectives"])
	objective_every_slider.set_value_no_signal(settings["objective_every"])
	for id in _theme_checks:
		_theme_checks[id].set_pressed_no_signal(id == settings["theme"])
	continue_button.text = "Continue" if hosting else "Start"
	# Boss tests are local only.
	boss_test_button.visible = not hosting and Global.sandbox_enabled()
	var width := BUTTON_WIDTH_WITH_BOSS_TEST if boss_test_button.visible else BUTTON_WIDTH
	back_button.custom_minimum_size.x = width
	continue_button.custom_minimum_size.x = width
	_refresh()
	show()
	continue_button.grab_focus()


func _on_waves_changed(value: float) -> void:
	Global.custom_settings["waves"] = int(value)
	_refresh()


func _on_enemy_toggled(_pressed: bool, _id: String) -> void:
	Global.custom_settings["enemies"] = _checked(_enemy_checks)
	_refresh()


func _on_objective_toggled(_pressed: bool, _id: String) -> void:
	Global.custom_settings["objectives"] = _checked(_objective_checks)
	_refresh()


func _on_theme_toggled(pressed: bool, id: String) -> void:
	if pressed:
		Global.custom_settings["theme"] = id


func _on_objective_every_changed(value: float) -> void:
	Global.custom_settings["objective_every"] = int(value)
	_refresh()


func _on_continue() -> void:
	if Global.custom_settings["enemies"].is_empty():
		return
	confirmed.emit()


func _refresh() -> void:
	var settings: Dictionary = Global.custom_settings
	_waves_value.text = str(settings["waves"])
	var every: int = settings["objective_every"]
	_objective_every_value.text = "Off" if every == 0 else "Every wave" if every == 1 \
		else "Every %s" % _ordinal(every)
	var no_enemies: bool = settings["enemies"].is_empty()
	continue_button.disabled = no_enemies
	if no_enemies:
		_mode_note.text = "Pick at least one enemy type."
	elif settings["objectives"].is_empty() or every == 0:
		_mode_note.text = "No objectives: survive each wave until the clock runs out."
	elif every == 1:
		_mode_note.text = "Every wave (bar boss waves) has an objective, picked from the ones chosen."
	else:
		_mode_note.text = "Waves %d, %d, %d... (bar boss waves) have an objective, picked from the ones chosen." \
			% [every, every * 2, every * 3]


static func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n


## A labelled slider row added to `parent`; `value_label` shows its value.
func _slider_row(parent: Control, text: String, min_value: int, max_value: int,
		value_label: Label) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(380, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 1
	slider.custom_minimum_size = Vector2(0, 80)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	value_label.custom_minimum_size = Vector2(340, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return slider


func _checked(checks: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in checks:
		if checks[id].button_pressed:
			ids.append(id)
	return ids


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _check(text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.add_theme_font_size_override("font_size", 56)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return check
