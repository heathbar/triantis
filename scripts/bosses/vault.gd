extends Boss
## The Vault (boss of wave 20, Campaign act 4): a strongbox in the middle
## of the map with a mortar on its roof, fought in three stages:
##
## 1. The lock (100% -> 75%). A big wall of blocks stands round it, well out
##    from it (shots and equipment can't get through), and players start
##    outside. The lock is a gate in the wall: picking it drops the wall for a
##    burn window.
## 2. The keypad (75% -> 50%). The same, but the gate is a keypad, and the
##    wall drops when someone enters its code. A laser corridor
##    (scripts/bosses/vault_lasers.gd) runs straight out from the keypad, so
##    players can only reach it from the corridor's far end.
## 3. It gets up (50% -> 0%). The door blows off, it grows legs and walks
##    after the nearest player. No wall any more: it fights back with a gun
##    turret, a stomp for anyone too close, shield drones that make it shrug
##    off most damage while they fly, and sweep lasers right across the map.
##
## Burn windows: the wall stays down for BURN_TIME seconds or until it has
## taken WINDOW_CUT of its full health, whichever comes first. Then it's back
## up with a fresh station; once it's at or below the stage's STAGE_MARKS
## mark, on to the next stage (so a window that runs to its full cut always
## ends the stage, one that runs out of time may not).
##
## The wall: a ring of WALL_CELL-wide blocks round a box WALL_FRACTION of the
## map's width and height. Before it stands up (at the start of the fight and
## after every window) its outline flashes on the ground for a few seconds
## (it can't be hurt meanwhile), so players can walk out. Anyone still inside
## when it stands is blasted out over it, landing just outside (away from
## enemies where possible) and unhurtable in the air and just after. Enemies
## inside are crushed.
##
## The lock and keypad: a cell of the wall, with a spot to stand on just
## outside it. In a local game it's on a different side of the wall after
## every window, so players have to go round to find it. In a squads game
## every squad has its own, always on its own side (the side facing its
## corner of the map), at a new spot along it after every window. A player at it sees a ring
## with a needle going round and a gold arc; X (F or Space on the keyboard)
## while the needle is in the arc sets a pin. PINS pins open it, each with a smaller arc and a
## faster needle (PIN_ARCS, PIN_SPEEDS; engineering widens the arcs). A miss
## puts the arc somewhere else and locks out presses for a moment, but keeps
## the pins already set. Stepping off keeps them too.
##
## The keypad: in the lock's place. A player standing on it gets a random
## code of face buttons (1/2/3/4 on the keyboard) and cracks it one press at
## a time. The code is hidden: a row of blank squares above them shows only
## how long it is and how far in they are, so they find each button by trying
## them. A wrong press, moving, shooting or swinging starts their code over.
## Taking a hit doesn't. Codes are CODE_LENGTH long,
## shorter for players with more engineering (ENGINEER_LENGTHS), so an
## engineer is the natural pick.
##
## Opening a window: a local game opens it with one lock or code. In a squads
## game SQUADS_NEEDED squads must each do theirs, with no time limit between
## them (fewer if fewer squads are still up: an overwhelmed squad can't hold
## everyone up). Then the wall drops and every squad can hit it.
##
## The walker: TRANSFORM_TIME to stand up (it can't be hurt meanwhile), then
## it walks after the nearest player (WALK_SPEED) but stops short of them. It
## keeps to the part of the map every squad shares, so everyone can reach it.
## Its turret fires a burst at a player in every squad every BURST_EVERY
## seconds (every FAN_EVERY-th one a fan instead), marked by an aim line for
## BURST_AIM first. Anyone within STOMP_TRIGGER when it can stomp gets a
## stomp: a ring on the ground for STOMP_WIND, then STOMP_DAMAGE. Every
## DRONE_EVERY seconds it tops its DRONES drones back up; while any is flying
## it takes DRONE_ARMOR of the damage. Every squad gets SWEEP_LINES sweep
## lasers at a time, each right across its map (one through one of its
## players): flashing for SWEEP_WARN, then burning for SWEEP_ON, then a new set.
##
## The mortar fires all fight: every VOLLEY_EVERY seconds it lobs a shell at
## a player in each squad (two for a squad of three or more). It never aims
## at players at a lock or keypad, and a shell that would land on one is
## pushed off it. A shell is marked on the ground for SHELL_FLIGHT seconds
## before it lands. Enraged: faster volleys, quicker landings, shorter sweep
## warnings, and a faster, angrier walker.
##
## Squads game: the host runs the wall (when it stands up), the windows, the
## walker, the sweeps and the mortar. Every squad's copy blasts its own
## players out and crushes its own enemies. Squads report a finished lock or keypad (with the window
## count, so a late one doesn't count for the next window), where their
## players and station are and who's at it. Each squad places its own station
## and runs its own corridor, which only its own players see. The drones are
## the host's (their health goes out with the state); every copy flies them
## round its own copy of the walker.

const VaultLasers := preload("res://scripts/bosses/vault_lasers.gd")
## A wrong keypad button, or a missed pin at the lock.
const KEYPAD_BUZZER := preload("res://assets/robot/boss/keypad_buzzer.ogg")
## A laser (corridor or sweep) burning a player.
const FENCE_BUZZER := preload("res://assets/robot/boss/fence_buzzer.ogg")
## A pin set at the lock.
const PICK_CLICK := preload("res://assets/robot/boss/pick_click.ogg")

const RADIUS := 30.0
const DEFAULT_HEALTH := 20000
const ENRAGE_AT := 240.0

## Seconds the wall stays down, and the most of its full health a window can
## take off.
const BURN_TIME := 15.0
const WINDOW_CUT := 0.25
## Each stage ends once it's at or below its mark (fractions of full health):
## the lock's, then the keypad's; then it walks.
const STAGE_MARKS := [0.75, 0.5]
## The phase (stages passed) at which it gets up and walks.
const WALK_PHASE := 2
## Squads game: squads that must do their lock or keypad to open a window.
const SQUADS_NEEDED := 2
const CODE_LENGTH := 5
## [engineering above this, its code length], checked in order.
const ENGINEER_LENGTHS := [[50, 3], [30, 4]]
const BUTTONS := ["A", "B", "X", "Y"]
## A code never has the same button more than this many times in a row.
const CODE_MAX_RUN := 2
## A player whose centre is this close to the lock or keypad is at it.
const KEYPAD_REACH := 14.0
## Seconds a wrong press shows red.
const MISS_FLASH := 0.35

## The lock: pins to set, the needle's speed (radians a second) for each pin,
## and each pin's gold arc (radians).
const PINS := 4
const PIN_SPEEDS := [2.2, 2.6, 3.0, 3.4]
const PIN_ARCS := [1.0, 0.8, 0.60, .40]
## [engineering above this, arc multiplier], checked in order.
const ENGINEER_ARCS := [[50, 1.5], [30, 1.25]]
## Seconds presses are ignored after a missed pin.
const PICK_MISS := 0.4
## A new arc lands at least this far (radians) round from the needle.
const ARC_CLEARANCE := 1.4

## The wall: a ring of cells WALL_CELL across (each 2x2 of the act's
## block-1 tiles, WALL_TILE each) round a box about WALL_FRACTION of the
## map's width and height (whole cells, at least WALL_MIN_CELLS a side),
## which shots stop at and players can't walk into. It sinks or rises in
## WALL_MOVE seconds.
const WALL_CELL := 48.0
const WALL_TILE := 24.0
const WALL_FRACTION := 0.375
const WALL_MIN_CELLS := 5
const WALL_MOVE := 0.35
## How close a player's centre gets to the wall's outside edge.
const WALL_REACH := 8.0
## The sides of the wall, by number: north, east, south, west.
const SIDES := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## Squads game: each squad's side (by squad number; Squads.SQUAD_GRID puts
## them top left, top right, bottom left, bottom right).
const SQUAD_SIDES := [0, 1, 3, 2]
## The lock's and keypad's art (drawn upright on any side), and how far out
## from the wall (from its outside edge) their standing spot's centre is.
const GATE_ART := preload("res://assets/robot/boss/gate.png")
const KEYPAD_ART := preload("res://assets/robot/boss/keypad.png")
const STATION_OUT := 16.0
## Seconds its outline flashes before the wall stands up: at the start of
## the fight, and after every burn window.
const START_WARN := 2.5
const RISE_WARN := 1.5
## Blasted out: seconds in the air, how high (px), how far out from the
## wall's outside edge they land (their centre), and seconds they stay
## unhurtable after landing. Landing spots are scored by how clear of
## enemies they are (up to LAND_CLEAR px), less LAND_WALK of the distance
## from where the player was, tried every LAND_STEP px round the wall.
const TOSS_TIME := 0.7
const TOSS_HEIGHT := 28.0
const TOSS_GRACE := 0.6
const LAND_OUT := 24.0
const LAND_CLEAR := 80.0
const LAND_WALK := 0.25
const LAND_STEP := 24.0
## Seconds the blast's ring spreads for.
const BLAST_RING := 0.4
## Enough damage to crush any enemy.
const CRUSH_DAMAGE := 1000000
const BLOCK_ART := preload("res://assets/meadow/environment/block-1a.png")
const ActTheme := preload("res://scripts/act_theme.gd")
## The wall's outline (as the Campaign's walls have: scripts/braid/braid_block.gd).
const WALL_OUTLINE := Color(0.14, 0.13, 0.16)
const WALL_ROBOT_OUTLINE := Color8(0x26, 0x28, 0x54)

