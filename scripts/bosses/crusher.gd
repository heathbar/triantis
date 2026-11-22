extends Boss
## The Crusher (boss of wave 5): a monster truck that tears round the map
## and runs players over.
##
## Charges: it picks a target, revs for REV_TIME (turning to follow them and
## showing its lane on the ground), locks its aim LOCK_TIME before it goes,
## then floors it down the lane: OVERSHOOT past where the target was, then it
## brakes. While charging it steers after its target (CHARGE_TURN) until
## it's within COMMIT_DIST of them, then it's committed and drives straight:
## stepping aside early isn't enough, dodge once it's close. Anyone it drives
## over (while it's going faster than HURT_SPEED)
## loses RUN_OVER_DAMAGE and is thrown out to the side. Regular enemies in
## its way are crushed too (no points, but they drop their resources).
##
## Walls: if it reaches the edge of the arena going faster than
## CRASH_SPEED, it slams into it and stalls for STALL_TIME, taking STALL_MULT
## damage. So the way to fight it is to stand with a wall behind you and
## sidestep at the last moment.
##
## Donuts: every DONUT_EVERY-th move it spins on the spot instead, hurting
## anyone close (DONUT_RADIUS) and flinging ROCKS rocks that land on marked
## spots around it (some aimed at nearby players).
##
## Pace: each charge is driven to suit the player it's after. Its top speed,
## acceleration and steering are scaled by that player's move speed over
## PACE_SPEED (clamped to PACE_MIN..PACE_MAX), so a slow class gets the same
## time to sidestep as a fast one.
##
## Enraged (ENRAGE_AT): shorter revs, a faster top speed, a second charge
## straight after each one, and more rocks.
##
## Freeze Ray: slows its top speed and acceleration (at boss strength,
## Boss.STATUS_STRENGTH). Knockback and pulls don't move it.
##
## Squads game: the arena is every present squad's map put together, and the
## host drives. Each charge goes after a player in the squad it went after
## least recently (a squad with nobody up is skipped), so it takes turns
## visiting each squad's map: a squad can only hit it while it's on their
## map. Squads report where their players are; the host sends where the
## truck is, which way it faces, its speed and what it's doing, and every
## copy carries it on between updates. Each copy runs over only its own
## players and crushes only its own enemies; the rocks are hazards.

const DEFAULT_HEALTH := 2100
const ENRAGE_AT := 90.0

## The truck, tyres included: its length (along its facing) and width.
const SIZE := Vector2(48, 38)
const HALF := SIZE / 2.0
## Anything whose centre is within this of the truck's outline is under it
## (it shoves things a little ahead of its bumper as it goes).
const FOOT_MARGIN := 6.0
## Its centre stays this far inside the map edges.
const ARENA_INSET := 30.0

const FIRST_MOVE := 2.5
const REV_TIME := 0.8
const ENRAGED_REV := 0.55
## The second charge of an enraged pair revs for this long.
const DOUBLE_REV := 0.45
const LOCK_TIME := 0.3
## Turning speed while revving (radians a second).
const REV_TURN := 9.0
const TOP_SPEED := 270.0
const ENRAGED_TOP_SPEED := 320.0
const ACCEL := 1000.0
const BRAKE := 650.0
const OVERSHOOT := 110.0
## Steering while charging (radians a second), towards its target while
## they're still ahead of it.
const CHARGE_TURN := 0.9
const ENRAGED_CHARGE_TURN := 1.3
## Once its target is this close ahead, it stops steering: the sidestep
## window. (It used to steer right up to its bumper, which no class could
## outrun: 2026-11-16.)
const COMMIT_DIST := 120.0
const PAUSE := 0.45
## Pace (see above): the player speed the numbers above are tuned for (the
## base player speed), and the limits on how far a charge is scaled.
const PACE_SPEED := 100.0
const PACE_MIN := 0.65
const PACE_MAX := 1.4
const ENRAGED_PAUSE := 0.25

