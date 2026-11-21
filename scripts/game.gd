extends GameBase
## Spawns the players chosen on the character select screen, keeps a shared
## camera framing all of them, and runs the waves:
##   wave (timed) -> summary -> shop (everyone readies up) -> next wave ...
## Surviving the last wave in `wave_set` wins; losing every player ends it.
## Either way the run ends on a score summary that cashes in everyone's
## unspent resources for points.
##
## Squads game (scripts/net/squads.gd): the host's wave clock rules. Joiners
## follow it, the next wave starts once every squad has left the shop, and a
## wiped-out squad sits out the rest of the wave (everyone is revived when it
## ends). It's game over only when every squad is down at once. Each squad's
## map overlaps its neighbours'; scripts/net/squad_link.gd shows other squads'
## players and enemies where they overlap ours and settles hits and kills.
## Our enemies stay on our map and spawn on it.
##
## Objective waves (has_objective: every Global.objective_every()th wave)
## also have a random objective (scripts/objectives/objective.gd), introduced by a how-to screen
## first (unless that's turned off in the settings). The objective can end
## the wave early, or keep it going past its time; failing it ends the run.
## In a squads game a squad that fails it is knocked out for the rest of the
## wave, the same as a wiped-out squad: it's only game over if every squad is
## out (a shared objective failing, like the crystal, fails every squad).
##
## Standard mode has one every 4th wave; a custom game picks how often.
##
## Custom game (Global.MODE_CUSTOM): the run is rebuilt from `wave_set` by
## scripts/waves/custom_run.gd, and objectives (if any were picked) are drawn
## from the picked types only, every `objective_every` waves.
##
## Boss waves (WaveDefinition.boss_id: waves 5, 10, 15 and 20 of the standard run):
## the boss's intro plays first (scripts/bosses/boss_intro.gd), then the boss
## fight (scripts/bosses/boss.gd) runs the wave in place of an objective (in
## any mode) until the boss dies. It pays a bigger reward
## (WaveDefinition.reward) and points for the kill.
##
## Boss Rush (Global.MODE_BOSS_RUSH): the run is just the boss waves
## (scripts/waves/boss_rush.gd), starting with resources and a shop.
##
## Boss Test (picked on character select, local games only): one boss, with
## the resources and hearts a run would have by then and a shop first
## (scripts/waves/boss_test.gd). It ends back on character select.
##
## Player spawning, the pixel-art view, enemy drops and the end-of-run
## summary are shared with Braid: see scripts/game_base.gd.

enum State { WAVE, SUMMARY, SHOP, WAITING, BRIEFING, GAME_OVER, VICTORY }

## Squads game: why our squad failed this wave's objective ("" if it hasn't).
var _squad_fail_reason := ""

const WaveDirector := preload("res://scripts/waves/wave_director.gd")
const Shop := preload("res://scripts/ui/shop.gd")
## New enemies appear this far beyond the edge of the visible area.
const ENEMY_SPAWN_MARGIN := 50.0
const CAMERA_MARGIN := Vector2(180, 140)
const MIN_ZOOM := 0.35
const SquadLink := preload("res://scripts/net/squad_link.gd")
## Squads game: spawn points tried before settling for one on screen; the
## first SPAWN_RING_ATTEMPTS are just off screen, the rest anywhere on the map.
const SPAWN_ATTEMPTS := 16
const SPAWN_RING_ATTEMPTS := 8
## Squads game: enemies spawn at least this far inside our map's edges.
const SPAWN_EDGE_INSET := 24.0
const CustomRun := preload("res://scripts/waves/custom_run.gd")
const ActTheme := preload("res://scripts/act_theme.gd")
## Waves per art theme: the theme changes after each boss (waves 5, 10, ...),
## in the campaign's act order (ActTheme.ACT_THEMES).
const WAVES_PER_THEME := 5
## The arena's own ground (the meadow), for themes without one.
const GROUND_TEXTURE := preload("res://assets/meadow/environment/background-1.png")
const ObjectiveTutorial := preload("res://scripts/objectives/objective_tutorial.gd")
const BossIntro := preload("res://scripts/bosses/boss_intro.gd")
const BossRush := preload("res://scripts/waves/boss_rush.gd")
const BossTest := preload("res://scripts/waves/boss_test.gd")