## The walker.
const TRANSFORM_TIME := 2.0
const WALK_SPEED := 22.0
const ENRAGED_WALK_SPEED := 32.0
## It stops this far (centre to centre) from the player it's after.
const WALK_STOP := 56.0
## It keeps this far in from the edge of the shared map.
const ROAM_INSET := 50.0
const STOMP_TRIGGER := 64.0
const STOMP_RADIUS := 72.0
const STOMP_WIND := 0.9
const ENRAGED_STOMP_WIND := 0.7
const STOMP_COOLDOWN := 3.5
const STOMP_DAMAGE := 2
const BURST_EVERY := 2.6
const ENRAGED_BURST_EVERY := 1.8
const BURST_AIM := 0.5
const BURST_SHOTS := 4
const BURST_GAP := 0.15
const FAN_EVERY := 3
const FAN_SHOTS := 7
const FAN_SPREAD := 1.2
const BULLET_SPEED := 120.0
const BULLET_LIFE := 2.8
const BULLET_RADIUS := 2.5
const BULLET_DAMAGE := 1
const DRONES := 3
const DRONE_EVERY := 18.0
## Each drone's health, as a fraction of the Vault's full health.
const DRONE_HP_FRAC := 0.025
const DRONE_ARMOR := 0.25
const DRONE_ORBIT := 48.0
const DRONE_SPIN := 1.3
const DRONE_RADIUS := 7.0
## Seconds a new drone takes to fly out to its orbit.
const DRONE_LAUNCH := 0.5
## Boss body part numbers for the drones (DRONE_PART + n).
const DRONE_PART := 10
## Sweep lasers: lines per squad, seconds of warning (flashing) and burning,
## and the pause before the next set.
const SWEEP_LINES := 3
const SWEEP_WARN := 2.0
const ENRAGED_SWEEP_WARN := 1.5
const SWEEP_ON := 3.0
const SWEEP_PAUSE := 0.4
## The directions they run in (radians): horizontal, vertical, both diagonals.
const SWEEP_ANGLES := [0.0, PI / 2.0, PI / 4.0, -PI / 4.0]
## Lines not through a player cross a point at least this far in from the
## squad's map edge.
const SWEEP_INSET := 40.0

const FIRST_VOLLEY := 3.0
const VOLLEY_EVERY := 3.2
const ENRAGED_VOLLEY := 2.0
const SHELL_RADIUS := 24.0
const TargetMarker := preload("res://scripts/target_marker.gd")
const ExplosionArt := preload("res://scripts/explosion_art.gd")
const SHELL_FLIGHT := 1.6
const ENRAGED_SHELL_FLIGHT := 1.2
const SHELL_DAMAGE := 2
const SHELL_LINGER := ExplosionArt.DURATION
## Shells land up to this far off their target.
const SHELL_SCATTER := 10.0

const STEEL := Color(0.36, 0.4, 0.44)
const STEEL_DARK := Color(0.16, 0.18, 0.2)
const BRASS := Color(0.85, 0.7, 0.35)
const SHIELD := Color(0.45, 0.85, 1.0)
const DONE := Color(0.45, 0.95, 0.45)
const MISS := Color(1.0, 0.3, 0.25)
const CORE := Color(1.0, 0.45, 0.2)
const BULLET := Color(1.0, 0.55, 0.2)
## The input action for each code button (see character_body.gd), whose key
## the keyboard player's keycap shows, and the colours the keycaps are drawn in.
const CODE_ACTIONS := {"A": &"code_a", "B": &"code_b", "X": &"code_x", "Y": &"code_y"}
## The lock's one button: X, F or Space (Global).
const PICK_ACTION := &"pick_lock"
## Controller button art (white, so drawn on a dark disc). Preloaded: loaded
## mid-draw they came out as blank white squares.
const BUTTON_ICONS := {
	"A": preload("res://assets/ui/controls/A.svg"),
	"B": preload("res://assets/ui/controls/B.svg"),
	"X": preload("res://assets/ui/controls/X.svg"),
	"Y": preload("res://assets/ui/controls/Y.svg"),
}
const BUTTON_COLORS := {"A": Color(0.4, 0.85, 0.35), "B": Color(0.95, 0.35, 0.3),
	"X": Color(0.35, 0.6, 1.0), "Y": Color(1.0, 0.85, 0.3)}

var body: BossBody
var hp := 1
var max_hp := 1
## Stages passed: 0 the lock, 1 the keypad, WALK_PHASE walking.
var phase := 0
## Burn windows closed so far (a new station goes down after each).
var windows := 0
## Wave seconds when the current burn window ends, or -1 while shielded.
var open_until := -1.0
## Wave seconds when the wall stands up (its outline flashes until then).
var rise_at := 0.0
## The wall's size in cells, and from its centre to its outside edge.
var wall_cells := Vector2i(WALL_MIN_CELLS, WALL_MIN_CELLS)
var wall_half := Vector2.ONE * WALL_MIN_CELLS * WALL_CELL / 2.0
## Our lock or keypad: the side of the wall it's on (SIDES) and which cell
## along that side (from 0, leaving out the corners).
var station_side := -1
var station_index := -1
## Squads that have done this window's keypad or lock (the host's list).
var done_squads: Array = []
## Codes needed to open the window (the host's count).
var need := 1
## Walking: when it's done standing up (wave seconds), or -1 before then.
var walk_from := -1.0
## The drones' health (0 = down), their full health, and when they last launched.
var drone_hp: Array = []
var drone_max := 1
var drones_at := -INF

## Our lock or keypad, and the window count it was placed for.
var keypad_pos := Vector2.ZERO
var _keypad_for := -1
## Our squad has done this window's keypad or lock (before the host says so).
var _local_done := false
## Our players at the keypad: player -> {"code": [buttons], "at": presses
## done, "miss": seconds of red left}.
var _codes := {}
## Our players at the lock: player -> {"pin": pins set, "arc": arc centre,
## "needle": angle, "miss": seconds presses are locked out}.
var _picks := {}
## Codes (or pins set) our players had this window, kept for when they step
## back onto the station: player -> [buttons] or int.
var _kept := {}
var lasers: VaultLasers
var _drone_bodies: Array[BossBody] = []
## Seconds of walking done (for the legs).
var _walked := 0.0
## Which way it's heading (for the legs and the turret).
var _heading := Vector2.DOWN
## Our copy of the burst bullets that have hit someone: hazard id -> [bools].
var _spent := {}
## Our sweep lasers' lines across our map: hazard id -> [from, to].
var _lines := {}
## How far up the wall is (0 sunk .. 1 up), as drawn; and which collision
## shape the body has now (true: the wall's square).
var _wall := 0.0
var _wall_shape := false
## When it last blasted players out (wave seconds).
var _blast_at := -INF

## Host: player key -> [shared position, when heard, at a station].
var _positions := {}
## Host: squad -> its station (shared position), so shells keep off it.
var _pads := {}
var _next_volley := FIRST_VOLLEY
## Host: the least health the current window can leave it on, and when the
## last window closed.
var _floor_hp := 0
var _closed_at := -INF
## Host: the walker's timers.
var _next_burst := 0.0
var _bursts := 0
var _next_stomp := 0.0
var _stomp_until := -1.0
var _next_drones := 0.0
var _next_sweep := 0.0
## Joiner: the walker's position as the host last said (shared), and when.
var _host_walk := Vector2.ZERO
var _host_walk_at := -1.0

var _ui: CanvasLayer
var _ui_canvas: Control


func boss_begin() -> void:
	enrage_at = ENRAGE_AT
	max_hp = scaled_health(base_health(DEFAULT_HEALTH))
	hp = max_hp
	drone_max = maxi(roundi(max_hp * DRONE_HP_FRAC), 1)
	drone_hp = []
	drone_hp.resize(DRONES)
	drone_hp.fill(0)
	body = add_body(0, shared_centre(), RADIUS, _paint)
	wall_cells = wall_cells_for(map_rect())
	wall_half = Vector2(wall_cells) * WALL_CELL / 2.0
	rise_at = elapsed + START_WARN
	lasers = VaultLasers.new(self)
	need = _codes_needed()
	_place_station()
	for player in game.all_players:
		player.shot_fired.connect(_on_player_shot.bind(player))
		player.melee_swung.connect(_interrupt.bind(player))
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui_canvas = Control.new()
	_ui_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The button icons are big SVGs drawn small: smooth, not nearest.
	_ui_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ui_canvas.draw.connect(_draw_ui)
	_ui.add_child(_ui_canvas)
	add_child(_ui)


## The players' signals disconnect themselves when this is freed.
func _exit_tree() -> void:
	for player in game.all_players:
		if is_instance_valid(player) and player.keypad == self:
			player.keypad = null
	if lasers:
		lasers.clear()


## 0 the lock, 1 the keypad, 2 walking.
func stage() -> int:
	return mini(phase, WALK_PHASE)


func is_shielded() -> bool:
	return phase < WALK_PHASE and open_until < 0.0 and not is_defeated()


func is_open() -> bool:
	return open_until >= 0.0 and not is_defeated()


## The wall's standing (shielded, and done warning that it's coming).
func wall_up() -> bool:
	return is_shielded() and elapsed >= rise_at


## The wall's outline is flashing: it's about to stand up.
func wall_rising() -> bool:
	return is_shielded() and elapsed < rise_at


func is_walking() -> bool:
	return phase >= WALK_PHASE and not is_defeated()


## Still getting up (it can't be hurt yet).
func is_standing_up() -> bool:
	return is_walking() and (walk_from < 0.0 or elapsed < walk_from)


func drones_up() -> bool:
	return drone_hp.any(func(h: Variant) -> bool: return int(h) > 0)


## Our squad has done this window's keypad or lock.
func our_code_done() -> bool:
	return _local_done or done_squads.has(my_squad)


## Health at stage `index`'s mark (STAGE_MARKS).
func mark_hp(index: int) -> int:
	return roundi(max_hp * float(STAGE_MARKS[index]))


## The least health a window opened at `from_hp` can leave it on.
func window_floor(from_hp: int) -> int:
	return maxi(from_hp - roundi(max_hp * WINDOW_CUT), 0)


# --- Every frame --------------------------------------------------------------------

