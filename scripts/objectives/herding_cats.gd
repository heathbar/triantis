extends Objective
## Herding Cats: a clowder of cats appears in the corner of our map nearest
## the middle (bottom right in a local game). Herd them into the pen in the
## opposite, outer corner (top left in a local game). A cat that reaches the
## pen settles down and stays there.
##
## Cats run from players: away from where you are, and the way you're coming
## at them (so walk at one from behind to push it where you're heading), with
## some jitter. Now and then one crouches for a moment (watch for the "!")
## and then darts off sideways instead (a juke). They sit, wander, get the
## zoomies, and gunfire close by spooks them. Enemies spook them a little too
## but never hurt them; shots pass straight through them.
##
## Any number of players plays it the same way a lone player does: nobody is
## tied to anyone, every player scares cats from SCARE_RADIUS, and the cats
## appear partway to the pen. (There used to be a rope tying a squad
## together; it made multiplayer far harder than solo, so it's gone.)
##
## Time limit: from how far the cats have to go (HERD_SPEED, TIME_BASE). Pen
## enough cats before it runs out, or the wave is failed.
##
## Squads game: every squad herds its own cats on its own map (no one else
## sees them), but other squads' players who wander onto our map spook ours.
## Pens are pooled: the wave is won once the squads still up have penned
## enough between them (each squad adds NEED). The host keeps the tally.

## Cats per squad (or local game), and how many must be penned (one spare, so
## the last one isn't a chase).
const CATS := 4
const NEED := 3

const CAT_RADIUS := 7.0
## Players scare cats within this distance.
const SCARE_RADIUS := 112.0
## Cats are shoved out of this distance from a player regardless.
const PERSONAL_SPACE := 28.0
const ENEMY_SCARE_RADIUS := 46.0
const ENEMY_SCARE_WEIGHT := 0.5
## A shot spooks cats this close to the shooter, each with STARTLE_CHANCE,
## and then not again for STARTLE_COOLDOWN seconds.
const STARTLE_RADIUS := 104.0
const STARTLE_CHANCE := 0.5
const STARTLE_COOLDOWN := 3.0

const WANDER_SPEED := 24.0
const FLEE_SPEED := 104.0
const JUKE_SPEED := 128.0
const ZOOM_SPEED := 132.0
const PEN_WALK_SPEED := 22.0
const ACCEL := 520.0
## Flee direction: this much of the player's own heading, the rest straight
## away from them, then turned up to JITTER radians either way.
const APPROACH_WEIGHT := 0.45
const JITTER := 0.5
## Chance a cat that starts fleeing (or changes course while fleeing) jukes.
const JUKE_CHANCE := 0.2
const RETARGET_JUKE_CHANCE := 0.08
## The crouch before a juke: the tell.
const TELL_TIME := 0.35
const ZOOMIES_CHANCE := 0.06

## The pen: a quarter circle in the map's outer corner, this share of the
## map's shorter side in radius.
const PEN_FRACTION := 0.15
## Where the cats appear and the players start, as fractions of the way
## across the map from its outer corner.
const CATS_AT := 0.5
const CATS_SPREAD := 52.0
const PLAYERS_AT := 0.62
## Time limit: the distance from TIME_FROM (a fraction like CATS_AT, further
## out than the cats really start, so there's slack) to the pen /
## HERD_SPEED + TIME_BASE, rounded up to 5 s.
const TIME_FROM := 0.78
const HERD_SPEED := 15.0
const TIME_BASE := 45.0

const CAT_COLORS := [Color(0.98, 0.6, 0.22), Color(0.14, 0.13, 0.14), Color(0.6, 0.6, 0.62),
	Color(0.96, 0.95, 0.92), Color(0.93, 0.82, 0.62), Color(0.45, 0.33, 0.25)]

enum CatState { IDLE, WANDER, FLEE, TELL, JUKE, ZOOM, PENNED }


class Cat:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dir := Vector2.RIGHT
	var state := CatState.IDLE
	## Seconds left in this state (or to the next change of course).
	var timer := 0.0
	## Seconds without a threat while fleeing; it calms down at calm_after.
	var calm := 0.0
	var calm_after := 0.5
	var startle_cd := 0.0
	var color := Color.WHITE
	var face := 1.0
	var phase := 0.0
	## Where it curls up in the pen.
	var spot := Vector2.ZERO


