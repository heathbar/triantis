extends Node
## Dummy squad: a testing stand-in for a second squad, so a Squads game (a
## Campaign's windows, turrets, airstrikes, junctions and mirrors, or an
## arena) can be tried by one person.
##
## The host's character select has a "+ Dummy squad" button while
## Global.sandbox_enabled() (scripts/ui/character_select.gd). It calls
## launch(), which starts another copy of the game in a small, muted window
## with ARG on its command line. That copy (Global.dummy_squad) adds one of
## these as a child of Global, which:
##   - joins the game on this computer, and quits when the session ends
##     (the host leaves or stops),
##   - joins one player on character select and readies up (pressing A on
##     DEVICE, a controller that isn't there),
## and the game does the rest for a dummy:
##   - the player (Player.dummy) stands still, can't be hurt, and walls and
##     enemies don't stop it, so the Campaign's tide pushes it along its lane
##     through anything in the way (it never goes down),
##   - its squad always counts as at the checkpoint (braid_game.gd), so the
##     real squad decides when the shop opens,
##   - checkpoint and wave summaries skip themselves (wave_summary.gd); the
##     shop and Class Mod picker already ready up a player whose controller
##     isn't connected; boss intros and objective tutorials (turned off)
##     time out,
##   - it never saves settings (Global.save_settings) and starts windowed.
##   - vsync stays off (Global._keep_running_unseen), so it runs at full speed
##     behind other windows instead of slowing to a crawl (other squads would
##     see its enemies blink in and out).
## At the end of a run it waits on the final scores like any joiner until the
## host returns everyone to character select, then readies up again.
##
## TRIANTIS_DUMMY_HEADLESS=1 (in the host's environment) starts dummies with
## no window at all.

## On the dummy's command line (after "--").
const ARG := "--dummy-squad"
const HEADLESS_ENV := "TRIANTIS_DUMMY_HEADLESS"
## The dummy player's device: a controller id no real one gets.
const DEVICE := 90
const PLAYER_NAME := "Dummy"
## The dummy's window (the menus' 2880x1864 shape, small), stacked down the
## right of the screen.
const WINDOW_SIZE := Vector2i(720, 466)
const WINDOW_GAP := 40
## Seconds between presses on character select.
const PRESS_EVERY := 0.3

## How many this game has started (where the next one's window goes).
static var _launched := 0

var _press_timer := 0.0
var _joining := false


## True if this copy of the game was started as a dummy.
static func requested() -> bool:
	return ARG in OS.get_cmdline_user_args()


## Starts a dummy. Returns its process id, or -1.
static func launch() -> int:
	var args := PackedStringArray()
	# From the editor the executable is Godot itself: point it at the project.
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	if OS.get_environment(HEADLESS_ENV) in ["1", "true", "yes"]:
		args.append("--headless")
	else:
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var slot := posmod(_launched, maxi(screen.size.y / (WINDOW_SIZE.y + WINDOW_GAP), 1))
		var at := Vector2i(screen.end.x - WINDOW_SIZE.x - WINDOW_GAP,
			screen.position.y + WINDOW_GAP + slot * (WINDOW_SIZE.y + WINDOW_GAP))
		args.append_array(["--windowed", "--resolution", "%dx%d" % [WINDOW_SIZE.x, WINDOW_SIZE.y],
			"--position", "%d,%d" % [at.x, at.y]])
	args.append_array(["--", ARG])
	_launched += 1
	return OS.create_process(OS.get_executable_path(), args)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the shop and summaries pause the game
	Global.player_names[DEVICE] = PLAYER_NAME
	Squads.session_ended.connect(_on_session_ended)
	get_window().title = "Dummy squad"


func _on_session_ended(_reason: String) -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if not _joining:
		# Join once the title screen is up (it moves on to character select).
		if scene.scene_file_path != Global.TITLE_SCENE:
			return
		_joining = true
		var err := Squads.join("127.0.0.1", Squads.GAME_PORT)
		if err != OK:
			push_error("Dummy squad: couldn't join (%s)" % error_string(err))
			get_tree().quit(1)
		return
	if scene.scene_file_path != Global.CHARACTER_SELECT_SCENE:
		return
	_press_timer -= delta
	if _press_timer > 0.0:
		return
	_press_timer = PRESS_EVERY
	for slot: Dictionary in scene.slots:
		if not slot.is_empty() and slot["device"] == DEVICE and slot["ready"]:
			return
	# A to join, A again to confirm the character.
	_press(JOY_BUTTON_A)


func _press(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = DEVICE
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
