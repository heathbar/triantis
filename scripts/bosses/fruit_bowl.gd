extends Boss
## The Fruit Bowl (boss of wave 5, Campaign act 1): a bowl of four fruit in the
## middle of the map. Break the bowl (BOWL_SHARE of its health) and it bursts:
## an explosion hides the bowl, which is gone when it clears, and the four
## fruit fly out of it, land and roll to their spots. Smash all four to win
## (in any order, with no time limit between them; a smashed fruit stays
## down where it was, drawn smashed).
##
## Where the fruit go: in a squads game, to the strips two squads' maps
## share (above, right of, below and left of the middle), so each fruit can
## be hit by two squads: the first between Alpha and Bravo, the second
## between Bravo and Delta, the third between Charlie and Delta, the fourth
## between Alpha and Charlie. A fruit whose two squads are both missing or
## wiped out comes back to the middle, where everyone can reach it. In a
## local game they spread out PIECE_SPREAD of the map from the middle.
##
## Attacks: rings. The bowl (and later each fruit) sends out a ring every so
## often that grows outwards; it has gaps to slip through, and touching it
## costs RING_DAMAGE. Every ring is four arcs with four gaps between.
## Enraged, rings come faster.
##
## Freeze Ray: a slowed bowl or fruit sends its rings slower and less often
## (at boss strength, Boss.STATUS_STRENGTH).
##
## Art: assets/meadow/boss/, drawn 1:1. The bowl is split in two (bowl-top
## behind the fruit, bowl-bottom in front) so the fruit sit inside it.
## Each fruit has a <fruit>_smashed.png for once it's smashed. The burst is
## three of the shared explosions (scripts/explosion_art.gd) across the bowl.
##
## Squads game: the host owns every part's health and where the fruit are
## anchored; the rings are hazards (scripts/bosses/boss.gd). The burst and
## the fruit's flight play out from split_at, so every copy sees the same.

const DEFAULT_HEALTH := 10000
const ENRAGE_AT := 120.0
const BOWL_SHARE := 0.5
## The bowl's body: an oval (half width and height) round the bowl and the
## fruit in it, and its rough size for anything that only knows circles.
const BOWL_OVAL := Vector2(88.0, 48.0)
const BOWL_RADIUS := 60.0
const CORE_PART := 4

const BOWL_TOP := preload("res://assets/meadow/boss/bowl-top.png")
const BOWL_BOTTOM := preload("res://assets/meadow/boss/bowl-bottom.png")
## Where the bowl's top-left corner is drawn, from the body's centre.
const BOWL_AT := Vector2(-96.0, -30.0)
const FRUIT_NAMES := ["Cabbage", "Cantaloupe", "Jackfruit", "Watermelon"]
const FRUIT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/meadow/boss/cabbage.png"),
	preload("res://assets/meadow/boss/cantaloupe.png"),
	preload("res://assets/meadow/boss/jackfruit.png"),
	preload("res://assets/meadow/boss/watermelon.png"),
]
const SMASHED_TEXTURES: Array[Texture2D] = [
	preload("res://assets/meadow/boss/cabbage_smashed.png"),
	preload("res://assets/meadow/boss/cantaloupe_smashed.png"),
	preload("res://assets/meadow/boss/jackfruit_smashed.png"),
	preload("res://assets/meadow/boss/watermelon_smashed.png"),
]
const ExplosionArt := preload("res://scripts/explosion_art.gd")
## Each fruit's rings and health bar (the three green ones told apart:
## cabbage pale green, jackfruit yellow, watermelon its red flesh).
const FRUIT_COLORS := [Color(0.62, 0.95, 0.5), Color(1.0, 0.64, 0.3),
	Color(1.0, 0.9, 0.3), Color(1.0, 0.36, 0.42)]
const BOWL_COLOR := Color(0.36, 0.52, 0.95)
## Each fruit's centre while it sits in the bowl, from the body's centre,
## and the order they're drawn (back to front).
const IN_BOWL := [Vector2(-8, -4), Vector2(25, -4.5), Vector2(-50, -18), Vector2(48, -14.5)]
const BOWL_ORDER := [2, 3, 0, 1]

## The burst: explosions over the bowl (BURSTS) for BURST_TIME seconds. At
## FLING (the bowl hidden under their fireballs) the bowl is gone and the
## fruit fly out, landing FLY_SHARE of the way to their spots at LAND, then
## rolling the rest of the way, arriving at SPLIT_TIME (they can't be hurt
## until then).
const BURST_TIME := 0.7
const FLING := 0.2
const LAND := 0.6
const SPLIT_TIME := 1.9
const FLY_SHARE := 0.3
const FLY_HEIGHT := 30.0
## The burst's explosions: [offset from the bowl's centre, fireball radius,
## seconds after the split it goes off]. A big one in the middle and one at
## each end of the bowl (it's wider than one fireball).
const BURSTS := [
	[Vector2(0, -6), 75.0, 0.0], [Vector2(-62, -12), 56.0, 0.03], [Vector2(62, -12), 56.0, 0.04],
]

