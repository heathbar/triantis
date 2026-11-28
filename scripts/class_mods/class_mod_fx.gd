extends Node2D
## Makes Class Mods (scripts/class_mods/class_mod.gd) happen in play, for
## our squad's players, in the arena and the Campaign alike (GameBase adds
## one and watch()es each player as they spawn).
##
## What it needs from the game: all_players, is_wave_running(),
## _drop_resources(), shot_bounds() (where Ricochet shots bounce in a game
## without walls) and `link` (another squad's game, if any: shots are
## reported to it, and when it has send_mark / remote_player_keys / send_heal,
## marks and heals reach other squads too). A player can have several branches going at once, so everything
## here looks picks up by mechanic (ClassMod.mechanics) and stacks
## what applies. It hooks the players' existing weapons from outside:
##   - each shot a player fires (their shot_fired signal) is swapped for a
##     ModShot (scripts/class_mods/mod_shot.gd) carrying every gun Class Mod
##     they have, plus a burst after it for Fan / Spray,
##   - a Laser Sight beam along each aiming player's line of fire,
##   - each melee swing (a MeleeSwing child added to the player) is widened
##     (spin), carries the player forward (lunge), throws shots (wave), sends
##     a ring (ring) or shoves (shove), and its hits feed Combo / Bulwark,
##   - attribute boosts (Player.add_boost) for the timed and conditional
##     ones: Drum Mag, Emplacement, Run & Gun, Hit & Run, Stim Darts...,
##   - Player.hit_filter for Riposte blocks and Triage shields.
## It also keeps what those leave behind: marks and shred on enemies,
## poison / fire / bleed, spike traps, burning lines and puddles, and heals
## for our players (and other squads', through the link).

const CharacterClasses := preload("res://scripts/character_classes.gd")
const ClassMod := preload("res://scripts/class_mods/class_mod.gd")
const ModShot := preload("res://scripts/class_mods/mod_shot.gd")
const MeleeSwing := preload("res://scripts/melee_swing.gd")
const Projectile := preload("res://scripts/projectile.gd")
const BossBody := preload("res://scripts/bosses/boss_body.gd")
const Visuals := preload("res://scripts/class_mods/mod_fx_visuals.gd")
const Blast := preload("res://scripts/equipment/blast.gd")

const TINTS := {
	"pierce": Color(0.55, 0.9, 1.0), "mark": Color(1.0, 0.4, 0.4), "ricochet": Color(1.0, 0.9, 0.4),
	"flak": Color(1.0, 0.75, 0.3), "nail": Color(0.8, 0.8, 0.85), "mortar": Color(1.0, 0.5, 0.2),
	"chain": Color(0.6, 0.8, 1.0), "heal": Color(0.4, 1.0, 0.5), "toxin": Color(0.6, 1.0, 0.2),
	"fan": Color(1.0, 0.95, 0.7), "wave": Color(0.7, 0.9, 1.0), "laser": Color(1.0, 0.2, 0.2),
	"grenade": Color(1.0, 0.6, 0.25), "slow": Color(0.55, 0.8, 1.0), "drum": Color(1.0, 0.95, 0.6),
	"shred": Color(1.0, 0.55, 0.7), "salvage": Color(0.95, 0.85, 0.4), "recycler": Color(0.6, 1.0, 0.8),
	"overclock": Color(0.5, 0.9, 1.0), "stim": Color(1.0, 0.5, 0.9), "burn": Color(1.0, 0.45, 0.15),
	"push": Color(0.9, 0.8, 0.6), "brace": Color(0.9, 0.9, 0.7), "tracer": Color(1.0, 0.35, 0.3),
	"moving": Color(0.5, 1.0, 1.0), "hitrun": Color(0.7, 1.0, 0.6), "concussion": Color(0.8, 0.65, 1.0),
	"ring": Color(0.9, 0.8, 0.6),
}
## Fan bursts: seconds between the shots.
const FAN_GAP := 0.06
## Heals: half hearts, and seconds before the same player can be healed again.
const HEAL_AMOUNT := 1
const HEAL_COOLDOWN := 1.0
## Spike traps: radius, seconds between hits, damage x the rivet's.
const SPIKE_RADIUS := 10.0
const SPIKE_TICK := 0.35
const SPIKE_DAMAGE := 0.5
## Seconds a Shredder stack lasts after the last hit.
const SHRED_SECS := 4.0
## Seconds between Bulwark thorn hits.
const THORN_TICK := 0.5
## Riposte: how close an enemy must be to be countered / stunned.
const RIPOSTE_REACH := 32.0
## Lunges: how close to the path an enemy or squadmate counts as passed.
const PATH_REACH := 10.0
## Laser Sight: how wide the beam is for finding enemies on it, and how long
## its boosts stay on after it slips off an enemy (so they don't flicker).
const LASER_WIDTH := 4.0
const LASER_GRACE := 0.25

## The game scene (a GameBase: scripts/game.gd or scripts/braid/braid_game.gd).
var game: Node2D
## Our players -> their running state (see _new_state).
var _st := {}
## Marked enemies: instance id -> {"enemy", "until", "reticle", "mult", "spread", "drop"}.
var _marks := {}
## Shredded enemies: instance id -> {"enemy", "stacks", "per", "until"}.
var _shred := {}
## Suppression: enemy instance id -> [hit times].
var _suppress := {}
## Bulldozer III: [{"enemy", "until", "stun"}] watched for hitting a wall.
var _shoved: Array[Dictionary] = []
## Juggernaut III: [{"enemy", "until", "amount", "source", "done"}].
var _thrown: Array[Dictionary] = []
## Heal cooldowns: our player -> time, or "squad:slot" -> time.
var _healed := {}
## Side Step III cooldowns: player -> time.
var _stepped := {}
## Triage III: players with a shield (player -> true).
var _shields := {}
## Stim Darts III: knocked-out player -> shots that passed them.
var _revive_hits := {}
## Spike traps per shooter: instance id -> [spike, ...].
var _spikes := {}
## Burning lines and puddles.
var _hazards: Array[Node] = []
## Attribute boosts: "player id:kind" -> {"player", "key" (the boost's
## source object), "effects"}.
var _boosts := {}
## Laser Sight's enemy query (one, reused every frame).
var _laser_query: PhysicsShapeQueryParameters2D
var _time := 0.0


func setup(game_node: Node2D) -> void:
	game = game_node
	z_index = 30


func watch(player: Node) -> void:
	player.shot_fired.connect(_on_shot.bind(player))
	player.child_entered_tree.connect(_on_child.bind(player))
	player.hit_filter = _filter_hit.bind(player)
	_st[player] = _new_state(player)


func _new_state(player: Node) -> Dictionary:
	return {
		"shots": 0, "volley": -1, "drum": 0.0, "still": 0.0, "kills": 0,
		"laser": [], "laser_on": -INF,
		"lunge_bonus": false, "swing_at": -INF, "next_double": false, "swings": 0,
		"combo": 0, "combo_at": -INF, "bulwark": 0, "bulwark_at": -INF, "thorn": 0.0,
		"hitrun": 0, "timed": {},
	}


