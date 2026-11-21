extends Boss
## The Quartet (boss of wave 15): four pieces fused around a core in the
## middle of the map. Break the core (CORE_SHARE of its health) and it splits:
## the four pieces fly out. Destroy all four to win (in any order, with no
## time limit between them; a destroyed piece stays down).
##
## Where the pieces go: in a squads game, to the strips two squads' maps
## share (above, right of, below and left of the middle), so each piece can
## be hit by two squads: North between Alpha and Bravo, East between Bravo
## and Delta, South between Charlie and Delta, West between Alpha and
## Charlie. A piece whose two squads are both missing or wiped out comes back
## to the middle, where everyone can reach it. In a local game they spread
## out PIECE_SPREAD of the map from the middle.
##
## Attacks: rings. The core (and later each piece) sends out a ring every so
## often that grows outwards; it has gaps to slip through, and touching it
## costs RING_DAMAGE. Every ring is four arcs with four gaps between. Enraged, rings come faster.
##
## Freeze Ray: a slowed core or piece sends its rings slower and less often
## (at boss strength, Boss.STATUS_STRENGTH).
##
## Squads game: the host owns every piece's health and where
## the pieces are anchored; the rings are hazards (scripts/bosses/boss.gd).

const DEFAULT_HEALTH := 7700
const ENRAGE_AT := 150.0
const CORE_SHARE := 0.5
const CORE_RADIUS := 38.0
const PIECE_RADIUS := 23.0
const CORE_PART := 4

## Seconds the pieces take to fly out after the split (they can't be hurt
## until they arrive).
const SPLIT_TIME := 1.6
const MOVE_SPEED := 180.0
## Pieces wander this far round their spot.
const DRIFT_RADIUS := 28.0
const DRIFT_SPEED := 0.35
## Local game: pieces sit this fraction of the map from the middle.
const PIECE_SPREAD := 0.3
## Squads game: how far along its strip (from the middle area's edge to the
## map's edge) a piece sits.
const STRIP_DEPTH := 0.35
## Pieces sent back to the middle sit this far from it.
const CENTRE_SPACING := 56.0

const RING_SPEED := 86.0
const RING_THICK := 9.0
const RING_DAMAGE := 1
const CORE_RING_EVERY := 3.0
const CORE_RING_REACH := 480.0
const CORE_GAPS := 4
const PIECE_RING_EVERY := 6.2
const PIECE_RING_REACH := 160.0
const PIECE_GAPS := 4
const GAP_HALF := deg_to_rad(24.0)
const ENRAGED_RING_RATE := 1.45

const PIECE_NAMES := ["North", "East", "South", "West"]
const PIECE_COLORS := [Color(0.5, 0.78, 1.0), Color(1.0, 0.62, 0.32),
	Color(0.5, 1.0, 0.6), Color(1.0, 0.48, 0.78)]
const PIECE_DIRS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## The two squads whose maps share each piece's strip.
const PIECE_SQUADS := [[0, 1], [1, 3], [2, 3], [0, 2]]
const CORE_COLOR := Color(0.72, 0.45, 1.0)

var core: BossBody
var pieces: Array = []
var core_hp := 1
var core_max := 1
var piece_hp: Array = [0, 0, 0, 0]
var piece_max := 1
var cracked: Array = [false, false, false, false]
## Pieces sent back to the middle (host's call).
var in_centre: Array = [false, false, false, false]
## When it split (wave seconds), or -1 while it's whole.
var split_at := -1.0

## Host: part -> seconds until it sends its next ring; part -> [slow, left].
var _ring_timers := {}
var _slows := {}
## Our strongest slow per part since the last report: part -> [mult, seconds].
var _pending_slows := {}


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	var total := scaled_health(base_health(DEFAULT_HEALTH))
	core_max = maxi(roundi(total * CORE_SHARE), 1)
	core_hp = core_max
	piece_max = maxi(roundi(total * (1.0 - CORE_SHARE) / 4.0), 1)
	piece_hp = [piece_max, piece_max, piece_max, piece_max]
	core = add_body(CORE_PART, shared_centre(), CORE_RADIUS, _paint_core)
	_ring_timers[CORE_PART] = 2.0


