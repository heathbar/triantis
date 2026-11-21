extends Objective
## Purge the Nests: enemies pour out of nests. Each squad has a nest on its
## own map (a local game has NESTS_SOLO), and a big hive sits in the middle,
## shielded until every nest is destroyed. Destroy the hive to win the wave.
## No clock: the timer counts up.
##
## While a squad has a nest standing, its enemies come out of its nests;
## once the hive's shield is down they come out of the hive too. Each
## standing nest also spawns an extra enemy every NEST_SPAWN_INTERVAL.
##
## Time limit: destroy the hive before the clock runs out, or the wave is
## failed (so there's no leaving the hive up to farm the nests). It's worked
## out from the squads' firepower at the start of the wave (damage a second,
## _firepower()): the time to shoot down a squad's nests (the slowest
## squad's) plus the hive (everyone together), x TIME_SLACK, plus TIME_BASE
## for getting about and fighting.
##
## Squads game: each squad's nest is its own; the host owns the hive's
## health and shield. Every squad reports how many nests it has left and
## the damage its players do to its copy of the hive.

const NEST_RADIUS := 19.0
const HIVE_RADIUS := 34.0
const NESTS_SOLO := 3
const NEST_HP := 110
## Nest health grows this much (x) per wave on top of the wave's enemy health.
const HP_GROWTH_PER_WAVE := 0.08
const HIVE_HP_PER_NEST := 2.0
const NEST_SPAWN_INTERVAL := 7.0
const HIVE_SPAWN_INTERVAL := 4.0
const NEST_SPACING := 280.0
const TIME_SLACK := 2.0
const TIME_BASE := 25.0
const TIME_MIN := 60.0

var hive: Structure
var hive_hp := 1
var hive_max := 1
## Nests still standing across every squad (host's count).
var nests_left := 1
var nests_total := 1
var _nests: Array[Structure] = []
var _pending_damage := 0
## Squad -> [standing, total] (host only).
var _nest_reports := {}
var _spawn_timers := {}
var _hive_timer := HIVE_SPAWN_INTERVAL
var _time := 0.0
## Seconds the squads have, from the start of the wave (the host's).
var time_limit := 120.0
## Health of one of a squad's nests, and how many it has.
var _nest_hp := 1
var _nests_each := 1
## Squad -> its firepower (host only), and ours.
var _firepower := {}
var _my_firepower := 1.0


func begin() -> void:
	var nest_hp := roundi(NEST_HP * wave.enemy_health_multiplier * (1.0 + HP_GROWTH_PER_WAVE * wave_index))
	var count := NESTS_SOLO if not squads_game else 1
	_nest_hp = nest_hp
	_nests_each = count
	var total_nests := count if not squads_game else present_squads().size()
	hive_max = roundi(nest_hp * HIVE_HP_PER_NEST * maxi(total_nests, 2))
	hive_hp = hive_max
	hive = add_structure("hive", shared_centre(), hive_max, HIVE_RADIUS)
	hive.shootable = true
	hive.networked = squads_game
	hive.contact_multiplier = 0.0
	hive.invulnerable = true
	hive.damaged.connect(func(amount: int) -> void: _pending_damage += amount)

	var avoid := [hive.position]
	avoid.append_array(player_positions())
	for i in count:
		var at := random_point(own_area(), avoid, NEST_SPACING)
		avoid.append(at)
		var nest := add_structure("nest", at, nest_hp, NEST_RADIUS)
		nest.shootable = true
		nest.contact_multiplier = 0.0
		_nests.append(nest)
		_spawn_timers[nest] = NEST_SPAWN_INTERVAL * randf_range(0.5, 1.0)
	nests_total = total_nests
	nests_left = total_nests
	_nest_reports[my_squad] = [count, count]
	_my_firepower = _firepower_now()
	_firepower[my_squad] = _my_firepower
	_update_time_limit()


## Our players' damage a second, with whichever of gun or melee hits harder.
func _firepower_now() -> float:
	var total := 0.0
	for p in game.all_players:
		var ranged := float(p.damage * p.shot_pellets) / maxf(p.fire_interval, 0.05)
		var melee := float(p.melee_damage) / maxf(p.melee_interval, 0.05)
		total += maxf(ranged, melee)
	return maxf(total, 1.0)


## Host: the time limit from what each squad can dish out (a squad we haven't
## heard from yet counts as having our firepower).
func _update_time_limit() -> void:
	var nest_phase := 0.0
	var everyone := 0.0
	for squad in present_squads():
		var power: float = _firepower.get(squad, _my_firepower)
		nest_phase = maxf(nest_phase, _nest_hp * _nests_each / power)
		everyone += power
	var hive_phase := hive_max / maxf(everyone, 1.0)
	var seconds := (nest_phase + hive_phase) * TIME_SLACK + TIME_BASE
	time_limit = maxf(ceilf(seconds / 5.0) * 5.0, TIME_MIN)


