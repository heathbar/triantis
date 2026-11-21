class_name Objective
extends Node2D
## Base for an objective wave's objective (every Global.objective_every()th wave).
## game.gd makes one at the start of every wave in that mode
## (type_for_wave picks which), adds it to the world and hands it to the wave
## director, which asks it when the wave ends (outcome) and what the wave
## clock shows (display_time). It's freed when the wave ends.
##
## Squads game: the host's copy decides. Every squad's copy reports what
## happens on its own map to the host (report -> host_receive), and the host
## sends everyone its state of the objective every STATE_INTERVAL
## (host_state -> apply_state). In a local game there's only the one copy,
## which is both. Positions shared between squads (the crystal, the hive,
## the VIP's route) are worked out from the map layout, so every squad puts
## them in the same place without being told.
##
## Subclasses override begin, tick, outcome, host_receive, host_state,
## apply_state, status_text, display_time, spawn_point and markers.

enum Outcome { RUNNING, SUCCESS, FAILED }

## Every objective type. "summary" is the one-line version shown in the wave
## banner; the tutorial (scripts/objectives/objective_tutorial.gd) explains
## the rest.
const TYPES := [
	{"id": "territory", "name": "Territory Capture", "color": Color(0.35, 0.95, 0.45),
		"script": "res://scripts/objectives/territory.gd",
		"summary": "Hold your zone to capture it before time runs out"},
	{"id": "crystal", "name": "Defend the Crystal", "color": Color(0.45, 0.85, 1.0),
		"script": "res://scripts/objectives/crystal.gd",
		"summary": "Keep the crystal alive until time runs out"},
	{"id": "hot_potato", "name": "Hot Potato", "color": Color(1.0, 0.6, 0.2),
		"script": "res://scripts/objectives/hot_potato.gd",
		"summary": "Carry the potatoes to the pit before they blow, and before time runs out"},
	{"id": "vip", "name": "VIP Escort", "color": Color(1.0, 0.85, 0.3),
		"script": "res://scripts/objectives/vip_escort.gd",
		"summary": "Walk the VIP to safety"},
	{"id": "nests", "name": "Purge the Nests", "color": Color(0.85, 0.4, 1.0),
		"script": "res://scripts/objectives/nests.gd",
		"summary": "Destroy the nests, then the hive, before time runs out"},
	{"id": "herding_cats", "name": "Herding Cats", "color": Color(1.0, 0.55, 0.75),
		"script": "res://scripts/objectives/herding_cats.gd",
		"summary": "Herd the cats into the pen before time runs out"},
]

const Structure := preload("res://scripts/objectives/structure.gd")
const MarkerOverlay := preload("res://scripts/objectives/marker_overlay.gd")
## Seconds between the host's state updates, and between a squad's routine
## reports (subclasses send events straight away with report()).
const STATE_INTERVAL := 0.2
const REPORT_INTERVAL := 0.2
## Placements stay this far inside the map edges.
const EDGE_INSET := 70.0

## The game scene (scripts/game.gd).
var game: Node2D
var wave_index := 0
var wave: WaveDefinition
## This objective's entry in TYPES.
var info: Dictionary = {}
var squads_game := false
var my_squad := 0
## True for the copy that decides (the host's, or the only one).
var is_authority := true
## Why it failed, for the game over screen (set alongside Outcome.FAILED).
var fail_reason := ""
## Squads that have failed the objective: squad -> why (the host's list,
## sent to everyone with its state). A squad that fails it is knocked out for
## the rest of the wave, just as if it had been wiped out; the run is only
## over if every squad is out. (Failing a shared objective, like the crystal,
## fails the whole wave: outcome() returns FAILED.) In a local game the one
## squad failing is the wave failing, so subclasses fail it in outcome().
var failed_squads := {}
## Seconds since the wave started, by the wave clock (the wave director
## keeps it up to date; the host's in a squads game).
var elapsed := 0.0

var _state_timer := 0.0
var _report_timer := 0.0
var _overlay: MarkerOverlay
## Squad -> seconds since its last report (host only), to notice squads
## that have gone quiet.
var _heard := {}
var _knocked_out := false