func _physics_process(delta: float) -> void:
	_time += delta
	for id in _marks.keys():
		var m: Dictionary = _marks[id]
		if not is_instance_valid(m["enemy"]) or _time >= m["until"]:
			_unmark(id)
	for id in _shred.keys():
		var sh: Dictionary = _shred[id]
		if not is_instance_valid(sh["enemy"]) or _time >= sh["until"]:
			_shred.erase(id)
			if is_instance_valid(sh["enemy"]):
				_refresh_taken(sh["enemy"])
	for player in _st.keys():
		if is_instance_valid(player):
			_tick_player(player, delta)
	_tick_shoved()
	_tick_thrown()
	queue_redraw()


# --- Per player, every frame ---------------------------------------------------

func _tick_player(p: Node, delta: float) -> void:
	var ev := ClassMod.mechanics(p)
	var s: Dictionary = _st[p]
	var alive: bool = not p.is_dead() and game.is_wave_running()
	# No shooting while meleeing (Player.melee_busy), so no aim for gun mods.
	var aim: Vector2 = p._read_aim() if alive and not p.melee_busy() else Vector2.ZERO
	var moving: bool = alive and p._read_direction() != Vector2.ZERO

	if ev.has("laser"):
		_tick_laser(p, s, ev["laser"], aim, alive)
	if ev.has("drum"):
		var st: Dictionary = ev["drum"]
		s["drum"] = s["drum"] + delta if aim != Vector2.ZERO and not p.overheated else 0.0
		var pct := snappedf(minf(st["per_sec"] * s["drum"], st["max"]), 0.05)
		_set_boost(p, "drum", {"fire_rate": _attr(pct)} if pct > 0.0 else {})
	if ev.has("brace"):
		var st: Dictionary = ev["brace"]
		s["still"] = s["still"] + delta if alive and not moving else 0.0
		var on: bool = s["still"] >= st["after"]
		var effects := {}
		if on:
			effects["ranged_damage"] = _attr(st["dmg"])
			if st.has("armor"):
				effects["armor"] = int(st["armor"])
		_set_boost(p, "brace", effects)
	if ev.has("moving"):
		_set_boost(p, "moving", {"ranged_damage": _attr(ev["moving"]["dmg"])} if moving else {})
	if ev.has("combo") and s["combo"] > 0 and _time - s["combo_at"] > ev["combo"]["window"]:
		s["combo"] = 0
		_set_boost(p, "combo", {})
	if ev.has("bulwark"):
		var st: Dictionary = ev["bulwark"]
		if s["bulwark"] > 0 and _time - s["bulwark_at"] > st["secs"]:
			s["bulwark"] = 0
			_set_boost(p, "bulwark", {})
		if alive and s["bulwark"] >= st["max"] and st.has("thorns"):
			s["thorn"] -= delta
			if s["thorn"] <= 0.0:
				s["thorn"] = THORN_TICK
				_thorns(p, st["thorns"])
	for kind in s["timed"].keys():
		if _time >= s["timed"][kind]:
			s["timed"].erase(kind)
			_set_boost(p, kind, {})
			if kind == "hitrun":
				s["hitrun"] = 0
				p.set_contact_shield(_boost_key(p, "hitrun_shield"), false)


## Laser Sight: while the player aims, a beam runs from the muzzle as far as
## the gun reaches, stopped by walls and by the first enemy on it (it's
## drawn in _draw). While it's on an enemy, or was within LASER_GRACE s, the
## player gets the stage's fire rate, speed and armor.
func _tick_laser(p: Node, s: Dictionary, st: Dictionary, aim: Vector2, alive: bool) -> void:
	s["laser"] = []
	if aim != Vector2.ZERO and not p.is_carrying() and not p.is_mounted():
		var from: Vector2 = p.global_position + aim * Player.MUZZLE_DISTANCE
		var to: Vector2 = from + aim * p.shot_speed * p.shot_lifetime
		var space := get_world_2d().direct_space_state
		var ray := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WALLS)
		ray.hit_from_inside = true  # the muzzle can poke into a wall
		var wall := space.intersect_ray(ray)
		if not wall.is_empty():
			to = wall["position"]
		var target := _laser_target(space, from, to, aim)
		if target:
			to = from + aim * maxf(aim.dot(target.global_position - from), 0.0)
			s["laser_on"] = _time
		s["laser"] = [from, to, target != null]
	var effects := {}
	if alive and _time - s["laser_on"] <= LASER_GRACE:
		effects["fire_rate"] = _attr(st["rate"], "fire_rate")
		if st.has("speed"):
			effects["speed"] = _attr(st["speed"], "speed")
		if st.has("armor"):
			effects["armor"] = int(st["armor"])
	_set_boost(p, "laser", effects)


## The enemy nearest `from` on the beam from `from` to `to`, or null.
func _laser_target(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, aim: Vector2) -> Node2D:
	if _laser_query == null:
		_laser_query = PhysicsShapeQueryParameters2D.new()
		_laser_query.shape = RectangleShape2D.new()
		_laser_query.collision_mask = PhysicsLayers.ENEMIES
	(_laser_query.shape as RectangleShape2D).size = Vector2(maxf(from.distance_to(to), 1.0), LASER_WIDTH)
	_laser_query.transform = Transform2D(aim.angle(), (from + to) / 2.0)
	var best: Node2D = null
	var best_dist := INF
	for result in space.intersect_shape(_laser_query):
		var enemy: Node2D = result.collider
		if not (enemy.is_in_group("enemies") and enemy.has_method("take_damage")):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		var d := from.distance_squared_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


# --- Attribute boosts --------------------------------------------------------------

## The `attribute_id` boost that gives x (1 + pct) (CharacterClasses.stat_multiplier
## is exponential up to its +100 multiplier).
static func _attr(pct: float, attribute_id: String = "") -> int:
	var top := CharacterClasses.mult_limits(attribute_id).y
	return roundi(100.0 * log(1.0 + pct) / log(top)) if pct > 0.0 else 0


func _boost_key(p: Node, kind: String) -> Object:
	var key := "%d:%s" % [p.get_instance_id(), kind]
	if not _boosts.has(key):
		_boosts[key] = {"player": p, "key": RefCounted.new(), "effects": {}}
	return _boosts[key]["key"]


## Sets `p`'s `kind` boost to `effects` ({} = none), only touching the
## player's stats when it changes.
func _set_boost(p: Node, kind: String, effects: Dictionary) -> void:
	var obj := _boost_key(p, kind)
	var entry: Dictionary = _boosts["%d:%s" % [p.get_instance_id(), kind]]
	if entry["effects"] == effects:
		return
	entry["effects"] = effects
	if effects.is_empty():
		p.remove_boost(obj)
	else:
		p.add_boost(obj, effects)