const HURT_SPEED := 70.0
const RUN_OVER_DAMAGE := 3
const ENRAGED_RUN_OVER_DAMAGE := 4
## How far past its side a run-over player lands.
const FLING := 10.0
const CRUSH_DAMAGE := 1000000

const CRASH_SPEED := 150.0
const STALL_TIME := 3.0
const STALL_MULT := 2.0
const RECOVER := 0.5

const DONUT_EVERY := 4
const DONUT_TIME := 2.4
const DONUT_SPIN := 9.0
const DONUT_RADIUS := 34.0
const DONUT_DAMAGE := 2
const ROCKS := 6
const ENRAGED_ROCKS := 10
## Of the rocks, how many go at players within ROCK_AIM_RANGE.
const AIMED_ROCKS := 3
const ROCK_AIM_RANGE := 200.0
const ROCK_MIN := 50.0
const ROCK_MAX := 150.0
const ROCK_FLIGHT := 1.2
const ROCK_RADIUS := 16.0
const ROCK_DAMAGE := 2
const ROCK_LINGER := 0.35

## Tyre tracks: a mark every TRACK_STEP pixels driven, fading over TRACK_FADE.
const TRACK_STEP := 5.0
const TRACK_FADE := 5.0
const MAX_TRACKS := 400

const PAINT := Color(0.88, 0.25, 0.16)
const PAINT_DARK := Color(0.55, 0.13, 0.1)
const TYRE := Color(0.1, 0.1, 0.11)
const TREAD := Color(0.26, 0.26, 0.28)
const CHROME := Color(0.78, 0.8, 0.84)
const GLASS := Color(0.45, 0.7, 0.85)
const LAMP := Color(1.0, 0.95, 0.6)

enum Mode { IDLE, REV, CHARGE, BRAKE, STALL, DONUT }

var body: BossBody
var hp := 1
var max_hp := 1
var mode := Mode.IDLE
## When the current mode ends (wave seconds; idle, rev, stall and donut).
var mode_end := FIRST_MOVE
## Facing (radians) and speed (pixels a second) of the truck (our copy).
var heading := 0.0
var speed := 0.0
## The lane it's revving for / charging down: its length from where it is.
var lane := 0.0
## Speed multiplier from slows (host's), and how long it has left.
var slow_mult := 1.0
var _slow_left := 0.0

## Host: player key -> [shared position, when heard, move speed].
var _positions := {}
## Host: the current charge's pace (see PACE_SPEED).
var pace := 1.0
## Host: squad -> when it was last charged at; player key -> the same.
var _squad_last := {}
var _player_last := {}
## Host: the player it's after (key), or -1.
var target := -1
## Host: moves made (for the donuts), how far is left of this charge, and
## whether this is the second of an enraged pair.
var _moves := 0
var _charge_left := 0.0
var _second := false

## Not the host: the truck as the host last told us, and when.
var _host_pos := Vector2.ZERO
var _host_heading := 0.0
var _host_at := -1.0

## Tyre marks (our coordinates): [position, heading, when].
var _tracks: Array = []
var _since_track := 0.0
## Our strongest slow since the last report: [mult, seconds].
var _pending_slow := []


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	max_hp = scaled_health(base_health(DEFAULT_HEALTH))
	hp = max_hp
	body = add_body(0, shared_centre(), HALF.y, _paint, SIZE)
	body.contact_damage = 1
	var players := living_players()
	if not players.is_empty():
		heading = body.global_position.angle_to_point(players[0].global_position)
	body.rotation = heading


# --- Where it can drive ---------------------------------------------------------------

## Every present squad's map put together (just ours in a local game), less
## ARENA_INSET, in our coordinates.
func arena() -> Rect2:
	var bounds := map_rect()
	if squads_game:
		var squads := present_squads()
		if not squads.is_empty():
			var all := squad_map_shared(squads[0])
			for squad in squads:
				all = all.merge(squad_map_shared(squad))
			bounds = Rect2(to_local_pos(all.position), all.size)
	return bounds.grow(-ARENA_INSET)


