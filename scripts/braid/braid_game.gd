extends GameBase
## Braid mode (called "Campaign" in the UI): each squad crosses its own lane from left to right,
## chased by the tide (scripts/braid/braid_tide.gd), which hurts anyone in it.
##
## A run is BraidTuning.ACTS acts. Each act has its own level
## (scripts/braid/braid_level.gd, laid out from the run's seed by
## scripts/braid/braid_generator.gd): one lane per squad, stacked, split into
## SEGMENTS_PER_ACT segments that each end at a checkpoint gate across every
## lane, then the convergence room every lane opens into. Each checkpoint is
## a shop building (scripts/braid/braid_shop_building.gd) with a metal plate
## before its door and a light per squad: a squad's light turns green (in
## every lane) while one of its players stands on its plate. Once every
## light is green (a squad that's down counts), or the tide reaches the
## checkpoint, the segment is over and squads go into the shop:
##   segment -> summary -> shop -> (every squad ready) -> out the back -> next
## After the act's last segment, the gates open into the room and every squad
## fights the act's boss together (a "round" like a segment, but with no tide:
## the boss's enrage is the clock). Then the boss prize, the shop, and the
## next act's level. Beating the last act's boss wins. As in the arena game,
## the run ends on a score summary that cashes in everyone's unspent
## resources.
##
## Rounds: every segment and boss fight is one round, numbered through the
## run (round_index), which is what the Squads messages count.
##
## A separate scene from the arena game (scripts/game.gd), sharing its
## players, enemies, shop and summary screens (and, through
## scripts/game_base.gd, the code that spawns players, adds enemies, hands
## out drops and shows the end-of-run summary). Differences:
##   - enemies walk around walls by a flow field (BraidLevel.grid, via the
##     enemies' `steering`), and shots stop at walls
##     (scripts/braid/braid_shot_walls.gd) but not window glass,
##   - segment n borrows the enemy mix of standard-run wave
##     BraidTuning.SEGMENT_WAVES[n], stretched to the segment's length and
##     scaled by our own player count; they come out of spawn vents in our
##     lane ahead of the squad, out of the tide, from just behind the squad
##     (off the left of the screen), or through doors in the lane's top and
##     bottom walls (scripts/braid/braid_door.gd), which flash first.
##
## Squads game (one game per squad, scripts/net/squads.gd): the host owns the
## tide's clock (sent like the arena's wave clock), ends each segment for
## everyone, and starts the next once every squad has left the shop. Squads
## swap lanes at junctions (each game seals the junction exits its own squad
## mustn't take: BraidLevel.add_seals), see each other through windows (the
## camera zooms out there and in junctions), can call an airstrike on the
## neighbouring lane from a pad by a window, and can man turrets in gun ports
## that fire into it. scripts/braid/braid_link.gd shows
## the other squads and settles hits and kills. A squad that's wiped out sits
## out the rest of the segment watching another squad (its enemies stay),
## and is back at the next checkpoint with everyone. It's game over only when
## every squad is down at once. Alone (one squad), a wipe ends the run.
##
## Strip test (the Braid dock in the editor, addons/braid_tools/): the editor
## writes DEBUG_FILE and runs this scene, which then plays one strip over and
## over (or one seed, optionally from a later act), restarting itself when
## the run ends.
##
## Vertical slices: twice an act the lanes turn up (once) and down (once)
## for a stretch and back (scripts/braid/braid_level.gd). Places along a lane
## are progress, not x (BraidLevel.progress): the tide, spawning, the camera
## and the HUD all go by it.
##
## Bosses: the arena's bosses, through Braid versions that put them in the
## room (BraidTuning.BRAID_BOSSES, scripts/braid/bosses/).
##
## Class Mods: picked between acts (GameBase._pick_class_mods), as in the
## arena after every boss fight but the last.
##
## Modifiers (scripts/braid/braid_modifiers.gd): optional harder rules picked
## after character select once the Campaign has been won, for a score
## multiplier. Read once at the start (mods) and applied here: elite chance
## and enemy counts in _segment_wave / _boss_wave, tide speed in _build_act,
## spawn shares in _spawn_group, enemy health in _emit_group, drops in
## _drop_resources, hearts and the score multiplier in _prepare_player, and
## the bosses' mortars in their Braid versions (scripts/braid/bosses/).

enum State { RUNNING, CHECKPOINT, WAITING, GAME_OVER, VICTORY }

const Shop := preload("res://scripts/ui/shop.gd")
const BraidTuning := preload("res://scripts/braid/braid_tuning.gd")
const ActTheme := preload("res://scripts/act_theme.gd")
const BraidLevel := preload("res://scripts/braid/braid_level.gd")
const BraidTide := preload("res://scripts/braid/braid_tide.gd")
const BraidHud := preload("res://scripts/braid/braid_hud.gd")
const BraidShotWalls := preload("res://scripts/braid/braid_shot_walls.gd")
const BraidGenerator := preload("res://scripts/braid/braid_generator.gd")
const BraidLink := preload("res://scripts/braid/braid_link.gd")
const BraidFavour := preload("res://scripts/braid/braid_favour.gd")
const BraidShopBuilding := preload("res://scripts/braid/braid_shop_building.gd")
const BraidModifiers := preload("res://scripts/braid/braid_modifiers.gd")
const CharacterClasses := preload("res://scripts/character_classes.gd")
const BossBody := preload("res://scripts/bosses/boss_body.gd")
const BossIntro := preload("res://scripts/bosses/boss_intro.gd")

## Written by the Braid dock to test a strip or a seed: [test] strip = name,
## seed = int, act = 1-based act to start at (a strip test is one act, drawn
## in that act's art), written = unix time. Ignored when older than DEBUG_FILE_MAX_AGE
## seconds (a test that never started).
const DEBUG_FILE := "user://braid_test.cfg"
const DEBUG_FILE_MAX_AGE := 120.0
## A strip test repeats the strip to about this length per segment.
const DEBUG_SEGMENT_LENGTH := 2560.0

## A player counts as on a checkpoint plate this far off its edge.
const PLATE_REACH := 6.0
## Seconds between every checkpoint light turning green and the shop.
const SHOP_UNLOCK_DELAY := 0.75
## Where squads start the run, and after a checkpoint (this far past the gate).
const START_X := 160.0
const AFTER_GATE := 48.0
## Up to this far (px) off its spot, so no two enemies spawn exactly stacked.
const SPAWN_JITTER := 4.0
## A group comes out spread this far apart (px, roughly; see _group_spots).
const SPAWN_SPACING := 24.0
## What enemies' bodies can't pass (_confine keeps their middles out of it).
const BODY_BLOCKERS := BraidTuning.WALL_LAYER | BraidTuning.WINDOW_LAYER
## A stuck enemy that gets stuck this many times in a row (see _steer) also
## edges sideways, this much (1 = as much as forward).
const UNSTICK_SIDESTEP_AFTER := 3
const UNSTICK_SIDESTEP := 0.7
## A stuck enemy picks a new waypoint (BraidGrid.waypoint_ahead) this often.
const UNSTICK_REPLAN_FRAMES := 10
## The tide spawns enemies this far in front of itself.
const TIDE_SPAWN_AHEAD := 20.0
## Squads game: how far a joiner's own clock may drift from the host's
## (sent every CLOCK_SYNC_INTERVAL) before it jumps instead of easing.
const CLOCK_SNAP := 0.5
## The camera zooms out this far ahead of a junction (and stays out a little
## past it).
const ZOOM_LEAD := 200.0
## max_player_spread keeps players this much (world px, per edge) further in
## than the camera frames them, so their spread can't nudge the zoom out.
const SPREAD_SLACK := 1.0

## How a squad's player count scales its enemies: Braid's own table, so tuning
## it never changes the arena game's (which uses the wave set's).
@export var player_scaling: PlayerScaling = preload("res://data/braid/braid_player_scaling.tres")

var level: BraidLevel
var tide: BraidTide
var braid_hud: BraidHud
var state := State.RUNNING
## The act, and the segment of it being played (0-based; SEGMENTS_PER_ACT
## is its boss fight).
var act := 0
## The act the run started at: 0, unless a Braid dock seed test started it
## later (then it plays as act 1 for difficulty, in that act's art).
var _start_act := 0
var segment := 0
## How many acts this run has (1 for a strip test, which has no boss).
var acts := BraidTuning.ACTS
## The boss fight going on (scripts/bosses/boss.gd, Braid version), or null.
var boss: Node2D
## Its enemies (a stretched copy of a standard-run wave: _segment_wave).
var segment_wave: WaveDefinition
## Squads game: which squad we are (0 alone).
var my_squad := 0
## Squads in lane order at the start (lane k starts with squad lane_order[k]),
## and the lane ours started in. Each act the lanes rotate (act_lane).
var lane_order: Array = [0]
var start_lane := 0
## Our squad is wiped out until the next checkpoint (squads game).
var squad_out := false
## Spectating while out: the squad we're watching.
var _watching := -1
## The run's seed, and the strip test going on ({} = none: see DEBUG_FILE).
var run_seed := 0
var _debug := {}
## The run's modifiers (BraidModifiers ids): the host's in a squads game.
var mods: Array = []

