extends Boss
## The Vault (boss of wave 20): a shielded strongbox in the middle of the map
## with a mortar on its roof. Shots and equipment can't touch it while its
## shield is up. Players drop the shield at a keypad, and then everyone gets
## a burn window to shoot it.
##
## Keypads: every squad has one on its own part of the map (one in a local
## game), and it moves after every burn window. A player standing on it gets
## a random code of face buttons (I/J/K/L on the keyboard), shown above them,
## and enters it one press at a time. A wrong press, moving, shooting or
## swinging starts their code over. Taking a hit doesn't. Codes get longer
## each window (CODE_LENGTHS) and are shorter for players with more
## engineering (ENGINEER_LENGTHS). The code length comes from whoever is
## typing, so an engineer is the natural pick.
##
## Burn window: a local game opens it with one code. In a squads game
## SQUADS_NEEDED squads must each enter a code, with no time limit between
## them (fewer if fewer squads are still up: an overwhelmed squad can't hold
## everyone up). Then the shield drops for BURN_TIME seconds and every squad
## can hit it. It comes back early once the window has taken WINDOW_CAP of
## its health, so even a team with huge damage needs three windows. When the
## shield comes back the keypads move, and the next code is longer.
##
## The mortar: every VOLLEY_EVERY seconds it lobs a shell at a player in each
## squad (two for a squad of three or more). It never aims at players at a
## keypad, and a shell that would land on a keypad is pushed off it, so the
## keypad is safe ground. A shell is marked on the ground for SHELL_FLIGHT
## seconds before it lands. Enraged: faster volleys and quicker landings.
##
## A player keeps their code for the window: stepping off the keypad and
## back on gives them the same code again (started over from the first press).
##
## Squads game: the host runs the shield, the windows and the mortar. Squads
## report a finished code (with the window number, so a late one doesn't
## count for the next window), where their players and keypad are and who's
## typing.
## Each squad places its own keypad, which only its own players see.

const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")

const RADIUS := 30.0
const DEFAULT_HEALTH := 12000
const ENRAGE_AT := 180.0

## Seconds the shield stays down, and the most of its health (a fraction of
## its full health) one window can take before the shield comes back.
const BURN_TIME := 15.0
const WINDOW_CAP := 0.4
## Squads game: squads that must enter a code to open a window.
const SQUADS_NEEDED := 2
## Code length for the 1st, 2nd and 3rd window (and every one after).
const CODE_LENGTHS := [4, 6, 8]
## [engineering above this, its code lengths], checked in order.
const ENGINEER_LENGTHS := [[50, [2, 3, 4]], [30, [3, 4, 5]]]
const BUTTONS := ["A", "B", "X", "Y"]
## A player whose centre is this close to the keypad is at it.
const KEYPAD_REACH := 14.0
## The keypad stays at least this far from the boss and from its last spot.
const KEYPAD_SPACING := 200.0
## Seconds a wrong press shows red.
const MISS_FLASH := 0.35

const FIRST_VOLLEY := 3.0
const VOLLEY_EVERY := 3.2
const ENRAGED_VOLLEY := 2.0
const SHELL_RADIUS := 24.0
const TargetMarker := preload("res://scripts/target_marker.gd")
const ExplosionArt := preload("res://scripts/explosion_art.gd")
const SHELL_FLIGHT := 1.6
const ENRAGED_SHELL_FLIGHT := 1.2
const SHELL_DAMAGE := 2
const SHELL_LINGER := ExplosionArt.DURATION
## Shells land up to this far off their target.
const SHELL_SCATTER := 10.0

const STEEL := Color(0.36, 0.4, 0.44)
const STEEL_DARK := Color(0.16, 0.18, 0.2)
const BRASS := Color(0.85, 0.7, 0.35)
const SHIELD := Color(0.45, 0.85, 1.0)
const DONE := Color(0.45, 0.95, 0.45)
const MISS := Color(1.0, 0.3, 0.25)
## The input action for each code button (see character_body.gd), whose key
## the keyboard player's keycap shows, and the colours the keycaps are drawn in.
const CODE_ACTIONS := {"A": &"code_a", "B": &"code_b", "X": &"code_x", "Y": &"code_y"}
const BUTTON_COLORS := {"A": Color(0.4, 0.85, 0.35), "B": Color(0.95, 0.35, 0.3),
	"X": Color(0.35, 0.6, 1.0), "Y": Color(1.0, 0.85, 0.3)}