func is_split() -> bool:
	return split_at >= 0.0


func pieces_arrived() -> bool:
	return is_split() and elapsed >= split_at + SPLIT_TIME


# --- Every frame --------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	if is_split() and pieces.is_empty():
		_split_apart()
	if is_authority:
		_host_think(delta)
	for i in pieces.size():
		var piece: BossBody = pieces[i]
		piece.dormant = cracked[i] or is_defeated()
		var to := anchor(i) + Vector2.from_angle(elapsed * DRIFT_SPEED + i * PI / 2.0) * DRIFT_RADIUS
		piece.position = piece.position.move_toward(to, MOVE_SPEED * delta)


## The core breaks into the four pieces (every squad's copy, when it hears).
func _split_apart() -> void:
	if is_instance_valid(core):
		bodies.erase(core)
		core.queue_free()
	for i in 4:
		var piece := add_body(i, shared_centre(), PIECE_RADIUS, _paint_piece)
		pieces.append(piece)
		_ring_timers[i] = SPLIT_TIME + 1.0 + i * 0.9


## Where piece `i` sits (our coordinates), before its wander.
func anchor(i: int) -> Vector2:
	var centre := shared_centre()
	if in_centre[i]:
		return centre + Vector2.from_angle(-PI / 2.0 + i * PI / 2.0) * CENTRE_SPACING
	var bounds := map_rect()
	if not squads_game:
		return centre + PIECE_DIRS[i] * bounds.size * PIECE_SPREAD
	# Half the middle area, then STRIP_DEPTH of the way along the strip.
	var stride := _stride()
	var half_middle := (bounds.size - stride) / 2.0
	return centre + PIECE_DIRS[i] * (half_middle + stride * STRIP_DEPTH)


func _host_think(delta: float) -> void:
	for part in _slows.keys():
		_slows[part][1] -= delta
		if _slows[part][1] <= 0.0:
			_slows.erase(part)
	if is_defeated():
		return
	# Pieces nobody can reach go to the middle (for good: wiped squads sit
	# out the rest of the wave).
	if squads_game:
		var present := present_squads()
		for i in 4:
			var reachable := false
			for squad: int in PIECE_SQUADS[i]:
				if squad in present and squad_up(squad):
					reachable = true
			if not reachable:
				in_centre[i] = true
	# Rings.
	var rate := ENRAGED_RING_RATE if is_enraged() else 1.0
	for part in _ring_timers.keys():
		if not _can_ring(part):
			continue
		var slow := _slow_of(part)
		_ring_timers[part] -= delta * rate * slow
		if _ring_timers[part] <= 0.0:
			var is_core: bool = part == CORE_PART
			_ring_timers[part] = CORE_RING_EVERY if is_core else PIECE_RING_EVERY
			_send_ring(part, slow)


func _can_ring(part: int) -> bool:
	if part == CORE_PART:
		return not is_split()
	return pieces_arrived() and part < pieces.size() and not cracked[part]


func _slow_of(part: int) -> float:
	return float(_slows[part][0]) if _slows.has(part) else 1.0


func _send_ring(part: int, slow: float) -> void:
	var is_core := part == CORE_PART
	var from: Vector2 = core.global_position if is_core else pieces[part].global_position
	var reach := CORE_RING_REACH if is_core else PIECE_RING_REACH
	var speed := RING_SPEED * slow
	var gaps := []
	var count := CORE_GAPS if is_core else PIECE_GAPS
	var turn := randf() * TAU
	for g in count:
		gaps.append(turn + g * TAU / count)
	emit_hazard("ring", from, elapsed + reach / speed,
		{"speed": speed, "reach": reach, "gaps": gaps, "part": part})


# --- Hits ---------------------------------------------------------------------------

