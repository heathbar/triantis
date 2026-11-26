class_name GameBase
extends Node2D
## What the arena game (scripts/game.gd) and the Braid campaign
## (scripts/braid/braid_game.gd) share: spawning the players picked on
## character select, drawing the world through the pixel-art view, adding
## enemies and handing out their resource drops, and the end-of-run score
## summary. Each mode extends this and runs its own rounds (waves in the
## arena, segments and boss fights in Braid).
##
## Both scenes (main.tscn, braid/braid_game.tscn) have the Camera2D, Players,
## HUD and PixelView/Container/Viewport nodes this expects.
##
## Players (scripts/player/character_body.gd) and objectives reach the game
## through the methods here: max_player_spread(), world_mouse_position(),
## spawn_enemy_at(), squad_failed_objective().

const PLAYER_SCENE := preload("res://scenenodethings/player.tscn")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const PlayerStats := preload("res://scripts/ui/player_stats.gd")
const WaveSummary := preload("res://scripts/ui/wave_summary.gd")
const CampfireWait := preload("res://scripts/ui/campfire_wait.gd")
const ResourcePickup := preload("res://scripts/resource_pickup.gd")
## The difficulty curve both modes share (sets each wave's enemy health).
const DifficultyCurve := preload("res://scripts/waves/difficulty_curve.gd")
## Class Mods, picked after every boss fight but a run's last (both modes).
const ClassModFx := preload("res://scripts/class_mods/class_mod_fx.gd")
const ClassModPicker := preload("res://scripts/class_mods/class_mod_picker.gd")
const DEFAULT_WAVE_SET := "res://data/waves/standard_run.tres"
## Where each player (by slot) starts around the spawn point. A lone player
## starts on it.
const SPAWN_OFFSETS := [Vector2(-24, -24), Vector2(24, -24), Vector2(-24, 24), Vector2(24, 24)]
## How quickly the camera catches up (per second, exponential).
const CAMERA_SPEED := 5.0
## A pack of N enemies (WaveEnemyGroup.cluster) spreads out to about this x
## sqrt(N) pixels around its spawn point.
const CLUSTER_SPACING := 12.0
## Resource pickups from one enemy are scattered this far apart.
const DROP_SCATTER := 8.0
## Points each unspent resource is worth when the run ends (won or lost).
const POINTS_PER_LEFTOVER_RESOURCE := 5
## Squads game: seconds between the host's clock broadcasts.
const CLOCK_SYNC_INTERVAL := 0.25
## Visibility layer bit of the world (this node and everything under it). The
## main viewport skips it, so the world is only drawn by the pixel-art
## viewport ($PixelView), while the UI (CanvasLayers) stays full resolution.
const WORLD_VISIBILITY_LAYER := 1 << 1

## The waves for this run (Braid borrows each segment's enemies from them).
## Falls back to DEFAULT_WAVE_SET if left empty.
@export var wave_set: WaveSet

@onready var camera: Camera2D = $Camera2D
@onready var players_root: Node2D = $Players
@onready var hud: CanvasLayer = $HUD
## The world is drawn into this low-resolution viewport
## (Global.PIXEL_ART_RESOLUTION, sharing this scene's 2D world), which is
## shown scaled up by a whole number.
@onready var pixel_container: SubViewportContainer = $PixelView/Container
@onready var pixel_viewport: SubViewport = $PixelView/Container/Viewport

var pause_menu: PauseMenu
## Every player in this game, including knocked-out ones (the "players" group
## only holds the living).
var all_players: Array[Node] = []
## True when playing a squads game over the LAN.
var squads_game := false
## Squads game: syncs the world with the other squads' games
## (scripts/net/squad_link.gd in the arena, scripts/braid/braid_link.gd in
## Braid), else null.
var link: Node
## Makes our players' Class Mods happen (scripts/class_mods/class_mod_fx.gd);
## added by _spawn_players.
var class_mod_fx: ClassModFx
## Screen pixels per world pixel in the pixel viewport itself: 1 when it
## renders at PIXEL_ART_RESOLUTION and is scaled up afterwards, or the
## whole-number scale when Global.SMOOTH_PIXEL_MOTION renders it at full size
## (the camera zooms in by this much, so the world looks the same size either
## way).
var render_scale := 1.0
## Squads game: other squads' end-of-run results, squad -> results (they can
## arrive before our own summary screen is up).
var _squad_results := {}
## The end-of-run summary while it's up (else null).
var _final_summary: WaveSummary
## Squads game: the campfire scene while we wait for the other squads (else
## null).
var _campfire: CampfireWait


func _exit_tree() -> void:
	get_viewport().canvas_cull_mask |= WORLD_VISIBILITY_LAYER