## The map's ground. Its tiled region sets grass_bounds.
@onready var grass: Sprite2D = $Grass

## World-space rectangle covered by the grass background. Players can't leave
## it and the camera never shows past it.
var grass_bounds := Rect2()

var state := State.WAVE
var director: WaveDirector
## Each player's totals when the current wave began, for the summary:
## player -> {"kills", "points", "resources"}.
var _wave_start_stats := {}
var _clock_sync_timer := 0.0
## Every how many waves an objective wave comes; 0 = never (Global.objective_every()).
var objective_every := 0
## Seconds spent fighting bosses that were beaten (Boss Rush's final time).
var _boss_time := 0.0
## Boss Test (scripts/waves/boss_test.gd, picked on character select): the
## run is one boss, with a run's worth of resources and hearts and a shop
## first. It ends back on character select, to go again.
var boss_test := false
## The current wave's objective while it's being fought (else null).
var objective: Node2D


func _ready() -> void:
	# Running main.tscn directly from the editor: use keyboard + all controllers.
	if Global.players.is_empty():
		Global.players = _default_players()

	_setup_pixel_view()
	# From the tiled region, not the texture, so a missing texture can't shrink the map.
	var grass_rect := Rect2(Vector2.ZERO, grass.region_rect.size)
	if grass.centered:
		grass_rect.position = -grass_rect.size / 2.0
	grass_bounds = grass.get_global_transform() * grass_rect

	squads_game = Squads.in_game()
	objective_every = Global.objective_every()
	boss_test = BossTest.is_active()

	# Backstop: Camera2D's own limits also stop it rendering past the grass.
	camera.limit_left = floori(grass_bounds.position.x)
	camera.limit_top = floori(grass_bounds.position.y)
	camera.limit_right = ceili(grass_bounds.end.x)
	camera.limit_bottom = ceili(grass_bounds.end.y)

	_spawn_players(grass_bounds)
	_add_pause_menu(boss_test)

	_update_camera(1.0)

	# Enemies placed in the scene by hand would bypass the waves.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()

	if wave_set == null:
		wave_set = load(DEFAULT_WAVE_SET)
	var test_kit := {}
	if boss_test:
		var test := BossTest.settings()
		var at := BossTest.wave_index(wave_set, test)
		test_kit = {
			"resources": BossTest.estimated_resources(wave_set, at, all_players.size(), test),
			"hearts": BossTest.bonus_hearts(wave_set, at),
		}
		wave_set = BossTest.build(wave_set, test)
	elif Global.current_mode() == Global.MODE_CUSTOM:
		wave_set = CustomRun.build(wave_set, Global.current_custom_settings())
	elif Global.current_mode() == Global.MODE_BOSS_RUSH:
		wave_set = BossRush.build(wave_set)
	director = WaveDirector.new()
	director.wave_set = wave_set
	director.spawn_requested.connect(_spawn_enemy)
	director.wave_finished.connect(_on_wave_finished)
	add_child(director)

	if squads_game:
		director.authoritative = Squads.is_host()
		Squads.wave_clock.connect(_on_host_wave_clock)
		Squads.wave_ended.connect(_on_host_wave_ended)
		Squads.wave_begin.connect(_on_squads_wave_begin)
		Squads.all_squads_down.connect(_on_all_squads_down)
		Squads.final_results.connect(_on_squad_final_results)
		var squad_link := SquadLink.new()
		squad_link.setup(self)
		add_child(squad_link)
		link = squad_link
		for player in all_players:
			player.shot_fired.connect(link.report_shot)

	if boss_test:
		# Kit up as if the run so far had been played.
		for player in all_players:
			if test_kit["hearts"] > 0:
				player.change_attribute("lives", test_kit["hearts"])
				player.restore_all_lives()
			player.add_resources(test_kit["resources"])
		if test_kit["resources"] > 0:
			_go_shopping(0)
		else:
			_prepare_wave(0)
	elif Global.current_mode() == Global.MODE_BOSS_RUSH:
		# Kit up before the first boss.
		for player in all_players:
			player.add_resources(BossRush.START_RESOURCES)
		_go_shopping(0)
	else:
		_prepare_wave(0)


