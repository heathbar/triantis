extends Boss
## The Lighthouse (boss of wave 10): a tower in the middle of the map that
## turns to face whoever has hurt it most lately, and lights them up.
##
## Facing: every player builds up threat by hurting it (fading by half every
## THREAT_HALF_LIFE seconds); it turns, at TURN_SPEED, towards the player with
## the most. Its front is armoured (hits within FRONT_ARC of where it faces
## do ARMOR_MULT damage) and its back is the weak spot (within REAR_ARC of
## straight behind: WEAK_MULT). So whoever it's facing draws its fire, and
## everyone else gets the back: hurting it the most pulls its aim off a
## squad that's struggling.
##
## Attacks, on a cycle (CYCLE seconds):
##   - the beam: CHARGE seconds of a thin warning line, then FIRE seconds of
##     a wide beam along its facing (it turns slower while firing, so the
##     target can outrun it). Standing in it costs BEAM_DAMAGE every second.
##   - shells: when the beam stops, SHELLS shells lobbed at the target's
##     area. Each lands SHELL_FLIGHT seconds later, marked on the ground
##     until then, and costs SHELL_DAMAGE to anyone in the blast.
## Every VENT_EVERY seconds it vents for VENT_LENGTH seconds: no turning,
## beam or shells, and it takes VENT_MULT damage from every side. That keeps
## a lone player (who can never get behind it) in the fight.
##
## Enraged: faster cycle and turning, more shells, quicker landings, and the
## beam hits harder.
##
## Freeze Ray: slows its turning (at boss strength, Boss.STATUS_STRENGTH).
##
## Squads game: the host does the targeting. Each squad reports where its
## players are and the threat they built up; the host sends its facing (and
## the angle it's turning towards, so other squads' copies can carry on
## turning between updates). Phases come from the shared wave clock.

const RADIUS := 30.0
const DEFAULT_HEALTH := 6000
const ENRAGE_AT := 80.0

const FRONT_ARC := deg_to_rad(65.0)
const REAR_ARC := deg_to_rad(60.0)
const ARMOR_MULT := 0.2
const WEAK_MULT := 2.0
const VENT_MULT := 1.5

const TURN_SPEED := deg_to_rad(42.0)
const FIRING_TURN := 0.45
const ENRAGED_TURN := 1.6
const THREAT_HALF_LIFE := 3.0

## The beam cycle starts this long into the wave.
const FIRST_CYCLE := 2.5
const CYCLE := 7.0
const ENRAGED_CYCLE := 4.8
const CHARGE := 1.1
const FIRE := 2.6
const BEAM_LENGTH := 520.0
const BEAM_HALF_WIDTH := 11.0
const BEAM_DAMAGE := 1
const ENRAGED_BEAM_DAMAGE := 2

const SHELLS := 3
const ENRAGED_SHELLS := 5
const SHELL_SPREAD := 64.0
const SHELL_RADIUS := 30.0
const TargetMarker := preload("res://scripts/target_marker.gd")
const SHELL_FLIGHT := 1.5
const ENRAGED_SHELL_FLIGHT := 1.15
const SHELL_DAMAGE := 2
## How long a landed shell's blast stays drawn.
const SHELL_LINGER := 0.4

const FIRST_VENT := 20.0
const VENT_EVERY := 24.0
const VENT_LENGTH := 4.5

const STONE := Color(0.33, 0.33, 0.38)
const ARMOR := Color(0.62, 0.66, 0.74)
const CORE := Color(1.0, 0.45, 0.2)
const LIGHT := Color(1.0, 0.92, 0.55)

var body: BossBody
var hp := 1
var max_hp := 1
## Facing (radians), and the facing it's turning towards.
var angle := PI / 2.0
var goal := PI / 2.0
## Turning speed multiplier from slows (host's), and how long it has left.
var slow_mult := 1.0
var _slow_left := 0.0