var _schedule: Array[Dictionary] = []
var _next_spawn := 0
## Seconds into the segment: drives spawning and (from where it started) the
## tide. The host's in a squads game.
var _clock := 0.0
## Seconds left of an act's opening calm (see BraidTuning.START_CALM_TIME).
var _start_calm := 0.0
var _tide_start := 0.0
var _segment_start_stats := {}
var _flow_timer := 0.0
var _clock_sync_timer := 0.0
## Our squad's checkpoint light (BraidShopBuilding.Light; sent to the host
## when it changes).
var _plate_state: int = BraidShopBuilding.Light.WAITING
## Host: {squad: [round index, BraidShopBuilding.Light]} as each squad said.
var _squad_plates := {}
## The lights as last shown (host: as last sent).
var _lights := {}
## Every light is green: the segment ends (host, or a squad alone) when this
## runs out. -1 = not yet.
var _unlock_timer := -1.0


func _ready() -> void:
	# Run straight from the editor (or the Braid dock): every controller, or
	# the keyboard if none is plugged in; a fresh seed.
	if Global.players.is_empty():
		Global.players = _default_players()
		if Global.players.size() > 1:
			Global.players = Global.players.filter(func(p: Dictionary) -> bool:
				return p["device"] != Global.KEYBOARD)
			for i in Global.players.size():
				Global.players[i]["slot"] = i
				Global.players[i]["character"] = i
		Global.run_seed = randi()
	_setup_pixel_view()
	if wave_set == null:
		wave_set = load(DEFAULT_WAVE_SET)
	DifficultyCurve.apply(wave_set)

	squads_game = Squads.in_game()
	if squads_game:
		my_squad = Squads.my_squad()
		lane_order = Squads.squads_present()
		lane_order.sort()
		start_lane = maxi(lane_order.find(my_squad), 0)

	# Strip tests only come from the Braid dock, in the editor.
	_debug = _read_debug_file() if OS.has_feature("editor") and not squads_game else {}
	run_seed = int(_debug.get("seed", Global.run_seed))
	mods = Global.current_modifiers().duplicate()
	if not _debug.get("strip", "").is_empty():
		acts = 1
	print_verbose("Braid: seed %d, %d lane(s), we're in lane %d" % [
		run_seed, lane_order.size(), start_lane + 1])

	tide = BraidTide.new()
	tide.name = "Tide"
	add_child(tide)
	tide.pickups_swallowed.connect(_on_tide_pickups)
	add_child(BraidShotWalls.new())
	braid_hud = BraidHud.new()
	add_child(braid_hud)
	# A seed test can start at a later act (the Braid dock's "Act"), to look
	# at that act's art; a strip test (one act) only takes on its art.
	# Its difficulty is still act 1's (see _difficulty_act).
	_start_act = clampi(int(_debug.get("act", 1)) - 1, 0, acts - 1)
	_build_act(_start_act)

	_spawn_players(level.bounds)
	_place_players(START_X)
	_add_pause_menu()

	if squads_game:
		Squads.wave_clock.connect(_on_host_clock)
		Squads.wave_ended.connect(_on_host_segment_ended)
		Squads.wave_begin.connect(_on_squads_segment_begin)
		Squads.all_squads_down.connect(_on_all_squads_down)
		Squads.final_results.connect(_on_squad_final_results)
		var braid_link := BraidLink.new()
		braid_link.setup(self)
		add_child(braid_link)
		link = braid_link
		for player in all_players:
			player.shot_fired.connect(link.report_shot)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	_start_segment(0)


func _exit_tree() -> void:
	super()
	ActTheme.reset()  # The arena game always uses the default art.


## The part of the world on screen.
func view_rect() -> Rect2:
	var size := view_size() / world_zoom()
	return Rect2(camera.global_position - size / 2.0, size)


func is_wave_running() -> bool:
	return state == State.RUNNING


## Players can't walk further apart than this (character_body.gd): what the
## camera shows right now, less BraidTuning.SCREEN_MARGIN at each edge (and a
## hair more, so walking to the limit never makes the camera zoom out). Zoomed
## out (a junction, window, slice or the room) they can spread further; as the
## camera zooms back in, the limit shrinks with it (_update_camera won't zoom
## in past what fits them, so nobody is pushed).
func max_player_spread() -> Vector2:
	return view_size() / world_zoom() - Vector2.ONE * (BraidTuning.SCREEN_MARGIN + SPREAD_SLACK) * 2.0


## The round being played, counted through the run (segments and boss
## fights): what the Squads messages go by.
func round_index() -> int:
	return act * (BraidTuning.SEGMENTS_PER_ACT + 1) + segment


## The act whose difficulty is played: the act, less any acts a Braid dock
## seed test skipped (that test starts at act 1's difficulty).
func _difficulty_act() -> int:
	return act - _start_act


func is_boss_round() -> bool:
	return segment == BraidTuning.SEGMENTS_PER_ACT


## True while our squad is in (or at) the convergence room.
func in_room() -> bool:
	return level.room.has_area() and _squad_s() >= level.room_start - BraidTuning.SCREEN_WIDTH / 4.0


# --- Acts ------------------------------------------------------------------------

## Builds act `a`'s level (replacing the last one).
func _build_act(a: int) -> void:
	act = a
	# Before the level is built: its pieces, and the act's enemies, take
	# their art from the act's theme (act 2: ocean).
	# A strip test is one act, drawn in the art of the act the dock picked.
	ActTheme.set_act(int(_debug.get("act", 1)) - 1 if _debug.has("strip") else a)
	Global.play_theme_music(ActTheme.current)
	if level:
		remove_child(level)
		level.queue_free()
	level = BraidLevel.new()
	level.name = "Level"
	add_child(level)
	move_child(level, 0)
	var layout := _debug_layout(_debug.get("strip", ""))
	if layout.is_empty():
		layout = BraidGenerator.act_layout(run_seed, a, BraidTuning.SEGMENTS_PER_ACT, lane_order.size())
	for problem in level.build(layout, acts > 1 or _debug.is_empty()):
		push_warning("Braid level (act %d): %s" % [a + 1, problem])
	level.add_seals(act_lane(), _squad_color(my_squad))
	level.set_shop_squads(lane_order, lane_order.map(_squad_color))
	for plate in level.favours:
		plate.triggered.connect(_on_favour)
	for turret in level.turrets:
		turret.game = self
	if _mod("riptide"):
		level.tide_speed_scale = BraidModifiers.TIDE_SPEED_MULT
	tide.level = level
	# Each act's level is its own length: keep players inside this one.
	for player in all_players:
		player.move_bounds = level.bounds
	var end := level.room_start + BraidTuning.ROOM_LENGTH if level.room.has_area() \
		else level.gate_x(level.segment_count() - 1)
	braid_hud.set_act(0.0, end, level)
	if link:
		link.new_act()


## The lane our squad starts this act in: squads rotate one lane each act, so
## everyone gets turns in the inner lanes.
func act_lane() -> int:
	return posmod(start_lane + act, lane_order.size())


# --- Lanes -------------------------------------------------------------------------

## The lane our squad is in now.
func my_lane() -> int:
	return level.lane_at(act_lane(), _squad_s())


## The squad in lane `lane` at x (-1 if none).
func squad_in_lane(lane: int, x: float) -> int:
	for k in lane_order.size():
		if level.lane_at(posmod(k + act, lane_order.size()), x) == lane:
			return lane_order[k]
	return -1


## Where our enemies may go after other squads' players: junction rooms and
## the convergence room.
func chase_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for j in level.junctions:
		out.append(Rect2(j["x0"], j["pair"] * BraidTuning.BAND_HEIGHT, j["x1"] - j["x0"],
			BraidTuning.BAND_HEIGHT * 2.0))
	if level.room.has_area():
		out.append(level.room)
	return out


func _squad_color(squad: int) -> Color:
	return Squads.SQUAD_COLORS[squad] if squad >= 0 and squad < Squads.SQUAD_COLORS.size() else Color.WHITE


# --- Segments ----------------------------------------------------------------------