var cats: Array[Cat] = []
## Ours: cats penned, and how many we need.
var penned := 0
var need := NEED
## Pooled across the squads still up (host's tally; ours in a local game).
var total_penned := 0
var total_needed := NEED
## Seconds from the start of the wave.
var time_limit := 120.0
## The pen's corner (ours) and radius.
var pen_corner := Vector2.ZERO
var pen_radius := 120.0

var _into_map := Vector2.ONE
var _squad_info := {}
var _age := 0.0
var _flash_text := ""
var _flash_left := 0.0
var _remote_last := {}
var _shot_hooks := {}
## Draws the cats over the players and enemies.
var _top: Node2D


func begin() -> void:
	_top = Node2D.new()
	_top.z_index = 5
	_top.z_as_relative = false
	_top.draw.connect(_draw_top)
	add_child(_top)

	need = NEED
	total_needed = need
	pen_corner = to_local_pos(outer_point(my_squad, Vector2.ZERO))
	var bounds := map_rect()
	pen_radius = minf(bounds.size.x, bounds.size.y) * PEN_FRACTION
	_into_map = (to_local_pos(outer_point(my_squad, Vector2(0.5, 0.5))) - pen_corner).sign()

	var herd_from := to_local_pos(outer_point(my_squad, Vector2.ONE * TIME_FROM))
	time_limit = ceilf((maxf(herd_from.distance_to(pen_corner) - pen_radius, 0.0) / HERD_SPEED
		+ TIME_BASE) / 5.0) * 5.0

	var centre := to_local_pos(outer_point(my_squad, Vector2.ONE * CATS_AT))
	var area := bounds.grow(-EDGE_INSET)
	for i in CATS:
		var cat := Cat.new()
		cat.pos = (centre + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * CATS_SPREAD) \
			.clamp(area.position, area.end)
		cat.color = CAT_COLORS[i % CAT_COLORS.size()]
		cat.phase = randf() * TAU
		cat.face = 1.0 if randf() < 0.5 else -1.0
		_set_state(cat, CatState.IDLE)
		cats.append(cat)

	game.place_players(to_local_pos(outer_point(my_squad, Vector2.ONE * PLAYERS_AT)))

	for player in game.all_players:
		var hook := _on_shot.bind(player)
		player.shot_fired.connect(hook)
		_shot_hooks[player] = hook


func _exit_tree() -> void:
	for player: Node in _shot_hooks:
		if is_instance_valid(player) and player.shot_fired.is_connected(_shot_hooks[player]):
			player.shot_fired.disconnect(_shot_hooks[player])
	_shot_hooks.clear()


# --- Cats ------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_age += delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	_top.queue_redraw()
	if failed_squads.has(my_squad):
		return
	var scarers := _scarers(delta)
	var area := map_rect().grow(-CAT_RADIUS - 2.0)
	for cat in cats:
		_update_cat(cat, delta, scarers)
	_separate()
	for cat in cats:
		if cat.state == CatState.PENNED:
			continue
		_keep_on_map(cat, area)
		if cat.pos.distance_to(pen_corner) < pen_radius - CAT_RADIUS:
			_pen(cat)


## Everything that scares cats: {pos, vel, r (radius), w (weight), push
## (shoves them out of PERSONAL_SPACE), approach (its heading counts)}.
func _scarers(delta: float) -> Array:
	var list := []
	for player in living_players():
		list.append({"pos": player.global_position, "vel": player.velocity, "r": SCARE_RADIUS, "w": 1.0,
			"push": true, "approach": true})
	# Other squads' players on our map.
	var seen := {}
	for remote: Node2D in get_tree().get_nodes_in_group("remote_players"):
		var id := remote.get_instance_id()
		var at := remote.global_position
		var vel: Vector2 = (at - _remote_last.get(id, at)) / maxf(delta, 0.001)
		_remote_last[id] = at
		seen[id] = true
		list.append({"pos": at, "vel": vel, "r": SCARE_RADIUS, "w": 1.0, "push": true,
			"approach": true})
	for id in _remote_last.keys():
		if not seen.has(id):
			_remote_last.erase(id)
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("is_mirror") or enemy.is_in_group("objective_structures"):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		list.append({"pos": enemy.global_position, "vel": Vector2.ZERO, "r": ENEMY_SCARE_RADIUS,
			"w": ENEMY_SCARE_WEIGHT, "push": false, "approach": false})
	return list