## Which objective wave `index` is in a run started with `seed`, drawn from
## the types with ids in `allowed` (all of them if it's empty). Never the
## same type twice in a row if there's a choice; every squad gets the same
## answer.
static func type_for_wave(seed: int, index: int, allowed: Array = []) -> Dictionary:
	var pool: Array = TYPES.filter(func(t: Dictionary) -> bool:
		return allowed.is_empty() or allowed.has(t["id"]))
	if pool.is_empty():
		pool = TYPES
	if pool.size() == 1:
		return pool[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var last := -1
	for i in index + 1:
		var pick := rng.randi_range(0, pool.size() - (1 if last < 0 else 2))
		if last >= 0 and pick >= last:
			pick += 1
		last = pick
	return pool[last]


static func type_by_id(id: String) -> Dictionary:
	for type in TYPES:
		if type["id"] == id:
			return type
	return TYPES[0]


## A new objective of `type` (an entry in TYPES), ready for setup().
static func create(type: Dictionary) -> Node2D:
	var objective: Node2D = load(type["script"]).new()
	objective.info = type
	return objective


## Call before adding to the tree.
func setup(game_node: Node2D, index: int, wave_def: WaveDefinition) -> void:
	game = game_node
	wave_index = index
	wave = wave_def
	squads_game = game.squads_game
	my_squad = Squads.my_squad() if squads_game else 0
	is_authority = not squads_game or Squads.is_host()


func _ready() -> void:
	z_index = -10  # Under the players and enemies, over the ground.
	if squads_game:
		Squads.objective_report.connect(_on_report)
		Squads.objective_state.connect(_on_state)
	_overlay = MarkerOverlay.new()
	_overlay.objective = self
	add_child(_overlay)
	begin()


func _physics_process(delta: float) -> void:
	if not game.is_wave_running():
		return
	tick(delta)
	_report_timer -= delta
	if _report_timer <= 0.0:
		_report_timer = REPORT_INTERVAL
		var routine := periodic_report()
		if not routine.is_empty():
			report(routine)
	if is_authority:
		for squad in _heard:
			_heard[squad] += delta
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state_timer = STATE_INTERVAL
			if squads_game:
				var state := host_state()
				state["_failed"] = failed_squads
				Squads.send_objective_state(wave_index, state)
	queue_redraw()


# --- For subclasses ---------------------------------------------------------------

## Set up the objective (it's in the tree; the wave has just started).
func begin() -> void:
	pass


## Every physics frame of the wave, on every squad's copy.
func tick(_delta: float) -> void:
	pass


## Host (or local game): has the objective been done, or failed? Set
## fail_reason when returning FAILED.
func outcome() -> int:
	return Outcome.RUNNING


## True if the wave ends when its time runs out, as a standard wave does
## (outcome can still fail it early). False: the clock is the objective's
## (display_time) and the wave lasts until outcome() says otherwise.
func uses_wave_clock() -> bool:
	return false


## What the wave timer shows, in seconds.
func display_time(elapsed: float) -> float:
	return maxf(wave.duration - elapsed, 0.0)


## True if display_time counts up (no time limit) rather than down.
func clock_counts_up() -> bool:
	return false


## A short line under the timer saying how it's going.
func status_text() -> String:
	return ""


## Host: a squad's report arrived (our own too).
func host_receive(_squad: int, _data: Dictionary) -> void:
	pass


## Host: the objective's state, for the other squads' apply_state.
func host_state() -> Dictionary:
	return {}


## Not the host: the host's state arrived.
func apply_state(_state: Dictionary) -> void:
	pass


## What to report to the host every REPORT_INTERVAL ({} = nothing).
func periodic_report() -> Dictionary:
	return {}


## Where the next of our enemies should appear, or Vector2.INF for the usual
## spot just off screen.
func spawn_point() -> Vector2:
	return Vector2.INF


## Things to point at from the screen edge while they're off screen:
## [[position (ours), colour], ...].
func markers() -> Array:
	return []


# --- Messages -----------------------------------------------------------------------

## Tell the host something (straight to host_receive in a local game).
func report(data: Dictionary) -> void:
	if not squads_game:
		host_receive(0, data)
	else:
		Squads.send_objective_report(wave_index, data)


func _on_report(squad: int, index: int, data: Dictionary) -> void:
	if index == wave_index and is_authority and game.is_wave_running():
		_heard[squad] = 0.0
		host_receive(squad, data)


func _on_state(index: int, data: Dictionary) -> void:
	if index == wave_index and not is_authority:
		failed_squads = data.get("_failed", failed_squads)
		_check_our_failure()
		apply_state(data)


## Host (or local game): `squad` has failed the objective.
func fail_squad(squad: int, reason: String) -> void:
	if not failed_squads.has(squad):
		failed_squads[squad] = reason
		_check_our_failure()


## Squads in the game that haven't failed the objective.
func squads_still_in() -> Array:
	return present_squads().filter(func(s: int) -> bool: return not failed_squads.has(s))


func _check_our_failure() -> void:
	if squads_game and not _knocked_out and failed_squads.has(my_squad):
		_knocked_out = true
		game.squad_failed_objective(failed_squads[my_squad])


# --- Squads and the map ---------------------------------------------------------------

## Squads in the game, in squad order ([0] in a local game).
func present_squads() -> Array:
	if not squads_game:
		return [0]
	var squads := Squads.squads_present()
	squads.sort()
	return squads


func map_rect() -> Rect2:
	return game.grass_bounds


## Size of one step across the squads' 2x2 grid of maps.
func _stride() -> Vector2:
	return map_rect().size * (1.0 - Squads.MAP_OVERLAP)


## A shared-coordinates position on our map, and back. (The same in a local
## game: there's only our map.)
func to_local_pos(shared_pos: Vector2) -> Vector2:
	return game.link.shared_to_local(shared_pos) if game.link else shared_pos


func to_shared_pos(local_pos: Vector2) -> Vector2:
	return game.link.local_to_shared(local_pos) if game.link else local_pos


## The middle of the area every squad's map shares (the middle of the map in
## a local game), in our coordinates.
func shared_centre() -> Vector2:
	var bounds := map_rect()
	if not squads_game:
		return bounds.get_center()
	# Alpha's map coordinates are the shared ones.
	return to_local_pos(bounds.position + (_stride() + bounds.size) / 2.0)


## `squad`'s map in shared coordinates.
func squad_map_shared(squad: int) -> Rect2:
	var bounds := map_rect()
	return Rect2(bounds.position + Vector2(Squads.SQUAD_GRID[squad]) * _stride(), bounds.size)


## A point on `squad`'s map (shared coordinates), `u` of the way in from its
## outer corner (the one furthest from the other maps) on each axis.
func outer_point(squad: int, u: Vector2) -> Vector2:
	var rect := squad_map_shared(squad)
	var grid := Vector2(Squads.SQUAD_GRID[squad])
	return rect.position + rect.size * Vector2(
		u.x if grid.x == 0 else 1.0 - u.x,
		u.y if grid.y == 0 else 1.0 - u.y)


## The part of our map no other squad's map can overlap (all of it in a
## local game), inset from the edges.
func own_area() -> Rect2:
	var bounds := map_rect()
	if not squads_game:
		return bounds.grow(-EDGE_INSET)
	var grid := Vector2(Squads.SQUAD_GRID[my_squad])
	var overlap := bounds.size * Squads.MAP_OVERLAP
	var lo := bounds.position + overlap * grid
	var hi := bounds.end - overlap * (Vector2.ONE - grid)
	return Rect2(lo, hi - lo).grow(-EDGE_INSET)


## A random point in `area` at least `min_dist` from every point in `avoid`
## (the furthest-away of several tries if none is).
func random_point(area: Rect2, avoid: Array, min_dist: float) -> Vector2:
	var best := area.get_center()
	var best_score := -INF
	for i in 24:
		var p := Vector2(randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		var score := INF
		for a: Vector2 in avoid:
			score = minf(score, p.distance_to(a))
		if score >= min_dist:
			return p
		if score > best_score:
			best_score = score
			best = p
	return best


## Our players who are up.
func living_players() -> Array:
	return game.all_players.filter(func(p: Node) -> bool: return not p.is_dead())


func player_positions() -> Array:
	return game.all_players.map(func(p: Node2D) -> Vector2: return p.global_position)


## A structure (scripts/objectives/structure.gd) at `at`, added to the world.
func add_structure(kind: String, at: Vector2, max_hp: int, radius: float) -> Structure:
	var thing := Structure.new()
	thing.kind = kind
	thing.max_hp = max_hp
	thing.hp = max_hp
	thing.radius = radius
	thing.color = info.get("color", Color.WHITE)
	thing.position = at  # before add_child, so it never appears at the origin
	add_child(thing)
	return thing


# --- Drawing helpers ---------------------------------------------------------------

## A thin ring, `fraction` of it filled clockwise from the top.
func draw_progress_ring(center: Vector2, radius: float, fraction: float, color: Color,
		width := 3.0) -> void:
	var back := color
	back.a *= 0.25
	draw_arc(center, radius, 0.0, TAU, 64, back, width)
	if fraction > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(fraction, 0.0, 1.0),
			64, color, width)
