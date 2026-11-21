extends CanvasLayer
## Pause menu for the game scene. Escape (keyboard) or Start (any controller)
## toggles it. While open the scene tree is paused; this layer keeps running.
##
## In a squads game the other squads keep playing, so the menu doesn't pause
## anything: it's just a way to leave. The host's "End Game" sends every squad
## back to character select; anyone else's "Leave Game" quits to the title.
##
## Below the menu, every local player's stats (scripts/ui/player_stats.gd).
##
## Also: Music and Effects volume sliders (saved like the title screen's
## settings) and the
## title screen's Controls diagram (scripts/ui/controls_menu.gd).
##
## Styled by the menus' theme (data/ui/menu_theme.tres: wooden sign board and
## plank buttons), like the title screen and character select.

const PlayerStats := preload("res://scripts/ui/player_stats.gd")
const ControlsMenu := preload("res://scripts/ui/controls_menu.gd")
const MENU_THEME := preload("res://data/ui/menu_theme.tres")
## Heading colour on the sign boards (as title_screen.gd ACCENT).
const ACCENT := Color(1, 0.86, 0.5)
## In a squads game the world keeps running, so the stats cards are
## refreshed this often (seconds) while the menu is open.
const STATS_REFRESH := 0.25

## Set to false to block pausing (e.g. once the game is over).
var enabled := true
## Set before adding to the tree.
var squads_game := false
## Boss Test game (scripts/waves/boss_test.gd): quitting goes back to
## character select. Set before adding to the tree.
var boss_test := false
## This game's players, for the stats cards. Set before adding to the tree.
var players: Array[Node] = []

var _root: Control
var _resume_button: Button
var _quit_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _controls_button: Button
## The menu panel and stats cards, hidden while the controls are shown.
var _column: Control
var _controls: ControlsMenu
## [player, PlayerStats] pairs, in player order.
var _cards: Array = []
var _stats_timer := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if not enabled or is_open():
		return
	if not squads_game:
		get_tree().paused = true
	_refresh_stats()
	_music_slider.set_value_no_signal(Global.music_volume * 100.0)
	_sfx_slider.set_value_no_signal(Global.sfx_volume * 100.0)
	_hide_controls()
	_root.show()
	_resume_button.grab_focus()


func close() -> void:
	if not is_open():
		return
	_hide_controls()
	_root.hide()
	if not squads_game:
		get_tree().paused = false


func _process(delta: float) -> void:
	# In a squads game the world keeps running behind the menu.
	if not squads_game or not is_open():
		return
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = STATS_REFRESH
		_refresh_stats()


func _refresh_stats() -> void:
	for pair in _cards:
		if is_instance_valid(pair[0]):
			pair[1].show_stats(PlayerStats.snapshot(pair[0]))


func _unhandled_input(event: InputEvent) -> void:
	# While disabled, leave input (e.g. Escape) for the game-over screen.
	if not enabled and not is_open():
		return
	if event.is_action_pressed("pause"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		# B / Escape-style cancel backs out of the controls, else resumes.
		if _controls.visible:
			_close_controls()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif is_open() and get_viewport().gui_get_focus_owner() == null:
		# Focus lost (e.g. mouse clicked the background): re-focus on nav input.
		for action in ["ui_accept", "ui_up", "ui_down"]:
			if event.is_action_pressed(action):
				if _controls.visible:
					_controls.back_button.grab_focus()
				else:
					_resume_button.grab_focus()
				get_viewport().set_input_as_handled()
				return


func _build() -> void:
	_root = Control.new()
	_root.theme = MENU_THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 40)
	center.add_child(column)
	_column = column

	# The theme's sign board.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MENU" if squads_game else "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 128)
	title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(title)

	_resume_button = _button("Resume")
	_resume_button.pressed.connect(close)
	vbox.add_child(_resume_button)

	if squads_game:
		var note := Label.new()
		note.text = "The game keeps running while this menu is open"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 48)
		note.modulate = Color(1, 1, 1, 0.7)
		vbox.add_child(note)

	_music_slider = _volume_row(vbox, "Music", func(v: float) -> void: Global.music_volume = v)
	_sfx_slider = _volume_row(vbox, "Effects", func(v: float) -> void: Global.sfx_volume = v)

	_controls_button = _button("Controls")
	_controls_button.pressed.connect(_open_controls)
	vbox.add_child(_controls_button)

	if boss_test:
		_quit_button = _button("Back to Character Select")
		_quit_button.pressed.connect(Global.go_to_character_select)
	elif not squads_game:
		_quit_button = _button("Quit to Title")
		_quit_button.pressed.connect(Global.go_to_title)
	elif Squads.is_host():
		_quit_button = _button("End Game for All Squads")
		_quit_button.pressed.connect(Squads.return_to_lobby)
	else:
		_quit_button = _button("Leave Game")
		_quit_button.pressed.connect(Global.go_to_title)
	vbox.add_child(_quit_button)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	column.add_child(row)
	var ordered := players.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	for player in ordered:
		var card := PlayerStats.new()
		row.add_child(card)
		_cards.append([player, card])

	_controls = ControlsMenu.new()
	# The diagram is nearly screen-wide: the same sign board, slimmer margins.
	var controls_style: StyleBox = MENU_THEME.get_stylebox("panel", "PanelContainer").duplicate()
	controls_style.content_margin_left = 40
	controls_style.content_margin_right = 40
	controls_style.content_margin_top = 24
	controls_style.content_margin_bottom = 32
	_controls.build(controls_style, ACCENT)
	_controls.closed.connect(_close_controls)
	_root.add_child(_controls)


## Adds a labelled 0-100% volume slider to `parent`; `set_volume` gets the
## new volume (0-1), then the setting is applied and saved.
func _volume_row(parent: Control, label_text: String, set_volume: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(800, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 32)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 80)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.mouse_entered.connect(func() -> void:
		if slider.is_visible_in_tree():
			slider.grab_focus())
	slider.value_changed.connect(func(value: float) -> void:
		set_volume.call(value / 100.0)
		Global.apply_settings()
		Global.save_settings())
	row.add_child(slider)
	return slider


func _open_controls() -> void:
	_column.hide()
	_controls.open()


func _close_controls() -> void:
	_hide_controls()
	_controls_button.grab_focus()


func _hide_controls() -> void:
	_controls.hide()
	_column.show()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(800, 120)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Hovering moves the focus highlight, so only one button looks selected.
	b.mouse_entered.connect(func() -> void:
		if b.is_visible_in_tree():
			b.grab_focus())
	return b
