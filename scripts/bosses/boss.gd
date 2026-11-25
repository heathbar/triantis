class_name Boss
extends Objective
## Base for a boss fight. A boss wave (WaveDefinition.boss_id set) has one of
## these instead of an objective; game.gd makes it at the start of the wave
## and hands it to the wave director like an objective, so it reuses the
## objective plumbing: the wave lasts until outcome() says the boss is dead,
## the clock counts up, regular enemies keep trickling in from the wave's
## enemy groups (the director loops the schedule), and in a squads game the
## same report / state messages carry the fight between squads.
##
## Squads game: the host owns the boss. Every squad has its own copy of it,
## in the middle of the area all four maps share (shared_centre). A squad's
## copy collects the damage its players do (on_body_hit) and reports it to
## the host every REPORT_INTERVAL; the host applies it and sends everyone
## the boss's state. A boss's attacks are *hazards* (emit_hazard): the host
## decides them and sends them with its state, and every squad's copy plays
## them out and hurts only its own players. In a local game the one copy
## does all of this itself.
##
## Health: the wave's boss_health, plus HEALTH_PER_EXTRA_PLAYER of it for
## every player beyond the first, counting every squad's players. A boss
## enrages after enrage_at seconds: its attacks get faster and harder, so a
## fight can't drag on forever.
##
## Subclasses override boss_begin, boss_tick, hit_multiplier, apply_damage,
## boss_report, boss_receive, boss_state, apply_boss_state, hazard_tick,
## draw_hazard, bar_segments and markers, and have a static paint_preview
## for the intro (scripts/bosses/boss_intro.gd).

const BossBody := preload("res://scripts/bosses/boss_body.gd")

## Every boss. "epithet" is the line under its name in the intro.
const BOSSES := {
	"lighthouse": {"id": "lighthouse", "name": "The Lighthouse",
		"epithet": "It never looks away first", "color": Color(1.0, 0.82, 0.3),
		"script": "res://scripts/bosses/lighthouse.gd",
		"summary": "Its back is the weak spot. It turns on whoever hurts it most."},
	"fruit_bowl": {"id": "fruit_bowl", "name": "The Fruit Bowl",
		"epithet": "Part of a balanced diet", "color": Color(0.36, 0.52, 0.95),
		"script": "res://scripts/bosses/fruit_bowl.gd",
		"summary": "Break the bowl, then smash all four fruit."},
	"vault": {"id": "vault", "name": "The Vault",
		"epithet": "Nothing gets in", "color": Color(0.4, 0.95, 0.75),
		"script": "res://scripts/bosses/vault.gd",
		"summary": "Enter the keypad code to drop its shield, then open fire."},
	"crusher": {"id": "crusher", "name": "The Crusher",
		"epithet": "Never touches the brakes", "color": Color(0.8, 0.34, 0.95),
		"script": "res://scripts/bosses/crusher.gd",
		"summary": "Dodge its charges. Make it hit a wall, then let it have it."},
}

## Boss health grows by this much of its base for every player beyond the
## first (every squad's players count).
const HEALTH_PER_EXTRA_PLAYER := 0.85
## Equipment does this much of its usual damage to a boss.
const EQUIPMENT_DAMAGE := 0.4
## Slows work at this fraction of their usual strength on a boss.
const STATUS_STRENGTH := 0.3
## Every player's reward for the kill: KILL_POINTS, plus SPEED_POINTS for
## every second it died before it would have enraged.
const KILL_POINTS := 500
const SPEED_POINTS := 10
## Seconds the boss takes to blow up before the wave ends.
const DEATH_TIME := 1.8
## Roughly half a player's size, for hazards reaching them.
const PLAYER_HALF := 12.0
## A squad's reported player positions are forgotten after this long.
const POSITION_STALE := 1.0

## Seconds into the wave when it enrages (subclasses set it in boss_begin).
var enrage_at := 120.0
## When it was killed (wave seconds), or -1 while it's alive.
var defeated_at := -1.0
## Its bodies (scripts/bosses/boss_body.gd).
var bodies: Array = []
## Hazards in play: id -> {"id", "kind", "pos" (ours), "born", "end", ...}.
var hazards := {}

