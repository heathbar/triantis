extends RefCounted
## Custom Game (Global.MODE_CUSTOM): the run is built from the standard run's
## first N waves with only the chosen enemy types in them. Every
## `objective_every`th wave (not boss waves) is an objective wave, drawn from
## the chosen objective types; with 0 or no types chosen, the waves are plain
## survive-the-clock waves.
##
## Settings are a Dictionary (see default_settings), shared with every squad
## in a squads game (Squads.custom_settings).
##
## A wave that loses some of its enemy types gets more of the types it keeps,
## so it stays about as tough (see THREAT). A wave left with none of its
## types gets an even mix of the chosen ones instead.

## Every enemy type that can be picked. "scene" matches WaveEnemyGroup.enemy_scene.
const ENEMIES := [
	{"id": "grunt", "name": "Grunt", "scene": "res://scenenodethings/enemy.tscn"},
	{"id": "runner", "name": "Runner", "scene": "res://scenenodethings/enemies/runner.tscn"},
	{"id": "swarmling", "name": "Swarmling", "scene": "res://scenenodethings/enemies/swarmling.tscn"},
	{"id": "brute", "name": "Brute", "scene": "res://scenenodethings/enemies/brute.tscn"},
	{"id": "charger", "name": "Charger", "scene": "res://scenenodethings/enemies/charger.tscn"},
	{"id": "bomber", "name": "Bomber", "scene": "res://scenenodethings/enemies/bomber.tscn"},
	{"id": "splitter", "name": "Splitter", "scene": "res://scenenodethings/enemies/splitter.tscn"},
	{"id": "shooter", "name": "Shooter", "scene": "res://scenenodethings/enemies/shooter.tscn"},
	{"id": "sprayer", "name": "Sprayer", "scene": "res://scenenodethings/enemies/sprayer.tscn"},
]

## Rough toughness of one enemy of each type (about its health), used to swap
## removed enemies for the right number of the kept ones.
const THREAT := {
	"grunt": 10.0, "runner": 6.0, "swarmling": 2.0, "brute": 80.0,
	"charger": 25.0, "bomber": 12.0, "splitter": 35.0, "shooter": 18.0,
	"sprayer": 20.0,
}

## A wave never gets more than this many times its usual number of enemies
## (lots of swarmlings standing in for brutes would be too many bodies).
const MAX_COUNT_FACTOR := 1.5

const MIN_WAVES := 1
## Range of the "objective wave every N waves" setting; 0 = no objectives.
const MAX_OBJECTIVE_EVERY := 10
const DEFAULT_OBJECTIVE_EVERY := 4
## The art theme: enemies, ground and shop. "campaign" changes it after each
## boss in the campaign's act order (game.gd); otherwise an ActTheme.THEMES
## id for the whole run.
const CAMPAIGN_THEME := "campaign"
const DEFAULT_THEME := CAMPAIGN_THEME
const ActTheme := preload("res://scripts/act_theme.gd")


## The theme choices, in menu order: {"id", "name"}.
static func theme_choices() -> Array:
	return [{"id": CAMPAIGN_THEME, "name": "Campaign"}] + ActTheme.THEMES



static func default_settings(max_waves: int) -> Dictionary:
	return {
		"waves": max_waves,
		"enemies": ENEMIES.map(func(e: Dictionary) -> String: return e["id"]),
		"objectives": Objective.TYPES.map(func(t: Dictionary) -> String: return t["id"]),
		"objective_every": DEFAULT_OBJECTIVE_EVERY,
		"theme": DEFAULT_THEME,
	}


