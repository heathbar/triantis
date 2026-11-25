extends Control
## Character select: every connected controller (and the keyboard) can join,
## pick a character and ready up. Up to Global.MAX_PLAYERS players.
##
## Controls (per device):
##   A / Enter / Space  - join, then confirm character
##   Left / Right       - change character (D-pad, left stick or arrow keys;
##                        the bumpers / Q / E too). Sets the class and colour.
##   Up / Down          - change skin (scripts/player/player_skins.gd); purely
##                        cosmetic, any class can wear any skin
##   B / Escape         - un-ready, then leave; with nobody joined, back to title
##   Start              - same as A; once everyone is ready, A / Start begins
##   Y / R              - enter a name (up to Global.MAX_NAME_LENGTH), shown
##                        on the score screens instead of "P1".."P4"
##
## Naming opens an on-screen keyboard in that player's slot:
##   D-pad / stick - move, A - type the key, B / X - delete (B with nothing
##   left closes it), Y / Start - done. The keyboard player can just type
##   (Backspace deletes, Enter / Escape is done) or click the keys.
## Names are remembered per device for the session (Global.player_names).
##
## The mouse drives the keyboard player: click an empty slot to join it, click
## the arrows beside the name (or scroll) to change character, click the art
## to change skin, click the player name to enter one, click the rest of the slot to confirm / begin, right-click it to un-ready / leave. The Back button
## does what Escape does.
##
## A Boss Test (set up from the custom game screen, scripts/waves/boss_test.gd)
## shows in the heading.
##
## Campaign runs, once the Campaign has been won here
## (BraidModifiers.page_unlocked): beginning opens the modifiers page
## (scripts/ui/modifiers_menu.gd) first, and the run starts from there. In a
## Squads game only the host gets it.
##
## In a Squads game (see scripts/net/squads.gd) this screen picks the players
## for this instance's squad. The squads in the session are shown across the
## top; the host (always Alpha) starts once every squad is ready. While
## Global.sandbox_enabled() the host also gets a "+ Dummy squad" button, for
## testing alone (scripts/net/dummy_squad.gd).

const MenuInput := preload("res://scripts/ui/menu_input.gd")
const CharacterClasses := preload("res://scripts/character_classes.gd")
const Guns := preload("res://scripts/guns.gd")
const Melee := preload("res://scripts/melee.gd")
const Equipment := preload("res://scripts/equipment.gd")
const AttributeBar := preload("res://scripts/ui/attribute_bar.gd")
const Hearts := preload("res://scripts/ui/hearts.gd")
const PlayerSprite := preload("res://scripts/player/player_sprite.gd")
const PlayerSkins := preload("res://scripts/player/player_skins.gd")
const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const SandboxEditor := preload("res://scripts/ui/sandbox_editor.gd")
const BossTest := preload("res://scripts/waves/boss_test.gd")
const DummySquad := preload("res://scripts/net/dummy_squad.gd")
const ModifiersMenu := preload("res://scripts/ui/modifiers_menu.gd")
const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")
## After starting a dummy squad, its button waits this long (seconds) for it
## to join before another can be added.
const DUMMY_JOIN_WAIT := 4.0
const EMPTY_COLOR := Color(0.18, 0.2, 0.18)
## Slot cards are the title screen's wooden sign boards (the theme's
## PanelContainer style); an empty slot's board is darker.
const BOARD_COLOR := Color(0.37, 0.23, 0.12, 0.97)
const EMPTY_BOARD_COLOR := Color(0.27, 0.17, 0.09, 0.9)
const BORDER_IDLE := Color(0.22, 0.12, 0.05)
## Text outline, and the empty part of the attribute bars.
const OUTLINE_COLOR := Color(0.2, 0.11, 0.04)
const TRACK_COLOR := Color(0.17, 0.1, 0.05)
const POSITIVE_COLOR := AttributeBar.POSITIVE_COLOR
const NEGATIVE_COLOR := AttributeBar.NEGATIVE_COLOR
## The on-screen name keyboard, NAME_KEY_COLUMNS keys a row. Single
## characters type themselves; the rest are the special keys below.
const NAME_KEYS := [
	"A", "B", "C", "D", "E", "F", "G", "H",
	"I", "J", "K", "L", "M", "N", "O", "P",
	"Q", "R", "S", "T", "U", "V", "W", "X",
	"Y", "Z", "0", "1", "2", "3", "4", "5",
	"6", "7", "8", "9", "space", "case", "del", "done",
]
const NAME_KEY_COLUMNS := 8
const NAME_KEY_TEXT := {"space": "Spc", "case": "abc", "del": "Del", "done": "OK"}
const NAME_KEY_COLOR := Color(0.24, 0.14, 0.07)
## Besides letters and digits, what the keyboard player may type.
const NAME_EXTRA_CHARS := " -_.'!"