# --- For subclasses to fill in ------------------------------------------------------

## Squads game: our squad round the campfire (scripts/ui/campfire_wait.gd)
## with `text` at the top, until hide_waiting_campfire().
func show_waiting_campfire(text: String) -> void:
	if _campfire:
		_campfire.set_text(text)
		return
	_campfire = CampfireWait.new()
	add_child(_campfire)
	_campfire.open(all_players, text)


func hide_waiting_campfire() -> void:
	if _campfire:
		_campfire.close()
		_campfire = null


## True while a round is being fought (not between rounds or after the end).
func is_wave_running() -> bool:
	return false


## How far apart (centre to centre, on each axis) our living players can get
## and still all be on screen. Players can't walk further apart than this
## (character_body.gd _stay_on_screen).
func max_player_spread() -> Vector2:
	return view_size()


## Spawns an enemy from `scene` at `at` mid-round (a splitter's pieces),
## scaled like the round's enemies and shoved by `knockback`. Returns null
## (and does nothing) between rounds.
func spawn_enemy_at(_scene: PackedScene, _at: Vector2, _elite := false,
		_knockback := Vector2.ZERO) -> Enemy:
	return null


## Squads game: objectives call this when our squad fails one.
func squad_failed_objective(_reason: String) -> void:
	pass


## One of our players was knocked out (connected to each player's `died`).
func _on_player_died(_hit_position: Vector2) -> void:
	pass


## A new player, set up from its character but not yet in the tree.
func _prepare_player(_player: Player) -> void:
	pass


## How enemies are scaled for the number of players (_add_enemy), and for how
## many.
func _enemy_scaling() -> PlayerScaling:
	return wave_set.get_player_scaling()


func _enemy_scaling_count() -> int:
	return all_players.size()


## A new enemy, scaled (and made elite or not), just before it enters the tree.
func _prepare_enemy(_enemy: Enemy) -> void:
	pass


## Every point earned this run is multiplied by this (each player's
## score_multiplier); the end-of-run cash-in shows leftover resources worth
## POINTS_PER_LEFTOVER_RESOURCE times it.
func score_multiplier() -> float:
	return 1.0


## One of our players killed one of our enemies at `at` (after the points and
## drops were handed out).
func _after_enemy_killed(killer: Node, at: Vector2, enemy: Enemy) -> void:
	if class_mod_fx:
		class_mod_fx.on_enemy_died(killer, at, enemy)


# --- Class Mods ---------------------------------------------------------------

## Where a bouncing Class Mod shot (Ricochet) bounces in a game without walls:
## the playing field. Empty: walls only (the Campaign).
func shot_bounds() -> Rect2:
	return Rect2()


## Every player picks a Class Mod (scripts/class_mods/class_mod_picker.gd);
## returns once everyone is ready. Call after a boss fight, with the world
## paused. `rng_seed` deals the cards.
func _pick_class_mods(rng_seed: int, title: String) -> void:
	var picker := ClassModPicker.new()
	add_child(picker)
	picker.open(all_players, rng_seed, title)
	await picker.all_ready


## Ends every Class Mod effect left on the field (marks, traps, puddles...).
func _clear_class_mods() -> void:
	if class_mod_fx:
		class_mod_fx.clear()


## Where drops from another squad's enemy that one of our players killed at
## `at` land: where it died (in Braid that can be across a window, in
## another lane; leftovers are handed out when the wave ends anyway).
func _remote_drop_point(at: Vector2) -> Vector2:
	return at


# --- Players ----------------------------------------------------------------------

## Spawns the players picked on character select (Global.players) under
## $Players, kept inside `bounds`, in formation around the origin. Each gets
## its character's colour, class and starting kit (or the sandbox
## character's hand-set kit).
func _spawn_players(bounds: Rect2) -> void:
	for p in Global.players:
		var player: Player = PLAYER_SCENE.instantiate()
		player.game = self
		player.move_bounds = bounds
		player.player_index = p["slot"]
		player.player_name = p.get("name", "")
		player.device = p["device"]
		player.dummy = Global.dummy_squad
		var character: Dictionary = Global.CHARACTERS[p["character"]]
		player.color = character["color"]
		player.skin = p.get("skin", 0)
		player.class_id = character["class"]
		var loadout := Global.loadout_for_character(p["character"])
		player.attributes = loadout["attributes"]
		player.gun_id = loadout["gun"]
		player.gun_level = loadout["gun_level"]
		player.melee_id = loadout["melee"]
		player.melee_level = loadout["melee_level"]
		player.equipment_id = loadout["equipment"]
		player.position = SPAWN_OFFSETS[p["slot"]] if Global.players.size() > 1 else Vector2.ZERO
		_prepare_player(player)
		players_root.add_child(player)
		all_players.append(player)
		hud.add_player(player)
		if loadout["resources"] > 0:
			player.add_resources(loadout["resources"])
		player.died.connect(_on_player_died)
	class_mod_fx = ClassModFx.new()
	class_mod_fx.setup(self)
	add_child(class_mod_fx)
	for player in all_players:
		class_mod_fx.watch(player)