## A boost that lasts `secs` (refreshed if it's already on).
func _timed(p: Node, kind: String, effects: Dictionary, secs: float) -> void:
	if not _st.has(p):
		return
	_st[p]["timed"][kind] = _time + secs
	_set_boost(p, kind, effects)


# --- Guns ---------------------------------------------------------------------

func _on_shot(shot: Node, player: Node) -> void:
	if not is_instance_valid(shot) or shot.get_script() == ModShot:
		return
	var ev := ClassMod.mechanics(player)
	if ev.is_empty():
		return
	var s: Dictionary = _st[player]
	var frame := Engine.get_physics_frames()
	var first: bool = s["volley"] != frame
	if first:
		s["volley"] = frame
		s["shots"] += 1
	var modded := _copy(shot, player, _tint_for(ev))
	_apply(modded, player, ev, first)
	_kill(shot)
	shot.get_parent().add_child(modded)
	# "every" N: only every Nth volley is a burst (default every one).
	if first and ev.has("fan") and s["shots"] % int(ev["fan"].get("every", 1)) == 0:
		var st: Dictionary = ev["fan"]
		var extra := int(st["extra"])
		for k in extra:
			var timer := get_tree().create_timer(FAN_GAP * (k + 1), false, true)
			timer.timeout.connect(_fan_shot.bind(player, shot.direction, shot.damage, shot.lifetime,
				shot.speed, shot.size, shot.knockback, k == extra - 1 and st.has("home_last")))


## Puts every gun Class Mod `player` has (`ev`) on shot `s`. `first` is the
## first shot of a volley (per-volley things: every-Nth shots, the lunge
## bonus).
func _apply(s: Node, player: Node, ev: Dictionary, first: bool) -> void:
	var state: Dictionary = _st[player]
	var st: Dictionary
	if ev.has("pierce"):
		st = ev["pierce"]
		s.pierce_left += int(st["pierce"])
		s.pierce_gain = st["gain"]
		s.line_secs = st.get("line", 0.0)
		s.big_bonus = st.get("big", 0.0)
		s.pierced_mark = st.get("pierced_mark", 1.0)
		s.pierced_secs = st.get("pierced_secs", 0.0)
	if ev.has("mark"):
		st = ev["mark"]
		s.mark_mult = st["mult"]
		s.mark_secs = st["secs"]
		s.mark_spread = st.get("spread", 0.0)
		s.mark_drop = int(st.get("drop", 0))
	if ev.has("tracer") and first and state["shots"] % int(ev["tracer"]["every"]) == 0:
		st = ev["tracer"]
		s.mark_mult = st["mult"]
		s.mark_secs = st["secs"]
		s.mark_spread = st.get("spread", 0.0)
		s.tint = TINTS["tracer"]
		s.size = Vector2(s.size.x + 3.0, s.size.y + 1.0)
	if ev.has("ricochet"):
		st = ev["ricochet"]
		s.bounces_left = int(st["bounces"])
		s.edge_bounds = game.shot_bounds()
		s.bounce_gain = st["gain"]
		s.seek = st.get("seek", false)
	if ev.has("grenade") and first and state["shots"] % int(ev["grenade"]["every"]) == 0:
		st = ev["grenade"]
		s.burst_radius = st["radius"]
		s.burst_mult = st["dmg"]
		s.bomblets = int(st.get("bomblets", 0))
		s.size = Vector2(5, 5)
		s.tint = TINTS["grenade"]
	if ev.has("slow"):
		s.slow_mult = ev["slow"]["mult"]
		s.slow_secs = ev["slow"]["secs"]
	if ev.has("drum") and ev["drum"].has("pierce") \
			and state["drum"] * ev["drum"]["per_sec"] >= ev["drum"]["max"]:
		s.pierce_left += int(ev["drum"]["pierce"])
	if ev.has("moving") and ev["moving"].has("pierce") and player._read_direction() != Vector2.ZERO:
		s.pierce_left += int(ev["moving"]["pierce"])
	if ev.has("fan") and ev["fan"].has("pierce"):
		s.pierce_left += int(ev["fan"]["pierce"])
	if ev.has("heal"):
		s.heal = true
		s.heal_remote = ev["heal"]["remote"]
	if ev.has("stim"):
		s.stim = true
	if ev.has("toxin"):
		st = ev["toxin"]
		s.toxin_dps = st["dps"]
		s.toxin_secs = st["secs"]
		s.toxin_spread = st["spread"]
		s.toxin_heals = st.get("heal_kill", false)
	if ev.has("push"):
		s.knockback = s.knockback * ev["push"]["push"] + ev["push"]["add"]
	if ev.has("concussion"):
		st = ev["concussion"]
		s.knockback = s.knockback * st["push"] + 6.0
		s.stun_secs = maxf(s.stun_secs, st["stun"])
		s.blast_radius = maxf(s.blast_radius, st["blast"])
	if ev.has("flak"):
		s.flak_shards = int(ev["flak"]["shards"])
		s.flak_at = ev["flak"]["at"]
	if ev.has("chain"):
		st = ev["chain"]
		s.chain_jumps = int(st["jumps"])
		s.chain_share = st["share"]
		s.chain_gadgets = st.get("gadgets", false)
	if ev.has("nail"):
		s.nail_secs = ev["nail"]["secs"]
	if ev.has("mortar"):
		st = ev["mortar"]
		s.mortar_radius = st["radius"]
		s.mortar_damage = st["dmg"]
		s.puddle_secs = st.get("puddle", 0.0)
		s.size = Vector2(5, 5)
	if not first:
		return
	if state["lunge_bonus"] and ev.has("lunge") and ev["lunge"].has("next_shot"):
		state["lunge_bonus"] = false
		s.damage = roundi(s.damage * ev["lunge"]["next_shot"])
		s.size = Vector2(s.size.x, s.size.y + 1.0)


## The colour for `ev`'s shots: its first gun branch's.
func _tint_for(ev: Dictionary) -> Color:
	for mech in ev:
		if ev[mech]["slot"] == "gun":
			return TINTS.get(mech, Color.WHITE)
	return Color.WHITE


## A ModShot with `shot`'s flight (direction, damage, range, look).
func _copy(shot: Node, player: Node, tint: Color) -> Node:
	var s := ModShot.new()
	s.direction = shot.direction
	s.damage = shot.damage
	s.lifetime = shot.lifetime
	s.speed = shot.speed
	s.size = shot.size
	s.knockback = shot.knockback
	s.overkill = shot.overkill
	s.shooter = player
	s.fx = self
	s.tint = tint
	s.position = shot.global_position
	return s


## Removes a projectile before it ever moves.
func _kill(shot: Node) -> void:
	shot.set_physics_process(false)
	shot.remove_from_group("projectiles")
	shot.queue_free()