func boss_tick(delta: float) -> void:
	var before := body.global_position
	if is_authority:
		_host_think(delta)
	elif is_walking():
		_follow_host(delta)
	if _keypad_for != windows:
		_place_station()
	match stage():
		0:
			_tick_lock(delta)
		1:
			_tick_keypad(delta)
		_:
			_release_players()
	lasers.set_active(stage() == 1 and wall_up() and not our_code_done())
	lasers.tick()
	_update_wall(delta)
	if is_walking():
		_walked += before.distance_to(body.global_position)
		if before.distance_squared_to(body.global_position) > 0.0001:
			_heading = before.direction_to(body.global_position)
	_update_drones()
	for cache: Dictionary in [_spent, _lines]:
		for id in cache.keys():
			if not hazards.has(id):
				cache.erase(id)
	_ui_canvas.queue_redraw()
	queue_redraw()


## The wall sinks or rises (as drawn), and the body swaps between the
## wall's box (shots stop at it, and it doesn't hurt to touch) and its own
## circle. As it stands up, anyone inside is blasted out; while it's up,
## enemies inside are crushed.
func _update_wall(delta: float) -> void:
	var up := wall_up()
	_wall = move_toward(_wall, 1.0 if up else 0.0, delta / WALL_MOVE)
	if up == _wall_shape:
		if up:
			_crush_enemies()
		return
	_wall_shape = up
	var holder := body.get_node("CollisionShape2D") as CollisionShape2D
	if up:
		var box := RectangleShape2D.new()
		box.size = wall_half * 2.0
		holder.set_deferred("shape", box)
		_blast_out()
	else:
		var circle := CircleShape2D.new()
		circle.radius = RADIUS * 0.9
		holder.set_deferred("shape", circle)
	body.contact_damage = 0 if up else 2


## While the wall's up, our players are kept out of its box (not just the
## Vault's circle): pushed out through the nearest side if they're at its
## edge, blasted out if they're somehow deep inside (revived in there, say).
## Players in the air are left to land.
func _keep_players_out() -> void:
	if not _wall_shape:
		super()
		return
	var centre := body.global_position
	var reach := wall_half + Vector2.ONE * WALL_REACH
	for player in living_players():
		if _in_air(player):
			continue
		var away: Vector2 = player.global_position - centre
		var depth := reach - away.abs()
		if depth.x <= 0.0 or depth.y <= 0.0:
			continue
		if minf(depth.x, depth.y) > PLAYER_HALF * 2.0 and player.has_method("toss"):
			player.toss(_landing_spot(player.global_position, []), TOSS_TIME, TOSS_HEIGHT,
				TOSS_GRACE)
			continue
		# Out through whichever side is nearest.
		if depth.x < depth.y:
			away.x = (1.0 if away.x >= 0.0 else -1.0) * reach.x
		else:
			away.y = (1.0 if away.y >= 0.0 else -1.0) * reach.y
		player.global_position = centre + away
		if player is Player:
			player.stay_in_bounds()


static func _in_air(player: Node) -> bool:
	return player.has_method("is_tossed") and player.is_tossed()


## The wall's just stood up: our players inside it are thrown out over it,
## each to a spot just outside (see _landing_spot), and enemies inside are
## crushed.
func _blast_out() -> void:
	_blast_at = elapsed
	var inside := Rect2(body.global_position - wall_half, wall_half * 2.0).grow(WALL_REACH)
	var taken := []
	for player in living_players():
		if _in_air(player) or not player.has_method("toss") \
				or not inside.has_point(player.global_position):
			continue
		var spot := _landing_spot(player.global_position, taken)
		taken.append(spot)
		player.toss(spot, TOSS_TIME, TOSS_HEIGHT, TOSS_GRACE)
	ExplosionArt.play_small_sound()
	_crush_enemies()


## Where a player at `from` (inside the wall) lands when blasted out: a spot
## LAND_OUT outside the wall, on our map, off the keypad's laser corridor and
## not on top of anyone else landing (`taken`), as clear of enemies as it can
## be without going too far round.
func _landing_spot(from: Vector2, taken: Array) -> Vector2:
	var centre := body.global_position
	var out := wall_half + Vector2.ONE * (WALL_REACH + LAND_OUT)
	var area := map_rect().grow(-PLAYER_HALF - 2.0)
	var foes := _enemy_spots()
	var best := Vector2.INF
	var best_score := -INF
	for side in SIDES.size():
		var normal: Vector2 = SIDES[side]
		var span := out.x if side % 2 == 0 else out.y
		var steps := maxi(ceili(span * 2.0 / LAND_STEP), 1)
		for k in steps + 1:
			var along := -span + span * 2.0 * k / steps
			var p := centre + (Vector2(along, normal.y * out.y) if side % 2 == 0 \
				else Vector2(normal.x * out.x, along))
			if not area.has_point(p) or _near_corridor(p):
				continue
			var clear := LAND_CLEAR
			for foe: Vector2 in foes:
				clear = minf(clear, foe.distance_to(p))
			var score := clear - from.distance_to(p) * LAND_WALK
			for spot: Vector2 in taken:
				if spot.distance_to(p) < PLAYER_HALF * 2.0:
					score -= LAND_CLEAR
			if score > best_score:
				best_score = score
				best = p
	if best == Vector2.INF:
		# Nowhere round it on our map: straight out the nearest side.
		var away := from - centre
		if out.x - absf(away.x) < out.y - absf(away.y):
			away.x = (1.0 if away.x >= 0.0 else -1.0) * out.x
		else:
			away.y = (1.0 if away.y >= 0.0 else -1.0) * out.y
		best = centre + away
	return best


## Whether a player at `p` would touch the keypad's laser corridor.
func _near_corridor(p: Vector2) -> bool:
	for beam: Array in lasers.beams:
		if Geometry2D.get_closest_point_to_segment(p, beam[0], beam[1]).distance_to(p) \
				<= VaultLasers.TOUCH + PLAYER_HALF:
			return true
	return false


## Where the enemies are (mirrors of other squads' too: they still hurt).
func _enemy_spots() -> Array:
	var spots := []
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not enemy is BossBody and not enemy.is_in_group("objective_structures"):
			spots.append(enemy.global_position)
	return spots


## Our enemies inside the wall's box are crushed (other squads' mirrors are
## left to their own copies).
func _crush_enemies() -> void:
	var inside := Rect2(body.global_position - wall_half, wall_half * 2.0)
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		if enemy is BossBody or enemy.get("is_mirror") or enemy.is_queued_for_deletion() \
				or enemy.is_in_group("objective_structures") or not enemy.has_method("take_damage"):
			continue
		if inside.has_point(enemy.global_position):
			enemy.take_damage(CRUSH_DAMAGE, null)


## No station any more: nobody's face buttons go to it.
func _release_players() -> void:
	for player in game.all_players:
		if is_instance_valid(player) and player.keypad == self:
			player.keypad = null
	_codes.clear()
	_picks.clear()


## A new lock or keypad for the next window, and a clean slate for its code
## or pins: a cell of the wall on our squad's side (squads game) or on
## another side than last time (local game), with its standing spot on our
## map.
func _place_station() -> void:
	var sides := [0, 1, 2, 3]
	var ours := _squad_side()
	if ours >= 0:
		sides = [ours]
	elif station_side >= 0:
		sides.erase(station_side)
	var reach := map_rect().grow(-PLAYER_HALF - WALL_REACH)
	var options := []
	for side: int in sides:
		for i in side_length(wall_cells, side):
			if (side != station_side or i != station_index) \
					and reach.has_point(stand_spot(side, i)):
				options.append(Vector2i(side, i))
	if options.is_empty():
		# (A map too small for the wall: anywhere along it.)
		for side in SIDES.size():
			for i in side_length(wall_cells, side):
				options.append(Vector2i(side, i))
	var pick: Vector2i = options.pick_random()
	station_side = pick.x
	station_index = pick.y
	keypad_pos = stand_spot(station_side, station_index)
	_keypad_for = windows
	_local_done = false
	_codes.clear()
	_picks.clear()
	_kept.clear()
	lasers.clear()
	if stage() == 1:
		lasers.build(keypad_pos, SIDES[station_side], map_rect(), STATION_OUT)


## The side our squad's station is always on in a squads game (SIDES), or
## -1 for any side (a local game).
func _squad_side() -> int:
	if not squads_game:
		return -1
	return SQUAD_SIDES[my_squad]


## The standing spot for the station in cell `index` along side `side`.
func stand_spot(side: int, index: int) -> Vector2:
	return shared_centre() + side_cell_centre(wall_cells, side, index) \
		+ (SIDES[side] as Vector2) * (WALL_CELL / 2.0 + STATION_OUT)


## The wall's size in cells for a map `zone`.
static func wall_cells_for(zone: Rect2) -> Vector2i:
	var n := (zone.size * WALL_FRACTION / WALL_CELL).round()
	return Vector2i(maxi(int(n.x), WALL_MIN_CELLS), maxi(int(n.y), WALL_MIN_CELLS))


## Cells along side `side` of a wall `cells` big, leaving out the corners.
static func side_length(cells: Vector2i, side: int) -> int:
	return (cells.x if side % 2 == 0 else cells.y) - 2


## Grid cell (column, row) of cell `index` along side `side`.
static func side_cell(cells: Vector2i, side: int, index: int) -> Vector2i:
	match side:
		0:
			return Vector2i(index + 1, 0)
		1:
			return Vector2i(cells.x - 1, index + 1)
		2:
			return Vector2i(index + 1, cells.y - 1)
	return Vector2i(0, index + 1)


## Centre of grid cell `cell` from the wall's centre.
static func cell_centre(cells: Vector2i, cell: Vector2i) -> Vector2:
	return -Vector2(cells) * WALL_CELL / 2.0 + (Vector2(cell) + Vector2.ONE * 0.5) * WALL_CELL