func _update_cat(cat: Cat, delta: float, scarers: Array) -> void:
	cat.timer -= delta
	cat.startle_cd -= delta
	if cat.state == CatState.PENNED:
		cat.vel = cat.pos.direction_to(cat.spot) * PEN_WALK_SPEED \
			if cat.pos.distance_to(cat.spot) > 1.6 else Vector2.ZERO
		cat.pos += cat.vel * delta
		if cat.vel.x != 0.0:
			cat.face = signf(cat.vel.x)
		return

	# How scared it is, which way is away, and which way they're coming.
	var away := Vector2.ZERO
	var approach := Vector2.ZERO
	var threat := 0.0
	for s: Dictionary in scarers:
		var off: Vector2 = cat.pos - s["pos"]
		var d := off.length()
		if d >= s["r"] or d < 0.001:
			continue
		var w: float = (1.0 - d / s["r"]) * s["w"]
		away += off / d * w
		threat = maxf(threat, w)
		var v: Vector2 = s["vel"]
		if s["approach"] and v.length() > 12.0:
			approach += v.normalized() * w * clampf(v.length() / 80.0, 0.0, 1.0)
		if s["push"] and d < PERSONAL_SPACE:
			cat.pos += off / d * (PERSONAL_SPACE - d) * minf(10.0 * delta, 1.0)

	match cat.state:
		CatState.IDLE, CatState.WANDER:
			if threat > 0.0:
				_start_flee(cat, away, approach, JUKE_CHANCE)
			elif cat.timer <= 0.0:
				_pick_calm_state(cat)
		CatState.FLEE:
			if threat > 0.0:
				cat.calm = 0.0
				if cat.timer <= 0.0:
					_start_flee(cat, away, approach, RETARGET_JUKE_CHANCE)
			else:
				cat.calm += delta
				if cat.calm >= cat.calm_after:
					_set_state(cat, CatState.IDLE)
		CatState.TELL:
			if cat.timer <= 0.0:
				cat.dir = cat.dir.rotated(randf_range(1.2, 1.9) * (1.0 if randf() < 0.5 else -1.0))
				_set_state(cat, CatState.JUKE)
		CatState.JUKE:
			if cat.timer <= 0.0:
				if threat > 0.0:
					_start_flee(cat, away, approach, 0.0)
				else:
					_set_state(cat, CatState.IDLE)
		CatState.ZOOM:
			if cat.timer <= 0.0:
				_set_state(cat, CatState.IDLE)
			elif fmod(cat.timer, 0.25) < delta:
				cat.dir = cat.dir.rotated(randf_range(-1.2, 1.2))

	var speed := 0.0
	var heading := cat.dir
	match cat.state:
		CatState.WANDER:
			speed = WANDER_SPEED
		CatState.FLEE:
			speed = FLEE_SPEED
		CatState.JUKE:
			speed = JUKE_SPEED
		CatState.ZOOM:
			speed = ZOOM_SPEED
	cat.vel = cat.vel.move_toward(heading * speed, ACCEL * delta)
	cat.pos += cat.vel * delta
	if absf(cat.vel.x) > 4.0:
		cat.face = signf(cat.vel.x)


func _start_flee(cat: Cat, away: Vector2, approach: Vector2, juke_chance: float) -> void:
	var dir := away.normalized()
	if approach.length() > 0.01:
		dir = (dir * (1.0 - APPROACH_WEIGHT) + approach.normalized() * APPROACH_WEIGHT).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	cat.dir = dir.rotated(randf_range(-JITTER, JITTER))
	cat.calm = 0.0
	cat.calm_after = randf_range(0.3, 0.8)
	if randf() < juke_chance:
		_set_state(cat, CatState.TELL)
	else:
		_set_state(cat, CatState.FLEE)