func _my_nests_left() -> int:
	return _nests.filter(func(n: Structure) -> bool: return not n.is_dead()).size()


func tick(delta: float) -> void:
	_time += delta
	var shielded := nests_left > 0
	hive.invulnerable = shielded
	hive.shield = 1.0 if shielded else 0.0
	if squads_game:
		hive.set_hp(hive_hp)
	else:
		hive_hp = hive.hp
		_nest_reports[0] = [_my_nests_left(), _nests.size()]
		_count_nests()

	# Standing nests (and the hive once it's open) keep spitting enemies out.
	for nest in _nests:
		if nest.is_dead():
			continue
		_spawn_timers[nest] -= delta
		if _spawn_timers[nest] <= 0.0:
			_spawn_timers[nest] = NEST_SPAWN_INTERVAL
			_spawn_extra(nest)
	if not shielded and not hive.is_dead():
		_hive_timer -= delta
		if _hive_timer <= 0.0:
			_hive_timer = HIVE_SPAWN_INTERVAL
			_spawn_extra(hive)


func _spawn_extra(from: Structure) -> void:
	var groups := wave.enemy_groups.filter(func(g: WaveEnemyGroup) -> bool:
		return g != null and g.enemy_scene != null)
	if groups.is_empty():
		return
	var group: WaveEnemyGroup = groups.pick_random()
	game.spawn_enemy_at(group.enemy_scene, _beside(from))


func _beside(thing: Structure) -> Vector2:
	var at := thing.position + Vector2.RIGHT.rotated(randf() * TAU) * (thing.radius + 18.0)
	return at.clamp(map_rect().position + Vector2(12, 12), map_rect().end - Vector2(12, 12))


func spawn_point() -> Vector2:
	var standing := _nests.filter(func(n: Structure) -> bool: return not n.is_dead())
	if not standing.is_empty():
		return _beside(standing.pick_random())
	if nests_left == 0 and not hive.is_dead():
		return _beside(hive)
	return Vector2.INF


func periodic_report() -> Dictionary:
	if not squads_game:
		return {}
	# A wiped-out squad sits out the wave; its nest mustn't keep the hive
	# shielded for everyone else.
	var left := _my_nests_left() if not living_players().is_empty() else 0
	var data := {"left": left, "total": _nests.size(), "power": _my_firepower}
	if _pending_damage > 0:
		data["dmg"] = _pending_damage
		_pending_damage = 0
	return data


func host_receive(squad: int, data: Dictionary) -> void:
	if data.has("power") and not _firepower.has(squad):
		_firepower[squad] = float(data["power"])
		_update_time_limit()
	if data.has("left"):
		_nest_reports[squad] = [int(data["left"]), int(data["total"])]
		_count_nests()
	if data.has("dmg") and nests_left == 0:
		hive_hp = maxi(hive_hp - int(data["dmg"]), 0)


func _count_nests() -> void:
	var left := 0
	var total := 0
	var present := present_squads()
	for squad in present:
		# A squad we haven't heard from yet still has its nest.
		var r: Array = _nest_reports.get(squad, [1, 1])
		left += r[0]
		total += r[1]
	nests_left = left
	nests_total = total


func outcome() -> int:
	if hive_hp <= 0:
		return Outcome.SUCCESS
	# (Another squad's copy only asks once the host has said it failed; its
	# clock may be a touch behind the host's.)
	if elapsed >= time_limit or not is_authority:
		fail_reason = "Time ran out before the hive was destroyed"
		return Outcome.FAILED
	return Outcome.RUNNING


func host_state() -> Dictionary:
	return {"hp": hive_hp, "left": nests_left, "total": nests_total, "limit": time_limit}


func apply_state(state: Dictionary) -> void:
	hive_hp = int(state.get("hp", hive_hp))
	nests_left = int(state.get("left", nests_left))
	nests_total = int(state.get("total", nests_total))
	time_limit = float(state.get("limit", time_limit))


func display_time(wave_elapsed: float) -> float:
	return maxf(time_limit - wave_elapsed, 0.0)


func status_text() -> String:
	if nests_left > 0:
		return "Nests destroyed %d/%d   The hive is shielded" % [nests_total - nests_left, nests_total]
	return "The hive's shield is down!   Hive %d%%" % roundi(100.0 * hive_hp / maxf(hive_max, 1.0))


func markers() -> Array:
	var list := []
	for nest in _nests:
		if not nest.is_dead():
			list.append([nest.position, info["color"]])
	if nests_left == 0 or _nests.all(func(n: Structure) -> bool: return n.is_dead()):
		list.append([hive.position, Color(1, 0.4, 0.4)])
	return list
