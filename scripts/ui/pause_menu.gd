extends CanvasLayer
## Pause menu for the game scene, in two pages:
##   MENU  - Resume, Music / Effects volume (saved like the title screen's
##           settings), the title screen's Controls diagram
##           (scripts/ui/controls_menu.gd) and the way out.
##   STATS - every local player's stats (scripts/ui/player_stats.gd).
## Start (any controller) / Escape / P opens it on MENU; Select (two squares) /
## Tab opens it on STATS. Pressing the button for the page that's showing
## closes it; the other one switches page. LB / RB, the D-pad's left / right
## and Q / E switch pages too. While open the scene tree and the music are
## paused; this layer keeps running.
##
## In a squads game the other squads keep playing, so the menu doesn't pause
## anything: it's just a way to leave. The host's "End Game" sends every squad
## back to character select; anyone else's "Leave Game" quits to the title.
## Every way out asks for confirmation first.
##
## Styled by the menus' theme (data/ui/menu_theme.tres: wooden sign board and
## plank buttons), like the title screen and character select.

const PlayerStats := preload("res://scripts/ui/player_stats.gd")
const ControlsMenu := preload("res://scripts/ui/controls_menu.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const MENU_THEME := preload("res://data/ui/menu_theme.tres")
## Heading colour on the sign boards (as title_screen.gd ACCENT).
const ACCENT := Color(1, 0.86, 0.5)
const MUTED := Color(0.75, 0.7, 0.6)
## In a squads game the world keeps running, so the stats cards are
## refreshed this often (seconds) while the menu is open.
const STATS_REFRESH := 0.25

enum Page { MENU, STATS }
const PAGE_NAMES := ["MENU", "STATS"]

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
var _page := Page.MENU
var _tab_styles: Array[StyleBoxFlat] = []
var _menu_page: Control
var _stats_page: Control
var _resume_button: Button
var _quit_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _controls_button: Button
## The tabs and pages, hidden while the controls are shown.
var _column: Control
var _controls: ControlsMenu
## The "are you sure?" box for _quit_button, and what quitting does.
var _confirm: Control
var _confirm_stay: Button
var _quit_action: Callable
## [player, PlayerStats] pairs, in player order.
var _cards: Array = []
var _stats_timer := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


## Leaving the scene with the menu open (quitting) mustn't leave the music
## paused.
func _exit_tree() -> void:
	if is_open():
		Global.set_music_paused(false)


func is_open() -> bool:
	return _root.visible


func open(page := Page.MENU) -> void:
	if not enabled or is_open():
		return
	if not squads_game:
		get_tree().paused = true
		Global.set_music_paused(true)
	_refresh_stats()
	_music_slider.set_value_no_signal(Global.music_volume * 100.0)
	_sfx_slider.set_value_no_signal(Global.sfx_volume * 100.0)
	_hide_controls()
	_confirm.hide()
	_root.show()
	_show_page(page)


func close() -> void:
	if not is_open():
		return
	_hide_controls()
	_confirm.hide()
	_root.hide()
	if not squads_game:
		get_tree().paused = false
		Global.set_music_paused(false)


func _show_page(page: Page) -> void:
	_page = page
	_hide_controls()
	_menu_page.visible = page == Page.MENU
	_stats_page.visible = page == Page.STATS
	for i in _tab_styles.size():
		_tab_styles[i].bg_color = Color(ACCENT, 0.9) if i == page else Color(0, 0, 0, 0.45)
	if page == Page.MENU:
		_resume_button.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()


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


## While open, everything is read here, before the buttons and sliders see it
## (so the D-pad switches pages instead of moving a slider, and Tab isn't
## focus navigation).
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if _confirm.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
				or event.is_action_pressed("stats_menu"):
			_cancel_quit()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed("ui_cancel"):
		# B / Escape backs out of the controls, else resumes.
		if _controls.visible:
			_close_controls()
		else:
			close()
	elif event.is_action_pressed("pause"):
		_press_page_button(Page.MENU)
	elif event.is_action_pressed("stats_menu"):
		_press_page_button(Page.STATS)
	elif _switch_direction(event) != 0:
		_show_page(Page.STATS if _page == Page.MENU else Page.MENU)
	elif get_viewport().gui_get_focus_owner() == null and not _controls.visible \
			and _page == Page.MENU and (event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
		# Focus lost (e.g. mouse clicked the background): re-focus on nav input.
		_resume_button.grab_focus()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Opening the menu is left to _unhandled_input, so screens over the game
## (the shop, summaries) get Start first.
func _unhandled_input(event: InputEvent) -> void:
	# While disabled, leave input (e.g. Escape) for the game-over screen.
	if not enabled or is_open():
		return
	if event.is_action_pressed("pause"):
		open(Page.MENU)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("stats_menu") and (squads_game or not get_tree().paused):
		# Not over another paused screen (the shop has its own STATS tab).
		open(Page.STATS)
		get_viewport().set_input_as_handled()


## Start / Select while open: closes the menu if it's showing that page,
## otherwise switches to it.
func _press_page_button(page: Page) -> void:
	if _page == page and not _controls.visible:
		close()
	else:
		_show_page(page)


## -1 / 1 if `event` switches page (LB / RB, Q / E, the D-pad's left / right),
## else 0. The left stick and arrow keys still move sliders.
func _switch_direction(event: InputEvent) -> int:
	if event.is_action_pressed("menu_prev_tab"):
		return -1
	if event.is_action_pressed("menu_next_tab"):
		return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			return -1
		if event.button_index == JOY_BUTTON_DPAD_RIGHT:
			return 1
	return 0


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

	column.add_child(_build_tabs())
	_menu_page = _build_menu_page()
	column.add_child(_menu_page)
	_stats_page = _build_stats_page()
	column.add_child(_stats_page)

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

	_confirm = _build_confirm()
	_root.add_child(_confirm)


## LB  [MENU]  [STATS]  RB
func _build_tabs() -> Control:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 24)
	bar.add_child(ButtonPrompts.label("{LB}", MUTED, 64))
	for i in PAGE_NAMES.size():
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(16)
		style.content_margin_left = 48
		style.content_margin_right = 48
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		_tab_styles.append(style)
		var tab := PanelContainer.new()
		tab.add_theme_stylebox_override("panel", style)
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_show_page(i))
		var label := Label.new()
		label.text = PAGE_NAMES[i]
		label.add_theme_font_size_override("font_size", 72)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 12)
		tab.add_child(label)
		bar.add_child(tab)
	bar.add_child(ButtonPrompts.label("{RB}", MUTED, 64))
	return bar


