extends Control
## The title screen. Each menu is a screen-sized page laid out on a strip of
## grass, side by side: opening a menu pans the "camera" (the strip slides
## left) to the next screen to the right; going back pans back to the left.
## The menus currently open run left to right from the main menu (_stack);
## the deepest is on screen.

@onready var strip: Control = %Strip
@onready var grass: TextureRect = %Grass
@onready var main_menu: Control = %MainMenu
@onready var settings_menu: Control = %SettingsMenu
@onready var squads_menu: Control = %SquadsMenu
@onready var join_menu: Control = %JoinMenu
@onready var host_menu: Control = %HostMenu
@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var host_status: Label = %HostStatus
@onready var start_hosting_button: Button = %StartHostingButton
@onready var host_back_button: Button = %HostBackButton
@onready var new_local_game_button: Button = %NewLocalGameButton
@onready var new_squads_game_button: Button = %NewSquadsGameButton
@onready var settings_button: Button = %SettingsButton
@onready var controls_button: Button = %ControlsButton
@onready var quit_button: Button = %QuitButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var back_button: Button = %BackButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var squads_status: Label = %SquadsStatus
@onready var squads_back_button: Button = %SquadsBackButton
@onready var join_status: Label = %JoinStatus
@onready var host_list: VBoxContainer = %HostList
@onready var join_back_button: Button = %JoinBackButton
@onready var address_edit: LineEdit = %AddressEdit
@onready var address_join_button: Button = %AddressJoinButton
@onready var tutorials_check: CheckButton = %TutorialsCheck
@onready var music_slider: HSlider = %MusicSlider
@onready var music_value: Label = %MusicValue
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sfx_value: Label = %SfxValue
@onready var mode_menu: Control = %ModeMenu
@onready var standard_button: Button = %StandardButton
@onready var mode_back_button: Button = %ModeBackButton
@onready var custom_button: Button = %CustomButton
@onready var boss_rush_button: Button = %BossRushButton
## Campaign or Arena, after Local (or Squads > Host).
@onready var play_menu: Control = %PlayMenu
@onready var play_heading: Label = %PlayHeading
@onready var campaign_button: Button = %CampaignButton
@onready var arena_button: Button = %ArenaButton
@onready var play_back_button: Button = %PlayBackButton

const STANDARD_RUN := "res://data/waves/standard_run.tres"
## Seconds the camera takes to pan from one menu to the next.
const PAN_TIME := 0.55
## How many screens of grass run right of the main menu: more than the
## deepest menu (Squads > Play > Arena > Custom > Host is 5 screens in).
const GRASS_SCREENS := 8
## Heading colour on the sign boards (the .tscn headings match it).
const ACCENT := Color(1, 0.86, 0.5)
const CustomGameMenu := preload("res://scripts/ui/custom_game_menu.gd")
const BossTestMenu := preload("res://scripts/ui/boss_test_menu.gd")
## Custom game setup (number of waves, enemies, objectives), built in code.
var custom_menu: CustomGameMenu
const ControlsMenu := preload("res://scripts/ui/controls_menu.gd")
## Controller diagram with what each button does, built in code.
var controls_menu: ControlsMenu

## Session id of the host we're connecting to, or "" while just browsing.
## ADDRESS_JOIN while connecting to (or looking up) a typed address.
var _connecting_to := ""
## Bumped whenever the join menu opens or closes, so a hostname lookup that
## finishes after the player left the menu is ignored.
var _join_attempt := 0

const ADDRESS_JOIN := "<address>"

## Every menu page on the strip.
var _pages: Array[Control] = []
## The menus open, main menu first; page i sits i screens right of the main
## menu, and the last one is on screen. Pages not in it are hidden (once the
## camera has panned away from them).
var _stack: Array[Control] = []
var _pan_tween: Tween
## How far right the camera is, in UI units (0 = the main menu).
var _camera_x := 0.0

## What the play / arena menus are choosing for: a local game, or a squads
## game we're about to host.
enum ModeFor { LOCAL, HOST }
var _mode_for := ModeFor.LOCAL