## Damage our players have done to each body (by part) since the last report.
var _pending := {}
## Host: squad -> whether it still has a player up (a squad we haven't heard
## from counts as up).
var _squad_up := {}
var _next_hazard := 1
## Ids of hazards already played (so a re-sent one isn't played twice).
var _seen_hazards := {}


static func exists(id: String) -> bool:
	return BOSSES.has(id)


static func boss_info(id: String) -> Dictionary:
	return BOSSES.get(id, {})


## A new boss fight for boss `id`, ready for setup().
static func create_boss(id: String) -> Node2D:
	var info_for: Dictionary = BOSSES[id]
	var boss: Node2D = load(info_for["script"]).new()
	boss.info = info_for
	return boss


## Where a boss stands (the middle of the area every squad's map shares, or
## of the map), in `game_node`'s world: the same spot as shared_centre(), for
## before the fight exists (the intro).
static func boss_centre(game_node: Node2D) -> Vector2:
	var bounds: Rect2 = game_node.grass_bounds
	if game_node.link == null:
		return bounds.get_center()
	var stride := bounds.size * (1.0 - Squads.MAP_OVERLAP)
	return game_node.link.shared_to_local(bounds.position + (stride + bounds.size) / 2.0)


## Draws boss `id` as it looks at the start of the fight, centred on
## `canvas`'s origin (the intro's preview).
static func paint_preview_of(id: String, canvas: CanvasItem, age: float) -> void:
	if exists(id):
		load(BOSSES[id]["script"]).paint_preview(canvas, age)


# --- Objective hooks ------------------------------------------------------------

func begin() -> void:
	z_index = -5  # Hazards under the players, over the ground.
	# Physics after the players (default 0), so _keep_players_out sees where
	# they moved this frame.
	process_physics_priority = 10
	boss_begin()


func tick(delta: float) -> void:
	if is_defeated():
		for body in bodies:
			body.dormant = true
	boss_tick(delta)
	_tick_hazards(delta)
	_keep_players_out()


## Players walk through enemies (they only get hurt touching them), but
## standing inside a boss would dodge its rings and beam, so our players are
## pushed back out to its edge: whether they walked in, a Fruit Bowl fruit
## drifted onto them or the boss appeared on top of them. Runs after the
## players have moved (process_physics_priority), so nobody is drawn inside.
func _keep_players_out() -> void:
	for body in bodies:
		if not is_instance_valid(body) or body.dormant:
			continue
		var centre: Vector2 = body.global_position
		# A circle's reach both ways, or an oval body's half width and height.
		var reach: Vector2 = Vector2.ONE * (body.radius + PLAYER_HALF)
		if body.oval != Vector2.ZERO:
			reach = body.oval + Vector2.ONE * PLAYER_HALF
		for player in living_players():
			# Measured with the oval squashed round (reach 1).
			var away: Vector2 = (player.global_position - centre) / reach
			if away.length_squared() >= 1.0:
				continue
			if away.is_zero_approx():
				# Dead centre: out the way they're facing (or right).
				away = Vector2.from_angle(player.body.rotation) if "body" in player else Vector2.RIGHT
			player.global_position = centre + away.normalized() * reach
			# The map edge wins over the boss: it's never far enough in to
			# trap anyone between the two.
			if player is Player:
				player.stay_in_bounds()


func outcome() -> int:
	if is_defeated() and elapsed >= defeated_at + DEATH_TIME:
		return Outcome.SUCCESS
	return Outcome.RUNNING


func uses_wave_clock() -> bool:
	return false


func display_time(wave_elapsed: float) -> float:
	return wave_elapsed


func clock_counts_up() -> bool:
	return true


func periodic_report() -> Dictionary:
	var data := boss_report()
	var dmg := {}
	for part in _pending.keys():
		var whole := floori(_pending[part])
		if whole > 0:
			dmg[part] = whole
			_pending[part] -= whole
	if not dmg.is_empty():
		data["dmg"] = dmg
	data["up"] = not living_players().is_empty()
	return data