## Sit, wander, or get the zoomies.
func _pick_calm_state(cat: Cat) -> void:
	var roll := randf()
	if roll < ZOOMIES_CHANCE:
		cat.dir = Vector2.RIGHT.rotated(randf() * TAU)
		_set_state(cat, CatState.ZOOM)
		return
	if roll < 0.5:
		cat.dir = Vector2.RIGHT.rotated(randf() * TAU)
		_set_state(cat, CatState.WANDER)
	else:
		_set_state(cat, CatState.IDLE)


func _set_state(cat: Cat, state: int) -> void:
	cat.state = state
	match state:
		CatState.IDLE:
			cat.timer = randf_range(0.6, 2.0)
		CatState.WANDER:
			cat.timer = randf_range(0.5, 1.4)
		CatState.FLEE:
			cat.timer = randf_range(0.25, 0.45)  # Till it changes course.
		CatState.TELL:
			cat.timer = TELL_TIME
		CatState.JUKE:
			cat.timer = randf_range(0.5, 0.8)
		CatState.ZOOM:
			cat.timer = randf_range(0.8, 1.3)


func _keep_on_map(cat: Cat, area: Rect2) -> void:
	var clamped := cat.pos.clamp(area.position, area.end)
	var hit_x := clamped.x != cat.pos.x
	var hit_y := clamped.y != cat.pos.y
	cat.pos = clamped
	if not (hit_x or hit_y):
		return
	if hit_x:
		cat.vel.x = 0.0
	if hit_y:
		cat.vel.y = 0.0
	if hit_x and hit_y:
		# Cornered (not in the pen): out along the wall it's least pressed to.
		cat.dir = cat.pos.direction_to(area.get_center()).rotated(randf_range(-0.6, 0.6))
		return
	# Slide along the wall rather than pressing into it.
	if hit_x:
		cat.dir.x = 0.0
		if absf(cat.dir.y) < 0.2:
			cat.dir.y = 1.0 if randf() < 0.5 else -1.0
	else:
		cat.dir.y = 0.0
		if absf(cat.dir.x) < 0.2:
			cat.dir.x = 1.0 if randf() < 0.5 else -1.0
	cat.dir = cat.dir.normalized()


func _separate() -> void:
	for i in cats.size():
		for j in range(i + 1, cats.size()):
			var a := cats[i]
			var b := cats[j]
			if a.state == CatState.PENNED or b.state == CatState.PENNED:
				continue
			var off := b.pos - a.pos
			var d := off.length()
			if d < CAT_RADIUS * 2.0 and d > 0.001:
				var push := off / d * (CAT_RADIUS * 2.0 - d) * 0.5
				a.pos -= push
				b.pos += push


func _pen(cat: Cat) -> void:
	cat.state = CatState.PENNED
	cat.vel = Vector2.ZERO
	var slot := penned
	penned += 1
	# Curl-up spots fanned across the pen, nearer the corner first.
	var row := floori(slot / 4.0)
	var col := slot % 4
	var angle := (col + 0.5 + 0.5 * (row % 2)) / 4.5 * (PI / 2.0)
	var r := pen_radius * clampf(0.35 + 0.2 * row, 0.3, 0.8)
	cat.spot = pen_corner + Vector2(_into_map.x * cos(angle), _into_map.y * sin(angle)) * r
	_flash("Cat penned! %d/%d" % [penned, need])


func _on_shot(_shot: Node, player: Node2D) -> void:
	if not game.is_wave_running():
		return
	for cat in cats:
		if cat.state == CatState.PENNED or cat.startle_cd > 0.0:
			continue
		if cat.pos.distance_to(player.global_position) > STARTLE_RADIUS:
			continue
		cat.startle_cd = STARTLE_COOLDOWN
		if randf() < STARTLE_CHANCE:
			cat.dir = player.global_position.direction_to(cat.pos).rotated(randf_range(-1.5, 1.5))
			_set_state(cat, CatState.ZOOM)


func _flash(text: String) -> void:
	_flash_text = text
	_flash_left = 2.0


# --- Tally ------------------------------------------------------------------------------

func periodic_report() -> Dictionary:
	return {"p": penned, "n": need, "up": not living_players().is_empty()}