static func side_cell_centre(cells: Vector2i, side: int, index: int) -> Vector2:
	return cell_centre(cells, side_cell(cells, side, index))


func _has_station() -> bool:
	return is_shielded()


func _at_station(player: Node) -> bool:
	return _codes.has(player) or _picks.has(player)


## Who's at our keypad: a player standing on it gets a code, and loses it
## when they step off. Moving on the spot starts it over.
func _tick_keypad(delta: float) -> void:
	var usable := wall_up() and not our_code_done()
	for player in game.all_players:
		if not _on_station(player, usable):
			_codes.erase(player)
			continue
		if not _codes.has(player):
			if not _kept.has(player):
				_kept[player] = _new_code(player)
			_codes[player] = {"code": _kept[player], "at": 0, "miss": 0.0}
		var entry: Dictionary = _codes[player]
		entry["miss"] = maxf(float(entry["miss"]) - delta, 0.0)
		if player.wants_to_move():
			entry["at"] = 0


## Who's at our lock: a player standing on it gets a picker, starting from
## the pins they set before stepping off. The needles go round.
func _tick_lock(delta: float) -> void:
	var usable := wall_up() and not our_code_done()
	for player in game.all_players:
		if not _on_station(player, usable):
			_picks.erase(player)
			continue
		if not _picks.has(player):
			_picks[player] = {"pin": int(_kept.get(player, 0)), "arc": 0.0, "needle": 0.0,
				"miss": 0.0}
			_new_pin(_picks[player], true)
		var entry: Dictionary = _picks[player]
		entry["miss"] = maxf(float(entry["miss"]) - delta, 0.0)
		var pin := mini(int(entry["pin"]), PINS - 1)
		# Every other pin turns the other way.
		var turn := 1.0 if pin % 2 == 0 else -1.0
		entry["needle"] = wrapf(float(entry["needle"]) + turn * pin_speed(pin) * delta,
			-PI, PI)


## Whether `player` is standing at our station (while it takes input), and
## points their face buttons at it if so.
func _on_station(player: Node, usable: bool) -> bool:
	var at: bool = usable and not player.is_dead() and not _in_air(player) \
		and player.global_position.distance_to(keypad_pos) <= KEYPAD_REACH
	if at:
		player.keypad = self
	elif player.keypad == self:
		player.keypad = null
	return at


func _new_code(player: Node) -> Array:
	return make_code(code_length(player.get_attribute("engineering")))


## A random code `length` presses long, never the same button more than
## CODE_MAX_RUN times in a row.
static func make_code(length: int) -> Array:
	var code := []
	for i in length:
		var options: Array = BUTTONS.duplicate()
		if i >= CODE_MAX_RUN and code.slice(i - CODE_MAX_RUN).count(code[i - 1]) == CODE_MAX_RUN:
			options.erase(code[i - 1])
		code.append(options.pick_random())
	return code


## Presses in a code for a player with `engineering`.
static func code_length(engineering: int) -> int:
	for row: Array in ENGINEER_LENGTHS:
		if engineering > int(row[0]):
			return int(row[1])
	return CODE_LENGTH


## The needle's speed (radians a second) for pin `pin`.
static func pin_speed(pin: int) -> float:
	return float(PIN_SPEEDS[clampi(pin, 0, PIN_SPEEDS.size() - 1)])


## The gold arc's width (radians) for pin `pin`, for a player with `engineering`.
static func pin_arc(engineering: int, pin: int) -> float:
	var width := float(PIN_ARCS[clampi(pin, 0, PIN_ARCS.size() - 1)])
	for row: Array in ENGINEER_ARCS:
		if engineering > int(row[0]):
			return width * float(row[1])
	return width


## Whether a needle at `needle` is inside an arc of `width` centred on `arc`.
static func needle_in_arc(needle: float, arc: float, width: float) -> bool:
	return absf(angle_difference(needle, arc)) <= width / 2.0


## A fresh arc for the entry's current pin, well round from the needle (and
## the needle somewhere new too if `fresh`).
func _new_pin(entry: Dictionary, fresh := false) -> void:
	if fresh:
		entry["needle"] = randf_range(-PI, PI)
	entry["arc"] = wrapf(float(entry["needle"]) + randf_range(ARC_CLEARANCE, TAU - ARC_CLEARANCE),
		-PI, PI)


## The input actions `player` can press at our station, each with the
## button it counts as (character_body.gd): the four code buttons at the
## keypad, the pick button at the lock, nothing elsewhere.
func station_actions(player: Node) -> Dictionary:
	if _picks.has(player):
		return {PICK_ACTION: PICK_BUTTON}
	if _codes.has(player):
		return {CODE_ACTIONS["A"]: "A", CODE_ACTIONS["B"]: "B", CODE_ACTIONS["X"]: "X",
			CODE_ACTIONS["Y"]: "Y"}
	return {}


## A button pressed by a player at our keypad or lock (character_body.gd).
func code_press(player: Node, button: String) -> void:
	if not wall_up() or our_code_done():
		return
	if _picks.has(player):
		_pick_press(player)
		return
	if not _codes.has(player):
		return
	var entry: Dictionary = _codes[player]
	var code: Array = entry["code"]
	if code[entry["at"]] != button:
		entry["at"] = 0
		entry["miss"] = MISS_FLASH
		Global.play_sfx(KEYPAD_BUZZER)
		return
	entry["at"] += 1
	if entry["at"] >= code.size():
		_station_done()


## The pick button at the lock: sets the pin if the needle's in the gold.
func _pick_press(player: Node) -> void:
	var entry: Dictionary = _picks[player]
	if float(entry["miss"]) > 0.0:
		return
	var pin := int(entry["pin"])
	var width := pin_arc(player.get_attribute("engineering"), pin)
	if not needle_in_arc(float(entry["needle"]), float(entry["arc"]), width):
		entry["miss"] = PICK_MISS
		Global.play_sfx(KEYPAD_BUZZER)
		_new_pin(entry)
		return
	entry["pin"] = pin + 1
	_kept[player] = pin + 1
	Global.play_sfx(PICK_CLICK)
	if pin + 1 >= PINS:
		_station_done()
	else:
		_new_pin(entry)


func _station_done() -> void:
	_local_done = true
	_codes.clear()
	_picks.clear()
	_kept.clear()
	report({"code": windows})


## Shooting or swinging starts a player's keypad code over.
func _interrupt(player: Node) -> void:
	if _codes.has(player):
		_codes[player]["at"] = 0


func _on_player_shot(_shot: Node, player: Node) -> void:
	_interrupt(player)


# --- Host -----------------------------------------------------------------------------

func _host_think(delta: float) -> void:
	for player in living_players():
		_positions[key_of(player)] = [to_shared_pos(player.global_position), elapsed,
			_at_station(player)]
	if _has_station():
		_pads[my_squad] = to_shared_pos(keypad_pos)
	else:
		_pads.clear()
	for key in _positions.keys():
		if elapsed - float(_positions[key][1]) > POSITION_STALE:
			_positions.erase(key)

	if is_defeated():
		return
	need = _codes_needed()
	if phase < WALK_PHASE:
		if is_shielded() and hp <= mark_hp(phase):
			# A late report took it to the mark after the window shut.
			_next_window(true)
		elif is_shielded() and done_squads.size() >= need:
			open_until = elapsed + BURN_TIME
			_floor_hp = window_floor(hp)
		elif is_open() and (elapsed >= open_until or hp <= _floor_hp):
			open_until = -1.0
			_closed_at = elapsed
			_next_window(hp <= mark_hp(phase))
	else:
		_walker_think(delta)

	if elapsed >= _next_volley:
		_next_volley = elapsed + (ENRAGED_VOLLEY if is_enraged() else VOLLEY_EVERY)
		_fire_volley()


## Host: the window's shut, and the wall's about to stand back up. On to the
## next stage if this one's mark was reached (and up on its legs after the
## last, with no wall), else the same stage again; either way a fresh
## station.
func _next_window(reached: bool) -> void:
	if reached:
		phase += 1
	windows += 1
	done_squads.clear()
	if phase >= WALK_PHASE:
		_start_walking()
	else:
		rise_at = elapsed + RISE_WARN


## Codes it takes to open the window: one in a local game; in a squads game
## SQUADS_NEEDED, or every squad still up if there are fewer.
func _codes_needed() -> int:
	if not squads_game:
		return 1
	var up := present_squads().filter(func(s: int) -> bool: return squad_up(s)).size()
	return clampi(up, 1, SQUADS_NEEDED)


## A shell at a player in every squad (two for a squad of three or more),
## never at whoever is at a keypad or lock, and never landing on one.
func _fire_volley() -> void:
	var by_squad := _keys_by_squad()
	var flight := ENRAGED_SHELL_FLIGHT if is_enraged() else SHELL_FLIGHT
	for squad in by_squad:
		var keys: Array = by_squad[squad]
		var targets := keys.filter(func(k: int) -> bool: return not bool(_positions[k][2]))
		if targets.is_empty():
			continue
		var shells := 2 if keys.size() >= 3 else 1
		for i in shells:
			var target: int = targets.pick_random()
			var shared: Vector2 = _positions[target][0] \
				+ Vector2.from_angle(randf() * TAU) * randf() * SHELL_SCATTER
			if _pads.has(squad):
				shared = _off_pad(shared, _pads[squad])
			var spot := to_local_pos(shared)
			var land := elapsed + flight + i * 0.25
			emit_hazard("shell", spot, land + SHELL_LINGER, {"land": land})


## Host: squad -> the keys of its players we know the positions of.
func _keys_by_squad() -> Dictionary:
	var by_squad := {}
	for key in _positions:
		var squad := int(key) / 16
		if not by_squad.has(squad):
			by_squad[squad] = []
		by_squad[squad].append(key)
	return by_squad


