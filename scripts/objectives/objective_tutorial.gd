extends CanvasLayer
## The how-to shown before every objective wave (unless turned off in the
## settings: Global.show_objective_tutorials). A looping cartoon of the
## objective with its rules underneath. A / Enter / Start (or a click) moves
## on; it also moves on by itself after AUTO_CONTINUE seconds.
## Runs while the game is paused.

signal finished

const ButtonPrompts := preload("res://scripts/ui/button_prompts.gd")
const LOOP := 8.0
const AUTO_CONTINUE := 16.0
## Presses are ignored this long at first, so one meant for the screen before
## doesn't skip it.
const INPUT_DELAY := 0.6
const STAGE_SIZE := Vector2(1500, 640)
## Rule lines wrap at this width (the screen is 2560 wide).
const RULES_WIDTH := 2000.0
const PLAYER_COLORS := [Color(0.2, 0.45, 1.0), Color(0.2, 0.8, 0.25), Color(1.0, 0.55, 0.1)]
const ENEMY_COLOR := Color(0.9, 0.2, 0.2)
const PANEL_BG := Color(0.06, 0.08, 0.07, 0.96)

## Rules for each objective type (by id): what to do, plus the squads note.
const RULES := {
	"territory": [
		"Stand in your zone to capture it: it only fills while one of you is inside.",
		"Enemies in the zone contest it: capture slows to half speed.",
		"Capture it before the clock runs out, or you fail. The zone moves now and then.",
	],
	"crystal": [
		"Enemies go for the crystal. If it's destroyed, it's game over.",
		"Shield generators protect the crystal. Each one destroyed makes it weaker.",
		"Engineers repair generators, even destroyed ones, by standing next to them.",
		"Survive until the clock runs out.",
	],
	"hot_potato": [
		"Walk over the potato to pick it up. Carry it to the pit.",
		"While carrying you're slow and can't shoot. {B} drops it.",
		"It burns if you hold it too long, so pass it on. Too many blow up and you fail!",
		"Deliver them all before the clock runs out.",
	],
	"vip": [
		"The VIP only walks while one of you is close by. Its route changes every time.",
		"Enemies go for the VIP. If it dies, it's game over.",
		"Get it to the green flag before the clock runs out, or it's game over.",
	],
	"nests": [
		"Enemies pour out of the nests. Shoot the nests to destroy them.",
		"The big hive is shielded until every nest is destroyed.",
		"Destroy the hive before the clock runs out to win the wave.",
	],
	"herding_cats": [
		"Herd the cats into the pen in the far corner. A cat that gets there settles down and stays.",
		"Cats run from you, and the way you're heading: come at one from behind. Watch for the \"!\": it's about to dart sideways.",
		"Spread out and come at them from different sides, so they have nowhere to run but the pen.",
		"Gunfire spooks cats nearby. Pen enough of them before the clock runs out.",
	],
}
const SQUAD_RULES := {
	"territory": "Squads: every squad has its own zone. Capture fills at the share of squads holding theirs.",
	"crystal": "Squads: one crystal in the middle, and one shield generator on each squad's map.",
	"hot_potato": "Squads: the pit is in the middle. Deliveries count for everyone; a squad with 3 strikes is out for the wave.",
	"vip": "Squads: one VIP walks through every squad's map in turn. Be ready at the handover flag.",
	"nests": "Squads: each squad destroys its own nest. Then everyone meets at the hive in the middle.",
	"herding_cats": "Squads: herd your own cats from the middle out to your corner. Pens count for everyone, and other squads spook your cats.",
}

var type_id := ""
var squads_game := false
var _time := 0.0
var _stage: Control
var _bar: ProgressBar


## Shows the tutorial for objective type `type` (an entry in Objective.TYPES).
func play(type: Dictionary, in_squads_game: bool) -> void:
	type_id = type["id"]
	squads_game = in_squads_game
	_build(type)


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build(type: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_continue())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_border_width_all(6)
	style.border_color = type["color"]
	style.set_corner_radius_all(24)
	style.set_content_margin_all(36)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(_label("OBJECTIVE", Color(1, 1, 1, 0.6), 48))
	vbox.add_child(_label(type["name"], type["color"], 96))

	_stage = Control.new()
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.clip_contents = true
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	vbox.add_child(_stage)

	var rules: Array = RULES.get(type_id, [])
	for line: String in rules:
		vbox.add_child(_rule(line, Color.WHITE, 40))
	if squads_game and SQUAD_RULES.has(type_id):
		vbox.add_child(_rule(SQUAD_RULES[type_id], Color(1, 0.85, 0.4), 36))

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	_bar.max_value = AUTO_CONTINUE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bar)
	vbox.add_child(ButtonPrompts.label("{A} ready", Color(1, 1, 1, 0.75), 50, 8))