## Host: player key -> threat; player key -> [shared position, when heard].
var _threat := {}
var _positions := {}
## Host: the player it's after (key), or -1.
var target := -1
## Host: the cycle number of the last shell volley.
var _last_volley := -1
## Our players' threat since the last report (key -> amount).
var _pending_threat := {}
## Our strongest slow since the last report: [mult, seconds].
var _pending_slow := []


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	max_hp = scaled_health(base_health(DEFAULT_HEALTH))
	hp = max_hp
	body = add_body(0, shared_centre(), RADIUS, _paint)
	# Face the nearest player to start with.
	var players := living_players()
	if not players.is_empty():
		angle = body.global_position.angle_to_point(players[0].global_position)
		goal = angle


# --- Phases (from the wave clock, the same in every squad's copy) ---------------

func is_venting() -> bool:
	return elapsed >= FIRST_VENT and fmod(elapsed - FIRST_VENT, VENT_EVERY) < VENT_LENGTH


func _cycle_length() -> float:
	return ENRAGED_CYCLE if is_enraged() else CYCLE


## Seconds into the current beam cycle, or -1 before the first.
func _cycle_time() -> float:
	if elapsed < FIRST_CYCLE:
		return -1.0
	return fmod(elapsed - FIRST_CYCLE, _cycle_length())


func _cycle_number() -> int:
	return floori((elapsed - FIRST_CYCLE) / _cycle_length())


func is_charging() -> bool:
	var t := _cycle_time()
	return t >= 0.0 and t < CHARGE and not is_venting() and not is_defeated()


func is_firing() -> bool:
	var t := _cycle_time()
	return t >= CHARGE and t < CHARGE + FIRE and not is_venting() and not is_defeated()


func facing() -> Vector2:
	return Vector2.from_angle(angle)


# --- Every frame --------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	_slow_left = maxf(_slow_left - delta, 0.0)
	if _slow_left <= 0.0:
		slow_mult = 1.0
	if is_authority:
		_host_think(delta)
	if not is_venting() and not is_defeated():
		var speed := TURN_SPEED * slow_mult * (ENRAGED_TURN if is_enraged() else 1.0)
		if is_firing():
			speed *= FIRING_TURN
		angle = rotate_toward(angle, goal, speed * delta)
	if is_firing():
		var damage := ENRAGED_BEAM_DAMAGE if is_enraged() else BEAM_DAMAGE
		hurt_players(_in_beam, damage)


func _in_beam(pos: Vector2) -> bool:
	var to := pos - body.global_position
	var along := to.dot(facing())
	return along > 0.0 and along < BEAM_LENGTH \
		and absf(to.cross(facing())) < BEAM_HALF_WIDTH + PLAYER_HALF


## Host: who to face, and when to lob shells.
func _host_think(delta: float) -> void:
	var fade := pow(0.5, delta / THREAT_HALF_LIFE)
	for key in _threat.keys():
		_threat[key] *= fade
		if _threat[key] < 0.5:
			_threat.erase(key)
	# Our own players, straight from the scene.
	for player in living_players():
		_positions[key_of(player)] = [to_shared_pos(player.global_position), elapsed]
	for key in _positions.keys():
		if elapsed - float(_positions[key][1]) > POSITION_STALE:
			_positions.erase(key)

	target = _pick_target()
	if target >= 0:
		goal = body.global_position.angle_to_point(to_local_pos(_positions[target][0]))

	if is_venting() or is_defeated():
		return
	var t := _cycle_time()
	if t >= CHARGE + FIRE and _cycle_number() != _last_volley:
		_last_volley = _cycle_number()
		_lob_shells()


## The player with the most threat, or (nobody has any) the nearest.
func _pick_target() -> int:
	var best := -1
	var best_threat := 0.0
	for key in _threat:
		if _positions.has(key) and _threat[key] > best_threat:
			best_threat = _threat[key]
			best = key
	if best >= 0:
		return best
	var centre := to_shared_pos(body.global_position)
	var best_dist := INF
	for key in _positions:
		var d := centre.distance_squared_to(_positions[key][0])
		if d < best_dist:
			best_dist = d
			best = key
	return best