func _exit_tree() -> void:
	super()
	ActTheme.reset()  # Back to the default art for whatever comes next.


## True while a wave is being fought (not between waves or after the end).
func is_wave_running() -> bool:
	return state == State.WAVE


# --- Waves --------------------------------------------------------------------

## True if wave `index` has an objective: every objective_every-th wave
## (never a boss wave).
func has_objective(index: int) -> bool:
	if objective_every <= 0 or wave_set.waves[index].is_boss_wave():
		return false
	return (index + 1) % objective_every == 0


## Wave `index`'s objective type (Objective.TYPES entry), if it has one. The
## objective waves are numbered among themselves, so two in a row never
## repeat a type.
func objective_type(index: int) -> Dictionary:
	index = (index + 1) / maxi(1, objective_every) - 1
	return Objective.type_for_wave(Global.run_seed, index, Global.allowed_objectives())


## Gets wave `index` going: in objective mode the how-to comes first, and in
## a squads game every squad has to be ready (after the shop, or the how-to)
## before it starts for everyone at once (_on_squads_wave_begin).
func _prepare_wave(index: int) -> void:
	_apply_theme(index)
	var wave := wave_set.waves[index]
	if wave.is_boss_wave() and Boss.exists(wave.boss_id):
		state = State.BRIEFING
		pause_menu.enabled = false
		get_tree().paused = true
		var intro := BossIntro.new()
		add_child(intro)
		intro.play(self, camera, wave.boss_id, Boss.boss_centre(self),
			"Boss Test" if boss_test else "Wave %d" % (index + 1))
		await intro.finished
	elif has_objective(index) and Global.show_objective_tutorials:
		state = State.BRIEFING
		pause_menu.enabled = false
		get_tree().paused = true
		var tutorial := ObjectiveTutorial.new()
		add_child(tutorial)
		tutorial.play(objective_type(index), squads_game)
		await tutorial.finished
	if squads_game and (index > 0 or has_objective(index) or wave.is_boss_wave()):
		state = State.WAITING
		get_tree().paused = true
		hud.show_notice("Waiting for the other squads...")
		Squads.report_ready_for_wave(index)
		return
	_start_wave(index)


func _start_wave(index: int) -> void:
	state = State.WAVE
	_squad_fail_reason = ""
	get_tree().paused = false
	pause_menu.enabled = true
	_wave_start_stats.clear()
	for player in all_players:
		_wave_start_stats[player] = {
			"kills": player.kills, "points": player.points, "resources": player.resources,
		}
		player.recharge_equipment()  # Every wave starts with equipment ready.
	var wave := wave_set.waves[index]
	_set_equipment_wave(wave)
	director.objective = null
	hud.hide_boss()
	if wave.is_boss_wave() and Boss.exists(wave.boss_id):
		objective = Boss.create_boss(wave.boss_id)
		objective.setup(self, index, wave)
		add_child(objective)
		director.objective = objective
		hud.hide_objective()
		hud.show_boss(objective)
	elif has_objective(index):
		var type := objective_type(index)
		objective = Objective.create(type)
		objective.setup(self, index, wave)
		add_child(objective)
		director.objective = objective
		hud.show_objective(type["name"], type["color"])
	else:
		hud.hide_objective()
	director.start_wave(index, all_players.size())
	var subtitle := wave.display_name
	if objective and wave.is_boss_wave():
		subtitle = objective.info["summary"]
	elif objective:
		subtitle = "%s: %s" % [objective.info["name"], objective.info["summary"]]
	hud.show_wave_start(index, wave_set.wave_count(), subtitle)
	_update_wave_hud()