func _ready() -> void:
	new_local_game_button.pressed.connect(_on_new_local_game_pressed)
	new_squads_game_button.pressed.connect(_open_squads_menu)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(func(): get_tree().quit())
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_close_settings)
	host_button.pressed.connect(_open_play_menu.bind(ModeFor.HOST))
	start_hosting_button.pressed.connect(_start_hosting)
	game_name_edit.text_submitted.connect(func(_text): _start_hosting())
	game_name_edit.max_length = Squads.MAX_NAME_LENGTH
	host_back_button.pressed.connect(_close_host_menu)
	join_button.pressed.connect(_open_join_menu)
	squads_back_button.pressed.connect(_close_squads_menu)
	join_back_button.pressed.connect(_close_join_menu)
	address_join_button.pressed.connect(_join_by_address)
	address_edit.text_submitted.connect(func(_text): _join_by_address())
	tutorials_check.toggled.connect(func(pressed: bool) -> void:
		Global.show_objective_tutorials = pressed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	standard_button.pressed.connect(_choose_mode.bind(Global.MODE_STANDARD))
	boss_rush_button.pressed.connect(_choose_mode.bind(Global.MODE_BOSS_RUSH))
	custom_button.pressed.connect(_open_custom_menu)
	mode_back_button.pressed.connect(_close_mode_menu)
	campaign_button.pressed.connect(_choose_mode.bind(Global.MODE_BRAID))
	arena_button.pressed.connect(_open_mode_menu)
	play_back_button.pressed.connect(_close_play_menu)

	custom_menu = CustomGameMenu.new()
	custom_menu.name = "CustomMenu"
	var standard_run: WaveSet = load(STANDARD_RUN)
	custom_menu.build(mode_menu.get_node("Panel").get_theme_stylebox("panel"), standard_run.wave_count())
	custom_menu.confirmed.connect(_on_custom_confirmed)
	custom_menu.cancelled.connect(_close_custom_menu)
	custom_menu.boss_test_requested.connect(_open_boss_test_menu)
	strip.add_child(custom_menu)

	controls_button.pressed.connect(_open_controls)
	controls_menu = ControlsMenu.new()
	controls_menu.name = "ControlsMenu"
	controls_menu.build(mode_menu.get_node("Panel").get_theme_stylebox("panel"), ACCENT)
	controls_menu.closed.connect(_close_controls)
	strip.add_child(controls_menu)

	_pages = [main_menu, settings_menu, squads_menu, join_menu, host_menu, play_menu,
		mode_menu, custom_menu, controls_menu]
	for page in _pages:
		# Placed by _layout(), not stretched over the screen.
		page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		page.hide()
	resized.connect(_layout)

	for control in find_children("*", "BaseButton", true, false) \
			+ find_children("*", "Range", true, false):
		_focus_on_hover(control)

	Squads.hosts_changed.connect(_rebuild_host_list)
	Squads.joined.connect(_on_joined)
	Squads.session_ended.connect(_on_session_ended)

	# Quit isn't meaningful in a web export, and Squads needs ENet (UDP),
	# which browsers don't allow (see Squads.is_supported()).
	quit_button.visible = not OS.has_feature("web")
	new_squads_game_button.visible = Squads.is_supported()

	# Back from a squads game that ended (host left, etc.): say why.
	if not Squads.notice.is_empty():
		_reset_to([main_menu, squads_menu])
		_set_squads_status(Squads.notice)
		Squads.notice = ""
		host_button.grab_focus()
	else:
		_reset_to([main_menu])
		new_local_game_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Escape / B (controller) backs out of whichever sub-menu is open.
	if event.is_action_pressed("escape"):
		var current := _current()
		if current == settings_menu:
			_close_settings()
		elif current == controls_menu:
			_close_controls()
		elif current == custom_menu:
			_close_custom_menu()
		elif current == mode_menu:
			_close_mode_menu()
		elif current == play_menu:
			_close_play_menu()
		elif current == join_menu:
			_close_join_menu()
		elif current == host_menu:
			_close_host_menu()
		elif current == squads_menu:
			_close_squads_menu()
		else:
			return
		get_viewport().set_input_as_handled()
		return

	# If focus was lost (e.g. mouse clicked the background), let a controller or
	# keyboard press re-focus the menu so A / Enter keeps working.
	if get_viewport().gui_get_focus_owner() == null:
		for action in ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right"]:
			if event.is_action_pressed(action):
				_default_focus().grab_focus()
				get_viewport().set_input_as_handled()
				return


## Hovering a button / slider moves the keyboard-controller focus to it, so
## only one thing ever looks selected.
func _focus_on_hover(control: Control) -> void:
	control.mouse_entered.connect(func() -> void:
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE \
				and not (control is BaseButton and control.disabled):
			control.grab_focus())


func _default_focus() -> Control:
	var current := _current()
	if current == settings_menu:
		return volume_slider
	if current == controls_menu:
		return controls_menu.back_button
	if current == custom_menu:
		return custom_menu.continue_button
	if current == mode_menu:
		match Global.game_mode:
			Global.MODE_CUSTOM:
				return custom_button
			Global.MODE_BOSS_RUSH:
				return boss_rush_button
		return standard_button
	if current == play_menu:
		return campaign_button
	if current == join_menu:
		return host_list.get_child(0) if host_list.get_child_count() > 0 else address_edit
	if current == host_menu:
		return game_name_edit
	if current == squads_menu:
		return host_button
	return new_local_game_button


# --- Menu pages and the camera ------------------------------------------------

## The menu on screen (or being panned to).
func _current() -> Control:
	return _stack.back() if not _stack.is_empty() else main_menu


## Open `page` one screen right of the current menu and pan over to it.
func _push(page: Control) -> void:
	_stack.append(page)
	# A menu still sliding away after going back may sit in that spot.
	_hide_offstage()
	page.show()
	_layout_page(page, _stack.size() - 1)
	_pan()


## Pan back to the menu left of the current one.
func _pop() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_pan()


## Jump straight (no pan) to `pages` open, the last one on screen.
func _reset_to(pages: Array) -> void:
	_stack.assign(pages)
	_hide_offstage()
	_layout()
	_pan(true)


## Move the camera to the current menu, and let only that menu take focus
## and clicks (so arrow keys can't reach a menu off-screen).
func _pan(instant := false) -> void:
	var current := _current()
	for page in _pages:
		var active := page == current
		page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if active \
			else Control.FOCUS_BEHAVIOR_DISABLED
		page.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if active \
			else Control.MOUSE_BEHAVIOR_DISABLED
		if page in _stack:
			page.show()
	if _pan_tween:
		_pan_tween.kill()
	var target := (_stack.size() - 1) * size.x
	if instant:
		_set_camera_x(target)
		_hide_offstage()
		return
	# Starts from wherever the camera is, so a quick Back mid-pan turns round.
	_pan_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_pan_tween.tween_method(_set_camera_x, _camera_x, target, PAN_TIME)
	_pan_tween.tween_callback(_hide_offstage)


func _set_camera_x(x: float) -> void:
	_camera_x = x
	# Land on whole screen pixels so the grass's pixels don't shimmer.
	var pixels_per_unit := get_viewport().get_final_transform().x.x
	if pixels_per_unit > 0.0:
		x = roundf(x * pixels_per_unit) / pixels_per_unit
	strip.position.x = -x


func _hide_offstage() -> void:
	for page in _pages:
		if page not in _stack:
			page.hide()


## Size the pages and grass to the screen (which, in UI units, is wider on
## wide windows) and put the camera back on the current menu.
func _layout() -> void:
	for i in _stack.size():
		_layout_page(_stack[i], i)
	# Same size as the grass in game (see Global.MENU_GRASS_SCALE).
	var texel := Global.MENU_GRASS_SCALE
	grass.scale = Vector2(texel, texel)
	grass.position = Vector2(-size.x, 0)
	grass.size = Vector2(size.x * (GRASS_SCREENS + 1), size.y) / texel
	_pan(true)


func _layout_page(page: Control, column: int) -> void:
	page.position = Vector2(column * size.x, 0)
	page.size = size


func _on_new_local_game_pressed() -> void:
	_open_play_menu(ModeFor.LOCAL)


# --- Game mode ----------------------------------------------------------------

## Campaign or Arena: for a local game, or (Squads > Host) a hosted one.
func _open_play_menu(mode_for: ModeFor) -> void:
	_mode_for = mode_for
	play_heading.text = "Host a Game" if mode_for == ModeFor.HOST else "Local Game"
	_push(play_menu)
	_default_focus().grab_focus()


func _close_play_menu() -> void:
	_pop()
	if _mode_for == ModeFor.HOST:
		host_button.grab_focus()
	else:
		new_local_game_button.grab_focus()


## The Arena menu: Standard, Custom, Boss Rush.
func _open_mode_menu() -> void:
	_push(mode_menu)
	_default_focus().grab_focus()


func _close_mode_menu() -> void:
	_pop()
	arena_button.grab_focus()


func _choose_mode(mode: String) -> void:
	Global.game_mode = mode
	if _mode_for == ModeFor.HOST:
		_open_host_menu()
	else:
		Global.go_to_character_select()


# --- Custom game ----------------------------------------------------------------

func _open_custom_menu() -> void:
	_push(custom_menu)
	custom_menu.open(_mode_for == ModeFor.HOST)


func _close_custom_menu() -> void:
	_pop()
	custom_button.grab_focus()


func _on_custom_confirmed() -> void:
	_choose_mode(Global.MODE_CUSTOM)


## The Boss Test setup, over the custom game screen. Start goes to character
## select with the test armed (the mode doesn't matter: the run is just the
## boss); Cancel comes back here.
func _open_boss_test_menu() -> void:
	var menu := BossTestMenu.new()
	menu.finished.connect(func(confirmed: bool) -> void:
		if confirmed:
			Global.game_mode = Global.MODE_STANDARD
			Global.go_to_character_select()
		else:
			custom_menu.boss_test_button.grab_focus())
	add_child(menu)


# --- Squads -----------------------------------------------------------------

func _open_squads_menu() -> void:
	_set_squads_status("")
	_push(squads_menu)
	host_button.grab_focus()


## Back to the squads menu (from wherever past it), saying why.
func _return_to_squads_menu(message: String) -> void:
	var at := _stack.find(squads_menu)
	if at == -1:
		_reset_to([main_menu, squads_menu])
	else:
		_stack.resize(at + 1)
		_pan()
	_set_squads_status(message)
	host_button.grab_focus()


func _set_squads_status(message: String) -> void:
	squads_status.text = message
	squads_status.visible = not message.is_empty()


func _close_squads_menu() -> void:
	_pop()
	new_squads_game_button.grab_focus()


func _open_host_menu() -> void:
	game_name_edit.text = Global.squads_game_name if not Global.squads_game_name.is_empty() \
		else Squads.default_game_name()
	host_status.hide()
	_push(host_menu)
	# Start typing straight away; Enter hosts, Down reaches the buttons.
	game_name_edit.grab_focus()
	game_name_edit.select_all()
	game_name_edit.edit()


func _close_host_menu() -> void:
	# Back to the play or arena menu, or the custom settings just chosen.
	_pop()
	_default_focus().grab_focus()


func _start_hosting() -> void:
	var game_name := Squads.clean_game_name(game_name_edit.text)
	var custom := Global.custom_settings if Global.game_mode == Global.MODE_CUSTOM else {}
	var err := Squads.host(game_name, Global.game_mode, custom)
	if err != OK:
		host_status.text = "Couldn't host a game (%s). Is another game already hosting on this computer?" % error_string(err)
		host_status.show()
		start_hosting_button.grab_focus()
		return
	Global.squads_game_name = game_name
	Global.save_settings()
	Global.go_to_character_select()


func _open_join_menu() -> void:
	_join_attempt += 1
	_connecting_to = ""
	address_edit.text = Global.squads_last_address
	_set_address_row_enabled(true)
	_push(join_menu)
	Squads.start_browsing()
	_rebuild_host_list()


func _close_join_menu() -> void:
	_join_attempt += 1
	Squads.leave()
	_connecting_to = ""
	_pop()
	join_button.grab_focus()


func _rebuild_host_list() -> void:
	if _current() != join_menu or not _connecting_to.is_empty():
		return
	# Keep focus on the same host across rebuilds so the list doesn't jump.
	var focused := get_viewport().gui_get_focus_owner()
	var focused_id: String = focused.get_meta("host_id", "") if focused and focused.get_parent() == host_list else ""
	for child in host_list.get_children():
		host_list.remove_child(child)
		child.queue_free()

	var ids := Squads.hosts.keys()
	ids.sort_custom(func(a, b): return Squads.hosts[a]["name"] < Squads.hosts[b]["name"])
	for id in ids:
		var info: Dictionary = Squads.hosts[id]
		var button := Button.new()
		button.custom_minimum_size = Vector2(1300, 130)
		button.add_theme_font_size_override("font_size", 56)
		var state := "%d/%d squads" % [info["squads"], Squads.MAX_SQUADS] if info["open"] else "Full / in progress"
		var mode := Global.mode_name(str(info.get("mode", "")))
		button.text = "%s   (%s, %s)" % [info["name"], mode, state]
		button.disabled = not info["open"]
		button.set_meta("host_id", id)
		button.pressed.connect(_on_host_chosen.bind(id))
		_focus_on_hover(button)
		host_list.add_child(button)
		if id == focused_id:
			button.grab_focus()

	_set_address_row_enabled(true)
	join_status.text = "Searching the LAN..." if ids.is_empty() else "Choose a game to join"
	if get_viewport().gui_get_focus_owner() == null:
		_default_focus().grab_focus()


func _on_host_chosen(id: String) -> void:
	var info: Dictionary = Squads.hosts.get(id, {})
	if info.is_empty():
		return
	var err := Squads.join(info["ip"], info["port"])
	if err != OK:
		join_status.text = "Couldn't connect (%s)" % error_string(err)
		Squads.start_browsing()
		return
	_connecting_to = id
	join_status.text = "Joining %s..." % info["name"]
	for child in host_list.get_children():
		child.disabled = true
	_set_address_row_enabled(false)
	join_back_button.grab_focus()


func _join_by_address() -> void:
	if not _connecting_to.is_empty():
		return
	var target := Squads.parse_address(address_edit.text)
	if target.has("error"):
		join_status.text = target["error"]
		address_edit.grab_focus()
		return
	Global.squads_last_address = address_edit.text.strip_edges()
	Global.save_settings()
	# Hosts_changed won't rebuild the list while _connecting_to is set.
	_connecting_to = ADDRESS_JOIN
	for child in host_list.get_children():
		child.disabled = true
	_set_address_row_enabled(false)
	join_back_button.grab_focus()
	var host: String = target["host"]
	var attempt := _join_attempt
	if not host.is_valid_ip_address():
		join_status.text = "Looking up %s..." % host
	var ip: String = await Squads.resolve_host(host)
	if attempt != _join_attempt:
		return  # The player left the join menu meanwhile.
	if ip.is_empty():
		_connecting_to = ""
		_rebuild_host_list()
		join_status.text = "Couldn't find \"%s\"." % host
		address_edit.grab_focus()
		return
	# join() stops browsing.
	var err := Squads.join(ip, target["port"])
	if err != OK:
		_connecting_to = ""
		Squads.start_browsing()
		_rebuild_host_list()
		join_status.text = "Couldn't connect (%s)" % error_string(err)
		return
	join_status.text = "Connecting to %s..." % Global.squads_last_address


func _set_address_row_enabled(enabled: bool) -> void:
	address_edit.editable = enabled
	address_join_button.disabled = not enabled


func _on_joined() -> void:
	Global.go_to_character_select()


func _on_session_ended(reason: String) -> void:
	Squads.notice = ""
	if _current() == join_menu:
		# Failed to join: show why and keep browsing.
		var by_address := _connecting_to == ADDRESS_JOIN
		_connecting_to = ""
		Squads.start_browsing()
		_rebuild_host_list()
		join_status.text = reason
		if by_address and reason == Squads.CONNECT_FAILED:
			join_status.text += " Check the address, and that the host has forwarded UDP port %d." % Squads.GAME_PORT
	else:
		_return_to_squads_menu(reason)


# --- Controls ---------------------------------------------------------------

func _open_controls() -> void:
	_push(controls_menu)
	controls_menu.open()


func _close_controls() -> void:
	_pop()
	controls_button.grab_focus()


# --- Settings ---------------------------------------------------------------

func _open_settings() -> void:
	volume_slider.set_value_no_signal(Global.master_volume * 100.0)
	volume_value.text = "%d%%" % int(volume_slider.value)
	fullscreen_check.set_pressed_no_signal(Global.fullscreen)
	tutorials_check.set_pressed_no_signal(Global.show_objective_tutorials)
	music_slider.set_value_no_signal(Global.music_volume * 100.0)
	music_value.text = "%d%%" % int(music_slider.value)
	sfx_slider.set_value_no_signal(Global.sfx_volume * 100.0)
	sfx_value.text = "%d%%" % int(sfx_slider.value)
	if not Global.fullscreen_supported():
		fullscreen_check.disabled = true
		fullscreen_check.text = "Fullscreen (not in editor Game tab)"
		fullscreen_check.tooltip_text = "Fullscreen can't be used while the game is embedded in the editor's Game tab. Run it in a separate window or export it."
	_push(settings_menu)
	volume_slider.grab_focus()


func _close_settings() -> void:
	Global.save_settings()
	_pop()
	settings_button.grab_focus()


func _on_volume_changed(value: float) -> void:
	Global.master_volume = value / 100.0
	volume_value.text = "%d%%" % int(value)
	Global.apply_settings()


func _on_music_volume_changed(value: float) -> void:
	Global.music_volume = value / 100.0
	music_value.text = "%d%%" % int(value)
	Global.apply_settings()


func _on_sfx_volume_changed(value: float) -> void:
	Global.sfx_volume = value / 100.0
	sfx_value.text = "%d%%" % int(value)
	Global.apply_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	Global.fullscreen = pressed
	Global.apply_settings()
