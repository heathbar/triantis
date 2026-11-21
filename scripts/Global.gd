extends Node

const SETTINGS_PATH := "user://settings.cfg"
const GAME_SCENE := "res://scenenodethings/main.tscn"
## Braid mode's game scene (scripts/braid/braid_game.gd), used in place of
## GAME_SCENE when the mode is MODE_BRAID.
const BRAID_SCENE := "res://scenenodethings/braid/braid_game.tscn"
const TITLE_SCENE := "res://scenenodethings/title_screen.tscn"
const CHARACTER_SELECT_SCENE := "res://scenenodethings/character_select.tscn"

## Every menu and HUD is laid out for this resolution and scaled to fit the
## window. (The game world isn't: it's drawn at PIXEL_ART_RESOLUTION by
## game_base.gd's pixel view, whatever the UI's resolution.)
## Enforced in code (see _apply_base_resolution) because the matching
## project.godot settings have been getting dropped when the editor re-saves.
const BASE_RESOLUTION := Vector2i(2880, 1864)

## The game world renders at this low resolution, then gets scaled up by a
## whole number to fill the window (640x360 x3 = 1920x1080), keeping pixels
## crisp. 1 world unit = 1 pixel of it.
const PIXEL_ART_RESOLUTION := Vector2i(640, 360)
## How the game world (game_base.gd's pixel view) is drawn:
## true  - at full screen resolution, with the camera zoomed in by the same
##         whole number. Art pixels are still exact NxN blocks, but things move
##         one screen pixel at a time, so motion is smooth. Rotated sprites and
##         drawn shapes (circles, lines) come out finer than the art pixels.
## false - at PIXEL_ART_RESOLUTION, then scaled up: strictly pixel-perfect
##         (everything, rotations too, snaps to the art's pixel grid), but
##         things move in whole art pixels (N screen pixels) at a time, which
##         looks choppy at most speeds.
const SMOOTH_PIXEL_MOTION := true

## Backdrop of the title screen, character select and arena shop: the grass,
## tiled, at the in-game pixel size (MENU_GRASS_SCALE UI units per texel, one
## texel per pixel of the PIXEL_ART_RESOLUTION view). Their look (wooden
## signs) is data/ui/menu_theme.tres.
const MENU_GRASS := preload("res://assets/meadow/environment/background-1.png")
const MENU_GRASS_SCALE := float(BASE_RESOLUTION.y) / PIXEL_ART_RESOLUTION.y
## Looped on the title screen, character select and the other menus
## (silence while the file doesn't exist).
const MENU_MUSIC := "res://assets/ui/menu-music.ogg"
## Looped in game: each act theme's (ActTheme) track, also used by the arena
## game as its theme changes. "%s" is the theme ("meadow" for the default).
const THEME_MUSIC := "res://assets/%s/environment/background.ogg"
## Looped during a theme's boss fight, when the theme has one (else its
## THEME_MUSIC carries on).
const BOSS_MUSIC := "res://assets/%s/boss/boss.ogg"
## Audio buses made at startup (both send to Master): the music player plays
## on MUSIC_BUS, everything else (gun shots) on SFX_BUS. Their volumes are
## the Music and Effects sliders in Settings.
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

const CharacterClasses := preload("res://scripts/character_classes.gd")

## Device id used for the keyboard player (joypad ids are always >= 0).
const KEYBOARD := -1
const MAX_PLAYERS := 4

## Selectable characters. Index into this array is stored in each player entry.
## "class" is a class id from scripts/character_classes.gd, which sets the
## character's starting attributes.
const CHARACTERS := [
	{"name": "Blue", "class": "soldier", "color": Color(0.2, 0.45, 1.0)},
	{"name": "Green", "class": "scavenger", "color": Color(0.2, 0.8, 0.25)},
	{"name": "Purple", "class": "sniper", "color": Color(0.6, 0.3, 0.9)},
	{"name": "Yellow", "class": "engineer", "color": Color(1.0, 0.85, 0.15)},
	{"name": "Orange", "class": "brawler", "color": Color(1.0, 0.55, 0.1)},
	{"name": "Cyan", "class": "scout", "color": Color(0.2, 0.9, 0.95)},
	{"name": "Pink", "class": "medic", "color": Color(1.0, 0.5, 0.8)},
	{"name": "Lime", "class": "gunner", "color": Color(0.7, 1.0, 0.2)},
	{"name": "Brown", "class": "tank", "color": Color(0.6, 0.38, 0.2)},
	{"name": "White", "class": "duelist", "color": Color(0.95, 0.95, 0.95)},
	# Sandbox character for testing and balancing: only offered when
	# sandbox_enabled(). Its loadout is set by hand (custom_loadout).
	{"name": "Black", "class": "custom", "color": Color(0.12, 0.12, 0.14), "sandbox": true},
]