var body: BossBody
var hp := 1
var max_hp := 1
## Burn windows opened so far (sets the code length).
var phase := 0
## Wave seconds when the current burn window ends, or -1 while shielded.
var open_until := -1.0
## Squads that have entered this window's code (the host's list).
var done_squads: Array = []
## Codes needed to open the window (the host's count).
var need := 1

## Our keypad, and the window number it was placed for.
var keypad_pos := Vector2.ZERO
var _keypad_phase := -1
## Our squad has entered this window's code (before the host says so).
var _local_done := false
## Our players at the keypad: player -> {"code": [buttons], "at": presses
## done, "miss": seconds of red left}.
var _codes := {}
## Codes our players were given this window, kept for when they step back
## onto the keypad: player -> [buttons].
var _kept := {}

## Host: player key -> [shared position, when heard, typing].
var _positions := {}
## Host: squad -> its keypad (shared position), so shells keep off it.
var _pads := {}
var _next_volley := FIRST_VOLLEY
## Host: health when the current window opened, and when the last one closed.
var _window_hp := 0
var _closed_at := -INF

var _ui: CanvasLayer
var _ui_canvas: Control


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	max_hp = scaled_health(base_health(DEFAULT_HEALTH))
	hp = max_hp
	body = add_body(0, shared_centre(), RADIUS, _paint)
	need = _codes_needed()
	_place_keypad()
	for player in game.all_players:
		player.shot_fired.connect(_on_player_shot.bind(player))
		player.melee_swung.connect(_interrupt.bind(player))
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui_canvas = Control.new()
	_ui_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.draw.connect(_draw_ui)
	_ui.add_child(_ui_canvas)
	add_child(_ui)


## The players' signals disconnect themselves when this is freed.
func _exit_tree() -> void:
	for player in game.all_players:
		if is_instance_valid(player) and player.keypad == self:
			player.keypad = null


func is_shielded() -> bool:
	return open_until < 0.0 and not is_defeated()


func is_open() -> bool:
	return open_until >= 0.0 and not is_defeated()


## Our squad has entered this window's code.
func our_code_done() -> bool:
	return _local_done or done_squads.has(my_squad)


# --- Every frame --------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	if is_authority:
		_host_think()
	if _keypad_phase != phase:
		_place_keypad()
	_tick_keypad(delta)
	_ui_canvas.queue_redraw()


## A new spot for our keypad, at least KEYPAD_SPACING from the boss and the
## old spot, and a clean slate for the new window's code.
func _place_keypad() -> void:
	var avoid := [shared_centre()]
	if _keypad_phase >= 0:
		avoid.append(keypad_pos)
	keypad_pos = random_point(own_area(), avoid, KEYPAD_SPACING)
	_keypad_phase = phase
	_local_done = false
	_codes.clear()
	_kept.clear()


## Who's at our keypad: a player standing on it gets a code, and loses it
## when they step off. Moving on the spot starts it over.
func _tick_keypad(delta: float) -> void:
	var usable := is_shielded() and not our_code_done()
	for player in game.all_players:
		var at_pad: bool = usable and not player.is_dead() \
			and player.global_position.distance_to(keypad_pos) <= KEYPAD_REACH
		if not at_pad:
			if player.keypad == self:
				player.keypad = null
			_codes.erase(player)
			continue
		player.keypad = self
		if not _codes.has(player):
			if not _kept.has(player):
				_kept[player] = _new_code(player)
			_codes[player] = {"code": _kept[player], "at": 0, "miss": 0.0}
		var entry: Dictionary = _codes[player]
		entry["miss"] = maxf(float(entry["miss"]) - delta, 0.0)
		if player.wants_to_move():
			entry["at"] = 0