func _on_wave_finished(index: int, failed := false) -> void:
	if state != State.WAVE:
		return
	if squads_game:
		Squads.end_wave(index, failed)  # Host only; tells the other squads.
	var wave := wave_set.waves[index]
	var fail_reason := _objective_fail_reason() if failed else ""
	# A boss wave that ended with the boss dead (not every squad falling):
	# its kill points, and how long it took.
	var boss_points := 0
	var boss_note := ""
	if objective and wave.is_boss_wave() and objective.is_defeated():
		boss_points = objective.kill_points()
		boss_note = "%s defeated in %s" % [objective.info["name"], _clock_text(objective.clear_time())]
		_boss_time += objective.clear_time()
	_clear_field()
	hud.hide_boss()
	hud.hide_wave_banner()
	hud.hide_notice()
	hud.set_wave_time(0.0)
	hud.hide_objective()

	# Freeze the world while the between-wave screens are up.
	state = State.SUMMARY
	pause_menu.close()  # In a squads game it may be open; the world never paused.
	pause_menu.enabled = false
	get_tree().paused = true

	# A failed objective ends the run.
	if failed:
		_game_over("Wave %d of %d failed: %s" % [index + 1, wave_set.wave_count(), fail_reason],
			_game_over_prompt())
		return

	var bonus := _wave_reward(index)
	for player in all_players:
		player.add_points(boss_points)
	var rows := _wave_summary_rows()
	for player in all_players:
		player.add_resources(bonus)
		if wave.bonus_hearts > 0:
			player.change_attribute("lives", wave.bonus_hearts)
		player.restore_all_lives()  # also revives knocked-out players

	if wave_set.is_final_wave(index):
		state = State.VICTORY
		var won := "All %d waves survived" % wave_set.wave_count()
		if boss_test:
			won = boss_note
		elif Global.current_mode() == Global.MODE_BOSS_RUSH:
			won = "All %d bosses defeated in %s" % [wave_set.wave_count(), _clock_text(_boss_time)]
		var summary := _show_final_summary("VICTORY!", Color(1, 0.85, 0.3),
			won, bonus, "Press {A} to return to character select" if boss_test
				else "Press {A} to return to menu")
		await summary.continued
		if boss_test:
			Global.go_to_character_select()
		elif not squads_game:
			Global.go_to_title()
		elif Squads.is_host():
			Squads.return_to_lobby()
		else:
			hud.show_notice("Waiting for the host...")
		return

	var summary := WaveSummary.new()
	add_child(summary)
	if not boss_note.is_empty():
		summary.show_summary("BOSS DEFEATED", Color(1.0, 0.85, 0.3),
			boss_note, rows, bonus, "Press {A} to continue to the shop", wave.bonus_hearts)
	elif _squad_fail_reason.is_empty():
		summary.show_summary("WAVE %d COMPLETE" % (index + 1), Color(0.45, 0.95, 0.45),
			wave.display_name, rows, bonus, "Press {A} to continue to the shop",
			wave.bonus_hearts)
	else:
		summary.show_summary("WAVE %d SURVIVED" % (index + 1), Color(1.0, 0.6, 0.3),
			"Your squad failed the objective: %s" % _squad_fail_reason, rows, bonus,
			"Press {A} to continue to the shop", wave.bonus_hearts)
	_squad_fail_reason = ""
	await summary.continued
	_go_shopping(index + 1)


## The shop before wave `next_index`, then that wave.
func _go_shopping(next_index: int) -> void:
	state = State.SHOP
	pause_menu.enabled = false
	get_tree().paused = true
	_apply_theme(next_index)  # The shop after a boss already shows the next theme.
	var shop := Shop.new()
	add_child(shop)
	# Prices go by how far into a standard run this is (Boss Rush skips waves).
	var price_waves := wave_set.price_waves
	var waves_done := price_waves[next_index] if next_index < price_waves.size() else -1
	var next_wave := wave_set.waves[next_index]
	_set_equipment_wave(next_wave)  # The shop shows equipment as it'll be next wave.
	var label := ""
	if next_wave.is_boss_wave() and Boss.exists(next_wave.boss_id):
		label = "BOSS: %s" % Boss.boss_info(next_wave.boss_id)["name"]
	elif has_objective(next_index) and objective_every > 1:
		label = "OBJECTIVE: %s" % objective_type(next_index)["name"]
	shop.open(all_players, next_index, wave_set.wave_count(), waves_done, label)
	await shop.all_ready
	_prepare_wave(next_index)


