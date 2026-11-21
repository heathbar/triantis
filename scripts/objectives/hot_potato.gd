extends Objective
## Hot Potato: a potato with a lit fuse appears on the map. Walk over it to
## pick it up and carry it to the pit; B (Q on the keyboard) drops it. While
## carrying it a player is slow and can't shoot, swing or use equipment.
##
## The potato heats up in your hands: hold it for HEAT_MAX seconds straight
## and it burns you (half a heart) and you drop it. Your heat cools while
## you're not holding it, so the quick way across the map is to pass it
## between teammates (drop it, they pick it up).
##
## Its fuse never stops. Deliver it to the pit and a new one appears; let
## the fuse run out and it explodes (hurting everyone and everything close
## by), costs a strike, and a new one appears. Deliver enough potatoes to win
## the wave; run out of strikes and it's lost.
##
## Time limit: deliver them all before the wave clock runs out, or the wave
## is failed (so there's no stalling to farm enemies): TIME_PER_DELIVERY for
## each potato a squad has to deliver, plus TIME_BASE. The clock is the
## wave's; each potato's fuse is shown on it.
##
## Squads game: every squad has its own potato on its own map, and the pit is
## in the middle, which every map shares. Deliveries count for everyone, but
## strikes are each squad's own: a squad that runs out of them has failed and
## is out for the rest of the wave (the deliveries still needed drop to match).
## Only if every squad fails is the wave lost. The host keeps the tally.

const PIT_RADIUS := 34.0
const PICKUP_RADIUS := 19.0
const FUSE_TIME := 45.0
const HEAT_MAX := 5.0
## Heat lost per second while not carrying.
const COOL_RATE := 1.0
## Seconds before a player who dropped the potato can pick it up again.
const REPICK_DELAY := 0.8
const RESPAWN_DELAY := 1.5
const SPAWN_MIN_DISTANCE := 360.0
## A squad with only one player can't pass the potato, so its potatoes
## appear this close to the pit instead: near enough to carry in one go
## (carrying, a player covers ~275 px a second, and it burns after HEAT_MAX
## seconds).
const LONE_SPAWN_MIN := 300.0
const LONE_SPAWN_MAX := 400.0
const BLAST_RADIUS := 76.0
## Half hearts the blast costs a player in it.
const BLAST_DAMAGE := 2
const BLAST_ENEMY_DAMAGE := 60
const BURN_DAMAGE := 1
const DELIVERIES_SOLO := 3
const DELIVERIES_PER_SQUAD := 2
## Strikes a squad (or a local game) can take before it fails.
const STRIKES := 3
const TIME_PER_DELIVERY := 30.0
const TIME_BASE := 15.0
const Blast := preload("res://scripts/equipment/blast.gd")

var pit := Vector2.ZERO
## Deliveries by every squad together, and strikes per squad (squad ->
## count) (host's count).
var delivered := 0
var strikes := {}
## Seconds the squads have, from the start of the wave. (Squads work in
## parallel, so it's set by what each squad has to deliver.)
var time_limit := 120.0

## Our potato: where it is, who's carrying it (or null), fuse seconds left.
var _active := false
var _at := Vector2.ZERO
var _carrier: Node = null
var _fuse := FUSE_TIME
var _respawn := 0.0
## player -> heat (seconds held), and player -> seconds before they can
## pick it up again.
var _heat := {}
var _no_pickup := {}
var _age := 0.0
## A message flashed under the timer for a moment.
var _flash_text := ""
var _flash_left := 0.0
## Draws the potato and heat bars over the players and enemies (the
## objective itself draws under them).
var _top: Node2D


func begin() -> void:
	_top = Node2D.new()
	_top.z_index = 30
	_top.z_as_relative = false
	_top.draw.connect(_draw_top)
	add_child(_top)
	pit = shared_centre()
	var each := DELIVERIES_PER_SQUAD if squads_game else DELIVERIES_SOLO
	time_limit = each * TIME_PER_DELIVERY + TIME_BASE
	_spawn_potato()


## Deliveries needed to win, for the squads still in.
func needed() -> int:
	return DELIVERIES_PER_SQUAD * squads_still_in().size() if squads_game else DELIVERIES_SOLO


func _spawn_potato() -> void:
	if game.all_players.size() == 1:
		_at = _point_near_pit()
	else:
		_at = random_point(own_area(), [pit], SPAWN_MIN_DISTANCE)
	_fuse = FUSE_TIME
	_carrier = null
	_active = true