func _new_code(player: Node) -> Array:
	var length: int = code_length(player.get_attribute("engineering"), phase)
	var code := []
	for i in length:
		code.append(BUTTONS.pick_random())
	return code


## Presses in a code for a player with `engineering`, for window `window`.
static func code_length(engineering: int, window: int) -> int:
	var lengths: Array = CODE_LENGTHS
	for row: Array in ENGINEER_LENGTHS:
		if engineering > int(row[0]):
			lengths = row[1]
			break
	return int(lengths[mini(window, lengths.size() - 1)])


## A face button pressed by a player at our keypad (character_body.gd).
func code_press(player: Node, button: String) -> void:
	if not _codes.has(player) or not is_shielded() or our_code_done():
		return
	var entry: Dictionary = _codes[player]
	var code: Array = entry["code"]
	if code[entry["at"]] != button:
		entry["at"] = 0
		entry["miss"] = MISS_FLASH
		return
	entry["at"] += 1
	if entry["at"] >= code.size():
		_local_done = true
		_codes.clear()
		_kept.clear()
		report({"code": phase})


## Shooting or swinging starts a player's code over.
func _interrupt(player: Node) -> void:
	if _codes.has(player):
		_codes[player]["at"] = 0


func _on_player_shot(_shot: Node, player: Node) -> void:
	_interrupt(player)


# --- Host -----------------------------------------------------------------------------

func _host_think() -> void:
	for player in living_players():
		_positions[key_of(player)] = [to_shared_pos(player.global_position), elapsed,
			_codes.has(player)]
	_pads[my_squad] = to_shared_pos(keypad_pos)
	for key in _positions.keys():
		if elapsed - float(_positions[key][1]) > POSITION_STALE:
			_positions.erase(key)

	if is_defeated():
		return
	need = _codes_needed()
	if is_shielded() and done_squads.size() >= need:
		open_until = elapsed + BURN_TIME
		_window_hp = hp
	elif is_open() and (elapsed >= open_until or hp <= _window_floor()):
		open_until = -1.0
		_closed_at = elapsed
		phase += 1
		done_squads.clear()

	if elapsed >= _next_volley:
		_next_volley = elapsed + (ENRAGED_VOLLEY if is_enraged() else VOLLEY_EVERY)
		_fire_volley()


## Codes it takes to open the window: one in a local game; in a squads game
## SQUADS_NEEDED, or every squad still up if there are fewer.
func _codes_needed() -> int:
	if not squads_game:
		return 1
	var up := present_squads().filter(func(s: int) -> bool: return squad_up(s)).size()
	return clampi(up, 1, SQUADS_NEEDED)


## A shell at a player in every squad (two for a squad of three or more),
## never at whoever is at a keypad, and never landing on a keypad.
func _fire_volley() -> void:
	var by_squad := {}
	for key in _positions:
		var squad := int(key) / 16
		if not by_squad.has(squad):
			by_squad[squad] = []
		by_squad[squad].append(key)
	var flight := ENRAGED_SHELL_FLIGHT if is_enraged() else SHELL_FLIGHT
	for squad in by_squad:
		var keys: Array = by_squad[squad]
		var targets := keys.filter(func(k: int) -> bool: return not bool(_positions[k][2]))
		if targets.is_empty():
			continue
		var shells := 2 if keys.size() >= 3 else 1
		for i in shells:
			var target: int = targets.pick_random()
			var shared: Vector2 = _positions[target][0] \
				+ Vector2.from_angle(randf() * TAU) * randf() * SHELL_SCATTER
			if _pads.has(squad):
				shared = _off_pad(shared, _pads[squad])
			var spot := to_local_pos(shared)
			var land := elapsed + flight + i * 0.25
			emit_hazard("shell", spot, land + SHELL_LINGER, {"land": land})


## `spot` moved straight out from keypad `pad` (both shared) until the shell's
## blast can't touch the keypad.
func _off_pad(spot: Vector2, pad: Vector2) -> Vector2:
	var clear := KEYPAD_REACH + SHELL_RADIUS
	var away := spot - pad
	if away.length() >= clear:
		return spot
	if away.length() < 0.01:
		away = Vector2.from_angle(randf() * TAU)
	return pad + away.normalized() * clear