func _fan_shot(player: Node, dir: Vector2, damage: int, life: float, spd: float, sz: Vector2,
		kb: float, homing: bool) -> void:
	if not is_instance_valid(player) or player.is_dead() or not game.is_wave_running():
		return
	var ev := ClassMod.mechanics(player)
	var s := ModShot.new()
	s.direction = dir.rotated(randf_range(-0.05, 0.05))
	s.damage = damage
	s.lifetime = life
	s.speed = spd
	s.size = sz
	s.knockback = kb
	s.overkill = player.shot_overkill
	s.shooter = player
	s.fx = self
	s.tint = _tint_for(ev)
	s.position = player.global_position + dir * 14.0
	_apply(s, player, ev, false)
	s.homing = homing
	player.get_parent().add_child(s)
	if game.link:
		game.link.report_shot(s)


## Everything a hit from one of our ModShots does that the shot itself
## doesn't (it has already dealt its damage).
func on_shot_hit(shot: Node, enemy: Node) -> void:
	var p: Node = shot.shooter
	if not is_instance_valid(p) or not _st.has(p):
		return
	if shot.has_meta("melee"):
		_on_melee_hit(enemy, p, null)
		return
	var ev := ClassMod.mechanics(p)
	if ev.has("overclock"):
		p.equipment_cooldown = maxf(p.equipment_cooldown - ev["overclock"]["per_hit"], 0.0)
	if shot.is_shard and ev.has("flak") and ev["flak"].get("combo", false) and ev.has("combo"):
		_combo_hit(p, ev["combo"])
	if not is_instance_valid(enemy) or enemy is BossBody or enemy.is_dead():
		return
	if ev.has("slow") and ev["slow"].has("stun_hits"):
		var st: Dictionary = ev["slow"]
		var id := enemy.get_instance_id()
		var times: Array = _suppress.get(id, [])
		times = times.filter(func(t: float) -> bool: return _time - t <= 1.0)
		times.append(_time)
		if times.size() >= int(st["stun_hits"]):
			times.clear()
			enemy.apply_slow(0.02, st["stun"])
			Visuals.ring(game, enemy.global_position, 10.0, TINTS["slow"])
		_suppress[id] = times
	if ev.has("shred"):
		_shred_hit(enemy, ev["shred"], p, shot.damage)
	if ev.has("burn"):
		var st: Dictionary = ev["burn"]
		poison(enemy, maxf(shot.damage * st["dps"], 1.0), st["secs"], 0.0, p, false, "burn",
			st.get("explode", 0.0), int(st.get("stacks", 1)))
	if ev.has("push") and ev["push"].has("wall_stun"):
		_shoved.append({"enemy": enemy, "until": _time + 0.5, "stun": ev["push"]["wall_stun"]})


func _shred_hit(enemy: Node, st: Dictionary, p: Node, shot_damage: int) -> void:
	var id := enemy.get_instance_id()
	var sh: Dictionary = _shred.get(id, {"enemy": enemy, "stacks": 0})
	sh["stacks"] = mini(sh["stacks"] + 1, int(st["max"]))
	sh["per"] = st["per"]
	sh["until"] = _time + SHRED_SECS
	_shred[id] = sh
	_refresh_taken(enemy)
	if sh["stacks"] >= int(st["max"]) and st.has("bleed"):
		poison(enemy, maxf(shot_damage * st["bleed"], 1.0), 3.0, 0.0, p, false, "bleed")


## Bulldozer III: a shoved enemy that runs into a wall is stunned.
func _tick_shoved() -> void:
	for i in range(_shoved.size() - 1, -1, -1):
		var e: Dictionary = _shoved[i]
		var enemy: Variant = e["enemy"]
		if not is_instance_valid(enemy) or _time >= e["until"] or enemy.is_dead():
			_shoved.remove_at(i)
			continue
		for k in enemy.get_slide_collision_count():
			var collider: Variant = enemy.get_slide_collision(k).get_collider()
			if collider is CollisionObject2D and collider.collision_layer & PhysicsLayers.WALLS:
				enemy.apply_slow(0.02, e["stun"])
				Visuals.ring(game, enemy.global_position, 12.0, TINTS["push"])
				_shoved.remove_at(i)
				break


# --- Melee ----------------------------------------------------------------------

func _on_child(node: Node, player: Node) -> void:
	if node.get_script() != MeleeSwing:
		return
	var ev := ClassMod.mechanics(player)
	if ev.is_empty():
		return
	var s: Dictionary = _st[player]
	s["swing_at"] = _time
	s["swings"] += 1
	node.hit_enemy.connect(_on_melee_hit.bind(player, node))
	if s["next_double"]:
		s["next_double"] = false
		node.damage *= 2
	if ev.has("mark") and ev["mark"].get("melee_double", false):
		node.damage_for = _dead_eye
	var facing := Vector2.from_angle(player.body.rotation)
	if ev.has("combo") and ev["combo"].has("slam") and s["combo"] >= int(ev["combo"]["max"]):
		var st: Dictionary = ev["combo"]
		s["combo"] = 0
		_set_boost(player, "combo", {})
		_area(player.global_position, st["slam"], player.melee_damage, player, st["stun"])
		Visuals.ring(game, player.global_position, st["slam"], TINTS["ring"])
	if ev.has("spin"):
		var st: Dictionary = ev["spin"]
		node.arc = TAU
		node.reach *= st["reach"]
		if st.has("extend"):
			_top_up_equipment(player, node.reach, st["extend"])
		if st.get("twice", false):
			var timer := get_tree().create_timer(0.15, false, true)
			timer.timeout.connect(_second_spin.bind(player, node.reach))
	if ev.has("lunge"):
		_lunge(player, ev["lunge"], facing)
	if ev.has("shove"):
		node.knockback = maxf(node.knockback, ev["shove"]["push"])
	if ev.has("wave"):
		var st: Dictionary = ev["wave"]
		var count := int(st["count"])
		for k in count:
			var angle := 0.0 if count == 1 else lerpf(-0.3, 0.3, float(k) / (count - 1))
			var s2 := ModShot.new()
			s2.direction = facing.rotated(angle)
			s2.damage = maxi(roundi(player.melee_damage * 0.7), 1)
			s2.lifetime = st["range"]
			s2.speed = 340.0
			s2.size = Vector2(6, st["width"])
			s2.pierce_left = 99
			s2.through_walls = st.get("walls", false)
			s2.returns = st.get("returns", false)
			s2.shooter = player
			s2.fx = self
			s2.tint = TINTS["wave"]
			s2.set_meta("melee", true)
			s2.position = player.global_position + facing * 14.0
			player.get_parent().add_child(s2)
	if ev.has("ring"):
		var st: Dictionary = ev["ring"]
		var at: Vector2 = player.global_position
		if st.has("quake_every") and s["swings"] % int(st["quake_every"]) == 0:
			_area(at, st["quake"], player.melee_damage, player, maxf(st["stun"], 0.4), true)
			Visuals.ring(game, at, st["quake"], TINTS["ring"])
		else:
			_area(at, node.inner + st["radius"], maxi(roundi(player.melee_damage * 0.7), 1), player,
				st["stun"], true)
			Visuals.ring(game, at, node.inner + st["radius"], TINTS["ring"])