## Adds the pause menu, with every player's stats card. Call once the players
## are spawned.
func _add_pause_menu(boss_test := false) -> void:
	pause_menu = PauseMenu.new()
	pause_menu.squads_game = squads_game
	pause_menu.boss_test = boss_test
	pause_menu.players = all_players
	add_child(pause_menu)


## Running the scene straight from the editor: the keyboard and every
## connected controller, as the first characters.
func _default_players() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"slot": 0, "device": Global.KEYBOARD, "character": 0}]
	for joy in Input.get_connected_joypads():
		if result.size() >= Global.MAX_PLAYERS:
			break
		var i := result.size()
		result.append({"slot": i, "device": joy, "character": i})
	return result


# --- Pixel-art view -------------------------------------------------------------

## Renders the world at Global.PIXEL_ART_RESOLUTION: the pixel viewport shares
## this scene's 2D world and has the camera, and the main viewport stops
## drawing the world itself (it only draws the UI layers).
func _setup_pixel_view() -> void:
	pixel_viewport.size = Global.PIXEL_ART_RESOLUTION
	pixel_container.size = Vector2(Global.PIXEL_ART_RESOLUTION)
	pixel_viewport.world_2d = get_viewport().world_2d
	camera.custom_viewport = pixel_viewport
	camera.make_current()
	visibility_layer = WORLD_VISIBILITY_LAYER
	get_viewport().canvas_cull_mask &= ~WORLD_VISIBILITY_LAYER
	get_viewport().canvas_transform = Transform2D.IDENTITY
	get_viewport().size_changed.connect(_fit_pixel_view)
	_fit_pixel_view()


## Scales the pixel view up by the largest whole number that fits the window
## (so every world pixel is an even NxN block of screen pixels) and centres it.
func _fit_pixel_view() -> void:
	var res := Vector2(Global.PIXEL_ART_RESOLUTION)
	var screen := Vector2(get_window().size)
	var ui_rect := get_viewport().get_visible_rect()
	if screen.x <= 0.0 or ui_rect.size.x <= 0.0:
		return
	var k := maxf(floorf(minf(screen.x / res.x, screen.y / res.y)), 1.0)
	# The UI is laid out in its own units (Global.BASE_RESOLUTION, scaled to
	# the window), so convert window pixels to those.
	var ui_per_pixel := ui_rect.size.x / screen.x
	var zoom_now := camera.zoom / render_scale
	render_scale = k if Global.SMOOTH_PIXEL_MOTION else 1.0
	pixel_viewport.size = Vector2i(res * render_scale)
	pixel_container.size = res * render_scale
	pixel_container.scale = Vector2.ONE * (k / render_scale) * ui_per_pixel
	camera.zoom = zoom_now * render_scale
	pixel_container.position = ui_rect.position + ((screen - res * k) / 2.0).floor() * ui_per_pixel


## Size of the world view in world units (pixels at zoom 1).
func view_size() -> Vector2:
	return Vector2(Global.PIXEL_ART_RESOLUTION)


## The camera's zoom in world terms (1 = PIXEL_ART_RESOLUTION's worth of world
## on screen), leaving out render_scale.
func world_zoom() -> Vector2:
	return camera.zoom / render_scale


## Where the mouse points in the world (the keyboard player aims with it).
func world_mouse_position() -> Vector2:
	return pixel_viewport.canvas_transform.affine_inverse() * pixel_container.get_local_mouse_position()


## World position -> position in the UI layers' coordinates.
func world_to_ui() -> Transform2D:
	return pixel_container.get_global_transform() * pixel_viewport.canvas_transform


## The part of the UI's coordinates the world is shown in.
func world_view_rect() -> Rect2:
	return Rect2(pixel_container.position, Vector2(pixel_viewport.size) * pixel_container.scale)


# --- Enemies and drops ------------------------------------------------------------

## Adds an enemy from `scene` at `at`, scaled by `health_mult` / `speed_mult`
## (and for the number of players), made elite if `elite`.
func _add_enemy(scene: PackedScene, at: Vector2, health_mult: float, speed_mult: float,
		elite: bool) -> Enemy:
	var enemy: Enemy = scene.instantiate()
	var scaling := _enemy_scaling()
	var count := _enemy_scaling_count()
	enemy.apply_modifiers(health_mult * scaling.health_multiplier(count),
		speed_mult * scaling.speed_multiplier(count))
	if elite:
		enemy.make_elite(scaling)
	_prepare_enemy(enemy)
	if link:
		link.register_enemy(enemy, scene.resource_path)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	# Position before adding to the tree: if it's added first, it briefly exists
	# at the world origin and players there register it as touching them.
	enemy.position = at
	add_child(enemy)
	return enemy