func apply_damage(_part: int, amount: int, _squad: int) -> void:
	# Hits are only counted while the shield is down (and just after, for
	# reports still on their way).
	if not is_open() and elapsed - _closed_at > REPORT_INTERVAL * 2.0:
		return
	# A window can't take more than WINDOW_CAP of its health.
	hp = maxi(hp - amount, _window_floor())
	if hp == 0:
		defeat()


## The least health the current window can leave it on.
func _window_floor() -> int:
	return maxi(_window_hp - roundi(max_hp * WINDOW_CAP), 0)


func boss_report() -> Dictionary:
	if not squads_game:
		return {}
	var pos := {}
	for player in living_players():
		pos[key_of(player)] = [to_shared_pos(player.global_position), _codes.has(player)]
	return {"pos": pos, "pad": to_shared_pos(keypad_pos)}


func boss_receive(squad: int, data: Dictionary) -> void:
	if data.has("code") and int(data["code"]) == phase and is_shielded() \
			and not done_squads.has(squad):
		done_squads.append(squad)
	var pos: Dictionary = data.get("pos", {})
	for key in pos:
		_positions[int(key)] = [pos[key][0], elapsed, bool(pos[key][1])]
	if data.has("pad"):
		_pads[squad] = data["pad"]


func boss_state() -> Dictionary:
	return {"hp": hp, "max": max_hp, "phase": phase, "open": open_until,
		"done": done_squads, "need": need}


func apply_boss_state(state: Dictionary) -> void:
	hp = int(state.get("hp", hp))
	max_hp = int(state.get("max", max_hp))
	phase = int(state.get("phase", phase))
	open_until = float(state.get("open", open_until))
	done_squads = state.get("done", done_squads)
	need = int(state.get("need", need))


# --- Hits ---------------------------------------------------------------------------

func hit_multiplier(_body: Node, _at: Vector2) -> float:
	return 1.0 if is_open() else 0.0


# --- Hazards ------------------------------------------------------------------------

func hazard_tick(h: Dictionary, _delta: float) -> void:
	if h["kind"] == "shell" and not h.get("landed", false) and elapsed >= float(h["land"]):
		h["landed"] = true
		var at: Vector2 = h["pos"]
		hurt_players(func(p: Vector2) -> bool:
			return p.distance_to(at) <= SHELL_RADIUS + PLAYER_HALF, SHELL_DAMAGE)


func draw_hazard(h: Dictionary) -> void:
	if h["kind"] != "shell":
		return
	var at: Vector2 = h["pos"]
	var land := float(h["land"])
	if elapsed < land:
		var k := clampf((elapsed - float(h["born"])) / maxf(land - float(h["born"]), 0.01), 0.0, 1.0)
		draw_circle(at, SHELL_RADIUS, Color(1.0, 0.3, 0.15, 0.12))
		draw_circle(at, SHELL_RADIUS * k, Color(1.0, 0.35, 0.15, 0.3))
		TargetMarker.draw(self, at, SHELL_RADIUS)
		var height := (1.0 - k) * 120.0
		draw_circle(at + Vector2(0, -height), 3.0, Color(0.15, 0.12, 0.1))
	else:
		ExplosionArt.draw(self, at, elapsed - land, SHELL_RADIUS)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	super._draw()
	if is_defeated():
		return
	# Our keypad: a pad on the ground and a little terminal.
	var lit := is_shielded()
	var done := our_code_done()
	var tint: Color = DONE if done else (info["color"] if lit else STEEL)
	var pad := keypad_pos
	draw_circle(pad, KEYPAD_REACH, Color(tint, 0.18 if lit else 0.08))
	draw_arc(pad, KEYPAD_REACH, 0.0, TAU, 32, Color(tint, 0.8 if lit else 0.3), 1.0)
	var box := Rect2(pad + Vector2(-6, -KEYPAD_REACH - 12), Vector2(12, 10))
	draw_rect(box, STEEL_DARK)
	draw_rect(box, tint, false, 1.0)
	for i in 4:
		var dot := box.position + Vector2(3 + (i % 2) * 6, 3 + (i / 2) * 4)
		draw_rect(Rect2(dot - Vector2.ONE, Vector2(2, 2)), Color(tint, 0.9 if lit else 0.4))