## `spot` moved straight out from keypad `pad` (both shared) until the shell's
## blast can't touch the keypad.
func _off_pad(spot: Vector2, pad: Vector2) -> Vector2:
	var clear := KEYPAD_REACH + SHELL_RADIUS
	var away := spot - pad
	if away.length() >= clear:
		return spot
	if away.length() < 0.01:
		away = Vector2.from_angle(randf() * TAU)
	return pad + away.normalized() * clear


func apply_damage(part: int, amount: int, _squad: int) -> void:
	if part >= DRONE_PART and part < DRONE_PART + DRONES:
		var i := part - DRONE_PART
		drone_hp[i] = maxi(int(drone_hp[i]) - amount, 0)
		return
	if part != 0:
		return
	if is_walking():
		# (Reports from the last window still on their way are lost.)
		if is_standing_up():
			return
		hp = maxi(hp - amount, 0)
	else:
		# Hits are only counted while the wall is down (and just after, for
		# reports still on their way), and never past the window's cut.
		if not is_open() and elapsed - _closed_at > REPORT_INTERVAL * 2.0:
			return
		hp = maxi(hp - amount, _floor_hp)
	if hp == 0:
		defeat()


func boss_report() -> Dictionary:
	if not squads_game:
		return {}
	var pos := {}
	for player in living_players():
		pos[key_of(player)] = [to_shared_pos(player.global_position), _at_station(player)]
	var data := {"pos": pos}
	if _has_station():
		data["pad"] = to_shared_pos(keypad_pos)
	return data


func boss_receive(squad: int, data: Dictionary) -> void:
	if data.has("code") and int(data["code"]) == windows and is_shielded() \
			and not done_squads.has(squad):
		done_squads.append(squad)
	var pos: Dictionary = data.get("pos", {})
	for key in pos:
		_positions[int(key)] = [pos[key][0], elapsed, bool(pos[key][1])]
	if data.has("pad") and _has_station():
		_pads[squad] = data["pad"]


func boss_state() -> Dictionary:
	var state := {"hp": hp, "max": max_hp, "phase": phase, "win": windows, "open": open_until,
		"rise": rise_at, "done": done_squads, "need": need}
	if phase >= WALK_PHASE:
		state["walk"] = walk_from
		state["wp"] = to_shared_pos(body.global_position)
		state["dr"] = drone_hp
		state["dmax"] = drone_max
		state["dat"] = drones_at
	return state


func apply_boss_state(state: Dictionary) -> void:
	hp = int(state.get("hp", hp))
	max_hp = int(state.get("max", max_hp))
	phase = int(state.get("phase", phase))
	windows = int(state.get("win", windows))
	open_until = float(state.get("open", open_until))
	rise_at = float(state.get("rise", rise_at))
	done_squads = state.get("done", done_squads)
	need = int(state.get("need", need))
	walk_from = float(state.get("walk", walk_from))
	if state.has("dr"):
		drone_hp = state["dr"]
	drone_max = int(state.get("dmax", drone_max))
	drones_at = float(state.get("dat", drones_at))
	if state.has("wp"):
		_host_walk = state["wp"]
		_host_walk_at = elapsed


# --- The walker -----------------------------------------------------------------------

func _start_walking() -> void:
	walk_from = elapsed + TRANSFORM_TIME
	_floor_hp = 0
	_next_drones = walk_from
	_next_burst = walk_from + 1.0
	_next_stomp = walk_from
	_next_sweep = walk_from + 1.0


## Host: walking, stomping, shooting and the drones.
func _walker_think(delta: float) -> void:
	if is_standing_up():
		return
	if elapsed >= _next_drones:
		_next_drones = elapsed + DRONE_EVERY
		drone_hp.fill(drone_max)
		drones_at = elapsed
	var me := to_shared_pos(body.global_position)
	if elapsed >= _next_stomp and _anyone_within(me, STOMP_TRIGGER):
		var land := elapsed + (ENRAGED_STOMP_WIND if is_enraged() else STOMP_WIND)
		emit_hazard("stomp", body.global_position, land + ExplosionArt.DURATION, {"land": land})
		_stomp_until = land
		_next_stomp = land + STOMP_COOLDOWN
	if elapsed >= _next_burst:
		_next_burst = elapsed + (ENRAGED_BURST_EVERY if is_enraged() else BURST_EVERY)
		_bursts += 1
		_fire_bursts(me, _bursts % FAN_EVERY == 0)
	if elapsed >= _next_sweep:
		var warn := ENRAGED_SWEEP_WARN if is_enraged() else SWEEP_WARN
		_next_sweep = elapsed + warn + SWEEP_ON + SWEEP_PAUSE
		_fire_sweeps(warn)
	if elapsed < _stomp_until:
		return  # Planted for the stomp.
	var target := _nearest_known(me)
	if target == Vector2.INF:
		return
	var to := target - me
	var step := minf((ENRAGED_WALK_SPEED if is_enraged() else WALK_SPEED) * delta,
		to.length() - WALK_STOP)
	if step > 0.0:
		me += to.normalized() * step
	var roam := roam_rect()
	me = me.clamp(roam.position, roam.end)
	body.global_position = to_local_pos(me)


## Host: whether any player we know of is within `reach` of `at` (shared).
func _anyone_within(at: Vector2, reach: float) -> bool:
	for key in _positions:
		if (_positions[key][0] as Vector2).distance_to(at) <= reach:
			return true
	return false


## Host: the nearest player we know of to `at` (shared), or Vector2.INF.
func _nearest_known(at: Vector2) -> Vector2:
	var best := Vector2.INF
	for key in _positions:
		var p: Vector2 = _positions[key][0]
		if best == Vector2.INF or p.distance_squared_to(at) < best.distance_squared_to(at):
			best = p
	return best


## Host: a burst (or a fan) at a player in every squad.
func _fire_bursts(me: Vector2, fan: bool) -> void:
	var by_squad := _keys_by_squad()
	for squad in by_squad:
		var target: int = (by_squad[squad] as Array).pick_random()
		var dir := me.direction_to(_positions[target][0])
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var fire := elapsed + BURST_AIM
		var n := FAN_SHOTS if fan else BURST_SHOTS
		var gap := 0.0 if fan else BURST_GAP
		emit_hazard("burst", body.global_position, fire + gap * n + BULLET_LIFE,
			{"dir": dir, "fire": fire, "n": n, "gap": gap, "spread": FAN_SPREAD if fan else 0.0})


## Host: SWEEP_LINES sweep lasers for every squad, the first through one of
## its players, the rest through random spots on its map, each in a random
## direction. Every squad's copy plays out only its own.
func _fire_sweeps(warn: float) -> void:
	var by_squad := _keys_by_squad()
	for squad in by_squad:
		var map := squad_map_shared(squad).grow(-SWEEP_INSET)
		for i in SWEEP_LINES:
			var through := Vector2(randf_range(map.position.x, map.end.x),
				randf_range(map.position.y, map.end.y))
			if i == 0:
				through = _positions[(by_squad[squad] as Array).pick_random()][0]
			emit_hazard("sweep", to_local_pos(through), elapsed + warn + SWEEP_ON,
				{"angle": SWEEP_ANGLES.pick_random(), "on": elapsed + warn, "sq": squad})


## Where the walker may go (shared): the part of the map every present squad
## shares (all of it in a local game), less ROAM_INSET.
func roam_rect() -> Rect2:
	var area := Rect2(to_shared_pos(map_rect().position), map_rect().size)
	if squads_game:
		for squad in present_squads():
			area = area.intersection(squad_map_shared(squad))
	area = area.grow(-ROAM_INSET)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return Rect2(to_shared_pos(shared_centre()), Vector2.ZERO)
	return area


## Joiner: carry the walker towards where the host last put it.
func _follow_host(delta: float) -> void:
	if _host_walk_at < 0.0:
		return
	var goal := to_local_pos(_host_walk)
	body.global_position = body.global_position.lerp(goal, 1.0 - exp(-10.0 * delta))


## Our copies of the drones: made when it starts walking, flown round it, and
## only there to hit while they're up.
func _update_drones() -> void:
	if _drone_bodies.is_empty() and not is_walking():
		return
	if _drone_bodies.is_empty():
		for i in DRONES:
			var d := add_body(DRONE_PART + i, body.global_position, DRONE_RADIUS, _paint_drone)
			# Not one of the boss's own bodies: they don't push players about.
			bodies.erase(d)
			d.contact_damage = 1
			d.dormant = true
			_drone_bodies.append(d)
	for i in _drone_bodies.size():
		var d := _drone_bodies[i]
		var up := int(drone_hp[i]) > 0 and not is_standing_up() and not is_defeated()
		d.global_position = drone_position(i)
		d.visible = up
		if d.dormant == up:
			d.dormant = not up


## Where drone `i` is flying now (our coordinates).
func drone_position(i: int) -> Vector2:
	var out := clampf((elapsed - drones_at) / DRONE_LAUNCH, 0.0, 1.0)
	var angle := elapsed * DRONE_SPIN + i * TAU / DRONES
	return body.global_position + Vector2.from_angle(angle) * DRONE_ORBIT * out


# --- Hits ---------------------------------------------------------------------------

func hit_multiplier(b: Node, _at: Vector2) -> float:
	if b != body:
		return 1.0  # A drone.
	if is_walking():
		if is_standing_up():
			return 0.0
		return DRONE_ARMOR if drones_up() else 1.0
	return 1.0 if is_open() else 0.0


# --- Hazards ------------------------------------------------------------------------

