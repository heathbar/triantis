@tool
extends Node2D
## An airstrike pad, beside a window (scripts/braid/braid_level.gd puts one
## on each side; it used to drop a crusher, hence "favour"). A player standing
## in its circle sees an X bubble; holding X (E on the keyboard) for
## FAVOUR_HOLD seconds calls a carpet bombing on the neighbouring lane across
## the window (crush_rect), hurting the enemies of whichever squad is there.
## Then it recharges (FAVOUR_RECHARGE seconds) and can be used again; X has
## to be let go and held again for another.
##
## The pad only notices our own players (group "players"); braid_game.gd
## connects `triggered`, tells the other squad's game, and shows the strike.

## `caller` (one of our players) held X long enough.
signal triggered(plate: Node2D, caller: Node2D)

const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const BraidPrompt := preload("res://scripts/braid/braid_prompt.gd")
const TargetMarker := preload("res://scripts/target_marker.gd")
const ExplosionArt := preload("res://scripts/explosion_art.gd")

const RADIUS := 12.0
const IDLE := Color(0.95, 0.75, 0.3)
const DONE := Color(0.4, 0.38, 0.35)
const BOMB_DARK := Color(0.16, 0.15, 0.18)
## The X bubble sits this far above the pad.
const PROMPT_OFFSET := Vector2(0, -24)
## Played as each column of bombs lands.
const BLAST_SOUND := preload("res://assets/meadow/enemies/bomber.ogg")
const BLAST_VOLUME := 0.3

## The lane it's in, and the lane it calls the strike on.
var lane := 0
var target_lane := 1
## Progress along the lanes where it is (BraidLevel.progress), and the world y
## of the middle of the target lane there (set by the level).
var s := 0.0
var crush_y := 0.0
## Recharging after a strike.
var used := false
## Seconds until it's ready again.
var _recharge := 0.0
## Someone held X through the last strike: they must let go first.
var _needs_release := false
var _held := 0.0
## A player is in the circle (the bubble shows), and whether the first one
## found is the keyboard player.
var _someone_in := false
var _keyboard := false
## The bubble and hold ring, drawn over players and walls (the pad itself is
## on the floor).
var _overlay: Node2D


func _ready() -> void:
	z_index = -9
	set_physics_process(not Engine.is_editor_hint())
	_overlay = Node2D.new()
	_overlay.z_as_relative = false
	_overlay.z_index = 60
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()


func _physics_process(delta: float) -> void:
	var inside := false
	var holding := false
	var holder: Node2D = null
	var keyboard := false
	for p: Node2D in get_tree().get_nodes_in_group("players"):
		if p.is_dead() or p.global_position.distance_to(global_position) > RADIUS + 10.0:
			continue
		if not inside:
			keyboard = p.device == Global.KEYBOARD
		inside = true
		if p.interact_held():
			holding = true
			if holder == null:
				holder = p
	if inside != _someone_in or keyboard != _keyboard:
		_someone_in = inside
		_keyboard = keyboard
		_redraw()
	if _someone_in:
		_redraw()  # the bubble bobs
	if not holding:
		_needs_release = false
	if used:
		_recharge = maxf(_recharge - delta, 0.0)
		_redraw()
		if _recharge > 0.0:
			return
		used = false
	if _needs_release:
		return
	var before := _held
	_held = clampf(_held + (delta if holding else -delta * 2.0), 0.0, BraidTuning.FAVOUR_HOLD)
	if _held != before:
		_redraw()
	if _held >= BraidTuning.FAVOUR_HOLD:
		used = true
		_held = 0.0
		_recharge = BraidTuning.FAVOUR_RECHARGE
		_needs_release = true
		_redraw()
		triggered.emit(self, holder)


## Where the bombs land: across the window, in the target lane.
func crush_rect() -> Rect2:
	var size := BraidTuning.FAVOUR_CRUSH_SIZE
	return Rect2(Vector2(position.x - size.x / 2.0, crush_y - size.y / 2.0), size)


func _draw() -> void:
	var c := DONE if used else IDLE
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.5))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, c, 2.0)
	# Three falling bombs, noses down-left.
	var fall := Vector2(-1, 1).normalized()
	_draw_bomb(Vector2(-3.0, -1.5), fall, 10.0, 5.0, c)
	_draw_bomb(Vector2(5.5, 1.5), fall, 6.5, 3.4, c)
	_draw_bomb(Vector2(-0.5, 7.0), fall, 4.5, 2.4, c)
	if used:
		# Recharging: a ring filling back up.
		var filled := 1.0 - _recharge / BraidTuning.FAVOUR_RECHARGE
		draw_arc(Vector2.ZERO, RADIUS + 3.0, -PI / 2.0, -PI / 2.0 + TAU * filled, 20, IDLE.darkened(0.3), 1.0)


## Someone in the circle, pad ready: the X bubble, and the hold ring filling.
func _draw_overlay() -> void:
	if used or not _someone_in:
		return
	BraidPrompt.draw_button(_overlay, PROMPT_OFFSET, _keyboard)
	BraidPrompt.draw_ring(_overlay, Vector2.ZERO, RADIUS + 3.0, _held / BraidTuning.FAVOUR_HOLD)