## Switches the art (enemies, ground, shop) to wave `index`'s theme: a custom
## game's fixed pick, else by where the wave falls in a standard run
## (WAVES_PER_THEME a theme, like the campaign's acts). Before the wave's
## enemies spawn: they pick their look as they come in.
func _apply_theme(index: int) -> void:
	var theme := CustomRun.CAMPAIGN_THEME
	if Global.current_mode() == Global.MODE_CUSTOM:
		theme = str(Global.current_custom_settings().get("theme", CustomRun.DEFAULT_THEME))
	if theme == CustomRun.CAMPAIGN_THEME:
		var standard_index := wave_set.price_waves[index] if index < wave_set.price_waves.size() else index
		theme = ActTheme.act_theme(floori(standard_index / float(WAVES_PER_THEME)))
	ActTheme.set_theme(theme)
	Global.play_theme_music(ActTheme.current, wave_set.waves[index].is_boss_wave())
	grass.texture = ActTheme.environment("background", GROUND_TEXTURE)


## Equipment grows with the wave's enemy health (Equipment.WAVE_SCALING).
func _set_equipment_wave(wave: WaveDefinition) -> void:
	for player in all_players:
		player.wave_enemy_health = wave.enemy_health_multiplier


## Resources every player gets for surviving wave `index`.
func _wave_reward(index: int) -> int:
	var bonus := wave_set.waves[index].reward()
	if Global.current_mode() == Global.MODE_BOSS_RUSH and not wave_set.is_final_wave(index):
		bonus += BossRush.STIPEND
	return bonus


## Why the current wave's objective failed (asked before it's cleared away).
func _objective_fail_reason() -> String:
	if objective == null:
		return "Objective failed"
	if objective.fail_reason.is_empty():
		objective.outcome()  # A squad other than the host's works it out from the state.
	return objective.fail_reason if not objective.fail_reason.is_empty() else "Objective failed"


# --- Squads game ----------------------------------------------------------

func _on_host_wave_clock(index: int, elapsed: float) -> void:
	if state == State.WAVE and index == director.index:
		director.sync_to(elapsed)


func _on_host_wave_ended(index: int, failed: bool) -> void:
	if state == State.WAVE and index == director.index:
		director.stop()
		_on_wave_finished(index, failed)


func _on_squads_wave_begin(index: int) -> void:
	if state == State.WAITING:
		hud.hide_notice()
		_start_wave(index)


func _on_all_squads_down(index: int) -> void:
	if state != State.WAVE:
		return
	_game_over("Every squad fell on wave %d of %d" % [index + 1, wave_set.wave_count()],
		_game_over_prompt())


## What the game over screen tells the player to press.
func _game_over_prompt() -> String:
	if boss_test:
		return "Press {B} to return to character select"
	if not squads_game:
		return "Press {B} to return to menu"
	return "Press {B} to return everyone to character select" if Squads.is_host() \
		else "Waiting for the host...     {B} leave game"


## What each player did during the wave that just ended (before the bonus).
func _wave_summary_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for player in all_players:
		var start: Dictionary = _wave_start_stats.get(player, {"kills": 0, "points": 0, "resources": 0})
		rows.append({
			"player": player,
			"kills": player.kills - start["kills"],
			"points": player.points - start["points"],
			"resources": player.resources - start["resources"],
			"health": player.health,  # half hearts as the wave ended, before refill
		})
	return rows


## Removes the wave's leftovers: enemies vanish, uncollected resources are
## handed out, and shots in flight and everything equipment put down
## (turrets, mines, ...) disappear.
func _clear_field() -> void:
	if objective:
		objective.queue_free()
		objective = null
	director.objective = null
	if link:
		link.clear_wave()  # Other squads' enemies go too.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	for pickup in get_tree().get_nodes_in_group("pickups"):
		pickup.collect()
	for shot in get_tree().get_nodes_in_group("projectiles"):
		shot.queue_free()
	for deployed in get_tree().get_nodes_in_group("deployables"):
		deployed.remove_from_group("decoys")
		deployed.queue_free()


## Squads game: another squad's enemy one of our players killed may have
## died just off our map (shots reach a little past the edge).
func _remote_drop_point(at: Vector2) -> Vector2:
	var inset := Vector2(ResourcePickup.RADIUS, ResourcePickup.RADIUS) * 2.0
	return at.clamp(grass_bounds.position + inset, grass_bounds.end - inset)


## Enemies are scaled for the player count the director's wave was set up for.
func _enemy_scaling_count() -> int:
	return director.player_count