## How far `from` can go along `dir` before leaving `rect`.
static func edge_distance(from: Vector2, dir: Vector2, rect: Rect2) -> float:
	var t := INF
	if dir.x > 0.001:
		t = minf(t, (rect.end.x - from.x) / dir.x)
	elif dir.x < -0.001:
		t = minf(t, (rect.position.x - from.x) / dir.x)
	if dir.y > 0.001:
		t = minf(t, (rect.end.y - from.y) / dir.y)
	elif dir.y < -0.001:
		t = minf(t, (rect.position.y - from.y) / dir.y)
	return maxf(t, 0.0)


func facing() -> Vector2:
	return Vector2.from_angle(heading)


func is_stalled() -> bool:
	return mode == Mode.STALL and not is_defeated()


func is_driving() -> bool:
	return (mode == Mode.CHARGE or mode == Mode.BRAKE) and not is_defeated()


func _top_speed() -> float:
	return (ENRAGED_TOP_SPEED if is_enraged() else TOP_SPEED) * slow_mult * pace


# --- Every frame ----------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	_slow_left = maxf(_slow_left - delta, 0.0)
	if _slow_left <= 0.0:
		slow_mult = 1.0
	var before := body.global_position
	if is_defeated():
		speed = 0.0
	elif is_authority:
		_host_think(delta)
	else:
		_follow_host(delta)
	body.rotation = heading
	# Brushing it while it's going fast counts as being run over (or the
	# smaller touch would land first and its hit cooldown would eat the run-over).
	var fast := is_driving() and speed >= HURT_SPEED
	body.contact_damage = _run_over_damage() if fast else 1
	_update_presence()
	_lay_tracks(before, delta)
	if not is_defeated():
		_run_over()
	queue_redraw()


## Host: the truck's mind and its driving.
func _host_think(delta: float) -> void:
	for player in living_players():
		_positions[key_of(player)] = [to_shared_pos(player.global_position), elapsed,
			player.move_speed]
	for key in _positions.keys():
		if elapsed - float(_positions[key][1]) > POSITION_STALE:
			_positions.erase(key)

	match mode:
		Mode.IDLE:
			if elapsed >= mode_end:
				_next_move()
		Mode.REV:
			if elapsed < mode_end - LOCK_TIME and target >= 0 and _positions.has(target):
				var at := to_local_pos(_positions[target][0])
				if at.distance_to(body.global_position) > 4.0:
					heading = rotate_toward(heading, body.global_position.angle_to_point(at),
						REV_TURN * delta)
				lane = minf(body.global_position.distance_to(at) + OVERSHOOT,
					edge_distance(body.global_position, facing(), arena()))
			if elapsed >= mode_end:
				mode = Mode.CHARGE
				_charge_left = lane
		Mode.CHARGE:
			speed = minf(speed + ACCEL * slow_mult * pace * delta, _top_speed())
			_steer(delta)
			_drive(delta)
		Mode.BRAKE:
			speed = maxf(speed - BRAKE * delta, 0.0)
			_drive(delta)
			if speed <= 0.0 and mode == Mode.BRAKE:
				_stopped()
		Mode.STALL:
			if elapsed >= mode_end:
				_idle(RECOVER)
		Mode.DONUT:
			heading = wrapf(heading + DONUT_SPIN * delta, -PI, PI)
			if elapsed >= mode_end:
				_idle(ENRAGED_PAUSE if is_enraged() else PAUSE)


## Host: turns a charge towards its target, if they're still ahead.
func _steer(delta: float) -> void:
	if target < 0 or not _positions.has(target):
		return
	var to := to_local_pos(_positions[target][0]) - body.global_position
	if to.dot(facing()) <= COMMIT_DIST:
		return
	var turn := (ENRAGED_CHARGE_TURN if is_enraged() else CHARGE_TURN) * slow_mult * pace
	heading = rotate_toward(heading, to.angle(), turn * delta)


