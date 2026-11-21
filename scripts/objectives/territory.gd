extends Objective
## Territory Capture: capture fills up only while players stand in their
## squad's zone. Each squad has its own zone on its own map, which moves
## somewhere else after it's been held for a while. Enemies inside a zone
## contest it (it counts at half rate). Fill it before the wave clock runs
## out to win the wave; if time runs out first, it's failed. The time limit
## is the hold time plus some slack, so there's no lingering to farm enemies.
##
## Squads game: every squad reports whether its zone is held, contested and
## whether any of its players are up; capture fills at
## (zones held, contested ones counting half) / (squads with someone up), so
## one squad standing around costs everyone time. Capture is shared, so
## running out of time fails every squad.

const ZONE_RADIUS := 90.0
## Of the hold time: each zone moves after being held this fraction of it.
const MOVE_AFTER := 1.0 / 3.0
## Seconds of hold needed are the wave's duration x this.
const HOLD_FRACTION := 0.8
const CONTESTED_RATE := 0.5
## Time limit: the hold time x TIME_SLACK, plus TIME_BASE (rounded up to 5 s).
const TIME_SLACK := 1.75
const TIME_BASE := 15.0

## Seconds of capture so far (host's; others follow it), out of hold_needed.
var progress := 0.0
var hold_needed := 30.0
## Seconds the squads have, from the start of the wave.
var time_limit := 60.0
## Squads holding / with someone up (host's count, for the status line).
var squads_holding := 0.0
var squads_alive := 1
var _zone_at := Vector2.ZERO
## Seconds our zone has been held since it last moved.
var _held_here := 0.0
var _held := false
var _contested := false
## Squad -> {"held", "contested", "alive"} (host only).
var _reports := {}
var _pulse := 0.0


func begin() -> void:
	hold_needed = maxf(wave.duration * HOLD_FRACTION, 10.0)
	time_limit = ceilf((hold_needed * TIME_SLACK + TIME_BASE) / 5.0) * 5.0
	_move_zone()


func _move_zone() -> void:
	var avoid := [_zone_at] if _zone_at != Vector2.ZERO else []
	avoid.append_array(player_positions())
	# Far enough to make a run for it, near enough to reach.
	_zone_at = random_point(own_area(), avoid, 220.0)
	_held_here = 0.0


func tick(delta: float) -> void:
	_pulse += delta
	_held = false
	for player in living_players():
		if player.global_position.distance_to(_zone_at) <= ZONE_RADIUS:
			_held = true
			break
	_contested = false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("is_mirror") or enemy.is_in_group("objective_structures"):
			continue
		if enemy.global_position.distance_to(_zone_at) <= ZONE_RADIUS:
			_contested = true
			break
	if _held:
		_held_here += delta * (CONTESTED_RATE if _contested else 1.0)
		if _held_here >= hold_needed * MOVE_AFTER:
			_move_zone()
	if is_authority:
		if not squads_game:
			_reports[0] = _my_report()
		_advance(delta)


func _my_report() -> Dictionary:
	return {"held": _held, "contested": _contested, "alive": not living_players().is_empty()}


func periodic_report() -> Dictionary:
	return _my_report() if squads_game else {}


func host_receive(squad: int, data: Dictionary) -> void:
	_reports[squad] = data


func _advance(delta: float) -> void:
	var holding := 0.0
	var alive := 0
	var present := present_squads()
	for squad in _reports:
		if squad not in present:
			continue
		var r: Dictionary = _reports[squad]
		if not r.get("alive", true):
			continue
		alive += 1
		if r.get("held", false):
			holding += CONTESTED_RATE if r.get("contested", false) else 1.0
	squads_holding = holding
	squads_alive = maxi(alive, 1)
	progress = minf(progress + delta * holding / squads_alive, hold_needed)


func outcome() -> int:
	if progress >= hold_needed:
		return Outcome.SUCCESS
	# (Another squad's copy only asks once the host has said it failed; its
	# clock may be a touch behind the host's.)
	if elapsed >= time_limit or not is_authority:
		fail_reason = "Time ran out before the zones were captured"
		return Outcome.FAILED
	return Outcome.RUNNING


func host_state() -> Dictionary:
	return {"p": progress, "h": squads_holding, "n": squads_alive}


func apply_state(state: Dictionary) -> void:
	progress = state.get("p", progress)
	squads_holding = state.get("h", squads_holding)
	squads_alive = state.get("n", squads_alive)


func display_time(wave_elapsed: float) -> float:
	return maxf(time_limit - wave_elapsed, 0.0)


func status_text() -> String:
	var line := "IN THE ZONE" if _held else "Get to your zone!"
	if _held and _contested:
		line = "CONTESTED - clear the zone!"
	line += "   Captured %d%%" % floori(100.0 * progress / maxf(hold_needed, 0.01))
	if squads_game and present_squads().size() > 1:
		line += "   (%s of %d squads holding)" % [str(snappedf(squads_holding, 0.5)), squads_alive]
	return line


func markers() -> Array:
	return [[_zone_at, info["color"]]]


func _draw() -> void:
	var base: Color = info["color"]
	var c := base if _held else Color(1, 1, 1)
	if _held and _contested:
		c = Color(1.0, 0.6, 0.2)
	var fill := c
	fill.a = 0.12 + (0.06 * sin(_pulse * 4.0) if _held else 0.0)
	draw_circle(_zone_at, ZONE_RADIUS, fill)
	draw_arc(_zone_at, ZONE_RADIUS, 0.0, TAU, 96, Color(c, 0.8), 2.0)
	# Dashes rotating slowly round the edge.
	for i in 24:
		var a := _pulse * 0.4 + i * TAU / 24.0
		draw_arc(_zone_at, ZONE_RADIUS + 5.0, a, a + 0.12, 4, Color(c, 0.6), 2.0)
	# How long until it moves, and the clock overall.
	draw_progress_ring(_zone_at, ZONE_RADIUS - 8.0, _held_here / (hold_needed * MOVE_AFTER),
		Color(c, 0.7), 2.0)
	draw_progress_ring(_zone_at, 18.0, progress / hold_needed, base, 5.0)