func hazard_tick(h: Dictionary, _delta: float) -> void:
	match h["kind"]:
		"shell":
			if not h.get("landed", false) and elapsed >= float(h["land"]):
				h["landed"] = true
				var at: Vector2 = h["pos"]
				if ExplosionArt.is_small(SHELL_RADIUS):
					ExplosionArt.play_small_sound()
				hurt_players(func(p: Vector2) -> bool:
					return p.distance_to(at) <= SHELL_RADIUS + PLAYER_HALF, SHELL_DAMAGE)
		"stomp":
			if not h.get("landed", false) and elapsed >= float(h["land"]):
				h["landed"] = true
				var at: Vector2 = h["pos"]
				hurt_players(func(p: Vector2) -> bool:
					return p.distance_to(at) <= STOMP_RADIUS + PLAYER_HALF, STOMP_DAMAGE)
		"burst":
			_tick_burst(h)
		"sweep":
			if _sweep_live(h):
				var line := _sweep_line(h)
				laser_hurt(func(p: Vector2) -> bool:
					return VaultLasers.touches(line[0], line[1], p))


## Burns every living player `touching` (a Callable on their position) says
## is on a laser, for VaultLasers.DAMAGE; the fence buzzer sounds if anyone
## actually took the hit (not one still flashing from their last).
func laser_hurt(touching: Callable) -> void:
	var hit := false
	for player in living_players():
		if touching.call(player.global_position):
			var before: int = player.health
			player.hurt_by(VaultLasers.DAMAGE, player.global_position)
			hit = hit or player.health < before
	if hit:
		Global.play_sfx(FENCE_BUZZER)


func _tick_burst(h: Dictionary) -> void:
	var id := int(h["id"])
	var n := int(h["n"])
	if not _spent.has(id):
		var fresh := []
		fresh.resize(n)
		fresh.fill(false)
		_spent[id] = fresh
	var spent: Array = _spent[id]
	for i in n:
		if spent[i]:
			continue
		var p: Variant = bullet_position(h, i, elapsed)
		if p == null:
			continue
		for player in living_players():
			if player.global_position.distance_to(p) <= BULLET_RADIUS + PLAYER_HALF * 0.6:
				player.hurt_by(BULLET_DAMAGE, p)
				spent[i] = true
				break


## Where bullet `i` of burst hazard `h` is at `now`, or null if it hasn't
## been fired yet or has flown its full range.
static func bullet_position(h: Dictionary, i: int, now: float) -> Variant:
	var t0 := float(h["fire"]) + float(h["gap"]) * i
	var age := now - t0
	if age < 0.0 or age > BULLET_LIFE:
		return null
	return Vector2(h["pos"]) + bullet_dir(h, i) * (RADIUS * 0.6 + BULLET_SPEED * age)


static func bullet_dir(h: Dictionary, i: int) -> Vector2:
	var dir: Vector2 = h["dir"]
	var n := int(h["n"])
	var spread := float(h["spread"])
	if spread > 0.0 and n > 1:
		dir = dir.rotated(spread * (float(i) / (n - 1) - 0.5))
	return dir


func draw_hazard(h: Dictionary) -> void:
	match h["kind"]:
		"shell":
			_draw_shell(h)
		"stomp":
			_draw_stomp(h)
		"burst":
			_draw_burst(h)
		"sweep":
			_draw_sweep(h)


func _draw_shell(h: Dictionary) -> void:
	var at: Vector2 = h["pos"]
	var land := float(h["land"])
	if elapsed < land:
		var k := clampf((elapsed - float(h["born"])) / maxf(land - float(h["born"]), 0.01), 0.0, 1.0)
		draw_circle(at, SHELL_RADIUS, Color(1.0, 0.3, 0.15, 0.12))
		draw_circle(at, SHELL_RADIUS * k, Color(1.0, 0.35, 0.15, 0.3))
		TargetMarker.draw(self, at, SHELL_RADIUS)
		var height := (1.0 - k) * 120.0
		draw_circle(at + Vector2(0, -height), 3.0, Color(0.15, 0.12, 0.1))
	else:
		ExplosionArt.draw(self, at, elapsed - land, SHELL_RADIUS)


func _draw_stomp(h: Dictionary) -> void:
	var at: Vector2 = h["pos"]
	var land := float(h["land"])
	if elapsed < land:
		var k := clampf((elapsed - float(h["born"])) / maxf(land - float(h["born"]), 0.01), 0.0, 1.0)
		draw_circle(at, STOMP_RADIUS, Color(1.0, 0.3, 0.15, 0.1))
		draw_arc(at, STOMP_RADIUS, 0.0, TAU, 48, Color(1.0, 0.35, 0.15, 0.8), 1.0)
		draw_arc(at, STOMP_RADIUS * k, 0.0, TAU, 48, Color(1.0, 0.35, 0.15, 0.5), 2.0)
	else:
		var t := elapsed - land
		var k := clampf(t / ExplosionArt.DURATION, 0.0, 1.0)
		draw_arc(at, STOMP_RADIUS * (0.6 + 0.4 * k), 0.0, TAU, 48, Color(0.85, 0.8, 0.7, 1.0 - k), 3.0)


## A sweep laser that's ours (not another squad's) and burning.
func _sweep_live(h: Dictionary) -> bool:
	return int(h["sq"]) == my_squad and elapsed >= float(h["on"])


## A sweep laser's line across our map (worked out once, then kept: not in
## the hazard itself, which goes out to the other squads).
func _sweep_line(h: Dictionary) -> PackedVector2Array:
	var id := int(h["id"])
	if not _lines.has(id):
		_lines[id] = VaultLasers.line_across(h["pos"], float(h["angle"]), map_rect())
	var line: PackedVector2Array = _lines[id]
	return line if line.size() == 2 else PackedVector2Array([h["pos"], h["pos"]])


func _draw_sweep(h: Dictionary) -> void:
	if int(h["sq"]) != my_squad:
		return
	var line := _sweep_line(h)
	var on := float(h["on"])
	if elapsed < on:
		var k := clampf((elapsed - float(h["born"])) / maxf(on - float(h["born"]), 0.01), 0.0, 1.0)
		VaultLasers.draw_warning(self, line[0], line[1], k, on - elapsed, elapsed)
	else:
		VaultLasers.draw_beam(self, line[0], line[1], elapsed, 2.0)


func _draw_burst(h: Dictionary) -> void:
	var at: Vector2 = h["pos"]
	var n := int(h["n"])
	if elapsed < float(h["fire"]):
		# The aim: a flickering line down each bullet's path.
		var flicker := 0.3 + 0.3 * signf(sin(elapsed * 28.0))
		var dirs := [0, n - 1] if float(h["spread"]) > 0.0 else [0]
		for i in dirs:
			var dir := bullet_dir(h, i)
			draw_line(at + dir * RADIUS * 0.6, at + dir * 70.0, Color(BULLET, flicker), 1.0)
		return
	var spent: Array = _spent.get(int(h["id"]), [])
	for i in n:
		if i < spent.size() and spent[i]:
			continue
		var p: Variant = bullet_position(h, i, elapsed)
		if p == null:
			continue
		var dir := bullet_dir(h, i)
		draw_line(p - dir * 6.0, p, Color(BULLET, 0.4), 2.0)
		draw_circle(p, BULLET_RADIUS, BULLET)
		draw_circle(p, BULLET_RADIUS * 0.5, Color(1, 0.95, 0.8))


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	super._draw()
	if is_defeated():
		return
	var centre := body.global_position - global_position
	if wall_rising():
		_draw_rise_warning(centre)
	if elapsed - _blast_at < BLAST_RING:
		var k := (elapsed - _blast_at) / BLAST_RING
		var reach := lerpf(RADIUS, wall_half.length(), k)
		draw_arc(centre, reach, 0.0, TAU, 64, Color(1.0, 0.85, 0.6, 0.8 * (1.0 - k)), 3.0)
	# Shadows under our players in the air.
	for player in game.all_players:
		if _in_air(player):
			var at: Vector2 = player.global_position - global_position + Vector2(0, PLAYER_HALF - 2.0)
			draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.35))
			draw_set_transform(Vector2.ZERO)
	lasers.draw(self, elapsed)
	# Tethers from the walker to its drones.
	for i in _drone_bodies.size():
		if _drone_bodies[i].visible:
			var pulse := 0.35 + 0.15 * sin(elapsed * 6.0 + i)
			draw_line(body.global_position - global_position,
				_drone_bodies[i].global_position - global_position, Color(SHIELD, pulse), 1.0)
	if not _has_station():
		return
	# Where to stand at our lock or keypad (its art is in the wall).
	var tint: Color = DONE if our_code_done() else info["color"]
	draw_circle(keypad_pos, KEYPAD_REACH, Color(tint, 0.18))
	draw_arc(keypad_pos, KEYPAD_REACH, 0.0, TAU, 32, Color(tint, 0.8), 1.0)


## The wall's about to stand up: where it will be flashes red on the ground,
## quicker as it gets closer (and so do the keypad corridor's beams).
func _draw_rise_warning(centre: Vector2) -> void:
	var left := rise_at - elapsed
	var k := clampf(1.0 - left / RISE_WARN, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(elapsed * (8.0 + 16.0 * k))
	var outer := Rect2(centre - wall_half, wall_half * 2.0)
	var inner := outer.grow(-WALL_CELL)
	var fill := Color(MISS, 0.12 + 0.18 * pulse)
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, WALL_CELL)), fill)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, WALL_CELL)), fill)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(WALL_CELL, inner.size.y)), fill)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(WALL_CELL, inner.size.y)), fill)
	var line := Color(MISS, 0.5 + 0.5 * pulse)
	draw_rect(outer, line, false, 1.0)
	draw_rect(inner, line, false, 1.0)
	if stage() == 1 and not our_code_done():
		for beam: Array in lasers.beams:
			VaultLasers.draw_warning(self, beam[0], beam[1], k, left, elapsed)