func _paint(b: BossBody) -> void:
	if is_defeated():
		paint_death(b, RADIUS, elapsed - defeated_at, info["color"])
		return
	var aim := Vector2.UP
	var target := _nearest_player()
	if target:
		aim = b.global_position.direction_to(target.global_position)
	paint_vault(b, b.age, aim, is_shielded(), b.flash > 0.0)


func _nearest_player() -> Node2D:
	var best: Node2D = null
	for player in living_players():
		if best == null or player.global_position.distance_squared_to(body.global_position) \
				< best.global_position.distance_squared_to(body.global_position):
			best = player
	return best


static func paint_preview(c: CanvasItem, age: float) -> void:
	paint_vault(c, age, Vector2.from_angle(-PI / 2.0 + sin(age * 0.7) * 0.6), true, false)


## The Vault: a steel box with a dial on its door and a mortar on its roof
## aimed along `aim`, inside its shield bubble while `shielded`. `hit` flashes
## it (or the shield) for a hit.
static func paint_vault(c: CanvasItem, age: float, aim: Vector2, shielded: bool, hit: bool) -> void:
	var r := RADIUS
	c.draw_circle(Vector2(0, r * 0.3), r * 1.05, Color(0, 0, 0, 0.3))
	var box := Rect2(Vector2(-r * 0.85, -r * 0.8), Vector2(r * 1.7, r * 1.6))
	c.draw_rect(box, Color(1, 0.45, 0.4) if hit and not shielded else STEEL)
	c.draw_rect(box, STEEL_DARK, false, 2.0)
	# Rivets in the corners.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		c.draw_circle(corner * Vector2(r * 0.7, r * 0.65), 1.5, STEEL_DARK)
	# The door dial, turning.
	var dial := Vector2(0, r * 0.2)
	c.draw_circle(dial, r * 0.36, STEEL_DARK)
	c.draw_circle(dial, r * 0.3, BRASS)
	for i in 3:
		var a := age * 1.3 + i * TAU / 3.0
		c.draw_line(dial, dial + Vector2.from_angle(a) * r * 0.28, STEEL_DARK, 2.0)
	c.draw_circle(dial, r * 0.08, STEEL_DARK)
	# The mortar on the roof: a turret and a stubby barrel.
	var top := Vector2(0, -r * 0.45)
	c.draw_line(top, top + aim.normalized() * r * 0.6, STEEL_DARK, 7.0)
	c.draw_line(top, top + aim.normalized() * r * 0.6, Color(0.25, 0.27, 0.3), 4.0)
	c.draw_circle(top, r * 0.24, Color(0.25, 0.27, 0.3))
	c.draw_arc(top, r * 0.24, 0.0, TAU, 20, STEEL_DARK, 1.0)
	if shielded:
		var pulse := 0.5 + 0.2 * sin(age * 3.0)
		var shield := Color(1, 1, 1) if hit else SHIELD
		c.draw_circle(Vector2.ZERO, r * 1.3, Color(shield, 0.12 * pulse + (0.15 if hit else 0.0)))
		c.draw_arc(Vector2.ZERO, r * 1.3, 0.0, TAU, 48, Color(shield, 0.85), 1.0)
		for i in 6:
			var a := age * 0.5 + i * TAU / 6.0
			c.draw_arc(Vector2.ZERO, r * 1.3, a, a + 0.35, 6, Color(1, 1, 1, 0.6 * pulse), 2.0)


# --- Codes on screen (UI layer, so they're crisp) -----------------------------------

## Size of a code button on screen (UI units), and the gap between them.
const ICON := 64.0
const ICON_GAP := 10.0


