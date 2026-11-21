extends Objective
## Defend the Crystal: one crystal in the middle (the area every squad's map
## shares) that most enemies go for instead of players, unless a player gets
## close to them. Survive until the wave's time runs out; if the crystal is
## destroyed, the wave is lost.
##
## Shield generators: each squad has one on its own map (a local game has
## GENERATORS_SOLO). Every generator still standing shields the crystal: it
## takes (1 - SHIELD_MAX x standing / total) of the damage done to it. Some
## enemies (GENERATOR_SHARE of them) go for a generator instead, so a squad
## that only guards the crystal loses its generator, and everyone's crystal
## gets more fragile.
##
## Engineers (the engineer class) repair generators just by standing next to
## one: REPAIR_RATE health a second, faster with more engineering. They can
## even rebuild a destroyed one, which comes back online once it's rebuilt to
## REBUILD_AT of its health.
##
## Squads game: the host owns the crystal's health. Every squad's copy of the
## crystal reports the damage its own enemies do; each squad reports how many
## of its generators are standing.

const CRYSTAL_RADIUS := 22.0
const CRYSTAL_HP := 300
## Extra crystal health for each squad after the first (more squads, more
## enemies at it).
const CRYSTAL_HP_PER_SQUAD := 200
const GENERATOR_RADIUS := 14.0
const GENERATOR_HP := 90
const GENERATORS_SOLO := 2
const SHIELD_MAX := 0.75
## Enemies whose objective_roll is under this go for a generator.
const GENERATOR_SHARE := 0.3
## Enemies going for the crystal turn on a player this close to them.
const AGGRO_RADIUS := 64.0
const CONTACT_MULTIPLIER := 2.0
## Engineers within this of a generator's edge repair it.
const REPAIR_REACH := 28.0
## Health a second one engineer repairs at 0 engineering; x (1 + engineering
## / 100), so an engineer (+40) does 1.4x this.
const REPAIR_RATE := 12.0
## A destroyed generator comes back online at this fraction of its health.
const REBUILD_AT := 0.5
const REPAIR_CLASS := "engineer"

var crystal: Structure
var crystal_hp := CRYSTAL_HP
var crystal_max := CRYSTAL_HP
## Generators standing / built, across every squad (host's count).
var generators_up := 0
var generators_total := 0
var _generators: Array[Structure] = []
## Generator -> repair done but not yet a whole point of health; and, for a
## destroyed one, the health rebuilt so far.
var _repair_carry := {}
var _rebuild := {}
## Generators being repaired this frame (for the sparks).
var _repairing := {}
var _age := 0.0
## Damage our crystal copy has taken since the last report.
var _pending_damage := 0
## Squad -> [standing, total] (host only).
var _gen_reports := {}


func begin() -> void:
	crystal_max = CRYSTAL_HP + CRYSTAL_HP_PER_SQUAD * (present_squads().size() - 1)
	crystal_hp = crystal_max
	crystal = add_structure("crystal", shared_centre(), crystal_max, CRYSTAL_RADIUS)
	crystal.networked = true
	crystal.contact_multiplier = CONTACT_MULTIPLIER
	crystal.lure = _crystal_lures
	crystal.damaged.connect(func(amount: int) -> void: _pending_damage += amount)

	var count := GENERATORS_SOLO if not squads_game else 1
	var avoid := [crystal.position]
	avoid.append_array(player_positions())
	for i in count:
		var at := random_point(own_area(), avoid, 260.0)
		avoid.append(at)
		var gen := add_structure("generator", at, GENERATOR_HP, GENERATOR_RADIUS)
		gen.contact_multiplier = CONTACT_MULTIPLIER
		gen.lure = _generator_lures.bind(gen)
		_generators.append(gen)
	generators_total = count
	generators_up = count
	_gen_reports[my_squad] = [count, count]


func _crystal_lures(enemy: Node) -> bool:
	if enemy.objective_roll < GENERATOR_SHARE and _any_generator_standing():
		return false
	return enemy.nearest_player_distance() > AGGRO_RADIUS


func _generator_lures(enemy: Node, gen: Structure) -> bool:
	return enemy.objective_roll < GENERATOR_SHARE and not gen.is_dead() \
		and enemy.nearest_player_distance() > AGGRO_RADIUS


func _any_generator_standing() -> bool:
	for gen in _generators:
		if not gen.is_dead():
			return true
	return false


func _my_generators_up() -> int:
	var up := 0
	for gen in _generators:
		if not gen.is_dead():
			up += 1
	return up


## The fraction of damage the crystal takes with the current shields.
func damage_taken_fraction() -> float:
	if generators_total <= 0:
		return 1.0
	return 1.0 - SHIELD_MAX * float(generators_up) / float(generators_total)


func tick(delta: float) -> void:
	_age += delta
	_repair(delta)
	crystal.set_hp(crystal_hp)
	crystal.shield = float(generators_up) / float(maxi(generators_total, 1))
	if not squads_game and _pending_damage > 0:
		report({"dmg": _pending_damage})
		_pending_damage = 0
	if not squads_game:
		_gen_reports[0] = [_my_generators_up(), _generators.size()]
		_count_generators()