func host_receive(squad: int, data: Dictionary) -> void:
	if data.has("up"):
		_squad_up[squad] = bool(data["up"])
	if data.has("dmg") and not is_defeated():
		var dmg: Dictionary = data["dmg"]
		for part in dmg:
			apply_damage(int(part), int(dmg[part]), squad)
	boss_receive(squad, data)


func host_state() -> Dictionary:
	var state := boss_state()
	state["dead"] = defeated_at
	var list := []
	for id in hazards:
		var h: Dictionary = hazards[id].duplicate()
		h["pos"] = to_shared_pos(h["pos"])
		list.append(h)
	state["hz"] = list
	return state


func apply_state(state: Dictionary) -> void:
	defeated_at = float(state.get("dead", defeated_at))
	for h in state.get("hz", []):
		if h is Dictionary and not _seen_hazards.has(int(h["id"])):
			var mine: Dictionary = h.duplicate()
			mine["pos"] = to_local_pos(h["pos"])
			_add_hazard(mine)
	apply_boss_state(state)


func markers() -> Array:
	var list := []
	for body in bodies:
		if not body.dormant:
			list.append([body.global_position, info.get("color", Color.WHITE)])
	return list


# --- For subclasses ---------------------------------------------------------------

func boss_begin() -> void:
	pass


func boss_tick(_delta: float) -> void:
	pass


## How much a hit landing at `at` on `body` counts for (x its damage).
func hit_multiplier(_body: Node, _at: Vector2) -> float:
	return 1.0


## Host: `amount` damage to body `part`, from `squad`'s players.
func apply_damage(_part: int, _amount: int, _squad: int) -> void:
	pass


## Extra things to tell the host every report.
func boss_report() -> Dictionary:
	return {}


## Host: a squad's report arrived (after its damage is applied).
func boss_receive(_squad: int, _data: Dictionary) -> void:
	pass


func boss_state() -> Dictionary:
	return {}


func apply_boss_state(_state: Dictionary) -> void:
	pass


## Every physics frame for each hazard in play (it's removed at its "end").
func hazard_tick(_h: Dictionary, _delta: float) -> void:
	pass


func draw_hazard(_h: Dictionary) -> void:
	pass


## The HUD's boss bar (scripts/ui/boss_bar.gd): one or more health bars,
## [{"label": String, "frac": 0..1, "color": Color, "dim": bool}, ...].
func bar_segments() -> Array:
	return []


## A line under the boss bar ("" for none).
func bar_note() -> String:
	return "ENRAGED" if is_enraged() else ""


## Our player who did a hit on a body: the shooter, or whoever's equipment it
## was. Subclasses hear about every hit through record_hit.
func record_hit(_body: Node, _damage: float, _player: Node) -> void:
	pass


# --- Shared ---------------------------------------------------------------------

func is_defeated() -> bool:
	return defeated_at >= 0.0


func is_enraged() -> bool:
	return elapsed >= enrage_at and not is_defeated()


## Host: the boss is dead.
func defeat() -> void:
	if not is_defeated():
		defeated_at = elapsed


## When it died (or how long the fight has gone on, if it hasn't).
func clear_time() -> float:
	return defeated_at if is_defeated() else elapsed


## Points each player gets for the kill.
func kill_points() -> int:
	return KILL_POINTS + SPEED_POINTS * maxi(floori(enrage_at - clear_time()), 0)


## Every player in the game, across every squad.
func total_players() -> int:
	if not squads_game:
		return game.all_players.size()
	var total := 0
	for id in Squads.roster:
		total += int(Squads.roster[id].get("joined", 0))
	return maxi(total, game.all_players.size())


## Base health scaled for everyone playing.
func scaled_health(base: int) -> int:
	return maxi(roundi(base * (1.0 + HEALTH_PER_EXTRA_PLAYER * maxi(total_players() - 1, 0))), 1)


## The wave's boss health, or `fallback` if it doesn't set one.
func base_health(fallback: int) -> int:
	return wave.boss_health if wave.boss_health > 0 else fallback