func _spawn_enemy(group: WaveEnemyGroup, wave: WaveDefinition, elite: bool, count := 1) -> void:
	if not is_inside_tree():
		return
	var at := _offscreen_spawn_point()
	if objective:
		var from: Vector2 = objective.spawn_point()
		if from != Vector2.INF:
			at = from
	# A pack spreads out around one spot (more members, wider spread).
	var spread := CLUSTER_SPACING * sqrt(float(count))
	for i in count:
		var offset := Vector2.ZERO
		if i > 0:
			offset = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.3, 1.0) * spread
		_add_enemy(group.enemy_scene, at + offset,
			wave.enemy_health_multiplier * group.health_multiplier,
			wave.enemy_speed_multiplier * group.speed_multiplier, elite)


## Spawns an enemy from `scene` at `at` mid-wave (a splitter's pieces),
## scaled like the current wave's enemies and shoved by `knockback`. Does
## nothing between waves.
func spawn_enemy_at(scene: PackedScene, at: Vector2, elite := false,
		knockback := Vector2.ZERO) -> Enemy:
	if not is_inside_tree() or state != State.WAVE or director.wave == null:
		return null
	var enemy := _add_enemy(scene, at, director.wave.enemy_health_multiplier,
		director.wave.enemy_speed_multiplier, elite)
	enemy.apply_knockback(knockback)
	return enemy


## A random point just outside what the camera currently shows, so new
## enemies walk in from off-screen instead of popping in on top of players.
func _offscreen_spawn_point() -> Vector2:
	var half_view := view_size() / world_zoom() / 2.0
	var radius := half_view.length() + ENEMY_SPAWN_MARGIN
	if link:
		return _spawn_point_on_map(half_view, radius)
	return camera.global_position + Vector2.RIGHT.rotated(randf() * TAU) * radius


## Squads game: our enemies can't leave our map, so they spawn on it: off
## screen where possible, and preferably not in a strip another squad's map
## overlaps (so they don't pop in on that squad's screen). Points just off
## screen are tried first, to keep them close to the action.
func _spawn_point_on_map(half_view: Vector2, radius: float) -> Vector2:
	var view := Rect2(camera.global_position - half_view, half_view * 2.0).grow(ENEMY_SPAWN_MARGIN)
	var area := grass_bounds.grow(-SPAWN_EDGE_INSET)
	var off_screen: Array[Vector2] = []
	for i in SPAWN_ATTEMPTS:
		var p: Vector2
		if i < SPAWN_RING_ATTEMPTS:
			p = camera.global_position + Vector2.RIGHT.rotated(randf() * TAU) * radius
		else:
			p = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		p = p.clamp(area.position, area.end)
		if not view.has_point(p):
			off_screen.append(p)
	for p in off_screen:
		if not link.is_shared(p):
			return p
	if not off_screen.is_empty():
		return off_screen[0]
	# Nearly the whole map is on screen: the corner furthest from the middle of it.
	var corners := [area.position, Vector2(area.end.x, area.position.y),
		Vector2(area.position.x, area.end.y), area.end]
	var furthest: Vector2 = corners[0]
	for c: Vector2 in corners:
		if c.distance_squared_to(camera.global_position) > furthest.distance_squared_to(camera.global_position):
			furthest = c
	return furthest


func _on_player_died(_hit_position: Vector2) -> void:
	if state != State.WAVE or not get_tree().get_nodes_in_group("players").is_empty():
		return
	if squads_game:
		# The other squads play on; everyone is revived when the wave ends.
		if _squad_fail_reason.is_empty():
			hud.show_notice("Squad down! Waiting for the wave to end...")
		else:
			hud.show_notice("Objective failed: %s. Waiting for the wave to end..." % _squad_fail_reason)
		Squads.report_squad_down(director.index)
		return
	_game_over("Fell on wave %d of %d" % [director.index + 1, wave_set.wave_count()])


## Squads game: our squad failed the objective (the host says so), so it's
## out for the rest of the wave, as if it had been wiped out
## (_on_player_died reports it down).
func squad_failed_objective(reason: String) -> void:
	if state != State.WAVE:
		return
	_squad_fail_reason = reason
	for player in all_players:
		if not player.is_dead():
			player.take_hit(player.health, player.global_position)