@onready var background: TextureRect = %Background
@onready var heading_label: Label = %Heading
@onready var squads_bar: HBoxContainer = %SquadsBar
@onready var slots_box: HBoxContainer = %Slots
@onready var hint_label: RichTextLabel = %Hint

## One entry per slot: {} when empty, else {"device", "character", "skin",
## "ready", "name", "editing", "key", "upper"}. "skin" indexes
## PlayerSkins.SKINS. While "editing" the name, "key" is the highlighted
## NAME_KEYS index and "upper" whether letters type in capitals.
var slots: Array[Dictionary] = []
## Node references for each slot's UI.
var views: Array[Dictionary] = []
## Squads game only: node references for each squad's roster chip.
var squad_views: Array[Dictionary] = []
var menu_input := MenuInput.new()
## The sandbox character's loadout screen while it's open (else null), and
## the slot it was opened for.
var sandbox_editor: Control
var sandbox_slot := -1
## The Campaign modifiers page while it's open (else null).
var modifiers_menu: Control
## Hosting with the sandbox on: the "+ Dummy squad" button (else null), and
## seconds left waiting for the last one started to join.
var dummy_button: Button
var _dummy_wait := 0.0
var _squads_before_dummy := 0


func _ready() -> void:
	resized.connect(_fit_background)
	_fit_background()
	for i in Global.MAX_PLAYERS:
		slots.append({})
		views.append(_build_slot_view(i))
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if Squads.is_active():
		_setup_squads()
	_build_back_button()
	_refresh()


## Tile the grass over the whole screen at its in-game pixel size.
func _fit_background() -> void:
	background.scale = Vector2.ONE * Global.MENU_GRASS_SCALE
	background.size = size / Global.MENU_GRASS_SCALE


func _setup_squads() -> void:
	# The squads bar replaces the heading to save vertical space.
	heading_label.hide()
	squads_bar.show()
	for i in Squads.MAX_SQUADS:
		squad_views.append(_build_squad_view(i))
	Squads.roster_changed.connect(_refresh)
	Squads.game_starting.connect(_start_game)
	if Squads.is_host() and Global.sandbox_enabled():
		_build_dummy_button()


func _input(event: InputEvent) -> void:
	# The sandbox loadout screen (or the modifiers page) takes all input
	# while it's open.
	if sandbox_editor or modifiers_menu:
		return
	# The keyboard player typing a name gets every key.
	var kb := _slot_of(Global.KEYBOARD)
	if kb != -1 and slots[kb]["editing"] and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed:
			_type_key(kb, event)
		return
	var press := menu_input.read(event)
	if press.is_empty():
		return
	var intent: String = press["intent"]
	var idx := _slot_of(press["device"])
	if idx != -1 and slots[idx]["editing"]:
		get_viewport().set_input_as_handled()
		_handle_name_entry(idx, intent)
		return
	if intent == "reroll":
		if idx != -1:
			get_viewport().set_input_as_handled()
			_start_name_entry(idx)
		return
	if intent == "start":
		intent = "accept"
	# The bumpers page through the characters too.
	elif intent == "prev_tab":
		intent = "left"
	elif intent == "next_tab":
		intent = "right"
	if intent not in ["accept", "back", "left", "right", "up", "down"]:
		return
	get_viewport().set_input_as_handled()
	_handle(press["device"], intent)