const MOVE_SPEED := 180.0
## Fruit wander this far round their spot, rocking WOBBLE radians either
## way on their base as they go.
const DRIFT_RADIUS := 28.0
const DRIFT_SPEED := 0.35
const WOBBLE := 0.1
const WOBBLE_SPEED := 3.2
## Local game: fruit sit this fraction of the map from the middle.
const PIECE_SPREAD := 0.3
## Squads game: how far along its strip (from the middle area's edge to the
## map's edge) a fruit sits.
const STRIP_DEPTH := 0.35
## Fruit sent back to the middle sit this far from it.
const CENTRE_SPACING := 70.0

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

const PIECE_DIRS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## The two squads whose maps share each fruit's strip.
const PIECE_SQUADS := [[0, 1], [1, 3], [2, 3], [0, 2]]

## The bowl's body (null once the burst has cleared), and the fruit's.
var core: BossBody
var pieces: Array = []
var core_hp := 1
var core_max := 1
var piece_hp: Array = [0, 0, 0, 0]
var piece_max := 1
var cracked: Array = [false, false, false, false]
## Fruit sent back to the middle (host's call).
var in_centre: Array = [false, false, false, false]
## When it burst (wave seconds), or -1 while it's whole.
var split_at := -1.0

## Host: part -> seconds until it sends its next ring; part -> [slow, left].
var _ring_timers := {}
var _slows := {}
## Our strongest slow per part since the last report: part -> [mult, seconds].
var _pending_slows := {}


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	var total := scaled_health(base_health(DEFAULT_HEALTH))
	core_max = maxi(roundi(total * BOWL_SHARE), 1)
	core_hp = core_max
	piece_max = maxi(roundi(total * (1.0 - BOWL_SHARE) / 4.0), 1)
	piece_hp = [piece_max, piece_max, piece_max, piece_max]
	core = add_body(CORE_PART, shared_centre(), BOWL_RADIUS, _paint_bowl, Vector2.ZERO, BOWL_OVAL)
	_ring_timers[CORE_PART] = 2.0


func is_split() -> bool:
	return split_at >= 0.0


func pieces_arrived() -> bool:
	return is_split() and elapsed >= split_at + SPLIT_TIME


## Fruit `i`'s rough size (its body's radius).
static func fruit_radius(i: int) -> float:
	var size := FRUIT_TEXTURES[i].get_size()
	return (size.x + size.y) / 4.0 * 0.85


# --- Every frame --------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	if is_split():
		if pieces.is_empty():
			_burst()
		if is_instance_valid(core):
			core.dormant = true
			if elapsed >= split_at + BURST_TIME:
				bodies.erase(core)
				core.queue_free()
				core = null
	if is_authority:
		_host_think(delta)
	var arrived := pieces_arrived()
	for i in pieces.size():
		var piece: BossBody = pieces[i]
		piece.dormant = cracked[i] or is_defeated() or not arrived
		# Under the explosion while it lasts, so they fly out of it.
		piece.z_index = -1 if elapsed < split_at + BURST_TIME else 0
		# (A smashed fruit stays where it fell.)
		if arrived and not cracked[i]:
			piece.position = piece.position.move_toward(_spot(i, elapsed), MOVE_SPEED * delta)
		else:
			piece.position = _flight(i)[0]


## The bowl bursts and the fruit come out (every squad's copy, when it hears).
func _burst() -> void:
	for i in 4:
		var at: Vector2 = _spot(i, elapsed) if pieces_arrived() else _flight(i)[0]
		var piece := add_body(i, at, fruit_radius(i), _paint_fruit)
		pieces.append(piece)
		_ring_timers[i] = SPLIT_TIME + 1.0 + i * 0.9


## Where fruit `i` sits (our coordinates), before its wander.
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


## Where fruit `i` wanders to at wave second `t`.
func _spot(i: int, t: float) -> Vector2:
	return anchor(i) + Vector2.from_angle(t * DRIFT_SPEED + i * PI / 2.0) * DRIFT_RADIUS


## Fruit `i` on its way out of the bowl, now: [where it is on the ground,
## how high it is off it, how far it has rolled round (radians)].
func _flight(i: int) -> Array:
	var from: Vector2 = shared_centre() + IN_BOWL[i]
	var to := _spot(i, split_at + SPLIT_TIME)
	var t := elapsed - split_at
	var along := 0.0
	var lift := 0.0
	if t >= LAND:
		var roll := clampf((t - LAND) / (SPLIT_TIME - LAND), 0.0, 1.0)
		along = FLY_SHARE + (1.0 - FLY_SHARE) * (1.0 - (1.0 - roll) * (1.0 - roll))
	elif t >= FLING:
		var fly := (t - FLING) / (LAND - FLING)
		along = FLY_SHARE * fly
		lift = 4.0 * FLY_HEIGHT * fly * (1.0 - fly)
	# Whole turns, so it lands the right way up; none rolling straight up or
	# down the screen.
	var dx := to.x - from.x
	var turns := roundi(absf(dx) / (TAU * fruit_radius(i)))
	return [from.lerp(to, along), lift, along * turns * TAU * signf(dx)]