## A point on our map LONE_SPAWN_MIN..LONE_SPAWN_MAX from the pit. (In a
## squads game it can be in a strip another squad's map shares; only our
## players see our potato anyway.)
func _point_near_pit() -> Vector2:
	var area := map_rect().grow(-EDGE_INSET)
	var at := pit
	for i in 24:
		at = pit + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(LONE_SPAWN_MIN, LONE_SPAWN_MAX)
		if area.has_point(at):
			return at
	return at.clamp(area.position, area.end)


func tick(delta: float) -> void:
	_age += delta
	_top.queue_redraw()
	_flash_left = maxf(_flash_left - delta, 0.0)
	for player in game.all_players:
		var carrying: bool = _carrier == player
		_heat[player] = maxf(_heat.get(player, 0.0) + (delta if carrying else -delta * COOL_RATE), 0.0)
		_no_pickup[player] = maxf(_no_pickup.get(player, 0.0) - delta, 0.0)

	if failed_squads.has(my_squad):
		_active = false  # We're out: no more potatoes for us this wave.
		return
	if not _active:
		_respawn -= delta
		if _respawn <= 0.0:
			_spawn_potato()
		return

	# A wiped-out squad's potato waits for the next wave instead of costing
	# everyone a strike.
	if not living_players().is_empty():
		_fuse -= delta
	if _carrier != null:
		if not is_instance_valid(_carrier) or _carrier.is_dead():
			_drop()
		else:
			_at = _carrier.global_position + Vector2(0, -19)
			if _heat.get(_carrier, 0.0) >= HEAT_MAX:
				var burned: Node = _carrier
				_drop()
				burned.take_hit(BURN_DAMAGE, burned.global_position)
				_flash("Too hot! Pass it on")
	else:
		_try_pickup()

	if _at.distance_to(pit) <= PIT_RADIUS:
		_deliver()
	elif _fuse <= 0.0:
		_explode()


func _try_pickup() -> void:
	for player in living_players():
		if player.is_carrying() or _no_pickup.get(player, 0.0) > 0.0:
			continue
		if _heat.get(player, 0.0) >= HEAT_MAX * 0.9:
			continue  # Still too hot to hold.
		if player.global_position.distance_to(_at) <= PICKUP_RADIUS:
			_carrier = player
			player.carrying = self
			return


## The carrier pressed B (scripts/player/character_body.gd).
func player_dropped(player: Node) -> void:
	if player == _carrier:
		_drop()


func _drop() -> void:
	if _carrier != null and is_instance_valid(_carrier):
		if _carrier.carrying == self:
			_carrier.carrying = null
		_no_pickup[_carrier] = REPICK_DELAY
		_at = _carrier.global_position + Vector2(0, 8)
	_carrier = null


func _deliver() -> void:
	_drop()
	_active = false
	_respawn = RESPAWN_DELAY
	_flash("Delivered!")
	report({"delivered": 1})


func _explode() -> void:
	var center := _at
	_drop()
	_active = false
	_respawn = RESPAWN_DELAY
	_flash("BOOM! Strike!")
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("is_mirror") or enemy.is_in_group("objective_structures") \
				or not enemy.has_method("take_damage") or enemy.is_dead():
			continue
		if center.distance_to(enemy.global_position) <= BLAST_RADIUS:
			enemy.take_damage(BLAST_ENEMY_DAMAGE, null,
				center.direction_to(enemy.global_position) * 40.0)
	for player in living_players():
		if center.distance_to(player.global_position) <= BLAST_RADIUS:
			player.hurt_by(BLAST_DAMAGE, center)
	var blast := Blast.new()
	blast.radius = BLAST_RADIUS
	blast.position = center  # before add_child
	game.add_child(blast)
	report({"boom": 1})


func _flash(text: String) -> void:
	_flash_text = text
	_flash_left = 2.0


func host_receive(squad: int, data: Dictionary) -> void:
	delivered += int(data.get("delivered", 0))
	if data.has("boom"):
		strikes[squad] = strikes.get(squad, 0) + int(data["boom"])
		if strikes[squad] >= STRIKES:
			fail_squad(squad, "Too many potatoes blew up")


func outcome() -> int:
	if squads_still_in().is_empty():
		fail_reason = "Too many potatoes blew up"
		return Outcome.FAILED
	if delivered >= needed():
		return Outcome.SUCCESS
	# (Another squad's copy only asks once the host has said it failed; its
	# clock may be a touch behind the host's.)
	if elapsed >= time_limit or not is_authority:
		fail_reason = "Time ran out before the potatoes were delivered"
		return Outcome.FAILED
	return Outcome.RUNNING