func _handle(device: int, intent: String) -> void:
	var idx := _slot_of(device)
	if idx != -1 and slots[idx]["editing"]:
		_handle_name_entry(idx, intent)
		return

	if idx == -1:
		match intent:
			"accept":
				_join(device)
			"back":
				if _joined_count() == 0:
					Global.go_to_title()
					return
		_refresh()
		return

	var slot := slots[idx]
	match intent:
		"left", "right":
			if not slot["ready"]:
				_cycle(idx, -1 if intent == "left" else 1)
		"up", "down":
			if not slot["ready"]:
				slot["skin"] = posmod(slot["skin"] + (-1 if intent == "up" else 1), PlayerSkins.count())
		"accept":
			if not slot["ready"]:
				if _is_sandbox(slot["character"]):
					_open_sandbox_editor(idx)
				elif not _is_locked(slot["character"], idx):
					slot["ready"] = true
			elif _all_ready():
				if not Squads.is_active():
					if not _open_modifiers():
						_start_game()
					return
				# Squads: the host starts everyone at once (via game_starting).
				if Squads.is_host() and Squads.all_squads_ready():
					if _open_modifiers() or Squads.start_game():
						return
		"back":
			if slot["ready"]:
				slot["ready"] = false
			else:
				slots[idx] = {}
	_refresh()


## Joins `device` into `preferred_slot` if it's free, else the first free slot.
func _join(device: int, preferred_slot := -1) -> void:
	var free_slot := -1
	if preferred_slot >= 0 and slots[preferred_slot].is_empty():
		free_slot = preferred_slot
	for i in slots.size():
		if free_slot == -1 and slots[i].is_empty():
			free_slot = i
			break
	if free_slot == -1:
		return
	# Prefer a character nobody else is showing; fall back to any unlocked one.
	var taken := []
	for s in slots:
		if not s.is_empty():
			taken.append(s["character"])
	var character := 0
	for c in Global.CHARACTERS.size():
		if c not in taken and _is_offered(c):
			character = c
			break
	slots[free_slot] = {"device": device, "character": character, "skin": 0, "ready": false,
		"name": Global.player_names.get(device, ""), "editing": false, "key": 0, "upper": true}


# --- Name entry ---------------------------------------------------------------

func _start_name_entry(idx: int) -> void:
	var slot := slots[idx]
	slot["editing"] = true
	slot["key"] = 0
	slot["upper"] = _wants_capital(slot["name"])
	_refresh()


## Capitals for the first letter of each word; lower case after.
static func _wants_capital(text: String) -> bool:
	return text == "" or text.ends_with(" ")


func _finish_name_entry(idx: int) -> void:
	var slot := slots[idx]
	slot["name"] = (slot["name"] as String).strip_edges()
	slot["editing"] = false
	Global.player_names[slot["device"]] = slot["name"]
	_refresh()


func _handle_name_entry(idx: int, intent: String) -> void:
	var slot := slots[idx]
	var key: int = slot["key"]
	var rows := ceili(float(NAME_KEYS.size()) / NAME_KEY_COLUMNS)
	var col := key % NAME_KEY_COLUMNS
	var row := floori(float(key) / NAME_KEY_COLUMNS)
	match intent:
		"left", "right":
			col = posmod(col + (-1 if intent == "left" else 1), NAME_KEY_COLUMNS)
		"up", "down":
			row = posmod(row + (-1 if intent == "up" else 1), rows)
		"accept":
			_press_name_key(idx, NAME_KEYS[key])
			return
		"back":
			if slot["name"] == "":
				_finish_name_entry(idx)
				return
			_press_name_key(idx, "del")
			return
		"bank":
			_press_name_key(idx, "del")
			return
		"reroll", "start":
			_finish_name_entry(idx)
			return
		_:
			return
	slot["key"] = row * NAME_KEY_COLUMNS + col
	_refresh()


func _press_name_key(idx: int, key: String) -> void:
	var slot := slots[idx]
	var text: String = slot["name"]
	match key:
		"done":
			_finish_name_entry(idx)
			return
		"case":
			slot["upper"] = not slot["upper"]
		"del":
			text = text.left(-1)
			slot["upper"] = _wants_capital(text)
		_:
			var c := " " if key == "space" else (key if slot["upper"] else key.to_lower())
			if text.length() < Global.MAX_NAME_LENGTH and not (c == " " and _wants_capital(text)):
				text += c
				slot["upper"] = _wants_capital(text)
	slot["name"] = text
	_refresh()