## A melee hit by `player` (a swing, or one of its waves, rings or slams:
## `swing` is null then).
func _on_melee_hit(enemy: Node, player: Node, swing: Node) -> void:
	if not is_instance_valid(player) or not _st.has(player):
		return
	var ev := ClassMod.mechanics(player)
	if ev.has("combo"):
		_combo_hit(player, ev["combo"])
	if ev.has("bulwark"):
		var st: Dictionary = ev["bulwark"]
		var s: Dictionary = _st[player]
		s["bulwark"] = mini(s["bulwark"] + int(st["per"]), int(st["max"]))
		s["bulwark_at"] = _time
		_set_boost(player, "bulwark", {"armor": s["bulwark"]})
	if not is_instance_valid(enemy) or enemy is BossBody:
		return
	if enemy.is_dead():
		_on_melee_kill(enemy, player, ev)
		return
	if swing == null:
		return
	if ev.has("spin") and ev["spin"].has("pull"):
		var toward: Vector2 = enemy.global_position.direction_to(player.global_position)
		enemy.apply_knockback(toward * (ev["spin"]["pull"] + swing.knockback))
	if ev.has("shove"):
		var st: Dictionary = ev["shove"]
		if st["stun"] > 0.0:
			enemy.apply_slow(0.02, st["stun"])
		if st.has("mark"):
			mark(enemy, st["mark"], st["mark_secs"])
	if ev.has("lunge") and ev["lunge"].has("throw"):
		var away: Vector2 = player.global_position.direction_to(enemy.global_position)
		enemy.apply_knockback(away * ev["lunge"]["throw"])
		_thrown.append({"enemy": enemy, "until": _time + 0.4, "source": player,
			"amount": maxi(roundi(player.melee_damage * 0.5), 1), "done": {enemy.get_instance_id(): true}})


func _on_melee_kill(enemy: Node, player: Node, ev: Dictionary) -> void:
	if ev.has("lunge"):
		var st: Dictionary = ev["lunge"]
		if st.has("kill_rate"):
			_timed(player, "bayonet", {"fire_rate": _attr(st["kill_rate"])}, st["kill_secs"])
		if st.get("kill_reset", false):
			player.reset_melee_cooldown()
	if ev.has("spin") and ev["spin"].has("kill_drop"):
		game._drop_resources(enemy.global_position, int(ev["spin"]["kill_drop"]))


func _combo_hit(p: Node, st: Dictionary) -> void:
	var s: Dictionary = _st[p]
	s["combo"] = mini(s["combo"] + 1, int(st["max"])) if _time - s["combo_at"] <= st["window"] else 1
	s["combo_at"] = _time
	_set_boost(p, "combo", {"melee_damage": _attr(st["per"] * s["combo"])})


## Moves `player` `st.dist` along `facing`, through enemies (walls still
## stop them), and does whatever this lunge does to what it passes.
func _lunge(player: Node, st: Dictionary, facing: Vector2) -> void:
	var from: Vector2 = player.global_position
	var mask: int = player.collision_mask
	player.collision_mask &= ~PhysicsLayers.ENEMIES
	player.move_and_collide(facing * st["dist"])
	player.collision_mask = mask
	var to: Vector2 = player.global_position
	if st["guard"] > 0.0:
		player.extend_invulnerability(st["guard"])
	if st.has("next_shot"):
		_st[player]["lunge_bonus"] = true
	if st.has("heal_pass"):
		for p: Node2D in game.all_players:
			if p == player or p.is_dead() or not _near_segment(p.global_position, from, to, PATH_REACH + 6.0):
				continue
			if _time >= _stepped.get(p, -INF):
				_stepped[p] = _time + st["heal_pass"]
				p.heal(HEAL_AMOUNT)
				Visuals.ring(game, p.global_position, 12.0, TINTS["heal"])
	if st.has("stun") or st.has("mark"):
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			if e is BossBody or not e.has_method("take_damage"):
				continue
			var reach: float = PATH_REACH + (e.half_extent() if e.has_method("half_extent") else 8.0)
			if not _near_segment(e.global_position, from, to, reach):
				continue
			if st.has("stun"):
				e.apply_slow(0.02, st["stun"])
			if st.has("mark"):
				mark(e, st["mark"], st["mark_secs"])


## Dead-Eye III: a melee hit on a marked enemy does double and uses the mark up.
func _dead_eye(enemy: Node, amount: int) -> int:
	var id := enemy.get_instance_id()
	if not _marks.has(id):
		return amount
	_unmark(id)
	Visuals.ring(game, enemy.global_position, 12.0, TINTS["mark"])
	return amount * 2


## Whirlwind III: the spin hits again.
func _second_spin(player: Node, reach: float) -> void:
	if not is_instance_valid(player) or player.is_dead() or not game.is_wave_running():
		return
	_area(player.global_position, reach, player.melee_damage, player, 0.0, true)
	Visuals.ring(game, player.global_position, reach, TINTS["wave"])


## Torque III: our equipment within `reach` gets `secs` back (up to its full time).
func _top_up_equipment(player: Node, reach: float, secs: float) -> void:
	for d in get_tree().get_nodes_in_group("deployables"):
		if not d is Deployable or d.owner_player != player or d.duration <= 0.0:
			continue
		if d.global_position.distance_to(player.global_position) <= reach:
			d.add_time(secs)
			Visuals.ring(game, d.global_position, 10.0, TINTS["overclock"])


## Juggernaut III: thrown enemies hurt the enemies they hit.
func _tick_thrown() -> void:
	for i in range(_thrown.size() - 1, -1, -1):
		var t: Dictionary = _thrown[i]
		var e: Variant = t["enemy"]
		if not is_instance_valid(e) or e.is_dead() or _time >= t["until"]:
			_thrown.remove_at(i)
			continue
		var r: float = e.half_extent() if e.has_method("half_extent") else 8.0
		for other: Node2D in get_tree().get_nodes_in_group("enemies"):
			if t["done"].has(other.get_instance_id()) or other is BossBody or not other.has_method("take_damage"):
				continue
			var r2: float = other.half_extent() if other.has_method("half_extent") else 8.0
			if other.global_position.distance_to(e.global_position) <= r + r2:
				t["done"][other.get_instance_id()] = true
				BossBody.deal(other, t["amount"], t["source"] if is_instance_valid(t["source"]) else null,
					e.global_position.direction_to(other.global_position) * 20.0, other.global_position)


## Bulwark III: every enemy touching `p` takes melee damage x `share`.
func _thorns(p: Node, share: float) -> void:
	var amount := maxi(roundi(p.melee_damage * share), 1)
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if e is BossBody or not e.has_method("take_damage"):
			continue
		var r: float = e.half_extent() if e.has_method("half_extent") else 8.0
		if e.global_position.distance_to(p.global_position) <= r + 11.0:
			BossBody.deal(e, amount, p, Vector2.ZERO, e.global_position)