func on_body_slow(body: Node, mult: float, seconds: float) -> void:
	var m := boss_slow(mult)
	var old: Array = _pending_slows.get(body.part, [])
	if old.is_empty() or m < float(old[0]):
		_pending_slows[body.part] = [m, seconds]


func boss_report() -> Dictionary:
	if _pending_slows.is_empty():
		return {}
	var data := {"slow": _pending_slows}
	_pending_slows = {}
	return data


func boss_receive(_squad: int, data: Dictionary) -> void:
	var slows: Dictionary = data.get("slow", {})
	for part in slows:
		var s: Array = slows[part]
		if not _slows.has(int(part)) or float(s[0]) <= float(_slows[int(part)][0]):
			_slows[int(part)] = [float(s[0]), float(s[1])]


func apply_damage(part: int, amount: int, _squad: int) -> void:
	if part == CORE_PART:
		if is_split():
			return
		core_hp = maxi(core_hp - amount, 0)
		if core_hp == 0:
			split_at = elapsed
		return
	if part < 0 or part > 3 or not pieces_arrived() or cracked[part]:
		return
	piece_hp[part] = maxi(piece_hp[part] - amount, 0)
	if piece_hp[part] > 0:
		return
	cracked[part] = true
	if not cracked.has(false):
		defeat()


func boss_state() -> Dictionary:
	return {"core": core_hp, "cmax": core_max, "php": piece_hp, "pmax": piece_max,
		"split": split_at, "cracked": cracked, "centre": in_centre}


func apply_boss_state(state: Dictionary) -> void:
	core_hp = int(state.get("core", core_hp))
	core_max = int(state.get("cmax", core_max))
	piece_max = int(state.get("pmax", piece_max))
	split_at = float(state.get("split", split_at))
	for key in ["php", "cracked", "centre"]:
		var list: Array = state.get(key, [])
		if list.size() == 4:
			match key:
				"php": piece_hp = list.duplicate()
				"cracked": cracked = list.duplicate()
				"centre": in_centre = list.duplicate()


# --- Hazards ------------------------------------------------------------------------

func _ring_radius(h: Dictionary) -> float:
	return (elapsed - float(h["born"])) * float(h["speed"])


func _in_gap(h: Dictionary, a: float) -> bool:
	for g in h["gaps"]:
		if absf(wrapf(a - float(g), -PI, PI)) < GAP_HALF:
			return true
	return false


func hazard_tick(h: Dictionary, _delta: float) -> void:
	if h["kind"] != "ring":
		return
	var r := _ring_radius(h)
	var at: Vector2 = h["pos"]
	hurt_players(func(p: Vector2) -> bool:
		var d := p.distance_to(at)
		return absf(d - r) < RING_THICK / 2.0 + PLAYER_HALF and not _in_gap(h, at.angle_to_point(p)),
		RING_DAMAGE)


func draw_hazard(h: Dictionary) -> void:
	if h["kind"] != "ring":
		return
	var r := _ring_radius(h)
	if r <= 1.0:
		return
	var part := int(h["part"])
	var color: Color = CORE_COLOR if part == CORE_PART else PIECE_COLORS[part]
	color.a = 0.85 * (1.0 - 0.6 * r / float(h["reach"]))
	var gaps: Array = h["gaps"]
	var step := TAU / gaps.size()
	for g in gaps:
		var a0 := float(g) + GAP_HALF
		var a1 := float(g) + step - GAP_HALF
		draw_arc(h["pos"], r, a0, a1, 48, color, RING_THICK)
		draw_arc(h["pos"], r, a0, a1, 48, Color(1, 1, 1, color.a * 0.6), 1.0)


# --- HUD ----------------------------------------------------------------------------

func bar_segments() -> Array:
	if not is_split():
		var total := float(core_max + piece_max * 4)
		return [{"label": info["name"], "frac": float(core_hp + piece_max * 4) / maxf(total, 1.0),
			"color": info["color"], "dim": false}]
	var list := []
	for i in 4:
		list.append({"label": PIECE_NAMES[i], "frac": float(piece_hp[i]) / maxf(piece_max, 1.0),
			"color": PIECE_COLORS[i], "dim": cracked[i]})
	return list