## The keyboard player typing their name on the real keyboard.
func _type_key(idx: int, event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
			if not event.echo:
				_finish_name_entry(idx)
			return
		KEY_BACKSPACE:
			_press_name_key(idx, "del")
			return
	var c := char(event.unicode) if event.unicode > 0 else ""
	if c == "" or not (c.is_valid_identifier() or c.is_valid_int() or c in NAME_EXTRA_CHARS):
		return
	var text: String = slots[idx]["name"]
	if text.length() < Global.MAX_NAME_LENGTH and not (c == " " and _wants_capital(text)):
		slots[idx]["name"] = text + c
		_refresh()


func _cycle(idx: int, dir: int) -> void:
	var c: int = slots[idx]["character"]
	for _i in Global.CHARACTERS.size():
		c = posmod(c + dir, Global.CHARACTERS.size())
		if _is_offered(c) and not _is_locked(c, idx):
			break
	slots[idx]["character"] = c


## True if another player has already confirmed this character.
func _is_locked(character: int, except_idx: int) -> bool:
	for i in slots.size():
		var s := slots[i]
		if i != except_idx and not s.is_empty() and s["ready"] and s["character"] == character:
			return true
	return false


## False for the sandbox character unless Global.sandbox_enabled().
func _is_offered(character: int) -> bool:
	return not _is_sandbox(character) or Global.sandbox_enabled()


func _is_sandbox(character: int) -> bool:
	return Global.CHARACTERS[character].get("sandbox", false)


## Shows the sandbox character's loadout screen; Done readies the slot.
func _open_sandbox_editor(idx: int) -> void:
	if sandbox_editor or _is_locked(slots[idx]["character"], idx):
		return
	sandbox_slot = idx
	sandbox_editor = SandboxEditor.new()
	sandbox_editor.finished.connect(_on_sandbox_editor_finished)
	add_child(sandbox_editor)


func _on_sandbox_editor_finished(confirmed: bool) -> void:
	sandbox_editor = null
	var idx := sandbox_slot
	sandbox_slot = -1
	if confirmed and idx >= 0 and not slots[idx].is_empty() \
			and _is_sandbox(slots[idx]["character"]) and not _is_locked(slots[idx]["character"], idx):
		slots[idx]["ready"] = true
	_refresh()


func _slot_of(device: int) -> int:
	for i in slots.size():
		if not slots[i].is_empty() and slots[i]["device"] == device:
			return i
	return -1


func _joined_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n


func _ready_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty() and s["ready"]:
			n += 1
	return n


func _all_ready() -> bool:
	if _joined_count() == 0:
		return false
	for s in slots:
		if not s.is_empty() and (not s["ready"] or s["editing"]):
			return false
	return true


func _start_game() -> void:
	var chosen: Array[Dictionary] = []
	for i in slots.size():
		var s := slots[i]
		if not s.is_empty():
			chosen.append({"slot": i, "device": s["device"], "character": s["character"],
				"skin": s["skin"], "name": s["name"]})
	Global.start_game(chosen)


## Whether beginning goes through the modifiers page: a Campaign run, once
## it's unlocked (in a Squads game, the host's choice).
func _wants_modifiers() -> bool:
	return Global.current_mode() == Global.MODE_BRAID and BraidModifiers.page_unlocked() \
		and (not Squads.is_active() or Squads.is_host())


## Opens the modifiers page if this run gets one (true), else false.
func _open_modifiers() -> bool:
	if not _wants_modifiers() or modifiers_menu:
		return false
	modifiers_menu = ModifiersMenu.new()
	modifiers_menu.finished.connect(_on_modifiers_finished)
	add_child(modifiers_menu)
	return true


func _on_modifiers_finished(confirmed: bool) -> void:
	modifiers_menu = null
	if confirmed and _all_ready():
		if not Squads.is_active():
			_start_game()
			return
		# (Someone may have un-readied meanwhile: then we stay here.)
		if Squads.start_game(Global.campaign_modifiers):
			return
	_refresh()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	menu_input.forget(device)
	var idx := _slot_of(device)
	if idx != -1:
		slots[idx] = {}
		if idx == sandbox_slot and sandbox_editor:
			sandbox_editor.queue_free()
			sandbox_editor = null
			sandbox_slot = -1
		_refresh()


# --- Mouse (acts as the keyboard player) ------------------------------------

func _on_slot_mouse(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var kb := Global.KEYBOARD
	var own := _slot_of(kb)
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if own == -1:
				if slots[i].is_empty():
					_join(kb, i)
					_refresh()
			elif own == i and slots[i]["editing"]:
				var key := _name_key_at(i, get_global_mouse_position())
				if key != -1:
					slots[i]["key"] = key
					_press_name_key(i, NAME_KEYS[key])
			elif own == i:
				if views[i]["tag"].get_global_rect().has_point(get_global_mouse_position()):
					_start_name_entry(i)
				else:
					_handle(kb, _name_click_intent(i))
		MOUSE_BUTTON_RIGHT:
			if own == i and slots[i]["editing"]:
				_finish_name_entry(i)
			elif own == i:
				_handle(kb, "back")
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			if own == i and not slots[i]["editing"]:
				_handle(kb, "left")
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			if own == i and not slots[i]["editing"]:
				_handle(kb, "right")
		_:
			return
	accept_event()


## A click on the left / right third of the "<  Name  >" label changes
## character, one on the art changes skin; anywhere else on the slot confirms.
func _name_click_intent(i: int) -> String:
	if slots[i]["ready"]:
		return "accept"
	var mouse := get_global_mouse_position()
	if views[i]["square"].get_global_rect().has_point(mouse):
		return "down"
	var rect: Rect2 = views[i]["name"].get_global_rect()
	if rect.has_point(mouse):
		if mouse.x < rect.position.x + rect.size.x / 3.0:
			return "left"
		if mouse.x > rect.end.x - rect.size.x / 3.0:
			return "right"
	return "accept"


## The NAME_KEYS index of slot `i`'s on-screen key under `point`, or -1.
func _name_key_at(i: int, point: Vector2) -> int:
	var keys: Array = views[i]["keys"]
	for k in keys.size():
		if keys[k]["panel"].get_global_rect().has_point(point):
			return k
	return -1


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _build_back_button() -> void:
	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 48)
	back.custom_minimum_size = Vector2(300, 100)
	back.position = Vector2(40, 40)
	back.pressed.connect(func() -> void: _handle(Global.KEYBOARD, "back"))
	add_child(back)


## Testing a squads game alone: starts another copy of the game that joins
## as a squad of one player who stands still (scripts/net/dummy_squad.gd).
func _build_dummy_button() -> void:
	dummy_button = Button.new()
	dummy_button.text = "+ Dummy squad"
	dummy_button.tooltip_text = "Testing: start another copy of the game that joins as a squad of one idle player."
	dummy_button.focus_mode = Control.FOCUS_NONE
	dummy_button.add_theme_font_size_override("font_size", 48)
	dummy_button.custom_minimum_size = Vector2(480, 100)
	dummy_button.anchor_left = 1.0
	dummy_button.anchor_right = 1.0
	dummy_button.offset_left = -520
	dummy_button.offset_right = -40
	dummy_button.offset_top = 40
	dummy_button.offset_bottom = 140
	dummy_button.pressed.connect(_add_dummy_squad)
	add_child(dummy_button)


func _add_dummy_squad() -> void:
	if DummySquad.launch() == -1:
		dummy_button.text = "Couldn't start one"
		return
	_dummy_wait = DUMMY_JOIN_WAIT
	_squads_before_dummy = Squads.roster.size()
	_refresh_dummy_button()


func _refresh_dummy_button() -> void:
	if dummy_button == null:
		return
	if Squads.roster.size() > _squads_before_dummy:
		_dummy_wait = 0.0  # it's in
	var full := Squads.roster.size() >= Squads.MAX_SQUADS
	dummy_button.disabled = full or _dummy_wait > 0.0
	dummy_button.text = "Joining..." if _dummy_wait > 0.0 and not full else "+ Dummy squad"


func _process(delta: float) -> void:
	if _dummy_wait > 0.0:
		_dummy_wait -= delta
		if _dummy_wait <= 0.0:
			_refresh_dummy_button()


# --- UI ---------------------------------------------------------------------

## A wooden sign board for a slot or squad card (its own copy, so its
## colours can change).
func _board_style(margin: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = get_theme_stylebox("panel", "PanelContainer").duplicate()
	style.bg_color = BOARD_COLOR
	style.border_color = BORDER_IDLE
	style.set_content_margin_all(margin)
	return style


func _build_slot_view(i: int) -> Dictionary:
	var style := _board_style(24)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_slot_mouse.bind(i))
	slots_box.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# The player's name (or P1..P4), then the class name and description,
	# then the art.
	var tag_label := _label(vbox, "", 44)
	var name_label := _label(vbox, "", 64)
	var blurb := _label(vbox, "", 32)
	blurb.modulate = Color(1, 1, 1, 0.7)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.y = 84  # room for two lines, so panels don't jump

	var center := CenterContainer.new()
	vbox.add_child(center)
	# The player art, palette-swapped to the character's colour.
	var square := TextureRect.new()
	square.custom_minimum_size = Vector2(200, 200)
	square.texture = PlayerSkins.cropped_texture(0)
	square.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	square.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	square.material = PlayerSprite.make_material(EMPTY_COLOR)
	# Pixel art: keep its pixels crisp (the screen otherwise filters smoothly).
	square.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	center.add_child(square)
	# Which skin is showing; Up / Down change it.
	var skin_label := _label(vbox, "", 30)
	skin_label.modulate = Color(1, 1, 1, 0.6)

	var gun_label := _label(vbox, "", 36)
	gun_label.modulate = Color(1.0, 0.85, 0.5)

	# Attribute rows: name, bar, value. Hidden (but still taking space, so
	# every panel is the same height) while the slot is empty.
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 14)
	stats.add_theme_constant_override("v_separation", 10)
	vbox.add_child(stats)
	var bars: Array = []
	var values: Array = []
	for attr in CharacterClasses.ATTRIBUTES:
		var attr_name := _label(stats, attr["name"], 32)
		attr_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		attr_name.custom_minimum_size.x = 190
		# Lives is a heart count, so it gets hearts instead of a -100..+100 bar.
		var bar: Control
		if attr.get("hearts", false):
			bar = Hearts.new()
			bar.heart_size = 30
			bar.max_width = 220
		else:
			bar = AttributeBar.new()
			bar.track_color = TRACK_COLOR
			bar.custom_minimum_size = Vector2(220, 24)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(bar)
		bars.append(bar)
		var value_label := _label(stats, "", 32)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size.x = 76
		values.append(value_label)

	# The on-screen keyboard for typing a name, in place of the stats.
	var keyboard := GridContainer.new()
	keyboard.columns = NAME_KEY_COLUMNS
	keyboard.add_theme_constant_override("h_separation", 6)
	keyboard.add_theme_constant_override("v_separation", 6)
	keyboard.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	keyboard.hide()
	vbox.add_child(keyboard)
	var keys: Array = []
	for key: String in NAME_KEYS:
		var key_style := StyleBoxFlat.new()
		key_style.bg_color = NAME_KEY_COLOR
		key_style.set_border_width_all(4)
		key_style.set_corner_radius_all(8)
		var key_panel := PanelContainer.new()
		key_panel.custom_minimum_size = Vector2(62, 54)
		key_panel.add_theme_stylebox_override("panel", key_style)
		keyboard.add_child(key_panel)
		var key_label := _label(key_panel, NAME_KEY_TEXT.get(key, key), 30)
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		keys.append({"panel": key_panel, "style": key_style, "label": key_label})

	var status := ButtonPrompts.label("", Color.WHITE, 56, 10)
	status.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	vbox.add_child(status)
	# Clicks anywhere on the slot reach the panel (see _on_slot_mouse).
	_ignore_mouse(vbox)

	return {
		"style": style,
		"tag": tag_label, "keyboard": keyboard, "keys": keys,
		"square": square, "skin": skin_label, "name": name_label, "blurb": blurb, "gun": gun_label, "status": status,
		"stats": stats, "bars": bars, "values": values,
	}