func host_receive(squad: int, data: Dictionary) -> void:
	if data.has("p"):
		_squad_info[squad] = data
		_retally()


func _retally() -> void:
	var p := 0
	var n := 0
	for squad in squads_still_in():
		var data: Dictionary = _squad_info.get(squad, {})
		if data.is_empty():
			n += NEED  # Not heard from yet.
		elif data.get("up", true):
			p += int(data["p"])
			n += int(data["n"])
	total_penned = p
	total_needed = n


func outcome() -> int:
	if total_needed > 0 and total_penned >= total_needed:
		return Outcome.SUCCESS
	if elapsed >= time_limit or not is_authority:
		fail_reason = "Time ran out before the cats were penned"
		return Outcome.FAILED
	return Outcome.RUNNING


func host_state() -> Dictionary:
	return {"p": total_penned, "n": total_needed}


func apply_state(state: Dictionary) -> void:
	total_penned = int(state.get("p", total_penned))
	total_needed = int(state.get("n", total_needed))


func display_time(wave_elapsed: float) -> float:
	return maxf(time_limit - wave_elapsed, 0.0)


func status_text() -> String:
	var line := "Cats penned %d/%d" % [total_penned, total_needed]
	if squads_game:
		line += "   Yours %d/%d" % [penned, need]
	if _flash_left > 0.0:
		line = _flash_text + "   " + line
	return line


func markers() -> Array:
	var list := [[pen_corner + Vector2(_into_map) * pen_radius * 0.4, info["color"]]]
	for cat in cats:
		if cat.state != CatState.PENNED:
			list.append([cat.pos, cat.color])
	return list


# --- Drawing ------------------------------------------------------------------------------

## The pen, under everything.
func _draw() -> void:
	var c: Color = info["color"]
	var a0 := Vector2(_into_map.x, 0).angle()
	var sweep := wrapf(Vector2(0, _into_map.y).angle() - a0, -PI, PI)
	var pts := PackedVector2Array([pen_corner])
	for i in 25:
		pts.append(pen_corner + Vector2.RIGHT.rotated(a0 + sweep * i / 24.0) * pen_radius)
	draw_colored_polygon(pts, Color(c, 0.14))
	# A picket fence round the curve, its mouth open in the middle.
	for i in 19:
		var f := i / 18.0
		if f > 0.3 and f < 0.7:
			continue
		var at := pen_corner + Vector2.RIGHT.rotated(a0 + sweep * f) * pen_radius
		draw_line(at + Vector2(0, 4), at + Vector2(0, -9), Color(0.45, 0.3, 0.18), 2.0)
		draw_circle(at + Vector2(0, -9), 1.0, Color(0.45, 0.3, 0.18))
	for f: float in [0.0, 0.7]:
		var from := a0 + sweep * f
		var to := a0 + sweep * (f + 0.3)
		draw_arc(pen_corner, pen_radius, minf(from, to), maxf(from, to), 16,
			Color(0.55, 0.38, 0.22), 2.0)
	# Cushions.
	for i in 8:
		var row := floori(i / 4.0)
		var angle := (i % 4 + 0.5 + 0.5 * (row % 2)) / 4.5 * (PI / 2.0)
		var r := pen_radius * (0.35 + 0.2 * row)
		var at := pen_corner + Vector2(_into_map.x * cos(angle), _into_map.y * sin(angle)) * r
		draw_set_transform(at, 0.0, Vector2(1.3, 0.8))
		draw_circle(Vector2.ZERO, 9.0, Color(c, 0.55))
		draw_set_transform(Vector2.ZERO)
	var font := ThemeDB.fallback_font
	var label_at := pen_corner + Vector2(_into_map) * pen_radius * 0.45 + Vector2(-16, 0)
	draw_string_outline(font, label_at, "PEN", HORIZONTAL_ALIGNMENT_CENTER, 32, 13, 2, Color.BLACK)
	draw_string(font, label_at, "PEN", HORIZONTAL_ALIGNMENT_CENTER, 32, 13, c)


## The cats, over the players.
func _draw_top() -> void:
	var canvas := _top
	for cat in cats:
		_draw_cat(canvas, cat)