func _start_segment(i: int) -> void:
	segment = i
	state = State.RUNNING
	squad_out = false
	_watching = -1
	_plate_state = BraidShopBuilding.Light.WAITING
	_lights = {}
	_unlock_timer = -1.0
	hud.hide_notice()
	if is_boss_round():
		_start_boss()
		return
	tide.visible = true
	_tide_start = level.segment_start(i) - BraidTuning.TIDE_START_GAP
	var stop := level.gate_x(i) - BraidTuning.TIDE_GATE_STOP
	tide.reset(_tide_start, stop)
	segment_wave = _segment_wave(_difficulty_act() * BraidTuning.SEGMENTS_PER_ACT + i, level.tide_time(_tide_start, stop))
	_schedule = segment_wave.build_spawn_schedule(all_players.size(), player_scaling)
	_next_spawn = 0
	_clock = 0.0
	_flow_timer = 0.0
	_clock_sync_timer = 0.0
	# An act's start strip is safe: nothing spawns until the squad leaves it.
	_start_calm = BraidTuning.START_CALM_TIME if i == 0 and level.start_end > 0.0 else 0.0
	_segment_start_stats.clear()
	for player in all_players:
		_segment_start_stats[player] = {
			"kills": player.kills, "points": player.points, "resources": player.resources,
		}
		player.wave_enemy_health = segment_wave.enemy_health_multiplier
		player.recharge_equipment()
	_update_flow()
	_update_camera(1.0)
	get_tree().paused = false
	pause_menu.enabled = true
	var n := level.segment_count()
	hud.set_wave_label(("ACT %d   CHAPTER %d / %d" % [act + 1, i + 1, n]) if acts > 1
		else "CHAPTER %d / %d" % [i + 1, n])
	braid_hud.set_bar_visible(true)
	var subtitle := segment_wave.display_name
	if i == 0:
		subtitle = "Reach the checkpoint before the tide"
		if lane_order.size() > 1:
			subtitle = "Lane %d of %d. Reach the checkpoint before the tide" % [act_lane() + 1, lane_order.size()]
		if act == 0 and not mods.is_empty():
			subtitle += "\nModifiers: %s" % BraidModifiers.names(mods)
	var title := "CHAPTER %d" % (i + 1)
	if i == 0 and acts > 1:
		title = "ACT %d" % (act + 1)
	braid_hud.show_banner(title, subtitle)
	_update_hud()


## The act's boss fight: the gates are open, our squad is at the lane mouths,
## and the boss is in the room.
func _start_boss() -> void:
	tide.visible = false
	Global.play_theme_music(ActTheme.current, true)
	segment_wave = _boss_wave(act)
	_schedule = segment_wave.build_spawn_schedule(all_players.size(), player_scaling)
	_next_spawn = 0
	_clock = 0.0
	_flow_timer = 0.0
	_clock_sync_timer = 0.0
	_segment_start_stats.clear()
	for player in all_players:
		_segment_start_stats[player] = {
			"kills": player.kills, "points": player.points, "resources": player.resources,
		}
		player.wave_enemy_health = segment_wave.enemy_health_multiplier
		player.recharge_equipment()
	var id := segment_wave.boss_id
	boss = load(BraidTuning.BRAID_BOSSES[id]).new()
	boss.info = Boss.boss_info(id)
	boss.setup(self, round_index(), segment_wave)
	add_child(boss)
	hud.show_boss(boss)
	hud.set_wave_label("ACT %d   BOSS" % (act + 1))
	braid_hud.set_bar_visible(false)
	braid_hud.show_banner(boss.info["name"].to_upper(), boss.info["summary"], boss.info["color"])
	_update_flow()
	_update_camera(1.0)
	get_tree().paused = false
	pause_menu.enabled = true
	_update_hud()


## Act `a`'s boss fight: a copy of standard-run wave BOSS_WAVES[a]. If its
## boss has no Braid version yet, FALLBACK_BOSS stands in, with its own
## wave's health scaled up by how much tougher this act's enemies are. Its
## adds are scaled by BraidTuning.BOSS_ADD_MULTIPLIER.
func _boss_wave(a: int) -> WaveDefinition:
	var base: WaveDefinition = wave_set.waves[BraidTuning.BOSS_WAVES[mini(a, BraidTuning.BOSS_WAVES.size() - 1)]]
	var wave: WaveDefinition = base.duplicate()
	var d := a - _start_act
	if d != a:
		# A dock seed test started at a later act: act `a`'s boss, but as tough
		# as act `d`'s (its health scaled the way that act's enemies are).
		var easier: WaveDefinition = wave_set.waves[BraidTuning.BOSS_WAVES[mini(d, BraidTuning.BOSS_WAVES.size() - 1)]]
		wave.boss_health = roundi(base.boss_health * easier.enemy_health_multiplier
			/ maxf(base.enemy_health_multiplier, 0.01))
		wave.enemy_health_multiplier = easier.enemy_health_multiplier
		wave.enemy_speed_multiplier = easier.enemy_speed_multiplier
		wave.base_elite_chance = easier.base_elite_chance
		base = wave.duplicate()
	if not BraidTuning.BRAID_BOSSES.has(wave.boss_id):
		wave.boss_id = BraidTuning.FALLBACK_BOSS
		for i in BraidTuning.BOSS_WAVES:
			var own: WaveDefinition = wave_set.waves[i]
			if own.boss_id == BraidTuning.FALLBACK_BOSS:
				wave.boss_health = roundi(own.boss_health * base.enemy_health_multiplier
					/ maxf(own.enemy_health_multiplier, 0.01))
				break
	if _mod("tyrants") and wave.boss_health > 0:
		wave.boss_health = roundi(wave.boss_health * BraidModifiers.BOSS_HEALTH_MULT)
	if _mod("champions"):
		wave.base_elite_chance += BraidModifiers.ELITE_CHANCE_BONUS
	var adds: float = BraidTuning.BOSS_ADD_MULTIPLIER.get(wave.boss_id, 1.0)
	if _mod("horde"):
		adds *= BraidModifiers.ENEMY_COUNT_MULT
	if adds != 1.0:
		# duplicate() shares the wave set's groups: copy them before scaling.
		var groups: Array[WaveEnemyGroup] = []
		for g in wave.enemy_groups:
			if g == null:
				continue
			var copy: WaveEnemyGroup = g.duplicate()
			copy.count = roundi(g.count * adds)
			groups.append(copy)
		wave.enemy_groups = groups
		wave.opening_spawn = roundi(wave.opening_spawn * adds)
	return wave


## Segment `i`'s enemies: standard-run wave SEGMENT_WAVES[i] with its counts
## stretched from its own duration to the segment's (`seconds`), times
## ENEMY_DENSITY. A fresh copy: the wave set's resources are left alone.
func _segment_wave(i: int, seconds: float) -> WaveDefinition:
	var waves := BraidTuning.SEGMENT_WAVES
	var base: WaveDefinition = wave_set.waves[waves[mini(i, waves.size() - 1)]]
	var stretch := seconds / maxf(base.duration, 1.0) * BraidTuning.ENEMY_DENSITY
	if _mod("horde"):
		stretch *= BraidModifiers.ENEMY_COUNT_MULT
	var wave := WaveDefinition.new()
	wave.display_name = base.display_name
	wave.duration = seconds
	wave.opening_spawn = base.opening_spawn
	wave.spawn_window = base.spawn_window
	wave.enemy_health_multiplier = base.enemy_health_multiplier
	wave.enemy_speed_multiplier = base.enemy_speed_multiplier
	wave.base_elite_chance = base.base_elite_chance
	if _mod("champions"):
		wave.base_elite_chance += BraidModifiers.ELITE_CHANCE_BONUS
	wave.completion_bonus = base.completion_bonus
	wave.bonus_hearts = base.bonus_hearts
	var groups: Array[WaveEnemyGroup] = []
	for g in base.enemy_groups:
		if g == null or g.enemy_scene == null:
			continue
		var copy := WaveEnemyGroup.new()
		copy.enemy_scene = g.enemy_scene
		copy.count = maxi(roundi(g.count * stretch), 1) if g.count > 0 else 0
		copy.health_multiplier = g.health_multiplier
		copy.speed_multiplier = g.speed_multiplier
		copy.cluster = g.cluster
		copy.allow_elite = g.allow_elite
		groups.append(copy)
	wave.enemy_groups = groups
	return wave


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		return
	_clock += delta
	if _start_calm > 0.0:
		_start_calm -= delta
		if _squad_s() >= level.start_end:
			_start_calm = 0.0
	# (Held spawns come out together once the calm ends: the opening burst,
	# just as the squad heads into the first real strip.)
	if not squad_out and _unlock_timer < 0.0 and _start_calm <= 0.0:
		while _next_spawn < _schedule.size() and _schedule[_next_spawn]["time"] <= _clock:
			var entry: Dictionary = _schedule[_next_spawn]
			_next_spawn += 1
			_spawn_group(entry["group"], entry["elite"], entry["count"])
	if boss:
		_boss_tick()
		return
	_check_plate()
	if _unlock_timer >= 0.0:
		_unlock_timer -= delta
		if _unlock_timer < 0.0 and (not squads_game or Squads.is_host()):
			_end_segment()
			return
	tide.update(level.tide_after(_tide_start, _clock, tide.stop_x), delta, all_players)
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = BraidTuning.FLOW_INTERVAL
		_update_flow()
	if squads_game and Squads.is_host():
		_clock_sync_timer -= delta
		if _clock_sync_timer <= 0.0:
			_clock_sync_timer = CLOCK_SYNC_INTERVAL
			Squads.send_wave_clock(round_index(), _clock)
	# The host (or a squad alone) ends the segment when the tide arrives.
	if tide.reached_stop() and (not squads_game or Squads.is_host()):
		_end_segment()