## Host: moves it along its facing at its speed; the arena edge either stalls
## it (fast) or just stops it.
func _drive(delta: float) -> void:
	var step := speed * delta
	var room := edge_distance(body.global_position, facing(), arena())
	if step >= room:
		body.global_position += facing() * room
		# Fast into the edge stalls it, even if it had started braking (a
		# charge that steered on its way can run out just short of a wall).
		if speed >= CRASH_SPEED * minf(pace, 1.0):
			speed = 0.0
			mode = Mode.STALL
			mode_end = elapsed + STALL_TIME
			_second = false
			lane = 0.0
		else:
			speed = 0.0
			_stopped()
		return
	body.global_position += facing() * step
	lane = maxf(lane - step, 0.0)
	if mode == Mode.CHARGE:
		_charge_left -= step
		if _charge_left <= 0.0:
			mode = Mode.BRAKE


## Host: it has come to a halt after a charge.
func _stopped() -> void:
	lane = 0.0
	if is_enraged() and not _second:
		_second = true
		_rev(DOUBLE_REV)
	else:
		_second = false
		_idle(ENRAGED_PAUSE if is_enraged() else PAUSE)


func _idle(seconds: float) -> void:
	mode = Mode.IDLE
	mode_end = elapsed + seconds
	speed = 0.0


## Host: the next charge, or donuts every DONUT_EVERY-th move.
func _next_move() -> void:
	_moves += 1
	if _moves % DONUT_EVERY == 0:
		mode = Mode.DONUT
		mode_end = elapsed + DONUT_TIME
		_fling_rocks()
		return
	_rev(ENRAGED_REV if is_enraged() else REV_TIME)


func _rev(seconds: float) -> void:
	target = _pick_target()
	if target < 0:
		_idle(1.0)
		return
	var squad := target / 16
	_squad_last[squad] = elapsed
	_player_last[target] = elapsed
	var target_speed := float(_positions[target][2]) if _positions[target].size() > 2 \
		else PACE_SPEED
	pace = clampf(target_speed / PACE_SPEED, PACE_MIN, PACE_MAX)
	mode = Mode.REV
	mode_end = elapsed + seconds
	lane = 0.0


## The squad it went after least recently (a squad with nobody up isn't
## heard from, so it's skipped), and in it the player it went after least
## recently, the nearer of two.
func _pick_target() -> int:
	var best := -1
	var best_score := INF
	var here := body.global_position
	for key in _positions:
		var squad := int(key) / 16
		var score: float = float(_squad_last.get(squad, -1000.0)) * 1000.0 \
			+ float(_player_last.get(key, -1000.0)) \
			+ here.distance_to(to_local_pos(_positions[key][0])) * 0.0001
		if score < best_score:
			best_score = score
			best = key
	return best


## Host: rocks for the donuts, some at nearby players and the rest anywhere
## round it.
func _fling_rocks() -> void:
	var count := ENRAGED_ROCKS if is_enraged() else ROCKS
	var here := body.global_position
	var near := []
	for key in _positions:
		var at := to_local_pos(_positions[key][0])
		if at.distance_to(here) <= ROCK_AIM_RANGE:
			near.append(at)
	var area := arena().grow(ARENA_INSET - ROCK_RADIUS)
	for i in count:
		var spot := here + Vector2.from_angle(randf() * TAU) * randf_range(ROCK_MIN, ROCK_MAX)
		if i < AIMED_ROCKS and not near.is_empty():
			spot = near[i % near.size()] + Vector2.from_angle(randf() * TAU) * randf() * 8.0
		spot = spot.clamp(area.position, area.end)
		var land := elapsed + ROCK_FLIGHT + i * DONUT_TIME * 0.6 / count
		emit_hazard("rock", spot, land + ROCK_LINGER, {"land": land})