func _draw_ui() -> void:
	if is_defeated() or not is_instance_valid(game):
		return
	var to_ui: Transform2D = game.world_to_ui()
	var font := ThemeDB.fallback_font
	if is_shielded():
		var label := "KEYPAD DONE" if our_code_done() else "KEYPAD"
		var color: Color = DONE if our_code_done() else info["color"]
		_ui_text(font, to_ui * (keypad_pos + Vector2(0, -KEYPAD_REACH - 18)), label, 40, color)
	for player in _codes:
		if not is_instance_valid(player):
			continue
		var entry: Dictionary = _codes[player]
		var code: Array = entry["code"]
		var at: int = entry["at"]
		var missed := float(entry["miss"]) > 0.0
		var width := code.size() * ICON + (code.size() - 1) * ICON_GAP
		var centre: Vector2 = to_ui * (player.global_position + Vector2(0, -24))
		var left := centre.x - width / 2.0
		var back := Rect2(left - 16, centre.y - ICON / 2.0 - 16, width + 32, ICON + 32)
		_ui_canvas.draw_rect(back, Color(0, 0, 0, 0.7))
		_ui_canvas.draw_rect(back, MISS if missed else Color(info["color"], 0.9), false, 4.0)
		for i in code.size():
			var rect := Rect2(left + i * (ICON + ICON_GAP), centre.y - ICON / 2.0, ICON, ICON)
			var tint := Color.WHITE
			if missed:
				tint = MISS
			elif i < at:
				tint = Color(1, 1, 1, 0.25)
			elif i > at:
				tint = Color(1, 1, 1, 0.7)
			if i == at and not missed:
				rect = rect.grow(6.0 + 3.0 * sin(elapsed * 10.0))
			_draw_button(code[i], rect, tint, player.device == Global.KEYBOARD, font)


## One code button: the controller's icon, or for the keyboard player a
## keycap with its letter.
func _draw_button(button: String, rect: Rect2, tint: Color, keyboard: bool, font: Font) -> void:
	if not keyboard:
		_ui_canvas.draw_texture_rect(ButtonPrompts.icon(button), rect, false, tint)
		return
	var color: Color = BUTTON_COLORS[button] * tint
	_ui_canvas.draw_rect(rect, Color(0.1, 0.1, 0.12, tint.a))
	_ui_canvas.draw_rect(rect, color, false, 4.0)
	var size := int(rect.size.y * 0.7)
	var pos := Vector2(rect.position.x, rect.get_center().y + size * 0.35)
	_ui_canvas.draw_string(font, pos, _key_letter(button), HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x, size, color)


## The keyboard key for code button `button` ("K" for "A" by default).
static func _key_letter(button: String) -> String:
	for e in InputMap.action_get_events(CODE_ACTIONS[button]):
		if e is InputEventKey:
			return e.as_text_physical_keycode()
	return "?"


func _ui_text(font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	var width := 600.0
	var pos := at + Vector2(-width / 2.0, size * 0.35)
	_ui_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 8,
		Color.BLACK)
	_ui_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


# --- HUD ----------------------------------------------------------------------------

func markers() -> Array:
	if is_defeated():
		return []
	if is_shielded() and not our_code_done():
		return [[keypad_pos, info["color"]]]
	return super.markers()


func bar_segments() -> Array:
	return [{"label": info["name"], "frac": float(hp) / maxf(max_hp, 1.0),
		"color": info["color"] if is_open() else SHIELD, "dim": is_shielded()}]


func bar_note() -> String:
	if is_defeated():
		return ""
	var note := ""
	if is_open():
		note = "SHIELD DOWN! Open fire: %d" % ceili(open_until - elapsed)
	elif not squads_game:
		note = "SHIELDED: stand still at the keypad and enter the code"
	else:
		var left := maxi(need - done_squads.size(), 1)
		if done_squads.is_empty() and not _local_done:
			note = "SHIELDED: %d squads must enter their keypad codes" % need
		elif our_code_done():
			note = "Your keypad is done: %d more squad%s must enter theirs" % [left, "" if left == 1 else "s"]
		else:
			var names := done_squads.map(func(s: int) -> String: return Squads.SQUAD_NAMES[s])
			note = "%s done: enter your keypad code!" % " & ".join(PackedStringArray(names))
	if is_enraged():
		note += "  (ENRAGED)"
	return note