func _on_enemy_died(killer: Node, at: Vector2, enemy: Enemy) -> void:
	# Squads game: if another squad's player finished it off, the kill and the
	# drops are theirs (the link tells their game); we get nothing.
	if link and link.owned_enemy_died(enemy, at):
		return
	if is_instance_valid(killer) and killer is Player:
		killer.record_kill(enemy.points_value)
	_drop_resources(at, enemy.resource_drops)
	_after_enemy_killed(killer, at, enemy)


## Squads game: one of our players (`slot`) finished off another squad's
## enemy at `at`, so the kill and its drops are ours.
func credit_remote_kill(slot: int, points: int, drops: int, at: Vector2) -> void:
	for player in all_players:
		if player.player_index == slot:
			player.record_kill(points)
	_drop_resources(_remote_drop_point(at), drops)


func _drop_resources(at: Vector2, count: int) -> void:
	for i in count:
		var offset := Vector2.ZERO if i == 0 else Vector2.RIGHT.rotated(randf() * TAU) * DROP_SCATTER
		_spawn_resource.call_deferred(at + offset)


func _spawn_resource(at: Vector2) -> void:
	# Drops from an enemy killed in the round's final frame arrive after the
	# field was cleared: hand them straight out instead.
	if not is_inside_tree() or not is_wave_running():
		_on_resource_collected()
		return
	var pickup := ResourcePickup.new()
	pickup.collected.connect(_on_resource_collected)
	pickup.position = at  # before add_child, so it never appears at the origin
	add_child(pickup)


## Whoever picks a resource up, every player (knocked out or not) gets their
## own copy of it.
func _on_resource_collected() -> void:
	for player in all_players:
		player.harvest(1)


# --- End of the run ---------------------------------------------------------------

## End of the run (won or lost): every player's unspent resources become
## points. Returns what the summary screen needs to animate it, as plain data
## so it can be sent to the other squads:
## {"players": [{"label", "slot", "color", "kills", "resources" (cashed in),
##   "points_before"}, ...], "stats": [PlayerStats.snapshot(), ...]}.
func _cash_in_resources() -> Dictionary:
	var players := []
	var stats := []
	for player in all_players:
		stats.append(PlayerStats.snapshot(player))
		var leftover: int = player.resources
		players.append({
			"label": player.display_name(),
			"slot": player.player_index,
			"color": player.color,
			"kills": player.kills,
			"resources": leftover,
			"points_before": player.points,
		})
		player.spend_resources(leftover)
		player.add_points(leftover * POINTS_PER_LEFTOVER_RESOURCE)
	return {"players": players, "stats": stats}


## Cashes in everyone's resources and opens the end-of-run summary. In a
## squads game it shares our results and has pages for every squad: ours
## first, then the rest in order after ours.
func _show_final_summary(title: String, title_color: Color, subtitle: String,
		bonus: int, prompt: String, back_only := false) -> WaveSummary:
	var results := _cash_in_resources()
	var pages: Array[Dictionary] = []
	if squads_game:
		Squads.send_final_results(results)
		var mine := Squads.my_squad()
		var squads := Squads.squads_present()
		squads.sort_custom(func(a: int, b: int) -> bool:
			return posmod(a - mine, Squads.MAX_SQUADS) < posmod(b - mine, Squads.MAX_SQUADS))
		for squad: int in squads:
			pages.append({
				"squad": squad,
				"name": Squads.SQUAD_NAMES[squad],
				"color": Squads.SQUAD_COLORS[squad],
				"results": results if squad == mine else _squad_results.get(squad, {}),
			})
	else:
		pages.append({"squad": -1, "name": "", "color": Color.WHITE, "results": results})

	var summary := WaveSummary.new()
	summary.back_only = back_only
	add_child(summary)
	_final_summary = summary
	summary.show_final(title, title_color, subtitle, bonus, prompt,
		POINTS_PER_LEFTOVER_RESOURCE * score_multiplier(), pages)
	return summary


func _on_squad_final_results(squad: int, results: Dictionary) -> void:
	_squad_results[squad] = results
	if is_instance_valid(_final_summary):
		_final_summary.add_results(squad, results)


## "1:23" for `seconds`.
static func _clock_text(seconds: float) -> String:
	var secs := floori(seconds)
	return "%d:%02d" % [secs / 60, secs % 60]