## Not the host: carry on from the host's last word, easing towards it.
func _follow_host(delta: float) -> void:
	if _host_at < 0.0:
		return
	var ahead := clampf(elapsed - _host_at, 0.0, 0.3)
	var goal := _host_pos
	if is_driving():
		goal += Vector2.from_angle(_host_heading) * speed * ahead
	body.global_position = body.global_position.lerp(goal, 1.0 - exp(-14.0 * delta))
	if mode == Mode.DONUT:
		heading = wrapf(heading + DONUT_SPIN * delta, -PI, PI)
	else:
		heading = lerp_angle(heading, _host_heading, 1.0 - exp(-15.0 * delta))


## Squads game: the truck is only there to touch and shoot while it's on
## our map (it's still drawn coming in from the edge).
func _update_presence() -> void:
	var map := map_rect()
	body.visible = map.grow(SIZE.x).has_point(body.global_position)
	var away := not map.grow(4.0).has_point(body.global_position)
	if body.dormant != (away or is_defeated()):
		body.dormant = away or is_defeated()


func _lay_tracks(before: Vector2, _delta: float) -> void:
	for i in range(_tracks.size() - 1, -1, -1):
		if elapsed - float(_tracks[i][2]) > TRACK_FADE:
			_tracks.remove_at(i)
	_since_track += before.distance_to(body.global_position)
	if mode == Mode.DONUT:
		_since_track += DONUT_SPIN * 4.0 * get_physics_process_delta_time()
	if _since_track >= TRACK_STEP and body.visible:
		_since_track = 0.0
		_tracks.append([body.global_position, heading, elapsed])
		if _tracks.size() > MAX_TRACKS:
			_tracks.pop_front()


# --- Running things over ------------------------------------------------------------

## Where `pos` is relative to the truck: x along its facing, y to its side.
func _truck_local(pos: Vector2) -> Vector2:
	return (pos - body.global_position).rotated(-heading)


func _under_truck(pos: Vector2, margin: float) -> bool:
	var p := _truck_local(pos)
	return absf(p.x) < HALF.x + margin and absf(p.y) < HALF.y + margin


## Our players and enemies under it while it's moving fast; our players too
## close while it does donuts.
func _run_over() -> void:
	if body.dormant:
		return
	if is_driving() and speed >= HURT_SPEED:
		var damage := _run_over_damage()
		for player in living_players():
			if _under_truck(player.global_position, FOOT_MARGIN):
				player.hurt_by(damage, player.global_position)
				_throw_aside(player)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is BossBody or enemy.is_in_group("objective_structures") \
					or bool(enemy.get("is_mirror")) or not enemy.has_method("take_damage"):
				continue
			if _under_truck(enemy.global_position, FOOT_MARGIN):
				enemy.take_damage(CRUSH_DAMAGE, null, facing() * 40.0)
	elif mode == Mode.DONUT and not is_defeated():
		hurt_players(func(p: Vector2) -> bool:
			return p.distance_to(body.global_position) <= DONUT_RADIUS + PLAYER_HALF * 0.5,
			DONUT_DAMAGE)


func _run_over_damage() -> int:
	return ENRAGED_RUN_OVER_DAMAGE if is_enraged() else RUN_OVER_DAMAGE


## Throws a player out past the truck's nearer side.
func _throw_aside(player: Node2D) -> void:
	var p := _truck_local(player.global_position)
	var side := 1.0 if p.y >= 0.0 else -1.0
	p.y = side * (HALF.y + PLAYER_HALF * 0.5 + FLING)
	player.global_position = body.global_position + p.rotated(heading)
	if player is Player:
		player.stay_in_bounds()


## Our players can't stand inside it: they're pushed out of the nearest side
## of its outline (replaces the base's circle).
func _keep_players_out() -> void:
	if body == null or body.dormant:
		return
	var margin := PLAYER_HALF * 0.5
	for player in living_players():
		var p := _truck_local(player.global_position)
		var dx := HALF.x + margin - absf(p.x)
		var dy := HALF.y + margin - absf(p.y)
		if dx <= 0.0 or dy <= 0.0:
			continue
		if dx < dy:
			p.x = signf(p.x if p.x != 0.0 else 1.0) * (HALF.x + margin)
		else:
			p.y = signf(p.y if p.y != 0.0 else 1.0) * (HALF.y + margin)
		player.global_position = body.global_position + p.rotated(heading)
		if player is Player:
			player.stay_in_bounds()