func _paint(b: BossBody) -> void:
	if is_defeated():
		paint_death(b, RADIUS, elapsed - defeated_at, info["color"])
		return
	var aim := Vector2.UP
	var target := _nearest_player()
	if target:
		aim = b.global_position.direction_to(target.global_position)
	if is_walking():
		var rise := 0.0
		if walk_from >= 0.0:
			rise = clampf(1.0 - (walk_from - elapsed) / TRANSFORM_TIME, 0.0, 1.0)
		paint_walker(b, b.age, aim, _walked, rise, drones_up(), b.flash > 0.0 and not is_standing_up())
		if walk_from >= 0.0:
			# The door blowing off as it starts to get up.
			var t := elapsed - (walk_from - TRANSFORM_TIME)
			ExplosionArt.draw(b, Vector2(0, RADIUS * 0.2), t, RADIUS * 0.8)
		return
	var cell := Vector2i(-1, -1)
	if _has_station() and station_side >= 0:
		cell = side_cell(wall_cells, station_side, station_index)
	paint_vault(b, b.age, aim, _wall, b.flash > 0.0, wall_half, cell,
		GATE_ART if stage() == 0 else KEYPAD_ART)


func _nearest_player() -> Node2D:
	var best: Node2D = null
	for player in living_players():
		if best == null or player.global_position.distance_squared_to(body.global_position) \
				< best.global_position.distance_squared_to(body.global_position):
			best = player
	return best


## (Without its wall: that stands up after the intro.)
static func paint_preview(c: CanvasItem, age: float) -> void:
	paint_vault(c, age, Vector2.from_angle(-PI / 2.0 + sin(age * 0.7) * 0.6), 0.0, false)


## The Vault: a steel box with a dial on its door and a mortar on its roof
## aimed along `aim`, inside its wall (`wall` 0 sunk .. 1 up; `half` from its
## centre to its outside edge), with `station_art` in grid cell `station`.
## `hit` flashes it (or the wall) for a hit.
static func paint_vault(c: CanvasItem, age: float, aim: Vector2, wall: float, hit: bool,
		half := Vector2.ONE * WALL_CELL * 2.5, station := Vector2i(-1, -1),
		station_art: Texture2D = null) -> void:
	var r := RADIUS
	c.draw_circle(Vector2(0, r * 0.3), r * 1.05, Color(0, 0, 0, 0.3))
	_paint_box(c, hit and wall <= 0.0)
	# The door dial, turning.
	var dial := Vector2(0, r * 0.2)
	c.draw_circle(dial, r * 0.36, STEEL_DARK)
	c.draw_circle(dial, r * 0.3, BRASS)
	for i in 3:
		var a := age * 1.3 + i * TAU / 3.0
		c.draw_line(dial, dial + Vector2.from_angle(a) * r * 0.28, STEEL_DARK, 2.0)
	c.draw_circle(dial, r * 0.08, STEEL_DARK)
	_paint_mortar(c, Vector2(0, -r * 0.45), aim)
	paint_wall(c, half, wall, hit, station, station_art)


## The wall round it: a ring of cells, each 2x2 of the act's block-1 tiles
## (the same mix the Campaign's walls use), with `station_art` (upright) in
## grid cell `station`, all sunk to `up` (0..1) of their size.
static func paint_wall(c: CanvasItem, half: Vector2, up: float, hit: bool,
		station := Vector2i(-1, -1), station_art: Texture2D = null) -> void:
	if up <= 0.0:
		return
	var options := ActTheme.environment_options("block", BLOCK_ART, 1)
	var tint := Color(1.0, 0.75, 0.7) if hit else Color.WHITE
	tint = tint.darkened(0.4 * (1.0 - up))
	var cells := Vector2i((half * 2.0 / WALL_CELL).round())
	var tile := Vector2.ONE * WALL_TILE * up
	for i in cells.x:
		for j in cells.y:
			if i != 0 and j != 0 and i != cells.x - 1 and j != cells.y - 1:
				continue
			var centre := cell_centre(cells, Vector2i(i, j))
			if Vector2i(i, j) == station and station_art:
				var size := Vector2.ONE * WALL_CELL * up
				c.draw_texture_rect(station_art, Rect2(centre - size / 2.0, size), false, tint)
				continue
			for a in 2:
				for b in 2:
					var at := centre + (Vector2(a, b) - Vector2.ONE * 0.5) * WALL_TILE
					var texture: Texture2D = options[posmod(hash(Vector2i(i * 2 + a, j * 2 + b)),
						options.size())]
					c.draw_texture_rect(texture, Rect2(at - tile / 2.0, tile), false, tint)
	if up >= 1.0:
		var outline := WALL_ROBOT_OUTLINE if ActTheme.current == "robot" else WALL_OUTLINE
		c.draw_rect(Rect2(-half, half * 2.0), outline, false, 1.0)
		c.draw_rect(Rect2(-half, half * 2.0).grow(-WALL_CELL), outline, false, 1.0)


## Stand-in art for the walker: the box up on four legs (`rise` 0 folded
## away .. 1 standing), its door gone and its glowing core showing, a gun
## turret beside the mortar, and a faint shield while its drones fly.
## `stride` (pixels walked) moves the feet.
static func paint_walker(c: CanvasItem, age: float, aim: Vector2, stride: float, rise: float,
		armoured: bool, hit: bool) -> void:
	var r := RADIUS
	var lift := Vector2(0, -6.0 * rise)
	c.draw_circle(Vector2(0, r * 0.35), r * 1.1, Color(0, 0, 0, 0.3))
	# Legs: hip at the box's side, knee out, foot on the ground; pairs step
	# in turn.
	var step := stride * 0.18
	for side in [-1.0, 1.0]:
		for pair in 2:
			var swing := sin(step + pair * PI + (0.0 if side < 0.0 else PI * 0.5))
			var hip := Vector2(side * r * 0.7, r * (0.1 + 0.4 * pair)) + lift
			var knee := hip + Vector2(side * r * 0.45, -r * 0.2) * rise
			var foot := Vector2(side * r * (0.75 + 0.35 * rise), r * (0.55 + 0.4 * pair)) \
				+ Vector2(0, -maxf(swing, 0.0) * 4.0 * rise) + Vector2(swing * 3.0 * rise, 0)
			c.draw_line(hip, knee, STEEL_DARK, 4.0)
			c.draw_line(knee, foot, STEEL_DARK, 4.0)
			c.draw_line(hip, knee, STEEL, 2.0)
			c.draw_line(knee, foot, STEEL, 2.0)
			c.draw_circle(foot, 2.5, STEEL_DARK)
	c.draw_set_transform(lift)
	_paint_box(c, hit)
	# The open door: a dark hole with its core glowing in it.
	var hole := Vector2(0, r * 0.2)
	c.draw_circle(hole, r * 0.38, Color(0.05, 0.05, 0.06))
	var glow := 0.6 + 0.4 * sin(age * 5.0)
	c.draw_circle(hole, r * 0.24, Color(CORE, 0.5 * glow))
	c.draw_circle(hole, r * 0.13, Color(1.0, 0.85, 0.5, glow))
	_paint_mortar(c, Vector2(-r * 0.35, -r * 0.45), Vector2.UP.lerp(aim, 0.3))
	# The gun turret, tracking its target.
	var gun := Vector2(r * 0.4, -r * 0.4)
	c.draw_line(gun, gun + aim.normalized() * r * 0.7, STEEL_DARK, 5.0)
	c.draw_line(gun, gun + aim.normalized() * r * 0.7, BULLET.darkened(0.3), 2.0)
	c.draw_circle(gun, r * 0.2, Color(0.25, 0.27, 0.3))
	c.draw_arc(gun, r * 0.2, 0.0, TAU, 16, STEEL_DARK, 1.0)
	if armoured:
		var pulse := 0.5 + 0.2 * sin(age * 4.0)
		c.draw_circle(Vector2.ZERO, r * 1.2, Color(SHIELD, 0.08 * pulse))
		c.draw_arc(Vector2.ZERO, r * 1.2, 0.0, TAU, 48, Color(SHIELD, 0.5 * pulse), 1.0)
	c.draw_set_transform(Vector2.ZERO)


static func _paint_box(c: CanvasItem, hit: bool) -> void:
	var r := RADIUS
	var box := Rect2(Vector2(-r * 0.85, -r * 0.8), Vector2(r * 1.7, r * 1.6))
	c.draw_rect(box, Color(1, 0.45, 0.4) if hit else STEEL)
	c.draw_rect(box, STEEL_DARK, false, 2.0)
	# Rivets in the corners.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		c.draw_circle(corner * Vector2(r * 0.7, r * 0.65), 1.5, STEEL_DARK)


## The mortar on the roof at `top`: a turret and a stubby barrel along `aim`.
static func _paint_mortar(c: CanvasItem, top: Vector2, aim: Vector2) -> void:
	var r := RADIUS
	c.draw_line(top, top + aim.normalized() * r * 0.6, STEEL_DARK, 7.0)
	c.draw_line(top, top + aim.normalized() * r * 0.6, Color(0.25, 0.27, 0.3), 4.0)
	c.draw_circle(top, r * 0.24, Color(0.25, 0.27, 0.3))
	c.draw_arc(top, r * 0.24, 0.0, TAU, 20, STEEL_DARK, 1.0)


## Stand-in art for a shield drone: a little disc with a light and rotors.
func _paint_drone(b: BossBody) -> void:
	var r := DRONE_RADIUS
	var spin := b.age * 18.0
	for i in 2:
		var a := spin + i * PI / 2.0
		b.draw_line(Vector2.from_angle(a) * r * 1.2, -Vector2.from_angle(a) * r * 1.2,
			Color(0.8, 0.85, 0.9, 0.5), 1.0)
	b.draw_circle(Vector2.ZERO, r * 0.8, Color.WHITE if b.flash > 0.0 else STEEL)
	b.draw_arc(Vector2.ZERO, r * 0.8, 0.0, TAU, 16, STEEL_DARK, 1.0)
	b.draw_circle(Vector2.ZERO, r * 0.35, SHIELD)