## A rule line. Long ones wrap at RULES_WIDTH instead of widening the panel
## off the screen. {A} / {B} / {X} / {Y} in it show as button icons.
func _rule(text: String, color: Color, size: int) -> Control:
	var label: Control
	if "{" in text:
		label = ButtonPrompts.label(text, color, size, 8)
		label.size_flags_horizontal = Control.SIZE_FILL
	else:
		label = _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = RULES_WIDTH
	return label


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	return label


func _process(delta: float) -> void:
	_time += delta
	if _bar:
		_bar.value = _time
	if _stage:
		_stage.queue_redraw()
	if _time >= AUTO_CONTINUE:
		_continue()


func _input(event: InputEvent) -> void:
	if _time < INPUT_DELAY or event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_start"):
		get_viewport().set_input_as_handled()
		_continue()


func _continue() -> void:
	if is_queued_for_deletion():
		return
	finished.emit()
	queue_free()


# --- The cartoon ---------------------------------------------------------------------

func _draw_stage() -> void:
	var s := _stage
	s.draw_rect(Rect2(Vector2.ZERO, STAGE_SIZE), Color(0.16, 0.26, 0.14))
	# Faint grass flecks.
	for i in 40:
		var p := Vector2(fmod(i * 397.0, STAGE_SIZE.x), fmod(i * 211.0, STAGE_SIZE.y))
		s.draw_line(p, p + Vector2(6, -14), Color(0.25, 0.4, 0.2), 4.0)
	var t := fmod(_time, LOOP)
	match type_id:
		"territory":
			_draw_territory(t)
		"crystal":
			_draw_crystal(t)
		"hot_potato":
			_draw_potato(t)
		"vip":
			_draw_vip(t)
		"nests":
			_draw_nests(t)
		"herding_cats":
			_draw_cats(t)
	s.draw_rect(Rect2(Vector2.ZERO, STAGE_SIZE), Color(1, 1, 1, 0.3), false, 4.0)


## 0..1: how far `t` is between `a` and `b` (eased).
static func _phase(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


func _player(at: Vector2, i: int, carrying := false) -> void:
	var c: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	_stage.draw_rect(Rect2(at - Vector2(30, 30), Vector2(60, 60)), Color.BLACK)
	_stage.draw_rect(Rect2(at - Vector2(26, 26), Vector2(52, 52)), c)
	_text(at + Vector2(0, 8), "P%d" % (i + 1), Color.WHITE, 26)
	if carrying:
		_potato(at + Vector2(0, -60), 1.0)


func _enemy(at: Vector2, size := 46.0) -> void:
	_stage.draw_rect(Rect2(at - Vector2.ONE * size / 2.0, Vector2.ONE * size), ENEMY_COLOR)
	_stage.draw_rect(Rect2(at - Vector2.ONE * size / 2.0, Vector2.ONE * size), Color.BLACK, false, 3.0)


func _shot(from: Vector2, to: Vector2, t: float) -> void:
	# A dash travelling from `from` to `to` as t goes 0..1.
	var p := from.lerp(to, fmod(t, 1.0))
	var dir := from.direction_to(to)
	_stage.draw_line(p - dir * 18.0, p + dir * 18.0, Color.WHITE, 6.0)


func _pop(at: Vector2, t: float) -> void:
	# A burst where something was destroyed (t 0..1).
	if t <= 0.0 or t >= 1.0:
		return
	_stage.draw_circle(at, 30.0 + 60.0 * t, Color(1, 0.7, 0.2, 0.6 * (1.0 - t)))


func _text(at: Vector2, text: String, color: Color, size := 34) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := at - Vector2(width / 2.0, 0)
	_stage.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color.BLACK)
	_stage.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A controller button icon (ButtonPrompts.ICONS) followed by `text`,