# --- Hits ---------------------------------------------------------------------------

func hit_multiplier(_body: Node, _at: Vector2) -> float:
	return STALL_MULT if is_stalled() else 1.0


func on_body_slow(_body: Node, mult: float, seconds: float) -> void:
	var m := boss_slow(mult)
	if _pending_slow.is_empty() or m < float(_pending_slow[0]):
		_pending_slow = [m, seconds]


func apply_damage(_part: int, amount: int, _squad: int) -> void:
	hp = maxi(hp - amount, 0)
	if hp == 0:
		defeat()


func boss_report() -> Dictionary:
	var data := {}
	if not _pending_slow.is_empty():
		data["slow"] = _pending_slow
		_pending_slow = []
	if squads_game:
		var pos := {}
		var speeds := {}
		for player in living_players():
			pos[key_of(player)] = to_shared_pos(player.global_position)
			speeds[key_of(player)] = player.move_speed
		data["pos"] = pos
		data["spd"] = speeds
	return data


func boss_receive(_squad: int, data: Dictionary) -> void:
	var speeds: Dictionary = data.get("spd", {})
	for key in data.get("pos", {}):
		_positions[int(key)] = [data["pos"][key], elapsed, float(speeds.get(key, PACE_SPEED))]
	var slow: Array = data.get("slow", [])
	if slow.size() == 2 and float(slow[0]) <= slow_mult:
		slow_mult = float(slow[0])
		_slow_left = maxf(_slow_left, float(slow[1]))


func boss_state() -> Dictionary:
	return {"hp": hp, "max": max_hp, "p": to_shared_pos(body.global_position), "h": heading,
		"v": speed, "m": mode, "end": mode_end, "lane": lane, "slow": slow_mult}


func apply_boss_state(state: Dictionary) -> void:
	hp = int(state.get("hp", hp))
	max_hp = int(state.get("max", max_hp))
	if state.has("p"):
		_host_pos = to_local_pos(state["p"])
		if _host_at < 0.0:
			body.global_position = _host_pos
		_host_at = elapsed
	_host_heading = float(state.get("h", _host_heading))
	speed = float(state.get("v", speed))
	mode = int(state.get("m", mode)) as Mode
	mode_end = float(state.get("end", mode_end))
	lane = float(state.get("lane", lane))
	slow_mult = float(state.get("slow", 1.0))
	_slow_left = 0.3 if slow_mult < 1.0 else 0.0


# --- HUD ----------------------------------------------------------------------------

func bar_segments() -> Array:
	return [{"label": info["name"], "frac": float(hp) / maxf(max_hp, 1.0),
		"color": info["color"], "dim": false}]


func bar_note() -> String:
	if is_stalled():
		return "STALLED: let it have it!"
	return super.bar_note()


## Shown off our map too, so a squad sees it coming.
func markers() -> Array:
	if is_defeated() or body == null:
		return []
	return [[body.global_position, info.get("color", Color.WHITE)]]


# --- Hazards ------------------------------------------------------------------------

func hazard_tick(h: Dictionary, _delta: float) -> void:
	if h["kind"] == "rock" and not h.get("landed", false) and elapsed >= float(h["land"]):
		h["landed"] = true
		var at: Vector2 = h["pos"]
		hurt_players(func(p: Vector2) -> bool:
			return p.distance_to(at) <= ROCK_RADIUS + PLAYER_HALF * 0.5, ROCK_DAMAGE)


