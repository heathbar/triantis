extends Objective
## VIP Escort: a VIP walks a route to safety. It only walks while a player
## is close enough to escort it (with nobody up in the squad escorting it, it
## trudges on alone, slowly). Many enemies go for it instead of the players.
## Get it to the end before the clock runs out to win the wave; if it dies or
## time runs out, the wave (and the run) is lost. The clock is set from the
## route's length, so there's no lingering to farm enemies.
##
## The route is picked at random each time (the same pick on every squad's
## game: it comes from the run seed and the wave number). Local game: one of
## SOLO_PATHS, mirrored and/or turned at random. Squads game: there's one
## VIP, and its route runs through every squad's map in turn, round the grid
## from a random squad in a random direction, with a random detour on each
## map and handovers at random spots in the strips where neighbouring maps
## overlap; it ends in the middle, which everyone shares. The squad whose leg it's on walks it (its game
## moves it and reports how far along it is); the host keeps its health,
## which every squad's copy reports damage to.

const VIP_RADIUS := 14.0
const VIP_HP := 25
const VIP_HP_PER_SQUAD := 40
const VIP_SPEED := 44.0
## Speed when the squad escorting it has nobody up (or has left the game).
const VIP_ALONE_SPEED := 18.0
const ESCORT_RADIUS := 96.0
## Enemies whose objective_roll is under this go for the VIP when it's
## within LURE_RADIUS of them (unless a player is right next to them).
const LURE_SHARE := 0.6
const LURE_RADIUS := 260.0
const AGGRO_RADIUS := 44.0
## Squads round the 2x2 grid; the route visits them in this order or its
## reverse, starting anywhere.
const ROUTE_ORDER := [0, 1, 3, 2]
## Time limit: the time the VIP takes to walk the route non-stop, times
## TIME_SLACK, plus TIME_BASE (rounded up to 5 s).
const TIME_SLACK := 1.5
const TIME_BASE := 15.0
## Routes on a single map, as fractions of the way across it (from its outer
## corner in a squads game). The last point is the end, unless it's a squads
## game, where the route then ends in the shared middle.
const SOLO_PATHS := {
	"Perimeter": [Vector2(0.15, 0.15), Vector2(0.85, 0.15), Vector2(0.85, 0.85),
		Vector2(0.15, 0.85), Vector2(0.5, 0.5)],
	"Zigzag": [Vector2(0.12, 0.12), Vector2(0.88, 0.26), Vector2(0.12, 0.42),
		Vector2(0.88, 0.58), Vector2(0.12, 0.74), Vector2(0.85, 0.88)],
	"Spiral": [Vector2(0.12, 0.12), Vector2(0.88, 0.12), Vector2(0.88, 0.88),
		Vector2(0.12, 0.88), Vector2(0.12, 0.34), Vector2(0.66, 0.34), Vector2(0.66, 0.66),
		Vector2(0.4, 0.62)],
	"Crossroads": [Vector2(0.12, 0.12), Vector2(0.88, 0.88), Vector2(0.88, 0.12),
		Vector2(0.12, 0.88), Vector2(0.5, 0.5)],
	"Switchback": [Vector2(0.12, 0.12), Vector2(0.3, 0.88), Vector2(0.5, 0.12),
		Vector2(0.7, 0.88), Vector2(0.88, 0.12)],
}
## Squads game: ways the route can wander on each squad's map between
## arriving and moving on (fractions from the map's outer corner; visited
## nearest first).
const LEG_DETOURS := [
	[],
	[Vector2(0.18, 0.18)],
	[Vector2(0.42, 0.42)],
	[Vector2(0.15, 0.55), Vector2(0.55, 0.15)],
	[Vector2(0.3, 0.14), Vector2(0.14, 0.3)],
]
## Where the route can start on the first squad's map, and how far in from
## the outer edges a handover can be.
const START_POINTS := [Vector2(0.15, 0.15), Vector2(0.15, 0.55), Vector2(0.55, 0.15)]
const HANDOVER_DEPTHS := [0.18, 0.3, 0.42]

var vip: Structure
var vip_hp := VIP_HP
var vip_max := VIP_HP
## How far along the route it is, in pixels (host's; or ours while we're
## walking it).
var distance := 0.0
var route_length := 0.0
## Seconds the escort has, from the start of the wave.
var time_limit := 60.0
## Which way the route goes (for tests and debugging).
var path_name := ""
## [[position (shared), squad walking it towards this point], ...]
var _route: Array = []
## Running total of the route's length at each point.
var _cumulative: Array[float] = []
var _shown_distance := 0.0
var _pending_damage := 0
var _escorted := false
var _age := 0.0