func bar_note() -> String:
	if is_split() and pieces_arrived() and not is_defeated():
		var standing := cracked.count(false)
		if standing < 4:
			return "%d PIECE%s LEFT" % [standing, "" if standing == 1 else "S"]
	if is_split() and not pieces_arrived():
		return "IT'S SPLITTING!"
	return super.bar_note()


func markers() -> Array:
	var list := []
	if not is_split():
		if is_instance_valid(core):
			list.append([core.global_position, CORE_COLOR])
		return list
	for i in pieces.size():
		# Only pieces we can reach (on our map).
		if not cracked[i] and map_rect().has_point(anchor(i)):
			list.append([pieces[i].global_position, PIECE_COLORS[i]])
	return list


# --- Drawing ------------------------------------------------------------------------

func _paint_core(b: BossBody) -> void:
	paint_core(b, b.age, b.flash > 0.0)


func _paint_piece(b: BossBody) -> void:
	var i: int = b.part
	if is_defeated():
		paint_death(b, PIECE_RADIUS, elapsed - defeated_at, PIECE_COLORS[i])
		return
	paint_piece(b, PIECE_RADIUS, PIECE_COLORS[i], b.age + i, b.flash > 0.0, cracked[i])


static func paint_preview(c: CanvasItem, age: float) -> void:
	paint_core(c, age, false)


## The whole Quartet: four pieces circling a dark eye.
static func paint_core(c: CanvasItem, age: float, flashing: bool) -> void:
	var r := CORE_RADIUS
	c.draw_circle(Vector2(0, r * 0.3), r * 1.1, Color(0, 0, 0, 0.3))
	c.draw_circle(Vector2.ZERO, r * 0.95, Color(0.16, 0.1, 0.22))
	c.draw_arc(Vector2.ZERO, r * 0.95, 0.0, TAU, 64, CORE_COLOR, 2.0)
	for i in 4:
		var a := age * 0.9 + i * PI / 2.0
		paint_piece(c, r * 0.42, PIECE_COLORS[i], age + i, flashing, false,
			Vector2.from_angle(a) * r * 0.55)
	var look := Vector2.from_angle(age * 0.7) * r * 0.08
	c.draw_circle(Vector2.ZERO, r * 0.26, Color(1, 1, 1) if not flashing else Color(1, 0.4, 0.35))
	c.draw_circle(look, r * 0.12, Color(0.1, 0.02, 0.15))


## One piece: a faceted gem in its colour (dark and cracked once broken).
static func paint_piece(c: CanvasItem, r: float, color: Color, age: float, flashing: bool,
		broken: bool, at := Vector2.ZERO) -> void:
	var fill := color
	if broken:
		fill = color.darkened(0.7)
	elif flashing:
		fill = Color(1, 0.4, 0.35)
	var spin := age * 0.8
	var gem := PackedVector2Array()
	for k in 6:
		gem.append(at + Vector2.from_angle(spin + k * TAU / 6.0) * r * (1.0 if k % 2 == 0 else 0.8))
	c.draw_colored_polygon(gem, fill)
	c.draw_polyline(gem + PackedVector2Array([gem[0]]), Color(1, 1, 1, 0.5 if not broken else 0.15), 1.0)
	if broken:
		c.draw_line(at + Vector2(-r * 0.6, -r * 0.3), at + Vector2(r * 0.1, r * 0.1), Color.BLACK, 1.0)
		c.draw_line(at + Vector2(r * 0.1, r * 0.1), at + Vector2(r * 0.5, -r * 0.5), Color.BLACK, 1.0)
		c.draw_line(at + Vector2(r * 0.1, r * 0.1), at + Vector2(0, r * 0.7), Color.BLACK, 1.0)
	else:
		c.draw_circle(at, r * 0.28, Color(1, 1, 1, 0.6 + 0.3 * sin(age * 5.0)))