func _host_think(delta: float) -> void:
	for part in _slows.keys():
		_slows[part][1] -= delta
		if _slows[part][1] <= 0.0:
			_slows.erase(part)
	if is_defeated():
		return
	# Fruit nobody can reach go to the middle (for good: wiped squads sit
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
	var color: Color = BOWL_COLOR if part == CORE_PART else FRUIT_COLORS[part]
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
		list.append({"label": FRUIT_NAMES[i], "frac": float(piece_hp[i]) / maxf(piece_max, 1.0),
			"color": FRUIT_COLORS[i], "dim": cracked[i]})
	return list


func bar_note() -> String:
	if is_split() and pieces_arrived() and not is_defeated():
		var standing := cracked.count(false)
		if standing < 4:
			return "%d FRUIT LEFT" % standing
	if is_split() and not pieces_arrived():
		return "THE BOWL BURST!"
	return super.bar_note()


func markers() -> Array:
	var list := []
	if not is_split():
		if is_instance_valid(core):
			list.append([core.global_position, BOWL_COLOR])
		return list
	for i in pieces.size():
		# Only fruit we can reach (on our map).
		if not cracked[i] and map_rect().has_point(anchor(i)):
			list.append([pieces[i].global_position, FRUIT_COLORS[i]])
	return list


# --- Drawing ------------------------------------------------------------------------

const FLASH_TINT := Color(1.0, 0.45, 0.4)


func _paint_bowl(b: BossBody) -> void:
	var t := elapsed - split_at
	if not is_split() or t < FLING:
		paint_bowl(b, b.age, b.flash > 0.0)
	if is_split():
		paint_burst(b, t)


func _paint_fruit(b: BossBody) -> void:
	var i: int = b.part
	if elapsed < split_at + FLING:
		return  # Still in the bowl.
	var tint := FLASH_TINT if b.flash > 0.0 else Color.WHITE
	if cracked[i]:
		paint_smashed(b, i)
	elif pieces_arrived():
		paint_fruit(b, i, Vector2.ZERO, sin(b.age * WOBBLE_SPEED + i * 1.7) * WOBBLE, true, tint)
	else:
		var flight := _flight(i)
		var lift: float = flight[1]
		if lift > 0.0:
			_paint_shadow(b, i, lift)
		paint_fruit(b, i, Vector2(0, -lift), flight[2], false, tint)
	if is_defeated():
		paint_death(b, fruit_radius(i), elapsed - defeated_at, FRUIT_COLORS[i])


## A shadow under fruit `i` while it's `lift` off the ground.
func _paint_shadow(c: CanvasItem, i: int, lift: float) -> void:
	var size := FRUIT_TEXTURES[i].get_size()
	c.draw_set_transform(Vector2(0, size.y / 2.0 - 2.0), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, size.x * 0.4 * (1.0 - lift / (FLY_HEIGHT * 2.0)), Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO)


static func paint_preview(c: CanvasItem, age: float) -> void:
	paint_bowl(c, age, false)


## The whole Fruit Bowl: the back of the bowl, the fruit sitting in it
## (each rocking a little), then the front of the bowl over them.
static func paint_bowl(c: CanvasItem, age: float, flashing: bool) -> void:
	var tint := FLASH_TINT if flashing else Color.WHITE
	c.draw_texture(BOWL_TOP, BOWL_AT, tint)
	for i: int in BOWL_ORDER:
		paint_fruit(c, i, IN_BOWL[i], sin(age * WOBBLE_SPEED * 0.6 + i * 1.7) * WOBBLE * 0.4, true, tint)
	c.draw_texture(BOWL_BOTTOM, BOWL_AT, tint)


## Fruit `i` smashed: its smashed art sitting on the ground where the whole
## fruit's base was (b's origin is the fruit's middle).
static func paint_smashed(c: CanvasItem, i: int) -> void:
	var tex := SMASHED_TEXTURES[i]
	var base := Vector2(0, (FRUIT_TEXTURES[i].get_size().y / 2.0)).floor()
	c.draw_texture(tex, base - Vector2((tex.get_size().x / 2.0), tex.get_size().y).floor())


## Fruit `i` centred on `at`, turned `angle`: rocking on its base if `rock`,
## else round its middle (rolling).
static func paint_fruit(c: CanvasItem, i: int, at: Vector2, angle: float, rock: bool,
		tint: Color) -> void:
	var tex := FRUIT_TEXTURES[i]
	var half := (tex.get_size() / 2.0).floor()
	if rock:
		c.draw_set_transform(at + Vector2(0, half.y), angle)
		c.draw_texture(tex, Vector2(-half.x, -half.y * 2.0), tint)
	else:
		c.draw_set_transform(at, angle)
		c.draw_texture(tex, -half, tint)
	c.draw_set_transform(Vector2.ZERO)


## The bowl bursting, `t` seconds after it broke: BURSTS going off across it.
static func paint_burst(c: CanvasItem, t: float) -> void:
	if t >= BURST_TIME:
		return
	for burst: Array in BURSTS:
		ExplosionArt.draw(c, burst[0], t - float(burst[2]), burst[1])