## A bomb `length` long and `width` wide centred on `at`, its nose pointing
## along `dir`: a rounded body with a pair of tail fins.
func _draw_bomb(at: Vector2, dir: Vector2, length: float, width: float, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var nose := at + dir * (length / 2.0 - width / 2.0)
	var tail := at - dir * (length / 2.0 - width * 0.35)
	draw_circle(nose, width / 2.0, color)
	draw_colored_polygon(PackedVector2Array([
		nose + side * width / 2.0, nose - side * width / 2.0,
		tail - side * width * 0.3, tail + side * width * 0.3]), color)
	# Fins: a little swept-back flare each side of the tail.
	var root := tail + dir * width * 0.15
	var tip := tail - dir * width * 0.55
	for k in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			root + side * k * width * 0.25, tip + side * k * width * 0.75,
			tip + side * k * width * 0.15]), color)
	# A dark band round the body.
	var band := at + dir * length * 0.05
	draw_line(band + side * width * 0.45, band - side * width * 0.45, BOMB_DARK.lerp(color, 0.35), 1.0)


## An airstrike on `rect` (world), drawn under `parent`: a warning box, then
## columns of bombs landing left to right. `on_column(rect)` (if set) is
## called with each column's part of `rect` as it lands (the squad whose lane
## it is hurts its enemies there).
static func show_crush(parent: Node, rect: Rect2, on_column := Callable()) -> void:
	var strike := Strike.new()
	strike.rect = rect
	strike.on_column = on_column
	strike.position = rect.position
	parent.add_child(strike)


class Strike extends Node2D:
	const WARN := Color(1.0, 0.3, 0.2)
	## A bomb falls this long (and this far, in pixels) before its blast.
	const DROP_TIME := 0.15
	const DROP_HEIGHT := 40.0
	const BLAST_TIME := ExplosionArt.DURATION

	var rect := Rect2()
	var on_column := Callable()
	var t := 0.0
	var _landed := 0

	func _ready() -> void:
		z_index = 40

	func _process(delta: float) -> void:
		t += delta
		var columns := BraidTuning.FAVOUR_COLUMNS
		while _landed < columns and t >= _land_time(_landed):
			if on_column.is_valid():
				var w := rect.size.x / columns
				on_column.call(Rect2(rect.position + Vector2(w * _landed, 0), Vector2(w, rect.size.y)))
			if _landed % 2 == 0:
				Global.play_sfx(BLAST_SOUND, BLAST_VOLUME)
			_landed += 1
		queue_redraw()
		if t > _land_time(columns - 1) + BLAST_TIME:
			queue_free()

	func _land_time(column: int) -> float:
		return BraidTuning.FAVOUR_WARNING + column * BraidTuning.FAVOUR_COLUMN_GAP

	## Where bomb `row` of `column` lands (local): rows staggered by half a
	## row on odd columns.
	func _spot(column: int, row: int) -> Vector2:
		var w := rect.size.x / BraidTuning.FAVOUR_COLUMNS
		var h := rect.size.y / BraidTuning.FAVOUR_ROWS
		var stagger := 0.25 if column % 2 == 0 else -0.25
		return Vector2(w * (column + 0.5), h * clampf(row + 0.5 + stagger, 0.3, BraidTuning.FAVOUR_ROWS - 0.3))

	func _draw() -> void:
		var local := Rect2(Vector2.ZERO, rect.size)
		var columns := BraidTuning.FAVOUR_COLUMNS
		var rows := BraidTuning.FAVOUR_ROWS
		# The target box, blinking faster as the bombs get close.
		if t < _land_time(columns - 1):
			var left := maxf(BraidTuning.FAVOUR_WARNING - t, 0.0)
			var lit := fmod(t, 0.08 + left * 0.2) < (0.04 + left * 0.1)
			var c := WARN if lit else WARN.darkened(0.45)
			draw_rect(local, Color(c, 0.12))
			draw_rect(local, c, false, 1.0)
			for column in range(_landed, columns):
				for row in rows:
					TargetMarker.draw(self, _spot(column, row), TargetMarker.AIM_SIZE / 2.0,
						Color.WHITE if lit else Color(0.6, 0.6, 0.6))
		var radius := minf(rect.size.x / columns, rect.size.y / rows) * 0.85
		for column in columns:
			var since := t - _land_time(column)
			for row in rows:
				var at := _spot(column, row)
				if since < -DROP_TIME:
					continue
				if since < 0.0:
					# Falling: a bomb dropping in over its growing shadow.
					var f := 1.0 + since / DROP_TIME
					draw_circle(at, 2.0 + 3.0 * f, Color(0, 0, 0, 0.3))
					var bomb := at - Vector2(0, DROP_HEIGHT * (1.0 - f))
					draw_rect(Rect2(bomb - Vector2(2, 4), Vector2(4, 8)), Color(0.18, 0.18, 0.2))
					continue
				if since > BLAST_TIME:
					continue
				ExplosionArt.draw(self, at, since, radius)