## centred on `at` (the text's baseline, like _text).
func _button_text(at: Vector2, button: String, text: String, color: Color, size := 34) -> void:
	var font := ThemeDB.fallback_font
	var icon_size := size * ButtonPrompts.ICON_SCALE
	var gap := size * 0.3
	var width := icon_size + gap + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var left := at.x - width / 2.0
	var icon_top := at.y - size * 0.35 - icon_size / 2.0
	_stage.draw_texture_rect(ButtonPrompts.icon(button),
		Rect2(Vector2(left, icon_top), Vector2(icon_size, icon_size)), false, color)
	var pos := Vector2(left + icon_size + gap, at.y)
	_stage.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color.BLACK)
	_stage.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _ring(at: Vector2, radius: float, frac: float, color: Color, width := 10.0) -> void:
	_stage.draw_arc(at, radius, 0.0, TAU, 48, Color(color, 0.25), width, true)
	if frac > 0.0:
		_stage.draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 48,
			color, width, true)


func _potato(at: Vector2, scale_by: float) -> void:
	_stage.draw_set_transform(at, 0.0, Vector2(1.25, 1.0) * scale_by)
	_stage.draw_circle(Vector2.ZERO, 26.0, Color.BLACK)
	_stage.draw_circle(Vector2.ZERO, 22.0, Color(0.62, 0.42, 0.22))
	_stage.draw_set_transform(Vector2.ZERO)
	_stage.draw_line(at + Vector2(10, -18), at + Vector2(18, -34), Color(0.2, 0.2, 0.2), 4.0)
	_stage.draw_circle(at + Vector2(18, -34), 6.0 + sin(_time * 30.0) * 2.0, Color(1, 0.85, 0.3))


func _draw_territory(t: float) -> void:
	var zone := Vector2(950, 340)
	var inside := t > 2.4
	var contested := t > 4.6 and t < 6.4
	var c := Color(0.35, 0.95, 0.45) if inside else Color.WHITE
	if contested:
		c = Color(1.0, 0.6, 0.2)
	_stage.draw_circle(zone, 190.0, Color(c, 0.15))
	_stage.draw_arc(zone, 190.0, 0.0, TAU, 64, c, 8.0, true)
	var player := Vector2(220, 380).lerp(zone + Vector2(-40, 30), _phase(t, 0.6, 2.4))
	_player(player, 0)
	# The enemy walks in and gets shot.
	if t > 4.0 and t < 6.4:
		var enemy := Vector2(1560, 200).lerp(zone + Vector2(110, -60), _phase(t, 4.0, 4.8))
		_enemy(enemy)
		if t > 5.4:
			_shot(player, enemy, (t - 5.4) * 3.0)
	_pop(zone + Vector2(110, -60), (t - 6.4) * 2.5)
	# Capture: only fills while someone's inside, half speed when contested.
	# The clock runs down regardless.
	var progress := 0.0
	if t > 2.4:
		progress = minf(t, 4.6) - 2.4
	if t > 4.6:
		progress += (minf(t, 6.4) - 4.6) * 0.5
	if t > 6.4:
		progress += t - 6.4
	_ring(Vector2(1360, 110), 60.0, progress / 6.0, Color(0.35, 0.95, 0.45), 14.0)
	_text(Vector2(1360, 205), "CAPTURE", Color.WHITE, 30)
	_text(Vector2(200, 110), "TIME  0:%02d" % maxi(40 - floori(t), 0), Color(1, 0.9, 0.5), 36)
	var label := "Stand in the zone!" if not inside else ("CONTESTED: half speed" if contested
		else "Capturing")
	_text(Vector2(zone.x, 110), label, c, 40)


