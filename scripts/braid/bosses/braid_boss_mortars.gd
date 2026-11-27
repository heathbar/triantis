extends RefCounted
## The Tyrants modifier's extra boss mechanic (scripts/braid/braid_modifiers.gd):
## every INTERVAL seconds (ENRAGED_INTERVAL once the boss enrages) mortar
## shells rain on the convergence room. Each marks its spot for WARNING
## seconds (a target ring filling in), then bursts, hurting our players
## within RADIUS. Some shells are aimed at players (where the boss last saw
## them, off by up to AIM_SPREAD), the rest land at random in the room.
##
## The same for every Braid boss: each one's Braid version (braid_crusher.gd
## and the rest) owns one of these while the modifier is on and passes its
## hazards through hazard_tick / draw. Shells are boss hazards
## (Boss.emit_hazard), so in a squads game the host decides them and every
## squad's copy plays them out on its own players.

const KIND := "mortar"
## Seconds into the fight of the first volley, and between volleys.
const FIRST_AT := 5.0
const INTERVAL := 7.0
const ENRAGED_INTERVAL := 4.5
## Shells a volley: BASE_COUNT + one per player in the game, up to MAX_COUNT.
const BASE_COUNT := 2
const MAX_COUNT := 10
## Of those, up to this many are aimed at players.
const MAX_AIMED := 4
const AIM_SPREAD := 16.0
## Seconds a shell's ring shows before it bursts, and the burst's flash.
const WARNING := 1.4
const BLAST := ExplosionArt.DURATION
## Burst radius (world px) and damage (half hearts).
const RADIUS := 22.0
const TargetMarker := preload("res://scripts/target_marker.gd")
const ExplosionArt := preload("res://scripts/explosion_art.gd")
const DAMAGE := 2
const COLOR := Color(1.0, 0.45, 0.2)

var _next := FIRST_AT


## The boss's tick (every boss, host or not: only the host fires).
func tick(boss: Boss) -> void:
	boss.queue_redraw()  # (shells animate, and the last one must be wiped)
	if not boss.is_authority or boss.is_defeated() or boss.elapsed < _next:
		return
	_next = boss.elapsed + (ENRAGED_INTERVAL if boss.is_enraged() else INTERVAL)
	var area: Rect2 = boss.map_rect().grow(-RADIUS)
	var aimed := _targets(boss)
	aimed.shuffle()
	var count := mini(BASE_COUNT + boss.total_players(), MAX_COUNT)
	for i in count:
		var at: Vector2
		if i < mini(aimed.size(), MAX_AIMED):
			at = aimed[i] + Vector2.from_angle(randf() * TAU) * randf() * AIM_SPREAD
		else:
			at = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		at = at.clamp(area.position, area.end)
		boss.emit_hazard(KIND, at, boss.elapsed + WARNING + BLAST, {"boom": boss.elapsed + WARNING})


## Where players are, as far as the boss knows: every squad's (the bosses
## that track them keep `_positions`), else just ours.
func _targets(boss: Boss) -> Array:
	var list := []
	var known: Variant = boss.get("_positions")
	if known is Dictionary and not (known as Dictionary).is_empty():
		for key in known:
			list.append(boss.to_local_pos(known[key][0]))
		return list
	for player in boss.living_players():
		list.append(player.global_position)
	return list


## Plays out hazard `h` if it's a shell (true), else leaves it to the boss.
static func hazard_tick(boss: Boss, h: Dictionary) -> bool:
	if h["kind"] != KIND:
		return false
	if not h.get("hit", false) and boss.elapsed >= float(h["boom"]):
		h["hit"] = true
		var at: Vector2 = h["pos"]
		if ExplosionArt.is_small(RADIUS):
			ExplosionArt.play_small_sound()
		var reach := RADIUS + Boss.PLAYER_HALF * 0.5
		boss.hurt_players(func(p: Vector2) -> bool: return p.distance_squared_to(at) <= reach * reach,
			DAMAGE)
	return true


## Draws hazard `h` if it's a shell (true), else leaves it to the boss.
static func draw(boss: Boss, h: Dictionary) -> bool:
	if h["kind"] != KIND:
		return false
	var at: Vector2 = h["pos"]
	var boom := float(h["boom"])
	if boss.elapsed < boom:
		var k := clampf((boss.elapsed - float(h["born"])) / maxf(boom - float(h["born"]), 0.01), 0.0, 1.0)
		boss.draw_circle(at, RADIUS * k, Color(COLOR, 0.3))
		TargetMarker.draw(boss, at, RADIUS)
	else:
		ExplosionArt.draw(boss, at, boss.elapsed - boom, RADIUS)
	return true