func draw_hazard(h: Dictionary) -> void:
	if h["kind"] != "rock":
		return
	var at: Vector2 = h["pos"]
	var land := float(h["land"])
	if elapsed < land:
		var k := clampf((elapsed - float(h["born"])) / maxf(land - float(h["born"]), 0.01), 0.0, 1.0)
		draw_circle(at, ROCK_RADIUS, Color(0.55, 0.4, 0.25, 0.15))
		draw_circle(at, ROCK_RADIUS * k, Color(0.6, 0.42, 0.25, 0.3))
		draw_arc(at, ROCK_RADIUS, 0.0, TAU, 32, Color(0.85, 0.6, 0.35, 0.85), 1.0)
		var height := sin(k * PI) * 60.0 + (1.0 - k) * 20.0
		draw_rect(Rect2(at + Vector2(-2, -2 - height), Vector2(5, 4)), Color(0.4, 0.33, 0.27))
	else:
		var t := clampf((elapsed - land) / ROCK_LINGER, 0.0, 1.0)
		for i in 5:
			var a := i * TAU / 5.0 + float(h["id"])
			var p := at + Vector2.from_angle(a) * ROCK_RADIUS * (0.4 + 0.8 * t)
			draw_rect(Rect2(p.round() - Vector2.ONE, Vector2(3, 3)),
				Color(0.5, 0.4, 0.3, 1.0 - t))


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	# Tyre tracks under everything.
	for mark: Array in _tracks:
		var fade := 1.0 - (elapsed - float(mark[2])) / TRACK_FADE
		var dir := Vector2.from_angle(float(mark[1]))
		var side := dir.orthogonal() * (HALF.y - 4.0)
		var back: Vector2 = mark[0] - dir * (HALF.x - 8.0)
		for s in [-1.0, 1.0]:
			draw_rect(Rect2((back + side * s).round() - Vector2(2, 2), Vector2(4, 4)),
				Color(0.18, 0.13, 0.08, 0.35 * fade))
	super._draw()
	if body == null or is_defeated():
		return
	var from := body.global_position
	var dir := facing()
	var side := dir.orthogonal() * HALF.y
	if mode == Mode.REV and lane > 0.0:
		var locked := elapsed >= mode_end - LOCK_TIME
		var flicker := 0.25 + 0.15 * sin(elapsed * (40.0 if locked else 18.0))
		var tip := from + dir * (HALF.x + lane)
		var start := from + dir * HALF.x
		draw_colored_polygon(PackedVector2Array([start + side, tip + side, tip - side, start - side]),
			Color(1.0, 0.25, 0.15, flicker))
		draw_line(start + side, tip + side, Color(1.0, 0.35, 0.2, 0.8), 1.0)
		draw_line(start - side, tip - side, Color(1.0, 0.35, 0.2, 0.8), 1.0)
		# Chevrons down the lane, marching forward.
		var step := 24.0
		var offset := fmod(elapsed * 60.0, step)
		var d := offset
		while d < lane - 6.0:
			var c := start + dir * d
			draw_polyline(PackedVector2Array([c - side * 0.6, c + dir * 8.0, c + side * 0.6]),
				Color(1.0, 0.85, 0.4, 0.7), 1.0)
			d += step
	elif mode == Mode.DONUT:
		draw_arc(from, DONUT_RADIUS, 0.0, TAU, 40, Color(1.0, 0.35, 0.2, 0.7), 1.0)
		draw_circle(from, DONUT_RADIUS, Color(0.6, 0.45, 0.3, 0.18))


func _paint(b: BossBody) -> void:
	if is_defeated():
		b.draw_set_transform(Vector2.ZERO, -b.rotation)
		paint_death(b, HALF.x, elapsed - defeated_at, info["color"])
		return
	var rev := mode == Mode.REV
	var shake := Vector2.ZERO
	if rev or is_stalled():
		shake = Vector2(roundf(sin(b.age * 70.0)), 0.0)
	paint_truck(b, b.age, shake, b.flash > 0.0, is_stalled(), rev or is_driving(),
		speed / TOP_SPEED)