## Environment variable that overrides when the sandbox ("Custom") character
## is offered: "1" always, "0" never. Unset: only when run from the editor.
const SANDBOX_ENV := "TRIANTIS_SANDBOX"

## Game modes chosen after "New ... Game" (squads games use the host's, see
## Squads.game_mode).
const MODE_STANDARD := "standard"
## Old mode (no longer on the menus): every wave is a random objective wave
## (scripts/objectives/). Custom games can do the same (objective_every 1).
const MODE_OBJECTIVE := "objective"
## The host picks the number of waves, which enemy and objective types are
## used, and how often an objective wave comes (scripts/waves/custom_run.gd).
const MODE_CUSTOM := "custom"
## Standard mode: every 4th wave has an objective (never a boss wave).
const STANDARD_OBJECTIVE_EVERY := 4
## Every boss of the standard run back to back, with a shop between
## (scripts/waves/boss_rush.gd).
const MODE_BOSS_RUSH := "boss_rush"
## Shown as "Campaign" everywhere in the UI. Each squad crosses its own
## lane, pushed along by a tide (scripts/braid/). Its own scene (BRAID_SCENE).
const MODE_BRAID := "braid"

## Players chosen on the character select screen.
## Each entry: {"slot": int (0-3), "device": int, "character": int,
## "skin": int, "name": String ("" = none)}
var players: Array[Dictionary] = []

## Longest player name the character select lets anyone type.
const MAX_NAME_LENGTH := 12
## Names typed on character select, by device, so a player who rejoins (or
## comes back after a run) keeps theirs. This session only.
var player_names := {}


## What score screens call a player: their name, or "P1".."P4" without one.
static func player_label(slot: int, player_name: String) -> String:
	return player_name if player_name != "" else "P%d" % (slot + 1)

## Mode of the next local game (MODE_STANDARD, MODE_CUSTOM, ...).
var game_mode := MODE_STANDARD
## Settings of the next local (or hosted) custom game: see
## CustomRun.default_settings. Empty until the custom game screen sets it.
var custom_settings := {}
## Boss Test settings (scripts/waves/boss_test.gd), set on the custom game
## screen: while "active", the next local game is just that boss. Kept for
## the session (switched off on returning to the title), not saved.
var boss_test := {}
## Picks each wave's objective in objective mode; every squad uses the host's.
var run_seed := 0

# Settings (persisted to user://settings.cfg)
var master_volume : float = 1.0   # 0.0 - 1.0
var fullscreen : bool = false
var squads_game_name : String = ""   # last name used when hosting a squads game
var squads_last_address : String = ""  # last address typed into "Join by address"
## Show the animated how-to before each objective wave.
var show_objective_tutorials : bool = true
var music_volume : float = 1.0   # 0.0 - 1.0, on top of master_volume
var sfx_volume : float = 1.0     # 0.0 - 1.0, on top of master_volume
## The sandbox character's loadout, set on its loadout screen
## (scripts/ui/sandbox_editor.gd); see loadout_for_character(). Persisted so
## the last test setup comes back next run.
var custom_loadout := {}

var _music: AudioStreamPlayer


func _ready() -> void:
	_apply_base_resolution()
	_setup_controller_ui_input()
	load_settings()
	_setup_buses()
	_setup_music()
	apply_settings()
	# Menus play the menu music; the games (GameBase) pick their own.
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()
	Squads.returned_to_lobby.connect(go_to_character_select)
	Squads.session_ended.connect(_on_squads_session_ended)
	# Playing from the editor: catch typos in the data tables straight away.
	if OS.has_feature("editor"):
		_check_data.call_deferred()


func _check_data() -> void:
	for problem in load("res://scripts/data_check.gd").problems():
		push_error("Data check: %s" % problem)


## Lost the squads session (e.g. the host dropped): back to the title screen,
## which shows Squads.notice. The title screen handles it itself if it's open.
func _on_squads_session_ended(_reason: String) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != TITLE_SCENE:
		go_to_title()


func _apply_base_resolution() -> void:
	var window := get_tree().root
	window.content_scale_size = BASE_RESOLUTION
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