func _build_menu_page() -> Control:
	# The theme's sign board.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

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

	var quit_text: String
	if boss_test:
		quit_text = "Back to Character Select"
		_quit_action = Global.go_to_character_select
	elif not squads_game:
		quit_text = "Quit Game"
		_quit_action = Global.go_to_title
	elif Squads.is_host():
		quit_text = "End Game for All Squads"
		_quit_action = Squads.return_to_lobby
	else:
		quit_text = "Leave Game"
		_quit_action = Global.go_to_title
	_quit_button = _button(quit_text)
	_quit_button.pressed.connect(_ask_quit)
	vbox.add_child(_quit_button)
	return panel


func _build_stats_page() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	vbox.add_child(row)
	var ordered := players.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.player_index < b.player_index)
	for player in ordered:
		var card := PlayerStats.new()
		row.add_child(card)
		_cards.append([player, card])
	vbox.add_child(ButtonPrompts.label("{B} Resume", MUTED, 56, 10))
	return vbox


## "Quit the game?" with Keep Playing (focused, so a stray A press is safe)
## and the quit button's own action.
func _build_confirm() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = _confirm_question()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(heading)

	var note := Label.new()
	note.text = _confirm_note()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 52)
	note.modulate = Color(1, 1, 1, 0.8)
	vbox.add_child(note)

	_confirm_stay = _button("Keep Playing")
	_confirm_stay.pressed.connect(_cancel_quit)
	vbox.add_child(_confirm_stay)
	var go := _button(_quit_button.text)
	go.pressed.connect(func() -> void: _quit_action.call())
	vbox.add_child(go)
	# Focus stays on these two: left to itself, navigation would reach the
	# menu's buttons behind the box.
	for pair in [[_confirm_stay, go], [go, _confirm_stay]]:
		var b: Button = pair[0]
		var other: NodePath = b.get_path_to(pair[1])
		var me: NodePath = b.get_path_to(b)
		b.focus_neighbor_top = other
		b.focus_neighbor_bottom = other
		b.focus_previous = other
		b.focus_next = other
		b.focus_neighbor_left = me
		b.focus_neighbor_right = me
	return overlay


func _confirm_question() -> String:
	if boss_test:
		return "Leave the Boss Test?"
	if squads_game and Squads.is_host():
		return "End the game for everyone?"
	if squads_game:
		return "Leave the game?"
	return "Quit the game?"


func _confirm_note() -> String:
	if squads_game and Squads.is_host():
		return "Every squad goes back to character select."
	return "This run's progress will be lost."


func _ask_quit() -> void:
	_confirm.show()
	_confirm_stay.grab_focus()


func _cancel_quit() -> void:
	_confirm.hide()
	_quit_button.grab_focus()


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