## Host (or a squad alone): the segment's over, for everyone.
func _end_segment() -> void:
	if squads_game:
		Squads.end_wave(round_index())
	_reach_checkpoint()


## Our squad's checkpoint light: OUT if we're down, ON_PLATE while any of
## our standing players is on the plate in the lane we'll be in there.
func _squad_plate_state() -> int:
	if squad_out:
		return BraidShopBuilding.Light.OUT
	# A dummy squad (scripts/net/dummy_squad.gd) stands still: it never holds
	# up the shop.
	if Global.dummy_squad:
		return BraidShopBuilding.Light.ON_PLATE
	var gate := level.gate_x(segment)
	var plate := level.plate_rect(segment, level.lane_at(act_lane(), gate)).grow(PLATE_REACH)
	for p: Node2D in _living_players():
		if plate.has_point(p.global_position):
			return BraidShopBuilding.Light.ON_PLATE
	return BraidShopBuilding.Light.WAITING


## Keeps our light up to date: shown at once alone, else told to the host,
## which lights every squad's checkpoint the same (on_shop_lights).
func _check_plate() -> void:
	var here := _squad_plate_state()
	if here != _plate_state:
		_plate_state = here
		if not squads_game:
			_show_lights({my_squad: here})
		elif Squads.is_host():
			_on_squad_plate(my_squad, round_index(), here)
		else:
			Squads.send_mode_message(0, ["gate", round_index(), here])
	if squads_game and Squads.is_host():
		_send_lights()  # squads come and go


## Host: a squad's light for round `index`.
func _on_squad_plate(squad: int, index: int, here: int) -> void:
	_squad_plates[squad] = [index, here]
	_send_lights()


## Host: every squad's light this round, to everyone (when it changes).
func _send_lights() -> void:
	if state != State.RUNNING or boss or _unlock_timer >= 0.0:
		return
	var lights := {}
	for squad in Squads.squads_present():
		var said: Array = _squad_plates.get(squad, [-1, 0])
		lights[squad] = said[1] if said[0] == round_index() else BraidShopBuilding.Light.WAITING
	if lights == _lights:
		return
	Squads.send_mode_message(-1, ["lights", round_index(), lights])
	_show_lights(lights)


## Squads game: the host's lights for round `index`.
func on_shop_lights(index: int, lights: Dictionary) -> void:
	if index == round_index() and state == State.RUNNING and not boss:
		_show_lights(lights)


## Lights segment `segment`'s checkpoints; all green starts the unlock
## (and then they stay as they are).
func _show_lights(lights: Dictionary) -> void:
	if _unlock_timer >= 0.0:
		return
	_lights = lights
	level.set_shop_lights(segment, lights)
	for squad in lights:
		if lights[squad] == BraidShopBuilding.Light.WAITING:
			return
	_unlock_timer = SHOP_UNLOCK_DELAY
	braid_hud.show_banner("SHOP OPEN", "Every squad is at the checkpoint", Color(0.45, 0.95, 0.45))


## A physics frame of the boss fight: enemies keep trickling in (the boss
## wave's schedule, over and over), and the host (or a squad alone) ends the
## round once the boss is dead.
func _boss_tick() -> void:
	if _next_spawn >= _schedule.size():
		var offset := _clock + 3.0
		_schedule = segment_wave.build_spawn_schedule(all_players.size(), player_scaling)
		for entry in _schedule:
			entry["time"] += offset
		_next_spawn = 0
	boss.elapsed = _clock
	_flow_timer -= get_physics_process_delta_time()
	if _flow_timer <= 0.0:
		_flow_timer = BraidTuning.FLOW_INTERVAL
		_update_flow()
	if not squads_game or Squads.is_host():
		if squads_game:
			_clock_sync_timer -= get_physics_process_delta_time()
			if _clock_sync_timer <= 0.0:
				_clock_sync_timer = CLOCK_SYNC_INTERVAL
				Squads.send_wave_clock(round_index(), _clock)
		if boss.outcome() == Objective.Outcome.SUCCESS:
			if squads_game:
				Squads.end_wave(round_index())
			_reach_checkpoint()


## Squads game: the host's clock for segment `index`.
func _on_host_clock(index: int, elapsed: float) -> void:
	if index != round_index() or state != State.RUNNING:
		return
	if absf(elapsed - _clock) > CLOCK_SNAP:
		_clock = elapsed
	else:
		_clock = lerpf(_clock, elapsed, 0.3)


func _on_host_segment_ended(index: int, _failed: bool) -> void:
	if index == round_index() and state == State.RUNNING:
		_reach_checkpoint()


func _on_squads_segment_begin(index: int) -> void:
	if state == State.WAITING and index == round_index() + 1:
		_open_and_start()


func _on_all_squads_down(index: int) -> void:
	if index == round_index() and state == State.RUNNING:
		_game_over("Every squad fell in %s  (seed %d)" % [_where(), run_seed])


func _process(delta: float) -> void:
	if squad_out:
		_read_spectate_input()
	_update_camera(1.0 - exp(-CAMERA_SPEED * delta))
	if state == State.RUNNING:
		_update_hud()


func _update_hud() -> void:
	if boss:
		hud.set_wave_time(_clock, false)
		return
	hud.set_wave_time(tide.time_left())
	var others := []
	if link:
		var positions: Dictionary = link.squad_positions()
		for squad in positions:
			others.append({"x": level.progress(positions[squad]["pos"]), "color": _squad_color(squad),
				"alive": positions[squad]["alive"]})
	braid_hud.update_bar(tide.front, all_players, others, level.progress)


## The flow field our enemies follow, from our living players, over the
## stretch from the tide to a way ahead of the squad.
func _update_flow() -> void:
	var sources: Array = []
	for p: Node2D in _living_players():
		sources.append(p.global_position)
	if sources.is_empty():
		return
	var squad := _squad_s()
	var span := level.flow_range(
		minf(tide.front - BraidTuning.FLOW_CELL * 2.0, squad - BraidTuning.FLOW_BEHIND),
		squad + BraidTuning.FLOW_AHEAD)
	level.grid.update_flow(sources, span.x, span.y)


## Given to every enemy as its `steering` (chasesplayer.gd): around walls
## toward our players, straight at anything else (decoys, other squads'
## players in a junction).
## An enemy that's been stuck (chasesplayer.gd's unstick_left) looks further
## down the field for a way its body fits (BraidGrid.waypoint_ahead), and if it
## keeps getting stuck (against other enemies, say) it edges sideways too.
func _steer(enemy: Node2D, target: Node2D) -> Vector2:
	if not target.is_in_group("players"):
		return enemy.global_position.direction_to(target.global_position)
	if enemy.unstick_left <= 0.0:
		return level.grid.steer(enemy.global_position, target.global_position)
	# Plan a few times a second (or on reaching the waypoint), not every frame.
	var frame := Engine.get_physics_frames()
	if frame - enemy.unstick_planned >= UNSTICK_REPLAN_FRAMES or enemy.unstick_waypoint == Vector2.INF \
			or enemy.global_position.distance_squared_to(enemy.unstick_waypoint) < 64.0:
		enemy.unstick_planned = frame
		enemy.unstick_waypoint = level.grid.waypoint_ahead(enemy.global_position,
			target.global_position, enemy.half_extent())
	if enemy.unstick_waypoint == Vector2.INF:
		return level.grid.steer(enemy.global_position, target.global_position)
	var dir: Vector2 = enemy.global_position.direction_to(enemy.unstick_waypoint)
	if enemy.stuck_count >= UNSTICK_SIDESTEP_AFTER:
		# Which side flips each time it gets stuck again.
		var side := 1.0 if (enemy.stuck_count + enemy.get_instance_id()) % 2 == 0 else -1.0
		dir = (dir + dir.orthogonal() * side * UNSTICK_SIDESTEP).normalized()
	return dir


func _living_players() -> Array[Node]:
	return all_players.filter(func(p: Node) -> bool: return not p.is_dead())


## Average y of our living players (or of all of them, if none are).
func _squad_y() -> float:
	var nodes := _living_players()
	if nodes.is_empty():
		nodes = all_players
	var sum := 0.0
	for n: Node2D in nodes:
		sum += n.global_position.y
	return sum / maxf(nodes.size(), 1.0)


## Average progress along their lanes (BraidLevel.progress) of our living
## players (or of all of them, if none are).
func _squad_s() -> float:
	var nodes := _living_players()
	if nodes.is_empty():
		nodes = all_players
	var sum := 0.0
	for n: Node2D in nodes:
		sum += level.progress(n.global_position)
	return sum / maxf(nodes.size(), 1.0)