func _lob_shells() -> void:
	var at := body.global_position + facing() * 180.0
	if target >= 0 and _positions.has(target):
		at = to_local_pos(_positions[target][0])
	var flight := ENRAGED_SHELL_FLIGHT if is_enraged() else SHELL_FLIGHT
	var count := ENRAGED_SHELLS if is_enraged() else SHELLS
	for i in count:
		var spot := at
		if i > 0:
			spot += Vector2.from_angle(randf() * TAU) * randf_range(0.35, 1.0) * SHELL_SPREAD
		var land := elapsed + flight + i * 0.12
		emit_hazard("shell", spot, land + SHELL_LINGER, {"land": land})


# --- Hits ---------------------------------------------------------------------------

func hit_multiplier(_body: Node, at: Vector2) -> float:
	if is_venting():
		return VENT_MULT
	return side_multiplier(at)


## What a hit from `at` is worth given where it faces (not counting vents).
func side_multiplier(at: Vector2) -> float:
	var from := body.global_position.angle_to_point(at)
	var off := absf(wrapf(from - angle, -PI, PI))
	if off <= FRONT_ARC:
		return ARMOR_MULT
	if off >= PI - REAR_ARC:
		return WEAK_MULT
	return 1.0


func record_hit(_body: Node, damage: float, player: Node) -> void:
	var key := key_of(player)
	_pending_threat[key] = _pending_threat.get(key, 0.0) + damage


func on_body_slow(_body: Node, mult: float, seconds: float) -> void:
	var m := boss_slow(mult)
	if _pending_slow.is_empty() or m < float(_pending_slow[0]):
		_pending_slow = [m, seconds]


func boss_report() -> Dictionary:
	var data := {}
	if not _pending_threat.is_empty():
		data["threat"] = _pending_threat
		_pending_threat = {}
	if not _pending_slow.is_empty():
		data["slow"] = _pending_slow
		_pending_slow = []
	if squads_game:
		var pos := {}
		for player in living_players():
			pos[key_of(player)] = to_shared_pos(player.global_position)
		data["pos"] = pos
	return data


func apply_damage(_part: int, amount: int, _squad: int) -> void:
	hp = maxi(hp - amount, 0)
	if hp == 0:
		defeat()


func boss_receive(_squad: int, data: Dictionary) -> void:
	for key in data.get("threat", {}):
		_threat[int(key)] = _threat.get(int(key), 0.0) + float(data["threat"][key])
	for key in data.get("pos", {}):
		_positions[int(key)] = [data["pos"][key], elapsed]
	var slow: Array = data.get("slow", [])
	if slow.size() == 2 and float(slow[0]) <= slow_mult:
		slow_mult = float(slow[0])
		_slow_left = maxf(_slow_left, float(slow[1]))


func boss_state() -> Dictionary:
	return {"hp": hp, "max": max_hp, "angle": angle, "goal": goal, "slow": slow_mult}


func apply_boss_state(state: Dictionary) -> void:
	hp = int(state.get("hp", hp))
	max_hp = int(state.get("max", max_hp))
	angle = float(state.get("angle", angle))
	goal = float(state.get("goal", goal))
	slow_mult = float(state.get("slow", 1.0))
	_slow_left = 0.3 if slow_mult < 1.0 else 0.0


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
		# The shell itself, dropping in.
		var height := (1.0 - k) * 100.0
		draw_circle(at + Vector2(0, -height), 4.0, Color(0.15, 0.12, 0.1))
	else:
		var t := clampf((elapsed - land) / SHELL_LINGER, 0.0, 1.0)
		draw_circle(at, SHELL_RADIUS * (0.8 + 0.4 * t), Color(1.0, 0.75, 0.3, 0.7 * (1.0 - t)))