func _draw_crystal(t: float) -> void:
	var crystal := Vector2(750, 330)
	var gens := [Vector2(220, 150), Vector2(1280, 500)]
	var gen_broken := t > 5.6
	# Beams and generators.
	for i in gens.size():
		var broken := i == 1 and gen_broken
		if not broken:
			_stage.draw_dashed_line(gens[i], crystal, Color(0.55, 0.9, 1.0, 0.5), 5.0, 26.0)
		var g: Vector2 = gens[i]
		_stage.draw_rect(Rect2(g - Vector2(50, 36), Vector2(100, 72)),
			Color(0.3, 0.1, 0.1) if broken else Color(0.15, 0.17, 0.2))
		_stage.draw_rect(Rect2(g - Vector2(50, 36), Vector2(100, 72)), Color(0.55, 0.9, 1.0), false, 5.0)
	_pop(gens[1], (t - 5.6) * 2.0)
	# The crystal and its shield (thinner once a generator's down).
	var shield := 0.5 if gen_broken else 1.0
	_stage.draw_circle(crystal, 130.0, Color(0.5, 0.85, 1.0, 0.1 + 0.15 * shield))
	_stage.draw_arc(crystal, 130.0, 0.0, TAU, 64, Color(0.6, 0.9, 1.0, 0.3 + 0.5 * shield), 6.0, true)
	var bob := sin(_time * 2.0) * 6.0
	_stage.draw_colored_polygon(PackedVector2Array([crystal + Vector2(0, -95 + bob),
		crystal + Vector2(50, bob), crystal + Vector2(0, 75 + bob), crystal + Vector2(-50, bob)]),
		Color(0.45, 0.85, 1.0))
	# Enemies march on the crystal; the player picks them off.
	var player := Vector2(560, 470)
	_player(player, 0)
	var starts := [Vector2(-40, 80), Vector2(1540, 120), Vector2(-40, 600)]
	for i in starts.size():
		var t0 := 0.4 + i * 1.3
		var dies := t0 + 2.2
		if t > t0 and t < dies:
			var e: Vector2 = (starts[i] as Vector2).lerp(crystal, _phase(t, t0, dies + 0.8) * 0.85)
			_enemy(e)
			if t > dies - 0.6:
				_shot(player, e, (t - dies + 0.6) * 1.7)
		_pop((starts[i] as Vector2).lerp(crystal, 0.6), (t - dies) * 2.5)
	# One goes for a generator instead.
	if t > 3.2 and t < 5.6:
		_enemy(Vector2(1560, 640).lerp(gens[1], _phase(t, 3.2, 4.6) * 0.8))
	_text(Vector2(750, 60), "Shields %d/2" % (1 if gen_broken else 2), Color(0.6, 0.9, 1.0), 40)


func _draw_potato(t: float) -> void:
	var pit := Vector2(1290, 330)
	_stage.draw_circle(pit, 110.0, Color(0.12, 0.06, 0.03))
	_stage.draw_arc(pit, 110.0, 0.0, TAU, 48, Color(1.0, 0.6, 0.2), 8.0, true)
	_text(pit + Vector2(0, 160), "PIT", Color(1.0, 0.6, 0.2), 38)
	var start := Vector2(180, 330)
	var p1_start := Vector2(120, 520)
	var handoff := Vector2(650, 330)
	var p2_wait := Vector2(760, 240)
	# P1 fetches it and carries it (slowly), heating up, then drops it.
	var p1 := p1_start.lerp(start, _phase(t, 0.2, 1.2))
	if t > 1.2:
		p1 = start.lerp(handoff, _phase(t, 1.2, 3.8))
	if t > 3.9:
		p1 = handoff.lerp(handoff + Vector2(-150, 150), _phase(t, 3.9, 4.3))
	var p1_carrying := t > 1.2 and t < 3.9
	var p2 := p2_wait
	if t > 4.1:
		p2 = p2_wait.lerp(handoff, _phase(t, 4.1, 4.5))
	if t > 4.5:
		p2 = handoff.lerp(pit + Vector2(-30, 0), _phase(t, 4.5, 7.0))
	var p2_carrying := t > 4.5 and t < 7.0
	_player(p1, 0, p1_carrying)
	_player(p2, 1, p2_carrying)
	if t < 1.2:
		_potato(start, 1.0)
	elif t >= 3.9 and t <= 4.5:
		_potato(handoff + Vector2(0, 40), 1.0)
	if t > 3.4 and t < 4.6:
		_button_text(handoff + Vector2(0, 130), "B", "drop it", Color.WHITE, 38)
	# P1's heat bar.
	var heat := clampf((t - 1.2) / 2.8, 0.0, 1.0) if t < 3.9 else maxf(1.0 - (t - 3.9) / 2.0, 0.0)
	if heat > 0.0:
		_stage.draw_rect(Rect2(p1 + Vector2(-50, -122), Vector2(100 * heat, 14)),
			Color(1, 0.8, 0.2).lerp(Color(1, 0.15, 0.1), heat))
		if t > 3.0 and t < 3.9:
			_text(p1 + Vector2(0, -136), "Too hot!", Color(1, 0.4, 0.3), 32)
	if t > 7.0:
		_text(pit + Vector2(0, -150), "DELIVERED!", Color(0.4, 1.0, 0.5), 48)
		_pop(pit, (t - 7.0) * 1.5)
	_text(Vector2(180, 80), "Fuse: %d" % ceili(45.0 - t * 3.0), Color(1, 0.9, 0.5), 40)