## Our engineers fix the generators they're standing next to.
func _repair(delta: float) -> void:
	_repairing.clear()
	for gen in _generators:
		var rate := 0.0
		for player in living_players():
			if player.class_id == REPAIR_CLASS \
					and player.global_position.distance_to(gen.position) <= gen.radius + REPAIR_REACH:
				rate += REPAIR_RATE * maxf(1.0 + player.get_attribute("engineering") / 100.0, 0.25)
		if rate <= 0.0:
			continue
		if gen.is_dead():
			_repairing[gen] = true
			_rebuild[gen] = _rebuild.get(gen, 0.0) + rate * delta
			if _rebuild[gen] >= gen.max_hp * REBUILD_AT:
				_rebuild.erase(gen)
				gen.set_hp(ceili(gen.max_hp * REBUILD_AT))
		elif gen.hp < gen.max_hp:
			_repairing[gen] = true
			_repair_carry[gen] = _repair_carry.get(gen, 0.0) + rate * delta
			var whole := floori(_repair_carry[gen])
			if whole > 0:
				_repair_carry[gen] -= whole
				gen.set_hp(gen.hp + whole)


func periodic_report() -> Dictionary:
	if not squads_game:
		return {}
	var data := {"up": _my_generators_up(), "total": _generators.size()}
	if _pending_damage > 0:
		data["dmg"] = _pending_damage
		_pending_damage = 0
	return data


func host_receive(squad: int, data: Dictionary) -> void:
	if data.has("up"):
		_gen_reports[squad] = [int(data["up"]), int(data["total"])]
		_count_generators()
	if data.has("dmg"):
		var amount := ceili(int(data["dmg"]) * damage_taken_fraction())
		crystal_hp = maxi(crystal_hp - amount, 0)


func _count_generators() -> void:
	var up := 0
	var total := 0
	var present := present_squads()
	for squad in _gen_reports:
		if squad in present:
			up += _gen_reports[squad][0]
			total += _gen_reports[squad][1]
	generators_up = up
	generators_total = total


func outcome() -> int:
	if crystal_hp <= 0:
		fail_reason = "The crystal was destroyed"
		return Outcome.FAILED
	return Outcome.RUNNING


func uses_wave_clock() -> bool:
	return true


func host_state() -> Dictionary:
	return {"hp": crystal_hp, "up": generators_up, "total": generators_total}


func apply_state(state: Dictionary) -> void:
	crystal_hp = int(state.get("hp", crystal_hp))
	generators_up = int(state.get("up", generators_up))
	generators_total = int(state.get("total", generators_total))


func status_text() -> String:
	var pct := roundi(100.0 * crystal_hp / maxf(crystal_max, 1.0))
	return "Crystal %d%%   Shields %d/%d" % [pct, generators_up, generators_total]


func markers() -> Array:
	var list := [[crystal.position, info["color"]]]
	var engineer := living_players().any(func(p: Node) -> bool: return p.class_id == REPAIR_CLASS)
	for gen in _generators:
		# An engineer gets pointed at broken ones too, to rebuild them.
		if not gen.is_dead() or engineer:
			list.append([gen.position, Color(0.6, 0.9, 1.0)])
	return list


func _draw() -> void:
	# A beam from each standing generator of ours to the crystal.
	for gen in _generators:
		if gen.is_dead():
			continue
		var c := Color(0.55, 0.9, 1.0, 0.25 + 0.1 * sin(Time.get_ticks_msec() / 150.0))
		draw_dashed_line(gen.position, crystal.position, c, 1.0, 8.0)
	# Repairs: how far along a rebuild is, and sparks while one's going on.
	for gen in _generators:
		if _rebuild.has(gen):
			draw_progress_ring(gen.position, gen.radius + 7.0,
				_rebuild[gen] / (gen.max_hp * REBUILD_AT), Color(1.0, 0.85, 0.3), 2.0)
		if _repairing.has(gen):
			for i in 4:
				var a := _age * 9.0 + i * TAU / 4.0
				var p := gen.position + Vector2.RIGHT.rotated(a) * (gen.radius * 0.6 + fmod(_age * 28.0 + i * 3.4, 10.0))
				draw_circle(p, 1.0, Color(1.0, 0.9, 0.4))
			draw_string_outline(ThemeDB.fallback_font, gen.position + Vector2(-30, -gen.radius - 6),
				"REBUILDING" if gen.is_dead() else "REPAIRING", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, 2,
				Color.BLACK)
			draw_string(ThemeDB.fallback_font, gen.position + Vector2(-30, -gen.radius - 6),
				"REBUILDING" if gen.is_dead() else "REPAIRING", HORIZONTAL_ALIGNMENT_CENTER, 60, 8,
				Color(1.0, 0.9, 0.4))
