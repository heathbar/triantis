extends RefCounted
## Boss Test: fight one boss, kitted out as if the standard run had been
## played up to it. A testing tool, set up from the custom game screen
## (scripts/ui/boss_test_menu.gd) where the sandbox character is offered
## (Global.sandbox_enabled()), local games only. Its Start goes to character
## select with the test armed; the next game is just that boss.
##
## Settings (Global.boss_test, see default_settings()):
##   "active"    - armed for the next game (switched off on going back to
##                 the title, so it can't linger into a real game)
##   "boss"      - boss id (scripts/bosses/boss.gd BOSSES)
##   "wave"      - standard-run wave (index) the fight stands in for, or -1
##                 for the boss's own wave. Sets the starting kit and the
##                 shop's prices.
##   "resources" - multiplies the estimated resources (0 = none, no shop)
##   "health"    - multiplies the boss's health
##
## Scaling, for the wave the fight stands in for:
##   - Resources: what a run would have earned by then, per player: every
##     earlier wave's completion reward, plus the drops of every enemy it
##     spawns (every player gets a copy of each pickup, so more players and
##     elites mean more). Spent all at once in one shop, priced for that wave.
##   - Hearts: every earlier wave's bonus_hearts.
##   - The boss and its enemy trickle: that boss wave's own (health scales
##     with players as usual, see boss.gd). A boss not placed in the run yet
##     borrows the trickle of the closest boss wave at or before the chosen
##     wave, and uses its own default health.


## Choices offered for the "resources" and "health" settings.
const RESOURCE_SCALES := [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]
const HEALTH_SCALES := [0.1, 0.25, 0.5, 1.0, 1.5, 2.0]


static func default_settings() -> Dictionary:
	return {"active": false, "boss": "", "wave": -1, "resources": 1.0, "health": 1.0}


## Global.boss_test with any missing settings filled in.
static func settings() -> Dictionary:
	var s := default_settings()
	s.merge(Global.boss_test, true)
	return s


## True if the next local game is a boss test.
static func is_active() -> bool:
	var s := settings()
	return bool(s["active"]) and Global.sandbox_enabled() and not Squads.is_active() \
		and Boss.exists(str(s["boss"]))


## Every boss, in the order the standard run meets them (ones not placed in
## it yet last): [{"id", "name", "wave" (its wave index, or -1)}, ...].
static func bosses(base: WaveSet) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var seen := {}
	for i in base.waves.size():
		var id := base.waves[i].boss_id
		if Boss.exists(id) and not seen.has(id):
			seen[id] = true
			list.append({"id": id, "name": Boss.boss_info(id)["name"], "wave": i})
	for id in Boss.BOSSES:
		if not seen.has(id):
			list.append({"id": id, "name": Boss.boss_info(id)["name"], "wave": -1})
	return list


## The standard-run wave (index) boss `id` normally is, or -1.
static func boss_wave(base: WaveSet, id: String) -> int:
	for i in base.waves.size():
		if base.waves[i].boss_id == id:
			return i
	return -1


## The standard-run wave (index) the test stands in for.
static func wave_index(base: WaveSet, s: Dictionary) -> int:
	var at := int(s.get("wave", -1))
	if at < 0:
		at = boss_wave(base, str(s.get("boss", "")))
	if at < 0:
		at = base.waves.size() - 1  # Not in the run yet: as its last wave.
	return clampi(at, 0, base.waves.size() - 1)


## Resources each of `player_count` players would have earned before
## standard-run wave `index` (already scaled by s["resources"]).
static func estimated_resources(base: WaveSet, index: int, player_count: int,
		s: Dictionary) -> int:
	var scaling := base.get_player_scaling()
	var drops_per_scene := {}
	var total := 0.0
	for i in mini(index, base.waves.size()):
		var wave := base.waves[i]
		total += wave.reward()
		var elite_chance := scaling.elite_chance(wave.base_elite_chance, player_count)
		for group in wave.enemy_groups:
			if group == null or group.enemy_scene == null:
				continue
			var path := group.enemy_scene.resource_path
			if not drops_per_scene.has(path):
				drops_per_scene[path] = _expected_drops(group.enemy_scene)
			var per_enemy: float = drops_per_scene[path]
			if group.allow_elite:
				per_enemy *= 1.0 + elite_chance * (scaling.elite_reward_multiplier - 1)
			total += group.count * scaling.count_multiplier(player_count) * per_enemy
	return roundi(total * float(s.get("resources", 1.0)))


## Extra max hearts a run would have gained before wave `index`.
static func bonus_hearts(base: WaveSet, index: int) -> int:
	var hearts := 0
	for i in mini(index, base.waves.size()):
		hearts += base.waves[i].bonus_hearts
	return hearts


## Average resources one enemy from `scene` drops.
static func _expected_drops(scene: PackedScene) -> float:
	var enemy := scene.instantiate()
	var drops := float(enemy.get("resource_drops")) if "resource_drops" in enemy else 0.0
	var chance := float(enemy.get("drop_chance")) if "drop_chance" in enemy else 1.0
	enemy.free()
	return drops * chance


## Boss `id`'s health for one player before s["health"]: its wave's
## boss_health, or its own default.
static func base_health(wave: WaveDefinition, id: String) -> int:
	if wave.boss_id == id and wave.boss_health > 0:
		return wave.boss_health
	var script: GDScript = load(Boss.boss_info(id)["script"])
	return int(script.get_script_constant_map().get("DEFAULT_HEALTH", 1000))


## The one-wave run for the test, built from `base` (the standard run). Its
## wave is a copy, so `base` is untouched. The wave it stands in for is kept
## in its price_waves, for the shop.
static func build(base: WaveSet, s: Dictionary) -> WaveSet:
	var id := str(s["boss"])
	var at := wave_index(base, s)
	var source := boss_wave(base, id)
	if source < 0:
		# Not in the run yet: borrow the closest earlier boss wave's trickle.
		for i in range(at, -1, -1):
			if base.waves[i].is_boss_wave():
				source = i
				break
	if source < 0:
		for i in base.waves.size():
			if base.waves[i].is_boss_wave():
				source = i
				break
	var wave: WaveDefinition = (base.waves[source] if source >= 0 else base.waves[at]).duplicate()
	var health := base_health(wave, id)
	wave.boss_id = id
	wave.boss_health = maxi(roundi(health * float(s.get("health", 1.0))), 1)
	wave.bonus_hearts = 0

	var run := WaveSet.new()
	run.display_name = "Boss Test"
	run.player_scaling = base.get_player_scaling()
	run.waves.append(wave)
	var price_waves: Array[int] = [at]
	run.price_waves = price_waves
	return run


## One-line description of what the test will do, for `player_count` players.
static func describe(base: WaveSet, s: Dictionary, player_count: int) -> String:
	var id := str(s.get("boss", ""))
	if not Boss.exists(id):
		return ""
	var at := wave_index(base, s)
	var resources := estimated_resources(base, at, player_count, s)
	var hearts := bonus_hearts(base, at)
	var text := "%s, kitted out as wave %d" % [Boss.boss_info(id)["name"], at + 1]
	if boss_wave(base, id) < 0:
		text += " (not in the run yet)"
	text += ":\n%d resources each%s, %s, boss health %d%%" % [
		resources, " (%d players)" % player_count if player_count > 1
			else " solo (more with more players)",
		"+%d heart%s" % [hearts, "" if hearts == 1 else "s"] if hearts > 0 else "no bonus hearts",
		roundi(float(s.get("health", 1.0)) * 100)]
	if resources <= 0:
		text += "\nNo resources: straight into the fight, no shop."
	return text