func _draw_vip(t: float) -> void:
	var path := [Vector2(130, 520), Vector2(480, 180), Vector2(880, 470), Vector2(1330, 200)]
	if squads_game:
		# The second half is the next squad's map.
		_stage.draw_rect(Rect2(Vector2(830, 0), Vector2(670, STAGE_SIZE.y)), Color(0.3, 0.6, 1.0, 0.12))
		_text(Vector2(1180, 600), "Next squad's map", Color(0.5, 0.75, 1.0), 32)
	for i in range(1, path.size()):
		_stage.draw_dashed_line(path[i - 1], path[i], Color(1.0, 0.85, 0.3, 0.6), 8.0, 28.0)
	var flag: Vector2 = path[-1]
	_stage.draw_line(flag, flag + Vector2(0, -90), Color.BLACK, 6.0)
	_stage.draw_colored_polygon(PackedVector2Array([flag + Vector2(0, -90), flag + Vector2(60, -72),
		flag + Vector2(0, -54)]), Color(0.4, 1.0, 0.5))
	# The VIP walks while escorted (it pauses from 3.0 to 4.0: nobody near).
	var walk := _phase(t, 0.3, 3.0) * 0.45 + _phase(t, 4.0, 7.5) * 0.55
	var vip := _along(path, walk)
	_stage.draw_arc(vip, 170.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.3, 0.35), 5.0, true)
	_stage.draw_circle(vip, 42.0, Color.BLACK)
	_stage.draw_circle(vip, 36.0, Color(1.0, 0.85, 0.3))
	_text(vip + Vector2(0, 12), "VIP", Color.BLACK, 28)
	var p1 := vip + Vector2(-110, 70)
	if t > 2.7 and t < 4.0:
		p1 = _along(path, 0.45) + Vector2(-110, 70) + Vector2(-260, 120) * sin(_phase(t, 2.7, 4.0) * PI)
		_text(vip + Vector2(0, -70), "Waiting for an escort...", Color.WHITE, 32)
	_player(p1, 0)
	_player(vip + Vector2(100, 90), 1)
	# An enemy goes for the VIP and is shot down.
	if t > 4.6 and t < 6.0:
		var e := Vector2(1300, 640).lerp(vip, _phase(t, 4.6, 6.4) * 0.7)
		_enemy(e)
		if t > 5.4:
			_shot(vip + Vector2(100, 90), e, (t - 5.4) * 1.7)
	_pop(Vector2(1300, 640).lerp(_along(path, 0.75), 0.65), (t - 6.0) * 2.5)


## The point `frac` of the way along a polyline.
static func _along(path: Array, frac: float) -> Vector2:
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector2).distance_to(path[i - 1])
	var want := clampf(frac, 0.0, 1.0) * total
	for i in range(1, path.size()):
		var seg := (path[i] as Vector2).distance_to(path[i - 1])
		if want <= seg:
			return (path[i - 1] as Vector2).lerp(path[i], want / maxf(seg, 0.001))
		want -= seg
	return path[-1]