func begin() -> void:
	_build_route()
	vip_max = VIP_HP + VIP_HP_PER_SQUAD * (present_squads().size() - 1)
	vip_hp = vip_max
	vip = add_structure("vip", _point_at(0.0), vip_max, VIP_RADIUS)
	vip.networked = true
	vip.lure = _lures
	vip.damaged.connect(func(amount: int) -> void: _pending_damage += amount)
	_place_players()


## Start next to the VIP if we walk it first, so it's in view and we can set
## off straight away; otherwise (squads game) at the flag where it'll be
## handed over to us.
func _place_players() -> void:
	var start := vip.position
	if _walker_at(0.0) != my_squad:
		var leg := -1
		for i in range(1, _route.size()):
			if _route[i][1] == my_squad:
				leg = i
				break
		if leg < 0:
			return  # Not on the route (shouldn't happen).
		start = to_local_pos(_route[leg - 1][0])
	# A step back from the route, so nobody starts standing on the VIP.
	game.place_players(start + Vector2(0, VIP_RADIUS + 44.0))


func _build_route() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Global.run_seed, wave_index, "vip"])
	var present := present_squads()
	if present.size() <= 1:
		_build_solo_route(rng, present[0] if not present.is_empty() else my_squad)
	else:
		_build_squads_route(rng, present)
	_cumulative = [0.0]
	for i in range(1, _route.size()):
		_cumulative.append(_cumulative[-1] + (_route[i][0] as Vector2).distance_to(_route[i - 1][0]))
	route_length = _cumulative[-1]
	time_limit = ceilf((route_length / VIP_SPEED * TIME_SLACK + TIME_BASE) / 5.0) * 5.0


## One of SOLO_PATHS on `squad`'s map, mirrored and/or turned at random.
func _build_solo_route(rng: RandomNumberGenerator, squad: int) -> void:
	var names := SOLO_PATHS.keys()
	path_name = names[rng.randi_range(0, names.size() - 1)]
	var flip_x := rng.randf() < 0.5
	var flip_y := rng.randf() < 0.5
	var turn := rng.randf() < 0.5
	var points: Array = SOLO_PATHS[path_name].duplicate()
	if squads_game:
		points.pop_back()  # It ends in the shared middle instead.
	for u: Vector2 in points:
		if turn:
			u = Vector2(u.y, u.x)
		if flip_x:
			u.x = 1.0 - u.x
		if flip_y:
			u.y = 1.0 - u.y
		var at := outer_point(squad, u) if squads_game \
			else to_shared_pos(map_rect().position + map_rect().size * u)
		_route.append([at, squad])
	if squads_game:
		_route.append([to_shared_pos(shared_centre()), squad])


## Round every present squad's map from a random one, in a random direction.
func _build_squads_route(rng: RandomNumberGenerator, present: Array) -> void:
	var cycle: Array = ROUTE_ORDER.duplicate()
	if rng.randf() < 0.5:
		cycle.reverse()
	var start := rng.randi_range(0, cycle.size() - 1)
	cycle = cycle.slice(start) + cycle.slice(0, start)
	var order: Array = cycle.filter(func(s: int) -> bool: return s in present)
	path_name = "%s first, %s" % [Squads.SQUAD_NAMES[order[0]],
		"clockwise" if cycle[1] == ROUTE_ORDER[(ROUTE_ORDER.find(cycle[0]) + 1) % 4] else "anticlockwise"]

	_route.append([outer_point(order[0], START_POINTS[rng.randi_range(0, START_POINTS.size() - 1)]),
		order[0]])
	for i in order.size():
		var squad: int = order[i]
		# Wander on this map...
		var detour: Array = LEG_DETOURS[rng.randi_range(0, LEG_DETOURS.size() - 1)].map(
			func(u: Vector2) -> Vector2: return outer_point(squad, u))
		while not detour.is_empty():
			var here: Vector2 = _route[-1][0]
			var nearest := 0
			for j in detour.size():
				if here.distance_to(detour[j]) < here.distance_to(detour[nearest]):
					nearest = j
			_route.append([detour[nearest], squad])
			detour.remove_at(nearest)
		# ...then hand over to the next squad, halfway between the two maps (in
		# the strip they share), or finish in the middle.
		if i + 1 < order.size():
			var depth: float = HANDOVER_DEPTHS[rng.randi_range(0, HANDOVER_DEPTHS.size() - 1)]
			var u := Vector2(depth, depth)
			_route.append([(outer_point(squad, u) + outer_point(order[i + 1], u)) / 2.0, squad])
		else:
			_route.append([to_shared_pos(shared_centre()), squad])


## Where `d` pixels along the route is, in our coordinates.
func _point_at(d: float) -> Vector2:
	d = clampf(d, 0.0, route_length)
	for i in range(1, _route.size()):
		if d <= _cumulative[i] or i == _route.size() - 1:
			var span := maxf(_cumulative[i] - _cumulative[i - 1], 0.001)
			var t := clampf((d - _cumulative[i - 1]) / span, 0.0, 1.0)
			return to_local_pos((_route[i - 1][0] as Vector2).lerp(_route[i][0], t))
	return to_local_pos(_route[0][0])