## The run is lost: the same score summary as a victory (unspent resources
## cashed in), minus the wave bonus.
func _game_over(subtitle: String, prompt: String = "Press {B} to return to menu") -> void:
	state = State.GAME_OVER
	director.stop()
	if objective:
		objective.queue_free()
		objective = null
		director.objective = null
	hud.hide_wave_banner()
	hud.hide_notice()
	hud.hide_boss()
	# Freeze the world, as between waves, so shots still in flight can't
	# change the scores once they're totted up.
	pause_menu.close()
	pause_menu.enabled = false
	get_tree().paused = true

	# As the prompts say: only B / Esc (in a squads game it makes a joiner leave).
	var summary := _show_final_summary("GAME OVER", Color(1, 0.25, 0.25), subtitle, 0,
		prompt, true)
	await summary.continued
	if boss_test:
		Global.go_to_character_select()
	elif squads_game and Squads.is_host():
		Squads.return_to_lobby()
	else:
		Global.go_to_title()  # Joiners leave the squads game.


func _process(delta: float) -> void:
	_update_camera(1.0 - exp(-CAMERA_SPEED * delta))
	if state == State.WAVE:
		_update_wave_hud()
		if squads_game and Squads.is_host():
			_clock_sync_timer -= delta
			if _clock_sync_timer <= 0.0:
				_clock_sync_timer = CLOCK_SYNC_INTERVAL
				Squads.send_wave_clock(director.index, director.elapsed())


func _update_wave_hud() -> void:
	var counts_up: bool = objective != null and objective.clock_counts_up()
	hud.set_wave_time(director.time_left, not counts_up)
	if objective:
		hud.set_objective_status(objective.status_text())


func _update_camera(weight: float) -> void:
	var nodes := get_tree().get_nodes_in_group("players")
	if nodes.is_empty():
		return
	var rect := Rect2((nodes[0] as Node2D).global_position, Vector2.ZERO)
	for n: Node2D in nodes:
		rect = rect.expand(n.global_position)

	var view := view_size()
	var needed := rect.size + CAMERA_MARGIN
	var min_zoom := _min_zoom()
	var zoom := clampf(minf(view.x / needed.x, view.y / needed.y), min_zoom, maxf(1.0, min_zoom))

	var new_zoom := world_zoom().lerp(Vector2(zoom, zoom), weight)
	camera.zoom = new_zoom * render_scale
	var center := camera.global_position.lerp(rect.get_center(), weight)
	camera.global_position = _clamp_to_grass(center, view / new_zoom)


## The furthest the camera zooms out: MIN_ZOOM, but never so far that the
## view is bigger than the grass.
func _min_zoom() -> float:
	var view := view_size()
	return maxf(MIN_ZOOM, maxf(view.x / grass_bounds.size.x, view.y / grass_bounds.size.y))


## How far apart (centre to centre, on each axis) our living players can get
## and still all be on screen with the camera zoomed all the way out. Players
## can't walk further apart than this (character_body.gd _stay_in_bounds).
func max_player_spread() -> Vector2:
	return view_size() / _min_zoom() - CAMERA_MARGIN


## Moves our players to around `at` (in their usual spawn formation, kept on
## the grass) and the camera straight there. For objectives that start the
## squad somewhere in particular (the VIP's side).
func place_players(at: Vector2) -> void:
	var area := grass_bounds.grow(-40.0)
	for player in all_players:
		var offset: Vector2 = SPAWN_OFFSETS[player.player_index] if all_players.size() > 1 else Vector2.ZERO
		player.global_position = (at + offset).clamp(area.position, area.end)
		player.velocity = Vector2.ZERO
	_update_camera(1.0)


## Keep the camera centre far enough from the grass edges that a view of
## `view` (in world units) stays entirely on the grass.
func _clamp_to_grass(center: Vector2, view: Vector2) -> Vector2:
	var lo := grass_bounds.position + view / 2.0
	var hi := grass_bounds.end - view / 2.0
	# If the view is bigger than the grass on an axis, just centre on it.
	return Vector2(
		clampf(center.x, lo.x, hi.x) if lo.x <= hi.x else grass_bounds.get_center().x,
		clampf(center.y, lo.y, hi.y) if lo.y <= hi.y else grass_bounds.get_center().y)