func _draw_nests(t: float) -> void:
	var nests := [Vector2(220, 150), Vector2(220, 500), Vector2(1300, 160)]
	var breaks := [1.8, 3.2, 4.6]
	var hive := Vector2(860, 380)
	var player := Vector2(560, 330)
	var shielded := t < 4.9
	var hive_hp := 1.0 - _phase(t, 5.2, 7.2)
	# Nests (spitting out little enemies until they break).
	for i in nests.size():
		var n: Vector2 = nests[i]
		if t < breaks[i]:
			_stage.draw_circle(n, 58.0, Color(0.6, 0.25, 0.7))
			_stage.draw_circle(n, 26.0, Color(0.1, 0.02, 0.1))
			var spit := fmod(t * 0.9 + i * 0.3, 1.0)
			_enemy(n.lerp(player, spit * 0.35), 30.0)
			if t > breaks[i] - 0.9:
				_shot(player, n, (t - breaks[i] + 0.9) * 2.2)
		else:
			_stage.draw_circle(n, 50.0, Color(0.2, 0.1, 0.2))
		_pop(n, (t - breaks[i]) * 2.5)
	# The hive.
	if hive_hp > 0.0:
		_stage.draw_circle(hive, 110.0, Color(0.85, 0.4, 1.0))
		_stage.draw_circle(hive, 44.0, Color(0.1, 0.02, 0.1))
		if shielded:
			_stage.draw_circle(hive, 150.0, Color(0.5, 0.85, 1.0, 0.25))
			_stage.draw_arc(hive, 150.0, 0.0, TAU, 64, Color(0.6, 0.9, 1.0), 6.0, true)
		_stage.draw_rect(Rect2(hive + Vector2(-100, 140), Vector2(200 * hive_hp, 16)), Color(0.35, 1, 0.4))
		if t > 5.2:
			_shot(player, hive, fmod(t * 3.0, 1.0))
	_pop(hive, (t - 7.2) * 1.5)
	_player(player, 0)
	var label := "Hive shielded: destroy the nests" if shielded else "Shield down! Destroy the hive"
	_text(Vector2(hive.x, 70), label, Color(0.85, 0.6, 1.0), 40)


func _draw_cats(t: float) -> void:
	# The pen in the top-left corner.
	var corner := Vector2.ZERO
	var pen := 300.0
	var c := Color(1.0, 0.55, 0.75)
	_stage.draw_circle(corner, pen, Color(c, 0.15))
	_stage.draw_arc(corner, pen, 0.0, PI / 2.0, 32, Color(0.55, 0.38, 0.22), 8.0, true)
	_text(Vector2(130, 120), "PEN", c, 44)
	# Two players sweep from the right towards the pen.
	var sweep := _phase(t, 0.5, 6.5)
	var p1 := Vector2(1150, 160).lerp(Vector2(560, 120), sweep)
	var p2 := Vector2(1350, 470).lerp(Vector2(700, 470), sweep)
	_player(p1, 0)
	_player(p2, 1)
	# Cats run ahead of them into the pen; one tries to slip past and is
	# headed off.
	var starts := [Vector2(950, 260), Vector2(1050, 380), Vector2(880, 420)]
	var ends := [Vector2(150, 110), Vector2(230, 190), Vector2(110, 230)]
	var colors := [Color(0.98, 0.6, 0.22), Color(0.14, 0.13, 0.14), Color(0.6, 0.6, 0.62)]
	for i in starts.size():
		var at: Vector2 = (starts[i] as Vector2).lerp(ends[i], _phase(t, 0.8 + i * 0.4, 7.0))
		var jink := sin(t * 5.0 + i * 2.0) * 25.0 * (1.0 - _phase(t, 5.5, 7.0))
		at += Vector2(0, jink)
		if i == 1 and t > 2.6 and t < 4.4:
			# The juke: toward the gap, then back when P2 closes in.
			at += Vector2(40, 140) * sin(_phase(t, 2.6, 4.4) * PI)
			if t < 3.0:
				_text(at + Vector2(0, -50), "!", Color(1, 0.9, 0.3), 48)
		_tutorial_cat(at, colors[i], t > 7.0)
	if t > 7.0:
		_text(Vector2(750, 80), "PENNED!", Color(0.4, 1.0, 0.5), 48)


func _tutorial_cat(at: Vector2, color: Color, asleep: bool) -> void:
	var dark := color.darkened(0.55) if color.get_luminance() > 0.3 else Color(0.35, 0.35, 0.38)
	if asleep:
		_stage.draw_circle(at, 26.0, dark)
		_stage.draw_circle(at, 22.0, color)
		return
	_stage.draw_line(at + Vector2(22, -4), at + Vector2(44, -34), dark, 8.0)
	_stage.draw_set_transform(at, 0.0, Vector2(1.5, 0.95))
	_stage.draw_circle(Vector2.ZERO, 20.0, dark)
	_stage.draw_circle(Vector2.ZERO, 17.0, color)
	_stage.draw_set_transform(Vector2.ZERO)
	var head := at + Vector2(-26, -14)
	for side: float in [-1.0, 1.0]:
		var base := head + Vector2(side * 8.0, -8.0)
		_stage.draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 3), base + Vector2(6, 3),
			base + Vector2(side * 3.0, -12)]), dark)
	_stage.draw_circle(head, 14.0, dark)
	_stage.draw_circle(head, 12.0, color)