## `amount` damage (and a `stun`) to every enemy within `radius` of `at`.
## With `melee`, each hit counts as `source`'s melee hit (Combo, Bulwark).
func _area(at: Vector2, radius: float, amount: int, source: Node, stun := 0.0, melee := false) -> void:
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not e.has_method("take_damage"):
			continue
		var reach: float = radius + (e.half_extent() if e.has_method("half_extent") else 8.0)
		if e.global_position.distance_to(at) > reach:
			continue
		BossBody.deal(e, maxi(amount, 1), source, Vector2.ZERO, at)
		if stun > 0.0 and not e is BossBody and e.has_method("apply_slow"):
			e.apply_slow(0.02, stun)
		if melee:
			_on_melee_hit(e, source, null)


# --- Blocks, kills, pickups ---------------------------------------------------------

## Player.hit_filter: true blocks the hit (a Triage shield, or a Riposte).
func _filter_hit(_amount: int, _at: Vector2, player: Node) -> bool:
	if _shields.has(player):
		_shields.erase(player)
		Visuals.ring(game, player.global_position, 12.0, TINTS["heal"])
		return true
	var ev := ClassMod.mechanics(player)
	if not ev.has("riposte"):
		return false
	var st: Dictionary = ev["riposte"]
	var s: Dictionary = _st[player]
	if _time - s["swing_at"] > st["window"]:
		return false
	Visuals.ring(game, player.global_position, RIPOSTE_REACH, Color(1, 1, 1))
	if st["counter"] > 0.0:
		var best: Node2D = null
		var best_d := RIPOSTE_REACH * RIPOSTE_REACH
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			var d := e.global_position.distance_squared_to(player.global_position)
			if d < best_d and e.has_method("take_damage"):
				best_d = d
				best = e
		if best:
			BossBody.deal(best, maxi(roundi(player.melee_damage * st["counter"]), 1), player,
				player.global_position.direction_to(best.global_position) * 16.0, player.global_position)
	if st.has("stun"):
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			if not e is BossBody and e.has_method("apply_slow") \
					and e.global_position.distance_to(player.global_position) <= RIPOSTE_REACH:
				e.apply_slow(0.02, st["stun"])
	if st.get("next_double", false):
		s["next_double"] = true
	return true


## GameBase: one of our own enemies died (not to another squad).
## `killer` is our player who finished it, or null.
func on_enemy_died(killer: Node, at: Vector2, enemy: Node) -> void:
	var id := enemy.get_instance_id()
	if _marks.has(id):
		var m: Dictionary = _marks[id]
		_unmark(id)
		if m["spread"] > 0.0:
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				if e != enemy and not e is BossBody and e.global_position.distance_to(at) <= m["spread"]:
					mark(e, m["mult"], 3.0, m["spread"], m["drop"])
		if m["drop"] > 0:
			game._drop_resources(at, m["drop"])
	_shred.erase(id)
	_suppress.erase(id)
	if not is_instance_valid(killer) or not _st.has(killer):
		return
	var ev := ClassMod.mechanics(killer)
	var s: Dictionary = _st[killer]
	if ev.has("salvage") and randf() < ev["salvage"]["chance"]:
		game._drop_resources(at, 1)
	if ev.has("recycler"):
		var st: Dictionary = ev["recycler"]
		s["kills"] += 1
		if s["kills"] % int(st["kills"]) == 0:
			killer.heal(HEAL_AMOUNT)
			Visuals.ring(game, killer.global_position, 12.0, TINTS["recycler"])
			if st.has("guard"):
				killer.extend_invulnerability(st["guard"])
	if ev.has("hitrun"):
		var st: Dictionary = ev["hitrun"]
		s["hitrun"] = mini(s["hitrun"] + 1, int(st["stacks"]))
		_timed(killer, "hitrun", {"speed": _attr(st["speed"] * s["hitrun"], "speed")}, st["secs"])
		if st.get("shield", false):
			killer.set_contact_shield(_boost_key(killer, "hitrun_shield"), true)
	if ev.has("overclock") and ev["overclock"].has("kill_extend"):
		for d: Node2D in get_tree().get_nodes_in_group("deployables"):
			if d.get("owner_player") == killer and float(d.get("duration")) > 0.0:
				d.duration += ev["overclock"]["kill_extend"]


## Salvage III: picking up resources speeds the gun up for a moment.
## Campaign: the tide swallowed `count` of our pickups (braid_tide.gd).
## Each of our players with Salvage III collects them, scaled by their
## harvesting like any pickup, knocked out or not (like the squad's shared
## copies); nobody else gets a copy.
func on_tide_pickups(count: int) -> void:
	for p: Node in _st:
		if not is_instance_valid(p):
			continue
		var st: Dictionary = ClassMod.mechanics(p).get("salvage", {})
		if st.get("tide", false):
			p.harvest(count)
			Visuals.ring(game, p.global_position, 12.0, TINTS["salvage"])


# --- What Class Mods leave behind ---------------------------------------------------

## Marks `enemy`: it takes x `mult` damage for `secs`. A marked enemy that
## dies passes its mark on to enemies within `spread` px, and drops `drop`
## extra resources. Another squad's enemy (a mirror) is marked in its own
## game: we tell that squad (just the multiplier and time).
func mark(enemy: Node, mult: float, secs: float, spread := 0.0, drop := 0) -> void:
	if enemy.get("is_mirror"):
		if game.link and game.link.has_method("send_mark"):
			game.link.send_mark(enemy, mult, secs)
		return
	if not "damage_taken_multiplier" in enemy or enemy.is_dead():
		return
	var id := enemy.get_instance_id()
	var m: Dictionary = _marks.get(id, {"enemy": enemy, "until": 0.0, "reticle": null,
		"mult": 1.0, "spread": 0.0, "drop": 0})
	m["mult"] = maxf(m["mult"], mult)
	m["until"] = maxf(m["until"], _time + secs)
	m["spread"] = maxf(m["spread"], spread)
	m["drop"] = maxi(m["drop"], drop)
	if not is_instance_valid(m["reticle"]):
		m["reticle"] = Reticle.new()
		enemy.add_child(m["reticle"])
	_marks[id] = m
	_refresh_taken(enemy)


func _unmark(id: int) -> void:
	var m: Dictionary = _marks.get(id, {})
	_marks.erase(id)
	if m.is_empty():
		return
	if is_instance_valid(m["reticle"]):
		m["reticle"].queue_free()
	if is_instance_valid(m["enemy"]):
		_refresh_taken(m["enemy"])


## An enemy's damage multiplier: its mark times its shred.
func _refresh_taken(enemy: Node) -> void:
	var id := enemy.get_instance_id()
	var mult := 1.0
	if _marks.has(id):
		mult *= _marks[id]["mult"]
	if _shred.has(id):
		mult *= 1.0 + _shred[id]["per"] * _shred[id]["stacks"]
	enemy.damage_taken_multiplier = mult