static func paint_preview(c: CanvasItem, age: float) -> void:
	c.draw_set_transform(Vector2.ZERO, -PI / 2.0 + sin(age * 0.9) * 0.25, Vector2.ONE * 1.5)
	paint_truck(c, age, Vector2(roundf(sin(age * 50.0)), 0.0), false, false, true, 0.0)
	c.draw_set_transform(Vector2.ZERO)


## The truck facing +x: four huge tyres, a red body with a roll bar and a
## windscreen, chrome bumper and lamps at the front, exhausts at the back.
static func paint_truck(c: CanvasItem, age: float, shake: Vector2, flashing: bool, stalled: bool,
		revving: bool, roll: float) -> void:
	var o := shake
	c.draw_rect(Rect2(o + Vector2(-HALF.x + 2, -HALF.y + 4), SIZE), Color(0, 0, 0, 0.3))
	# Tyres, treads scrolling as it rolls.
	for fx in [-1.0, 1.0]:
		for fy in [-1.0, 1.0]:
			var centre := o + Vector2(fx * 14.0, fy * 14.0)
			var tyre := Rect2(centre - Vector2(8, 5), Vector2(16, 10))
			c.draw_rect(tyre, TYRE)
			var scroll := fmod(age * 40.0 * roll, 4.0)
			var x := -8.0 + scroll
			while x < 8.0:
				c.draw_rect(Rect2(centre + Vector2(x, -5), Vector2(1, 10)), TREAD)
				x += 4.0
	# Chassis and body.
	var paint := Color(1, 0.75, 0.7) if flashing else PAINT
	c.draw_rect(Rect2(o + Vector2(-21, -10), Vector2(42, 20)), PAINT_DARK)
	c.draw_rect(Rect2(o + Vector2(-20, -9), Vector2(40, 18)), paint)
	# Bonnet stripe, cab and windscreen.
	c.draw_rect(Rect2(o + Vector2(4, -2), Vector2(14, 4)), Color(1.0, 0.85, 0.3))
	c.draw_rect(Rect2(o + Vector2(-8, -7), Vector2(11, 14)), PAINT_DARK)
	c.draw_rect(Rect2(o + Vector2(1, -6), Vector2(3, 12)), GLASS)
	# Roll bar.
	c.draw_rect(Rect2(o + Vector2(-11, -8), Vector2(2, 16)), CHROME)
	# Bumper and lamps.
	c.draw_rect(Rect2(o + Vector2(20, -9), Vector2(3, 18)), CHROME)
	var lamp := LAMP if not stalled else Color(0.4, 0.38, 0.3)
	c.draw_rect(Rect2(o + Vector2(19, -8), Vector2(2, 3)), lamp)
	c.draw_rect(Rect2(o + Vector2(19, 5), Vector2(2, 3)), lamp)
	# Exhausts, puffing while it revs or drives.
	for fy in [-1.0, 1.0]:
		c.draw_rect(Rect2(o + Vector2(-24, fy * 6.0 - 1.0), Vector2(4, 2)), CHROME)
		if revving:
			var k := fmod(age * 3.0 + (0.5 if fy > 0 else 0.0), 1.0)
			c.draw_circle(o + Vector2(-26.0 - 10.0 * k, fy * (6.0 + 4.0 * k)), 2.0 + 3.0 * k,
				Color(0.35, 0.35, 0.38, 0.6 * (1.0 - k)))
	if stalled:
		# Steam from the bonnet and stars round it.
		for i in 3:
			var k := fmod(age * 1.2 + i * 0.33, 1.0)
			c.draw_circle(o + Vector2(10.0 + 6.0 * k, -4.0 + i * 4.0 - 8.0 * k), 2.0 + 4.0 * k,
				Color(0.9, 0.9, 0.95, 0.55 * (1.0 - k)))
		for i in 4:
			var a := age * 4.0 + i * TAU / 4.0
			var p := (Vector2.from_angle(a) * Vector2(12, 8)).round()
			c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.95, 0.4))