func _build_squad_view(squad: int) -> Dictionary:
	var color: Color = Squads.SQUAD_COLORS[squad]
	var style := _board_style(20)
	# Our own squad's card is tinted with its colour so it stands out.
	if squad == Squads.my_squad():
		style.bg_color = style.bg_color.lerp(color, 0.3)
	style.border_color = color

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	panel.add_theme_stylebox_override("panel", style)
	squads_bar.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var title := _label(vbox, Squads.SQUAD_NAMES[squad], 56)
	title.add_theme_color_override("font_color", color)
	var status := _label(vbox, "", 36)
	return {"panel": panel, "status": status}


func _refresh_squads() -> void:
	Squads.set_local_status(_joined_count(), _ready_count())
	for squad in squad_views.size():
		var v := squad_views[squad]
		var e := Squads.squad_entry(squad)
		if e.is_empty():
			v["panel"].modulate.a = 0.35
			v["status"].text = "Open"
			continue
		v["panel"].modulate.a = 1.0
		if e["joined"] == 0:
			v["status"].text = "Choosing players"
		elif e["ready"] == e["joined"]:
			v["status"].text = "READY (%d)" % e["joined"]
		else:
			v["status"].text = "%d/%d ready" % [e["ready"], e["joined"]]


func _mode_name() -> String:
	return Global.mode_name(Global.current_mode())


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	# The theme's outline is sized for big menu text.
	if size < 48:
		label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