## Progress at the edge of the screen behind (`side` -1) or ahead (+1): the
## nearest place along our lane, from the middle of the screen, past which it's
## all off screen (where the lane runs right, about the screen's left or right
## edge).
func _view_edge(side: int) -> float:
	var view := view_rect()
	var lane := my_lane()
	var s := level.progress(level.clamp_to_lane(view.get_center(), lane))
	var wall := BraidTuning.OUTER_WALL
	for i in 400:
		s += BraidTuning.FLOW_CELL * side
		var seen := false
		for v in [wall, BraidTuning.BAND_HEIGHT / 2.0, BraidTuning.BAND_HEIGHT - wall]:
			if view.has_point(level.point_at(lane, s, v)):
				seen = true
				break
		if not seen:
			break
	return s


# --- Checkpoints and the end -------------------------------------------------------

func _reach_checkpoint() -> void:
	state = State.CHECKPOINT
	# A boss fight's kill points and time, before the boss goes.
	var boss_points := 0
	var boss_note := ""
	if boss and boss.is_defeated():
		boss_points = boss.kill_points()
		boss_note = "%s defeated in %s" % [boss.info["name"], _clock_text(boss.clear_time())]
	_clear_field()
	braid_hud.hide_banner()
	braid_hud.set_bar_visible(false)
	hud.hide_notice()
	hud.hide_boss()
	hud.set_wave_time(0.0)
	pause_menu.close()
	pause_menu.enabled = false
	get_tree().paused = true

	var bonus := segment_wave.reward()
	for player in all_players:
		player.add_points(boss_points)
	var rows := _summary_rows()
	var was_out := squad_out
	for player in all_players:
		player.add_resources(bonus)
		if segment_wave.bonus_hearts > 0:
			player.change_attribute("lives", segment_wave.bonus_hearts)
		player.restore_all_lives()  # also revives knocked-out players
	squad_out = false

	var last_round := act == acts - 1 and segment == _last_segment_of_act()
	if last_round:
		state = State.VICTORY
		if acts == BraidTuning.ACTS and _debug.is_empty():
			Global.mark_campaign_cleared()
		var won := "All %d acts crossed" % acts if acts > 1 else "All %d chapters crossed" % level.segment_count()
		var summary := _show_final_summary("VICTORY!", Color(1, 0.85, 0.3),
			"%s  (seed %d)%s" % [won, run_seed, _modifiers_note()], bonus, _end_prompt("{A}"))
		await summary.continued
		if squads_game and not Squads.is_host():
			hud.show_notice("Waiting for the host...")
			return
		_leave()
		return

	var n := level.segment_count()
	var summary := WaveSummary.new()
	# B, not A: a second player still mashing A from the fight would
	# otherwise skip this and buy something in the shop by accident.
	summary.back_only = true
	add_child(summary)
	if is_boss_round():
		summary.show_summary("BOSS DEFEATED", Color(1.0, 0.85, 0.3), boss_note, rows, bonus,
			"Press {B} to continue to the shop", segment_wave.bonus_hearts)
	elif was_out:
		summary.show_summary("CHECKPOINT %d / %d" % [segment + 1, n], Color(1.0, 0.6, 0.3),
			"Your squad fell, but the others made it. You're back in!", rows, bonus,
			"Press {B} to continue to the shop", segment_wave.bonus_hearts)
	else:
		summary.show_summary("CHECKPOINT %d / %d" % [segment + 1, n], Color(0.45, 0.95, 0.45),
			"Chapter %d crossed" % (segment + 1), rows, bonus,
			"Press {B} to continue to the shop", segment_wave.bonus_hearts)
	await summary.continued

	# After a boss: every player picks a Class Mod.
	if is_boss_round():
		await _pick_class_mods(run_seed + act * 7 + my_squad * 101,
			"ACT %d CLEARED: CLASS MOD" % (act + 1))

	# What's next, for the shop: its enemy health (equipment scales to it),
	# its prices, and its name.
	var next_act := act
	var next_seg := segment + 1
	if segment == _last_segment_of_act():
		next_act += 1
		next_seg = 0
	var next_wave: WaveDefinition
	var price_wave: int
	var heading: String
	if next_seg == BraidTuning.SEGMENTS_PER_ACT:
		price_wave = BraidTuning.BOSS_WAVES[mini(next_act - _start_act, BraidTuning.BOSS_WAVES.size() - 1)]
		next_wave = _boss_wave(next_act)
		heading = "Next: BOSS  -  %s" % Boss.boss_info(next_wave.boss_id)["name"]
	else:
		var g := mini((next_act - _start_act) * BraidTuning.SEGMENTS_PER_ACT + next_seg, BraidTuning.SEGMENT_WAVES.size() - 1)
		price_wave = BraidTuning.SEGMENT_WAVES[g]
		next_wave = wave_set.waves[price_wave]
		heading = "Next: Act %d, chapter %d / %d" % [next_act + 1, next_seg + 1, n] if acts > 1 \
			else "Next: Chapter %d / %d" % [next_seg + 1, n]
	var shop := Shop.new()
	add_child(shop)
	for player in all_players:
		player.wave_enemy_health = next_wave.enemy_health_multiplier
	shop.open(all_players, next_seg, n, maxi(price_wave, 1), "", heading)
	await shop.all_ready

	# Before a boss: its entrance (everyone sees it before saying they're ready).
	if next_seg == BraidTuning.SEGMENTS_PER_ACT:
		var intro := BossIntro.new()
		add_child(intro)
		intro.play(self, camera, next_wave.boss_id, level.arena.get_center(), "Act %d" % (act + 1))
		await intro.finished

	if squads_game:
		state = State.WAITING
		show_waiting_campfire("Waiting for the other squads...")
		Squads.report_ready_for_wave(round_index() + 1)
		return
	_open_and_start()


## The act's last round: its boss fight, or (a strip test, no room) its last
## segment.
func _last_segment_of_act() -> int:
	return BraidTuning.SEGMENTS_PER_ACT if level.room.has_area() else level.segment_count() - 1


## Starts the next round: the next segment (through the gates, with our
## squad just past them in whichever lane it's in by then), the boss fight
## (the same, into the room), or the next act's first segment (a new level).
func _open_and_start() -> void:
	hide_waiting_campfire()
	hud.hide_notice()
	if segment == _last_segment_of_act():
		_build_act(act + 1)
		_place_players(START_X)
		_start_segment(0)
		return
	level.open_gate(segment)
	var x := level.gate_x(segment) + BraidLevel.GATE_WIDTH + AFTER_GATE
	_place_players(x)
	_start_segment(segment + 1)


## "chapter 2 of act 3" (or "the act 3 boss fight").
func _where() -> String:
	if is_boss_round():
		return "the act %d boss fight" % (act + 1)
	if acts > 1:
		return "chapter %d of act %d" % [segment + 1, act + 1]
	return "chapter %d of %d" % [segment + 1, level.segment_count()]


## What each player did this segment (before the bonus).
func _summary_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for player in all_players:
		var start: Dictionary = _segment_start_stats.get(player, {"kills": 0, "points": 0, "resources": 0})
		rows.append({
			"player": player,
			"kills": player.kills - start["kills"],
			"points": player.points - start["points"],
			"resources": player.resources - start["resources"],
			"health": player.health,
		})
	return rows


## Enemies vanish, uncollected resources are handed out, shots and
## everything equipment put down disappear.
func _clear_field() -> void:
	_clear_class_mods()
	if boss:
		boss.queue_free()
		boss = null
	if link:
		link.clear_wave()
	_remove_own_enemies()
	for pickup in get_tree().get_nodes_in_group("pickups"):
		pickup.collect()
	for shot in get_tree().get_nodes_in_group("projectiles") + get_tree().get_nodes_in_group("enemy_bullets"):
		shot.queue_free()
	for deployed in get_tree().get_nodes_in_group("deployables"):
		deployed.remove_from_group("decoys")
		deployed.queue_free()


func _remove_own_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		# Not other squads' (mirrors), and not the boss (its bodies are in the
		# group so shots hit them; the boss goes with the round).
		if (enemy is Enemy and enemy.is_mirror) or enemy is BossBody:
			continue
		enemy.remove_from_group("enemies")
		enemy.queue_free()


func _on_player_died(_hit_position: Vector2) -> void:
	if state != State.RUNNING or squad_out or not _living_players().is_empty():
		return
	if not squads_game:
		_game_over("Fell in %s  (seed %d)" % [_where(), run_seed])
		return
	# Out until the next checkpoint. Our enemies stay (they'd all vanish at
	# once otherwise, mid-junction): they only go after other squads' players
	# where they always could (junction rooms, the boss room), and the tide
	# still swallows them. No more spawn for us.
	squad_out = true
	hud.show_notice("Squad down! Back %s.  Left / Right: watch another squad" % [
		"after the boss" if is_boss_round() else "at the next checkpoint"])
	Squads.report_squad_down(round_index())