func _draw() -> void:
	super._draw()
	if body == null or is_defeated():
		return
	var from := body.global_position
	var dir := facing()
	var side := dir.orthogonal()
	if is_charging():
		var flicker := 0.35 + 0.35 * sin(elapsed * 40.0)
		draw_line(from + dir * RADIUS, from + dir * BEAM_LENGTH, Color(1.0, 0.3, 0.2, flicker), 1.0)
	elif is_firing():
		var w := BEAM_HALF_WIDTH * (1.0 + 0.08 * sin(elapsed * 30.0))
		var pts := PackedVector2Array([
			from + dir * RADIUS * 0.6 + side * w * 0.6, from + dir * BEAM_LENGTH + side * w * 1.6,
			from + dir * BEAM_LENGTH - side * w * 1.6, from + dir * RADIUS * 0.6 - side * w * 0.6])
		draw_colored_polygon(pts, Color(LIGHT, 0.35))
		draw_line(from + dir * RADIUS * 0.6, from + dir * BEAM_LENGTH, Color(1, 1, 0.9, 0.85), w * 0.6)


# --- HUD ----------------------------------------------------------------------------

func bar_segments() -> Array:
	return [{"label": info["name"], "frac": float(hp) / maxf(max_hp, 1.0),
		"color": info["color"], "dim": false}]


func bar_note() -> String:
	if is_defeated():
		return ""
	if is_venting():
		return "VENTING: hit it anywhere!"
	return super.bar_note()


# --- Drawing ------------------------------------------------------------------------

func _paint(b: BossBody) -> void:
	if is_defeated():
		paint_death(b, RADIUS, elapsed - defeated_at, info["color"])
		return
	paint_tower(b, angle - b.global_rotation, b.age, b.flash > 0.0, is_venting(),
		is_charging() or is_firing())


static func paint_preview(c: CanvasItem, age: float) -> void:
	paint_tower(c, -PI / 2.0 + sin(age * 0.8) * 0.4, age, false, false, true)


## The tower facing `facing_angle`: a stone base, an armour plate across the
## front, a glowing core at the back (the weak spot) and the lamp on top.
static func paint_tower(c: CanvasItem, facing_angle: float, age: float, flashing: bool,
		venting: bool, lit: bool) -> void:
	var r := RADIUS
	var dir := Vector2.from_angle(facing_angle)
	c.draw_circle(Vector2(0, r * 0.25), r * 1.05, Color(0, 0, 0, 0.3))
	# Base: an octagon of stone.
	var base := PackedVector2Array()
	for i in 8:
		base.append(Vector2.from_angle(i * TAU / 8.0 + PI / 8.0) * r)
	c.draw_colored_polygon(base, Color(1, 0.4, 0.35) if flashing else STONE)
	c.draw_polyline(base + PackedVector2Array([base[0]]), Color(0.15, 0.15, 0.18), 2.0)
	# The weak spot: a glowing core on its back.
	var pulse := 0.75 + 0.25 * sin(age * 6.0)
	var core_at := -dir * r * 0.62
	c.draw_circle(core_at, r * 0.34, Color(0.25, 0.08, 0.05))
	c.draw_circle(core_at, r * 0.26 * pulse, CORE.lightened(0.3 if venting else 0.0))
	# Armour across the front.
	c.draw_arc(Vector2.ZERO, r * 0.95, facing_angle - FRONT_ARC, facing_angle + FRONT_ARC, 24,
		ARMOR, r * 0.22)
	c.draw_arc(Vector2.ZERO, r * 0.95, facing_angle - FRONT_ARC, facing_angle + FRONT_ARC, 24,
		Color(0.9, 0.93, 1.0), 1.0)
	# The lamp.
	c.draw_circle(Vector2.ZERO, r * 0.42, Color(0.12, 0.12, 0.14))
	c.draw_circle(dir * r * 0.18, r * 0.24, LIGHT if lit else Color(0.5, 0.45, 0.3))
	if venting:
		# Steam puffing out all round.
		for i in 8:
			var a := i * TAU / 8.0 + age * 0.6
			var k := fmod(age * 1.5 + i * 0.37, 1.0)
			c.draw_circle(Vector2.from_angle(a) * r * (1.0 + 0.8 * k), 6.0 + 6.0 * k,
				Color(0.9, 0.9, 0.95, 0.45 * (1.0 - k)))