## The name of the boss being tested, or "" if no boss test is set.
func _boss_test_name() -> String:
	if not BossTest.is_active():
		return ""
	return Boss.boss_info(str(BossTest.settings()["boss"]))["name"]


func _refresh() -> void:
	if Squads.is_active():
		_refresh_squads()
	_refresh_dummy_button()
	var test_name := _boss_test_name()
	if not Squads.is_active():
		heading_label.text = "Boss Test  -  %s" % test_name if test_name != "" \
			else "Choose Your Character  -  %s Mode" % _mode_name()
	for i in slots.size():
		var s := slots[i]
		var v := views[i]
		if s.is_empty():
			_tint_preview(v["square"], EMPTY_COLOR, 0.5)
			v["square"].texture = PlayerSkins.cropped_texture(0)
			v["skin"].text = " "
			v["tag"].text = " "
			v["keyboard"].hide()
			v["stats"].show()
			v["name"].text = " "
			v["blurb"].text = " "
			v["gun"].text = " \n \n "
			v["stats"].modulate.a = 0.0
			ButtonPrompts.set_text(v["status"], "Press {A} to join")
			v["status"].modulate = Color(1, 1, 1, 0.5)
			v["style"].border_color = BORDER_IDLE
			v["style"].bg_color = EMPTY_BOARD_COLOR
			continue

		var character: Dictionary = Global.CHARACTERS[s["character"]]
		var class_data := CharacterClasses.get_class_data(character["class"])
		# The sandbox character shows its hand-set loadout.
		var loadout := Global.loadout_for_character(s["character"])
		var attrs: Dictionary = loadout["attributes"]
		var locked := _is_locked(s["character"], i)
		v["style"].bg_color = BOARD_COLOR
		v["blurb"].text = class_data["description"]
		var gun := Guns.get_gun(loadout["gun"])
		var melee := Melee.get_weapon(loadout["melee"])
		var equipment := Equipment.find(loadout["equipment"])
		v["gun"].text = "Gun: %s\nMelee: %s\nEquipment: %s" % [
			Guns.display_name(gun, loadout["gun_level"]),
			Melee.display_name(melee, loadout.get("melee_level", 0)),
			equipment.get("name", "None")]
		v["stats"].modulate.a = 0.5 if locked else 1.0
		for a in CharacterClasses.ATTRIBUTES.size():
			var attr: Dictionary = CharacterClasses.ATTRIBUTES[a]
			var value: int = attrs[attr["id"]]
			var value_label: Label = v["values"][a]
			if attr.get("hearts", false):
				v["bars"][a].max_health = value * CharacterClasses.HALVES_PER_HEART
				v["bars"][a].health = value * CharacterClasses.HALVES_PER_HEART
				value_label.text = str(value)
			else:
				v["bars"][a].value = value
				value_label.text = "%+d" % value if value != 0 else "0"
			# Coloured by how it compares to an average character.
			var diff: int = value - CharacterClasses.default_value(attr["id"])
			value_label.modulate = POSITIVE_COLOR if diff > 0 \
				else (NEGATIVE_COLOR if diff < 0 else Color(1, 1, 1, 0.6))
		_refresh_name(i)
		_tint_preview(v["square"], character["color"], 0.4 if locked else 1.0)
		v["square"].texture = PlayerSkins.cropped_texture(s["skin"])
		var skin_name: String = PlayerSkins.get_skin(s["skin"])["name"]
		v["skin"].text = skin_name if s["ready"] or PlayerSkins.count() < 2 \
			else "^  %s  v" % skin_name
		if s["editing"]:
			v["name"].text = class_data["name"]
			ButtonPrompts.set_text(v["status"], "{Y} done")
			v["status"].modulate = Color.WHITE
			v["style"].border_color = BORDER_IDLE.lerp(character["color"], 0.4)
		elif s["ready"]:
			v["name"].text = class_data["name"]
			v["status"].text = "READY!"
			v["status"].modulate = character["color"]
			v["style"].border_color = character["color"]
		else:
			v["name"].text = "<  %s  >" % class_data["name"]
			ButtonPrompts.set_text(v["status"], "Taken" if locked
				else ("{A} edit loadout" if _is_sandbox(s["character"]) else "{A} confirm"))
			v["status"].modulate = Color(1, 0.4, 0.4) if locked else Color.WHITE
			v["style"].border_color = BORDER_IDLE.lerp(character["color"], 0.4)

	var hint := ""
	if _all_ready() and Squads.is_active():
		if not Squads.is_host():
			hint = "Ready! Waiting for Alpha squad (the host) to start     {B} un-ready"
		elif Squads.all_squads_ready():
			hint = "All squads are ready! Press {A} or Start to %s" % _begin_word()
		else:
			hint = "Ready! Waiting for the other squads     {B} un-ready"
	elif _all_ready():
		hint = "Everyone's ready! Press {A} or Start to %s" % _begin_word()
	elif _joined_count() == 0 and Squads.is_active():
		hint = "Press {A} to join     {B} leave squads game"
	elif _joined_count() == 0:
		hint = "Press {A} to join     {B} back"
	else:
		hint = "{LB}{RB} class     {UP}{DOWN} skin     {Y} name     {A} confirm     {B} back"
	if _editing_count() > 0:
		hint = "Name:  {A} type     {B} delete     {Y} done"
	if Squads.is_active():
		hint = "%s mode     %s" % [_mode_name(), hint]
	ButtonPrompts.set_text(hint_label, hint)