## Squads game, while out: Left / Right pick which squad to watch.
func _read_spectate_input() -> void:
	var dir := 0
	if Input.is_action_just_pressed("ui_left"):
		dir = -1
	elif Input.is_action_just_pressed("ui_right"):
		dir = 1
	var others: Array = []
	if link:
		others = link.squad_positions().keys()
	others.sort()
	if others.is_empty():
		_watching = -1
		return
	if _watching not in others:
		_watching = others[0]
	if dir != 0:
		_watching = others[posmod(others.find(_watching) + dir, others.size())]


func _game_over(subtitle: String) -> void:
	state = State.GAME_OVER
	braid_hud.hide_banner()
	hud.hide_notice()
	pause_menu.close()
	pause_menu.enabled = false
	get_tree().paused = true
	var summary := _show_final_summary("GAME OVER", Color(1, 0.25, 0.25), subtitle + _modifiers_note(), 0,
		_end_prompt("{B}"), true)
	await summary.continued
	_leave()


func _end_prompt(button: String) -> String:
	if not squads_game:
		return "Press %s to return to menu" % button
	return "Press %s to return everyone to character select" % button if Squads.is_host() \
		else "Waiting for the host...     {B} leave game"


## The run is over: back to the title (alone), character select (squads,
## the host decides), or for a strip test, round again.
func _leave() -> void:
	if squads_game:
		if Squads.is_host():
			Squads.return_to_lobby()
		else:
			Global.go_to_title()  # A joiner pressing back leaves the game.
		return
	if _debug.is_empty():
		Global.go_to_title()
		return
	_write_debug_file(_debug)
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Favours ---------------------------------------------------------------------

## One of our players called an airstrike from a pad.
func _on_favour(plate: Node2D, caller: Node2D) -> void:
	if state != State.RUNNING:
		return
	if link:
		link.send_favour(plate, caller.player_index)
	else:
		BraidFavour.show_crush(self, plate.crush_rect())


## Another squad's Triage shot passed our player `slot`.
func receive_heal(slot: int, amount: int) -> void:
	for player in all_players:
		if player.player_index == slot and not player.is_dead():
			player.heal(amount)


## Objectives call this when our squad fails one; bosses never do.
func squad_failed_objective(_reason: String) -> void:
	pass


## Another squad (`squad`, player `slot` of theirs called it) called an
## airstrike on `rect`: show it; each column of bombs hurts our enemies under
## it as it lands (each enemy once). Its kills are theirs, as their shots'
## are: their points, and the drops come out in their lane (braid_link.gd).
func receive_favour(rect: Rect2, squad: int, slot: int) -> void:
	BraidFavour.show_crush(link if link else self, rect, _favour_column.bind({}, squad, slot))


func _favour_column(column: Rect2, already_hit: Dictionary, squad: int, slot: int) -> void:
	if not is_wave_running():
		return
	var damage := roundi(BraidTuning.FAVOUR_DAMAGE * segment_wave.enemy_health_multiplier)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Enemy and not enemy.is_mirror and not already_hit.has(enemy) \
				and column.has_point(enemy.global_position):
			already_hit[enemy] = true
			enemy.take_remote_damage(damage, squad, slot)


# --- Enemies and drops ----------------------------------------------------------

## Where the group comes from: behind the squad, through a door in the
## lane's wall (after it flashes), or ahead / out of the tide (_spawn_point),
## by BraidTuning's spawn shares.
func _spawn_group(group: WaveEnemyGroup, elite: bool, count: int) -> void:
	if not is_boss_round():
		var roll := randf()
		var behind_share := BraidModifiers.AMBUSH_BEHIND_SHARE if _mod("ambush") \
			else BraidTuning.BEHIND_SPAWN_SHARE
		var door_share := BraidModifiers.AMBUSH_DOOR_SHARE if _mod("ambush") \
			else BraidTuning.DOOR_SPAWN_SHARE
		if roll < behind_share:
			var behind := _behind_spawn_point()
			if behind != Vector2.INF:
				_emit_group(group, elite, count, behind)
				return
		elif roll < behind_share + door_share:
			var door := _pick_door()
			if door:
				door.open(_door_warning())
				var seg := round_index()
				# The point, not the door: the level (and its doors) may be
				# gone by then (a new act).
				var exit: Vector2 = door.exit_point()
				get_tree().create_timer(_door_warning(), false).timeout.connect(func() -> void:
					if state == State.RUNNING and not squad_out and round_index() == seg:
						_emit_group(group, elite, count, exit, true))
				return
	_emit_group(group, elite, count, _spawn_point())


## `from_door`: they come out of a door's dark doorway, fading up from black.
func _emit_group(group: WaveEnemyGroup, elite: bool, count: int, at: Vector2,
		from_door := false) -> void:
	for p in _group_spots(at, count):
		var enemy := _add_enemy(group.enemy_scene, p,
			segment_wave.enemy_health_multiplier * group.health_multiplier * _enemy_health_mult(),
			segment_wave.enemy_speed_multiplier * group.speed_multiplier, elite)
		if from_door:
			_emerge(enemy)


## Fades `enemy` up from black (its alpha kept: Braid fades enemies). A
## slow tint it picks up in those few frames is lost.
func _emerge(enemy: Node2D) -> void:
	var tween := enemy.create_tween()
	tween.tween_method(func(v: float) -> void:
		enemy.modulate = Color(v, v, v, enemy.modulate.a),
		0.0, 1.0, BraidTuning.DOOR_EMERGE_TIME)


## Where a group of `count` coming out at `at` stands: spread round it about
## SPAWN_SPACING apart (a sunflower pattern), on open floor in the same lane,
## clear of walls where there's room. Bodies that start piled on each other
## are pushed apart by the physics hard enough to fly off across the screen,
## or (beside a vent or door) right through the lane's wall. Each spot is
## jittered a little: never two enemies exactly stacked (another group may
## come out of this vent too).
func _group_spots(at: Vector2, count: int) -> Array[Vector2]:
	var grid := level.grid
	var step := SPAWN_SPACING / sqrt(PI)
	var turn := randf() * TAU
	var spots: Array[Vector2] = []
	var taken := {}
	# Roomy floor first, then any open floor.
	for need in [2, 1]:
		for k in count * 8:
			if spots.size() >= count:
				return spots
			if taken.has(k):
				continue
			var p := at + Vector2.from_angle(turn + k * 2.39996) * step * sqrt(float(k))
			if grid.clearance(grid.cell_of(p)) >= need and level.same_lane(p, at):
				taken[k] = true
				spots.append(p + Vector2.from_angle(randf() * TAU) * randf_range(1.0, SPAWN_JITTER))
	# No room at all: on the spot (_confine keeps them out of the walls).
	while spots.size() < count:
		spots.append(at + Vector2.from_angle(randf() * TAU) * randf_range(1.0, SPAWN_JITTER))
	return spots


## A spawn vent serving our lane ahead of the squad, just off screen (most of
## the time), or the tide's front in our lane.
func _spawn_point() -> Vector2:
	if is_boss_round():
		return _room_spawn_point()
	var lane := my_lane()
	# The tide only spits enemies out while it's off screen behind us (never
	# on top of the squad, as at a segment's start).
	# (Nor while it's still behind the segment's start: that's the last
	# checkpoint's shop.)
	var tide_hidden := not _tide_on_screen() and _tide_spawn_x() >= level.segment_start(segment)
	if tide_hidden and randf() < BraidTuning.TIDE_SPAWN_SHARE:
		return _tide_spawn_point()
	var limit := level.gate_x(segment) - BraidTuning.SPAWN_GATE_MARGIN
	var ahead := _view_edge(1) + BraidTuning.SPAWN_SCREEN_MARGIN
	var seen := view_rect().grow(BraidTuning.SPAWN_SCREEN_MARGIN)
	var vents := level.vents_between(lane, ahead, minf(_squad_s() + BraidTuning.SPAWN_AHEAD_MAX, limit)).filter(
		func(v: Vector2) -> bool: return not seen.has_point(v))
	if not vents.is_empty():
		return vents.pick_random()
	if tide_hidden:
		return _tide_spawn_point()
	# No vent in reach: just off screen ahead, in our lane there (not past
	# the checkpoint).
	for i in 12:
		var at_x := ahead + i * BraidTuning.FLOW_CELL
		if at_x > limit:
			break
		var p := level.random_open_point_at(level.lane_at(act_lane(), at_x), at_x)
		if p != Vector2.INF and not seen.has_point(p):
			return p
	# The checkpoint's on screen (we're nearly there): from behind instead,
	# not popping up in front of its shop.
	var behind := _behind_spawn_point()
	return behind if behind != Vector2.INF else _tide_spawn_point()