func _draw_cat(canvas: Node2D, cat: Cat) -> void:
	var at := cat.pos
	var dark := cat.color.darkened(0.55) if cat.color.get_luminance() > 0.3 else Color(0.35, 0.35, 0.38)
	canvas.draw_set_transform(at + Vector2(0, 5), 0.0, Vector2(1.6, 0.5))
	canvas.draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.3))
	canvas.draw_set_transform(Vector2.ZERO)
	var f := cat.face
	if cat.state == CatState.PENNED and cat.pos.distance_to(cat.spot) <= 1.6:
		# Curled up asleep.
		canvas.draw_circle(at, 7.0, dark)
		canvas.draw_circle(at, 6.0, cat.color)
		canvas.draw_arc(at, 4.0, 0.3, 2.6, 12, dark, 1.0)
		_draw_head(canvas, at + Vector2(3 * f, -2), f, cat.color, dark, true)
		var z := fmod(_age + cat.phase, 2.0)
		var font := ThemeDB.fallback_font
		canvas.draw_string(font, at + Vector2(4, -10 - z * 4), "z", HORIZONTAL_ALIGNMENT_LEFT, -1,
			8, Color(1, 1, 1, 1.0 - z / 2.0))
		return
	var moving := cat.vel.length() > 8.0
	var squash := Vector2.ONE
	if cat.state == CatState.TELL:
		squash = Vector2(1.2, 0.72)
	elif moving:
		squash = Vector2(1.12, 0.92)
	var bounce := absf(sin(_age * 18.0 + cat.phase)) * 1.2 if moving else 0.0
	var body := at + Vector2(0, -bounce)
	# Tail.
	var wag := sin(_age * (12.0 if moving else 3.0) + cat.phase)
	var tail := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		tail.append(body + Vector2(-f * (5.6 + 6 * t), -2 - 8 * t + wag * 2.8 * t * t))
	canvas.draw_polyline(tail, dark, 3.0)
	canvas.draw_polyline(tail, cat.color, 1.0)
	# Body.
	canvas.draw_set_transform(body, 0.0, Vector2(1.5, 0.95) * squash)
	canvas.draw_circle(Vector2.ZERO, 5.0, dark)
	canvas.draw_circle(Vector2.ZERO, 4.0, cat.color)
	canvas.draw_set_transform(Vector2.ZERO)
	var head_at := body + Vector2(7 * f * squash.x, -4 * squash.y)
	_draw_head(canvas, head_at, f, cat.color, dark, false)
	if cat.state == CatState.TELL:
		var font := ThemeDB.fallback_font
		canvas.draw_string_outline(font, head_at + Vector2(-2, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1,
			11, 2, Color.BLACK)
		canvas.draw_string(font, head_at + Vector2(-2, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1,
			11, Color(1, 0.9, 0.3))


func _draw_head(canvas: Node2D, at: Vector2, f: float, color: Color, dark: Color, asleep: bool) -> void:
	for side: float in [-1.0, 1.0]:
		var base := at + Vector2(side * 2.0, -2.0)
		var ear := PackedVector2Array([base + Vector2(-2, 1), base + Vector2(2, 1),
			base + Vector2(side * 1.0, -3)])
		canvas.draw_colored_polygon(ear, dark)
	canvas.draw_circle(at, 4.0, dark)
	canvas.draw_circle(at, 3.0, color)
	var eye := Color(0.1, 0.1, 0.1) if color.get_luminance() > 0.3 else Color(0.9, 0.85, 0.3)
	if asleep:
		canvas.draw_line(at + Vector2(-2, -1), at + Vector2(-1, -1), eye, 1.0)
		canvas.draw_line(at + Vector2(1, -1), at + Vector2(2, -1), eye, 1.0)
	else:
		canvas.draw_rect(Rect2(at + Vector2(roundf(-2 + f * 0.6), -1), Vector2.ONE), eye)
		canvas.draw_rect(Rect2(at + Vector2(roundf(1 + f * 0.6), -1), Vector2.ONE), eye)
	canvas.draw_rect(Rect2(at + Vector2(roundf(f), 1), Vector2.ONE), Color(1, 0.55, 0.6))