## `settings` cleaned up (e.g. as received from the network): known ids only,
## wave count in range, at least one enemy type.
static func sanitize(settings: Dictionary, max_waves: int) -> Dictionary:
	var known_enemies := ENEMIES.map(func(e: Dictionary) -> String: return e["id"])
	var known_objectives := Objective.TYPES.map(func(t: Dictionary) -> String: return t["id"])
	var enemies: Array[String] = []
	for id in settings.get("enemies", known_enemies):
		if str(id) in known_enemies and not str(id) in enemies:
			enemies.append(str(id))
	if enemies.is_empty():
		enemies.assign(known_enemies)
	var objectives: Array[String] = []
	for id in settings.get("objectives", known_objectives):
		if str(id) in known_objectives and not str(id) in objectives:
			objectives.append(str(id))
	var theme := str(settings.get("theme", DEFAULT_THEME))
	if not theme_choices().any(func(t: Dictionary) -> bool: return t["id"] == theme):
		theme = DEFAULT_THEME
	return {
		"theme": theme,
		"waves": clampi(int(settings.get("waves", max_waves)), MIN_WAVES, max_waves),
		"enemies": enemies,
		"objectives": objectives,
		"objective_every": clampi(int(settings.get("objective_every", DEFAULT_OBJECTIVE_EVERY)),
			0, MAX_OBJECTIVE_EVERY),
	}


## The run for `settings`, built from `base` (the standard run). `base` and
## its waves are left untouched.
static func build(base: WaveSet, settings: Dictionary) -> WaveSet:
	settings = sanitize(settings, base.wave_count())
	var allowed: Array[String] = settings["enemies"]
	var templates := _group_templates(base)

	var run := WaveSet.new()
	run.display_name = "Custom"
	run.player_scaling = base.get_player_scaling()
	for i in settings["waves"]:
		run.waves.append(_custom_wave(base.waves[i], allowed, templates))
	return run


## Enemy type id of `group`, or "" if it isn't one of ENEMIES.
static func group_type(group: WaveEnemyGroup) -> String:
	if group == null or group.enemy_scene == null:
		return ""
	for e in ENEMIES:
		if e["scene"] == group.enemy_scene.resource_path:
			return e["id"]
	return ""


## Type id -> the first group of that type in the standard run, so a stand-in
## group gets the usual cluster size and elite rule for its type.
static func _group_templates(base: WaveSet) -> Dictionary:
	var templates := {}
	for wave in base.waves:
		for group in wave.enemy_groups:
			var id := group_type(group)
			if not id.is_empty() and not templates.has(id):
				templates[id] = group
	return templates


static func _custom_wave(source: WaveDefinition, allowed: Array[String],
		templates: Dictionary) -> WaveDefinition:
	var wave: WaveDefinition = source.duplicate()
	var budget := 0.0
	var total := 0
	var kept: Array[WaveEnemyGroup] = []
	for group in source.enemy_groups:
		var id := group_type(group)
		if id.is_empty():
			continue
		budget += group.count * THREAT[id]
		total += group.count
		if id in allowed:
			kept.append(group.duplicate())

	if kept.is_empty():
		# None of this wave's enemies are allowed: an even mix of the chosen ones.
		for id in allowed:
			var group: WaveEnemyGroup = templates[id].duplicate() if templates.has(id) \
				else WaveEnemyGroup.new()
			if not templates.has(id):
				group.enemy_scene = load(_scene_for(id))
			group.health_multiplier = 1.0
			group.speed_multiplier = 1.0
			group.count = maxi(1, roundi(budget / allowed.size() / THREAT[id]))
			kept.append(group)
		_scale_counts(kept, 1.0, total)
	else:
		var kept_threat := 0.0
		for group in kept:
			kept_threat += group.count * THREAT[group_type(group)]
		if kept_threat < budget:
			_scale_counts(kept, budget / kept_threat, total)

	wave.enemy_groups = kept
	return wave


## Multiply every group's count by `factor`, but keep the total under
## MAX_COUNT_FACTOR x `usual_total`.
static func _scale_counts(groups: Array[WaveEnemyGroup], factor: float, usual_total: int) -> void:
	var count := 0
	for group in groups:
		count += group.count
	if count == 0:
		return
	var cap := maxf(usual_total * MAX_COUNT_FACTOR, groups.size())
	factor = minf(factor, cap / float(count))
	for group in groups:
		group.count = maxi(1, roundi(group.count * factor))


static func _scene_for(id: String) -> String:
	for e in ENEMIES:
		if e["id"] == id:
			return e["scene"]
	return ENEMIES[0]["scene"]