## Every input action the game uses, set up here rather than only in
## project.godot (whose input settings the editor has dropped on re-saves).
## Menus respond to an Xbox-style controller: A = accept, B = cancel,
## D-pad / left stick = navigate. Controller events are for any controller
## (device -1): whoever reads an action checks which device pressed it.
func _setup_controller_ui_input() -> void:
	_ensure_joy_button("ui_accept", JOY_BUTTON_A)
	_ensure_joy_button("ui_cancel", JOY_BUTTON_B)
	_ensure_joy_button("escape", JOY_BUTTON_B)
	# Pause during gameplay: Escape / P on keyboard, Start on a controller.
	_ensure_key("pause", KEY_ESCAPE)
	_ensure_key("pause", KEY_P)
	_ensure_joy_button("pause", JOY_BUTTON_START)
	# Keyboard movement: WASD as well as the arrow keys (set in project.godot).
	_ensure_key("up", KEY_W)
	_ensure_key("left", KEY_A)
	_ensure_key("down", KEY_S)
	_ensure_key("right", KEY_D)
	# The keyboard player's other controls (scripts/player/character_body.gd).
	# Controller players use their sticks and triggers instead.
	_ensure_mouse_button("fire", MOUSE_BUTTON_LEFT)
	_ensure_key("melee", KEY_SPACE)
	_ensure_mouse_button("melee", MOUSE_BUTTON_RIGHT)
	_ensure_key("use_equipment", KEY_F)
	_ensure_key("drop", KEY_Q)
	_ensure_joy_button("drop", JOY_BUTTON_B)
	# The Vault's keypad: face buttons, or I / J / K / L laid out the same way.
	_ensure_key("code_a", KEY_K)
	_ensure_joy_button("code_a", JOY_BUTTON_A)
	_ensure_key("code_b", KEY_L)
	_ensure_joy_button("code_b", JOY_BUTTON_B)
	_ensure_key("code_x", KEY_J)
	_ensure_joy_button("code_x", JOY_BUTTON_X)
	_ensure_key("code_y", KEY_I)
	_ensure_joy_button("code_y", JOY_BUTTON_Y)
	# Shared screens where every player drives their own column
	# (scripts/ui/menu_input.gd: the shop, character select).
	_ensure_joy_button("menu_start", JOY_BUTTON_START)
	_ensure_key("menu_bank", KEY_X)
	_ensure_joy_button("menu_bank", JOY_BUTTON_X)
	_ensure_key("menu_reroll", KEY_R)
	_ensure_joy_button("menu_reroll", JOY_BUTTON_Y)
	_ensure_key("menu_prev_tab", KEY_Q)
	_ensure_joy_button("menu_prev_tab", JOY_BUTTON_LEFT_SHOULDER)
	_ensure_key("menu_next_tab", KEY_E)
	_ensure_joy_button("menu_next_tab", JOY_BUTTON_RIGHT_SHOULDER)
	# The HUD's debug readout (scripts/ui/health_hud.gd).
	_ensure_key("debug_menu", KEY_QUOTELEFT)
	_ensure_joy_button("ui_up", JOY_BUTTON_DPAD_UP)
	_ensure_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_ensure_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_joy_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_ensure_joy_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_ensure_joy_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)


func _ensure_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return
	var ev := InputEventJoypadButton.new()
	ev.device = -1  # any controller
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _ensure_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode == key:
			return
	var ev := InputEventKey.new()
	ev.device = -1  # any device
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _ensure_mouse_button(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and e.button_index == button:
			return
	var ev := InputEventMouseButton.new()
	ev.device = -1  # any device
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _ensure_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == signf(value):
			return
	var ev := InputEventJoypadMotion.new()
	ev.device = -1  # any controller
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _setup_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var bus := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, bus_name)
		AudioServer.set_bus_send(bus, &"Master")


func _setup_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	# Keeps playing while the game is paused (pause menu, shop, summaries).
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	# Loops tracks that aren't imported as looping.
	_music.finished.connect(_music.play)
	add_child(_music)


## Loops the music file at `path`. Already playing it: carries on. No such
## file: silence.
func play_music(path: String) -> void:
	if _music.stream and _music.stream.resource_path == path:
		return
	if not ResourceLoader.exists(path):
		_music.stop()
		_music.stream = null
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true  # Seamless; the `finished` replay is the fallback.
	_music.stream = stream
	_music.play()


## Loops act theme `theme`'s track (an ActTheme theme; "" = "meadow"), or its
## boss track for a boss fight (when it has one).
func play_theme_music(theme: String, boss := false) -> void:
	theme = theme if theme != "" else "meadow"
	if boss and ResourceLoader.exists(BOSS_MUSIC % theme):
		play_music(BOSS_MUSIC % theme)
	else:
		play_music(THEME_MUSIC % theme)


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene and not scene is GameBase:
		play_music(MENU_MUSIC)