# --- Codes and picks on screen (UI layer, so they're crisp) --------------------------

## Size of a code button on screen (UI units), and the gap between them.
const ICON := 64.0
const ICON_GAP := 10.0
## The lock picker's ring radius on screen (UI units).
const PICK_RING := 78.0
## The button the picker shows and takes (PICK_ACTION).
const PICK_BUTTON := "X"
## The keypad's hint bubble: its buttons' size and gap (UI units).
const HINT_ICON := 48.0
const HINT_GAP := 12.0


func _draw_ui() -> void:
	if is_defeated() or not is_instance_valid(game):
		return
	var to_ui: Transform2D = game.world_to_ui()
	var font := ThemeDB.fallback_font
	if _has_station():
		var word := "LOCK" if stage() == 0 else "KEYPAD"
		var label := word + (" DONE" if our_code_done() else "")
		var color: Color = DONE if our_code_done() else info["color"]
		# Above the spot, or below it on the wall's south side (clear of the wall).
		var label_at := Vector2(0, KEYPAD_REACH + 14) if station_side == 2 \
			else Vector2(0, -KEYPAD_REACH - 18)
		_ui_text(font, to_ui * (keypad_pos + label_at), label, 40, color)
	for player in _codes:
		if is_instance_valid(player):
			_draw_code(player, to_ui)
	for player in _picks:
		if is_instance_valid(player):
			_draw_pick(player, to_ui, font)


func _draw_code(player: Node2D, to_ui: Transform2D) -> void:
	var entry: Dictionary = _codes[player]
	var code: Array = entry["code"]
	var at: int = entry["at"]
	var missed := float(entry["miss"]) > 0.0
	var width := code.size() * ICON + (code.size() - 1) * ICON_GAP
	var centre: Vector2 = to_ui * (player.global_position + Vector2(0, -24))
	var left := centre.x - width / 2.0
	var back := Rect2(left - 16, centre.y - ICON / 2.0 - 16, width + 32, ICON + 32)
	_ui_canvas.draw_rect(back, Color(0, 0, 0, 0.7))
	_ui_canvas.draw_rect(back, MISS if missed else Color(info["color"], 0.9), false, 4.0)
	for i in code.size():
		var rect := Rect2(left + i * (ICON + ICON_GAP), centre.y - ICON / 2.0, ICON, ICON)
		var tint := Color.WHITE
		if missed:
			tint = MISS
		elif i < at:
			tint = Color(1, 1, 1, 0.25)
		elif i > at:
			tint = Color(1, 1, 1, 0.7)
		if i == at and not missed:
			rect = rect.grow(6.0 + 3.0 * sin(elapsed * 10.0))
		# Every button is a blank square: the code has to be cracked.
		_ui_canvas.draw_rect(rect, Color(tint, tint.a * 0.8))
	_draw_hint(Vector2(centre.x, back.position.y - 14.0), player.device == Global.KEYBOARD)


## A speech bubble whose tail points down at `tip`, showing the buttons a
## code can use (A B X Y, or the keyboard's 1 2 3 4).
func _draw_hint(tip: Vector2, keyboard: bool) -> void:
	var font := ThemeDB.fallback_font
	var buttons := ["A", "B", "X", "Y"]
	var row := buttons.size() * HINT_ICON + (buttons.size() - 1) * HINT_GAP
	var pad := 16.0
	var tail := 16.0
	var box := Rect2(tip.x - row / 2.0 - pad, tip.y - tail - HINT_ICON - pad * 2.0,
		row + pad * 2.0, HINT_ICON + pad * 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.border_color = Color(info["color"], 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	_ui_canvas.draw_style_box(style, box)
	var base_y := box.end.y
	_ui_canvas.draw_colored_polygon(PackedVector2Array([Vector2(tip.x - tail, base_y - 2.0),
		Vector2(tip.x + tail, base_y - 2.0), tip]), style.bg_color)
	_ui_canvas.draw_polyline(PackedVector2Array([Vector2(tip.x - tail, base_y),
		tip, Vector2(tip.x + tail, base_y)]), style.border_color, 3.0)
	for i in buttons.size():
		var rect := Rect2(box.position.x + pad + i * (HINT_ICON + HINT_GAP), box.position.y + pad,
			HINT_ICON, HINT_ICON)
		_draw_button(buttons[i], rect, Color.WHITE, keyboard, font, CODE_ACTIONS[buttons[i]])


## The lock picker over a player: the ring, its gold arc, the needle, a
## button prompt in the middle, and a dot for each pin.
func _draw_pick(player: Node2D, to_ui: Transform2D, font: Font) -> void:
	var entry: Dictionary = _picks[player]
	var centre: Vector2 = to_ui * (player.global_position + Vector2(0, -40))
	var missed := float(entry["miss"]) > 0.0
	var pin := mini(int(entry["pin"]), PINS - 1)
	var ring_color := MISS if missed else Color(info["color"], 0.9)
	_ui_canvas.draw_circle(centre, PICK_RING + 18.0, Color(0, 0, 0, 0.7))
	_ui_canvas.draw_arc(centre, PICK_RING, 0.0, TAU, 64, Color(0.3, 0.32, 0.36), 10.0)
	var width := pin_arc(player.get_attribute("engineering"), pin)
	var arc := float(entry["arc"])
	_ui_canvas.draw_arc(centre, PICK_RING, arc - width / 2.0, arc + width / 2.0, 24,
		Color(0.5, 0.5, 0.5) if missed else BRASS, 14.0)
	_ui_canvas.draw_arc(centre, PICK_RING + 18.0, 0.0, TAU, 64, ring_color, 4.0)
	var needle := Vector2.from_angle(float(entry["needle"]))
	_ui_canvas.draw_line(centre + needle * 30.0, centre + needle * (PICK_RING + 10.0),
		Color.WHITE, 6.0)
	var icon := Rect2(centre - Vector2.ONE * ICON * 0.4, Vector2.ONE * ICON * 0.8)
	_draw_button(PICK_BUTTON, icon, Color(1, 1, 1, 0.4) if missed else Color.WHITE,
		player.device == Global.KEYBOARD, font, PICK_ACTION)
	for i in PINS:
		var dot := centre + Vector2((i - (PINS - 1) / 2.0) * 34.0, PICK_RING + 46.0)
		var set_pin := i < int(entry["pin"])
		_ui_canvas.draw_circle(dot, 12.0, DONE if set_pin else Color(0.2, 0.2, 0.22))
		_ui_canvas.draw_arc(dot, 12.0, 0.0, TAU, 16, Color.BLACK, 3.0)


## One button: for a controller, its icon (assets/ui/controls, white) on a
## dark disc; for the keyboard player a keycap with the key `action` is
## bound to.
func _draw_button(button: String, rect: Rect2, tint: Color, keyboard: bool, font: Font,
		action: StringName) -> void:
	if not keyboard:
		var centre := rect.get_center()
		var r := rect.size.x * 0.5 * 190.0 / 256.0  # Just past the icons' ring (166 of 256).
		_ui_canvas.draw_circle(centre, r, Color(0.05, 0.05, 0.07, 0.85 * tint.a))
		_ui_canvas.draw_texture_rect(BUTTON_ICONS[button], rect, false, tint)
		return
	var color: Color = BUTTON_COLORS[button] * tint
	_ui_canvas.draw_rect(rect, Color(0.1, 0.1, 0.12, tint.a))
	_ui_canvas.draw_rect(rect, color, false, 4.0)
	var size := int(rect.size.y * 0.7)
	var pos := Vector2(rect.position.x, rect.get_center().y + size * 0.35)
	_ui_canvas.draw_string(font, pos, _key_letter(action), HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x, size, color)


## The first keyboard key bound to `action` ("1" for code_a, "F" for the lock).
static func _key_letter(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.as_text_physical_keycode()
	return "?"


func _ui_text(font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	var width := 600.0
	var pos := at + Vector2(-width / 2.0, size * 0.35)
	_ui_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 8,
		Color.BLACK)
	_ui_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


# --- HUD ----------------------------------------------------------------------------

func markers() -> Array:
	if is_defeated():
		return []
	if _has_station() and not our_code_done():
		return [[keypad_pos, info["color"]]]
	return super.markers()


func bar_segments() -> Array:
	var hot := is_open() or (is_walking() and not is_standing_up())
	return [{"label": info["name"], "frac": float(hp) / maxf(max_hp, 1.0),
		"color": info["color"] if hot else SHIELD, "dim": not hot}]


func bar_note() -> String:
	if is_defeated():
		return ""
	var note := ""
	var station := "lock" if stage() == 0 else "keypad code"
	if is_walking():
		if is_standing_up():
			note = "IT'S GETTING UP..."
		elif drones_up():
			note = "DRONES UP: shoot them down! It shrugs off hits while they fly"
		else:
			note = "OPEN FIRE!"
	elif is_open():
		note = "WALL DOWN! Open fire: %d" % ceili(open_until - elapsed)
	elif wall_rising():
		note = "WALL RISING: get outside it! %d" % ceili(rise_at - elapsed)
	elif not squads_game:
		if stage() == 0:
			note = "WALLED IN: find the lock in the wall and pick it. Press when the needle's in the gold"
		else:
			note = "WALLED IN: find the keypad in the wall, stand still at it and enter the code"
	else:
		var left := maxi(need - done_squads.size(), 1)
		if done_squads.is_empty() and not _local_done:
			note = "WALLED IN: %d squads must do their %s" % [need, station]
		elif our_code_done():
			note = "Your %s is done: %d more squad%s must do theirs" % [station, left,
				"" if left == 1 else "s"]
		else:
			var names := done_squads.map(func(s: int) -> String: return Squads.SQUAD_NAMES[s])
			note = "%s done: do your %s!" % [" & ".join(PackedStringArray(names)), station]
	if is_enraged():
		note += "  (ENRAGED)"
	return note