## Poisons (or burns, or bleeds: `kind`) `enemy`: `dps` damage a second for
## `secs`, credited to `source`. When it dies, enemies within `spread` px
## catch it, with `heals` the nearest player in our squad gets half a heart,
## and with `explode` > 0 it bursts that wide. With `max_stacks` > 1 each
## new dose adds another `dps` (up to that many) and refreshes the timer;
## otherwise it only refreshes the timer and keeps the stronger dps.
func poison(enemy: Node, dps: float, secs: float, spread: float, source: Node, heals := false,
		kind := "toxin", explode := 0.0, max_stacks := 1) -> void:
	for child in enemy.get_children():
		if child is Dot and child.kind == kind:
			child.left = maxf(child.left, secs)
			child.per_stack = maxf(child.per_stack, dps)
			child.max_stacks = maxi(child.max_stacks, max_stacks)
			child.stacks = mini(child.stacks + 1, child.max_stacks)
			child.dps = child.per_stack * child.stacks
			return
	var d := Dot.new()
	d.kind = kind
	d.dps = dps
	d.per_stack = dps
	d.max_stacks = max_stacks
	d.left = secs
	d.spread = spread
	d.heals = heals
	d.explode = explode
	d.source = source
	d.fx = self
	enemy.add_child(d)


## Toxin III: half a heart to the player in our squad nearest `at` (at most
## once a second for each).
func heal_nearest(at: Vector2) -> void:
	var best: Node2D = null
	var best_d := INF
	for p: Node2D in game.all_players:
		var d := p.global_position.distance_squared_to(at)
		if not p.is_dead() and d < best_d:
			best_d = d
			best = p
	if best and _time >= _healed.get(best, -INF):
		_healed[best] = _time + HEAL_COOLDOWN
		best.heal(HEAL_AMOUNT)
		Visuals.ring(game, best.global_position, 12.0, TINTS["heal"])


## A spike trap at `at` for `secs`, hurting enemies that touch it. Each
## shooter has at most their stage's number (the oldest goes).
func add_spike(shooter: Node, at: Vector2, secs: float, damage: int) -> void:
	if not is_instance_valid(shooter) or not game.is_wave_running():
		return
	var st: Dictionary = ClassMod.mechanics(shooter).get("nail", {})
	var cap := int(st.get("max", 8))
	var list: Array = _spikes.get(shooter.get_instance_id(), [])
	list = list.filter(func(s) -> bool: return is_instance_valid(s))
	while list.size() >= cap:
		list.pop_front().queue_free()
	var spike := Spike.new()
	spike.left = secs
	spike.damage = maxi(roundi(damage * SPIKE_DAMAGE), 1)
	spike.slow = st.get("slow", 1.0)
	spike.source = shooter
	spike.position = at
	game.add_child(spike)
	list.append(spike)
	_spikes[shooter.get_instance_id()] = list


## A burning line (from `a` to `b`) or, with a == b, a puddle, `radius` wide,
## hurting enemies on it `damage` every Hazard.TICK for `secs`.
func add_hazard(a: Vector2, b: Vector2, radius: float, secs: float, damage: int, source: Node,
		color: Color) -> void:
	if not game.is_wave_running():
		return
	var h := Hazard.new()
	h.position = a
	h.to = b - a
	h.radius = radius
	h.left = secs
	h.damage = damage
	h.source = source
	h.color = color
	game.add_child(h)
	_hazards = _hazards.filter(func(x) -> bool: return is_instance_valid(x))
	_hazards.append(h)


## Underbarrel III: `count` small bursts scattered round `at`, one after another.
func bomblets(at: Vector2, count: int, damage: int, source: Node) -> void:
	for k in count:
		var timer := get_tree().create_timer(0.12 * (k + 1), false, true)
		var spot := at + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 24.0)
		timer.timeout.connect(func() -> void:
			if not game.is_wave_running():
				return
			_area(spot, 14.0, damage, source if is_instance_valid(source) else null)
			Blast.spawn(game, spot, 14.0))


## A Triage or Stim shot moving from -> to: heals, boosts or revives the
## players it passes.
func ally_along(shot: Node, from: Vector2, to: Vector2) -> void:
	var reach := 16.0
	var shooter: Node = shot.shooter
	var ev := ClassMod.mechanics(shooter) if is_instance_valid(shooter) else {}
	for p: Node2D in game.all_players:
		if p == shooter or not _near_segment(p.global_position, from, to, reach):
			continue
		if p.is_dead():
			if ev.has("stim") and ev["stim"].has("revive_hits") and not shot.allies_passed.has(p):
				shot.allies_passed[p] = true
				_revive_hits[p] = int(_revive_hits.get(p, 0)) + 1
				Visuals.ring(game, p.global_position, 8.0, TINTS["stim"])
				if _revive_hits[p] >= int(ev["stim"]["revive_hits"]) and not get_tree().get_nodes_in_group("players").is_empty():
					_revive_hits.erase(p)
					p.revive()
					Visuals.ring(game, p.global_position, 18.0, TINTS["heal"])
			continue
		if shot.heal and _time >= _healed.get(p, -INF):
			_healed[p] = _time + HEAL_COOLDOWN
			if p.health >= p.max_health:
				if ev.has("heal") and ev["heal"].get("shield", false):
					_shields[p] = true
			else:
				p.heal(HEAL_AMOUNT)
			Visuals.ring(game, p.global_position, 12.0, TINTS["heal"])
		if shot.stim and ev.has("stim") and not shot.allies_passed.has(p):
			shot.allies_passed[p] = true
			var boost: float = ev["stim"]["boost"]
			_timed(p, "stim", {"speed": _attr(boost, "speed"), "fire_rate": _attr(boost)},
					ev["stim"]["secs"])
	if shot.heal and shot.heal_remote and game.link and game.link.has_method("remote_player_keys"):
		for key in game.link.remote_player_keys():
			var proxy: Node2D = game.link.remote_player(key)
			if proxy and proxy.is_alive() and _near_segment(proxy.position, from, to, reach):
				var tag := str(key)
				if _time >= _healed.get(tag, -INF):
					_healed[tag] = _time + HEAL_COOLDOWN
					game.link.send_heal(key >> 4, key & 15, HEAL_AMOUNT)
					Visuals.ring(game, proxy.position, 12.0, TINTS["heal"])