func host_state() -> Dictionary:
	return {"d": delivered, "s": strikes}


func apply_state(state: Dictionary) -> void:
	delivered = int(state.get("d", delivered))
	strikes = state.get("s", strikes)


func display_time(wave_elapsed: float) -> float:
	return maxf(time_limit - wave_elapsed, 0.0)


func status_text() -> String:
	var line := "Delivered %d/%d   Strikes %d/%d" % [delivered, needed(), strikes.get(my_squad, 0), STRIKES]
	if _active:
		line = "Fuse %d   " % ceili(maxf(_fuse, 0.0)) + line
	if _flash_left > 0.0:
		line = _flash_text + "   " + line
	return line


func markers() -> Array:
	var list := [[pit, info["color"]]]
	if _active and _carrier == null:
		list.append([_at, Color(0.75, 0.5, 0.25)])
	return list


func _exit_tree() -> void:
	# The wave ended: nobody's carrying anything any more.
	if _carrier != null and is_instance_valid(_carrier) and _carrier.carrying == self:
		_carrier.carrying = null
	_carrier = null


func _draw() -> void:
	var c: Color = info["color"]
	# The pit.
	draw_circle(pit, PIT_RADIUS + 4.0, Color(0, 0, 0, 0.35))
	draw_circle(pit, PIT_RADIUS, Color(0.12, 0.06, 0.03))
	for i in 3:
		var a := _age * 1.5 + i * TAU / 3.0
		draw_arc(pit, PIT_RADIUS * (0.4 + 0.2 * i), a, a + 2.0, 24, Color(c, 0.5), 2.0)
	draw_arc(pit, PIT_RADIUS, 0.0, TAU, 64, c, 2.0)


func _draw_top() -> void:
	var canvas := _top
	# Heat bars over anyone warm.
	for player in game.all_players:
		var heat: float = _heat.get(player, 0.0)
		if heat <= 0.05 or player.is_dead():
			continue
		var frac := clampf(heat / HEAT_MAX, 0.0, 1.0)
		var top: Vector2 = player.global_position + Vector2(-12, -35)
		canvas.draw_rect(Rect2(top - Vector2(1, 1), Vector2(26, 5)), Color.BLACK)
		canvas.draw_rect(Rect2(top, Vector2(24 * frac, 3)), Color(1.0, 0.8, 0.2).lerp(Color(1, 0.15, 0.1), frac))

	if not _active:
		return
	# The potato, shaking harder as its fuse runs down.
	var urgency := 1.0 - clampf(_fuse / FUSE_TIME, 0.0, 1.0)
	var shake := Vector2(sin(_age * 40.0), cos(_age * 37.0)) * urgency * 1.2
	var at := _at + shake
	var body := Color(0.62, 0.42, 0.22)
	if _fuse < 10.0 and fmod(_age, 0.4) < 0.2:
		body = Color(1, 0.35, 0.2)
	canvas.draw_set_transform(at, 0.0, Vector2(1.25, 1.0))
	canvas.draw_circle(Vector2.ZERO, 10.0, Color.BLACK)
	canvas.draw_circle(Vector2.ZERO, 8.0, body)
	canvas.draw_set_transform(Vector2.ZERO)
	for spot: Vector2 in [Vector2(-4, -2), Vector2(2, 2), Vector2(4, -3)]:
		canvas.draw_circle(at + spot, 1.0, body.darkened(0.4))
	# Fuse and spark.
	var fuse_end := at + Vector2(6, -12)
	canvas.draw_line(at + Vector2(4, -7), fuse_end, Color(0.2, 0.2, 0.2), 1.0)
	canvas.draw_circle(fuse_end, 1.8 + sin(_age * 30.0) * 0.6, Color(1, 0.85, 0.3))
	var font := ThemeDB.fallback_font
	canvas.draw_string_outline(font, at + Vector2(-16, -20), str(ceili(_fuse)), HORIZONTAL_ALIGNMENT_CENTER,
		32, 9, 2, Color.BLACK)
	canvas.draw_string(font, at + Vector2(-16, -20), str(ceili(_fuse)), HORIZONTAL_ALIGNMENT_CENTER,
		32, 9, Color(1, 0.9, 0.5))