## The squad walking the VIP at `d` pixels along.
func _walker_at(d: float) -> int:
	for i in range(1, _route.size()):
		if d < _cumulative[i]:
			return _route[i][1]
	return _route[-1][1]


func _lures(enemy: Node) -> bool:
	return enemy.objective_roll < LURE_SHARE \
		and enemy.global_position.distance_to(vip.global_position) <= LURE_RADIUS \
		and enemy.nearest_player_distance() > AGGRO_RADIUS


func tick(delta: float) -> void:
	_age += delta
	var walker := _walker_at(distance)
	_escorted = false
	if walker == my_squad:
		var living := living_players()
		var speed := VIP_ALONE_SPEED if living.is_empty() else 0.0
		for player in living:
			if player.global_position.distance_to(vip.global_position) <= ESCORT_RADIUS:
				_escorted = true
				speed = VIP_SPEED
				break
		distance = minf(distance + speed * delta, route_length)
	elif is_authority and walker not in present_squads():
		distance = minf(distance + VIP_ALONE_SPEED * delta, route_length)  # Its squad left.
	# Others ease towards the reported spot instead of jumping.
	if walker == my_squad or absf(_shown_distance - distance) > 120.0:
		_shown_distance = distance
	else:
		_shown_distance = move_toward(_shown_distance, distance, VIP_SPEED * 1.5 * delta)
	vip.position = _point_at(_shown_distance)
	vip.set_hp(vip_hp)
	if not squads_game and _pending_damage > 0:
		report({"dmg": _pending_damage})
		_pending_damage = 0


func periodic_report() -> Dictionary:
	if not squads_game:
		return {}
	var data := {}
	if _walker_at(distance) == my_squad:
		data["d"] = distance
	if _pending_damage > 0:
		data["dmg"] = _pending_damage
		_pending_damage = 0
	return data


func host_receive(_squad: int, data: Dictionary) -> void:
	if data.has("d"):
		distance = maxf(distance, float(data["d"]))
	if data.has("dmg"):
		vip_hp = maxi(vip_hp - int(data["dmg"]), 0)


func outcome() -> int:
	if vip_hp <= 0:
		fail_reason = "The VIP didn't make it"
		return Outcome.FAILED
	if distance >= route_length:
		return Outcome.SUCCESS
	# (Another squad's copy only asks once the host has said it failed; its
	# clock may be a touch behind the host's.)
	if elapsed >= time_limit or not is_authority:
		fail_reason = "Time ran out before the VIP got there"
		return Outcome.FAILED
	return Outcome.RUNNING


func host_state() -> Dictionary:
	return {"d": distance, "hp": vip_hp}


func apply_state(state: Dictionary) -> void:
	vip_hp = int(state.get("hp", vip_hp))
	var d := float(state.get("d", distance))
	# While it's our leg we're walking it; only ever move it forwards.
	if _walker_at(distance) != my_squad or d > distance:
		distance = d


func display_time(wave_elapsed: float) -> float:
	return maxf(time_limit - wave_elapsed, 0.0)


func status_text() -> String:
	var pct := roundi(100.0 * distance / maxf(route_length, 1.0))
	var line := "VIP %d%% of the way   Health %d%%" % [pct, roundi(100.0 * vip_hp / maxf(vip_max, 1.0))]
	var walker := _walker_at(distance)
	if squads_game and walker != my_squad:
		line = "%s squad is escorting   " % Squads.SQUAD_NAMES[walker] + line
	elif not _escorted:
		line = "Stay close to the VIP!   " + line
	return line


func markers() -> Array:
	return [[vip.position, info["color"]], [_point_at(route_length), Color(0.4, 1.0, 0.5)]]


func _draw() -> void:
	var c: Color = info["color"]
	# The rest of the route, dotted, with flags at the handovers and the end.
	var from := _shown_distance
	var prev := _point_at(from)
	for i in range(1, _route.size()):
		if _cumulative[i] <= from:
			continue
		var p := to_local_pos(_route[i][0])
		draw_dashed_line(prev, p, Color(c, 0.55), 2.0, 7.0)
		prev = p
		var flag: Color = Color(0.4, 1.0, 0.5) if i == _route.size() - 1 \
			else Squads.SQUAD_COLORS[_route[i + 1][1]] if squads_game and i + 1 < _route.size() \
			else Color(c, 0.7)
		draw_line(p, p + Vector2(0, -22), Color.BLACK, 2.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(14, -18),
			p + Vector2(0, -13)]), flag)
	# Escort range.
	var ring := Color(c, 0.35 if _escorted else 0.15 + 0.1 * sin(_age * 5.0))
	draw_arc(vip.position, ESCORT_RADIUS, 0.0, TAU, 96, ring, 1.0)