## True if any of the tide's front (or just ahead of it, where it spits
## enemies out) is on screen (or nearly).
func _tide_on_screen() -> bool:
	var seen := view_rect().grow(BraidTuning.SPAWN_SCREEN_MARGIN)
	var wall := BraidTuning.OUTER_WALL
	for s in [tide.front, tide.front + TIDE_SPAWN_AHEAD + BraidTuning.FLOW_CELL]:
		var lane := level.lane_at(act_lane(), s)
		for v in [wall, BraidTuning.BAND_HEIGHT / 2.0, BraidTuning.BAND_HEIGHT - wall]:
			if seen.has_point(level.point_at(lane, s, v)):
				return true
	return false


## Just off the screen behind the squad in our lane, between the tide and the
## squad (Vector2.INF if there's no room: the tide is too close, or the
## segment's start is on screen).
func _behind_spawn_point() -> Vector2:
	var hi := _view_edge(-1) - BraidTuning.SPAWN_SCREEN_MARGIN
	var lo := maxf(tide.front + TIDE_SPAWN_AHEAD + BraidTuning.FLOW_CELL * 2.0,
		level.segment_start(segment) + BraidTuning.FLOW_CELL * 2.0)
	lo = maxf(lo, hi - BraidTuning.BEHIND_SPAWN_DEPTH)
	if hi <= lo:
		return Vector2.INF
	var seen := view_rect().grow(BraidTuning.SPAWN_SCREEN_MARGIN)
	for i in 8:
		var at_x := randf_range(lo, hi)
		var p := level.random_open_point_at(level.lane_at(act_lane(), at_x), at_x)
		# (Round a corner an earlier stretch can be on screen.)
		if p != Vector2.INF and not seen.has_point(p):
			return p
	return Vector2.INF


## A door into our lane that's on screen or just ahead, not too close to any
## of our players, and not already opening (null if none).
func _pick_door() -> Node:
	# (Counting how far the tide comes on while the door flashes.)
	var from_x := maxf(_view_edge(-1), tide.front + BraidTuning.DOOR_TIDE_MARGIN
		+ level.tide_speed_at(tide.front) * _door_warning())
	var to_x := minf(_view_edge(1) + BraidTuning.DOOR_AHEAD,
		level.gate_x(segment) - BraidTuning.SPAWN_GATE_MARGIN)
	var min_d := BraidTuning.DOOR_MIN_PLAYER_DISTANCE
	var choices: Array[Node] = []
	for lane in [level.lane_at(act_lane(), from_x), level.lane_at(act_lane(), to_x)]:
		for door: Node2D in level.doors_between(lane, from_x, to_x):
			if door in choices or door.is_busy() or level.lane_at(act_lane(), door.s) != door.lane:
				continue
			var near := false
			for player: Node2D in all_players:
				if player.global_position.distance_squared_to(door.exit_point()) < min_d * min_d:
					near = true
					break
			if not near:
				choices.append(door)
	return choices.pick_random() if not choices.is_empty() else null


## Boss fights: somewhere in the room past the mouths that's off screen
## (anywhere in it, if it's all on screen).
func _room_spawn_point() -> Vector2:
	var area: Rect2 = level.arena.grow(-BraidTuning.FLOW_CELL * 2.0)
	var view := view_rect().grow(BraidTuning.SPAWN_SCREEN_MARGIN)
	var p := Vector2.INF
	for i in 16:
		p = level.nearest_open(Vector2(randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y)))
		if not view.has_point(p):
			return p
	return p


## Just ahead of the tide, in whichever lane our squad was in there (before a
## junction it may not be the one we're in now).
func _tide_spawn_point() -> Vector2:
	var x := maxf(_tide_spawn_x(), level.segment_start(segment) + BraidTuning.FLOW_CELL)
	for i in 12:
		var at_x := x + i * BraidTuning.FLOW_CELL
		var p := level.random_open_point_at(level.lane_at(act_lane(), at_x), at_x)
		if p != Vector2.INF:
			return p
	return level.lane_point(level.lane_at(act_lane(), x), x)


## Progress just ahead of the tide, where it spits enemies out.
func _tide_spawn_x() -> float:
	return maxf(tide.front + TIDE_SPAWN_AHEAD, 8.0)


## Spawns an enemy mid-segment (a splitter's pieces). See game.gd.
func spawn_enemy_at(scene: PackedScene, at: Vector2, elite := false,
		knockback := Vector2.ZERO) -> Enemy:
	if not is_inside_tree() or state != State.RUNNING or segment_wave == null or squad_out:
		return null
	# (Pieces pushed out of a wall can land on the same cell centre: not stacked.)
	at = level.nearest_open(at) + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(1.0, SPAWN_JITTER)
	var enemy := _add_enemy(scene, at, segment_wave.enemy_health_multiplier * _enemy_health_mult(),
		segment_wave.enemy_speed_multiplier, elite)
	enemy.apply_knockback(knockback)
	_calm_piece(enemy)
	return enemy


## A splitter's fresh piece: harmless for SPLIT_GRACE seconds (contact_damage
## 0, drawn faded), running away from whoever it's after, then a normal enemy.
func _calm_piece(enemy: Enemy) -> void:
	var damage := enemy.contact_damage
	enemy.contact_damage = 0
	enemy.modulate.a = 0.55
	enemy.steering = func(e: Node2D, target: Node2D) -> Vector2:
		var away := target.global_position.direction_to(e.global_position)
		var ahead: Vector2 = e.global_position + away * BraidTuning.FLOW_CELL * 2.0
		# Along a wall rather than into it.
		if not level.grid.is_free_at(ahead):
			away = away.orthogonal() if level.grid.is_free_at(e.global_position + away.orthogonal() * BraidTuning.FLOW_CELL * 2.0) \
				else -away.orthogonal()
		return away
	get_tree().create_timer(BraidTuning.SPLIT_GRACE, false).timeout.connect(func() -> void:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.contact_damage = damage
			enemy.modulate.a = 1.0
			enemy.steering = _steer)


## Braid's own player scaling table (player_scaling), not the wave set's.
func _enemy_scaling() -> PlayerScaling:
	return player_scaling


## Enemies collide with walls and window glass, walk round walls, and never
## get shoved through them.
func _prepare_enemy(enemy: Enemy) -> void:
	enemy.collision_mask |= BraidTuning.WALL_LAYER | BraidTuning.WINDOW_LAYER
	enemy.steering = _steer
	enemy.confine = _confine


## Given to every enemy as its `confine` (chasesplayer.gd), after each move
## from `from`. Bodies overlapping each other (a crowd squeezed against a wall,
## a group just out of a vent) are pushed apart by the physics without regard
## to walls, sometimes hard enough to shove one right through a lane's thin
## wall: into the void, where it's stuck for good, or the next lane. Undoes any
## move that took its middle through a wall or glass, or out of the level.
func _confine(enemy: Enemy, from: Vector2) -> void:
	var at := enemy.global_position
	var grid := level.grid
	# A short move ending a cell clear of every wall can't have crossed one
	# (most moves: one cached lookup).
	if from.distance_squared_to(at) < grid.cell * grid.cell and grid.clearance(grid.cell_of(at)) >= 2:
		return
	if not grid.is_outside_at(at) and not _wall_between(enemy, from, at):
		return
	if not grid.is_outside_at(from) and not _in_wall(enemy, from):
		enemy.global_position = from
	else:
		# Already somewhere it shouldn't be (a seal shut on it, say): the
		# nearest open floor.
		var back := level.nearest_open(at)
		enemy.global_position = back if grid.is_free_at(back) else level.nearest_open(from)