## "pick modifiers" when beginning opens the modifiers page, else "begin".
func _begin_word() -> String:
	return "pick modifiers" if _wants_modifiers() else "begin"


func _editing_count() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty() and s["editing"]:
			n += 1
	return n


## Slot `i`'s name line, and its on-screen keyboard while typing one.
func _refresh_name(i: int) -> void:
	var s := slots[i]
	var v := views[i]
	var character: Dictionary = Global.CHARACTERS[s["character"]]
	var text: String = s["name"]
	var editing: bool = s["editing"]
	v["keyboard"].visible = editing
	v["stats"].visible = not editing
	v["tag"].modulate = Color.WHITE if text != "" or editing else Color(1, 1, 1, 0.55)
	v["tag"].add_theme_color_override("font_color", character["color"].lerp(Color.WHITE, 0.35))
	if editing:
		var cursor := "_" if text.length() < Global.MAX_NAME_LENGTH else ""
		v["tag"].text = "%s%s  (%d/%d)" % [text, cursor, text.length(), Global.MAX_NAME_LENGTH]
	else:
		v["tag"].text = Global.player_label(i, text)
	if not editing:
		return
	for k in NAME_KEYS.size():
		var key: String = NAME_KEYS[k]
		var view: Dictionary = v["keys"][k]
		var selected: bool = k == s["key"]
		view["style"].bg_color = NAME_KEY_COLOR.lerp(character["color"], 0.55) if selected else NAME_KEY_COLOR
		view["style"].border_color = Color.WHITE if selected else BORDER_IDLE
		if key.length() == 1 and key.is_valid_identifier():
			view["label"].text = key if s["upper"] else key.to_lower()
		elif key == "case":
			view["label"].text = "abc" if s["upper"] else "ABC"


## Recolours a slot's character preview; `brightness` below 1 dims all of it.
static func _tint_preview(preview: TextureRect, color: Color, brightness: float) -> void:
	var m := preview.material as ShaderMaterial
	m.set_shader_parameter("armor_color", color)
	m.set_shader_parameter("brightness", brightness)