func _set_bus_volume(bus_name: StringName, volume: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume))
	AudioServer.set_bus_mute(bus, volume <= 0.0)


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))
	AudioServer.set_bus_mute(bus, master_volume <= 0.0)
	_set_bus_volume(MUSIC_BUS, music_volume)
	_set_bus_volume(SFX_BUS, sfx_volume)

	if not fullscreen_supported():
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## The editor's embedded Game view can't change window mode, so fullscreen
## only works when the game runs in its own window (or an exported build).
func fullscreen_supported() -> bool:
	return not Engine.is_embedded_in_editor()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("squads", "game_name", squads_game_name)
	config.set_value("squads", "last_address", squads_last_address)
	config.set_value("gameplay", "objective_tutorials", show_objective_tutorials)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	if not custom_loadout.is_empty():
		config.set_value("sandbox", "loadout", custom_loadout)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(config.get_value("audio", "master_volume", master_volume), 0.0, 1.0)
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	squads_game_name = str(config.get_value("squads", "game_name", squads_game_name))
	squads_last_address = str(config.get_value("squads", "last_address", squads_last_address))
	show_objective_tutorials = bool(config.get_value("gameplay", "objective_tutorials",
		show_objective_tutorials))
	# Older settings had a music on/off switch instead of a volume.
	var music_default := music_volume if bool(config.get_value("audio", "music", true)) else 0.0
	music_volume = clampf(float(config.get_value("audio", "music_volume", music_default)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	var loadout: Variant = config.get_value("sandbox", "loadout", {})
	if loadout is Dictionary:
		custom_loadout = loadout


## True if the sandbox ("Custom") character is offered on character select:
## when running from the Godot editor, unless SANDBOX_ENV says otherwise.
func sandbox_enabled() -> bool:
	match OS.get_environment(SANDBOX_ENV):
		"1", "true", "yes":
			return true
		"0", "false", "no":
			return false
	return OS.has_feature("editor")


## What the character at `index` in CHARACTERS starts a game with:
## {"attributes", "gun", "gun_level", "melee", "melee_level", "equipment",
## "resources"}.
## The sandbox character uses custom_loadout; the rest use their class.
func loadout_for_character(index: int) -> Dictionary:
	var class_id: String = CHARACTERS[index]["class"]
	var loadout := {
		"attributes": CharacterClasses.starting_attributes(class_id),
		"gun": CharacterClasses.starting_gun(class_id),
		"gun_level": 0,
		"melee": CharacterClasses.starting_melee(class_id),
		"melee_level": 0,
		"equipment": CharacterClasses.starting_equipment(class_id),
		"resources": 0,
	}
	if not CHARACTERS[index].get("sandbox", false):
		return loadout
	var custom: Dictionary = custom_loadout
	var attrs: Dictionary = custom.get("attributes", {})
	for id in loadout["attributes"]:
		if attrs.has(id):
			loadout["attributes"][id] = CharacterClasses.clamp_attribute(id, int(attrs[id]))
	for key in ["gun", "melee", "equipment"]:
		if custom.has(key):
			loadout[key] = str(custom[key])
	loadout["gun_level"] = maxi(int(custom.get("gun_level", 0)), 0)
	loadout["melee_level"] = maxi(int(custom.get("melee_level", 0)), 0)
	loadout["resources"] = maxi(int(custom.get("resources", 0)), 0)
	return loadout


func device_name(device: int) -> String:
	if device == KEYBOARD:
		return "Keyboard"
	return "Controller"


func go_to_character_select() -> void:
	get_tree().paused = false
	players.clear()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


## The mode of the game being played: the host's in a squads game.
func current_mode() -> String:
	return Squads.game_mode if Squads.is_active() else game_mode


## Every how many waves an objective wave comes (wave N, 2N, ...; boss waves
## never have one); 0 = never. 1 = every wave.
func objective_every() -> int:
	match current_mode():
		MODE_STANDARD:
			return STANDARD_OBJECTIVE_EVERY
		MODE_OBJECTIVE:
			return 1
		MODE_CUSTOM:
			var settings := current_custom_settings()
			if settings.get("objectives", []).is_empty():
				return 0
			return maxi(0, int(settings.get("objective_every", 0)))
	return 0


## The custom game settings in play: the host's in a squads game.
func current_custom_settings() -> Dictionary:
	return Squads.custom_settings if Squads.is_active() else custom_settings


## Objective types (ids) the current game's waves are drawn from; empty means
## all of them.
func allowed_objectives() -> Array:
	if current_mode() == MODE_CUSTOM:
		return current_custom_settings().get("objectives", [])
	return []


## Display name of a game mode.
func mode_name(mode: String) -> String:
	match mode:
		MODE_OBJECTIVE:
			return "Objective"
		MODE_CUSTOM:
			return "Custom"
		MODE_BOSS_RUSH:
			return "Boss Rush"
		MODE_BRAID:
			return "Campaign"
	return "Standard"


func start_game(chosen_players: Array[Dictionary]) -> void:
	players = chosen_players
	run_seed = Squads.run_seed if Squads.is_active() else randi()
	get_tree().change_scene_to_file(BRAID_SCENE if current_mode() == MODE_BRAID else GAME_SCENE)


func go_to_title() -> void:
	# A boss test lasts until the title: don't let it linger into a real
	# game started later (the chosen boss and settings are kept).
	boss_test["active"] = false
	Squads.leave()
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)