## True if the straight line `from` -> `to` touches a wall or glass.
func _wall_between(enemy: Enemy, from: Vector2, to: Vector2) -> bool:
	if from.is_equal_approx(to):
		return _in_wall(enemy, to)
	var query := PhysicsRayQueryParameters2D.create(from, to, BODY_BLOCKERS, [enemy.get_rid()])
	query.hit_from_inside = true
	return not enemy.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _in_wall(enemy: Enemy, at: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	query.collision_mask = BODY_BLOCKERS
	return not enemy.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


# --- Players and camera ---------------------------------------------------------

## Players bump into walls and window glass, and get Braid's equipment
## tuning.
func _prepare_player(player: Player) -> void:
	player.collision_mask |= BraidTuning.WALL_LAYER | BraidTuning.WINDOW_LAYER
	player.equipment_tuning = BraidTuning.EQUIPMENT_TUNING
	player.score_multiplier = score_multiplier()
	if _mod("glass_heart"):
		player.attributes["lives"] = CharacterClasses.clamp_attribute("lives",
			int(player.attributes["lives"]) - BraidModifiers.HEARTS_LOST)


# --- Modifiers -------------------------------------------------------------------

## Whether modifier `id` (scripts/braid/braid_modifiers.gd) is on this run.
func _mod(id: String) -> bool:
	return id in mods


func score_multiplier() -> float:
	return BraidModifiers.score_multiplier(mods)


## Seconds a door flashes before its enemies come out.
func _door_warning() -> float:
	return BraidModifiers.AMBUSH_DOOR_WARNING if _mod("ambush") else BraidTuning.DOOR_WARNING


func _enemy_health_mult() -> float:
	return BraidModifiers.ENEMY_HEALTH_MULT if _mod("ironhide") else 1.0


## The tide swallowed `count` of our pickups: a Salvage III Scavenger gets
## them (class_mod_fx.gd); otherwise they're lost.
func _on_tide_pickups(count: int) -> void:
	if class_mod_fx:
		class_mod_fx.on_tide_pickups(count)


## Famine: each resource is only dropped with DROP_KEEP_CHANCE.
func _drop_resources(at: Vector2, count: int) -> void:
	if _mod("famine"):
		var kept := 0
		for i in count:
			if randf() < BraidModifiers.DROP_KEEP_CHANCE:
				kept += 1
		count = kept
	super(at, count)


## A second line for the end screens: "Riptide, Horde:  score x1.40" ("" without
## any modifiers).
func _modifiers_note() -> String:
	if mods.is_empty():
		return ""
	return "\n%s:  score %s" % [BraidModifiers.names(mods),
		BraidModifiers.multiplier_text(score_multiplier())]


## Puts every player (knocked out or not) at x `x`, in formation across the
## middle of whichever lane our squad is in there, and the camera straight
## there.
func _place_players(x: float) -> void:
	var lane := level.lane_at(act_lane(), x)
	var at := level.lane_point(lane, x)
	for player in all_players:
		var offset: Vector2 = SPAWN_OFFSETS[player.player_index] if all_players.size() > 1 else Vector2.ZERO
		player.global_position = level.nearest_open(at + offset)
		player.velocity = Vector2.ZERO
	_update_camera(1.0)


## Follows the squad along its lane (round corners too), centred across it.
## At a window, or in (and near) a junction, it zooms out to show both lanes;
## while one of ours is on a turret it zooms out the same, centred on the
## squad.
## Through a vertical slice it zooms out a little (VERTICAL_ZOOM) and looks
## VERTICAL_CAMERA_LEAD ahead. In the convergence room it zooms out and
## follows the squad up and down. Whatever the place, it always shows every
## living player in our squad (BraidTuning.SCREEN_MARGIN in from the edges):
## it moves off its target, and won't zoom in, as far as that takes. While our
## squad is out, it follows the squad we're watching.
func _update_camera(weight: float) -> void:
	var x := _squad_s()
	var lane := my_lane()
	var watched := false
	var squad_y := _squad_y()
	if squad_out and link:
		var positions: Dictionary = link.squad_positions()
		if positions.has(_watching):
			watched = true
			var pos: Vector2 = positions[_watching]["pos"]
			x = level.progress(pos)
			lane = level.lane_of(pos)
			squad_y = pos.y
	var zoom := 1.0
	var target := level.lane_point(lane, x)
	var along := level.dir_at(lane, x)
	if absf(along.y) > 0.5:
		target += along * BraidTuning.VERTICAL_CAMERA_LEAD
	for sl in level.slices:
		if x >= sl["from"] - ZOOM_LEAD and x < sl["to"] + ZOOM_LEAD / 2.0:
			zoom = BraidTuning.VERTICAL_ZOOM
			break
	var pair := -1
	for j in level.junctions:
		if x < j["x0"] - ZOOM_LEAD or x >= j["x1"] + ZOOM_LEAD / 2.0:
			continue
		# A junction the squad on screen goes through.
		var entry := lane if watched else level.lane_at(act_lane(), j["x0"])
		if entry == j["pair"] or entry == j["pair"] + 1:
			pair = j["pair"]
			break
	if pair < 0:
		var w := level.window_at(lane, x)
		if not w.is_empty():
			pair = w["pair"]
	if pair >= 0:
		zoom = BraidTuning.ZOOM_OUT
		target = level.point_at(pair, x, BraidTuning.BAND_HEIGHT)
	elif not watched and _anyone_mounted():
		# Someone of ours on a turret: zoomed out to show the lane it fires
		# into too, but centred on the squad (no lead: nobody's moving).
		zoom = BraidTuning.ZOOM_OUT
		target = _squad_centre()
	# In (or at) the convergence room: zoomed out, following the squad up and
	# down too.
	if level.room.has_area() and x >= level.room_start - ZOOM_LEAD:
		zoom = BraidTuning.ROOM_ZOOM
		target.y = squad_y

	# Our living players, as a box grown by the margin: the camera must show
	# all of it. (None when watching another squad.)
	var frame := Rect2()
	var framing := false
	if not watched:
		for p: Node2D in _living_players():
			if framing:
				frame = frame.expand(p.global_position)
			else:
				frame = Rect2(p.global_position, Vector2.ZERO)
				framing = true
		frame = frame.grow(BraidTuning.SCREEN_MARGIN)

	var view := view_size()
	var new_zoom := lerpf(world_zoom().x, zoom, weight)
	if framing:
		# Never zoomed in so far that the box doesn't fit.
		new_zoom = minf(new_zoom, minf(view.x / frame.size.x, view.y / frame.size.y))
	camera.zoom = Vector2.ONE * new_zoom * render_scale
	var half := view / new_zoom / 2.0
	var pos := camera.global_position.lerp(_in_bounds(target, half), weight)
	if framing:
		# However the camera lags or leads, it keeps the box on screen.
		pos = Vector2(_frame_axis(pos.x, frame.position.x, frame.end.x, half.x),
			_frame_axis(pos.y, frame.position.y, frame.end.y, half.y))
	camera.global_position = _in_bounds(pos, half)


func _anyone_mounted() -> bool:
	for p: Node2D in _living_players():
		if p.is_mounted():
			return true
	return false


## The middle of our living players.
func _squad_centre() -> Vector2:
	var sum := Vector2.ZERO
	var living := _living_players()
	for p: Node2D in living:
		sum += p.global_position
	return sum / maxf(living.size(), 1)


## Camera centre `c` moved so the screen (`half` either side of it) stays
## inside the level.
func _in_bounds(c: Vector2, half: Vector2) -> Vector2:
	var b := level.bounds
	return Vector2(
		clampf(c.x, b.position.x + half.x, maxf(b.end.x - half.x, b.position.x + half.x)),
		clampf(c.y, b.position.y + half.y, maxf(b.end.y - half.y, b.position.y + half.y)))


## Camera centre `c` on one axis, moved (as little as it takes) so the screen,
## `half` either side of it, covers lo..hi; centred on lo..hi if it's wider.
static func _frame_axis(c: float, lo: float, hi: float, half: float) -> float:
	if hi - lo >= half * 2.0:
		return (lo + hi) / 2.0
	return clampf(c, hi - half, lo + half)


# --- Strip test ---------------------------------------------------------------------

## DEBUG_FILE's settings (and the file deleted), or {} if there's no test.
static func _read_debug_file() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(DEBUG_FILE) != OK:
		return {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DEBUG_FILE))
	var age := Time.get_unix_time_from_system() - float(cfg.get_value("test", "written", 0.0))
	if age > DEBUG_FILE_MAX_AGE:
		return {}
	var out := {}
	var strip: String = cfg.get_value("test", "strip", "")
	if not strip.is_empty():
		out["strip"] = strip
	if cfg.has_section_key("test", "seed"):
		out["seed"] = int(cfg.get_value("test", "seed"))
	if cfg.has_section_key("test", "act"):
		out["act"] = int(cfg.get_value("test", "act"))
	return out


## Writes a strip test for the next time this scene starts (the Braid dock
## does the same from the editor).
static func _write_debug_file(test: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in test:
		cfg.set_value("test", key, test[key])
	cfg.set_value("test", "written", Time.get_unix_time_from_system())
	cfg.save(DEBUG_FILE)


## A strip test's lane: every segment is `strip` repeated (after the start
## strip in the first). {} if `strip` is "" or doesn't exist.
func _debug_layout(strip: String) -> Dictionary:
	if strip.is_empty():
		return {}
	var info := {}
	var starter := ""
	for s in BraidGenerator.catalog():
		if s["name"] == strip:
			info = s
		if s["zone"] == "start" and starter.is_empty():
			starter = s["name"]
	if info.is_empty():
		push_warning("Braid strip test: no strip called %s" % strip)
		return {}
	var segments := []
	for i in BraidTuning.SEGMENTS_PER_ACT:
		var names := []
		var length := 0.0
		if i == 0 and not starter.is_empty() and starter != strip:
			names.append(starter)
		while length < DEBUG_SEGMENT_LENGTH:
			names.append(strip)
			length += info["length"]
		segments.append(names)
	return BraidGenerator.single_lane(segments)