## Host: whether `squad` still has a player up.
func squad_up(squad: int) -> bool:
	return _squad_up.get(squad, true)


## A body for this boss at `at`, drawn by `painter` (Callable(body)); a box
## of `box` (along its rotation) instead of a circle if given, or an oval of
## half width and height `oval`.
func add_body(part: int, at: Vector2, radius: float, painter: Callable,
		box := Vector2.ZERO, oval := Vector2.ZERO) -> BossBody:
	var body := BossBody.new()
	body.boss = self
	body.part = part
	body.radius = radius
	body.box_size = box
	body.oval = oval
	body.painter = painter
	body.position = at  # before add_child, so it never appears at the origin
	add_child(body)
	bodies.append(body)
	return body


## A body was hit (BossBody.boss_hit).
func on_body_hit(body: Node, amount: int, source: Node, at: Vector2, from_equipment: bool) -> void:
	if is_defeated():
		return
	var dmg := float(amount) * hit_multiplier(body, at)
	if from_equipment:
		dmg *= EQUIPMENT_DAMAGE
	_pending[body.part] = _pending.get(body.part, 0.0) + dmg
	if is_instance_valid(source) and source in game.all_players:
		record_hit(body, dmg, source)


func on_body_slow(_body: Node, _mult: float, _seconds: float) -> void:
	pass


func on_body_pull(_body: Node, _pull: Vector2) -> void:
	pass


## A slow of `mult` as it works on a boss.
static func boss_slow(mult: float) -> float:
	return lerpf(1.0, mult, STATUS_STRENGTH)


## Identifies a player across squads.
static func player_key(squad: int, slot: int) -> int:
	return squad * 16 + slot


func key_of(player: Node) -> int:
	return player_key(my_squad, player.player_index)


## Hurts each of our players `test` (Callable(position) -> bool) says is
## caught, by `halves` half hearts (armor and the hit cooldown still apply).
func hurt_players(test: Callable, halves: int) -> void:
	for player in living_players():
		if test.call(player.global_position):
			player.hurt_by(halves, player.global_position)


# --- Hazards ----------------------------------------------------------------------

## Host: starts a hazard of `kind` at `at` (our coordinates) lasting until
## `end` (wave seconds), with extra fields in `data`.
func emit_hazard(kind: String, at: Vector2, end: float, data := {}) -> void:
	var h := data.duplicate()
	h["id"] = _next_hazard
	_next_hazard += 1
	h["kind"] = kind
	h["pos"] = at
	h["born"] = elapsed
	h["end"] = end
	_add_hazard(h)


func _add_hazard(h: Dictionary) -> void:
	var id := int(h["id"])
	if _seen_hazards.has(id) or float(h["end"]) <= elapsed:
		return
	_seen_hazards[id] = true
	hazards[id] = h


func _tick_hazards(delta: float) -> void:
	for id in hazards.keys():
		var h: Dictionary = hazards[id]
		if elapsed >= float(h["end"]):
			hazards.erase(id)
			continue
		hazard_tick(h, delta)


func _draw() -> void:
	for id in hazards:
		draw_hazard(hazards[id])


# --- Drawing helpers --------------------------------------------------------------

## Text with a dark outline, centred on `at`.
func draw_label(at: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := 120.0
	var pos := at + Vector2(-width / 2.0, size * 0.35)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 2, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


## A body bursting apart, `t` seconds after it died (on the body's canvas).
static func paint_death(c: CanvasItem, radius: float, t: float, color: Color) -> void:
	var k := clampf(t / DEATH_TIME, 0.0, 1.0)
	for i in 10:
		var a := i * TAU / 10.0 + i * 0.7
		var p := Vector2.from_angle(a) * radius * (0.3 + 2.2 * k)
		c.draw_circle(p, radius * 0.35 * (1.0 - k) + 1.0, Color(color, 1.0 - k))
	c.draw_circle(Vector2.ZERO, radius * (0.6 + k), Color(1, 1, 0.85, 0.8 * (1.0 - k)))