static func _near_segment(p: Vector2, a: Vector2, b: Vector2, r: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= r


## The segment is over: what Class Mods left in the field goes (it's
## cleared anyway), and every running boost stops so the shop shows plain
## stats.
func clear() -> void:
	for id in _marks.keys():
		_unmark(id)
	for id in _shred.keys():
		var e: Variant = _shred[id]["enemy"]
		_shred.erase(id)
		if is_instance_valid(e):
			_refresh_taken(e)
	_suppress.clear()
	_shoved.clear()
	_thrown.clear()
	_revive_hits.clear()
	for list in _spikes.values():
		for s in list:
			if is_instance_valid(s):
				s.queue_free()
	_spikes.clear()
	for h in _hazards:
		if is_instance_valid(h):
			h.queue_free()
	_hazards.clear()
	for key in _boosts:
		var entry: Dictionary = _boosts[key]
		if is_instance_valid(entry["player"]) and not entry["effects"].is_empty():
			entry["effects"] = {}
			entry["player"].remove_boost(entry["key"])
	for player in _st.keys():
		if not is_instance_valid(player):
			continue
		player.set_contact_shield(_boost_key(player, "hitrun_shield"), false)
		var fresh := _new_state(player)
		fresh["shots"] = _st[player]["shots"]
		fresh["kills"] = _st[player]["kills"]
		fresh["swings"] = _st[player]["swings"]
		_st[player] = fresh


## Each aiming player's Laser Sight beam (brighter, with a dot, while it's
## on an enemy), and a ring round shielded players.
func _draw() -> void:
	for p in _st:
		if not is_instance_valid(p) or p.is_dead():
			continue
		var at := to_local(p.global_position)
		var s: Dictionary = _st[p]
		var beam: Array = s["laser"]
		if not beam.is_empty():
			var c: Color = TINTS["laser"]
			c.a = 0.85 if beam[2] else 0.35
			draw_line(to_local(beam[0]), to_local(beam[1]), c, 1.0)
			if beam[2]:
				draw_circle(to_local(beam[1]), 1.5, c)
		if _shields.has(p):
			draw_arc(at, 11.0, 0.0, TAU, 20, Color(TINTS["heal"], 0.8), 1.0)


## A marked enemy's reticle.
class Reticle extends Node2D:
	var _t := 0.0

	func _ready() -> void:
		z_index = 15

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := 11.0 + sin(_t * 8.0)
		var c := Color(1.0, 0.35, 0.35, 0.9)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, c, 1.0)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2.0)
			draw_line(d * (r - 3.0), d * (r + 3.0), c, 1.0)


## Poison, fire or bleeding on an enemy (a child of it).
class Dot extends Node2D:
	const COLORS := {"toxin": Color(0.6, 1.0, 0.2, 0.8), "burn": Color(1.0, 0.5, 0.15, 0.9),
		"bleed": Color(0.85, 0.1, 0.15, 0.85)}
	var kind := "toxin"
	## Total damage a second: per_stack x stacks.
	var dps := 1.0
	var per_stack := 1.0
	var stacks := 1
	var max_stacks := 1
	var left := 3.0
	var spread := 0.0
	var heals := false
	var explode := 0.0
	var source: Node
	var fx: Node
	var _tick := 0.0
	var _owed := 0.0

	func _ready() -> void:
		var host := get_parent()
		if (spread > 0.0 or heals or explode > 0.0) and host.has_signal("died"):
			host.died.connect(_on_host_died, CONNECT_ONE_SHOT)

	func _physics_process(delta: float) -> void:
		left -= delta
		_owed += dps * delta
		_tick += delta
		if _tick >= 0.5 and _owed >= 1.0:
			_tick = 0.0
			var host := get_parent()
			var amount := floori(_owed)
			_owed -= amount
			if host.has_method("take_damage") and not host.is_dead():
				host.take_damage(amount, source if is_instance_valid(source) else null)
		queue_redraw()
		if left <= 0.0:
			queue_free()

	func _on_host_died(_killer: Node, at: Vector2) -> void:
		if not is_instance_valid(fx):
			return
		var src: Node = source if is_instance_valid(source) else null
		if spread > 0.0:
			for e: Node2D in fx.get_tree().get_nodes_in_group("enemies"):
				if e != get_parent() and not e is BossBody and e.global_position.distance_to(at) <= spread:
					fx.poison(e, dps, maxf(left, 2.0), spread, src, heals, kind, explode)
		if heals:
			fx.heal_nearest(at)
		if explode > 0.0:
			fx.call_deferred("_area", at, explode, maxi(roundi(dps * 3.0), 1), src)
			Blast.spawn(fx.game, at, explode)

	func _draw() -> void:
		var c: Color = COLORS.get(kind, Color.WHITE)
		var n := maxi(stacks, 3)
		for k in n:
			var a := Time.get_ticks_msec() / 300.0 + k * TAU / n
			draw_circle(Vector2.from_angle(a) * 7.0, 1.5, c)


## A spike trap left by a Nailer rivet.
class Spike extends Node2D:
	var left := 5.0
	var damage := 1
	## x speed for enemies on it (1 = no slow).
	var slow := 1.0
	var source: Node
	var _tick := 0.0

	func _ready() -> void:
		z_index = -8
		add_to_group("deployables")

	func _physics_process(delta: float) -> void:
		left -= delta
		_tick -= delta
		if _tick <= 0.0:
			_tick = SPIKE_TICK
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				if e is BossBody or not e.has_method("take_damage"):
					continue
				var reach: float = SPIKE_RADIUS + (e.half_extent() if e.has_method("half_extent") else 8.0)
				if e.global_position.distance_to(global_position) <= reach:
					e.take_damage(damage, source if is_instance_valid(source) else null)
					if slow < 1.0 and is_instance_valid(e) and not e.is_dead():
						e.apply_slow(slow, SPIKE_TICK + 0.1)
		if left <= 0.0:
			queue_free()

	func _draw() -> void:
		var c := Color(0.75, 0.75, 0.8)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2.0 + PI / 4.0)
			draw_line(Vector2.ZERO, d * 5.0, c, 1.0)
		draw_circle(Vector2.ZERO, 1.5, Color(0.4, 0.4, 0.45))


## A burning line (Rail III) or a corrosive puddle (Mortar III): hurts
## enemies on it every TICK.
class Hazard extends Node2D:
	const TICK := 0.4
	## The far end, relative to the start (zero for a puddle).
	var to := Vector2.ZERO
	var radius := 6.0
	var left := 3.0
	var damage := 1
	var source: Node
	var color := Color.WHITE
	var _life := 3.0
	var _tick := 0.0

	func _ready() -> void:
		z_index = -7
		_life = left

	func _physics_process(delta: float) -> void:
		left -= delta
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			var a := global_position
			var b := global_position + to
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				if e is BossBody or not e.has_method("take_damage"):
					continue
				var reach: float = radius + (e.half_extent() if e.has_method("half_extent") else 8.0)
				if Geometry2D.get_closest_point_to_segment(e.global_position, a, b).distance_to(e.global_position) <= reach:
					e.take_damage(damage, source if is_instance_valid(source) else null)
		queue_redraw()
		if left <= 0.0:
			queue_free()

	func _draw() -> void:
		var c := Color(color, 0.45 * clampf(left / _life, 0.0, 1.0) + 0.1)
		if to == Vector2.ZERO:
			draw_circle(Vector2.ZERO, radius, c)
		else:
			draw_line(Vector2.ZERO, to, c, radius * 2.0)
